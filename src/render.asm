; Drawing code that runs on every camera move. It lives in the fixed ROM at $4000, where there is room.

; Every image has moved, so comparing the lists would find nothing: pair_lists_moved erases the old list and draws the new.
; A=0 for entries in the upper half of the screen, 1 for the lower half.
BLIT_ERASE_X macro
            ldd ,x
            std BLIT_SRC
            ldd 2,x
            std BLIT_DST
            ldd 4,x
            std BLIT_W
            clr BLIT_SOLID
            lda 6,x
            ora #BC_SOLID
            sta BLIT_CTRL
            endm
BLIT_DRAW_U macro
            ldd ,u
            std BLIT_SRC
            ldd 2,u
            std BLIT_DST
            ldd 4,u
            std BLIT_W
            ldd 6,u
            stb BLIT_SOLID
            sta BLIT_CTRL
            endm
; In each half, all its erases and then all its draws. Erasing an old entry after drawing a new one cut the new one wherever
; the two met, and an entry gained or lost earlier in the list puts every pair out of step: then each image of the boss's
; worm was drawn and at once cut by its own old copy, and stayed so for the tick. An entry is the upper half's only if it
; ends above BEAM_MID. One that crosses the middle goes with the lower half, which runs while the beam is in the upper half
; and moving away from it.
pair_lists_moved
            pshs u
            ldx <dl_old
            ldu <dl_new
            tsta
            bne .lower
.ue_next    cmpx <dl_oldend
            bhs .ud_next
            ldb 3,x
            addb 5,x
            bcs .ue_skip
            cmpb #BEAM_MID
            bhi .ue_skip
            BLIT_ERASE_X
.ue_skip    leax DL_SIZE,x
            bra .ue_next
.ud_next    cmpu <dl_newp
            bhs .done
            ldb 3,u
            addb 5,u
            bcs .ud_skip
            cmpb #BEAM_MID
            bhi .ud_skip
            BLIT_DRAW_U
.ud_skip    leau DL_SIZE,u
            bra .ud_next
.done       puls u,pc
.lower
.le_next    cmpx <dl_oldend
            bhs .ld_next
            ldb 3,x
            addb 5,x
            bcs .le_go
            cmpb #BEAM_MID
            bls .le_skip
.le_go      BLIT_ERASE_X
.le_skip    leax DL_SIZE,x
            bra .le_next
.ld_next    cmpu <dl_newp
            bhs .done
            ldb 3,u
            addb 5,u
            bcs .ld_go
            cmpb #BEAM_MID
            bls .ld_skip
.ld_go      BLIT_DRAW_U
.ld_skip    leau DL_SIZE,u
            bra .ld_next

; ---- terrain list ---------------------------------------------------------------------------
; Walking the level's rects and clipping each in 16 bits is too slow to do on every camera step. So the rects near the view
; are kept in RAM, already clipped to the view's lines and sorted by screen half, which also does the job of the blit queue.
; A rect joins or leaves only when the view crosses into a new bucket of the level's x index: on most steps there is only
; each entry's new position to work out. A vertical camera move throws the list away, since lines are clipped into it.
;
; Nearly all terrain is walls one column wide and floors one line high, in one color. When the camera moves one column, such
; a line moves as one blit, from a table holding its color next to black. There are no registers to work out but where it
; goes, which is what makes scrolling cheap. A block's image is the third common case. Whatever else there is goes in a
; short list of its own. So there are four lists, and an entry starts col(2, in the world), then:
;   wall   ctrl(1, its mask of pixels) row(1, video line) h(1)
;   floor  w(1) row(1) lim(1, the first column at which it no longer fits on screen with one more)
;   group of blocks  w(1) row(1) h(1) off(1, lines cut off its top)
;   other  w(1) row(1) h(1) solid(1) ctrl(1)
; Others come first, then walls, and floors after,
; because a wall's erase can clip the end of a line, and the line's repaint heals that. A block has its trailing column erased
; before all of them and is drawn after all of them: it is opaque, and it often has a wall or another block beside it.
TL_COL      equ 0
TL_W        equ 2
TL_MASK     equ 2
TL_OFF      equ 5
TL_BLOCK    equ 6           ; the size of an entry for a group of blocks
TL_ROW      equ 3
TL_H        equ 4
TL_LIM      equ 4
TL_S        equ 5
TL_C        equ 6
TL_SIZE     equ 7
TL_LINE     equ 5           ; the size of an entry for a wall or a floor
TL_RETRY    equ 30          ; camera moves to wait after the list did not fit

tl_rooms_lvl fdb TL_BASE,TL_A_END,TL_B_BASE,TL_B_END,TLF_BASE,TLF_END,TLO_BASE,TLO_END
tl_rooms_boss fdb tl_ram,tl_ram+TLX_A,tl_ram+TLX_A,tl_ram+2*TLX_A,tl_ram+2*TLX_A,tl_ram+2*TLX_A+TLX_F
            fdb tl_ram+2*TLX_A+TLX_F,tl_ram+TL_A_BYTES

; A boss has taken the lower half's RAM: from now on the list keeps to tl_ram. Keeps X, Y, U.
tl_boss     ldd #tl_rooms_boss
            std tl_rooms
            clr tl_valid
            rts

TL_Level    ldd #tl_rooms_lvl
            std tl_rooms
            clr beam_n
            ldd #0
            std rem_acc
            clr gov_load
            clr gov_calm
            ldb #1
            stb gov_mask
            lda #1
            sta rem_dirty
            sta tgt_new         ; no list of targets holds over from another level
            ldb #$FF
            stb mc_cells
            stb mc_cells+4
            stb mc_cells+8
            stb mc_cells+12
            clr heal_n
            clr blk_kills
            clr vl_valid
            clr vl_hold
            rts

; Decides whether this camera step can use the list, and brings the list up to date. The level bank is selected.
tl_prepare  ldd <cam_col
            subd <old_col
            std <scroll_k
            addd #32            ; a jump: not worth following
            cmpd #64
            bhs .off
            tst tl_valid
            bne .window
            tst tl_wait
            beq .build
            dec tl_wait
            rts
.build      clr vl_valid        ; the same RAM
            jsr tl_build
            tst tl_valid
            beq .failed
            bra .use
            ; Add the buckets the view has moved into.
.window     bsr tl_buckets      ; A=low bucket, B=high bucket
            pshs d
.hi         lda tl_hi
            cmpa 1,s
            bhs .lo
            inca
            sta tl_hi
            jsr tl_add_starting
            tst tl_valid
            beq .fail2
            bra .hi
.lo         lda tl_lo
            cmpa ,s
            bls .added
            deca
            sta tl_lo
            jsr tl_add_ending
            tst tl_valid
            beq .fail2
            bra .lo
.added      leas 2,s
.use        lda #1
            sta tl_mode
.off        rts
.fail2      leas 2,s
.failed     lda #TL_RETRY
            sta tl_wait
            rts

; Returns A=the view's low bucket, B=its high bucket.
tl_buckets  ldd <cam_col
            bpl .lo_pos
            ldd #0
.lo_pos     bsr tl_div16
            pshs b
            ldd <cam_col
            addd #VIEW_COLS-1
            bpl .hi_pos
            ldd #0
.hi_pos     bsr tl_div16
            puls a,pc
tl_div16    lsra
            rorb
            lsra
            rorb
            lsra
            rorb
            lsra
            rorb
            rts

; A full build: every rect touching the view's buckets.
tl_build    ldx tl_rooms
            ldd TR_A0,x
            std tla_t
            ldd TR_A1,x
            std tla_k
            ldd TR_B0,x
            std tlb_t
            ldd TR_B1,x
            std tlb_k
            ldd TR_F0,x
            std tlf_a
            ldd TR_F1,x
            std tlf_b
            ldd TR_O0,x
            std tlo_a
            ldd TR_O1,x
            std tlo_b
            lda #1
            sta tl_valid
            bsr tl_buckets
            sta tl_lo
            stb tl_hi
            ldd <cam_col
            addd #VIEW_COLS
            std <t1
            ldd <cam_col
            jsr terrain_range
            ldd <t1
            std tl_stop
.next       cmpy tl_stop
            bhs .done
            jsr tl_insert
            tst tl_valid
            beq .done
            leay 8,y
            bra .next
.done       rts

; A=bucket. Y=its first rect by the word at offset B of its index entry (0 = reaching it, 2 = starting in it).
tl_index    pshs b
            tfr a,b
            clra
            aslb
            rola
            aslb
            rola
            cmpd <lvl_index_max
            bls .ok
            ldd <lvl_index_max
.ok         addd <lvl_index
            addb ,s+
            adca #0
            tfr d,x
            ldd ,x
            addd <lvl_rects
            tfr d,y
            rts

; A=bucket just added at the high end: the rects that start in it.
tl_add_starting
            pshs a
            inca
            ldb #2
            bsr tl_index
            sty tl_stop
            puls a
            ldb #2
            bsr tl_index
.next       cmpy tl_stop
            bhs .done
            jsr tl_insert
            tst tl_valid
            beq .done
            leay 8,y
            bra .next
.done       rts

; A=bucket just added at the low end: the rects that end in it. Others reaching it are in the list already.
tl_add_ending
            pshs a
            inca
            ldb #2
            bsr tl_index
            sty tl_stop
            lda ,s
            clrb
            bsr tl_index
.next       cmpy tl_stop
            bhs .done
            ldb 4,y
            clra
            addd ,y
            subd #1
            lbsr tl_div16
            cmpb ,s
            bne .skip
            jsr tl_insert
            tst tl_valid
            beq .done
.skip       leay 8,y
            bra .next
.done       puls a,pc

; Y=rect. Clips it to the view's lines and adds it, as two entries if it crosses the middle of the screen. Keeps Y.
; Clears tl_valid when there is no room.
tl_insert   lda 7,y
            bita #RECT_HIDE
            beq .shown
            jsr [rect_hidden_v]
            bcc .shown
            rts
.shown      lda 7,y
            bita #RECT_IMAGE
            beq tl_insert1
            tst blk_kills
            beq tl_insert1
            ; A group with a block gone goes in block by block.
            jsr blk_group_any
            beq tl_insert1
            ldx #tl_insert1
            jmp blk_split

tl_insert1  ldd 2,y
            subd <cam_top
            bpl .below
            addb 5,y            ; starts above the view
            adca #0
            lbne .out
            tstb
            lbeq .out
            pshs b
            lda 5,y
            suba ,s+
            sta tl_cut          ; lines cut off its top
            cmpb #VIEW_H
            bls .h1
            ldb #VIEW_H
.h1         stb tl_ht
            ldb #VIEW_ROW0
            stb tl_r
            bra .band
.below      cmpd #VIEW_H
            lbhs .out
            clr tl_cut
            addb #VIEW_ROW0
            stb tl_r
            subb #VIEW_ROW0
            lda #VIEW_H         ; lines left
            pshs b
            suba ,s+
            ldb 5,y
            pshs a
            cmpb ,s+
            bls .h2
            tfr a,b
.h2         stb tl_ht
.band       lda tl_r
            cmpa #BEAM_MID
            bhs .lower
            adda tl_ht
            cmpa #BEAM_MID
            bls .upper
            suba #BEAM_MID      ; A = its lines in the lower half
            pshs a
            ldb tl_ht
            subb ,s
            stb tl_ht
            bsr .upper
            lda tl_cut
            adda tl_ht
            sta tl_cut
            puls a
            sta tl_ht
            lda #BEAM_MID
            sta tl_r
.lower      ldx #tlb_t
            bra .put
.upper      ldx #tla_t
            ; A rect the boss's regions can hide is sorted as the rect it is: as an other it was drawn before the walls,
            ; whose erases then cut its ends. Nor does the flag reach the blitter, where it is the slow bit.
.put        lda 7,y
            anda #~RECT_HIDE&$FF
            sta tl_k
            bita #RECT_IMAGE
            lbne .block
            lda 4,y
            cmpa #1
            bne .notwall
            ldb 6,y
            cmpb #LINE_SOLID
            beq .wall_ok
            cmpb #LINE_SOLID&$0F
            beq .wall_ok
            cmpb #LINE_SOLID&$F0
            lbne .other
            ; A wall, unless it is really a dot of a floor: those are floors.
.wall_ok    lda 5,y
            cmpa #SCROLL_FLAT
            bhi .wall
            tst tl_k
            bne .wall
.notwall    lda 5,y
            cmpa #1
            bne .other
            tst tl_k
            bne .other
            lda 6,y
            cmpa #LINE_SOLID
            bne .other
            ; A floor.
            cmpx #tla_t
            bne .f_lower
            ldd tlf_a
            addd #TL_LINE
            cmpd tlf_b
            bhi .full
            std tlf_a
            subd #TL_LINE
            bra .f_put
.f_lower    ldd tlf_b
            subd #TL_LINE
            cmpd tlf_a
            blo .full
            std tlf_b
.f_put      tfr d,x
            ldd ,y
            std TL_COL,x
            lda 4,y
            sta TL_W,x
            lda tl_r
            sta TL_ROW,x
            ldb #VIEW_COLS
            subb 4,y
            bcc .lim
            clrb
.lim        stb TL_LIM,x
.out        rts
.full       clr tl_valid
            rts
.wall       ldd ,x
            addd #TL_LINE
            cmpd 2,x
            bhi .full
            std ,x
            subd #TL_LINE
            tfr d,x
            ldd ,y
            std TL_COL,x
            lda tl_k
            ora #BC_DST256
            sta TL_MASK,x
            lda tl_r
            sta TL_ROW,x
            lda tl_ht
            sta TL_H,x
            rts
.other      cmpx #tla_t
            bne .o_lower
            ldd tlo_a
            addd #TL_SIZE
            cmpd tlo_b
            bhi .full
            std tlo_a
            subd #TL_SIZE
            bra .o_put
.o_lower    ldd tlo_b
            subd #TL_SIZE
            cmpd tlo_a
            blo .full
            std tlo_b
.o_put      tfr d,x
            ldd ,y
            std TL_COL,x
            lda 4,y
            sta TL_W,x
            lda tl_r
            sta TL_ROW,x
            lda tl_ht
            sta TL_H,x
            lda 6,y
            sta TL_S,x
            lda tl_k
            ora #BC_SOLID+BC_DST256
            sta TL_C,x
            rts
.block      ldd 2,x
            subd #TL_BLOCK
            cmpd ,x
            lblo .full
            std 2,x
            tfr d,x
.k_put      ldd ,y
            std TL_COL,x
            lda 4,y
            sta TL_W,x
            lda tl_cut
            sta TL_OFF,x
            lda tl_r
            sta TL_ROW,x
            lda tl_ht
            sta TL_H,x
.out2       rts

; D=a column relative to the view, tl_wv=width. Returns B=first visible column, A=width; A is 0 and Z set if none is visible.
tl_span     tsta
            bmi .left
            bne .none
            cmpb #VIEW_COLS
            bhs .none
            ; Starts in the view: width = min(w, columns left).
            lda #VIEW_COLS
            stb <t4
            suba <t4
            cmpa tl_wv
            bls .ok
            lda tl_wv
.ok         tsta
            rts
.left       addb tl_wv          ; starts left of it: what remains
            adca #0
            bne .none
            tfr b,a
            clrb
            cmpa #VIEW_COLS
            bls .ok2
            lda #VIEW_COLS
.ok2        tsta
            rts
.none       clra
            rts

; The lists of one half, in their order.
tl_upper    ldy tla_k
            ldx tl_rooms
            ldx TR_A1,x
            jsr tl_blk_erase
            ldy tl_rooms
            ldy TR_O0,y
            ldx tlo_a
            bsr tl_others
            ldy tl_rooms
            ldy TR_A0,y
            ldx tla_t
            jsr tl_walls
            ldy tl_rooms
            ldy TR_F0,y
            ldx tlf_a
            jsr tl_flats
            ldy tla_k
            ldx tl_rooms
            ldx TR_A1,x
            jmp tl_blk_draw
tl_lower    ldy tlb_k
            ldx tl_rooms
            ldx TR_B1,x
            jsr tl_blk_erase
            ldy tlo_b
            ldx tl_rooms
            ldx TR_O1,x
            bsr tl_others
            ldy tl_rooms
            ldy TR_B0,y
            ldx tlb_t
            jsr tl_walls
            ldy tlf_b
            ldx tl_rooms
            ldx TR_F1,x
            jsr tl_flats
            ldy tlb_k
            ldx tl_rooms
            ldx TR_B1,x
            jmp tl_blk_draw

; Y=first entry, X=end. Erases each entry where it was and draws it where it is. The camera's move is in scroll_k.
; The blitter keeps its registers, so what the erase and draw share is written once.
tl_others   stx <t1
            tfr y,x
.next       cmpx <t1
            lbhs .done
            ; A solid rect, such as lava, keeps most of its pixels: only the end that trails is erased.
            lda TL_C,x
            cmpa #BC_SOLID+BC_DST256
            lbne .pair
            lda TL_H,x
            sta BLIT_H
            lda TL_S,x
            sta tl_fs
            ; All of it in view: its middle does not change, so only its ends are drawn. What erases across it leaves a hole,
            ; which waits for the next step that paints all of it.
            tst tl_rep
            bne .whole
            lda TL_W,x
            cmpa #3
            blo .whole
            ldd TL_COL,x
            subd <cam_col
            tsta
            bne .whole
            stb <t2
            addb TL_W,x
            bcs .whole
            cmpb #VIEW_COLS-1
            bhs .whole
            stb <t3
            ; Two columns where it advances: the wall beside it, moved after it, clips the first of them, and this heals that.
            ldd <scroll_k
            cmpd #1
            bne .e_right
            lda <t2             ; moved left: draw its new first two columns, erase its old last one
            ldb <t3
            bra .e_go
.e_right    cmpd #-1
            bne .whole
            ldb <t2             ; moved right: draw its new last two columns, erase its old first one
            beq .whole
            decb
            lda <t3
            suba #2
.e_go       adda #VIEW_COL0
            addb #VIEW_COL0
            sta BLIT_DST
            stb <t4
            lda TL_ROW,x
            sta BLIT_DST+1
            lda #2
            sta BLIT_W
            lda tl_fs
            sta BLIT_SOLID
            lda #BC_SOLID+BC_DST256
            sta BLIT_CTRL
            ldb <t4
            stb BLIT_DST
            ldb #1
            stb BLIT_W
            clr BLIT_SOLID
            sta BLIT_CTRL
            leax TL_SIZE,x
            lbra .next
.whole      ldd TL_COL,x
            subd <cam_col
            jsr tl_flat_edge
            leax TL_SIZE,x
            lbra .next
.pair       lda TL_ROW,x
            sta BLIT_DST+1
            lda TL_H,x
            sta BLIT_H
            ldd TL_COL,x
            subd <cam_col
            std <t2
            addd <scroll_k      ; where it was
            ; Most stay wholly in view, which makes the two spans simple. One write of the width does for both.
            tsta
            bne .span
            stb <t3
            addb TL_W,x
            bcs .span
            cmpb #VIEW_COLS
            bhi .span
            lda <t2
            bne .span
            lda <t2+1
            adda TL_W,x
            bcs .span
            cmpa #VIEW_COLS
            bhi .span
            lda TL_W,x
            sta BLIT_W
            lda <t3
            adda #VIEW_COL0
            sta BLIT_DST
            clr BLIT_SOLID
            lda TL_C,x
            sta BLIT_CTRL
            ldb <t2+1
            addb #VIEW_COL0
            stb BLIT_DST
            ldb TL_S,x
            stb BLIT_SOLID
            sta BLIT_CTRL
            leax TL_SIZE,x
            lbra .next
.span       lda TL_W,x
            sta tl_wv
            ldd <t2
            addd <scroll_k
            lbsr tl_span
            beq .noerase
            sta BLIT_W
            addb #VIEW_COL0
            stb BLIT_DST
            clr BLIT_SOLID
            lda TL_C,x
            sta BLIT_CTRL
.noerase    ldd <t2
            lbsr tl_span
            beq .skip
            sta BLIT_W
            addb #VIEW_COL0
            stb BLIT_DST
            lda TL_S,x
            sta BLIT_SOLID
            lda TL_C,x
            sta BLIT_CTRL
.skip       leax TL_SIZE,x
            lbra .next
.done       rts

; D, 16 bits, clamped to 0..VIEW_COLS, in B.
TL_CLAMP    macro
            tsta
            bmi .z\@
            bne .m\@
            cmpb #VIEW_COLS
            bls .o\@
.m\@        ldb #VIEW_COLS
            bra .o\@
.z\@        clrb
.o\@
            endm

; Y=first entry, X=end. Walls, for a camera move of one column: one blit each, unless the wall is at the edge of the view.
; The source steps two bytes a line through color and black. The wall's mask keeps the other pixel of each byte.
tl_walls    stx <t1
            cmpy <t1
            lbhs .done
            tfr y,x
            ldd #TAB_ALT
            std BLIT_SRC
            lda #2
            sta BLIT_W
            ldd <scroll_k
            cmpd #1
            beq .left
            cmpd #-1
            beq .right
.any        ldd TL_COL,x
            subd <cam_col
            bsr tl_wall_edge
            leax TL_LINE,x
            cmpx <t1
            blo .any
            rts
            ; The view moved right, so the wall moved left: color, then black.
.l_edge     bsr tl_wall_edge
            bra .l_on
.left       ldd TL_COL,x        ; 5
            subd <cam_col       ; 6
            tsta                ; 2
            bne .l_edge         ; 3
            cmpb #VIEW_COLS-1   ; 2
            bhs .l_edge         ; 3
            addb #VIEW_COL0     ; 2
            stb BLIT_DST        ; 5
            ldd TL_ROW,x        ; 6: row and height
            sta BLIT_DST+1      ; 5
            stb BLIT_H          ; 5
            lda TL_MASK,x       ; 5
            sta BLIT_CTRL       ; 5
.l_on       leax TL_LINE,x      ; 5
            cmpx <t1            ; 6
            blo .left           ; 3
            rts
            ; The view moved left, so the wall moved right: black, then color.
.r_edge     bsr tl_wall_edge
            ldd #TAB_ALT+1
            std BLIT_SRC
            bra .r_on
.right      ldd #TAB_ALT+1
            std BLIT_SRC
.r_next     ldd TL_COL,x
            subd <cam_col
            tsta
            bne .r_edge
            decb
            cmpb #VIEW_COLS-1
            bhs .r_fix
            addb #VIEW_COL0
            stb BLIT_DST
            ldd TL_ROW,x
            sta BLIT_DST+1
            stb BLIT_H
            lda TL_MASK,x
            sta BLIT_CTRL
.r_on       leax TL_LINE,x
            cmpx <t1
            blo .r_next
.done       rts
.r_fix      incb
            bra .r_edge

; X=wall, D=its column relative to the view: a wall at the edge, or a move of more than one column. An erase and a draw, each
; only if it is in the view. Leaves the blitter ready for the fast loops.
tl_wall_edge
            std <t2
            ldd TL_ROW,x
            sta BLIT_DST+1
            stb BLIT_H
            lda #1
            sta BLIT_W
            ldd <t2
            addd <scroll_k
            tsta
            bne .draw
            cmpb #VIEW_COLS
            bhs .draw
            addb #VIEW_COL0
            stb BLIT_DST
            clr BLIT_SOLID
            lda TL_MASK,x
            ora #BC_SOLID
            sta BLIT_CTRL
.draw       ldd <t2
            tsta
            bne .out
            cmpb #VIEW_COLS
            bhs .out
            addb #VIEW_COL0
            stb BLIT_DST
            lda #LINE_SOLID
            sta BLIT_SOLID
            lda TL_MASK,x
            ora #BC_SOLID
            sta BLIT_CTRL
.out        lda #2
            sta BLIT_W
            rts

; Y=first entry, X=end. Floors. A floor is repainted in full: its pixels stay still on screen while sprites slide across them,
; so otherwise each erase of a sprite would leave a hole that stays. In one blit, its trailing end included, when it is wholly
; in view and the camera moved one column.
tl_flats    stx <t1
            cmpy <t1
            lbhs .done
            tfr y,x
            ldd #TAB_FLAT
            std BLIT_SRC
            lda #LINE_SOLID
            sta tl_fs
            lda #1
            sta BLIT_H
            ldd <scroll_k
            cmpd #1
            beq .left
            cmpd #-1
            lbeq .right
.any        ldd TL_COL,x
            subd <cam_col
            lbsr tl_flat_edge
            leax TL_LINE,x
            cmpx <t1
            blo .any
.done       rts
            ; The view moved right, so the floor moved left: color, then black. A floor over the edge of the view is
            ; the same with its ends worked out.
.l_edge     std <t2             ; start
            ldb TL_W,x
            clra
            addd <t2
            std <t3             ; end
            bmi .l_next         ; wholly left of the view, trailing end too
            ldd <t2
            bpl .l_a
            clrb                ; a = max(start, 0)
            bra .l_row
.l_a        tsta
            bne .l_next
            cmpb #VIEW_COLS
            bhs .l_next
.l_row      stb <t4
            addb #VIEW_COL0
            stb BLIT_DST
            lda TL_ROW,x
            sta BLIT_DST+1
            ldd <t3
            tsta
            bne .l_solid
            cmpb #VIEW_COLS
            bhs .l_solid
            ; Its old end is in view: color from a up to the end, then one black.
            subb <t4
            incb
            stb BLIT_W
            negb
            addb #(TAB_FLAT+TAB_COLS+2)&$FF
            stb BLIT_SRC+1
            lda #BC_DST256
            sta BLIT_CTRL
            bra .l_on
.l_solid    ldb #VIEW_COLS      ; no end in view: all that shows, in one color
            subb <t4
            stb BLIT_W
            lda #LINE_SOLID
            sta BLIT_SOLID
            lda #BC_SOLID+BC_DST256
            sta BLIT_CTRL
.l_on
.l_next     leax TL_LINE,x
            cmpx <t1
            blo .left
            rts
.left       ldd TL_COL,x        ; 5
            subd <cam_col       ; 6
            tsta                ; 2
            bne .l_edge         ; 3
            cmpb TL_LIM,x       ; 5
            bhs .l_edge         ; 3
            addb #VIEW_COL0     ; 2
            stb BLIT_DST        ; 5
            lda TL_ROW,x        ; 5
            sta BLIT_DST+1      ; 5
            ldb TL_W,x          ; 5
            incb                ; 2
            stb BLIT_W          ; 5
            negb                ; 2
            addb #(TAB_FLAT+TAB_COLS+2)&$FF    ; 2
            stb BLIT_SRC+1      ; 5
            lda #BC_DST256      ; 2
            sta BLIT_CTRL       ; 5
            leax TL_LINE,x      ; 5
            cmpx <t1            ; 6
            blo .left           ; 3
            rts
            ; The view moved left, so the floor moved right: black, then color.
.r_edge     std <t2             ; start
            ldb TL_W,x
            clra
            addd <t2
            ble .r_on           ; wholly left of the view
            cmpd #VIEW_COLS
            bls .r_b
            ldd #VIEW_COLS
.r_b        stb <t3             ; b = min(end, view)
            ldd <t2
            bmi .r_whole        ; starts left of it, and so does its old start
            beq .r_whole
            tsta
            bne .r_on
            cmpb #VIEW_COLS
            bhi .r_on
            ; Its old start, one before this, is in view: one black, then color up to b. A start past the last column has
            ; only that black left to draw.
            decb
            stb <t4
            addb #VIEW_COL0
            stb BLIT_DST
            lda TL_ROW,x
            sta BLIT_DST+1
            ldb <t3
            subb <t4
            stb BLIT_W
            lda #TAB_FLAT&$FF
            sta BLIT_SRC+1
            lda #BC_DST256
            sta BLIT_CTRL
            bra .r_on
.r_whole    lda TL_ROW,x
            sta BLIT_DST+1
            lda #VIEW_COL0
            sta BLIT_DST
            ldb <t3
            stb BLIT_W
            lda #LINE_SOLID
            sta BLIT_SOLID
            lda #BC_SOLID+BC_DST256
            sta BLIT_CTRL
            bra .r_on
.right      ldb #TAB_FLAT&$FF
            stb BLIT_SRC+1
.r_next     ldd TL_COL,x
            subd <cam_col
            tsta
            bne .r_edge
            decb
            cmpb TL_LIM,x
            lbhs .r_fix
            addb #VIEW_COL0
            stb BLIT_DST
            lda TL_ROW,x
            sta BLIT_DST+1
            ldb TL_W,x
            incb
            stb BLIT_W
            lda #BC_DST256
            sta BLIT_CTRL
.r_on       leax TL_LINE,x
            cmpx <t1
            lblo .r_next
            rts
.r_fix      incb
            lbra .r_edge

; X=floor or other solid rect, D=its column relative to the view, tl_fs=its color, with the blitter's height set: an end is
; outside the view, or the move was more than one column. Erases its trailing end, then draws all that shows. Leaves the source as the loop going right wants it.
tl_flat_edge
            std <t2             ; new start
            lda TL_ROW,x
            sta BLIT_DST+1
            tst <scroll_k
            bmi .rightward
            ; The view moved right, so the rect moved left: the right end trails.
            ldb TL_W,x
            clra
            addd <t2
            std <t3             ; new end
            TL_CLAMP
            stb <t4
            ldd <t3
            addd <scroll_k
            TL_CLAMP
            bra .erase
            ; The view moved left, so the rect moved right: the left end trails.
.rightward  ldd <t2
            addd <scroll_k
            TL_CLAMP
            stb <t4
            ldd <t2
            TL_CLAMP
.erase      subb <t4            ; B = width of the part to erase
            bls .draw
            stb BLIT_W
            lda <t4
            adda #VIEW_COL0
            sta BLIT_DST
            clr BLIT_SOLID
            lda #BC_SOLID+BC_DST256
            sta BLIT_CTRL
.draw       lda TL_W,x
            sta tl_wv
            ldd <t2
            jsr tl_span
            beq .out
            sta BLIT_W
            addb #VIEW_COL0
            stb BLIT_DST
            lda tl_fs
            sta BLIT_SOLID
            lda #BC_SOLID+BC_DST256
            sta BLIT_CTRL
.out        rts

; Y=first entry, X=end. The trailing column of each group of blocks, ahead of everything else in its half. One at the edge of the
; view, or moving further than a column, has all of where it was erased.
tl_blk_erase
            stx <t1
            cmpy <t1
            lbhs .done
            tfr y,x
            clr BLIT_SOLID
            lda #1
            sta BLIT_W
            ldd <scroll_k
            cmpd #1
            beq .left
            cmpd #-1
            beq .right
.any        ldd TL_COL,x
            subd <cam_col
            bsr tl_blk_wipe
            leax TL_BLOCK,x
            cmpx <t1
            blo .any
.done       rts
.l_edge     bsr tl_blk_wipe
            bra .l_on
.left       ldd TL_COL,x
            subd <cam_col
            tsta
            bne .l_edge
            stb <t2
            addb TL_W,x
            bcs .l_fix
            cmpb #VIEW_COLS
            bhs .l_fix
            addb #VIEW_COL0
            stb BLIT_DST
            ldd TL_ROW,x
            sta BLIT_DST+1
            stb BLIT_H
            lda #BC_SOLID+BC_DST256
            sta BLIT_CTRL
.l_on       leax TL_BLOCK,x
            cmpx <t1
            blo .left
            rts
.l_fix      clra
            ldb <t2
            bra .l_edge
.r_edge     bsr tl_blk_wipe
            bra .r_on
.right      ldd TL_COL,x
            subd <cam_col
            tsta
            bne .r_edge
            stb <t2
            addb TL_W,x
            bcs .r_fix
            cmpb #VIEW_COLS
            bhi .r_fix
            ldb <t2
            decb
            cmpb #VIEW_COLS
            bhs .r_fix
            addb #VIEW_COL0
            stb BLIT_DST
            ldd TL_ROW,x
            sta BLIT_DST+1
            stb BLIT_H
            lda #BC_SOLID+BC_DST256
            sta BLIT_CTRL
.r_on       leax TL_BLOCK,x
            cmpx <t1
            blo .right
            rts
.r_fix      clra
            ldb <t2
            bra .r_edge

; X=group, D=its new column relative to the view. Erases what shows of it where it was. Keeps X.
tl_blk_wipe addd <scroll_k
            pshs d
            lda TL_W,x
            sta tl_wv
            ldd TL_ROW,x
            sta BLIT_DST+1
            stb BLIT_H
            puls d
            jsr tl_span
            beq .out
            sta BLIT_W
            addb #VIEW_COL0
            stb BLIT_DST
            lda #BC_SOLID+BC_DST256
            sta BLIT_CTRL
.out        lda #1
            sta BLIT_W
            rts

; Y=first entry, X=end. Each group's image where it is now, last in its half. A page of the image for each column.
tl_blk_draw stx <t1
            cmpy <t1
            lbhs .done
            tfr y,x
            lda #BLOCK_PAGE
            sta BLIT_SRC
.next       ldd TL_COL,x
            subd <cam_col
            tsta
            bne .edge
            stb <t2
            lda TL_W,x
            sta BLIT_W
            adda <t2
            bcs .fix
            cmpa #VIEW_COLS
            bhi .fix
            addb #VIEW_COL0
            stb BLIT_DST
            ldd TL_ROW,x
            sta BLIT_DST+1
            stb BLIT_H
            lda TL_OFF,x
            sta BLIT_SRC+1
            lda #BC_DST256+BC_SRC256
            sta BLIT_CTRL
.on         leax TL_BLOCK,x
            cmpx <t1
            blo .next
.done       rts
.fix        clra
            ldb <t2
            ; Cut off by the edge of the view: what shows starts further along the image.
.edge       std <t2
            lda TL_W,x
            sta tl_wv
            ldd <t2
            jsr tl_span
            beq .on
            sta BLIT_W
            addb #VIEW_COL0
            stb BLIT_DST
            ldd <t2
            bpl .cut
            negb
            bra .cutb
.cut        clrb
.cutb       addb #BLOCK_PAGE
            stb BLIT_SRC
            ldd TL_ROW,x
            sta BLIT_DST+1
            stb BLIT_H
            lda TL_OFF,x
            sta BLIT_SRC+1
            lda #BC_DST256+BC_SRC256
            sta BLIT_CTRL
            lda #BLOCK_PAGE
            sta BLIT_SRC
            bra .on

; Y=a group of blocks' rect, X=a routine. Calls it with Y=a rect of one block, for each block not destroyed. Keeps Y. Sets blk_nw and
; blk_nh, its size in blocks.
blk_split   stx blk_fn
            pshs y
            ldd ,y
            std blk_x0
            ldd 2,y
            std blk_cy
            clr blk_nw
            lda 4,y
.w          inc blk_nw
            suba #BLOCK_COLS
            bne .w
            clr blk_nh
            lda 5,y
.h          inc blk_nh
            suba #BLOCK_LINES
            bne .h
            lda blk_nh
            sta blk_ny
            ; The changed bit of the group's first cell, found once: each block is the next bit, each row cls_stride bytes on.
            ; 0,s this block's mask, 1,s its byte; 3,s and 4,s the same for the row's first.
            ldd <t0
            pshs d
            ldd <t1
            pshs d
            ldd <t2
            pshs d
            jsr blk_origin
            jsr cell_changed    ; X=its byte, B=its mask
            pshs b,x
            ldd 3,s
            std <t2
            ldd 5,s
            std <t1
            ldd 7,s
            std <t0
            ldb ,s
            ldx 1,s
            leas 9,s
            pshs b,x
            pshs b,x
.row        ldd blk_x0
            std blk_cx
            lda blk_nw
            sta blk_nx
.col        ldb ,s
            bitb [1,s]
            bne .next           ; destroyed
            ldd blk_cx
            std blk_tmp
            ldd blk_cy
            std blk_tmp+2
            ldd #BLOCK_COLS*256+BLOCK_LINES
            std blk_tmp+4
            ldd #RECT_IMAGE
            std blk_tmp+6
            ldy #blk_tmp
            ldx blk_fn
            jsr ,x
.next       ldd blk_cx
            addd #BLOCK_COLS
            std blk_cx
            lsl ,s
            bne .bit
            inc ,s
            ldx 1,s
            leax 1,x
            stx 1,s
.bit        dec blk_nx
            bne .col
            ldd blk_cy
            addd #BLOCK_LINES
            std blk_cy
            ldd 4,s
            addb <cls_stride
            adca #0
            std 4,s
            std 1,s
            lda 3,s
            sta ,s
            dec blk_ny
            bne .row
            leas 6,s
            puls y,pc

; After drawing: drops the buckets the view has left, and the entries that no longer touch any bucket held.
tl_trim     jsr tl_buckets
            cmpa tl_lo
            bne .trim
            cmpb tl_hi
            lbeq .out
.trim       sta tl_lo
            stb tl_hi
            ldd #TL_LINE
            std <t3
            lda #1              ; walls: one column
            sta <t4
            ldx tl_rooms
            ldx TR_A0,x
            ldy #tla_t
            lbsr tl_trim_up
            ldx tl_rooms
            ldx TR_B0,x
            ldy #tlb_t
            lbsr tl_trim_up
            clr <t4             ; these hold their width
            ldd #TL_BLOCK
            std <t3
            ldy #tla_k
            ldx tl_rooms
            ldd TR_A1,x
            lbsr tl_trim_down
            ldy #tlb_k
            ldx tl_rooms
            ldd TR_B1,x
            lbsr tl_trim_down
            ldd #TL_LINE
            std <t3
            ldx tl_rooms
            ldx TR_F0,x
            ldy #tlf_a
            lbsr tl_trim_up
            ldy #tlf_b
            ldx tl_rooms
            ldd TR_F1,x
            lbsr tl_trim_down
            ldd #TL_SIZE
            std <t3
            ldx tl_rooms
            ldx TR_O0,x
            ldy #tlo_a
            lbsr tl_trim_up
            ldy #tlo_b
            ldx tl_rooms
            ldd TR_O1,x
            lbsr tl_trim_down
.out        rts

; X=entry, t4=the list's width, or 0 for the entry's own. Z set if it no longer touches a bucket held.
tl_gone     ldd TL_COL,x
            jsr tl_div16
            cmpb tl_hi
            bhi .yes
            ldb <t4
            bne .wide
            ldb TL_W,x
.wide       clra
            addd TL_COL,x
            subd #1
            jsr tl_div16
            cmpb tl_lo
            blo .yes
            andcc #$FB
            rts
.yes        orcc #$04
            rts

; X=first, Y=the variable holding the end, t3=entry size. Moves the last entry over each one that goes.
tl_trim_up
.next       cmpx ,y
            bhs .done
            bsr tl_gone
            bne .keep
            ldd ,y
            subd <t3
            std ,y
            pshs y
            tfr d,y
            bsr tl_copy
            puls y
            bra .next
.keep       ldb <t3+1
            abx
            bra .next
.done       rts

; Y=the variable holding the start, D=the end, t3=entry size. Moves the first entry over each one that goes.
tl_trim_down
            std <t1
            ldx ,y
.next       cmpx <t1
            bhs .done
            bsr tl_gone
            bne .keep
            ldd ,y
            pshs y
            tfr d,y
            bsr tl_copy
            puls y
            ldd <t3
            addd ,y
            std ,y
.keep       ldb <t3+1
            abx
            bra .next
.done       rts

; Copies the entry at Y to X. Keeps X and Y.
tl_copy     pshs y,x
            ldb <t3+1
.next       lda ,y+
            sta ,x+
            decb
            bne .next
            puls x,y,pc

; A block died: the lists are made again, leaving it out.
tl_block_gone
            clr vl_valid
            clr tl_valid
            rts

; ---- rects near the view, for a vertical camera move --------------------------------------------
; The terrain list is clipped to the view's lines, so a vertical step cannot use it, and the level's rects are not indexed by
; line, so a walk visits every rect in these columns, on a tall level several times what is in view. So this keeps pointers to
; the rects near the view, in the RAM of the terrain list. Only one of the two is valid at a time.
;
; When the camera moves only vertically, a wall changes only at its ends and a floor is a short erase and draw. Nothing is ever
; missing from the screen for long, so there is no need to time this to the beam or to have every erase come first. The order
; is what keeps terrain whole: a wall's trailing end goes first, then floors as pairs, since a floor's erase can clip a wall,
; then the walls are all drawn, which heals that. Blocks are opaque, so they are erased with the walls and drawn last.
VL_BASE     equ tl_ram          ; walls grow up from here and floors and the rest grow down from VL_MID
VL_MID      equ tl_ram+470
VL_END      equ tl_ram+TL_A_BYTES ; blocks grow up from VL_MID to here
VL_MX       equ 16              ; columns kept beyond the view on each side
VL_MY       equ 40              ; lines kept beyond it above and below
VL_BIG     equ 64              ; a vertical move this big or bigger takes the long way round
VL_STEPS     equ 2               ; sideways camera steps that also use these rects after a vertical one, so that a diagonal
                                ; does not rebuild the terrain list on every step

; The level's bank is selected. Moves the terrain. Clears vl_valid and does nothing if the rects did not fit.
vl_step     tst vl_valid
            beq .build
            ldd <cam_col
            bsr .in_cols
            blo .build
            ldd <old_col
            bsr .in_cols
            blo .build
            ldd <cam_top
            bsr .in_rows
            blo .build
            ldd <old_top
            bsr .in_rows
            bhs .go
.build      jsr vl_build
            tst vl_valid
            beq .out
.go         pshs u
            clr vl_any
            ldd <cam_top
            subd <old_top
            std vl_dy
            ldd <cam_col
            subd <old_col
            std <scroll_k
            ; A small step straight up or down is the case worth the short path.
            bne .any
            ldd vl_dy
            beq .any
            addd #VL_BIG
            cmpd #VL_BIG*2
            blo .walls
.any        inc vl_any
.walls      jsr vl_walls_find
            jsr vl_walls_first
            jsr vl_flats_all
            jsr vl_walls_draw
            jsr vl_blocks_draw
            puls u
.out        rts
            ; D=first column: carry set if the view from there is not within the rects kept.
.in_cols    cmpd vl_c0
            blt .no
            addd #VIEW_COLS
            cmpd vl_c1
            bgt .no
            andcc #$FE
            rts
.in_rows    cmpd vl_r0
            blt .no
            addd #VIEW_H
            cmpd vl_r1
            bgt .no
            andcc #$FE
            rts
.no         orcc #$01
            rts

; Lists the rects near both the view last drawn and the view to draw.
vl_build    clr tl_valid
            clr vl_valid
            ldd <cam_top
            cmpd <old_top
            ble .r_lo
            ldd <old_top
.r_lo       subd #VL_MY
            std vl_r0
            ldd <cam_top
            cmpd <old_top
            bge .r_hi
            ldd <old_top
.r_hi       addd #VIEW_H+VL_MY
            std vl_r1
            ldd <cam_col
            cmpd <old_col
            bge .c_hi
            ldd <old_col
.c_hi       addd #VIEW_COLS+VL_MX
            std vl_c1
            std <t1
            ldd <cam_col
            cmpd <old_col
            ble .c_lo
            ldd <old_col
.c_lo       subd #VL_MX
            std vl_c0
            jsr terrain_range
            ldd <t1
            std vl_stop
            ldd #VL_BASE
            std vl_w
            ldd #VL_MID
            std vl_f
            std vl_b
.next       cmpy vl_stop
            bhs .done
            ; Within the lines kept? Across every level this is what most rects fail.
            ldd 2,y
            cmpd vl_r1
            bge .skip
            ldb 5,y
            clra
            addd 2,y
            cmpd vl_r0
            ble .skip
            lda 7,y
            bita #RECT_HIDE
            bne .hide
.kind       bita #RECT_IMAGE
            bne .block
            ldb 4,y
            decb
            bne .flat           ; wider than a column
            tsta
            bne .wall
            lda 5,y
            cmpa #SCROLL_FLAT
            bls .flat
.wall       ldx vl_w
            leax 2,x
            cmpx vl_f
            bhi .out
            stx vl_w
            sty -2,x
            bra .skip
.flat       ldx vl_f
            leax -2,x
            cmpx vl_w
            blo .out
            stx vl_f
            sty ,x
            bra .skip
.block      ldx vl_b
            cmpx #VL_END-1
            bhs .out
            sty ,x++
            stx vl_b
.skip       leay 8,y
            bra .next
.done       lda #1
            sta vl_valid
            ldd #$7FFF          ; no view is here: the walls in view must be found
            std vl_wcol
.out        rts
.hide       jsr [rect_hidden_v]
            bcs .skip
            lda 7,y
            anda #~RECT_HIDE&$FF ; sorted as the rect it was before it was cut
            bra .kind

; Level 9's bank holds rect_hidden (boss_terrain.asm), and only its rects are marked RECT_HIDE, so the terrain routines,
; which have the level's bank in view, call it through this.
rect_hidden_v fdb rect_hidden

; X=address in the level's bank: A=the byte there, X one past it. For code in a bank of its own, which cur_bank names.
; Keeps B, Y, U.
lvl_byte    lda <level_bank
            sta BANK_SELECT
            lda ,x+
            pshs a
            lda <cur_bank
            sta BANK_SELECT
            puls a,pc

; Y=rect one column wide: puts it in the blitter's destination column. Z set if it is not in the view.
VL_COL      macro skip
            ldd ,y
            subd <cam_col
            tsta
            bne \skip
            cmpb #VIEW_COLS
            bhs \skip
            addb #VIEW_COL0
            stb BLIT_DST
            endm

; D=first line relative to the view, t0=lines. Clips them, and writes the blitter's line and height. Z set if none show.
vl_lines    tsta
            bne .off
            stb <t4
            addb <t0
            bcs .clip
            cmpb #VIEW_H
            bhi .clip
            lda <t0             ; all of it is in view, as most are
            sta BLIT_H
            ldb <t4
            addb #VIEW_ROW0
            stb BLIT_DST+1      ; never 0
            rts
.clip       ldb <t4
            cmpb #VIEW_H
            bhs .none
            lda #VIEW_H
            suba <t4
            sta BLIT_H
            addb #VIEW_ROW0
            stb BLIT_DST+1
            rts
.off        bpl .none
            addb <t0            ; starts above the view: what remains
            adca #0
            bne .none
            tstb
            beq .none
            cmpb #VIEW_H
            bls .h_ok
            ldb #VIEW_H
.h_ok       stb BLIT_H
            ldb #VIEW_ROW0
            stb BLIT_DST+1
            rts
.none       clra
            rts

; Y=rect, for the long way round: erases it where it was and draws it where it is.
vl_pair     ldd <old_col
            std <t2
            ldd <old_top
            std <t3
            clr <t4
            jsr terrain_rect
vl_draw     ldd <cam_col
            std <t2
            ldd <cam_top
            std <t3
            lda #1
            sta <t4
            jmp terrain_rect

; The trailing ends of walls, or on the long way round, walls moved as pairs. Then where each block was.
vl_walls_first
            ldu #VL_BASE
            tst vl_any
            lbne .all
            lda #1
            sta BLIT_W
            clr BLIT_SOLID
            ldu vl_wa
            lbra .test
            ; Moved sideways too, so it is all of the wall, as a pair.
.all        lda #1
            sta BLIT_W
.a_test     cmpu vl_w
            lbhs .blocks
            ldy ,u++
            ldb 5,y
            stb <t0
            ldd ,y
            subd <old_col
            tsta
            bne .a_draw
            cmpb #VIEW_COLS
            bhs .a_draw
            addb #VIEW_COL0
            stb BLIT_DST
            ldd 2,y
            subd <old_top
            jsr vl_lines
            beq .a_draw
            clr BLIT_SOLID
            lda 7,y
            ora #BC_SOLID+BC_DST256
            sta BLIT_CTRL
.a_draw     VL_COL .a_test
            ldd 2,y
            subd <cam_top
            jsr vl_lines
            beq .a_test
            ldb 6,y
            stb BLIT_SOLID
            lda 7,y
            ora #BC_SOLID+BC_DST256
            sta BLIT_CTRL
            bra .a_test
.next       ldy ,u++
            ldb 1,y             ; it is in view
            subb <cam_col+1
            addb #VIEW_COL0
            stb BLIT_DST
            ldd vl_dy
            bmi .up
            ; The view moved down, so the wall moved up: its lower end trails.
            cmpb 5,y
            bls .d_len
            ldb 5,y
.d_len      stb <t0
            ldb 5,y
            subb <t0
            clra
            addd 2,y
            subd <old_top
            bra .erase
.up         negb
            cmpb 5,y
            bls .u_len
            ldb 5,y
.u_len      stb <t0
            ldd 2,y
            subd <old_top
.erase      jsr vl_lines
            beq .test
            lda 7,y
            ora #BC_SOLID+BC_DST256
            sta BLIT_CTRL
.test       cmpu vl_wz
            blo .next
.blocks     ldu #VL_MID
            clr BLIT_SOLID
            bra .b_test
.b_next     ldy ,u++
            lda 4,y
            sta tl_wv
            lda 5,y
            sta <t0
            ldd 2,y
            subd <old_top
            jsr vl_lines
            beq .b_test
            ldd ,y
            subd <old_col
            jsr tl_span
            beq .b_test
            sta BLIT_W
            addb #VIEW_COL0
            stb BLIT_DST
            lda #BC_SOLID+BC_DST256
            sta BLIT_CTRL
.b_test     cmpu vl_b
            blo .b_next
            rts

; Floors and everything else that is not a wall or a block, each as a pair.
vl_flats_all
            ldu vl_f
.next       cmpu #VL_MID
            lbhs .done
            ldy ,u++
            lda 5,y
            deca
            bne .long
            tst 7,y
            bne .long
            tst vl_any
            beq .floor
            ; Moved sideways too.
            lda 4,y
            sta tl_wv
            lda #1
            sta BLIT_H
            ldd 2,y
            subd <old_top
            tsta
            bne .any_new
            cmpb #VIEW_H
            bhs .any_new
            addb #VIEW_ROW0
            stb BLIT_DST+1
            ldd ,y
            subd <old_col
            jsr tl_span
            beq .any_new
            sta BLIT_W
            addb #VIEW_COL0
            stb BLIT_DST
            clr BLIT_SOLID
            lda #BC_SOLID+BC_DST256
            sta BLIT_CTRL
.any_new    ldd 2,y
            subd <cam_top
            tsta
            bne .next
            cmpb #VIEW_H
            bhs .next
            addb #VIEW_ROW0
            stb BLIT_DST+1
            ldd ,y
            subd <cam_col
            jsr tl_span
            beq .next
            sta BLIT_W
            addb #VIEW_COL0
            stb BLIT_DST
            ldb 6,y
            stb BLIT_SOLID
            lda #BC_SOLID+BC_DST256
            sta BLIT_CTRL
            lbra .next
.long       jsr vl_pair
            lbra .next
            ; A floor keeps its columns. The camera moved only vertically.
.floor      ldd 2,y
            subd <cam_top
            tsta
            bne .f_old
            cmpb #VIEW_H
            blo .f_in
.f_old      ldd 2,y
            subd <old_top
            tsta
            lbne .next
            cmpb #VIEW_H
            lbhs .next
.f_in       ldd ,y
            subd <cam_col
            tsta
            bne .f_clip
            stb <t4
            addb 4,y
            bcs .f_back
            cmpb #VIEW_COLS
            bhi .f_back
            lda 4,y
            sta BLIT_W
            ldb <t4
            bra .f_col
.f_back     clra
            ldb <t4
.f_clip     pshs a
            lda 4,y
            sta tl_wv
            puls a
            jsr tl_span
            lbeq .next
            sta BLIT_W
.f_col      addb #VIEW_COL0
            stb BLIT_DST
            lda #1
            sta BLIT_H
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
            lbne .next
            cmpb #VIEW_H
            lbhs .next
            addb #VIEW_ROW0
            stb BLIT_DST+1
            ldb 6,y
            stb BLIT_SOLID
            lda #BC_SOLID+BC_DST256
            sta BLIT_CTRL
            lbra .next
.done       rts

; All of each wall, where it is now.
vl_walls_draw
            ldu vl_wa
            lda #1
            sta BLIT_W
            bra .test
.next       ldy ,u++
            ldb 1,y             ; it is in view
            subb <cam_col+1
            addb #VIEW_COL0
            stb BLIT_DST
            ldb 5,y
            stb <t0
            ldd 2,y
            subd <cam_top
            jsr vl_lines
            beq .test
            ldb 6,y
            stb BLIT_SOLID
            lda 7,y
            ora #BC_SOLID+BC_DST256
            sta BLIT_CTRL
.test       cmpu vl_wz
            blo .next
            rts

; Each group where it is. The first lines and columns cut off by the view say where in the image to start: one page per column.
vl_blocks_draw
            ldu #VL_MID
            cmpu vl_b
            bhs .done
.next       ldy ,u++
            lda <level_bank     ; the rect
            sta BANK_SELECT
            tst blk_kills
            bne .slow
            lda 4,y
            sta tl_wv
            lda 5,y
            sta <t0
            ldd 2,y
            subd <cam_top
            pshs d
            jsr vl_lines
            puls d
            beq .test
            tsta
            bpl .top_in
            negb
            bra .top_set
.top_in     clrb
.top_set    stb BLIT_SRC+1
            ldd ,y
            subd <cam_col
            pshs d
            jsr tl_span
            puls x
            beq .test
            sta BLIT_W
            addb #VIEW_COL0
            stb BLIT_DST
            tfr x,d
            tsta
            bpl .left_in
            negb
            bra .left_set
.left_in    clrb
.left_set   addb #BLOCK_PAGE
            stb BLIT_SRC
            clr BANK_SELECT     ; the image
            lda #BC_DST256+BC_SRC256
            sta BLIT_CTRL
.test       cmpu vl_b
            blo .next
            lda <level_bank
            sta BANK_SELECT
.done       rts
.slow       jsr vl_draw
            bra .test

; ---- blit queue -----------------------------------------------------------------------------
; A camera step changes everything on screen, and that takes longer than the beam takes to cross it. Drawn as it comes, a
; frame shows a wall half in its old place and half in its new one, cut where the beam passed.
; So blits are sorted by screen half. The upper half is drawn while the beam is in the lower half, and the lower half
; while the beam is in the upper half, so the beam never meets anything in the middle of changing. A blit that crosses the
; middle is split in two. Within a half, all erases come first.

; Empties the queue. The boss keeps its state in the same RAM once it exists, leaving only a small queue.
q_setup     tst wiz_live
            bne .small
            ldx #Q_BIG
            ldd #Q_BIG+Q_BIG_SIZE/2
            ldy #Q_BIG+Q_BIG_SIZE
            bra .set
.small      ldx #Q_SMALL
            ldd #Q_SMALL+Q_SMALL_SIZE/2
            ldy #Q_SMALL+Q_SMALL_SIZE
.set        stx q_base
            stx qa_e
            std q_mid
            std qa_d
            std qb_e
            sty q_end
            sty qb_d
            rts

; Sends the blit in em_dst, em_wh, em_cs, em_kind to the queue, or runs it now if there is no queue or no room.
; Keeps Y and U.
emit_blit   tst queue_on
            beq .exec
            lda em_dst+1
            cmpa #BEAM_MID
            bhs .lower
            adda em_wh+1
            cmpa #BEAM_MID
            bls .upper
            suba #BEAM_MID      ; A = its lines in the lower half
            pshs a
            ldb em_wh+1
            subb ,s
            stb em_wh+1
            bsr .upper
            puls a
            sta em_wh+1
            lda #BEAM_MID
            sta em_dst+1
.lower      ldx #qb_e
            bra .put
.upper      ldx #qa_e
.put        tst em_kind
            bne .draw
            ldd ,x              ; an erase goes at the bottom, unless it would reach the draws
            cmpd 2,x
            bhs .exec
            addd #6
            std ,x
            subd #6
            tfr d,x
            bra .write
.draw       ldd 2,x
            subd #6
            cmpd ,x
            blo .exec
            std 2,x
            tfr d,x
.write      ldd em_dst
            std ,x
            ldd em_wh
            std 2,x
            ldd em_cs
            std 4,x
            rts
.exec       ldd em_dst
            std BLIT_DST
            ldd em_wh
            std BLIT_W
            ldd em_cs
            stb BLIT_SOLID
            sta BLIT_CTRL
            rts

; Y=first entry, X=end. Runs a stretch of the queue.
q_run       pshs x
.next       cmpy ,s
            bhs .done
            ldd ,y
            std BLIT_DST
            ldd 2,y
            std BLIT_W
            ldd 4,y
            stb BLIT_SOLID
            sta BLIT_CTRL
            leay 6,y
            bra .next
.done       puls x,pc

; ---- still layer ----------------------------------------------------------------------------
; From sprite_common: U=sprite entry, X, Y=world, t5=extra control and solid value, the caller's U on the stack.
; Unlike the display list, this keeps an image that is out of view, so scrolling needs no re-drawing by its owner.
; Positions are relative to the view last drawn, which can differ from the camera's on a skipped tick. still_pass moves new
; entries along with the rest.
still_add   lda still_used
            cmpa #STILL_MAX
            lbhs .full
            tfr x,d
            addb 4,u
            adca #0
            subd <old_left
            addd #VIEW_COL0*2
            asra
            rorb                ; carry = odd pixel
            std <t1
            lda #BC_DST256+BC_FG_ONLY
            bcc .even
            lda #BC_DST256+BC_FG_ONLY+BC_SHIFT
.even       ora <t5
            sta <t5
            tfr y,d
            addb 5,u
            adca #0
            subd <old_top
            addd #VIEW_ROW0
            std <t4
            ; Upward from the last slot used, never into a hole behind it: still_pass depends on list order being the
            ; order of the text.
            ldx still_scan
.scan       cmpx still_end
            bhs .full
            lda S_STATE,x
            beq .found
            leax S_SIZE,x
            bra .scan
.found      ldd ,u
            std S_SRC,x
            ldd 2,u
            std S_W,x
            ldd <t5
            std S_CTRL,x
            ldd <t1
            std S_COL,x
            ldd <t4
            std S_ROW,x
            lda still_owner
            ora #SS_LIVE+SS_NEW
            sta S_STATE,x
            stx still_last
            cmpx #still_list+STILL_BANNER*S_SIZE
            blo .banner
            ora #SS_CUR
            sta S_STATE,x
            jsr still_mark
            lda S_STATE,x
            inc still_rem
            inc rem_dirty
            leax S_SIZE,x
            stx still_scan
            cmpx still_rhi
            bls .nothi
            stx still_rhi
            bra .nothi
.banner     leax S_SIZE,x
            stx still_scan
            cmpx still_bhi
            bls .nothi
            stx still_bhi
.nothi      inc still_used
            sta still_work
            sta still_any
            puls u,pc
.full       inc still_full
            puls u,pc

; X=entry. Keeps X and U. Marks it to be erased and freed; the slot stays in use until Present has done so.
Still_Release
            lda S_STATE,x
            anda #SS_SHOWN
            beq still_free
            lda S_STATE,x
            anda #$0F
            anda #~SS_NEW&$FF
            ora #SS_DIE
            sta S_STATE,x
            sta still_work
            rts

; X=entry, not on screen. Frees it. Keeps X and U.
still_free  clr S_STATE,x
            dec still_used
            cmpx #still_list+STILL_BANNER*S_SIZE
            blo .banner
            dec still_rem
            inc rem_dirty
            pshs x
            ldx still_rhi
.rtrim      cmpx #still_list+STILL_BANNER*S_SIZE
            bls .rset
            tst S_STATE-S_SIZE,x
            bne .rset
            leax -S_SIZE,x
            bra .rtrim
.rset       stx still_rhi
            puls x,pc
            ; Pull the walk's end back past any empty slots now at the top.
.banner     pshs x
            ldx still_bhi
.trim       cmpx #still_list
            bls .set
            tst S_STATE-S_SIZE,x
            bne .set
            leax -S_SIZE,x
            bra .trim
.set        stx still_bhi
            puls x,pc

; D=sprite, X, Y=world, for something that will not change for a while. Returns X=its still layer entry, or 0 if there was
; no room, in which case the caller draws it the usual way. Keeps U.
Still_AddStatic
            pshs y,x,d
            lda still_rem
            cmpa #STILL_MAX-STILL_BANNER
            bhs .none
            ldx #still_list+STILL_BANNER*S_SIZE
            stx still_scan
            ldx #still_list+STILL_MAX*S_SIZE
            stx still_end
            ldx #0
            stx still_last
            clr still_full
            clr still_owner
            inc <still_mode
            ldd ,s
            ldx 2,s
            ldy 4,s
            jsr Draw_SpriteAny
            clr <still_mode
            tst still_full
            bne .none
            ldx still_last
            leas 6,s
            rts
.none       ldx #0
            leas 6,s
            rts

; X=entry, D=sprite of the same size. The entry shows that sprite from now on, at once. Keeps U.
Still_Swap  aslb
            rola
            aslb
            rola
            aslb
            rola
            addd #sprite_table
            tfr d,y
            ldd ,y
            std S_SRC,x
            lda S_STATE,x
            bita #SS_NEW+SS_DIE
            bne .out
            bita #SS_SHOWN
            beq .out
            clr BANK_SELECT
            jsr still_draw
            lda <cur_bank
            sta BANK_SELECT
.out        rts

; Releases every entry owned by banner slot A (1..15). Keeps U.
Still_ReleaseOwner
            asla
            asla
            asla
            asla
            sta <t1
            ldx #still_list
            ldb #STILL_BANNER
            stb <t1+1
.next       lda S_STATE,x
            beq .skip
            anda #$F0
            cmpa <t1
            bne .skip
            jsr Still_Release
.skip       leax S_SIZE,x
            dec <t1+1
            bne .next
            rts

; Erases all of it, for a new level or a restart.
Still_Reset ldx #still_list
            ldb #STILL_MAX
            stb <t1+1
.next       lda S_STATE,x
            beq .skip
            jsr Still_Release
.skip       leax S_SIZE,x
            dec <t1+1
            bne .next
            clr ban_used
            rts

; Called by Present with bank 0 selected. still_dc, still_dr hold the move; A=nonzero when the camera moved. On a tick
; with a still camera, only new and dying entries do anything.
; Each image is erased and redrawn as a pair, so none is ever missing from a frame. Glyphs are closer together than a
; camera step, so the order matters: walking the list in the direction the images move, an erase only ever touches
; ground that has not been drawn on yet. Text is stored left to right and top to bottom, so a view moving right or down
; walks forward, and one moving left or up walks backward.
still_pass  sta <t0
            ; Which way to walk.
            clr <t0+1
            tsta
            beq .forward
            tst still_dc
            bmi .back
            ldd still_dc
            bne .forward
            tst still_dr
            bpl .forward
.back       inc <t0+1
.forward    lda ban_bank        ; the banners' slots hold word images
            sta BANK_SELECT
            ldx #still_list
            ldy still_bhi
            bsr still_walk
            clr BANK_SELECT
            tst still_rem
            beq .out
            ldx #still_list+STILL_BANNER*S_SIZE
            ldy still_rhi
            bsr still_walk
.out        clr still_work
            rts

; X=first entry, Y=the end of the range. Walks it in the direction in t0+1.
still_walk  pshs y              ; 0,s = where the walk stops
            cmpx ,s
            lbeq .none          ; an empty range
            ldd #S_SIZE
            tst <t0+1
            beq .dir
            tfr x,d             ; backward: from the last entry down to just below the first
            subd #S_SIZE
            std ,s
            leax -S_SIZE,y
            ldd #-S_SIZE
.dir        std <t1
.next       lda S_STATE,x
            lbeq .skip
            tst still_band
            beq .inband
            ldd S_ROW,x
            cmpd #BEAM_MID
            blt .up
            lda still_band
            cmpa #2
            lbne .skip
            bra .inband
.up         lda still_band
            cmpa #1
            lbne .skip
.inband     lda S_STATE,x
            bita #SS_DIE
            lbne .die
            bita #SS_NEW
            bne .place
            tst <t0
            lbeq .skip
            bita #SS_SHOWN
            beq .move
            lbsr still_erase
            ldd S_COL,x
            subd still_dc
            std S_COL,x
            ldd S_ROW,x
            subd still_dr
            std S_ROW,x
            lda S_STATE,x
            anda #~SS_SHOWN&$FF
            sta S_STATE,x
            ; The same limits as the display list. The blitter does not clip.
            ldd S_COL,x
            beq .q_col
            tsta
            lbne .skip
.q_col      cmpb #VIEW_COL0+VIEW_COLS
            lbhs .skip
            addb S_W,x
            cmpb #VIEW_COL0
            lbls .skip
            ldd S_ROW,x
            cmpd #VIEW_BOTTOM
            bhs .skip
            addb S_W+1,x
            cmpb #VIEW_ROW0
            bls .skip
            lda S_STATE,x
            ora #SS_SHOWN
            sta S_STATE,x
            ; The erase left the source and size in the blitter's registers.
            lda S_COL+1,x
            ldb S_ROW+1,x
            std BLIT_DST
            ldd S_CTRL,x
            stb BLIT_SOLID
            sta BLIT_CTRL
            jsr still_edge
            bra .skip
.move       ldd S_COL,x
            subd still_dc
            std S_COL,x
            ldd S_ROW,x
            subd still_dr
            std S_ROW,x
            lda S_STATE,x
            anda #~SS_SHOWN&$FF
            sta S_STATE,x
            bra .show
.place      anda #~SS_NEW&$FF
            sta S_STATE,x
            tst <t0
            bne .move
.show       ldd S_COL,x
            beq .col_ok
            tsta
            bne .skip
.col_ok     cmpb #VIEW_COL0+VIEW_COLS
            bhs .skip
            addb S_W,x
            cmpb #VIEW_COL0
            bls .skip
            ldd S_ROW,x
            cmpd #VIEW_BOTTOM
            bhs .skip
            addb S_W+1,x
            cmpb #VIEW_ROW0
            bls .skip
            lda S_STATE,x
            ora #SS_SHOWN
            sta S_STATE,x
            lbsr still_draw
.skip       ldd <t1
            leax d,x
            cmpx ,s
            lbne .next
.none       puls y,pc
.die        bita #SS_SHOWN
            beq .free
            lbsr still_erase
.free       jsr still_free
            bra .skip

; The camera moved sideways: the usual case, and worth its own short path. New and dying entries are dealt with first.
; Remains: still_scroll_erase takes away what shows, the terrain moves, and still_scroll draws them where they now are. They lie on
; the ground, and an erase after the terrain would leave a hole in it on every step.
; Banners are in the air, so they stay in still_scroll as pairs, which is cheaper: the erase leaves the registers set for the draw.
; t3=0 for the upper half of the screen, $80 for the lower. An image is looked at in the pass for its half, whether in view or not:
; half of them need only this. One out of view just follows the camera, in the upper half's pass.
STILL_ERASE_ONE macro
            lda S_STATE,x
            bita #SS_SHOWN
            beq .no\@
            ldd S_SRC,x
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
.no\@
            endm

; A=0 for the upper half's pass, $80 for the lower's. The lists hold only remains near the view: see rem_relist. Those not in a list
; have the view's moves added up in rem_acc, and get them when next looked at. A boss wants the lists' RAM, and then they move as pairs.
still_scroll_erase
            sta <t3
            tst wiz_live
            bne .done
            tsta
            bne .half
            tst rem_dirty
            bne .list_now
            ldd rem_acc
            addd #REM_NEAR
            cmpd #REM_NEAR*2
            blo .sum
.list_now   lbsr rem_relist
.sum        ldd rem_acc
            addd still_dc
            std rem_acc
.half       ldy #rem_a
            tst <t3
            beq .list
            ldy #rem_b
.list       ldx ,y++
            beq .done
            lda S_STATE,x
            bita #SS_TERR
            beq .list
            STILL_ERASE_ONE
            bra .list
.done       rts

; The view moved only sideways, with the image still on screen. Remains, erased already.
STILL_SCROLL_ONE macro step
            lda S_STATE,x
            bita #SS_SHOWN
            beq .hidden\step
            ldd S_COL,x
            subd <t2
            std S_COL,x
            tsta
            bne .hide\step
            cmpb #VIEW_COL0+VIEW_COLS
            bhs .hide\step
            addb S_W,x
            cmpb #VIEW_COL0
            bls .hide\step
            jsr still_draw
            bra .skip\step
.hide\step  lda S_STATE,x
            anda #~SS_SHOWN&$FF
            sta S_STATE,x
            bra .skip\step
.hidden\step tsta
            beq .skip\step
            ldd S_COL,x
            subd <t2
            std S_COL,x
            tsta
            bne .skip\step
            cmpb #VIEW_COL0+VIEW_COLS
            bhs .skip\step
            addb S_W,x
            cmpb #VIEW_COL0
            bls .skip\step
            ldd S_ROW,x
            cmpd #VIEW_BOTTOM
            bhs .skip\step
            addb S_W+1,x
            cmpb #VIEW_ROW0
            bls .skip\step
            lda S_STATE,x
            ora #SS_SHOWN
            sta S_STATE,x
            jsr still_draw
.skip\step
            endm

; As STILL_SCROLL_ONE, erasing it too.
STILL_PAIR_ONE macro step
            lda S_STATE,x
            bita #SS_SHOWN
            beq .hidden\step
            ldd S_SRC,x
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
            ldd S_COL,x
            subd <t2
            std S_COL,x
            tsta
            bne .hide\step
            cmpb #VIEW_COL0+VIEW_COLS
            bhs .hide\step
            addb S_W,x
            cmpb #VIEW_COL0
            bls .hide\step
            ; The erase left the source and size in the blitter's registers.
            lda S_COL+1,x
            ldb S_ROW+1,x
            std BLIT_DST
            ldd S_CTRL,x
            stb BLIT_SOLID
            sta BLIT_CTRL
            jsr still_edge
            bra .skip\step
.hide\step  lda S_STATE,x
            anda #~SS_SHOWN&$FF
            sta S_STATE,x
            bra .skip\step
.hidden\step tsta
            beq .skip\step
            ldd S_COL,x
            subd <t2
            std S_COL,x
            tsta
            bne .skip\step
            cmpb #VIEW_COL0+VIEW_COLS
            bhs .skip\step
            addb S_W,x
            cmpb #VIEW_COL0
            bls .skip\step
            ldd S_ROW,x
            cmpd #VIEW_BOTTOM
            bhs .skip\step
            addb S_W+1,x
            cmpb #VIEW_ROW0
            bls .skip\step
            lda S_STATE,x
            ora #SS_SHOWN
            sta S_STATE,x
            jsr still_draw
.skip\step
            endm

; X=first entry, t1=end.
still_scroll_fwd
            bra .next
.adv        leax S_SIZE,x
.next       cmpx <t1
            lbhs .done
            lda S_ROW+1,x
            eora <t3
            bmi .adv
            STILL_PAIR_ONE f
            lbra .adv
.done       rts
; X=last entry, t1=first entry.
still_scroll_back
            bra .next
.adv        leax -S_SIZE,x
.next       cmpx <t1
            lblo .done
            lda S_ROW+1,x
            eora <t3
            bmi .adv
            STILL_PAIR_ONE b
            lbra .adv
.done       rts

; A=0 for the upper half's pass, $80 for the lower's. Banners walk in the direction the view moved, as still_pass explains.
still_scroll
            sta <t3
            lda ban_bank        ; the banners' slots hold word images
            sta BANK_SELECT
            ldd still_dc
            std <t2
            bmi .back
            ldx still_bhi
            stx <t1
            ldx #still_list
            lbsr still_scroll_fwd
            bra .rest
.back       ldx #still_list
            stx <t1
            ldx still_bhi
            leax -S_SIZE,x
            lbsr still_scroll_back
.rest       clr BANK_SELECT
            tst wiz_live
            lbne .walk
.listed     ldy #rem_a
            tst <t3
            beq .list
            ldy #rem_b
.list       ldx ,y++
            lbeq .done
            lda S_STATE,x
            bita #SS_TERR
            lbne .terr
            ; Wholly in a cell it cannot touch terrain, so it stays a pair, and is never missing from the screen.
            STILL_PAIR_ONE p
            lbra .list
.terr       STILL_SCROLL_ONE l
            lbra .list
.done       rts
.walk       ldd rem_acc
            beq .w_go
            lbsr rem_flush
.w_go       ldx still_rhi
            stx <t1
            ldx #still_list+STILL_BANNER*S_SIZE
            lbra still_scroll_fwd

; Gives every remains its moves from rem_acc, those in the lists having had them. Keeps U.
rem_flush   ldx #still_list+STILL_BANNER*S_SIZE
            bra .test
.next       lda S_STATE,x
            beq .adv
            bita #SS_CUR+SS_DIE ; one that is dying has lost the mark, and if it shows, it has had its moves
            bne .cur
            ora #SS_CUR
            sta S_STATE,x
            ldd S_COL,x
            subd rem_acc
            std S_COL,x
.adv        leax S_SIZE,x
.test       cmpx still_rhi
            blo .next
            ldd #0
            std rem_acc
            rts
.cur        leax S_SIZE,x
            bra .test

still_erase ldd S_SRC,x
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
            rts

; A word that has just finished typing was last drawn as letters, so the display list has just erased those letters, on top
; of the word. So it is drawn once more now that the erasing is over.
still_fresh ldx ban_fresh
            beq .out
            clr ban_fresh
            clr ban_fresh+1
            lda S_STATE,x
            bita #SS_SHOWN
            beq .out
            bita #SS_DIE
            bne .out
            lda ban_bank
            sta BANK_SELECT
            jsr still_draw
            clr BANK_SELECT
.out        rts

still_draw  ldd S_SRC,x
            std BLIT_SRC
            lda S_COL+1,x
            ldb S_ROW+1,x
            std BLIT_DST
            ldd S_W,x
            std BLIT_W
            lda S_SOLID,x
            sta BLIT_SOLID
            lda S_CTRL,x
            sta BLIT_CTRL
            jmp still_edge
; Redraws a few images each still tick, to heal holes left by sprites erasing across them.
STILL_HEALS equ 2
still_repair
            ldx still_heal
            bne .start
            ldx #still_list
.start      ldb #STILL_HEALS
            stb <t0
.next       cmpx #still_list+STILL_MAX*S_SIZE
            blo .in
            ldx #still_list
.in         lda S_STATE,x
            bita #SS_SHOWN
            beq .skip
            bita #SS_DIE
            bne .skip
            cmpx #still_list+STILL_BANNER*S_SIZE
            bhs .draw
            lda ban_bank
            sta BANK_SELECT
            jsr still_draw
            clr BANK_SELECT
            bra .skip
.draw       jsr still_draw
.skip       leax S_SIZE,x
            dec <t0
            bne .next
            stx still_heal
            rts

