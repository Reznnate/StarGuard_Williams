; The vertical build's bezel. The normal build's bands above and below the window are the board's color 0 for each line
; (Bezel_On, Bezel_Tick); turned, those lines run across the window, so here the bands are pixels, in the columns either side
; of it, in pens 10 to 15 (gen_assets.py --vertical gives them their colors). Band 0 is the red line next to the window, as
; there. The rest start VBZ_SKIP pixels further out, past anything that may cross the window's edge: no image is wider than 7
; bytes and a black cover is one wider, so the covers and the erasing of what crosses the edge reach only band 0 and the
; rails, which are drawn again after them as the normal build's rails are (bz_dirty). Drawn on a level's first tick, on a
; clear screen; any screen clears it again (Screen_Clear clears vbz_on). The screens show none: they use the whole monitor.
vbz_k       equ bz_line         ; the band the light is on
vbz_on      equ bz_save         ; nonzero while the bezel is on the screen
VBZ_N       equ 67              ; bands, as bz_band
VBZ_LN0     equ 7               ; the lines the monitor shows
VBZ_LNS     equ 240
VBZ_PXL     equ VIEW_COL0*2-1   ; band 0, left: the pixel next to the window. Band k is k pixels further out
VBZ_PXR     equ (VIEW_COL0+VIEW_COLS)*2
VBZ_SKIP    equ 15              ; band 1 on, as much further out again: band 1 is 8 byte columns from the window
VBZ_LIGHT   equ $FF             ; pen 15: the light that runs out from the window, amber
            assert VBZ_PXL-VBZ_SKIP-1<=(VIEW_COL0-8)*2+1,"band 1 within reach of what crosses the window's edge"
            assert VBZ_PXR+VBZ_SKIP+1>=(VIEW_COL0+VIEW_COLS+8)*2,"band 1 within reach of what crosses the window's edge"
            assert VBZ_PXL-VBZ_SKIP-(VBZ_N-1)>=6,"the bands run off the left of what the monitor shows"
            assert VBZ_PXR+VBZ_SKIP+VBZ_N-1<=297,"the bands run off the right of what the monitor shows"

; Once a tick after Present, in a level. The light moves two bands out every fourth tick: as fast as the normal build's, which
; moves one every other tick, at half the cost, each move being four blits the height of the screen.
vbz_tick    tst vbz_on
            beq vbz_draw
            lda <now+1
            anda #3
            bne .mend
            jsr vbz_all
            ldb vbz_k
            ldx #vbz_pen
            lda b,x
            lbsr vbz_band        ; the light's band gets its own color back
            ldb vbz_k
            addb #2
            cmpb #VBZ_N
            blo .keep
            ldb #1
.keep       stb vbz_k
            lda #VBZ_LIGHT
            lbsr vbz_band
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
            ; The rails, for two ticks after a cover.
            tst bz_dirty
            beq .out
            dec bz_dirty
            bra vbz_rails
.out        rts

; Every band, and the rails.
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
            sta vbz_k
            ldd #$FF00          ; no covers yet
            std vbz_clo
            std vbz_plo
; The rails across the window's ends: two lines each, as the normal build's are two pixels wide.
vbz_rails   lda #$11
            sta BLIT_SOLID
            ldd #(VIEW_COL0-1)*256+VIEW_ROW0-2
            std BLIT_DST
            ldd #(VIEW_COLS+2)*256+2
            std BLIT_W
            lda #BC_SOLID+BC_DST256
            sta BLIT_CTRL
            ldd #(VIEW_COL0-1)*256+VIEW_BOTTOM
            std BLIT_DST
            lda #BC_SOLID+BC_DST256
            sta BLIT_CTRL
            clr BLIT_SOLID
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

; Each band's pen, from bz_band's colors: 01 pen 10, 02 pen 11, 03 pen 12, 04 to 06 pen 13 (05), 07 pen 1 (the game's red),
; 0F to 1F pen 14 (17). Pen 15 is the light. Seven pens for the normal build's ten shades: those were all that were free.
vbz_pen     fcb $11,$00,$BB,$CC,$BB,$BB,$CC,$BB,$BB,$BB,$DD,$AA,$AA,$AA,$AA,$DD
            fcb $AA,$AA,$AA,$AA,$AA,$DD,$00,$00,$00,$00,$00,$00,$DD,$00,$00,$00
            fcb $00,$00,$00,$00,$11,$00,$00,$00,$00,$00,$00,$00,$00,$EE,$00,$00
            fcb $00,$00,$00,$00,$00,$00,$00,$EE,$00,$00,$00,$00,$00,$00,$00,$00
            fcb $00,$00,$EE
            assert *-vbz_pen==VBZ_N,"a pen for every band"
