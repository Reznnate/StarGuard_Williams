; Man.as, ported from ../port/src/man.c at a fixed 30 Hz tick. Fixed ROM.

; Speeds are 8.8 pixels per tick: v * 256 / 30. Accelerations are 8.8 per tick: a * 256 / 900.
MAN_GROUND_ACCEL equ 109    ; 384 px/s^2
MAN_FRICTION     equ 218    ; 768
MAN_AIR_FRICTION equ 20     ; 72
MAN_GRAVITY      equ 113    ; 396
MAN_JUMP_SPEED   equ 819    ; 96 px/s
MAN_LIMIT_X      equ 512    ; 60 px/s
MAN_LIMIT_Y      equ 1024   ; 120 px/s
MAN_WALLSPEED    equ 102    ; 12 px/s, the speed kept when pressing into a wall
MAN_HARDLAND     equ 205    ; 24 px/s, above which landing makes a sound
MAN_JUMP_HEIGHT  equ 30
MAN_RUN_RATE     equ 171    ; run frames per tick, 8.8 (20 frames a second at 30 Hz)
MAN_RUN_FRAMES   equ 5
MAN_HOLSTER_T    equ 30     ; ticks
MAN_FIRE_RATE    equ 6
MAN_FIREANIM_T   equ 2
MAN_KEY_MARGIN   equ 3
MAN_INVULN_T     equ 90
; Half sizes in 8.8.
MAN_HALF_W       equ $0280  ; 2.5
MAN_HALF_H       equ $0300  ; 3.0

; Jump lift by rise: 89 * (1 - (rise / 25)^3) for rise 0..30, clamped to the range the C's fade allows.
man_lift    fcb 89,89,89,89,89,88,88,87,87,86,85,84,82,81,79,77,74,72,69,65,61,57,53,48,42,36,29,22,14,5,0

; Man(heading, cell x, cell y): A=1 or -1, X=cell x, B=cell y.
Man_New     sta <man_heading
            pshs b,x
            ; x = cell * 12 + 6, y = cell * 12 + 6 + 3.
            tfr x,d
            bsr .times12
            addd #6
            std <man_x
            clr <man_x+2
            ldb ,s
            clra
            bsr .times12
            addd #9
            std <man_y
            clr <man_y+2
            clr <man_vx
            clr <man_vx+1
            clr <man_vy
            clr <man_vy+1
            clr <man_run_t
            clr <man_run_t+1
            lda #MF_ACTIVE+MF_INVULN+MF_FREEFALL+MF_HOLSTER+MF_DESCEND+MF_FIREOK
            sta <man_flags
            ldd <now
            std <man_spawn_t
            subd #100           ; no recent shot, ledge or key press
            std <man_fire_t
            std <man_unh_t
            std <man_ledge_t
            std <man_jkey_t
            jsr Man_DropLocation
            std <man_jump_y
            tst <death_cam
            bne .out
            ; Draw.SetCamera(x, drop), then offset the man camera behind the heading.
            tfr d,y
            ldx <man_x
            jsr Camera_Set
            ldb #2*DRAW_DEAD_ZONE
            lda <man_heading
            bmi .left
            negb
            sex
            bra .off
.left       clra
.off        addd <man_x
            std <camm_x
            lda #1
            sta <cam_lock
            ; Nudge = 24 pixels toward the heading.
            ldd #CAM_NUDGE_MAX
            tst <man_heading
            bpl .nudge
            ldd #-CAM_NUDGE_MAX
.nudge      std <cam_nudge
            jsr Camera_Apply
.out        puls b,x,pc
.times12    aslb                ; D * 12
            rola
            aslb
            rola
            std <t0
            aslb
            rola
            addd <t0
            rts

; Lowest free y under the man: Man.GetDropLocation. Returns D.
Man_DropLocation
            ldd <man_x
            jsr Div12
            tfr d,x
            stx <t2+0
            ldd <man_y
            jsr Div12
            stb <t4+1
            ; t2 is used by GetCell, so keep the column on the stack.
.down       pshs x
            ldb <t4+1
            jsr Main_GetCell
            puls x
            tsta
            bne .hit
            inc <t4+1
            bra .down
.hit        ldb <t4+1
            clra
            aslb
            rola
            aslb
            rola
            std <t0
            aslb
            rola
            addd <t0
            subd #3
            rts

; Man.Update.
Man_Update  lda <man_flags
            ; Invulnerability ends with time.
            bita #MF_INVULN
            beq .inv_done
            ldd <now
            subd <man_spawn_t
            cmpd #MAN_INVULN_T
            bls .inv_done
            lda <man_flags
            anda #~MF_INVULN&$FF
            sta <man_flags
.inv_done   lda <inp_dir
            tst <man_lock
            beq .have_dir
            clra
.have_dir   sta <man_dir
            lda <man_flags
            bita #MF_FREEFALL
            bne .air

            ; ---- on the ground ----
            tst <man_dir
            beq .stand
            lda <man_dir
            cmpa <man_heading
            beq .sameway
            sta <man_heading
            clr <man_run_t
            clr <man_run_t+1
.sameway    lbsr man_accel
            ldd <man_run_t
            addd #MAN_RUN_RATE
            std <man_run_t
            ; frame = run position % 5 + 1, plus 12 when the gun is out.
            lda <man_run_t
.mod5       cmpa #MAN_RUN_FRAMES
            blo .modok
            suba #MAN_RUN_FRAMES
            bra .mod5
.modok      inca
            ldb <man_flags
            bitb #MF_HOLSTER
            bne .runh
            adda #12
.runh       sta <man_frame
            bra .jumpkey
.stand      clra
            ldb <man_flags
            bitb #MF_HOLSTER
            bne .standset
            ldd <now
            subd <man_fire_t
            cmpd #MAN_FIREANIM_T
            bhs .gun_idle
            lda #25
            bra .standset
.gun_idle   lda #24
.standset   sta <man_frame

.jumpkey    lda <inp_buttons
            bita #BTN_JUMP
            beq .ground_done
            ldb <man_flags
            bitb #MF_NOJUMP
            bne .keymark
            ldd <now
            subd <man_jkey_t
            cmpd #MAN_KEY_MARGIN
            bhs .keymark
            jsr man_jump
.keymark    lda <man_flags
            bita #MF_JKEYDOWN
            bne .ground_done
            ora #MF_JKEYDOWN
            sta <man_flags
            ldd <now
            std <man_jkey_t
.ground_done
            lda <man_flags
            bita #MF_FREEFALL
            lbeq .after_air      ; a jump just now falls through to the air code, as in the C

            ; ---- in the air ----
.air        ldd <man_y
            subd <man_jump_y
            std <man_rise       ; negative while rising
            lda <inp_buttons
            bita #BTN_JUMP
            beq .air_nokey
            lda <man_flags
            bita #MF_DESCEND
            bne .air_desc
            ; Holding jump while rising: a lift that fades with height.
            ldd <man_rise
            coma
            comb
            addd #1             ; rise as a positive number
            bpl .rise_pos
            ldd #0
.rise_pos   cmpd #30
            bls .rise_ok
            ldd #30
.rise_ok    ldx #man_lift
            ldb d,x
            clra
            std <t0
            ldd <man_vy
            subd <t0
            std <man_vy
            lbsr man_key_mark
            bra .air_nokey
.air_desc   lda <man_flags
            bita #MF_JKEYDOWN
            bne .air_nokey
            lbsr man_key_mark
            ldd <now
            subd <man_ledge_t
            cmpd #MAN_KEY_MARGIN
            bhs .air_nokey
            jsr man_jump
.air_nokey  ldd <man_rise
            cmpd #-MAN_JUMP_HEIGHT
            bge .notcap
            ldd <man_jump_y
            subd #MAN_JUMP_HEIGHT
            std <man_y
            clr <man_y+2
            clr <man_vy
            clr <man_vy+1
            lda <man_flags
            ora #MF_DESCEND
            sta <man_flags
            bra .capdone
.notcap     ble .capdone
            clr <cam_lock
.capdone    ldd <man_vy
            bmi .rising
            lda <man_flags
            ora #MF_DESCEND
            sta <man_flags
.rising     tst <man_dir
            beq .noairdir
            lda <man_dir
            sta <man_heading
            jsr man_accel
.noairdir   lda <man_flags
            bita #MF_HOLSTER
            beq .air_gun
            lda #26
            bra .air_frame
.air_gun    lda #28
            ldx <now
            stx <man_unh_t
.air_frame  ldb <man_flags
            bitb #MF_DESCEND
            beq .air_set
            inca
.air_set    sta <man_frame

            ; ---- friction ----
.after_air  tst <man_dir
            bne .limits
            ldx #MAN_FRICTION
            lda <man_flags
            bita #MF_FREEFALL
            beq .fric
            ldx #MAN_AIR_FRICTION
.fric       stx <t0
            ldd <man_vx
            bmi .fneg
            beq .limits
            subd <t0
            bpl .fstore
            ldd #0
            bra .fstore
.fneg       addd <t0
            bmi .fstore
            ldd #0
.fstore     std <man_vx

            ; ---- limits and movement ----
.limits     ldd <man_vx
            cmpd #MAN_LIMIT_X
            ble .x1
            ldd #MAN_LIMIT_X
.x1         cmpd #-MAN_LIMIT_X
            bge .x2
            ldd #-MAN_LIMIT_X
.x2         std <man_vx
            ldd <man_vy
            cmpd #MAN_LIMIT_Y
            ble .y1
            ldd #MAN_LIMIT_Y
.y1         cmpd #-MAN_LIMIT_Y
            bge .y2
            ldd #-MAN_LIMIT_Y
.y2         std <man_vy
            ; x += vx
            ldd <man_vx
            ldx #man_x
            jsr add_8_8
            ; vy += gravity, y += vy
            ldd <man_vy
            addd #MAN_GRAVITY
            std <man_vy
            ldx #man_y
            jsr add_8_8

            ; Holster after a while.
            ldd <now
            subd <man_unh_t
            cmpd #MAN_HOLSTER_T
            bls .noholster
            lda <man_flags
            ora #MF_HOLSTER
            sta <man_flags
.noholster  lda <inp_buttons
            bita #BTN_JUMP
            bne .keepkeys
            lda <man_flags
            anda #(~(MF_NOJUMP+MF_JKEYDOWN))&$FF
            sta <man_flags
.keepkeys
            ; Sprite: right-facing frames, plus 6 facing left.
            ldb <man_frame
            lda <man_heading
            bpl .right
            addb #6
.right      clra
            std <man_sprite

            jsr man_collide

            ; ---- firing ----
            lda <inp_buttons
            bita #BTN_FIRE
            beq .nofire
            lda <man_flags
            anda #~MF_HOLSTER&$FF
            sta <man_flags
            ldd <now
            subd <man_fire_t
            cmpd #MAN_FIRE_RATE
            bhi .shoot
            lda <man_flags
            bita #MF_FIREOK
            beq .firedone
.shoot      ldd <now
            std <man_fire_t
            std <man_unh_t
            jsr Man_Fire
            lda <man_flags
            anda #~MF_FIREOK&$FF
            sta <man_flags
            bra .firedone
.nofire     lda <man_flags
            ora #MF_FIREOK
            sta <man_flags
.firedone   rts

man_accel   lda <man_heading
            bmi .neg
            ldd <man_vx
            addd #MAN_GROUND_ACCEL
            std <man_vx
            rts
.neg        ldd <man_vx
            subd #MAN_GROUND_ACCEL
            std <man_vx
            rts

man_key_mark
            lda <man_flags
            bita #MF_JKEYDOWN
            bne .out
            ora #MF_JKEYDOWN
            sta <man_flags
            ldd <now
            std <man_jkey_t
.out        rts

man_jump    ldd #-MAN_JUMP_SPEED
            std <man_vy
            ldd <man_y
            std <man_jump_y
            lda <man_flags
            ora #MF_FREEFALL+MF_NOJUMP
            anda #~MF_DESCEND&$FF
            sta <man_flags
            lda #1
            sta <cam_lock
            lda #SND_JUMP
            jsr Sound_Play
            ldx <man_x
            ldd <man_y
            addd #2
            tfr d,y
            jmp JumpEffect_New

; Adds a signed 8.8 value in D to the 16.8 number at X.
add_8_8     tsta
            bmi .neg
            addd 1,x
            std 1,x
            bcc .out
            inc ,x
.out        rts
.neg        addd 1,x
            std 1,x
            bcs .out2
            dec ,x
.out2       rts

; Collision against the 3x3 cells around the man: the C's loop, in row then column order.
man_collide clr <man_ground
            ldd <man_x
            jsr Div12
            lbsr .minus1
            std <man_base_x
            ldd <man_y
            jsr Div12
            lbsr .minus1
            stb <man_cell_y
            lda #3
            sta <man_rows
            ; The man overlaps one to four of the nine cells. The test man_touch would make comes first, so the others cost
            ; no read of the grid. It is made afresh for each cell: a touch can move the man. Those it does read are kept, since
            ; this runs several times a tick around the same cells.
            lda #12
            ldb <man_cell_y
            mul
            stb mc_row
            lda #12
            ldb <man_base_x+1
            mul
            stb mc_col0
            clr mc_hit
.row        lda <man_y+1
            suba mc_row
            ldb <man_y+2
            addd #MAN_HALF_H
            bgt .row_on
            ; This row is below him, and so are the rest, unless a touch has moved him.
            tst mc_hit
            lbne .nextrow
            lbra .rows_end
.row_on     cmpd #12*256+2*MAN_HALF_H
            lbge .nextrow
            ldd <man_base_x
            std <man_cell_x
            lda mc_col0
            sta mc_col
            lda #3
            sta <man_cols
.col        lda <man_x+1
            suba mc_col
            ldb <man_x+2
            addd #MAN_HALF_W
            bgt .col_on
            ; This column is right of him, and so are the rest, unless a touch has moved him.
            tst mc_hit
            bne .next
            bra .nextrow
.col_on     cmpd #12*256+2*MAN_HALF_W
            bge .next
            ; The cell. Those the man can touch at once all differ in the low bit of a coordinate.
            lda <man_cell_x+1
            anda #1
            ldb <man_cell_y
            andb #1
            aslb
            stb <t0
            adda <t0
            asla
            asla
            ldx #mc_cells
            leax a,x
            ldd ,x
            cmpd <man_cell_x
            bne .read
            lda 2,x
            cmpa <man_cell_y
            bne .read
            lda 3,x
            bra .have
.read       pshs x
            ldx <man_cell_x
            ldb <man_cell_y
            jsr Main_GetCell
            puls x
            ldb <man_cell_x
            stb ,x
            ldb <man_cell_x+1
            stb 1,x
            ldb <man_cell_y
            stb 2,x
            sta 3,x
.have       tsta
            beq .next
            sta <man_cell_t
            sta mc_hit
            jsr man_touch
.next       ldx <man_cell_x
            leax 1,x
            stx <man_cell_x
            lda mc_col
            adda #12
            sta mc_col
            dec <man_cols
            bne .col
.nextrow    inc <man_cell_y
            lda mc_row
            adda #12
            sta mc_row
            dec <man_rows
            lbne .row
.rows_end
            ; Walked off a ledge.
            lda <man_flags
            bita #MF_FREEFALL
            bne .out
            tst <man_ground
            bne .out
            ora #MF_FREEFALL
            sta <man_flags
            ; speedX /= 4, speedY = 0
            ldd <man_vx
            asra
            rorb
            asra
            rorb
            std <man_vx
            clr <man_vy
            clr <man_vy+1
            ldd <now
            std <man_ledge_t
.out        rts
.minus1     cmpd #0             ; int(v / 12 - 1): truncation makes both 0 and 1 give 0
            beq .zero
            subd #1
.zero       rts

; Tests the man against the cell in man_cell_x/man_cell_y, of type man_cell_t.
; Offsets below are 8.8, relative to the cell's top-left corner; the distances are small enough for 16 bits.
man_touch   ldb <man_cell_x+1
            lda #12
            mul
            stb <t0             ; the low byte of the cell's left edge is all this needs
            lda <man_x+1
            suba <t0
            ldb <man_x+2
            std <man_rx         ; relx = man_x (low 16 bits) - cell left
            ldb <man_cell_y
            lda #12
            mul
            stb <t0
            lda <man_y+1
            suba <t0
            ldb <man_y+2
            std <man_ry
            ; Separated on any axis? d_* are the four overlaps from the C's GetDisplacement.
            ldd <man_rx
            addd #MAN_HALF_W
            lble .out
            std <man_dl         ; a.right - b.left
            ldd #12*256+MAN_HALF_W
            subd <man_rx
            lble .out
            std <man_dr         ; b.right - a.left
            ldd <man_ry
            addd #MAN_HALF_H
            lble .out
            std <man_dt         ; a.under - b.top
            ldd #12*256+MAN_HALF_H
            subd <man_ry
            lble .out
            std <man_du         ; b.under - a.top

            ; Choose the smallest overlap under one tile whose neighbor cell is passable.
            ldd #$7FFF
            std <man_best
            clr <man_side       ; default side is RIGHT, with no displacement
            clr <man_sign
            ldd <man_dl
            cmpd #12*256
            bhs .try_r
            ldx <man_cell_x
            leax -1,x
            ldb <man_cell_y
            jsr cell_open
            bne .try_r
            ldd <man_dl
            std <man_best
            lda #2              ; LEFT
            sta <man_side
            lda #-1
            sta <man_sign
.try_r      ldd <man_dr
            cmpd #12*256
            bhs .try_t
            cmpd <man_best
            bge .try_t
            ldx <man_cell_x
            leax 1,x
            ldb <man_cell_y
            jsr cell_open
            bne .try_t
            ldd <man_dr
            std <man_best
            clr <man_side       ; RIGHT
            lda #1
            sta <man_sign
.try_t      ldd <man_dt
            cmpd #12*256
            bhs .try_u
            cmpd <man_best
            bge .try_u
            ldx <man_cell_x
            ldb <man_cell_y
            decb
            jsr cell_open
            bne .try_u
            ldd <man_dt
            std <man_best
            lda #1              ; TOP
            sta <man_side
            lda #-1
            sta <man_sign
.try_u      ldd <man_du
            cmpd #12*256
            bhs .apply
            cmpd <man_best
            bge .apply
            ldx <man_cell_x
            ldb <man_cell_y
            incb
            jsr cell_open
            bne .apply
            ldd <man_du
            std <man_best
            lda #3              ; UNDERSIDE
            sta <man_side
            lda #1
            sta <man_sign

.apply      lda <man_cell_t
            cmpa #PLATFORM
            beq .solid
            cmpa #PLATFORM_DESTRUCTIBLE
            beq .solid
            cmpa #EXPLODING_PLATFORM
            beq .solid
            cmpa #FLOATY_PLATFORM
            lbeq .floaty
            cmpa #LAVA
            lbeq .lava
            cmpa #LAVA2
            lbeq .lava2
            cmpa #GOAL
            lbeq .goal
.out        rts

.solid      tst <man_sign
            beq .sides
            ; The displacement goes along the axis of the chosen side.
            ldd <man_best
            tst <man_sign
            bpl .disp_pos
            coma
            comb
            addd #1
.disp_pos   ldb <man_side
            pshs b
            ldd <man_best
            tst <man_sign
            bpl .disp2
            coma
            comb
            addd #1
.disp2      ldx #man_x
            tst ,s
            beq .disp_x         ; RIGHT
            pshs a
            lda 1,s
            cmpa #2
            puls a
            beq .disp_x         ; LEFT
            ldx #man_y
.disp_x     leas 1,s
            jsr add_8_8
.sides      lda <man_side
            beq .s_right
            cmpa #1
            beq .s_top
            cmpa #2
            beq .s_left
            ; UNDERSIDE: stop rising.
            ldd <man_vy
            bpl .u1
            clr <man_vy
            clr <man_vy+1
.u1         lda <man_flags
            ora #MF_DESCEND
            sta <man_flags
            rts
.s_right    ldd <man_vx
            cmpd #-MAN_WALLSPEED
            bge .sr1
            ldd #-MAN_WALLSPEED
            std <man_vx
.sr1        rts
.s_left     ldd <man_vx
            cmpd #MAN_WALLSPEED
            ble .sl1
            ldd #MAN_WALLSPEED
            std <man_vx
.sl1        rts
.s_top      ldd <man_vy
            cmpd #MAN_HARDLAND
            ble .soft
            lda #SND_LAND
            jsr Sound_Play
.soft       ldd <man_vy
            ble .st1
.land       clr <man_vy
            clr <man_vy+1
            lda #1
            sta <man_ground
            lda <man_flags
            anda #~MF_FREEFALL&$FF
            sta <man_flags
            clr <cam_lock
.st1        rts

            ; A one-way platform catches the man only when he is falling onto its top.
.floaty     ldd <man_vy
            ble .fl_out
            ; overlap = cell top - (y + 3), so ry + 3 > 0 is already known; require y within 5 of the catch line.
            ldd <man_dt
            cmpd #5*256
            bge .fl_out
            ; Horizontal: |x - cell center| < 6 + 2.5.
            ldd <man_rx
            subd #6*256
            bpl .fl_abs
            coma
            comb
            addd #1
.fl_abs     cmpd #6*256+MAN_HALF_W
            bge .fl_out
            ; The original plays this at a volume that goes with the speed, so standing or walking here, caught again each
            ; tick, is silent. With no volume, it plays as a floor's landing does: only a hard one.
            ldd <man_vy
            cmpd #MAN_HARDLAND
            ble .fl_soft
            lda #SND_LAND
            jsr Sound_Play
.fl_soft
            ; y += overlap, a move up by man_dt.
            ldd <man_dt
            coma
            comb
            addd #1
            ldx #man_y
            jsr add_8_8
            bra .land
.fl_out     rts

.lava       lda #LAVA_DEATH
            bra .die
.lava2      lda #LAVA2_DEATH
.die        ldb <man_flags
            bitb #MF_ACTIVE
            beq .fl_out
            jmp Man_Die
.goal       lda #1
            sta <level_done
            rts

; X=cell x, B=cell y. Z set when the cell is passable for GetDisplacement: EMPTY, LAVA or FLOATY_PLATFORM.
; Out of bounds counts as blocked, as `undefined` compared unequal in the original.
cell_open   cmpx <lvl_w
            bhs .no
            cmpb <lvl_h+1
            bhs .no
            jsr Main_GetCell
            tsta
            beq .yes
            cmpa #LAVA
            beq .yes
            cmpa #FLOATY_PLATFORM
            beq .yes
.no         andcc #$FB
            rts
.yes        orcc #$04
            rts

; Man.DrawSelf: flashes white while invulnerable, one tick on, one off.
Man_Draw    lda <man_flags
            bita #MF_ACTIVE
            beq .out
            ldx <man_x
            leax -6,x
            ; One line above the C's position. His feet would otherwise share a line with the ground, and erasing him takes
            ; the ground with him: flat terrain is not redrawn while scrolling, so that leaves a trail of dashes.
            ldy <man_y
            leay -10,y
            lda <man_flags
            bita #MF_INVULN
            beq .plain
            lda <now+1
            lsra
            bcc .plain
            lda #COLOR_WHITE
            sta <draw_color
            ldd <man_sprite
            jmp Draw_ColoredSprite
.plain      ldd <man_sprite
            jmp Draw_Sprite
.out        rts

; Man.Fire: X = x + 5 * heading, Y = y - 2, A = heading.
Man_Fire    ldb <man_heading
            lda #5
            mul                 ; magnitude only; heading is 1 or -1
            tst <man_heading
            bpl .pos
            ldd #-5
            bra .x
.pos        ldd #5
.x          addd <man_x
            tfr d,x
            ldd <man_y
            subd #2
            tfr d,y
            lda <man_heading
            jsr SpacemanLaser_New
            lda #SND_LASER
            jmp Sound_Play

; Man.Die: A=death type. Respawn is in game.asm.
Man_Die     jmp Game_ManDie
