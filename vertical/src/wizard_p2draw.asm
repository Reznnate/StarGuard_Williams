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
            if VERT
            ; The worm's images go in a list of their own, down from the display list's last entry, which is its header:
            ; Present moves them one at a time, each erased and at once drawn, so the worm is never missing while the beam
            ; goes by (wm_half). The header notes where in the display list the worm belongs, for what is drawn over it.
            ldx <dl_new
            leax (DL_ENTRIES-1)*DL_SIZE,x
            ldd <dl_newp
            std DL_WM_AT-(DL_ENTRIES-1)*DL_SIZE,x
            tfr x,d
            subd #WM_MAX*DL_SIZE
            cmpd <dl_newp
            lblo .done          ; no room under the list this tick
            std <dl_limit
            stx wq_cx           ; the next image's entry goes below this: nothing else uses wq_cx while the worm is drawn
            endif
            clr wq_i
            lda #P2_MAX_SEGS
            sta wd_n
            ; The cursor is the right end of the next segment. Left of the view: everything further back is too.
.seg        ldd wd_cur
            cmpd <gcam_left
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
            subd <gcam_left
            if VERT
            cmpd #GVIEW_W
            else
            cmpd #VIEW_COLS*2
            endif
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
            if VERT
; Turned, no image can be cut along its lines, so each shape a segment takes is an image of its own (gen_assets.py,
; worm_pieces): image, bytes a line, lines, column and line in its canvas. A width's tallest first, then 2 shorter each.
p2_vimg     fdb WORM_V636
            fcb WORM_V636_W,WORM_V636_H,WORM_V636_OX,WORM_V636_OY
            fdb WORM_V634
            fcb WORM_V634_W,WORM_V634_H,WORM_V634_OX,WORM_V634_OY
            fdb WORM_V632
            fcb WORM_V632_W,WORM_V632_H,WORM_V632_OX,WORM_V632_OY
            fdb WORM_V732
            fcb WORM_V732_W,WORM_V732_H,WORM_V732_OX,WORM_V732_OY
            fdb WORM_V730
            fcb WORM_V730_W,WORM_V730_H,WORM_V730_OX,WORM_V730_OY
            fdb WORM_V830
            fcb WORM_V830_W,WORM_V830_H,WORM_V830_OX,WORM_V830_OY
            fdb WORM_V828
            fcb WORM_V828_W,WORM_V828_H,WORM_V828_OX,WORM_V828_OY
            fdb WORM_V928
            fcb WORM_V928_W,WORM_V928_H,WORM_V928_OX,WORM_V928_OY
; By width, 6 to 9: its first image in p2_vimg, and then its tallest segment.
p2_vfirst   fcb 0,3,5,7
            fcb 36,32,30,28

; wd_x, wd_y, wd_w, wd_h. The image is as wide as the segment is tall, and p2_put places a canvas VROT_W wide: the
; difference is allowed for in the y it is given.
p2_draw_segment
            ldb wd_w
            subb #6
            ldx #p2_vfirst
            abx
            lda 4,x
            suba wd_h
            lsra
            adda ,x
            ldb #6
            mul
            ldx #p2_vimg
            abx
            ldd ,x
            std wq_tx
            ldd 2,x
            std wq_ty
            ldd 4,x
            std wq_o
            ldb wd_h
            subb #VROT_W
            clra
            addd wd_y
            tfr d,y
            ldx wd_x
            lbra p2_put
            else
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
            endif

; wd_x, wd_y, wd_h. The head: its top and bottom 9 lines, and its middle 18 from h/2-9.
p2_draw_mouth
            ldd #WORM_HT
            std wq_tx
            ldd #WORM_HT_W*256+WORM_HT_H
            std wq_ty
            if VERT
            ldd #WORM_HT_OX*256+WORM_HT_OY
            std wq_o
            endif
            ldx wd_x
            ldy wd_y
            bsr p2_put
            ldd #WORM_HB
            std wq_tx
            ldd #WORM_HB_W*256+WORM_HB_H
            std wq_ty
            if VERT
            ldd #WORM_HB_OX*256+WORM_HB_OY
            std wq_o
            endif
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
            if VERT
            ldd #WORM_HC_OX*256+WORM_HC_OY
            std wq_o
            endif
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
p2_put
            if VERT
            ; Turned, as Draw_Sprite: the column from y, vert_xm - VROT_W - y + its column in the canvas, and the line from x.
            pshs x
            tfr y,d
            coma
            comb
            addd <vk
            addb wq_o
            adca #0
            puls y              ; the game's x, for the line
            ldx wq_cx           ; into the worm's own list, which p2_draw made room for
            leax -DL_SIZE,x
            cmpx <dl_limit
            blo .out
            else
            tfr x,d
            subd <spr_ox
            ldx <dl_newp
            cmpx <dl_limit
            bhs .full
            endif
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
            if VERT
            addb wq_o+1
            adca #0
            endif
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
            if VERT
            stx wq_cx
            ldy <dl_new
            inc DL_WM_N,y
            DL_INSIDE
.out        rts
            ; It crosses the window's edge: the black that covers what is outside goes in the display list, which is
            ; drawn after the worm from where the worm belongs.
.edge       ldd 2,x
            sta edge_c
            stb edge_r
            ldd 4,x
            std edge_w
            ldx #edge_dl
            stx edge_fn
            pshs u
            jsr edge_rects
            puls u,pc
            else
            DL_INSIDE
            leax DL_SIZE,x
            stx <dl_newp
.out        rts
.edge       pshs u
            jsr dl_edge
            puls u,pc
            endif
.full       ldx <dl_dropped
            leax 1,x
            stx <dl_dropped
            rts

