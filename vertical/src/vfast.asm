; The vertical build's short ways for its commonest move, the view going a few lines along the lines (the game going sideways).
; They do what the general routines do then, blit for blit and in the same order, without the work a move across needs.

; In the list of rects near the view, a floor's entry, or another flat's, is 4 bytes here: the rect, then what its columns
; come to in the view, which holds until the view moves across: the blitter's width, with VLF_LONG set if it is not a floor,
; and the blitter's column. Both are 0 if none of it is in the view's columns. vl_fcol is the view's column they were worked
; out for, and vl_nlong how many of them vl_trail has a strip to erase for.
VLF_LONG     equ $80

; Floors and everything else that is not a wall or a block, for a small step along the lines only. A floor is erased where
; it was and drawn where it is. One that the boss changes is a floor like any other while it is in the list, which is made
; again when a region's look changes.
vl_flats_line
            ldd <cam_col
            cmpd vl_fcol
            beq .cached
            jsr vl_fcache
.cached     tst vl_nlong
            beq .floors
            jsr vl_trail        ; solid rects' trailing strips, before any is drawn
.floors     lda #1
            sta BLIT_H
            ldu vl_f
            bra .test
.long       anda #~VLF_LONG&$FF
            sta BLIT_W
            stb BLIT_DST
            jsr vl_long
            lda #1
            sta BLIT_H
            bra .adv
.next       ldy ,u
            ldd 2,u
            beq .adv
            bmi .long
            sta BLIT_W
            stb BLIT_DST
            ldd 2,y
            subd <old_top
            tsta
            bne .draw
            cmpb #VIEW_H
            bhs .draw
            addb #VIEW_ROW0
            stb BLIT_DST+1
            clr BLIT_SOLID
            lda #BC_SOLID+BC_DST256
            sta BLIT_CTRL
.draw       ldd 2,y
            subd <cam_top
            tsta
            bne .adv
            cmpb #VIEW_H
            bhs .adv
            addb #VIEW_ROW0
            stb BLIT_DST+1
            ldb 6,y
            stb BLIT_SOLID
            lda #BC_SOLID+BC_DST256
            sta BLIT_CTRL
.adv        leau VL_FSIZE,u
.test       cmpu #VL_MID
            blo .next
            rts

; The boss's worm is redrawn whole on every tick it shows, and it is most of the picture: erased with the rest of the display
; list and then drawn, it was missing wherever the beam went by in between. So its images are in a list of their own
; (wizard_p2draw.asm) and are moved one at a time here, each erased and at once drawn, which leaves at most one of them
; missing, for about two lines of the beam. A=0 for the images in the upper half of the screen, 1 for the lower half, by
; pair_lists_moved's rule. The old list's images are taken with the new one's, in order: they need not be the same segments,
; only all be erased and all be drawn. An erase can cut a new image already taken, a neighbor or one of the head's other
; pieces, which is then drawn again. Keeps X, Y, U.
; The upper half's pass walks both lists once and keeps what belongs to the lower half, in order, as records at WM_RP0
; (wm_rpe their end): the lower half's pass only plays them back. A record: a byte, $FF for a draw or else how many new
; images an erase could cut, then the image, then where the new list stood (for a draw, the image again).
WM_RP0      equ $9710           ; past the columns the screen shows, and cleared at reset
wm_rpe      equ $970E           ; 0 when there are none
wm_rpp      equ $970C
            assert WM_RP0+WM_MAX*2*5<=$9800,"room for a tick's records"
wm_half     pshs x,y,u
            tsta
            lbne .replay
            ldx #WM_RP0
            stx wm_rpp
            ldx <dl_old
            lda DL_WM_N,x
            sta <t3
            leax DL_ROOM*DL_SIZE,x
            ldu <dl_new
            lda DL_WM_N,u
            sta <t4
            leau DL_ROOM*DL_SIZE,u
            ldy #0              ; how many of the new images just before this one an erase could cut: up to 3
.pair       tst <t3
            beq .new
            dec <t3
            leax -DL_SIZE,x
            lda 3,x
            adda 5,x
            cmpa #BEAM_MID
            tfr y,d
            bhi .e_keep
            lbsr .erase
            bra .new
.e_keep     bsr .keep
.new        tst <t4
            beq .more
            dec <t4
            leau -DL_SIZE,u
            cmpy #3
            bhs .n_half
            leay 1,y
.n_half     lda 3,u
            adda 5,u
            cmpa #BEAM_MID
            bhi .d_keep
            BLIT_DRAW_U
            bra .more
.d_keep     ldb #$FF
            pshs x
            tfr u,x
            bsr .keep
            puls x
.more       lda <t3
            ora <t4
            bne .pair
            ldx wm_rpp          ; the records are ready for the lower half
            stx wm_rpe
            puls x,y,u,pc
            ; B=what the record is, X=the image, U=where the new list stands.
.keep       pshs y
            ldy wm_rpp
            stb ,y+
            stx ,y++
            stu ,y++
            sty wm_rpp
            puls y,pc
            ; The lower half's pass: the records, in order.
.replay     ldy #WM_RP0
            bra .r_test
.r_next     ldb ,y+
            ldx ,y++
            ldu ,y++
            tstb
            bmi .r_draw
            lbsr .erase
            bra .r_test
.r_draw     BLIT_DRAW_U
.r_test     cmpy wm_rpe
            blo .r_next
            ldd #0
            std wm_rpe
            puls x,y,u,pc
            ; X=an old image: erased. B=how many new images from U on it could cut: each it does is drawn again. Keeps X, Y, U.
.erase      pshs b
            BLIT_ERASE_X
            puls b
            tstb
            beq .e_out
            pshs b,u            ; did that cut any of them? Then it is drawn again
.h_next     lda 3,x
            adda 5,x
            cmpa 3,u
            bls .h_no
            lda 3,u
            adda 5,u
            cmpa 3,x
            bls .h_no
            lda 2,x
            adda 4,x
            cmpa 2,u
            bls .h_no
            lda 2,u
            adda 4,u
            cmpa 2,x
            bls .h_no
            BLIT_DRAW_U
.h_no       leau DL_SIZE,u
            dec ,s
            bne .h_next
            puls b,u
.e_out      rts

