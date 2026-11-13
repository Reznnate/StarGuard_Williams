; What crosses the edge of the window. This sits after the sprites in fixed ROM, where there is room.

; X=an entry just drawn. Keeps X. Blackens whatever of it lies outside the window: the blitter does not clip.
still_edge  lda S_COL+1,x
            cmpa #VIEW_COL0
            blo .edge
            adda S_W,x
            cmpa #VIEW_COL0+VIEW_COLS-1
            bhi .edge
            lda S_ROW+1,x
            cmpa #VIEW_ROW0
            blo .edge
            adda S_W+1,x
            cmpa #VIEW_BOTTOM
            bhi .edge
            rts
.edge       pshs x,y
            lda S_COL+1,x
            sta edge_c
            lda S_ROW+1,x
            sta edge_r
            ldd S_W,x
            std edge_w
            ldx #edge_blit
            stx edge_fn
            clr BLIT_SOLID
            jsr edge_rects
            puls x,y,pc

; Whatever of an image lies outside the window is covered with black straight after the image, since the blitter does not clip.
; edge_c, edge_r, edge_w, edge_h=the image. Calls edge_fn with A=column, B=line, edge_mw, edge_mh for each piece. The image may be shifted a pixel, so
; it is taken as a column wider.
edge_rects
            lda #2
            sta bz_dirty
            lda edge_c
            cmpa #VIEW_COL0
            bhs .right
            ldb #VIEW_COL0
            subb edge_c
            stb edge_mw
            ldb edge_h
            stb edge_mh
            ldb edge_r
            jsr [edge_fn]
.right      lda edge_c
            adda edge_w
            inca
            suba #VIEW_COL0+VIEW_COLS
            bls .top
            sta edge_mw
            ldb edge_h
            stb edge_mh
            lda #VIEW_COL0+VIEW_COLS
            ldb edge_r
            jsr [edge_fn]
.top        ldb edge_w
            incb
            stb edge_mw
            lda edge_r
            cmpa #VIEW_ROW0
            bhs .bottom
            ldb #VIEW_ROW0
            subb edge_r
            stb edge_mh
            lda edge_c
            ldb edge_r
            jsr [edge_fn]
.bottom     lda edge_r
            adda edge_h
            suba #VIEW_BOTTOM
            bls .done
            sta edge_mh
            lda edge_c
            ldb #VIEW_BOTTOM
            jsr [edge_fn]
.done       rts

edge_blit   std BLIT_DST
            ldd edge_mw
            std BLIT_W
            lda #BC_SOLID+BC_DST256
            sta BLIT_CTRL
            rts

; The display list entry at X is complete, and is not wholly inside the window. Adds it, and its black pieces as entries after it, so that they pair
; and erase as any other. Their source is 0, so that the pairing compares their size. Keeps Y and U.
dl_edge     pshs y
            ldd 2,x
            sta edge_c
            stb edge_r
            ldd 4,x
            std edge_w
            leax DL_SIZE,x
            stx <dl_newp
            ldx #edge_dl
            stx edge_fn
            jsr edge_rects
            puls y,pc

edge_dl     ldx <dl_newp
            cmpx <dl_limit
            bhs .full
            std 2,x
            ldd #0
            std ,x
            ldd edge_mw
            std 4,x
            ldd #(BC_SOLID+BC_DST256)*256
            std 6,x
            leax DL_SIZE,x
            stx <dl_newp
            rts
.full       ldx <dl_dropped
            leax 1,x
            stx <dl_dropped
            rts

; Lists the remains near the view by the half of the screen they are in. One further than the view can move before the next listing
; waits, out of the lists. On many levels that is most of them.
REM_NEAR    equ 16
rem_relist  pshs u
            jsr rem_flush
            clr rem_dirty
            ldx #still_list+STILL_BANNER*S_SIZE
            ldy #rem_a
            ldu #rem_b
.next       cmpx still_rhi
            bhs .end
            lda S_STATE,x
            beq .skip
            ldd S_COL,x
            subd #VIEW_COL0-(REM_NEAR+2)
            cmpd #VIEW_COLS+(REM_NEAR+2)*2
            bhs .far
            ldd S_ROW,x
            cmpd #VIEW_BOTTOM
            bhs .far
            addb S_W+1,x
            cmpb #VIEW_ROW0
            bls .far
            ldb S_ROW+1,x
            bmi .low
            stx ,y++
            bra .skip
.low        stx ,u++
            bra .skip
.far        lda S_STATE,x
            anda #~SS_CUR&$FF
            sta S_STATE,x
.skip       leax S_SIZE,x
            bra .next
.end        ldd #0
            std ,y
            std ,u
            puls u,pc

BZ_LIGHT    equ $2F^$FF         ; the light that runs out from the window: amber
BZ_RAIL     equ $11             ; red
; Once a tick after Present. The light costs a few writes to the line colors. The rails cost nothing unless a black cover has been near them.
Bezel_Tick  jsr bz_gate
            bcs .rails
            ldx #COLOR0_TABLE
            ldy #COLOR0_TABLE+255
            ldb bz_line
            lda bz_save
            sta b,x
            negb
            sta b,y
            negb
            decb
            cmpb #7
            bhs .keep
            ldb #71
.keep       stb bz_line
            lda b,x
            sta bz_save
            lda #BZ_LIGHT
            sta b,x
            negb
            sta b,y
.rails      tst bz_dirty
            beq .out
            dec bz_dirty
            lda #BZ_RAIL
            sta BLIT_SOLID
            ldx #(VIEW_COL0-1)*256+VIEW_ROW0-1
            stx BLIT_DST
            ldx #256+VIEW_H+2
            stx BLIT_W
            lda #BC_SOLID+BC_DST256
            sta BLIT_CTRL
            ldx #(VIEW_COL0+VIEW_COLS)*256+VIEW_ROW0-1
            stx BLIT_DST
            sta BLIT_CTRL
            clr BLIT_SOLID
.out        rts
