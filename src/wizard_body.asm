; Phase 3's body, kept from one tick to the next. Called from wizard.asm with FAR: bank 11 is full, and the boss only lives on
; level 9, whose bank has room. RAM only, so nothing here cares which bank is selected.

; The body's entries, copied from the list drawn last tick, which is still whole in dl_old, with this tick's color. Building
; them is most of the boss's time. If y2 or the view has moved since, every entry moves by the same columns and lines (the
; view steps 2 pixels, a whole byte column, and x2 stays put in this phase), so long as none was cut at the view's edge then
; or would be now. Returns D=0 (Z set) if done; otherwise the body is to be drawn the usual way, starting at the list index
; kept in wk_idx, and then p3_body_note. Only low bytes are compared, since the list is one tick old.
P3_MOVE_MAX equ 16              ; columns or lines: beyond this (a respawn's jump) the usual way, which needs no checks
p3_body_reuse
            ldd <dl_newp
            subd <dl_new
            jsr wz_shift3
            lda wk_idx          ; where the body was in the old list
            sta wd_h
            stb wk_idx          ; where it goes in this one
            tst wk_ok
            lbeq .no
            clr wk_ok
            lda dl_gen
            deca
            cmpa wk_gen
            lbne .no
            tst <still_mode
            lbne .no
            lda wd_g
            cmpa wk_oy+1
            lbne .no
            ; wd_x = columns moved, wd_x+1 = lines.
            ldb wk_y+1
            subb <spr_ox+1
            asrb
            stb wd_x
            addb #P3_MOVE_MAX
            cmpb #2*P3_MOVE_MAX
            lbhi .no
            lda wp3_y+1
            suba wk_y
            suba <spr_oy+1
            adda wk_oy
            sta wd_x+1
            adda #P3_MOVE_MAX
            cmpa #2*P3_MOVE_MAX
            lbhi .no
            jsr p3_body_count
            stb wq_n
            lda #DL_SIZE
            mul
            addd <dl_newp
            cmpd <dl_limit      ; no room for them all: the usual way counts what is dropped
            lbhi .no
            ldb wd_h
            lda #DL_SIZE
            mul
            addd <dl_old
            pshs u
            tfr d,u
            lda <draw_color
            ldb #$11
            mul
            stb wd_w
            ldy <dl_newp
            ldd wd_x
            bne .move
.copy       pulu d,x
            std ,y
            stx 2,y
            pulu d,x
            std 4,y
            tfr x,d
            ldb wd_w
            std 6,y
            leay DL_SIZE,y
            dec wq_n
            bne .copy
            bra .done
            ; Each entry wholly inside the view, before and after the move, as Draw_ColoredSprite and Draw_RectWorld would
            ; have made it with no cut: strictly inside, so a rect cut to the edge is never taken for whole.
.move       pulu d,x
            std ,y
            tfr x,d             ; A=column, B=line, before
            cmpa #VIEW_COL0
            bls .abort
            cmpb #VIEW_ROW0
            bls .abort
            adda wd_x
            addb wd_x+1
            std 2,y
            cmpa #VIEW_COL0
            bls .abort
            cmpb #VIEW_ROW0
            bls .abort
            pulu d,x            ; A=w, B=h
            std 4,y
            adda 2,y
            cmpa #VIEW_COL0+VIEW_COLS-1
            bhs .abort
            suba wd_x
            cmpa #VIEW_COL0+VIEW_COLS-1
            bhs .abort
            addb 3,y
            cmpb #VIEW_BOTTOM
            bhs .abort
            subb wd_x+1
            cmpb #VIEW_BOTTOM
            bhs .abort
            tfr x,d
            ldb wd_w
            std 6,y
            leay DL_SIZE,y
            dec wq_n
            bne .move
.done       sty <dl_newp
            puls u
            inc tl_rect         ; as Draw_RectWorld does for the big rect
            lda dl_gen
            sta wk_gen
            lda wp3_y+1
            ldb <spr_ox+1
            std wk_y
            lda <spr_oy+1
            ldb wd_g
            std wk_oy
            inc wk_ok
            ldd #0
            rts
.abort      puls u
.no         ldd #1
            rts

; B = how many entries the body has: its parts, and the jaw's rect while it is shut.
p3_body_count
            ldb #P3_PART_COUNT
            tst wd_g
            beq .out
            incb
.out        rts

; D / 8 in B.
wz_shift3   lsra
            rorb
            lsra
            rorb
            lsra
            rorb
            rts

; The body was just drawn the usual way from list index wk_idx. Keeps what it depended on, if every part went into the list
; as one entry: none was off the view, cut at its edge, or dropped from a full list.
p3_body_note
            ldd <dl_newp
            subd <dl_new
            jsr wz_shift3
            subb wk_idx
            pshs b
            jsr p3_body_count
            cmpb ,s+
            bne .out
            tst <still_mode
            bne .out
            lda wp3_y+1
            ldb <spr_ox+1
            std wk_y
            lda <spr_oy+1
            ldb wd_g
            std wk_oy
            lda dl_gen
            sta wk_gen
            inc wk_ok
.out        rts
