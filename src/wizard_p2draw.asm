; Phase 2's worm drawing (Wizard_p2_3.DrawSelf), called with FAR from P2_Update in bank 11, which is full. Its state is
; in wiz_ram as before: see the equates at the top of wizard.asm.
; By phase, one per tick of the 3-second period: a segment's width, its height (28 + 2 * stretch), and its top below the
; worm's (4 - stretch).
p2_seg_table
            fcb 6,36,0,6,36,0,6,36,0,6,36,0,6,36,0,6,36,0,6,36,0,6,36,0,6,36,0,6,36,0
            fcb 6,36,0,6,36,0,6,36,0,6,36,0,6,36,0,6,36,0,6,36,0,6,34,1,6,34,1,6,34,1
            fcb 6,34,1,6,34,1,6,34,1,6,32,2,6,32,2,7,32,2,7,32,2,7,32,2,7,32,2,7,30,3
            fcb 7,30,3,7,30,3,8,30,3,8,30,3,8,28,4,8,28,4,8,28,4,8,28,4,8,28,4,8,28,4
            fcb 9,28,4,9,28,4,9,28,4,9,28,4,9,28,4,9,28,4,9,28,4,9,28,4,9,28,4,9,28,4
            fcb 9,28,4,8,28,4,8,28,4,8,28,4,8,28,4,8,28,4,8,28,4,8,30,3,8,30,3,7,30,3
            fcb 7,30,3,7,30,3,7,32,2,7,32,2,7,32,2,7,32,2,6,32,2,6,32,2,6,34,1,6,34,1
            fcb 6,34,1,6,34,1,6,34,1,6,34,1,6,36,0,6,36,0,6,36,0,6,36,0,6,36,0,6,36,0
            fcb 6,36,0,6,36,0,6,36,0,6,36,0,6,36,0,6,36,0,6,36,0,6,36,0,6,36,0,6,36,0

; DrawSelf. The C draws 36 segments of 5 entries each, 180 in all. Only the part in view is drawn here, the mouth in full
; and at most P2_MAX_SEGS segments behind it, in 3 entries for the head and 1 or 2 a segment.
p2_draw     lda #COLOR_RED
            sta <draw_color
            lda E_FLAGS,u
            bita #EF_FLASHING
            beq .color
            ldb <now+1
            subb E_FLASHT,u
            cmpb #ALIEN_FLASH_T
            bls .white
            lda E_FLAGS,u
            anda #~EF_FLASHING&$FF
            sta E_FLAGS,u
            bra .color
.white      lda #COLOR_WHITE
            sta <draw_color
.color      lda <draw_color
            ldb #$11
            mul
            stb wd_g            ; for p2_put
            ldd wp2_y
            subd #P2_SIZEY
            std wd_top
            ; Phase of segment 0: 1 - progress.
            ldd <now
            subd wp2_segt
.mod        cmpd #P2_ANIM_T
            blo .modded
            subd #P2_ANIM_T
            bra .mod
.modded
            pshs b
            ldb #P2_ANIM_T
            subb ,s+
            cmpb #P2_ANIM_T
            blo .ph
            clrb
.ph         lda #3
            mul
            addd #p2_seg_table
            std wd_p
            ldd wp2_x
            addd #P2_SIZEX-12
            std wd_cur
            clr wq_i
            lda #P2_MAX_SEGS
            sta wd_n
            ; The cursor is the right end of the next segment. Left of the view: everything further back is too.
.seg        ldd wd_cur
            cmpd <cam_left
            blt .done
            ldx wd_p
            subb ,x
            sbca #0
            std wd_cur
            std wd_x
            ldd ,x
            sta wd_w
            stb wd_h
            ldb 2,x
            clra
            addd wd_top
            std wd_y
            ; Right of the view: not drawn, but it still counts toward the cursor.
            ldd wd_x
            subd <cam_left
            cmpd #VIEW_COLS*2
            bge .next
            tst wq_i
            bne .body
            jsr p2_draw_mouth
            bra .next
.body       jsr p2_draw_segment
            dec wd_n
            beq .done
.next       ldx wd_p            ; 0.1 of the period on
            leax 27,x
            cmpx #p2_seg_table+270
            blo .nowrap
            leax -270,x
.nowrap     stx wd_p
            inc wq_i
            lda wq_i
            cmpa #36            ; P2_SEGMENT_COUNT
            lblo .seg
.done       rts

; The worm is drawn from images that gen_assets bakes from the original's sprites 288-292 (see worm_pieces there), one
; color, the same pixels as the C's 5 draws a segment and 10 for the head. Per width: its tallest segment.
p2_simg     fdb WORM_S6
            fcb WORM_S6_W,WORM_S6_H
            fdb WORM_S7
            fcb WORM_S7_W,WORM_S7_H
            fdb WORM_S8
            fcb WORM_S8_W,WORM_S8_H
            fdb WORM_S9
            fcb WORM_S9_W,WORM_S9_H

; wd_x, wd_y, wd_w, wd_h. A segment as tall as its width's image is that image. A shorter one is the image's first
; h-9 lines and then its last 9 lines, the caps, 9 lines above its foot.
p2_draw_segment
            ldb wd_w
            subb #6
            aslb
            aslb
            ldx #p2_simg
            abx
            ldd ,x
            std wq_tx
            ldd 2,x             ; A=bytes a line, B=the image's lines
            cmpb wd_h
            bne .split
            std wq_ty
            ldx wd_x
            ldy wd_y
            lbra p2_put
.split      sta wq_ty
            pshs b
            ldb wd_h
            subb #9
            stb wq_ty+1
            ldx wd_x
            ldy wd_y
            bsr p2_put
            puls b
            subb #9
            lda wq_ty
            mul
            addd wq_tx
            std wq_tx
            lda #9
            sta wq_ty+1
            ldb wd_h
            subb #9
            clra
            addd wd_y
            tfr d,y
            ldx wd_x
            bra p2_put

; wd_x, wd_y, wd_h. The head: its top and bottom 9 lines, and its middle 18 from h/2-9.
p2_draw_mouth
            ldd #WORM_HT
            std wq_tx
            ldd #WORM_HT_W*256+WORM_HT_H
            std wq_ty
            ldx wd_x
            ldy wd_y
            bsr p2_put
            ldd #WORM_HB
            std wq_tx
            ldd #WORM_HB_W*256+WORM_HB_H
            std wq_ty
            ldb wd_h
            subb #9
            clra
            addd wd_y
            tfr d,y
            ldx wd_x
            bsr p2_put
            ldd #WORM_HC
            std wq_tx
            ldd #WORM_HC_W*256+WORM_HC_H
            std wq_ty
            ldb wd_h
            lsrb
            subb #9
            clra
            addd wd_y
            tfr d,y
            ldx wd_x
            ; fall through

; One image into the display list, as Draw_ColoredSprite does it: X, Y = world x, y of its top left, wq_tx = its pixels,
; wq_ty = bytes a line and lines, wd_g = the color in both pixels. Keeps U.
p2_put      tfr x,d
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
            addb wq_ty
            cmpb #VIEW_COL0
            bls .out
            tfr y,d
            subd <spr_oy
            tsta
            bne .out
            subb #12
            blo .out
            stb 3,x
            cmpb #VIEW_BOTTOM
            bhs .out
            addb wq_ty+1
            cmpb #VIEW_ROW0
            bls .out
            ldd wq_tx
            std ,x
            ldd wq_ty
            std 4,x
            lda wd_g
            sta 7,x
            DL_INSIDE
            leax DL_SIZE,x
            stx <dl_newp
.out        rts
.edge       pshs u
            jsr dl_edge
            puls u,pc
.full       ldx <dl_dropped
            leax 1,x
            stx <dl_dropped
            rts

