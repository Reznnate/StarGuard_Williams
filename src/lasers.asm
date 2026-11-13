; lasers/*.as, ported from ../port/src/lasers.c. Fixed ROM.

; ---- SpacemanLaser.as ---------------------------------------------------------------------------
SPACEMANLASER_SPEED equ 1092    ; 128 px/s
SPACEMANLASER_RANGE equ 108
SL_STARTX   equ L_DATA

spaceman_laser_vt fdb SpacemanLaser_Update,0

; X=x, Y=y, A=heading (1 or -1). Returns U=laser or Z set.
SpacemanLaser_New
            pshs a,x,y
            ldx #spaceman_laser_vt
            lda #ALIENS
            jsr Laser_Alloc
            beq .full
            puls a,x,y
            stx L_X,u
            stx SL_STARTX,u
            sty L_Y,u
            ldb #4
            stb L_SIZEX,u
            tsta
            bmi .left
            ldd #SPACEMANLASER_SPEED
            bra .set
.left       ldd #-SPACEMANLASER_SPEED
.set        std L_VX,u
            andcc #$FB
            rts
.full       puls a,x,y,pc

SpacemanLaser_Update
            ldd L_VX,u
            ADD_8_8U L_X
            jsr Laser_CellHere
            cmpa #PLATFORM
            bne .inair
            lda L_FLAGS,u
            ora #LF_HITWALL
            anda #~LF_ACTIVE&$FF
            sta L_FLAGS,u
            lda #SND_MISS
            jsr Sound_Play
            ; The impact effect sits on the wall face.
            ldd L_X,u
            jsr Div12
            jsr Times12
            tst L_VX,u
            bmi .from_right
            subd #1
            bra .impact
.from_right addd #12
.impact     tfr d,x
            ldy L_Y,u
            lda #COLOR_GREEN
            jmp LaserImpact_New
            ; It ends once past its range and out of the player's sight. Most ticks it is still in range.
.inair      ldd L_X,u
            subd SL_STARTX,u
            addd #SPACEMANLASER_RANGE
            cmpd #SPACEMANLASER_RANGE*2
            bls .out
            ldx L_X,u
            ldy L_Y,u
            jsr Main_OnScreen
            beq .out
            lda L_FLAGS,u
            anda #~LF_ACTIVE&$FF
            sta L_FLAGS,u
.out        rts

; ---- the rest of the family ----------------------------------------------------------------------
; Every constructor below preserves the caller's U (and A, B, Y), and returns X=new laser with Z clear, or Z set if
; nothing was made. The record comes back in X and not U, because U must survive for entity code to go on using self.
;
;   AlienLaser_New             X=x Y=y A=speed: the C's multiplier, the heading, 1 or -1
;   AlienLaserVertical_New     X=x Y=y A=speed: 1 or -1
;   AllyLaser_New              X=x Y=y A=speed: 1 or -1
;   ReboundLaser_New           X=x Y=y arg0=speed (signed 8.8; the C's 128*heading px/s is +-1092)
;   SightChecker_New           X=x Y=y arg0=speed (signed 8.8; the C's 192*heading px/s is +-1638)
;   SpacemanLaserVertical_New  X=x Y=y arg0=heading: really a speed (signed 8.8; the C's 128*heading px/s is +-1092)
;   AreaEffect_New             X=c(x) Y=d(y) A=a(size) B=b(target)
;   Laser2_New, Laser5_New     X=x Y=y arg0=target x arg1=target y
;   Laser3_New                 X=x Y=y D=speed (8.8) arg0=target x arg1=target y. color is dropped: the C never draws it
;   Laser4_New                 X=x Y=y D=speed (8.8) arg0=target x arg1=target y
;                              Speeds: LASER3_SPEED_1 48 px/s=410, LASER3_SPEED_2 72=614, LASER4_SPEED_1 48=410, _2 30=256
;   LaserBeam_New              X=b(x1) Y=c(y1) A=a(orientation: 0 horizontal, 1 vertical) arg0=d(x2) arg1=e(y2)
;   MineBlast_New, MineBomb_New  X=x Y=y
;
; Effects are called with their first argument in both A and B (SlowCircle: A=size, B=even).
;
; SetActive. Laser_UpdateAll runs update, laser_hits, draw, then frees the slot if LF_ACTIVE is clear, so a laser hit in
; this pass is gone before its next update: only the draw handler can see it. A laser that ends itself (the C writing
; `active` directly) sets LZ_SELF, so LF_ACTIVE clear without LZ_SELF means "the engine called SetActive(false)".
; - MineBomb explodes, SightChecker records the alien.
; - AreaEffect, Laser5, LaserBeam, MineBlast have empty SetActive: they pierce. lz_pierce turns them back on. They live
;   with LF_HITWALL set so laser_hits goes on through the entity list after a hit, and lz_pierce does the man test
;   that laser_hits skips once LF_ACTIVE is clear.
LZ_SELF     equ $80             ; private L_FLAGS bits; the engine only clears LF_ACTIVE
SIGHT_ALIEN equ $40             ; these two outlive the slot, until Laser_Alloc zeroes it
SIGHT_WALL  equ $20
LZ_LIVE     equ LF_ACTIVE+LF_CANCEL
LZ_PIERCING equ LF_ACTIVE+LF_HITWALL

; A class row, for lz_make: handlers; target, damage, death, sizex, sizey, flags; sprite.
lz_row_alien    fdb alienlaser_vt
                fcb ALLIES,16,LASER_DEATH,4,1,LZ_LIVE
                fdb 38
lz_row_alienv   fdb alienlaserv_vt
                fcb ALLIES,16,LASER_DEATH,4,1,LZ_LIVE
                fdb 218
lz_row_ally     fdb allylaser_vt
                fcb ALIENS,16,LASER_DEATH,4,1,LZ_LIVE
                fdb 36
; An area effect and a mine's blast are not shots: their rows say BOTH so that the load governor (Laser_Alloc) never refuses
; them. A refused one broke a chain of exploding platforms. AreaEffect_New sets the real target, MineBlast_New sets ALLIES.
lz_row_area     fdb areaeffect_vt
                fcb BOTH,64,LASER_DEATH,1,1,LZ_PIERCING+LF_CANCEL
                fdb 36
lz_row_2        fdb laser2_vt
                fcb ALLIES,24,LASER_DEATH,1,1,LZ_LIVE
                fdb 64
lz_row_3        fdb laser3_vt
                fcb ALLIES,48,LASER_DEATH,2,2,LZ_LIVE
                fdb 132
lz_row_4        fdb laser4_vt
                fcb ALLIES,64,LASER_DEATH,4,4,LZ_LIVE
                fdb 134
lz_row_5        fdb laser5_vt
                fcb ALLIES,64,LASER_HEAVY_DEATH,9,9,LZ_PIERCING
                fdb 36
lz_row_beam     fdb laserbeam_vt
                fcb ALLIES,255,LASER_HEAVY_DEATH,1,1,LZ_PIERCING    ; the C's damage is 10000; L_DAMAGE is a byte
                fdb 36
lz_row_blast    fdb mineblast_vt
                fcb BOTH,64,EXPLOSION_ONLY,6,6,LZ_PIERCING
                fdb 36
lz_row_bomb     fdb minebomb_vt
                fcb ALLIES,1,LASER_HEAVY_DEATH,1,1,LZ_LIVE
                fdb 138
lz_row_sight    fdb sightchecker_vt
                fcb ALIENS,0,LASER_DEATH,4,1,LZ_LIVE
                fdb 71
lz_row_smv      fdb smlaserv_vt
                fcb BOTH,16,LASER_DEATH,4,1,LZ_LIVE
                fdb 204

; X=row. The constructor has done pshs d,x,y,u, and gets U=record with that frame still on the stack. If nothing could
; be allocated this returns from the constructor itself, with Z set.
lz_make     pshs x
            lda 2,x
            ldx ,x
            jsr Laser_Alloc
            puls y
            beq .none
            ldd 4,s             ; the frame's X
            std L_X,u
            ldd 6,s             ; the frame's Y
            std L_Y,u
            ldd 3,y
            std L_DAMAGE,u
            ldd 5,y
            std L_SIZEX,u
            lda 7,y
            sta L_FLAGS,u
            ldd 8,y
            std L_SPRITE,u
            rts
.none       leas 2,s
            puls d,x,y,u,pc

; Ends a constructor: X=record, Z clear, everything else as the caller had it.
lz_done     stu 2,s
            andcc #$FB
            puls d,x,y,u,pc

; D = -D.
lz_neg      coma
            comb
            addd #1
            rts

; For a constructor with its frame on the stack: D = D, negated if the frame's A is negative.
lz_signed   tst 2,s
            bmi lz_neg
            rts

; Ends the laser by its own hand. Clears LF_HITWALL, which pierces set while alive.
lz_end      lda L_FLAGS,u
            anda #~(LF_ACTIVE+LF_HITWALL)&$FF
            ora #LZ_SELF
            sta L_FLAGS,u
            rts

; hitWall = true; active = false.
lz_end_wall lda L_FLAGS,u
            anda #~LF_ACTIVE&$FF
            ora #LF_HITWALL+LZ_SELF
            sta L_FLAGS,u
            rts

; Draw handlers of the piercing classes start here: an empty SetActive(false).
lz_pierce   lda L_FLAGS,u
            bita #LF_ACTIVE+LZ_SELF
            bne .out
            ora #LF_ACTIVE
            sta L_FLAGS,u
            lda L_TARGET,u
            cmpa #ALIENS
            beq .out
            lda <man_flags
            bita #MF_ACTIVE
            beq .out
            tst L_DAMAGE,u
            beq .out
            ldd L_X,u
            subd <man_x
            jsr Abs_D
            pshs d
            ldb L_SIZEX,u
            clra
            addd #2
            cmpd ,s++
            ble .out
            ldd L_Y,u
            subd <man_y
            jsr Abs_D
            pshs d
            ldb L_SIZEY,u
            clra
            addd #3
            cmpd ,s++
            ble .out
            lda L_DEATH,u
            jmp Man_Die
.out        rts

; D=sprite id: draws centered on the laser.
lz_draw_d   pshs d
            ldx L_X,u
            leax -6,x
            ldy L_Y,u
            leay -6,y
            puls d
            jmp Draw_Sprite

; X=flash sprite, D=flash ticks: the flash sprite until then, L_SPRITE after.
lz_flash_draw
            pshs d
            ldd <now
            subd L_START,u
            cmpd ,s++
            lbhs Laser_Base_Draw
            tfr x,d
            bra lz_draw_d

; A=color. LaserImpact on the wall face the laser ran into, horizontally.
lz_impact_x pshs a
            ldd L_X,u
            jsr Div12
            jsr Times12
            tst L_VX,u
            bmi .right
            subd #1
            bra .go
.right      addd #12
.go         tfr d,x
            ldy L_Y,u
            puls a
            tfr a,b
            jmp LaserImpact_New

; A=color. The same, vertically.
lz_impact_y pshs a
            ldd L_Y,u
            jsr Div12
            jsr Times12
            tst L_VY,u
            bmi .below
            subd #1
            bra .go
.below      addd #12
.go         tfr d,y
            ldx L_X,u
            puls a
            tfr a,b
            jmp LaserImpact_New

; Effects at the laser's position.
lz_circle4  ldx L_X,u
            ldy L_Y,u
            ldd #4*257
            jmp Circle_New
lz_explosion6
            ldx L_X,u
            ldy L_Y,u
            ldd #6*257
            jmp Explosion_New
lz_sound_if_on
            ldx L_X,u
            ldy L_Y,u
            jsr Main_OnScreen
            bne .out
            lda #SND_QUIET_EXPLOSION
            jmp Sound_Play
.out        rts

; Moves on both axes and counts a frame timer (2 per tick). Returns A=cell here.
LZ_TIMER    equ L_DATA
LZ_TRAILX   equ L_DATA+1        ; Laser3, Laser4: unit vector pointing back along the flight, signed 1.7
LZ_TRAILY   equ L_DATA+2
LZ_SHAPE    equ L_DATA+3        ; 1 + which of trail_shapes its heading gives; 0 for none
lz_move_xy  ldd L_VX,u
            beq .y              ; a row's shots fly along one axis, and adding 0 changes nothing
            jsr laser_move_x
.y          ldd L_VY,u
            beq .t
            jsr Laser_MoveY
.t          lda LZ_TIMER,u
            adda #2
            sta LZ_TIMER,u
            jmp Laser_CellHere

; l->x += trailX; l->y += trailY.
lz_trail_back
            ldb LZ_TRAILX,u
            sex
            aslb
            rola
            jsr laser_move_x
            ldb LZ_TRAILY,u
            sex
            aslb
            rola
            jmp Laser_MoveY

; D=sprite, one of 132 to 134. Three copies, one trail step apart: one image, whose shape lz_aim has found. With no shape, three sprites.
lz_trail_draw
            tst LZ_SHAPE,u
            beq .three
            subb #132
            lda #TRAIL_N
            mul
            addb LZ_SHAPE,u
            adca #0
            addd #TRAIL_COMP-1
            ldx L_X,u
            leax -9,x
            ldy L_Y,u
            leay -9,y
            jmp Draw_Sprite
.three      pshs d
            clra
.loop       pshs a              ; 0,s = copy, 1,s = sprite
            ldb LZ_TRAILY,u
            bsr lz_trail_off
            addd L_Y,u
            subd #6
            tfr d,y
            lda ,s
            ldb LZ_TRAILX,u
            bsr lz_trail_off
            addd L_X,u
            subd #6
            tfr d,x
            ldd 1,s
            jsr Draw_Sprite
            puls a
            inca
            cmpa #3
            blo .loop
            puls d,pc
; A=copy, B=trail (1.7). D=whole pixels, rounded.
lz_trail_off
            pshs b
            tstb
            bpl .pos
            negb
.pos        mul
            addd #64
            aslb
            rola
            tfr a,b
            clra
            tst ,s+
            lbmi lz_neg
            rts

; Aim. D=speed (8.8), arg0, arg1=target; sets L_VX, L_VY and LZ_TRAILX, LZ_TRAILY from the laser's position.
; No division: the deltas are scaled by shifts until the larger is 128-255, the length is approximated as
; max(big, 7/8 big + 1/2 small), and a 56-byte table gives its reciprocal. Over all deltas to 400 px the vector's
; length is 0.969 to 1.033 of true, and its direction is exact but for the rounding of the scaled deltas.
; Target on top of the laser: fires right. (The C's NaN puts the laser at x=0, which ends it.)
lz_aim      std <t4             ; speed
            ldd <arg0
            subd L_X,u
            std <t0             ; dx
            jsr Abs_D
            std <t2
            ldd <arg1
            subd L_Y,u
            std <t1             ; dy
            jsr Abs_D
            std <t3
.down       lda <t2
            ora <t3
            beq .up
            lsr <t2
            ror <t2+1
            lsr <t3
            ror <t3+1
            bra .down
.up         lda <t2+1
            ora <t3+1
            bmi .scaled
            bne .shift
            inc <t2+1
            bra .up
.shift      asl <t2+1
            asl <t3+1
            bra .up
.scaled     lda <t2+1
            ldb <t3+1
            pshs b
            cmpa ,s+
            bhs .ordered
            exg a,b
.ordered    std <t5             ; big, small
            lsrb                ; small / 2
            lsra
            lsra
            lsra                ; big / 8
            pshs a
            lda <t5
            suba ,s+            ; big * 7/8
            pshs a
            clra
            addb ,s+
            adca #0
            bne .length
            cmpb <t5
            bhs .length
            ldb <t5
.length     subd #128
            lsra
            rorb
            lsra
            rorb
            ldx #lz_recip
            ldb b,x
            stb <t5             ; 32768 / length
            lda <t2+1
            ldb <t0
            bsr lz_axis
            std L_VX,u
            ldb <t5+1
            stb LZ_TRAILX,u
            lda <t3+1
            ldb <t1
            bsr lz_axis
            std L_VY,u
            ldb <t5+1
            stb LZ_TRAILY,u
            ; Which shape its trail has.
            lda #2
            ldb LZ_TRAILY,u
            lbsr lz_trail_off
            pshs b
            lda #2
            ldb LZ_TRAILX,u
            lbsr lz_trail_off
            pshs b
            lda #1
            ldb LZ_TRAILY,u
            lbsr lz_trail_off
            pshs b
            lda #1
            ldb LZ_TRAILX,u
            lbsr lz_trail_off
            pshs b              ; 0,s to 3,s are the steps, in the table's order
            ldx #trail_shapes
            lda #1
.shape      ldb ,x
            cmpb ,s
            bne .other
            ldb 1,x
            cmpb 1,s
            bne .other
            ldb 2,x
            cmpb 2,s
            bne .other
            ldb 3,x
            cmpb 3,s
            beq .found
.other      leax 4,x
            inca
            cmpa #TRAIL_N
            bls .shape
            clra
.found      sta LZ_SHAPE,u
            leas 4,s
            rts
; A=scaled delta, B=high byte of the signed delta, t5=reciprocal, t4=speed. D=velocity, t5+1=trail.
lz_axis     pshs b
            ldb <t5
            mul
            aslb
            rola
            bcc .unit
            lda #255            ; 0.996, the most a byte can say
.unit       sta <t5+1           ; 8 bits of fraction
            ldb <t4+1
            mul
            sta <t3             ; the high byte of t3 is free by now
            lda <t5+1
            ldb <t4
            mul
            addb <t3
            adca #0
            lsr <t5+1
            tst ,s+
            lbmi lz_neg         ; flying the negative way: the trail stays positive
            neg <t5+1
            rts
; Generated: round(32768 / (130 + 4 * i)).
lz_recip    fcb 252,245,237,231,224,218,213,207,202,197,193,188,184,180,176,172
            fcb 169,165,162,159,156,153,150,148,145,142,140,138,135,133,131,129
            fcb 127,125,123,121,120,118,116,115,113,111,110,109,107,106,104,103
            fcb 102,101,99,98,97,96,95,94

; ---- AlienLaser.as -------------------------------------------------------------------------------
ALIENLASER_SPEED equ 614        ; 72 px/s
LZ_FLASH_T  equ 4               ; 125 ms

alienlaser_vt fdb AlienLaser_Update,lz_flash37

AlienLaser_New
            pshs d,x,y,u
            ldx #lz_row_alien
            jsr lz_make
            ldd #ALIENLASER_SPEED
            jsr lz_signed
            std L_VX,u
            jmp lz_done

AlienLaser_Update
            ldd L_VX,u
            jsr laser_move_x
            jsr Laser_CellHere
            cmpa #PLATFORM
            bne .out
            jsr lz_end_wall
            lda #COLOR_RED
            jmp lz_impact_x
.out        rts

; AlienLaser and AllyLaser.
lz_flash37  ldx #37
            ldd #LZ_FLASH_T
            jmp lz_flash_draw

; ---- AlienLaserVertical.as -----------------------------------------------------------------------
; A row of bolts: see BoltRow_Update.
alienlaserv_vt fdb BoltRow_Update,0

; For br_walk: a bolt in lava raises a mound or a bubble each tick.
br_h_lava   ldb 2,s
            leax BR_LIST,u
            abx
            tst ,x
            bpl .out
            ldd L_Y,u
            jsr Div12
            jsr Times12
            subd #1
            tfr d,y
            ldx L_X,u
            jsr Random          ; Random < 7/8
            cmpb #224
            bhs .bubble
            ldd #2*257
            jmp LavaMound_New
.bubble     ldd #2*257
            jmp LavaBubble_New
.out        rts

; ---- AllyLaser.as --------------------------------------------------------------------------------
allylaser_vt fdb AllyLaser_Update,lz_flash37

AllyLaser_New
            pshs d,x,y,u
            ldx #lz_row_ally
            jsr lz_make
            ldd #SPACEMANLASER_SPEED    ; also 128 px/s
            jsr lz_signed
            std L_VX,u
            jmp lz_done

AllyLaser_Update
            ldd L_VX,u
            jsr laser_move_x
            jsr Laser_CellHere
            cmpa #PLATFORM
            bne .out
            jsr lz_end_wall
            bra lz_green_miss_x
.out        rts

; AllyLaser and ReboundLaser.
lz_green_miss_x
            lda #SND_MISS
            jsr Sound_Play
            lda #COLOR_GREEN
            jmp lz_impact_x

; ---- AreaEffect.as -------------------------------------------------------------------------------
AREAEFFECT_T equ 2              ; 66 ms

areaeffect_vt fdb AreaEffect_Update,AreaEffect_Draw

AreaEffect_New
            pshs d,x,y,u
            ldx #lz_row_area
            jsr lz_make
            ldd ,s
            sta L_SIZEX,u
            sta L_SIZEY,u
            stb L_TARGET,u
            FAR Area_Blocks     ; bank 11
            jmp lz_done

AreaEffect_Update
            ldd <now
            subd L_START,u
            cmpd #AREAEFFECT_T
            lbhi lz_end
            rts

AreaEffect_Draw
            jsr lz_pierce
            jmp Laser_Base_Draw

; ---- Laser2.as -----------------------------------------------------------------------------------
LASER2_SPEED equ 410            ; 48 px/s

laser2_vt   fdb Laser2_Update,Laser2_Draw

Laser2_New  pshs d,x,y,u
            ldx #lz_row_2
            jsr lz_make
            ldd #LASER2_SPEED
            jsr lz_aim
            jmp lz_done

Laser2_Update
            jsr lz_move_xy
            cmpa #PLATFORM
            bne .out
            jsr lz_end
            lda #SND_MISS
            jsr Sound_Play
            jmp lz_circle4
.out        rts

Laser2_Draw lda LZ_TIMER,u
            anda #2
            lsra
            tfr a,b
            clra
            addd L_SPRITE,u
            jmp lz_draw_d

; ---- Laser3.as -----------------------------------------------------------------------------------
laser3_vt   fdb Laser3_Update,Laser3_Draw

Laser3_New  pshs d,x,y,u
            ldx #lz_row_3
            jsr lz_make
            ldd ,s
            jsr lz_aim
            jmp lz_done

Laser3_Update
            jsr lz_move_xy
            cmpa #PLATFORM
            bne lz_rts
            jsr lz_trail_back
            jsr lz_end
            jsr lz_sound_if_on
            jsr lz_explosion6
            jmp lz_circle4
lz_rts      rts

; A shot's trail (Laser3, Laser4) wholly outside the view: Draw_Sprite would show none of it, so its drawing is skipped.
; U=laser. Returns HI when it is off, with a 32-pixel margin past anything Draw_Sprite could still show.
lz_offview  ldd L_X,u
            subd <cam_x
            addd #VIEW_HALF_W+32
            cmpd #(VIEW_HALF_W+32)*2
            bhi .out
            ldd L_Y,u
            subd <spr_oy
            subd #12+VIEW_ROW0-32
            cmpd #VIEW_H+64
.out        rts

Laser3_Draw bsr lz_offview
            bhi lz_rts
            ldd L_SPRITE,u
            jmp lz_trail_draw

; ---- Laser4.as -----------------------------------------------------------------------------------
laser4_vt   fdb Laser4_Update,Laser4_Draw

Laser4_New  pshs d,x,y,u
            ldx #lz_row_4
            jsr lz_make
            ldd ,s
            jsr lz_aim
            jmp lz_done

Laser4_Update
            jsr lz_move_xy
            cmpa #PLATFORM
            beq .wall
            cmpa #PLATFORM_DESTRUCTIBLE
            bne .out
.wall       jsr lz_trail_back
            jsr lz_end
            jsr lz_sound_if_on
            jmp lz_circle4
.out        rts

Laser4_Draw bsr lz_offview
            bhi lz_rts
            lda LZ_TIMER,u      ; bit 1 of the timer is the frame
            anda #2
            bne .second
            ldd #134
            jmp lz_trail_draw
.second     ldd #133
            jmp lz_trail_draw

; ---- Laser5.as -----------------------------------------------------------------------------------
LASER5_SPEED equ 717            ; 84 px/s

laser5_vt   fdb Laser5_Update,Laser5_Draw

Laser5_New  pshs d,x,y,u
            ldx #lz_row_5
            jsr lz_make
            ldd #LASER5_SPEED
            jsr lz_aim
            jmp lz_done

Laser5_Update
            jsr lz_move_xy
            cmpa #PLATFORM
            beq .wall
            cmpa #PLATFORM_DESTRUCTIBLE
            bne .out
.wall       jsr lz_end
            jsr lz_sound_if_on
            ldd L_X,u           ; to the nearest cell edge
            addd #6
            jsr Div12
            jsr Times12
            pshs d
            ; A third of a cell back along the flight. The C's NaN for speedX 0 is not kept: no offset.
            ldx L_VX,u
            beq .noback
            tst L_VX,u
            bmi .left
            subd #4
            bra .noback
.left       addd #4
.noback     tfr d,x
            ldy L_Y,u
            ldd #16*257
            jsr Explosion_New
            puls x
            ldy L_Y,u
            ldd #12*257
            jmp CircleLarge_New
.out        rts

; Four corner sprites from 312 + 4 * (12 - size); size is 8 in frame 0, 9 in frame 1.
Laser5_Draw jsr lz_pierce
            lda LZ_TIMER,u
            anda #2
            bne .big
            ldd #328
            bra .go
.big        ldd #324
.go         pshs d
            ldx #lz_laser5_corners
.loop       pshs x              ; 0,s = table, 2,s = sprite
            ldb 1,x
            sex
            addd L_Y,u
            tfr d,y
            ldb ,x
            sex
            addd L_X,u
            tfr d,x
            ldd 2,s
            jsr Draw_Sprite
            ldd 2,s
            addd #1
            std 2,s
            puls x
            leax 2,x
            cmpx #lz_laser5_corners+8
            blo .loop
            puls d,pc
lz_laser5_corners
            fcb 0,-12,-12,-12,-12,0,0,0

; ---- LaserBeam.as --------------------------------------------------------------------------------
LASERBEAM_T equ 29              ; 31/32 s
LASERBEAM_FADEOUT_AT equ 19     ; less 1/3 s
LASERBEAM_FADEIN_T equ 8        ; 1/4 s
LASERBEAM_ORIENT equ L_DATA
LASERBEAM_RECT_MAX equ 240      ; Draw_RectWorld takes a byte of size

laserbeam_vt fdb LaserBeam_Update,LaserBeam_Draw

LaserBeam_New
            pshs d,x,y,u
            ldx #lz_row_beam
            jsr lz_make
            lda ,s
            sta LASERBEAM_ORIENT,u
            ldd <arg0
            addd 2,s
            lsra
            rorb
            std L_X,u
            ldd <arg0
            subd 2,s
            bsr lz_half
            stb L_SIZEX,u
            ldd <arg1
            addd 4,s
            lsra
            rorb
            std L_Y,u
            ldd <arg1
            subd 4,s
            bsr lz_half
            stb L_SIZEY,u
            jmp lz_done
; D=signed length. B=half of it, at most 255 (a beam over 510 pixels hits only its middle 510).
lz_half     jsr Abs_D
            lsra
            rorb
            tsta
            beq .out
            ldb #255
.out        rts

LaserBeam_Update
            ldd <now
            subd L_START,u
            cmpd #LASERBEAM_T
            blo .alive
            clra
            bsr lz_beam_size
            jmp lz_end
.alive      cmpb #LASERBEAM_FADEOUT_AT
            blo .notfading
            lda #LASERBEAM_T
            pshs b
            suba ,s+
            lsra                ; (1 - (t - 19) / 10) * 5
            bra lz_beam_size
.notfading  cmpb #LASERBEAM_FADEIN_T
            blo .fadein
            lda #5
            bra lz_beam_size
.fadein     lda #5              ; t / 8 * 5
            mul
            lsrb
            lsrb
            lsrb
            tfr b,a
; A=thickness.
lz_beam_size
            ldb LASERBEAM_ORIENT,u
            beq .horizontal
            sta L_SIZEX,u
            rts
.horizontal sta L_SIZEY,u
            rts

; Long beams take more than one rectangle. X, Y = the rectangle's corner, t3, t4 = the width and height still to draw.
; Draw_RectWorld keeps Y and t3-t5. Most beams are one rectangle: the loop runs once.
LaserBeam_Draw
            jsr lz_pierce
            ldb L_SIZEX,u
            beq .out            ; the C's rectangle is empty
            clra
            std <t3
            ldd L_X,u
            subd <t3
            tfr d,x
            ldb L_SIZEY,u
            beq .out
            clra
            std <t4
            ldd L_Y,u
            subd <t4
            tfr d,y
            ldd <t3
            aslb
            rola
            std <t3
            ldd <t4
            aslb
            rola
            std <t4
            lda #COLOR_WHITE
            sta <draw_color
.seg        ldd <t3
            cmpd #LASERBEAM_RECT_MAX
            bls .wok
            ldd #LASERBEAM_RECT_MAX
.wok        stb <t5
            ldd <t4
            cmpd #LASERBEAM_RECT_MAX
            bls .hok
            ldd #LASERBEAM_RECT_MAX
.hok        stb <t5+1
            pshs x
            ldd <t5
            jsr Draw_RectWorld
            puls x
            ldd <t3
            subd #LASERBEAM_RECT_MAX
            bls .wdone
            std <t3
            leax LASERBEAM_RECT_MAX,x
            bra .seg
.wdone      ldd <t4
            subd #LASERBEAM_RECT_MAX
            bls .out
            std <t4
            leay LASERBEAM_RECT_MAX,y
            bra .seg
.out        rts

; ---- MineBlast.as --------------------------------------------------------------------------------
MINEBLAST_UPDATED equ L_DATA

mineblast_vt fdb MineBlast_Update,lz_pierce

MineBlast_New
            pshs d,x,y,u
            ldx #lz_row_blast
            jsr lz_make
            lda #ALLIES
            sta L_TARGET,u
            ldx 2,s
            ldy 4,s
            leay -5,y
            ldd #4*257
            jsr HalfCircle_New
            jmp lz_done

MineBlast_Update
            tst MINEBLAST_UPDATED,u
            lbne lz_end
            inc MINEBLAST_UPDATED,u
            rts

; ---- MineBomb.as ---------------------------------------------------------------------------------
MINEBOMB_SPEED equ 307          ; 3 cells per second
MINEBOMB_FLASH_T equ 5          ; 166 ms

minebomb_vt fdb MineBomb_Update,MineBomb_Draw

MineBomb_New
            pshs d,x,y,u
            ldx #lz_row_bomb
            jsr lz_make
            ldd #MINEBOMB_SPEED
            std L_VY,u
            jmp lz_done

MineBomb_Update
            lda L_FLAGS,u
            bita #LF_ACTIVE     ; deactivated from outside: MineBomb_Draw will explode it
            beq .out
            ldd L_VY,u
            jsr Laser_MoveY
            jsr Laser_CellHere
            cmpa #PLATFORM
            beq .ground
            cmpa #FLOATY_PLATFORM
            beq .ground
            cmpa #LAVA
            beq .ground
            cmpa #LAVA2
            bne .out
            ; ExplodeHalfCircle. Its deathType write is dropped: the bomb can hit nothing more.
.ground     jsr lz_end
            lda #SND_QUIET_EXPLOSION
            jsr Sound_Play
            jsr lz_explosion6
            ldd L_Y,u
            jsr Div12
            jsr Times12
            subd #1
            tfr d,y
            ldx L_X,u
            jmp MineBlast_New
.out        rts

; Runs after laser_hits, so this is where SetActive(false) shows up: Explode.
MineBomb_Draw
            lda L_FLAGS,u
            bita #LF_ACTIVE+LZ_SELF
            bne .draw
            ora #LZ_SELF
            sta L_FLAGS,u
            lda #SND_QUIET_EXPLOSION
            jsr Sound_Play
            jsr lz_explosion6
            ldx L_X,u
            ldy L_Y,u
            ldd #4*256+1
            jsr SlowCircle_New
.draw       ldd <now
            subd L_START,u
            cmpd #MINEBOMB_FLASH_T
            lbhs Laser_Base_Draw
            lda #COLOR_WHITE
            sta <draw_color
            ldx L_X,u
            leax -6,x
            ldy L_Y,u
            leay -6,y
            ldd L_SPRITE,u
            jmp Draw_ColoredSprite

; ---- SightChecker.as -----------------------------------------------------------------------------
; Hidden, and freed in the very tick it finds something, or after 2/3 s. The results are read from the freed record,
; so they stay valid until something else allocates that slot, which can happen in the same tick: the entity pass runs
; right after the laser pass. So the record names its owner, the U of whoever made it, and the queries answer only
; that owner, called with its own U. On a reused slot they say false, and the caller's own look timer takes over.
; Reading LF_ACTIVE in `L_FLAGS,x` as the C does works, but a reused slot can read active until its new laser ends.
SIGHT_OWNER equ L_DATA
SIGHT_T     equ 20              ; 666 ms

sightchecker_vt fdb SightChecker_Update,SightChecker_Draw

SightChecker_New
            pshs d,x,y,u
            ldx #lz_row_sight
            jsr lz_make
            ldd 6,s
            std SIGHT_OWNER,u
            ldd <arg0
            std L_VX,u
            jmp lz_done

; X=laser, U=the entity that made it. Z clear when true. Preserves X, Y, U, B.
SightChecker_IsAlienFound
            lda #SIGHT_ALIEN
            bra lz_sight_query
SightChecker_IsWallFound
            lda #SIGHT_WALL
lz_sight_query
            anda L_FLAGS,x
            beq .out
            cmpu SIGHT_OWNER,x
            beq .mine
            orcc #$04
            rts
.mine       andcc #$FB
.out        rts

SightChecker_Update
            ldd L_VX,u
            jsr laser_move_x
            jsr Laser_CellHere
            cmpa #PLATFORM
            bne .notwall
            jsr lz_end
            ora #SIGHT_WALL
            sta L_FLAGS,u
.notwall    ldd <now
            subd L_START,u
            cmpd #SIGHT_T
            lbhi lz_end
            rts

; Draws nothing. SetActive records the alien.
SightChecker_Draw
            lda L_FLAGS,u
            bita #LF_ACTIVE+LZ_SELF
            bne .out
            ora #SIGHT_ALIEN
            sta L_FLAGS,u
.out        rts

; ---- SpacemanLaserVertical.as --------------------------------------------------------------------
smlaserv_vt fdb SpacemanLaserVertical_Update,0

SpacemanLaserVertical_New
            pshs d,x,y,u
            ldx #lz_row_smv
            jsr lz_make
            ldd <arg0
            std L_VY,u
            jmp lz_done

SpacemanLaserVertical_Update
            ldd L_VY,u
            jsr Laser_MoveY
            jsr Laser_CellHere
            cmpa #PLATFORM
            bne .air
            jsr lz_end
            lda #SND_MISS
            jsr Sound_Play
            lda #COLOR_GREEN
            jmp lz_impact_y
.air        ldx L_X,u
            ldy L_Y,u
            jsr Main_OnScreen
            lbne lz_end
            rts
