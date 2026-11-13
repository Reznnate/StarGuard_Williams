; The terrain the boss changes, as the original draws it: see tools/boss_terrain.py. Bank 9, level 9's own bank, which
; holds the region table, so this runs with the level's bank in view (FAR, or the terrain routines, which select it).
; Main_SetCellRectangle marks the regions near the cells it sets (region_mark). At the end of Present the look of each
; marked region is worked out from the cells (region_redraw); a region whose look has changed is drawn again with the
; terrain rects of its new look (only those that differ are erased or drawn), and region_after in fixed
; ROM blits again the sprites over it. The terrain
; routines ask rect_hidden whether to draw a rect marked RECT_HIDE.

; The region table (boss_terrain.table): a count, the look table's address, the absent list's, then the regions.
RT_VIS      equ 1               ; per level rect, 2 bytes: for one marked RECT_HIDE its region and the looks it shows in
RT_ABSENT   equ 3               ; blocks the level begins without: a count, then byte in the map of changed cells (2), bit
RT_REG      equ 5
RG_COL0     equ 0               ; first byte column, word
RG_COL1     equ 2               ; end byte column
RG_ROW0     equ 4               ; first line
RG_ROW1     equ 6               ; end line
RG_KEYS     equ 8               ; its keys: a count, then byte in the map of changed cells (2), bit, grid is a platform
RG_LOOKS    equ 10              ; its readings: a count, then key bits and the look each calls for
RG_RECTS    equ 12              ; its rects: a count, then their addresses
RG_SIZE     equ 14

; Main_SetCellRectangle's rect (rect_x, rect_y, arg0, arg1, in cells): the regions it touches, or touches the cells
; around, may look different now. Keeps everything Main_SetCellRectangle uses.
region_mark pshs d,x,y,u
            leas -9,s           ; 0 first column, 2 end column, 4 first line, 6 end line, 8 regions left
            ldd rect_x
            subd #1
            jsr Times12
            asra
            rorb
            std ,s
            ldb <arg0+1
            clra
            addd rect_x
            addd #1
            jsr Times12
            asra
            rorb
            std 2,s
            ldb rect_y
            clra
            subd #1
            jsr Times12
            std 4,s
            ldb rect_y
            clra
            addb <arg1+1
            adca #0
            addd #1
            jsr Times12
            std 6,s
            ldx lvl_regions
            lda ,x
            sta 8,s
            leay RT_REG,x
            ldu #reg_dirty
.next       ldd RG_COL0,y
            cmpd 2,s
            bge .skip
            ldd RG_COL1,y
            cmpd ,s
            ble .skip
            ldd RG_ROW0,y
            cmpd 6,s
            bge .skip
            ldd RG_ROW1,y
            cmpd 4,s
            ble .skip
            lda #1
            sta ,u
            sta reg_any
.skip       leay RG_SIZE,y
            leau 1,u
            dec 8,s
            bne .next
            leas 9,s
            puls d,x,y,u,pc

; End of Present: each marked region's look from its cells, and a region whose look has changed drawn again.
; reg_box is left as the screen box of what was drawn (end column 0 if nothing).
region_redraw
            pshs x,y,u
            clr reg_any
            ldx lvl_regions
            lda ,x
            pshs a              ; regions left
            leay RT_REG,x
            ldu #reg_look
.next       tst REG_MAX,u
            beq .skip
            clr REG_MAX,u
            jsr rg_look
            ldb ,u
            cmpa ,u
            beq .skip
            sta ,u
            clr vl_valid        ; the terrain lists are made again for the new look
            clr tl_valid
            jsr rg_draw
.skip       leay RG_SIZE,y
            leau 1,u
            dec ,s
            bne .next
            leas 1,s
            puls x,y,u,pc

; Y=region. Returns A=its look: the one its keys call for, or 0. A key reads PLATFORM if its grid cell is a platform
; and not changed, or empty and changed (Main_GetCell's answer, from the map of changed cells). Keeps Y, U.
rg_look     pshs y,u
            leas -9,s           ; 0-3 key bits, 6 keys left, 7 this key's bit, 8 bytes of bits
            clr ,s
            clr 1,s
            clr 2,s
            clr 3,s
            ldx RG_KEYS,y
            lda ,x+
            sta 6,s
            lda #$80
            sta 7,s
            leau ,s
.key        ldd ,x++
            addd <class_map
            tfr d,y
            lda ,y
            anda ,x+            ; changed?
            beq .grid
            lda #1
.grid       eora ,x+
            beq .off
            lda 7,s
            ora ,u
            sta ,u
.off        lsr 7,s
            bcc .same
            leau 1,u            ; on to the next byte of bits
            ror 7,s
.same       dec 6,s
            bne .key
            ldy 9,s
            ldx RG_KEYS,y
            lda ,x
            adda #7
            lsra
            lsra
            lsra
            sta 8,s
            ldx RG_LOOKS,y
            lda ,x+
            sta 6,s
            beq .none
.pat        leau ,s
            ldb 8,s
            pshs x
.cmp        lda ,x+
            cmpa ,u+
            bne .no
            decb
            bne .cmp
            lda ,x              ; this reading's look
            leas 2,s
            bra .out
.no         puls x
            ldb 8,s
            abx
            leax 1,x
            dec 6,s
            bne .pat
.none       clra
.out        leas 9,s
            puls y,u,pc

; Y=region, A=its new look, B=its old one. On screen, erases the rects the old look shows and the new does not, then
; draws those the new shows and the old did not, and adds its box to reg_box. Off screen it is left to the terrain
; lists, made again for the new look. Keeps Y, U.
rg_draw     pshs y,u
            leas -3,s           ; 0 the new look's bit, 1 the old's, 2 rects left
            bsr .bit
            sta ,s
            tfr b,a
            bsr .bit
            sta 1,s
            jsr rg_box
            bcs .out
            ldd <old_col
            std <t2
            ldd <old_top
            std <t3
            clr <t4             ; erase
            ldb 1,s
            lda ,s
            bsr .pass
            lda #1
            sta <t4             ; draw
            ldb ,s
            lda 1,s
            bsr .pass
.out        leas 3,s
            puls y,u,pc
            ; A=look number: A=its bit.
.bit        pshs b
            ldb #1
.b1         tsta
            beq .b2
            aslb
            deca
            bra .b1
.b2         tfr b,a
            puls b,pc
            ; Each rect of the region that shows in look bit B and not in A goes through terrain_rect.
.pass       pshs d              ; 0 not, 1 in, 2 return, 4 rg_draw's frame: 6 rects left, 7 the region
            ldy 7,s
            ldx RG_RECTS,y
            lda ,x+
            beq .p3
            sta 6,s
.p1         ldy ,x++
            tfr y,d
            subd <lvl_rects
            lsra
            rorb
            lsra
            rorb
            pshs x
            ldx lvl_regions
            addd RT_VIS,x
            tfr d,x
            ldb 1,x             ; the looks it shows in
            puls x
            bitb 1,s
            beq .p2
            bitb ,s
            bne .p2
            pshs x
            ldd <old_col        ; terrain_rect may have moved them
            std <t2
            ldd <old_top
            std <t3
            jsr terrain_rect_any ; past rect_hidden, which already has the new look
            puls x
.p2         dec 6,s
            bne .p1
.p3         puls d,pc

; Y=region: its box on screen, clipped to the view, joined to reg_box. Carry set if none of it is in view.
rg_box      leas -4,s           ; first column, first line, end column, end line
            ldd RG_COL0,y
            bsr .col
            stb ,s
            ldd RG_COL1,y
            bsr .col
            stb 2,s
            ldd RG_ROW0,y
            bsr .row
            stb 1,s
            ldd RG_ROW1,y
            bsr .row
            stb 3,s
            lda ,s
            cmpa 2,s
            bhs .none           ; not in view
            lda 1,s
            cmpa 3,s
            bhs .none
            tst reg_box+2
            bne .join
            ldd ,s
            std reg_box
            ldd 2,s
            std reg_box+2
            bra .out
.join       lda ,s
            cmpa reg_box
            bhs .j1
            sta reg_box
.j1         lda 1,s
            cmpa reg_box+1
            bhs .j2
            sta reg_box+1
.j2         lda 2,s
            cmpa reg_box+2
            bls .j3
            sta reg_box+2
.j3         lda 3,s
            cmpa reg_box+3
            bls .out
            sta reg_box+3
.out        leas 4,s
            andcc #$FE
            rts
.none       leas 4,s
            orcc #$01
            rts
            ; D=byte column in the world: B=video column, clamped to the view.
.col        subd <old_col
            bpl .c1
            ldb #VIEW_COL0
            rts
.c1         cmpd #VIEW_COLS
            bls .c2
            ldb #VIEW_COLS
.c2         addb #VIEW_COL0
            rts
            ; D=line in the world: B=video line, clamped to the view.
.row        subd <old_top
            bpl .r1
            ldb #VIEW_ROW0
            rts
.r1         cmpd #VIEW_H
            bls .r2
            ldb #VIEW_H
.r2         addb #VIEW_ROW0
            rts

; Y=a rect marked RECT_HIDE: carry set if it does not show in its region's look now. The look table gives each rect its
; region and the looks it shows in. Keeps everything.
rect_hidden pshs d,x
            tfr y,d
            subd <lvl_rects
            lsra                ; 8 bytes a rect, 2 a look table entry
            rorb
            lsra
            rorb
            ldx lvl_regions
            addd RT_VIS,x
            tfr d,x
            ldb ,x              ; its region
            pshs x
            ldx #reg_look
            lda b,x             ; that region's look
            puls x
            ldb 1,x             ; the looks it shows in
.shift      tsta
            beq .bit
            lsrb
            deca
            bra .shift
.bit        lsrb
            bcs .shown
            orcc #$01
            puls d,x,pc
.shown      andcc #$FE
            puls d,x,pc
