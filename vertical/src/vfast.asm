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
wm_half     pshs x,y,u
            sta <t0
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
            jsr .half
            bne .new
            BLIT_ERASE_X
            tfr y,d
            tstb
            beq .new
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
.new        tst <t4
            beq .more
            dec <t4
            leau -DL_SIZE,u
            cmpy #3
            bhs .n_half
            leay 1,y
.n_half     lda 3,u
            adda 5,u
            jsr .half
            bne .more
            BLIT_DRAW_U
.more       lda <t3
            ora <t4
            lbne .pair
            puls x,y,u,pc
            ; A=an image's last line: Z set if it is in the half being done.
.half       cmpa #BEAM_MID
            bhi .lower
            lda <t0
            rts
.lower      lda <t0
            eora #1
            rts

; pair_lists's draws on a level with a boss: the same, with the worm's images moved where the worm belongs in the list.
; Y=the entries listed to draw, to t1, then the new entries from t2. Ends pair_lists. Everything in the list from the worm's
; place on is drawn, changed or not: it lies over the worm, which has just been drawn whole, and the black that covers what
; of the worm is outside the window is there.
wm_still    ldx <dl_new
            ldu <dl_newp
            tst DL_WM_N,x
            bne .has
            stu <t5             ; no worm now: what there was of it goes before anything is drawn
            bsr .worm
            bra .f_draw
.has        ldu DL_WM_AT,x
            stu <t5             ; the worm's place in the list
.f_draw     cmpy <t1
            bhs .tail
            ldu ,y++
            cmpu <t5
            bhs .tail
            jsr blit_draw
            bra .f_draw
.tail       ldu <t2
.t_next     cmpu <t5
            bhs .place
            jsr blit_draw
            leau DL_SIZE,u
            bra .t_next
.place      ldx <dl_new
            tst DL_WM_N,x
            beq .out
            bsr .worm
            ldu <t5
.all        cmpu <dl_newp
            bhs .out
            jsr blit_draw
            leau DL_SIZE,u
            bra .all
.out        puls u,pc
.worm       clra
            jsr wm_half
            lda #1
            jmp wm_half
