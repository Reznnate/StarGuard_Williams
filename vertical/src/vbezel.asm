; The vertical build's bezel. The normal build's bands above and below the window are the board's color 0 for each line
; (Bezel_On, Bezel_Tick); turned, those lines run across the window, so here the bands are pixels, in the columns either side
; of it, in pens 10 to 15 (gen_assets.py --vertical gives them their colors). Band 0 is the red line next to the window, as
; there. The rest start VBZ_SKIP pixels further out, past anything that may cross the window's edge: no image is wider than 7
; bytes and a black cover is one wider, so the covers and the erasing of what crosses the edge reach only band 0,
; which is drawn again after them. Drawn on a level's first tick, on a clear screen; any screen clears it again (Screen_Clear clears vbz_on). The screens show none: they use the whole monitor.
vbz_on      equ bz_save         ; nonzero while the bezel is on the screen
VBZ_N       equ 67              ; bands, as bz_band
VBZ_LN0     equ 7               ; the lines the monitor shows
VBZ_LNS     equ 240
VBZ_PXL     equ VIEW_COL0*2-1   ; band 0, left: the pixel next to the window. Band k is k pixels further out
VBZ_PXR     equ (VIEW_COL0+VIEW_COLS)*2
VBZ_SKIP    equ 15              ; band 1 on, as much further out again: band 1 is 8 byte columns from the window
            assert VBZ_PXL-VBZ_SKIP-1<=(VIEW_COL0-8)*2+1,"band 1 within reach of what crosses the window's edge"
            assert VBZ_PXR+VBZ_SKIP+1>=(VIEW_COL0+VIEW_COLS+8)*2,"band 1 within reach of what crosses the window's edge"
            assert VBZ_PXL-VBZ_SKIP-(VBZ_N-1)>=6,"the bands run off the left of what the monitor shows"
            assert VBZ_PXR+VBZ_SKIP+VBZ_N-1<=297,"the bands run off the right of what the monitor shows"

; Once a tick after Present, in a level. The bands are still: from the window out they fade from pen 10 to pen 15, dark red to
; amber, so after the first tick only band 0 is ever drawn again. No rails across the window's ends: the bands frame it.
vbz_tick    tst vbz_on
            beq vbz_draw
            ; Band 0 where black covers have been, this tick or the last, whose covers are erased this tick. Every 32 ticks all
            ; of it: an image in the still layer is erased whenever it goes, with no cover then.
.mend       lda <now+1
            anda #31
            beq .whole
            lda vbz_clo
            cmpa vbz_plo
            bls .lo
            lda vbz_plo
.lo         cmpa #VBZ_LN0
            bhs .lo_ok
            lda #VBZ_LN0
.lo_ok      ldb vbz_chi
            cmpb vbz_phi
            bhs .hi
            ldb vbz_phi
.hi         cmpb #VBZ_LN0+VBZ_LNS
            bls .hi_ok
            ldb #VBZ_LN0+VBZ_LNS
.hi_ok      sta vbz_l0
            pshs a
            subb ,s+
            bls .aged           ; no lines
            stb vbz_ln
            bra .band0
.whole      jsr vbz_all
.band0      ldb #0
            lda vbz_pen
            lbsr vbz_band
.aged       ldd vbz_clo         ; this tick's covers become last tick's
            std vbz_plo
            ldd #$FF00
            std vbz_clo
            rts

; Every band.
vbz_draw    jsr vbz_all
            ldb #VBZ_N-1
.next       pshs b
            ldx #vbz_pen
            lda b,x
            lbsr vbz_band
            puls b
            decb
            bpl .next
            lda #1
            sta vbz_on
            ldd #$FF00          ; no covers yet
            std vbz_clo
            std vbz_plo
            rts

; vbz_px's lines: all the monitor shows.
vbz_all     ldd #VBZ_LN0*256+VBZ_LNS
            std vbz_l0
            rts

; B=band, A=its pen in both nibbles: draws it both sides of the window.
vbz_band    pshs a
            clra
            tstb
            beq .zero
            addd #VBZ_SKIP
.zero       pshs d
            ldd #VBZ_PXR
            addd ,s
            tfr d,x
            lda 2,s
            bsr vbz_px
            ldd #VBZ_PXL
            subd ,s++
            tfr d,x
            puls a
; X=pixel column, A=its pen in both nibbles: that one pixel on the lines in vbz_l0 and vbz_ln.
vbz_px      sta BLIT_SOLID
            tfr x,d
            lsra
            rorb                ; B=byte column, carry=the odd pixel
            lda #BC_SOLID+BC_DST256+BC_NO_ODD
            bcc .even
            lda #BC_SOLID+BC_DST256+BC_NO_EVEN
.even       pshs a
            tfr b,a
            ldb vbz_l0
            std BLIT_DST
            lda #1
            ldb vbz_ln
            std BLIT_W
            puls a
            sta BLIT_CTRL
            clr BLIT_SOLID
            rts

; Each band's pen: band 0 the game's red (pen 1), then pens 10 to 15 from the window out, neighbouring pens mixed where
; they meet so that the fade has no hard steps.
vbz_pen     fcb $11,$AA,$AA,$AA,$AA,$BB,$AA,$BB,$AA,$BB,$AA,$BB,$BB,$BB,$BB,$BB
            fcb $BB,$BB,$CC,$BB,$CC,$BB,$CC,$BB,$CC,$CC,$CC,$CC,$CC,$CC,$CC,$DD
            fcb $CC,$DD,$CC,$DD,$CC,$DD,$DD,$DD,$DD,$DD,$DD,$DD,$EE,$DD,$EE,$DD
            fcb $EE,$DD,$EE,$EE,$EE,$EE,$EE,$EE,$EE,$FF,$EE,$FF,$EE,$FF,$EE,$FF
            fcb $FF,$FF,$FF
            assert *-vbz_pen==VBZ_N,"a pen for every band"

; In a level, once a tick after Present: vbz_tick, unless it has nothing to do, as on most ticks. Called with FAR (bank 6).
vbz_quick   lda sc_pia          ; Advance pressed or let go, or the SCROLL hotkey's note showing: sc_hotkey
            anda #IN2_ADVANCE
            cmpa sc_adv
            bne .hot
            tst sc_note
            beq .bz
.hot        jsr sc_hotkey
.bz         lda CM_BEZEL
            anda #$0F
            cmpa #ST_OFF
            beq .out            ; turned off in the settings
            tst vbz_on
            beq .far            ; to be drawn
            lda <now+1
            bita #31
            beq .far            ; band 0 is drawn whole
            lda vbz_clo
            anda vbz_plo
            inca
            bne .far            ; a cover beside the window, this tick or the last
.out        rts
.far        jmp vbz_tick

; Game_Reset (game.asm), here in bank 6 in the vertical build, for room in the fixed ROM: Level_Run calls it with FAR, and
; the screens, in this bank, as before.
Game_Reset  ldx #ent_pool
            stx ent_hi
            stx ent_ask_at
            ldx #0
            stx ban_fresh
            ldx #ent_pool
            ldx #laser_pool
            stx laser_hi
            ldx #ent_pool
            ldd #CLASS_END-ent_pool
            jsr mem_clear
            ldx #laser_pool
            ldd #LASER_SIZE*LASER_COUNT
            jsr mem_clear
            jsr Effect_ClearAll
            FAR MessageTrigger_Initialize
            jsr MessageBanner_ClearBanners
            ldd #dl_a
            std <dl_new
            std <dl_newp
            addd #DL_ROOM*DL_SIZE
            std <dl_limit
            ldd #dl_b
            std <dl_old
            std <dl_oldend
            clr <terrain_on
            clr <terrain_dirty
            clr <target_n
            clr <target_m
            clr wiz_live
            clr queue_on
            clr tl_valid
            clr tl_wait
            ldx #reg_ram        ; no region is marked or looks other than as the level began
            ldb #REG_BYTES
.regs       clr ,x+
            decb
            bne .regs
            clr <repair_rect
            clr <repair_rect+1
            clr <cam_fixed
            clr <death_cam
            clr <man_lock
            clr <level_done
            jmp Screen_Clear
