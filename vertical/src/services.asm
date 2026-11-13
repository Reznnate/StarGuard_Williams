; Engine services for the game classes: cells, rectangles, text, sprites in screen space, sound. Fixed ROM.

; Main.SetCellRectangle: A=type, X=cell x, B=cell y, arg0=width, arg1=height (cells). The terrain around the cells is
; drawn again as the original would draw it, at the end of Present: see boss_terrain.asm.
Main_SetCellRectangle
            sta rect_type
            stb rect_y
            stx rect_x
            ldd lvl_regions
            beq .unmarked
            FAR region_mark
.unmarked
            lda <arg1+1
            sta rect_rows
.row        ldx rect_x
            stx rect_cx
            lda <arg0+1
            sta rect_cols
.col        lda rect_type
            ldx rect_cx
            ldb rect_y
            jsr Main_SetCellType
            ldx rect_cx
            leax 1,x
            stx rect_cx
            dec rect_cols
            bne .col
            inc rect_y
            dec rect_rows
            bne .row
            rts

; A destroyed block: X=cell x, B=cell y, whose cell has been marked changed. It leaves the terrain for good: it is erased once and
; never drawn again, since terrain_image and tl_insert look at the cell.
Terrain_Hole
            lda #1
            sta blk_kills
            pshs y
            ldy <t5
            pshs y
            ldy <t4
            pshs y
            stx rect_x
            stb rect_y
            if VERT
            ; Turned: the cell's column is its row counted from the bottom, and its line its column.
            lda <lvl_h+1
            suba rect_y
            deca
            ldb #BLOCK_COLS
            mul
            std hole_rect
            ldd rect_x
            jsr Times12
            std hole_rect+2
            else
            tfr x,d
            jsr Times12
            asra
            rorb
            std hole_rect
            ldb rect_y
            clra
            jsr Times12
            std hole_rect+2
            endif
            ldd #BLOCK_COLS*256+BLOCK_LINES
            std hole_rect+4
            ldd #RECT_IMAGE
            std hole_rect+6
            jsr tl_block_gone
            ldy #hole_rect
            ldd <old_col
            std <t2
            ldd <old_top
            std <t3
            clr <t4
            jsr terrain_rect
            puls y
            sty <t4
            puls y
            sty <t5
            puls y,pc

; X, Y=the center of a block in the world. Its image is drawn again at the end of this tick's Present, which is about to erase the
; sprite that was over it. Not many of these can happen at once, and terrain repairs heal any that do not fit.
Block_Heal  ldb heal_n
            cmpb #HEAL_MAX
            bhs .out
            inc heal_n
            aslb
            aslb
            pshs u
            ldu #heal_list
            leau b,u
            if VERT
            ldd <vert_xm        ; turned: the column from the game's y, the line from its x
            pshs y
            subd ,s++
            subd #BLOCK_LINES/2
            asra
            rorb
            std ,u
            tfr x,d
            subd #BLOCK_LINES/2
            std 2,u
            else
            tfr x,d
            subd #BLOCK_COLS
            asra
            rorb
            std ,u
            tfr y,d
            subd #BLOCK_LINES/2
            std 2,u
            endif
            puls u
.out        rts

; Called by Present when it is done.
block_heal_run
            lda #BC_FG_ONLY     ; the black of the block's middle must not paint over a sprite
            sta blk_fg
            ldd <old_col
            std <t2
            ldd <old_top
            std <t3
            lda #1
            sta <t4
            ldd #BLOCK_COLS*256+BLOCK_LINES
            std hole_rect+4
            ldd #RECT_IMAGE
            std hole_rect+6
            ldx #heal_list
.next       ldd ,x
            std hole_rect
            ldd 2,x
            std hole_rect+2
            pshs x
            ldy #hole_rect
            jsr terrain_rect
            puls x
            ; The check for a dead block uses these.
            ldd <old_col
            std <t2
            ldd <old_top
            std <t3
            leax 4,x
            dec heal_n
            bne .next
            clr blk_fg
            rts

; End of Present, when the boss has set cells: regions whose look has changed are drawn again (region_redraw), and
; the display list's images over them blitted again, since the black went over them.
region_after
            clr reg_box+2       ; nothing drawn yet
            FAR region_redraw
            tst reg_box+2
            beq .out
            clr BANK_SELECT     ; the images' pixels
            pshs u
            ldu <dl_new
.next       cmpu <dl_newp
            bhs .done
            lda 2,u             ; column
            cmpa reg_box+2
            bhs .skip
            adda 4,u
            cmpa reg_box
            bls .skip
            lda 3,u             ; line
            cmpa reg_box+3
            bhs .skip
            adda 5,u
            bcs .draw
            cmpa reg_box+1
            bls .skip
.draw       jsr blit_draw
.skip       leau DL_SIZE,u
            bra .next
.done       puls u
.out        rts

; Main.PitCheck(depth, x, y): A=depth, X=world x, Y=world y. Returns A=first non-empty type within depth + 2 cells
; below, or EMPTY. Out of bounds reads as EMPTY here, unlike Main_GetCell.
Main_PitCheck
            sta pit_depth
            tfr x,d
            jsr Div12
            std pit_x
            tfr y,d
            jsr Div12
            stb pit_y
            clr pit_off
.loop       ldx pit_x
            ldb pit_y
            addb pit_off
            cmpx <lvl_w
            bhs .empty
            cmpb <lvl_h+1
            bhs .empty
            jsr Main_GetCell
            bra .have
.empty      clra
.have       inc pit_off
            tsta
            bne .out
            ldb pit_off
            decb
            cmpb pit_depth
            bls .loop
            clra
.out        rts

; Cell under a world position: X=world x, Y=world y. Returns A=type. Negative coordinates are out of bounds.
; X, Y=world position. Returns A=the type of the cell there. Keeps Y and U. This is the most asked question in the game, so
; the two divisions by 12 are in line here. The table answers (position / 4) / 3 for positions under 3072.
Cell_At     stx <t0
            sty <t3
            tfr y,d
            lbmi .oob
            cmpa #$0C
            bhs .slow
            lsra
            rorb
            lsra
            rorb
            ldy #div3_table
            ldb d,y             ; the row
            stb <t1
            cmpb <lvl_h+1
            bhs .oob2
            lda <grid_stride
            mul
            addd <lvl_grid
            std <t2
            ldd <t0
            bmi .oob2
            cmpa #$0C
            bhs .slowx
            lsra
            rorb
            lsra
            rorb
            ldb d,y             ; the column, which fits in a byte below 3072
            ldy <t3
            clra
            std <t0
            cmpd <lvl_w
            lbhs getcell_oob
            ldx <t2
            lsrb
            abx
            jmp getcell_tail
.slowx      ldy <t3
            jsr Div12
            tfr d,x
            ldb <t1
            jmp Main_GetCell
.slow       jsr Div12
            pshs b
            tfr x,d
            bmi .oob3
            jsr Div12
            tfr d,x
            puls b
            jmp Main_GetCell
.oob2       ldy <t3
            lda #PLATFORM
            rts
.oob3       leas 1,s
.oob        lda #PLATFORM
            rts

; A world rectangle, like ShadedRectangleWorld: X=x, Y=y, A=width, B=height (pixels), draw_color=palette index.
; Rounded to whole byte columns; clipped to the view.
TL_LONG     equ 24
Draw_RectWorld
            if VERT
            ; The game's rectangle, turned: x = vert_xm - y - height, y = x, and the width and height swap.
            pshs y
            exg a,b
            pshs d,x,y          ; 0,s=height 1,s=width 2,s=x 4,s=y
            ldd <vert_xm
            subd 4,s
            subb ,s
            sbca #0
            tfr d,x
            ldy 2,s
            puls d
            leas 4,s
            bsr rect_world_r
            puls y,pc
rect_world_r
            endif
            std <t2             ; width, height
            tfr x,d
            subd <cam_left
            bmi .lclip
            cmpd #292
            bge .out
            bra .xok
.lclip      addb <t2            ; starts left of the view: keep what remains
            adca #0
            bne .out
            tstb
            beq .out
            stb <t2
            ldd #0
.xok        lsra
            rorb
            addb #VIEW_COL0
            stb <t0             ; first column
            ; Width in columns, at least 1, trimmed to the screen.
            lda <t2
            inca
            lsra
            bne .wok
            lda #1
.wok        adda <t0
            cmpa #VIEW_COL0+VIEW_COLS
            bls .wok2
            lda #VIEW_COL0+VIEW_COLS
.wok2       suba <t0
            bls .out
            sta <t2
            tfr y,d
            subd <cam_top
            bmi .tclip
            cmpd #VIEW_H
            bge .out
            bra .yok
.tclip      addb <t2+1
            adca #0
            bne .out
            tstb
            beq .out
            stb <t2+1
            ldd #0
.yok        addb #VIEW_ROW0
            stb <t0+1
            ; Trim the bottom.
            addb <t2+1
            bcs .trimb
            cmpb #VIEW_ROW0+VIEW_H
            bls .hok
.trimb      lda #VIEW_ROW0+VIEW_H
            suba <t0+1
            sta <t2+1
.hok        ldd <t2
            ; A long one can cut across a solid rect: see Present. Only what is drawn counts: a beam off the view
            ; made the solid rects repaint whole on every step for nothing.
            cmpa #TL_LONG/2     ; columns
            bhs .long
            cmpb #TL_LONG
            blo .short
.long       inc tl_rect
.short      std <t1
            ldd <t0
            jmp raw_rect_entry
.out        rts

; Screen-space rectangle: A=video column, B=video line, t1=(w,h), draw_color.
raw_rect_entry
            ldx <dl_newp
            cmpx <dl_limit      ; before anything is written: past the list's end lie other variables
            bhs .full
            std 2,x
            ldd #0
            std ,x
            ldd <t1
            std 4,x
            lda <draw_color
            ldb #$11
            mul
            stb 7,x
            lda #BC_SOLID+BC_DST256
            sta 6,x
            leax DL_SIZE,x
            stx <dl_newp
            rts
.full       ldx <dl_dropped
            leax 1,x
            stx <dl_dropped
            rts

; Screen-space versions of the sprite calls: D=id, X=x, Y=y with (0,0) the top-left of the visible screen.
Draw_SpriteScreen
            pshs d
            tfr x,d
            addd <gcam_left
            tfr d,x
            tfr y,d
            addd <gcam_top
            tfr d,y
            puls d
            jmp Draw_Sprite
Draw_ColoredSpriteScreen
            pshs d
            tfr x,d
            addd <gcam_left
            tfr d,x
            tfr y,d
            addd <gcam_top
            tfr d,y
            puls d
            jmp Draw_ColoredSprite

; A glyph from font 2 in world space: B=glyph, X=x, Y=y. Colored when draw_color is non-zero; white otherwise.
Draw_Glyph  clra
            addd #FONT2_BASE
            tst <draw_color
            lbeq Draw_SpriteAny
            jmp Draw_ColoredSprite

; Sound.Play: A=id. Keeps B, X, Y, U. The board plays one sound at a time and a new command cuts off the last, so each sound
; has a priority and a time, in frames, for which only an equal or higher priority may cut it off. The same sound never
; restarts itself in that time, and priority 0 never cuts anything off.
Sound_Play  pshs x,b
            tfr a,b
            ldx #sound_commands
            abx
            lda ,x
            beq .out
            ldb SND_COUNT,x
            beq .expired
            cmpa snd_cmd
            beq .expired
            cmpb snd_pri
            bhs .take
.expired    pshs d
            ldd snd_until       ; the frames it is still protected for: 1 to 255, as long as protection lasts. Taken so, and not
            subd <frames        ; as frames-snd_until signed, which turns negative again 32768 frames on (9 minutes without a
            subd #1             ; sound), and then kept every lower sound out for 9 minutes more
            cmpd #255
            puls d              ; leaves the flags alone
            blo .out
.take       sta <snd_pending
            sta snd_cmd
            stb snd_pri
            ldb SND_COUNT*2,x
            clra
            addd <frames
            std snd_until
.out        puls b,x,pc

; X=a new entry for remains. Marks it if its box crosses a line between cells, where floors are. Keeps X and U.
still_mark
            if VERT
            bra .mark           ; floors do not lie across the renderer's lines here: every one is marked
            endif
            ldd S_ROW,x
            subd #VIEW_ROW0
            addd <old_top
            bmi .mark
            std <t0
            jsr Div12
            jsr Times12
            pshs d
            ldd <t0
            subd ,s++           ; B=lines down the cell
            addb S_W+1,x
            cmpb #12
            bhi .mark
            rts
.mark       lda S_STATE,x
            ora #SS_TERR
            sta S_STATE,x
            rts
