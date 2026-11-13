; Boot, tick loop, input, display list, terrain, cells, camera, level loading. Fixed ROM.

; Cell types, as in the C port.
EMPTY       equ 0
PLATFORM    equ 1
PLATFORM_DESTRUCTIBLE equ 2
FLOATY_PLATFORM equ 3
LAVA        equ 4
LAVA2       equ 5
EXPLODING_PLATFORM equ 6
GOAL        equ 7
; Cell classes in the RAM map. Class 3 means "look at the ROM grid".
CLS_EMPTY   equ 0
CLS_PLATFORM equ 1
CLS_FLOATY  equ 2
CLS_SPECIAL equ 3

; The picture is a window of this size centered on the screen, with black around it. Everything else follows from these.
VIEW_COLS   equ 112         ; 224 pixels
VIEW_H      equ 108
VIEW_COL0   equ (152-VIEW_COLS)/2   ; first visible byte column
VIEW_ROW0   equ (256-VIEW_H)/2      ; first visible line
VIEW_BOTTOM equ VIEW_ROW0+VIEW_H    ; the first line below the picture
VIEW_HALF_W equ VIEW_COLS
VIEW_HALF_H equ VIEW_H/2
TAB_COLS    equ 146         ; the width of the baked table of floors, whatever the window's
SCR_COL0    equ 3           ; text on the title and other full screens is placed from here, not from the window
SCR_ROW0    equ 7
LOGIC_HALF_W equ 96         ; the original 192x108 view, used for gameplay checks
LOGIC_HALF_H equ 54
VIEW_DEAD_ZONE equ 28       ; lines cam_y can move before the view follows
VIEW_STEP_X equ $FE         ; the view moves in steps of 2 pixels and 4 lines. Coarser steps make the man jitter against
VIEW_STEP_Y equ $FC         ; the background, which reads as a double image
BEAM_MID    equ 128         ; the line that divides the screen for beam-timed drawing
Q_BIG       equ $BD00       ; the boss's RAM holds the blit queue on any level until a boss exists
Q_BIG_SIZE  equ 480
; The terrain list. Each half's walls grow up and its blocks grow down in the same room, since a room of blocks has few walls
; and open ground has no blocks. The floors of both halves share another room. The lower half's room is the same RAM as the
; big queue: only one is in use at a time. Other rects, from either half, follow that.
TL_BASE     equ tl_ram
TL_A_END    equ tl_ram+316
TLF_BASE    equ TL_A_END
TLF_END     equ tl_ram+TL_A_BYTES
TL_B_BASE   equ $BD00
TL_B_END    equ TL_B_BASE+358
TLO_BASE    equ TL_B_END
TLO_END     equ TLO_BASE+147
BK_END      equ tl_ram+TL_A_BYTES   ; queued blocks may use all of tl_ram when there is no list
Q_SMALL     equ $BE9C       ; the part of that RAM the boss does not use
Q_SMALL_SIZE equ 96
; Once a boss exists, the list keeps to tl_ram: rooms sized from every view of level 9 (14 of 45000 do not fit, and those
; take the way of vl_step until the list fits again). tl_rooms points at the rooms in use, as these offsets:
TR_A0       equ 0           ; upper half: walls from here
TR_A1       equ 2           ; and blocks back from here
TR_B0       equ 4           ; lower half the same
TR_B1       equ 6
TR_F0       equ 8           ; floors
TR_F1       equ 10
TR_O0       equ 12          ; others
TR_O1       equ 14
TLX_A       equ 170         ; the boss's rooms' sizes, together TL_A_BYTES (sized from every level 9 view: tools/tlfit.py)
TLX_F       equ 200

; ---- boot -----------------------------------------------------------------------------------
reset       orcc #$50
            lds #$BFFF
            lda #$98
            tfr a,dp
            ldx #$9700
.clr        clr ,x+
            cmpx #$BF00
            blo .clr
            lda #$FF
            sta COLOR0_TABLE    ; color 0 is pen(BB00 ^ FF), so this makes it black
            clr VIDEO_CTRL
            clr REMAP_SELECT
            ; PIA 0: inputs. CB2 low selects the stick and the button group.
            clr PIA0_CA
            clr PIA0_A
            lda #$04
            sta PIA0_CA
            clr PIA0_CB
            clr PIA0_B
            lda #$34
            sta PIA0_CB
            ; PIA 1: inputs with a rising CA1 interrupt on port A, sound command on port B.
            clr PIA1_CA
            clr PIA1_A
            lda #$07
            sta PIA1_CA
            clr PIA1_CB
            lda #$FF
            sta PIA1_B
            lda #$04
            sta PIA1_CB
            lda #$FF
            sta PIA1_B
            ; ROM view on, blits locked out of RAM.
            lda #$05
            sta ROM_SELECT
            clr BANK_SELECT
            jsr Screen_Clear
            FAR reset_rest      ; in a bank: the fixed bank is full
            andcc #$EF
            jmp game_start

hw_palette  HW_PALETTE

            include "div3_table.inc"

Screen_Clear
            lda #2
            sta bz_dirty        ; the bezel's rails have gone too
            clr BLIT_SOLID
            ldd #0
            std BLIT_DST
            ldd #152*256+255
            std BLIT_W
            lda #BC_SOLID+BC_DST256
            sta BLIT_CTRL
            ldd #$00FF
            std BLIT_DST
            ldd #152*256+1
            std BLIT_W
            lda #BC_SOLID+BC_DST256
            sta BLIT_CTRL
            rts

irq         lda PIA1_A          ; clears the interrupt flag
            inc <vphase
            ldx <frames
            leax 1,x
            stx <frames
            ; The sound board acts on the line leaving idle, and on nothing else. So a command is held for a frame and the line
            ; then goes idle for a frame, however long a game tick takes.
            tst snd_line
            bne .idle
            lda <snd_pending
            beq .out
            coma
            sta PIA1_B
            clr <snd_pending
            inc snd_line
            rti
.idle       lda #$FF
            sta PIA1_B
            clr snd_line
.out        rti

unused_vector rti

; ---- tick -----------------------------------------------------------------------------------
; Waits for the tick boundary, then does what happens once at the start of every tick.
GOV_CALM_T  equ 20
Tick_Begin  ldx #0
.wait       lda <vphase         ; 4
            cmpa #TICK_FRAMES   ; 2
            leax 1,x            ; 5
            blo .wait           ; 3
            stx <tick_spare
            suba #TICK_FRAMES
            beq .ontime
            ldx <late_ticks
            leax 1,x
            stx <late_ticks
            clr gov_calm
            lda gov_load
            cmpa #3
            bhs .govok
            inca
            bra .govset
.ontime     lda gov_calm
            inca
            sta gov_calm
            cmpa #GOV_CALM_T
            blo .govok
            clr gov_calm
            lda gov_load
            beq .govok
            deca
.govset     sta gov_load
            ldb #1
            tsta
            beq .govm
            ldb #3
.govm       stb gov_mask
.govok      clr <vphase
            lda #WATCHDOG_KEY
            sta WATCHDOG
            ldx <now
            leax 1,x
            stx <now
            ; falls through

; The stick reports 7 positions per axis: below 7 is left/up, 7 is center, above 7 is right/down.
Input_Read  lda PIA0_A
            tfr a,b
            lsra
            lsra
            lsra
            lsra
            bsr .axis
            sta <inp_dir
            tfr b,a
            anda #$0F
            bsr .axis
            sta <inp_ydir
            ldb PIA0_B
            bitb #BTN_ALTJUMP
            beq .noalt
            orb #BTN_JUMP
.noalt      andb #BTN_JUMP+BTN_FIRE+BTN_START1+BTN_START2
            lda <inp_buttons
            coma
            stb <inp_buttons
            anda <inp_buttons
            sta <inp_pressed
            rts
.axis       cmpa #7
            beq .center
            bhi .plus
            lda #-1
            rts
.plus       lda #1
            rts
.center     clra
            rts

; Returns B, 0-255. Preserves A, X, Y, U.
Random      pshs a
            ldd <rng
            lsra
            rorb
            bcc .nox
            eora #$B4
.nox        std <rng
            addb <frames+1
            puls a,pc

; D = value (non-negative). Returns D = value / 12. Preserves X, Y, U. Clobbers t3-t5. Flags are not meaningful.
; World positions are nearly always under 3072, which a table answers in about 40 cycles.
Div12       cmpa #$0C
            bhs div12_slow
            lsra
            rorb
            lsra
            rorb
            stx <t3
            ldx #div3_table
            ldb d,x
            clra
            ldx <t3
            rts
; value / 12 = (value / 4) / 3, and 85 / 256 is just under 1/3; the remainder then corrects the estimate.
div12_slow  std <t3             ; value
            lsra
            rorb
            lsra
            rorb
            std <t4             ; value / 4
            lda <t4+1
            ldb #85
            mul
            sta <t5+1
            lda <t4
            ldb #85
            mul
            addb <t5+1
            adca #0
            std <t5             ; estimated quotient
.fix        aslb                ; quotient * 12
            rola
            aslb
            rola
            std <t4
            aslb
            rola
            addd <t4
            std <t4
            ldd <t3
            subd <t4
            cmpd #12
            blo .done
            ldd <t5
            addd #1
            std <t5
            bra .fix
.done       ldd <t5
            rts

; ---- display list ---------------------------------------------------------------------------
; An entry is one blit: src(2) dst(2) w(1) h(1) ctrl(1) solid(1).

; D=sprite id, X=world x, Y=world y (top-left of the 12x12 cell).
; The most called routine in the game. It writes straight into the list entry, so an image that does not get that far costs
; only the tests. Code that may be filling the still layer calls Draw_SpriteAny.
; Goes to .edge unless the display list entry at X lies inside the window, as nearly all do.
DL_INSIDE   macro
            lda 2,x
            cmpa #VIEW_COL0
            blo .edge
            adda 4,x
            cmpa #VIEW_COL0+VIEW_COLS-1
            bhi .edge
            lda 3,x
            cmpa #VIEW_ROW0
            blo .edge
            adda 5,x
            cmpa #VIEW_BOTTOM
            bhi .edge
            endm

Draw_Sprite aslb                ; entry = id * 8 + table
            rola
            aslb
            rola
            aslb
            rola
            adda #sprite_table>>8
            assert (sprite_table&255)<1,"the sprite table starts a page"
            pshs u
            tfr d,u
            lda 2,u             ; width in bytes; 0 means a blank cell
            beq .out
            ; x on the 304-pixel video line: world + trim - camera + the 6 hidden pixels.
            tfr x,d
            addb 4,u
            adca #0
            subd <spr_ox
            ldx <dl_newp
            cmpx <dl_limit
            bhs .full
            lsra
            rorb                ; carry = odd pixel
            tsta                ; the hardware does not clip: skip anything leaving the 152 columns. Negative fails too
            bne .out            ; and past the last column, the width's test below fails
            stb 2,x             ; byte column
            lda #BC_DST256+BC_FG_ONLY
            bcc .even
            lda #BC_DST256+BC_FG_ONLY+BC_SHIFT
.even       sta 6,x
            cmpb #VIEW_COL0+VIEW_COLS
            bhs .out
            addb 2,u
            cmpb #VIEW_COL0
            bls .out
            ; Line. The hidden lines above the picture let a sprite crossing the top wrap harmlessly.
            tfr y,d
            addb 5,u
            adca #0
            subd <spr_oy
            tsta
            bne .out
            subb #12
            blo .out
            stb 3,x
            cmpb #VIEW_BOTTOM
            bhs .out
            addb 3,u
            cmpb #VIEW_ROW0
            bls .out
            ldd ,u
            std ,x
            ldd 2,u
            std 4,x
            clr 7,x
            DL_INSIDE
            leax DL_SIZE,x
            stx <dl_newp
.out        puls u,pc
.edge       jsr dl_edge
            puls u,pc
.full       ldx <dl_dropped
            leax 1,x
            stx <dl_dropped
            puls u,pc

; As Draw_Sprite, or into the still layer when still_mode is set.
Draw_SpriteAny
            tst <still_mode
            lbeq Draw_Sprite
            aslb
            rola
            aslb
            rola
            aslb
            rola
            addd #sprite_table
            pshs u
            tfr d,u
            lda 2,u
            beq .out
            clr <t5
            clr <t5+1
            jmp still_add
.out        puls u,pc

; As Draw_Sprite, filled with the palette color in draw_color: the C's ColoredSprite and FlashingSprite. Debris is mostly these.
Draw_ColoredSprite
            aslb
            rola
            aslb
            rola
            aslb
            rola
            adda #sprite_table>>8
            pshs u
            tfr d,u
            lda 2,u
            beq .out
            tst <still_mode
            bne .still
            tfr x,d
            addb 4,u
            adca #0
            subd <spr_ox
            ldx <dl_newp
            cmpx <dl_limit
            bhs .full
            lsra
            rorb
            tsta
            bne .out
            stb 2,x
            lda #BC_DST256+BC_FG_ONLY+BC_SOLID
            bcc .even
            lda #BC_DST256+BC_FG_ONLY+BC_SOLID+BC_SHIFT
.even       sta 6,x
            cmpb #VIEW_COL0+VIEW_COLS
            bhs .out
            addb 2,u
            cmpb #VIEW_COL0
            bls .out
            tfr y,d
            addb 5,u
            adca #0
            subd <spr_oy
            tsta
            bne .out
            subb #12
            blo .out
            stb 3,x
            cmpb #VIEW_BOTTOM
            bhs .out
            addb 3,u
            cmpb #VIEW_ROW0
            bls .out
            ldd ,u
            std ,x
            ldd 2,u
            std 4,x
            lda <draw_color
            ldb #$11
            mul
            stb 7,x
            DL_INSIDE
            leax DL_SIZE,x
            stx <dl_newp
.out        puls u,pc
.edge       jsr dl_edge
            puls u,pc
.full       ldx <dl_dropped
            leax 1,x
            stx <dl_dropped
            puls u,pc
.still      lda <draw_color
            ldb #$11
            mul
            stb <t5+1
            lda #BC_SOLID
            sta <t5
            jmp still_add

; A solid rectangle in screen space: A=byte column on the video line, B=line, t0=w,h, draw_color=color.
; Used by the HUD and by Draw_RectWorld.
Draw_RawRect
            ldx <dl_newp
            cmpx <dl_limit
            bhs .full
            std 2,x
            ldd #0
            std ,x
            ldd <t0
            std 4,x
            lda <draw_color
            ldb #$11
            mul
            stb 7,x
            lda #BC_SOLID+BC_DST256
            sta 6,x
            leax DL_SIZE,x
            stx <dl_newp
            rts
.full       ldx <dl_dropped
            leax 1,x
            stx <dl_dropped
            rts

; The walls are listed in order of column, so those in view lie together. Finds them, unless the view has not moved sideways since the last time.
vl_walls_find
            ldd <cam_col
            cmpd vl_wcol
            beq .out
            std vl_wcol
            ldu #VL_BASE
.lo         cmpu vl_w
            bhs .lo_end
            ldy ,u
            ldd ,y
            cmpd <cam_col
            bge .lo_end
            leau 2,u
            bra .lo
.lo_end     stu vl_wa
            ldd <cam_col
            addd #VIEW_COLS
            std <t2
.hi         cmpu vl_w
            bhs .hi_end
            ldy ,u
            ldd ,y
            cmpd <t2
            bge .hi_end
            leau 2,u
            bra .hi
.hi_end     stu vl_wz
.out        rts

; ---- present --------------------------------------------------------------------------------
; Brings the screen up to date with the new display list and the camera. It ends a tick's drawing.
Present     lda #WATCHDOG_KEY   ; a slow tick should slow the game, not reset the machine
            sta WATCHDOG
            ; A rectangle such as a beam is erased across solid rects, and the two ticks after it was drawn can heal that.
            lda tl_rect
            beq .norect
            clr tl_rect
            lda #3
            sta tl_rectw
            bra .rected
.norect     lda tl_rectw
            beq .rected
            dec tl_rectw
.rected     clr BANK_SELECT     ; sprite pixels
            ldd <cam_left
            cmpd <old_left
            bne .moved
            ldd <cam_top
            cmpd <old_top
            bne .moved
            tst <terrain_on
            beq .moved
            jsr pair_lists
            tst still_any
            beq .nostill
            tst still_work
            beq .heal
            clr BANK_SELECT
            clr still_band
            clra
            jsr still_pass
.heal       clr BANK_SELECT
            jsr still_repair
.nostill    tst <terrain_dirty
            bne .refresh
            jsr Terrain_Repair
            lbra .swap
.refresh    clr <terrain_dirty
            lda <level_bank
            sta BANK_SELECT
            jsr Terrain_Draw
            lbra .swap
.moved      clr tl_rep          ; solid rects are painted whole on every 4th step
            inc tl_step
            lda tl_rectw
            bne .whole
            lda tl_step
            anda #3
            bne .ends
.whole      inc tl_rep
.ends       lda <level_bank
            sta BANK_SELECT
            clr tl_mode
            ldd #tl_ram
            std blk_p
            ; Even a late tick waits for the beam: a moving view drawn while the beam crosses it shows blocks half drawn,
            ; which looks worse than the moment the wait costs. (q_nowait stays 0: kept to try the other way again.)
            clr q_nowait
            tst <terrain_on
            beq .noterrain
            ldd <cam_top
            cmpd <old_top
            bne .vertical
            tst vl_hold
            beq .sideways
            dec vl_hold
            bra .near
.sideways   jsr tl_prepare
            tst tl_mode
            lbne .queued
            bra .near
.scroll     jsr q_setup
            inc queue_on
            jsr Terrain_Scroll
            bra .tdone
.vertical   lda #VL_STEPS
            sta vl_hold
.near       jsr q_setup
            jsr vl_step
            tst vl_valid
            bne .tdone
            ; The rects near the view did not fit.
            clr tl_valid
            ldd <cam_top
            cmpd <old_top
            beq .scroll
            inc queue_on
            jsr Terrain_Move
.tdone      ldd <cam_top
            cmpd <old_top
            bne .torn           ; all the terrain in view has just been drawn again
            lda #REPAIR_MOVING*4
            jsr terrain_repair_n
.torn
            clr queue_on
            bra .queued
.noterrain  clr tl_valid
            jsr q_setup
            jsr Terrain_Draw
.queued     ldd <cam_col
            subd <old_col
            std still_dc
            ldd <cam_top
            subd <old_top
            std still_dr
            ldd <cam_left
            std <old_left
            ldd <cam_top
            std <old_top
            ldd <cam_col
            std <old_col
            lda #1
            sta <terrain_on
            clr BANK_SELECT
            ; Upper half, with the beam in the lower half.
            tst q_nowait
            bne .a_go
.a_wait     lda VCOUNT
            cmpa #BEAM_MID
            blo .a_wait
.a_go       tst still_any
            beq .a_nostill
            ldx still_dr
            bne .a_nostill      ; a vertical move does them all after the terrain
            tst still_work
            beq .a_scroll
            clr still_band      ; new and dying entries first, where the last drawn view had them
            clra
            jsr still_pass
.a_scroll   clra
            jsr still_scroll_erase
.a_nostill  tst tl_mode
            beq .a_queue
            jsr tl_upper
            bra .a_done
.a_queue    ldy q_base
            ldx qa_e
            jsr q_run
            ldy qa_d
            ldx q_mid
            jsr q_run
            clra
            jsr blk_run
.a_done
            tst still_any
            beq .a_nodraw
            ldx still_dr
            beq .a_side
            inc rem_dirty
            jsr rem_flush
            ; A vertical move can carry an image across the middle, so then they all go in this pass.
            clr still_band
            lda #1
            jsr still_pass
            bra .a_nodraw
.a_side     clra
            jsr still_scroll
.a_nodraw   clra
            jsr pair_lists_moved
            ; Lower half, with the beam in the upper half.
            tst q_nowait
            bne .b_go
            ; The beam below the picture has finished with the lower half for this frame, so that does as well as the top:
            ; waiting for it to come round wasted up to 78 lines, and left the lower half too little time before the beam
            ; was back (the boss's worm, just below the middle, was caught half drawn).
.b_wait     lda VCOUNT
            cmpa #BEAM_MID
            blo .b_go
            cmpa #VIEW_BOTTOM
            blo .b_wait
.b_go       tst still_any
            beq .b_nostill
            ldx still_dr
            bne .b_nostill
            lda #$80
            jsr still_scroll_erase
.b_nostill  tst tl_mode
            beq .b_queue
            jsr tl_lower
            bra .b_done
.b_queue    ldy q_mid
            ldx qb_e
            jsr q_run
            ldy qb_d
            ldx q_end
            jsr q_run
            lda #1
            jsr blk_run
.b_done
            tst still_any
            beq .b_nodraw
            ldx still_dr
            bne .b_nodraw
            lda #$80
            jsr still_scroll
.b_nodraw   lda #1
            jsr pair_lists_moved
            ; The list's upkeep draws nothing, so it waits until the images the beam is racing are done.
            tst tl_mode
            beq .swap
            jsr tl_trim
.swap       jsr still_fresh
            tst heal_n
            beq .noheal
            jsr block_heal_run
.noheal     tst reg_any
            beq .noreg
            jsr region_after
.noreg      tst beam_n
            beq .notops
            clr BANK_SELECT
            jsr beam_tops
.notops     lda <cur_bank
            sta BANK_SELECT
            inc dl_gen
            ldd <dl_newp        ; the list just drawn becomes the old one
            std <dl_oldend
            ldx <dl_new
            ldy <dl_old
            stx <dl_old
            sty <dl_new
            sty <dl_newp
            leay DL_ENTRIES*DL_SIZE,y
            sty <dl_limit
            rts

; Beam turrets whose beams are live: their images in the still layer, again, over the beam. Keeps U.
beam_tops   pshs u
            ldy #beam_list
.next       ldu ,y++
            ldx E_STILL,u
            bsr .one
            ldx BEAMT_S2,u
            bsr .one
            dec beam_n
            bne .next
            puls u,pc
.one        beq .out
            lda S_STATE,x
            anda #SS_SHOWN+SS_DIE
            cmpa #SS_SHOWN
            bne .out
            jmp still_draw
.out        rts

; The camera did not move, so unchanged entries cost nothing. All erases come before all draws: an entry leaving the list
; moves every later entry up one slot, and with erase and draw paired, each image would be drawn and then erased as the
; next slot's old image. An entry that left or joined is recognized, so what follows it, one slot off, is not redrawn.
; What is to be drawn is listed as it is found, in the old list's RAM behind where it is being read, so the draws need not
; look through the list again. Each guess that an entry left or joined is only a guess: whichever it is, the entries are
; then compared in full, so a wrong one costs blits and never a wrong picture.
pair_lists  pshs u
            ldx <dl_old
            ldu <dl_new
            ldy <dl_old
            ldd <dl_oldend
            subd #DL_SIZE
            std <t3             ; old[i+1] exists below this
            ldd <dl_newp
            subd #DL_SIZE
            std <t4             ; new[i+1] exists below this
            ; t1: steps until either list runs out. t2: new count - old count + entries left - entries joined, which says
            ; which list a step that takes from only one of them brings closer to its end.
            ldd <dl_oldend
            subd <dl_old
            bsr .count
            stb <t1
            ldd <dl_newp
            subd <dl_new
            bsr .count
            tfr b,a
            subb <t1
            stb <t2
            cmpa <t1
            bhs .min
            sta <t1
.min        tst <t1
            bne .f_next
            lbra .rest
.count      lsra
            rorb
            lsra
            rorb
            lsra
            rorb
            rts
.f_next     ldd 2,x
            cmpd 2,u
            bne .f_diff
            ldd ,x
            cmpd ,u
            bne .f_diff
            tsta
            bne .f_sized
            ldd 4,x
            cmpd 4,u
            bne .f_diff
.f_sized    ldd 6,x
            cmpd 6,u
            bne .f_color
            leax DL_SIZE,x
            leau DL_SIZE,u
            dec <t1
            bne .f_next
            bra .rest
            ; Only the color differs (a boss flashing white when hit): the draw covers exactly the pixels the old image had,
            ; so it needs no erase. An erase would only punch holes in neighbors for this draw to fill again.
.f_color    cmpa 6,u
            bne .f_diff
            stu ,y++
            leax DL_SIZE,x
            leau DL_SIZE,u
            bra .f_step
            ; Did old[i] leave? Then old[i+1] is new[i]. Told by where it is drawn and what.
.f_diff     cmpx <t3
            bhs .f_join
            ldd DL_SIZE+2,x
            cmpd 2,u
            bne .f_join
            ldd DL_SIZE,x
            cmpd ,u
            bne .f_join
            lbsr blit_erase
            leax DL_SIZE,x
            lda <t2
            inc <t2
            tsta
            bpl .f_step         ; the old list was not the nearer its end
            bra .f_next
            ; Did new[i] join? Then new[i+1] is old[i]. Listing it must not reach old[i], which is still to be read.
.f_join     cmpu <t4
            bhs .f_change
            ldd DL_SIZE+2,u
            cmpd 2,x
            bne .f_change
            ldd DL_SIZE,u
            cmpd ,x
            bne .f_change
            leay 2,y
            pshs y
            cmpx ,s++
            leay -2,y
            blo .f_change
            stu ,y++
            leau DL_SIZE,u
            lda <t2
            dec <t2
            tsta
            ble .f_step
            bra .f_next
.f_change   bsr blit_erase
            stu ,y++
            leax DL_SIZE,x
            leau DL_SIZE,u
.f_step     dec <t1
            lbne .f_next
            ; Old entries beyond the steps are erased, before any draw.
.rest       cmpx <dl_oldend
            bhs .r_draw
            bsr blit_erase
            leax DL_SIZE,x
            bra .rest
            ; The draws, in list order: those listed, then new entries beyond the steps.
.r_draw     stu <t2
            sty <t1
            ldy <dl_old
.f_draw     cmpy <t1
            bhs .r_new
            ldu ,y++
            ldd ,u
            std BLIT_SRC
            ldd 2,u
            std BLIT_DST
            ldd 4,u
            std BLIT_W
            ldd 6,u
            stb BLIT_SOLID
            sta BLIT_CTRL
            bra .f_draw
.r_new      ldu <t2
.r_next     cmpu <dl_newp
            bhs .done
            bsr blit_draw
            leau DL_SIZE,u
            bra .r_next
.done       puls u,pc

; X=old entry. A transparent entry erases its own shape; a solid one its rectangle.
blit_erase  ldd ,x
            std BLIT_SRC
            ldd 2,x
            std BLIT_DST
            ldd 4,x
            std BLIT_W
            clr BLIT_SOLID
            lda 6,x
            ora #BC_SOLID
            sta BLIT_CTRL
            rts

; U=new entry.
blit_draw   ldd ,u
            std BLIT_SRC
            ldd 2,u
            std BLIT_DST
            ldd 4,u
            std BLIT_W
            lda 7,u
            sta BLIT_SOLID
            lda 6,u
            sta BLIT_CTRL
            rts

; As pair_lists, for a tick when the terrain moved: an unchanged entry may have had terrain drawn over it, so it is
; drawn again. Erasing and redrawing as a pair is what keeps sprites from vanishing for a frame.
; ---- terrain --------------------------------------------------------------------------------
; Rectangles live in the level bank, which the caller has selected. The index has a pair of words per bucket:
; the first rect reaching that bucket, and the first rect starting in it.

; Sets Y and t1 to the rect range for view columns D (low) to t1 (high column).
terrain_range
            bsr .bucket
            aslb
            rola
            aslb
            rola
            cmpd <lvl_index_max
            bls .lo_ok
            ldd <lvl_index_max
.lo_ok      addd <lvl_index
            tfr d,x
            ldy ,x              ; first rect reaching the low bucket
            ldd <t1
            bsr .bucket
            addd #1
            aslb
            rola
            aslb
            rola
            cmpd <lvl_index_max
            bls .hi_ok
            ldd <lvl_index_max
.hi_ok      addd <lvl_index
            tfr d,x
            ldd 2,x             ; first rect starting past the high bucket
            addd <lvl_rects
            std <t1
            tfr y,d
            addd <lvl_rects
            tfr d,y
            rts
.bucket     bpl .pos
            ldd #0
            rts
.pos        lsra
            rorb
            lsra
            rorb
            lsra
            rorb
            lsra
            rorb
            rts

; Redraws a few rects in view each still tick, to heal holes left by sprites erasing across terrain.
REPAIR_RECTS equ 4
REPAIR_MOVING equ 2         ; rects per tick while the camera moves

Terrain_Repair
            lda #BC_FG_ONLY     ; a block's black middle must not paint over a sprite that is not being redrawn
            sta blk_fg
            lda #REPAIR_RECTS*4
; A=budget: 4 per rect redrawn, 1 per rect looked at. Only rects in view are visited, so a hole heals soon.
terrain_repair_n
            sta <repair_left
            lda <level_bank
            sta BANK_SELECT
            ldd <cam_col
            std <t2
            std <scroll_lo
            ldd <cam_top
            std <t3
            lda #1
            sta <t4
.next       ldd <repair_rect
            addd #8
            std <repair_rect
            addd <lvl_rects
            cmpd <lvl_objects   ; the rect table's size is objects - rects
            bhs .wrap
            tfr d,y
            ldd ,y
            subd <t2
            cmpd #VIEW_COLS
            blt .test
            ; Past the view's right edge: start again at its left.
.wrap       ldd <t2
            addd #VIEW_COLS
            std <t1
            ldd <t2
            jsr terrain_range
            cmpy <t1
            bhs .far            ; no rects here
            tfr y,d
            subd <lvl_rects
            std <repair_rect
.test       jsr terrain_near
            bne .far
            jsr terrain_rect
            lda <repair_left
            suba #4
            sta <repair_left
.far        dec <repair_left
            bgt .next
            clr blk_fg
            rts

; The camera moved vertically, and perhaps sideways. Each rect is erased and redrawn as a pair, so the terrain is never
; all gone at once. An erase can clip a neighbor's new position; Terrain_Repair heals that.
Terrain_Move
            ldd <cam_col
            cmpd <old_col
            bge .hi
            ldd <old_col
.hi         addd #VIEW_COLS
            std <t1
            ldd <cam_col
            cmpd <old_col
            ble .lo
            ldd <old_col
.lo         std <scroll_lo
            jsr terrain_range
.rect       cmpy <t1
            bhs .done
            ldd <old_top
            std <t3
            jsr terrain_near
            bne .new
            ldd <old_col
            std <t2
            clr <t4
            jsr terrain_rect
.new        ldd <cam_top
            std <t3
            jsr terrain_near
            bne .next
            ldd <cam_col
            std <t2
            lda #1
            sta <t4
            jsr terrain_rect
.next       leay 8,y
            bra .rect
.done       rts

Terrain_Draw
            ldd <cam_col
            std <t2
            ldd <cam_top
            std <t3
            lda #1
            sta <t4
terrain_walk
            ldd <t2
            addd #VIEW_COLS
            std <t1
            ldd <t2
            std <scroll_lo
            jsr terrain_range
            bra .test
.rect       jsr terrain_rect
.next       leay 8,y
.test       cmpy <t1
            bhs .done
            jsr terrain_near
            bne .next
            bra .rect
.done       rts

; Y=rect. Z set if it can touch the view: not ending left of scroll_lo, and within the lines at t3.
; Rects past the view's right edge are already excluded by the index.
terrain_near
            ldb 4,y
            clra
            addd ,y
            cmpd <scroll_lo
            ble .no
            ldb 5,y
            clra
            addd 2,y
            cmpd <t3
            ble .no
            ldd 2,y
            subd <t3
            cmpd #VIEW_H
            bge .no
            orcc #$04
            rts
.no         andcc #$FB
            rts

; The camera moved sideways only. A flat rectangle is erased only at its trailing end, and repainted in one blit. Others are
; erased and redrawn in full.
; Rects never overlap, but an old position can overlap another rect's new one, so every erase happens first.
Terrain_Scroll
            ldd <cam_col
            subd <old_col
            std <scroll_k       ; columns moved; positive = view moved right
            ldd <cam_top
            std <t3
            ldd <cam_col        ; the range covers both views
            cmpd <old_col
            bge .hi_new
            ldd <old_col
.hi_new     addd #VIEW_COLS
            std <t1
            ldd <cam_col
            cmpd <old_col
            ble .lo_new
            ldd <old_col
.lo_new     std <scroll_lo
            jsr terrain_range
.rect       cmpy <t1
            bhs .done
            jsr terrain_near
            bne .next
            lda 5,y
            cmpa #SCROLL_FLAT
            bhi .full
            tst 7,y
            bne .full
            bsr terrain_flat
            bra .next
.full       ldd <old_col
            std <t2
            clr <t4
            jsr terrain_rect
            ldd <cam_col
            std <t2
            lda #1
            sta <t4
            jsr terrain_rect
.next       leay 8,y
            bra .rect
.done       rts

SCROLL_FLAT equ 3           ; rects this tall or shorter scroll by their ends alone

; Y=rect. Works out the clipped spans in both views, as columns relative to the view, in 16 bits. Emits the erase of the
; trailing end, then a draw of the whole span.
terrain_flat
            ; Row clip, shared by both views: the camera did not move vertically.
            ldd 2,y
            subd <t3
            bmi .above
            cmpd #VIEW_H-SCROLL_FLAT
            bhs .out
            addb #VIEW_ROW0
            stb <flat_row
            ; old span [oa, ob)
            ldd ,y
            subd <old_col
            std <flat_oa
            ldb 4,y
            clra
            addd <flat_oa
            std <flat_ob
            ; new span [na, nb) is the old span shifted by k.
            ldd <flat_oa
            subd <scroll_k
            std <flat_na
            ldd <flat_ob
            subd <scroll_k
            std <flat_nb
            ldx #flat_oa
            bsr .clip
            ldx #flat_na
            bsr .clip
            ldd <scroll_k
            bmi .moves_right
            ; The view moved right: the rect moves left on screen.
            ldd <flat_nb        ; erase [max(nb, oa), ob)
            cmpd <flat_oa
            bge .e1
            ldd <flat_oa
.e1         std <t5
            ldd <flat_ob
            subd <t5
            ble .draw
            bsr .erase_at
            bra .draw
.moves_right
            ldd <flat_oa        ; erase [oa, min(na, ob))
            std <t5
            ldd <flat_na
            cmpd <flat_ob
            ble .e2
            ldd <flat_ob
.e2         subd <flat_oa
            ble .draw
            bsr .erase_at
            ; The draw covers the whole span, not just the new end. This line's pixels stay still on screen while sprites
            ; slide across them, so one erase after another would otherwise leave a trail of holes. Blitter time is
            ; plentiful, and this is still one blit.
.draw       ldd <flat_nb
            subd <flat_na
            ble .out
            ldx <flat_na
            stx <t5
            bra .draw_at
.out        rts
.above      ldd <old_col        ; crosses the top of the view: redraw it in full
            std <t2
            clr <t4
            jsr terrain_rect
            ldd <cam_col
            std <t2
            lda #1
            sta <t4
            jmp terrain_rect
.clip       ldd ,x              ; clamp the span at X to 0..VIEW_COLS
            bpl .c1
            ldd #0
.c1         cmpd #VIEW_COLS
            ble .c2
            ldd #VIEW_COLS
.c2         std ,x
            ldd 2,x
            bpl .c3
            ldd #0
.c3         cmpd #VIEW_COLS
            ble .c4
            ldd #VIEW_COLS
.c4         std 2,x
            rts
.erase_at   clr em_kind         ; B=width, t5=first column
            lda #BC_SOLID+BC_DST256
            sta em_cs
            clr em_cs+1
            bra .span
.draw_at    lda #1              ; B=width, t5=first column
            sta em_kind
            lda #BC_SOLID+BC_DST256
            sta em_cs
            lda 6,y
            sta em_cs+1
.span       stb em_wh
            lda 5,y
            sta em_wh+1
            lda <t5+1
            adda #VIEW_COL0
            ldb <flat_row
            std em_dst
            jmp emit_blit

; Y=rect: col(2) row(2) w h solid ctrl. t2/t3 give the view, t4 says draw or erase.
terrain_rect
            lda 7,y
            bita #RECT_HIDE
            beq terrain_rect_any
            jsr [rect_hidden_v] ; in terrain the boss changes: boss_terrain.asm
            bcc terrain_rect_any
            rts
; The same, shown or not: boss_terrain.asm erases with it what a region's old look showed.
terrain_rect_any
            ldd ,y
            subd <t2            ; column relative to the view
            bpl .col_in
            addb 4,y            ; starts left of the view: keep what remains
            adca #0
            lbne .skip
            tstb
            lbeq .skip
            cmpb #VIEW_COLS     ; a long rect can also run past the right edge. The blitter does not clip: unclamped,
            bls .w_left         ; this reaches the I/O mirrors at $C000 up and stops interrupts or swaps out the ROM
            ldb #VIEW_COLS
.w_left     stb <t5
            clrb
            bra .col
.col_in     cmpd #VIEW_COLS
            bhs .skip
            lda #VIEW_COLS      ; width = min(w, columns left)
            pshs b
            suba ,s
            ldb 4,y
            pshs a
            cmpb ,s+
            bls .w_ok
            tfr a,b
.w_ok       stb <t5
            puls b
.col        addb #VIEW_COL0
            stb <t0             ; video column
            ldd 2,y
            subd <t3            ; line relative to the view
            bpl .row_in
            addb 5,y            ; starts above the view
            adca #0
            bne .skip
            tstb
            beq .skip
            cmpb #VIEW_H
            bls .h_ok1
            ldb #VIEW_H
.h_ok1      stb <t5+1
            clrb
            bra .row
.row_in     cmpd #VIEW_H
            bhs .skip
            lda #VIEW_H         ; height = min(h, lines left)
            pshs b
            suba ,s
            ldb 5,y
            pshs a
            cmpb ,s+
            bls .h_ok
            tfr a,b
.h_ok       stb <t5+1
            puls b
.row        addb #VIEW_ROW0
            lda <t0
            std em_dst
            ldd <t5
            std em_wh
            lda 7,y
            ora #BC_SOLID+BC_DST256
            ldb 6,y
            tst <t4
            bne .paint
            clrb
            bra .emit
.paint      bita #RECT_IMAGE
            bne terrain_image
.emit       std em_cs
            lda <t4
            sta em_kind
            jmp emit_blit
.skip       rts

; Y=a block's rect, with em_dst and em_wh worked out by terrain_rect. A queue has no room for a source, so a queued block is
; drawn by blk_run, after the erases its half has queued. The level's bank is selected, and is again on return.
terrain_image
            lda 4,y
            cmpa #BLOCK_COLS
            bne .group
            lda 5,y
            cmpa #BLOCK_LINES
            bne .group
            jsr blk_dead
            bne .out
            bra .queue
            ; A group with a block gone is drawn block by block. In a queue it comes back through here later.
.group      tst queue_on
            bne .queue
            tst blk_kills
            beq .now
            jsr blk_group_any   ; whole, it is still one image
            beq .now
            ldx #terrain_rect
            jmp blk_split
.queue      tst queue_on
            beq .now
            clr tl_valid        ; its pointer goes where the list keeps blocks
            clr vl_valid
            ldx blk_p
            cmpx #BK_END-1
            bhs .now
            sty ,x++
            stx blk_p
            rts
.now        ldd <t2             ; columns and lines cut off by the view
            subd ,y
            bpl .c_ok
            clrb
.c_ok       addb #BLOCK_PAGE
            stb BLIT_SRC
            ldd <t3
            subd 2,y
            bpl .r_ok
            clrb
.r_ok       stb BLIT_SRC+1
            ldd em_dst
            std BLIT_DST
            ldd em_wh
            std BLIT_W
            lda blk_fg
            ora #BC_DST256+BC_SRC256
            clr BANK_SELECT
            sta BLIT_CTRL
            lda <level_bank
            sta BANK_SELECT
.out        rts

; Y=a block's rect. Z clear if the block has been destroyed. Keeps Y, U, t0 to t3: the terrain walks hold their end in t1.
blk_dead    tst blk_kills       ; Z set: none has been
            beq .out
            ldd <t3
            pshs d
            ldd <t2
            pshs d
            ldd <t1
            pshs d
            ldd <t0
            pshs d
            jsr blk_origin
            jsr cell_changed
            tfr cc,a
            puls x
            stx <t0
            puls x
            stx <t1
            puls x
            stx <t2
            puls x
            stx <t3
            tfr a,cc
.out        rts

; Y=a rect: t0=the column of its first cell, t1's high byte its row. Keeps X, Y, U, t2, t3.
blk_origin  ldd <t3             ; Div12 uses it
            pshs d
            ldd 2,y
            jsr Div12
            stb <t1
            ldd ,y
            aslb
            rola
            jsr Div12
            std <t0
            puls d
            std <t3
            rts

; Y=a group of blocks' rect. Z clear if any of its blocks has been destroyed: one pass over their changed bits, so a group
; that is whole is still drawn as one image. Keeps Y, U, t0 to t3.
blk_group_any
            ldd <t3
            pshs d
            ldd <t2
            pshs d
            ldd <t1
            pshs d
            ldd <t0
            pshs d
            jsr blk_origin
            jsr cell_changed    ; X=its byte, B=its mask
            pshs b,x            ; 0,s the row's first mask, 1,s its byte
            lda 5,y
.rows       pshs a              ; lines left: the row's mask and byte are now at 1,s and 2,s
            ldb 1,s
            ldx 2,s
            lda 4,y             ; columns left
.cell       bitb ,x
            bne .hit
            aslb
            bne .same
            leax 1,x
            ldb #1
.same       suba #BLOCK_COLS
            bne .cell
            ldd 2,s             ; the next row's byte
            addb <cls_stride
            adca #0
            std 2,s
            puls a
            suba #BLOCK_LINES
            bne .rows
            leas 3,s
            clra                ; Z set: all there
            bra .out
.hit        leas 4,s
            lda #1              ; Z clear
.out        tfr cc,a
            puls x
            stx <t0
            puls x
            stx <t1
            puls x
            stx <t2
            puls x
            stx <t3
            tfr a,cc
            rts

; A=0 for the upper half's pass, 1 for the lower's: draws the blocks queued up by terrain_rect that touch that half.
blk_run     ldx blk_p
            cmpx #tl_ram
            beq .out
            sta blk_half
            ldd <cam_col
            std <t2
            ldd <cam_top
            std <t3
            lda #1
            sta <t4
            lda <level_bank
            sta BANK_SELECT
            ldx #tl_ram
.next       cmpx blk_p
            bhs .done
            ldy ,x++
            ldd 2,y
            subd <t3
            addd #VIEW_ROW0
            tst blk_half
            bne .lower
            cmpd #BEAM_MID
            bge .next
            bra .draw
.lower      pshs d
            ldb 5,y
            clra
            addd ,s++
            cmpd #BEAM_MID
            ble .next
.draw       pshs x
            jsr terrain_rect
            puls x
            bra .next
.done       clr BANK_SELECT
.out        rts

; ---- cells ----------------------------------------------------------------------------------
; The cells live in the level's ROM grid, 4 bits each. RAM holds one bit per cell, set when the game has changed that cell:
; a changed cell is EMPTY, or PLATFORM if the grid has it empty. Only a few types of cell ever change, so most reads never
; look at the bits. The exception is a boss building walls in empty space, which sets cell_anychg.
; X=cell x, B=cell y (unsigned, so -1 reads as out of bounds). Returns A=type. Preserves Y and U.
Main_GetCell
            cmpx <lvl_w
            bhs getcell_oob
            cmpb <lvl_h+1
            bhs getcell_oob
            stx <t0
            stb <t1
            lda <grid_stride
            mul
            addd <lvl_grid
            std <t2
            ldd <t0
            lsra
            rorb
            addd <t2
            tfr d,x
; X=the grid's byte, t0=the column, t1=the row.
getcell_tail
            lda <level_bank
            cmpa <cur_bank
            bne .switch
            lda ,x
.have       ldb <t0+1
            lsrb
            bcs .low
            lsra
            lsra
            lsra
            lsra
.low        anda #$0F
            cmpa #2
            blo .plain
            cmpa #3
            beq .plain
            ; A type that can change.
            sta <cell_raw       ; the block with a buried crystal reads as a plain block
            bsr cell_changed
            bne .gone
            cmpa #8
            bne .out
            lda #PLATFORM_DESTRUCTIBLE
.out        rts
.gone       clra                ; EMPTY
            rts
.plain      tst cell_anychg
            bne .check
            rts
.check      bsr cell_changed
            beq .out
            cmpa #EMPTY
            bne .gone
            lda #PLATFORM
            rts
.switch     sta BANK_SELECT
            lda ,x
            ldb <cur_bank
            stb BANK_SELECT
            bra .have
getcell_oob lda #PLATFORM
            rts

; t0=column, t1=row, keeps A. Returns Z clear if the cell's changed bit is set, X=its byte and B=its mask.
cell_changed
            pshs a
            ldb <t0+1
            andb #7
            ldx #bit_masks
            ldb b,x
            pshs b
            ldb <t1
            lda <cls_stride
            mul
            addd <class_map
            std <t2
            ldd <t0
            lsra
            rorb
            lsra
            rorb
            lsra
            rorb
            addd <t2
            tfr d,x
            puls b
            bitb ,x
            puls a,pc

; Main.SetCellType: A=type, X=cell x, B=cell y. Keeps X and B.
Main_SetCellType
            pshs b,x
            inc cell_gen
            sta <t3
            pshs y              ; what lasers have kept may be out of date now
            ldy #laser_pool
.lm         cmpy laser_hi
            bhs .lmdone
            clr LM_TYPE,y
            leay LASER_SIZE,y
            bra .lm
.lmdone     puls y
            lda #$FF            ; and so may what the man has. No column is that large.
            sta mc_cells
            sta mc_cells+4
            sta mc_cells+8
            sta mc_cells+12
            cmpx <lvl_w
            bhs .out
            cmpb <lvl_h+1
            bhs .out
            stx <t0
            stb <t1
            lda <grid_stride
            mul
            addd <lvl_grid
            std <t2
            ldd <t0
            lsra
            rorb
            addd <t2
            tfr d,x
            lda <level_bank
            sta BANK_SELECT
            lda ,x
            ldb <cur_bank
            stb BANK_SELECT
            ldb <t0+1
            lsrb
            bcs .low
            lsra
            lsra
            lsra
            lsra
.low        anda #$0F           ; what the grid says
            ; Does what is wanted differ from the grid? Anything else asked for means what the grid says. A floaty platform
            ; over an empty grid cell (the bridge the boss leaves) can only be held as a platform.
            ldx #cell_class
            ldb <t3
            ldb b,x
            cmpb #CLS_EMPTY
            beq .empty
            cmpb #CLS_SPECIAL
            beq .clear
            cmpa #EMPTY         ; asked for platform, or a floaty platform: both read as PLATFORM
            bne .clear
            bra .set
.empty      cmpa #EMPTY
            beq .clear
.set        cmpa #2
            blo .plain
            cmpa #3
            bne .bit
.plain      lda #1
            sta cell_anychg
.bit        jsr cell_changed
            orb ,x
            stb ,x
            bra .out
.clear      jsr cell_changed
            comb
            andb ,x
            stb ,x
.out        puls b,x,pc

Level_Load  sta <level_bank
            pshs a
            jsr TL_Level
            puls a
            ldx #atlas_banks
            ldb a,x
            stb ban_bank
            sta <cur_bank
            sta BANK_SELECT
            ldx #0              ; level header at the start of the bank
            ldd ,x
            std <lvl_w
            ldd 2,x
            std <lvl_h
            ldd 4,x
            std <lvl_grid
            ldd 6,x
            std <lvl_index
            ldd 8,x
            std <lvl_rects
            ldd 10,x
            std <lvl_objects
            ldd 12,x
            std <lvl_objcount
            ldd 22,x
            std lvl_regions     ; the terrain the boss changes: boss_terrain.asm
            ; The index is pairs of words; the last valid pair starts 4 bytes before the rects.
            ldd <lvl_rects
            subd <lvl_index
            subd #4
            std <lvl_index_max
            ; Strides: 4 cells to a RAM byte, 2 to a ROM byte.
            ldd <lvl_w
            addd #1
            lsra
            rorb
            stb <grid_stride
            ; One changed bit per cell, just below the video tables. Game_Reset has cleared it.
            ldd <lvl_w
            addd #7
            lsra
            rorb
            lsra
            rorb
            lsra
            rorb
            stb <cls_stride
            lda <cls_stride
            ldb <lvl_h+1
            mul
            std <t0
            ldd #CLASS_END
            subd <t0
            std <class_map
            clr cell_anychg
            ; Blocks the boss makes later are in the grid, and begin gone (boss_terrain.ABSENT).
            ldx lvl_regions
            beq .noabs
            ldx RT_ABSENT,x
            ldb ,x+
            beq .noabs
            lda #1              ; their group images are drawn block by block
            sta blk_kills
.abs        pshs b
            ldd ,x++
            addd <class_map
            tfr d,y
            lda ,x+
            ora ,y
            sta ,y
            puls b
            decb
            bne .abs
.noabs
            ; The entity pool fills the room left below the bits.
            ldd <class_map
            subd #ent_pool
            ldx #ent_pool-ENT_SIZE
            clr <ent_count
.fit        subd #ENT_SIZE
            bcs .fitted
            leax ENT_SIZE,x
            inc <ent_count
            pshs a
            lda <ent_count
            cmpa #ENT_MAX
            puls a
            blo .fit
.fitted     stx <ent_last
            rts

atlas_banks ATLAS_BANKS
; ROM cell type to RAM class.
cell_class  fcb CLS_EMPTY,CLS_PLATFORM,CLS_SPECIAL,CLS_FLOATY,CLS_SPECIAL,CLS_SPECIAL,CLS_SPECIAL,CLS_SPECIAL,CLS_SPECIAL

; ---- camera ---------------------------------------------------------------------------------
; Draw.PushCamera3. X=man x, Y=man y.
CAM_LOOK    equ 737         ; 2.88 pixels per tick, 8.8
CAM_NUDGE_MAX equ 24*256

Camera_Update
            stx <t0
            sty <t1
            tst <cam_fixed
            bne .fixed
            tfr x,d
            subd <camm_x
            cmpd #-DRAW_DEAD_ZONE
            bge .notleft
            ldd <cam_nudge
            subd #CAM_LOOK
            cmpd #-CAM_NUDGE_MAX
            bge .l_ok
            ldd #-CAM_NUDGE_MAX
.l_ok       std <cam_nudge
            ldd <t0
            addd #DRAW_DEAD_ZONE
            std <camm_x
            bra .ydir
.notleft    cmpd #DRAW_DEAD_ZONE
            ble .ydir
            ldd <cam_nudge
            addd #CAM_LOOK
            cmpd #CAM_NUDGE_MAX
            ble .r_ok
            ldd #CAM_NUDGE_MAX
.r_ok       std <cam_nudge
            ldd <t0
            subd #DRAW_DEAD_ZONE
            std <camm_x
.ydir       tst <cam_lock
            bne .ymove
            ldd <t1
            std <cam_target_y
.ymove      ldd <cam_target_y
            subd <camm_y
            cmpd #4
            bge .ydown
            cmpd #-4
            ble .yup
            ldd <cam_target_y
            bra .ystore
.ydown      ldd <camm_y
            addd #4
            bra .ystore
.yup        ldd <camm_y
            subd #4
.ystore     std <camm_y
            bra Camera_Apply
            ; Boss arenas: ease toward a fixed target.
.fixed      ldd <cam_fixed_x
            subd <camm_x
            bsr .ease
            addd <camm_x
            std <camm_x
            ldd <cam_fixed_y
            subd <camm_y
            bsr .ease
            addd <camm_y
            std <camm_y
            clr <cam_nudge
            clr <cam_nudge+1
            bra Camera_Apply
.ease       cmpd #2             ; D = distance; returns a step of at most 2 per tick
            bgt .e_plus
            cmpd #-2
            blt .e_minus
            rts
.e_plus     ldd #2
            rts
.e_minus    ldd #-2
            rts

; Computes the view from camm_x + nudge and camm_y. The view moves in whole byte columns.
Camera_Apply
            ldb <cam_nudge      ; integer part of the nudge, sign extended
            sex
            addd <camm_x
            std <cam_x
            ldd <camm_y
            std <cam_y
            tst <death_cam
            beq .apply
            ; Draw.UpdateDeathCamera: position = from + ease * (target - from).
            ldb <death_cam
            dec <death_cam
            lda #30
            suba <death_cam     ; ticks elapsed, 1..30
            ldx #death_ease
            lda a,x
            sta <t0             ; ease, 0..255
            ldd <cam_x
            subd <death_from_x
            bsr .scale
            addd <death_from_x
            std <cam_x
            ldd <cam_y
            subd <death_from_y
            bsr .scale
            addd <death_from_y
            std <cam_y
            bra .apply
.scale      std <t1             ; signed distance * t0 / 256
            bpl .s1
            coma
            comb
            addd #1
.s1         std <t2
            lda <t2
            ldb <t0
            mul
            std <t3
            lda <t2+1
            ldb <t0
            mul
            tfr a,b
            clra
            addd <t3
            tst <t1
            bpl .s2
            coma
            comb
            addd #1
.s2         rts
.apply      ldd <cam_x
            andb #VIEW_STEP_X
            std <cam_x
            subd #VIEW_HALF_W
            clr <t0             ; t0 not 0: the view moves sideways this tick
            cmpd <cam_left
            beq .still
            inc <t0
.still      std <cam_left
            subd #VIEW_COL0*2
            std <spr_ox
            ldd <cam_left
            asra
            rorb
            std <cam_col
            ; Gameplay keeps cam_y. The view only moves when cam_y leaves a zone around it, because each vertical move
            ; redraws all the terrain in view. With 240 lines shown, the 108-line gameplay box stays in view.
            ldd <cam_y
            subd <view_y
            cmpd #VIEW_DEAD_ZONE
            bgt .vdown
            cmpd #-VIEW_DEAD_ZONE
            bge .vzone
            ldd <cam_y
            addd #VIEW_DEAD_ZONE
            bra .vset
.vdown      ldd <cam_y
            subd #VIEW_DEAD_ZONE
            bra .vset
            ; Inside the zone. Once the man stands still on a floor, with the camera caught up, the view comes down to center
            ; him as the original's does, so that from an edge he sees what he would drop into. Only down: each step redraws
            ; the terrain, so not while he walks, nor while the view moves sideways, and not up, which costs more than it shows.
.vzone      tst <t0
            bne .vkeep
            ldd <man_vx
            bne .vkeep
            tst <cam_lock
            bne .vkeep
            ldd <camm_y
            cmpd <cam_target_y
            bne .vkeep
            ldd <cam_y
            subd <view_y
            cmpd #4
            blt .vkeep
.sdown      ldd <view_y
            addd #4
.vset       std <view_y
.vkeep      ldd <view_y
            andb #VIEW_STEP_Y
            subd #VIEW_HALF_H
            std <cam_top
            subd #VIEW_ROW0+12
            std <spr_oy
            rts

; A smooth curve from 0 to 255 over 30 ticks, index 1..30.
death_ease  fcb 0,1,2,5,9,14,20,27,35,44,55,66,79,92,106,120,135,150,163,176,189,200,211,220,228,235,241,246,250,253,255

; Draw.SetCamera: X=x, Y=y.
Camera_Set  stx <camm_x
            sty <camm_y
            sty <view_y
            sty <cam_target_y
            clr <cam_nudge
            clr <cam_nudge+1
            lbra Camera_Apply

; Main.OnScreen against the original 192x108 box: X=x, Y=y. Returns Z set when on screen.
Main_OnScreen
            tfr x,d
            subd <cam_x
            addd #LOGIC_HALF_W
            cmpd #LOGIC_HALF_W*2
            bhi .no
            tfr y,d
            subd <cam_y
            addd #LOGIC_HALF_H
            cmpd #LOGIC_HALF_H*2
            bhi .no
            orcc #$04
            rts
.no         andcc #$FB
            rts
