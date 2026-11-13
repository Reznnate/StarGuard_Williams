; The vertical build's still layer when the view goes a few lines along the lines only (the game going sideways): see still_lines.

; X=first entry, Y=the end of the range, t0+1=direction, as still_walk takes them. The view moved by still_dr lines and no
; columns: what still_walk does then. One that shows was within the view's columns when it was shown, and still is.
still_lmove pshs y              ; 0,s = where the walk stops
            cmpx ,s
            beq .none           ; an empty range
            ldb #S_SIZE
            tst <t0+1
            beq .dir
            tfr x,d             ; backward: from the last entry down to just below the first
            subd #S_SIZE
            std ,s
            leax -S_SIZE,y
            ldb #-S_SIZE
.dir        stb <t1
.next       lda S_STATE,x
            beq .skip
            bita #SS_DIE+SS_NEW
            bne .odd
            bita #SS_SHOWN
            beq .hidden
            ldd S_SRC,x         ; erased where it was
            std BLIT_SRC
            lda S_COL+1,x
            ldb S_ROW+1,x
            std BLIT_DST
            ldd S_W,x
            std BLIT_W
            clr BLIT_SOLID
            lda S_CTRL,x
            ora #BC_SOLID
            sta BLIT_CTRL
            ldd S_ROW,x
            subd still_dr
            std S_ROW,x
            cmpd #VIEW_BOTTOM
            bhs .hide
            addb S_W+1,x
            cmpb #VIEW_ROW0
            bls .hide
            ; The erase left the source and size in the blitter's registers, and the column has not changed.
            lda S_COL+1,x
            ldb S_ROW+1,x
            std BLIT_DST
            ldd S_CTRL,x
            stb BLIT_SOLID
            sta BLIT_CTRL
            jsr still_edge
.skip       ldb <t1
            leax b,x
            cmpx ,s
            bne .next
.none       puls y,pc
.hide       lda S_STATE,x
            anda #~SS_SHOWN&$FF
            sta S_STATE,x
            bra .skip
            ; New: placed where the view now is.
.odd        bita #SS_DIE
            bne .die
            anda #~(SS_NEW+SS_SHOWN)&$FF
            sta S_STATE,x
.hidden     ldd S_ROW,x
            subd still_dr
            std S_ROW,x
            cmpd #VIEW_BOTTOM
            bhs .skip
            addb S_W+1,x
            cmpb #VIEW_ROW0
            bls .skip
            ldd S_COL,x
            beq .col_ok
            tsta
            bne .skip
.col_ok     cmpb #VIEW_COL0+VIEW_COLS
            bhs .skip
            addb S_W,x
            cmpb #VIEW_COL0
            bls .skip
            lda S_STATE,x
            ora #SS_SHOWN
            sta S_STATE,x
            jsr still_draw
            bra .skip
.die        bita #SS_SHOWN
            beq .free
            jsr still_erase
.free       jsr still_free
            bra .skip
