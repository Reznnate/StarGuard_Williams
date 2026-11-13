; Phase 3's drawing (from wizard.asm's "p3 drawing"). Bank 9, level 9's own bank, which has room: bank 11 needed it for
; the exploding platforms' manager. Called from wizard.asm with FAR (p3_draw_self). RAM and fixed ROM only, so it does not
; care which bank is selected beyond its own; p3_body_reuse and p3_body_note are beside it in this bank.

p3_t        ldd <now           ; as wz_t
            subd E_START,u
            rts
p3_neg      coma               ; as wz_neg
            comb
            addd #1
            rts

; ---- p3 drawing ---------------------------------------------------------------------------------
; The C's body: 22 sprites and 15 rectangles, drawn in the C's order and all in one color. Each row: hi, lo, dx, dy, gf
; with position (x2 + dx, y2 + dy + gf * G), where G = -g is the closing of the jaw, 0..4. hi with bit 7 set is a rectangle
; with width hi & $7F and height lo; otherwise hi:lo is a sprite id. sizeX is 23.
P3PART      macro id,dx,dy,gf
            fcb hi(\id),lo(\id),\dx,\dy,\gf
            endm
P3RECT      macro w,h,dx,dy,gf
            fcb $80+\w,\h,\dx,\dy,\gf
            endm
p3_parts    P3PART 300,-23,-12,1
            P3PART 301,-23,0,-1
            P3PART 302,-11,-12,1
            P3PART 303,-11,0,-1
            ; p3_Rect(x2 - 7, y2 - g, 7, g * 2) has height <= 0, which draws nothing in the C either. Left out.
            P3PART 333,-19,-24,1
            P3PART 316,-20,-25,1
            P3PART 316,-24,-22,1
            P3PART 315,-26,-19,1
            P3PART 312,-24,-19,1
            P3PART 312,-27,6,-1
            P3PART 338,-20,12,-1
            P3PART 316,-24,7,-1
            P3PART 318,-20,10,-1
            P3PART 315,3,-28,1
            P3PART 315,7,-26,1
            P3PART 317,11,-23,1
            P3RECT 12,11,-7,-23,1
            P3RECT 4,12,5,-24,1
            P3RECT 4,10,9,-22,1
            P3RECT 4,8,13,-20,1
            P3RECT 6,5,17,-17,1
            P3RECT 8,9,-8,12,0
            P3RECT 8,13,0,12,0
            P3RECT 9,7,8,12,0
            P3PART 338,-14,14,0
            P3RECT 2,3,-2,21,0
            P3RECT 4,1,4,25,0
            P3PART 312,1,20,0
            P3PART 304,17,7,0
            P3PART 305,8,19,0
            P3RECT 24,24,1,-12,0
            P3PART 324,15,-17,0
            P3PART 316,19,-9,0
            P3RECT 2,7,25,0,0
            P3RECT 1,6,27,-1,0
p3_parts_end
P3_PART_COUNT    equ (p3_parts_end-p3_parts)/5

; The four tentacles: base dx, dy, gf, then the y of the direction (its x is -4).
p3_tent     fcb -20,-14,1,2
            fcb -19,-18,1,-2
            fcb -20,14,-1,2
            fcb -15,20,-1,3
; Unit vectors for a direction (-4, v), v = -5..6, as |x| * 64, y * 64, were 40,-50 45,-45 51,-38 57,-29 62,-16 64,0 62,16
; 57,29 51,38 45,45 40,50 36,53. For each v and distance d = 2..6: d * |x| / 64 and d * y / 64, rounded toward 0, as the
; dots used to work them out with two multiplies a dot.
p3_doff     fcb 1,-1,1,-2,2,-3,3,-3,3,-4
            fcb 1,-1,2,-2,2,-2,3,-3,4,-4
            fcb 1,-1,2,-1,3,-2,3,-2,4,-3
            fcb 1,0,2,-1,3,-1,4,-2,5,-2
            fcb 1,0,2,0,3,-1,4,-1,5,-1
            fcb 2,0,3,0,4,0,5,0,6,0
            fcb 1,0,2,0,3,1,4,1,5,1
            fcb 1,0,2,1,3,1,4,2,5,2
            fcb 1,1,2,1,3,2,3,2,4,3
            fcb 1,1,2,2,2,2,3,3,4,4
            fcb 1,1,1,2,2,3,3,3,3,4
            fcb 1,1,1,2,2,3,2,4,3,4
; Dots of the tentacles: tentacle, distance along it. The C draws 96 sprites along lines 3 to 6 pixels long, 24 to a line,
; and most land on the same pixel. These 14 are the distinct pixels outside the body parts above. Half are drawn each
; tick, alternating; a dot left out of a tick is erased, which on open background is just the flicker of a thin line.
p3_dots     fcb 0,2,0,4,0,6,1,2,1,4,2,2,3,2
            fcb 3,4,0,3,0,5,1,3,2,3,3,3,3,5

; UpdateTentacles, for a 30 Hz tick: two of the C's steps at once.
p3_update_tentacles
            ; Keep the offset as y2 moves under it.
            ldd wp3_prevy
            subd wp3_y+1
            addd wp3_rel
            std wp3_rel
            ldd wp3_y+1
            std wp3_prevy
            ; dy = -rel: dy < 0 slows, else speeds up.
            ldd wp3_tvel
            tst wp3_rel
            bpl .minus
            addd #26
            bra .clamp
.minus      ldx wp3_rel
            beq .plus
            subd #26
            bra .clamp
.plus       addd #26
.clamp      cmpd #256
            ble .c1
            ldd #256
.c1         cmpd #-256
            bge .c2
            ldd #-256
            ; * 0.9, on the magnitude.
.c2         tsta
            bpl .pos
            jsr p3_neg
            jsr p3_damp
            jsr p3_neg
            bra .store
.pos        jsr p3_damp
.store      std wp3_tvel
            addd wp3_rel
            cmpd #768
            ble .r1
            ldd #768
.r1         cmpd #-768
            bge .r2
            ldd #-768
.r2         std wp3_rel
            rts
; D (0..256) * 230 / 256.
p3_damp     cmpd #256
            blo .small
            ldd #230
            rts
.small      lda #230
            mul
            tfr a,b
            clra
            rts

; Whether anything moved under the body parts. Entries that move redraw one by one, and erasing one can punch a hole in a
; neighbor that was drawn before it. The holes stay once the body stops, so the first still tick redraws everything with
; the other palette index for red, which looks the same but makes every entry differ. Same-place redraws heal themselves.
p3_heal_check
            ldd wp3_y
            cmpd wp3_ly
            bne .changed
            lda wd_g
            cmpa wp3_lg
            bne .changed
            lda wp3_charged
            cmpa wp3_lc
            bne .changed
            tst wp3_heal
            beq .out
            clr wp3_heal
            lda wp3_red
            eora #COLOR_RED^P3_RED_ALT
            sta wp3_red
.out        rts
.changed    lda #1
            sta wp3_heal
            ldd wp3_y
            std wp3_ly
            lda wd_g
            sta wp3_lg
            lda wp3_charged
            sta wp3_lc
            rts

; Sets wd_g from the phase, the color, and draws.
p3_draw_self
            lda wp3_phase
            cmpa #P3P_DYING
            lbeq p3_draw_dying
            cmpa #P3P_MINIONS
            bne .n1
            ; jaw = 1 - t / 30, so G = min(4, t * 4 / 30).
            ldd <now
            subd wp3_t3
            cmpd #P3_JAW_T
            bge .shut
            bsr p3_g_of_t
            bra .have
.shut       ldb #4
            bra .have
.n1         cmpa #P3P_HIGHLOW
            bne .n2
            ; jaw = t / 30, so G = (30 - t) * 4 / 30 until open.
            ldd <now
            subd wp3_t3
            cmpd #P3_JAW_T
            bge .open
            std wq_tmp
            ldd #P3_JAW_T
            subd wq_tmp
            bsr p3_g_of_t
            bra .have
.open       clrb
            bra .have
.n2         ldb #4
.have       stb wd_g
            jsr p3_update_tentacles
            jsr p3_heal_check
            lda wp3_red
            sta <draw_color
            lda E_FLAGS,u
            bita #EF_FLASHING
            beq p3_draw_wizard
            ldb <now+1
            subb E_FLASHT,u
            cmpb #ALIEN_FLASH_T
            bls .white
            lda E_FLAGS,u
            anda #~EF_FLASHING&$FF
            sta E_FLAGS,u
            bra p3_draw_wizard
.white      lda #COLOR_WHITE
            sta <draw_color
            bra p3_draw_wizard

; D = t, 0..29. B = t * 4 / 30, that is t * 2 / 15.
p3_g_of_t   aslb
            pshs b
            clrb
            lda ,s+
.l          cmpa #15
            blo .out
            suba #15
            incb
            bra .l
.out        rts

; DrawWizard, with draw_color and wd_g set.
p3_draw_wizard
            jsr p3_body_reuse
            lbeq .tent
            ldx #p3_parts
            stx wd_p
            lda #P3_PART_COUNT
            sta wd_n
.part       ldx wd_p
            ldb 2,x
            sex
            addd wp3_x
            std wd_x
            ldx wd_p
            ldb 3,x
            sex
            addd wp3_y
            std wd_y
            lda 4,x
            beq .place
            ldb wd_g
            clra
            tst 4,x
            bpl .gplus
            jsr p3_neg
.gplus      addd wd_y
            std wd_y
.place      ldx wd_p
            lda ,x
            bmi .rect
            ldd ,x
            ldx wd_x
            ldy wd_y
            jsr Draw_ColoredSprite
            bra .next
.rect       anda #$7F
            ldb 1,x
            ldx wd_x
            ldy wd_y
            jsr Draw_RectWorld
.next       ldx wd_p
            leax 5,x
            stx wd_p
            dec wd_n
            bne .part
            ; p3_Rect(x2 - 8, y2 + 12 + g, 9, -g): only there while the jaw is shut.
            ldb wd_g
            beq .noted
            clra
            std wq_tmp
            ldx wp3_x
            leax -8,x
            ldd wp3_y
            addd #12
            subd wq_tmp
            tfr d,y
            lda #9
            ldb wd_g
            jsr Draw_RectWorld
.noted      jsr p3_body_note
.tent       jsr p3_draw_dots
            ; The charge is drawn behind the body in the C. Here it comes last, so that toggling it leaves every other
            ; entry at its index in the display list.
            tst wp3_charged
            beq .done
            jsr p3_t
            andb #1
            bne .f1
            ldd #325
            std wq_tx
            bra .fgo
.f1         ldd #333
            std wq_tx
.fgo        ldx wp3_x
            leax -13,x
            ldy wp3_y
            leay -12,y
            ldd wq_tx
            jsr Draw_Sprite
            ldx wp3_x
            leax -13,x
            ldy wp3_y
            ldd wq_tx
            addd #1
            jmp Draw_Sprite
.done       rts

; P3_TENT_PER_TICK dots of the tentacles, cycling. As if each were Draw_ColoredSprite(312) at (base - (d*|ux|/64) - 6,
; base + d*uy/64 - 6), d its distance and (ux, uy) its tentacle's direction; the products come from p3_doff.
; A dot wholly inside the view is listed here directly (the routine's cost was mostly the general sprite path); one at an
; edge, or with the list full, goes through Draw_ColoredSprite, which cuts it or counts the drop.
p3_draw_dots
            ; rel, rounded to whole pixels.
            ldd wp3_rel
            addd #128
            sta wq_tmp
            ; What every dot shares: wq_cx, wq_cy = the base's world origin less the 6; wq_fx, wq_fy = world to video,
            ; for sprite 312; wq_best = its entry's source; wq_d = its w, h; wd_w = the color byte.
            ldx #sprite_table+312*8
            ldd ,x
            std wq_best
            ldd 2,x
            std wq_d
            ldb 4,x
            clra
            if VERT
            addd <vk            ; turned: the pixel is vk - 1 + its column in the canvas - y
            subd #1
            else
            subd <spr_ox
            endif
            std wq_fx
            ldb 5,x
            clra
            subd <spr_oy
            subd #12
            std wq_fy
            ldd wp3_x
            subd #6
            std wq_cx
            ldd wp3_y
            subd #6
            std wq_cy
            lda <draw_color
            ldb #$11
            mul
            stb wd_w
            lda #P3_TENT_PER_TICK
            sta wq_n
            lda wp3_tcur
            sta wq_i
.dot        ldb wq_i
            aslb
            ldx #p3_dots
            abx
            ldb ,x              ; tentacle
            aslb
            aslb
            ldy #p3_tent
            leay b,y
            ; The products for this dot: p3_doff[(v + rel + 5) * 5 + d - 2], two bytes each.
            lda 3,y
            adda wq_tmp
            adda #5
            ldb #5
            mul
            addb 1,x
            subb #2
            aslb
            ldx #p3_doff
            abx
            ; World x = base x - dx (wd_x), world y = base y +- G + dy (wd_y).
            ldb ,y
            subb ,x
            sex
            addd wq_cx
            std wd_x
            ldb 1,y
            sex
            addd wq_cy
            std wd_y
            ldb 1,x
            sex
            addd wd_y
            std wd_y
            ldb wd_g
            clra
            tst 2,y
            bpl .gplus
            jsr p3_neg
.gplus      addd wd_y
            std wd_y
            ; Inside the view as DL_INSIDE has it, and room in the list? Else the general way, which also knows the still
            ; layer.
            tst <still_mode
            bne .slow
            ldx <dl_newp
            cmpx <dl_limit
            bhs .slow
            if VERT
            ldd wq_fx           ; turned: the pixel from y, the line from x
            subd wd_y
            else
            ldd wd_x
            addd wq_fx          ; the video line's pixel
            endif
            subd #VIEW_COL0*2
            std wq_tx
            lda #VIEW_COLS-1    ; columns the image may start in: 0 to VIEW_COLS-1-w
            suba wq_d
            ldb #2
            mul
            addd #1
            cmpd wq_tx
            blo .slow
            if VERT
            ldd wd_x
            else
            ldd wd_y
            endif
            addd wq_fy
            subd #VIEW_ROW0
            bmi .slow
            tsta
            bne .slow
            addb wq_d+1
            bcs .slow
            cmpb #VIEW_H
            bhi .slow
            subb wq_d+1
            addb #VIEW_ROW0
            stb 3,x
            ldd wq_tx
            lsra
            rorb                ; carry = odd pixel
            lda #BC_DST256+BC_FG_ONLY+BC_SOLID
            bcc .even
            lda #BC_DST256+BC_FG_ONLY+BC_SOLID+BC_SHIFT
.even       addb #VIEW_COL0
            stb 2,x
            ldb wd_w
            std 6,x
            ldd wq_best
            std ,x
            ldd wq_d
            std 4,x
            leax DL_SIZE,x
            stx <dl_newp
            bra .next
.slow       ldx wd_x
            ldy wd_y
            ldd #312
            jsr Draw_ColoredSprite
.next       lda wq_i
            inca
            cmpa #P3_TENT_DOTS
            blo .nowrap
            clra
.nowrap     sta wq_i
            dec wq_n
            lbne .dot
            sta wp3_tcur
            rts


; DrawPhaseDying.
p3_draw_dying
            lda #COLOR_WHITE
            sta <draw_color
            jsr p3_t
            cmpd #P3_DYING_WHITE_T
            bge .sprites
            ldb #4
            stb wd_g
            jsr p3_update_tentacles
            jmp p3_draw_wizard
.sprites    ldx wp3_x
            leax -6,x
            ldy wp3_y
            leay -6,y
            ldd #281
            jsr Draw_ColoredSprite
            ldx wp3_x
            leax -7,x
            ldy wp3_y
            leay -1,y
            ldd #63
            jmp Draw_ColoredSprite
