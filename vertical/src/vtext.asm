; The vertical build's text on the full screens. The screens keep the horizontal build's layout in its coordinates (x across,
; y down, as Text_Draw takes them); they are drawn turned as the game is: x along the lines, y down the pixel columns from
; the right. The sprites, the font among them, are already turned (gen_assets.py --vertical).

; B=glyph. Blits straight to the screen at text_x, text_y.
glyph_blit  clra
            addd #FONT2_BASE
; D=sprite id.
sprite_blit aslb
            rola
            aslb
            rola
            aslb
            rola
            addd #sprite_table
            tfr d,u
            lda 2,u
            beq .out
            clr BANK_SELECT
            ldd ,u
            std BLIT_SRC
            ldd 2,u
            std BLIT_W
            ldd text_x          ; x is the line
            addd #SCV_L
            addb 5,u
            pshs b
            ; Each image is a canvas VROT_W wide with the game's row y in column VROT_W-1-y.
            ldd #SCV_P-(VROT_W-1)
            subd text_y
            addb 4,u
            adca #0
            lsra
            rorb
            tfr b,a             ; neither this nor the pull changes the carry: the odd pixel
            puls b
            pshs cc
            std BLIT_DST
            lda <draw_color
            ldb #$11
            mul
            stb BLIT_SOLID
            lda #BC_DST256+BC_FG_ONLY
            tst <draw_color
            beq .white
            ora #BC_SOLID
.white      puls cc
            bcc .even
            ora #BC_SHIFT
.even       sta BLIT_CTRL
            lda <cur_bank
            sta BANK_SELECT
.out        rts
