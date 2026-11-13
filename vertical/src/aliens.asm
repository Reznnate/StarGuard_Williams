; aliens/*.as, first part: ExplodingHopper, Flyer, Hopper, Piglet, Popper, Seeker, Trooper. Ported from ../port/src/aliens.c.
; Bank 12. The macros below are also used by aliens2.asm, which is assembled after this file.
;
; Cell lookups are the hot path here, so nothing per-tick uses Div12 (about 420 cycles) or Cell_At. AL_PosCells divides
; each axis once through a table (about 75 cycles an axis) and keeps the remainder, then AL_Near finds a neighbouring
; cell by adding the pixel offset to the remainder. The cell under the entity is looked up at most once per PosCells.

; Scratch of the cell helpers. Main_GetCell only uses t0-t2. Times12, Div12, Draw_* and effects clobber these, so
; call PosCells again after any of those if you still need Near.
PC_COL      equ t3              ; cell x of E_X, word
PC_REMX     equ t4              ; E_X mod 12
PC_ROW      equ t4+1            ; cell y of E_Y
PC_REMY     equ t5              ; E_Y mod 12
PC_HERE     equ t5+1            ; type of (PC_COL, PC_ROW), $FF = not read yet

; Trooper and TrooperHeavy keep their ground cell here: they test it every tick and rarely move.
GC_X        equ E_DATA+0
GC_Y        equ E_DATA+2
GC_COL      equ E_DATA+4
GC_ROW      equ E_DATA+6
GC_END      equ E_DATA+7
GC_TYPE     equ 44              ; the ground's type, as of cell_gen in GC_GEN. Both classes leave these free
GC_GEN      equ 45

; A one-byte count constructor (Explosion_New etc): pools.asm passes the count in B, PORTING.md says A. Sets both.
FX_COUNT    macro target,n
            ldd #(\n)*257
            ldx E_X,u
            ldy E_Y,u
            jsr \target
            endm
; Number position kept as integer word plus separate fraction byte: pos += spd (signed 8.8). 38 cycles.
ADDPOS      macro spd,frac,pos
            ldb \spd+1,u
            addb \frac,u
            stb \frac,u
            ldb \spd,u
            sex
            adcb \pos+1,u
            adca \pos,u
            std \pos,u
            endm
; Skips to label unless |man_x - E_X| < k, with k at least sizeX + 2: 24 cycles, against 69 for Ent_TouchesMan's miss.
TOUCH_X     macro k,label
            ldd <man_x
            subd E_X,u
            addd #(\k)-1
            cmpd #2*(\k)-1
            bhs \label
            endm
; Allocates an alien. U=record, Z set if the pool is full. The caller has saved the X and B arguments.
ALIEN_ALLOC macro vt
            ldx #\vt
            lda #bank(\vt)
            ldb #KIND_ALIEN
            jsr Ent_Alloc
            endm
; 48 bytes of D/12 quotients: value>>2 is the index, each row covers 16 cells.
D3ROW       macro n
            fcb \n,\n,\n,\n+1,\n+1,\n+1,\n+2,\n+2,\n+2,\n+3,\n+3,\n+3,\n+4,\n+4,\n+4,\n+5,\n+5,\n+5,\n+6,\n+6,\n+6,\n+7,\n+7,\n+7
            fcb \n+8,\n+8,\n+8,\n+9,\n+9,\n+9,\n+10,\n+10,\n+10,\n+11,\n+11,\n+11,\n+12,\n+12,\n+12,\n+13,\n+13,\n+13,\n+14,\n+14,\n+14,\n+15,\n+15,\n+15
            endm

; The helpers shared by both banks. All symbols are global, so each bank gets its own prefix.
AL_HELPERS  macro p
\p_D3tab    D3ROW 0
            D3ROW 16
            D3ROW 32
            D3ROW 48
            D3ROW 64
            D3ROW 80
            D3ROW 96
            D3ROW 112
            D3ROW 128
            D3ROW 144
            D3ROW 160
            D3ROW 176
            D3ROW 192
            D3ROW 208
            D3ROW 224
            D3ROW 240

; D=pixel coordinate. Returns D=cell, truncating toward 0 as the C does, or -1 when more than one cell negative.
; Works past cell 255 (level 9 is 272 wide). Clobbers X.
\p_CellOf   tsta
            bmi .neg
            lsra
            rorb
            lsra
            rorb
            cmpa #3
            bhs .big
            addd #\p_D3tab
            tfr d,x
            ldb ,x
            clra
            rts
.big        cmpa #6
            bhs .huge
            suba #3
            addd #\p_D3tab
            tfr d,x
            ldb ,x
            lda #1
            rts
.huge       ldd #$7FFF
            rts
.neg        cmpd #-11
            blt .m1
            ldd #0
            rts
.m1         ldd #-1
            rts

; Loads PC_* for the entity at U. Clobbers D, X. A negative coordinate reads as the out-of-bounds cell -1.
\p_PosCells ldd E_X,u
            bmi .negx
            lsra
            rorb
            lsra
            rorb
            cmpa #3
            bhs .bigx
            addd #\p_D3tab
            tfr d,x
            ldb ,x
            clra
.havex      std <PC_COL
            lda #12
            mul
            negb
            addb E_X+1,u
            stb <PC_REMX
.doy        ldd E_Y,u
            bmi .negy
            lsra
            rorb
            lsra
            rorb
            addd #\p_D3tab
            tfr d,x
            ldb ,x
            stb <PC_ROW
            lda #12
            mul
            negb
            addb E_Y+1,u
            stb <PC_REMY
.out        lda #$FF
            sta <PC_HERE
            rts
.bigx       suba #3
            addd #\p_D3tab
            tfr d,x
            ldb ,x
            lda #1
            bra .havex
.negx       ldd #-1
            std <PC_COL
            clr <PC_REMX
            bra .doy
.negy       ldb #$FF
            stb <PC_ROW
            clr <PC_REMY
            bra .out

; A=dx, B=dy, signed pixels in -12..12 from the position given to PosCells. Returns A=cell type, flags from nothing:
; test with tsta. Clobbers B, X. Preserves Y, U and the PC_* values.
\p_NearY    addb <PC_REMY       ; dx = 0, the common case. B=dy.
            bmi .up
            cmpb #12
            bhs .down
            lda <PC_HERE
            cmpa #$FF
            bne .have
            ldb <PC_ROW
            ldx <PC_COL
            jsr Main_GetCell
            sta <PC_HERE
.have       rts
.up         ldb <PC_ROW
            decb
            ldx <PC_COL
            jmp Main_GetCell
.down       ldb <PC_ROW
            incb
            ldx <PC_COL
            jmp Main_GetCell

\p_Near     addb <PC_REMY
            bmi .up
            cmpb #12
            bhs .down
            ldb <PC_ROW
            adda <PC_REMX
            bmi .left
            cmpa #12
            bhs .right
            lda <PC_HERE
            cmpa #$FF
            bne .have
            ldx <PC_COL
            jsr Main_GetCell
            sta <PC_HERE
.have       rts
.up         ldb <PC_ROW
            decb
            bra .col
.down       ldb <PC_ROW
            incb
.col        adda <PC_REMX
            bmi .left
            cmpa #12
            bhs .right
            ldx <PC_COL
            jmp Main_GetCell
.left       ldx <PC_COL
            leax -1,x
            jmp Main_GetCell
.right      ldx <PC_COL
            leax 1,x
            jmp Main_GetCell

; Main.RectangleOnScreen(x, y, sizeX, sizeY) for the entity at U, against the gameplay box (Main_OnScreen's).
; Z set when on screen. The C tests y + w, not y + h, and so does this. Clobbers D.
\p_RectOn   ldd E_X,u
            subd <cam_x
            bpl .xp
            coma
            comb
            addd #1
.xp         subd #LOGIC_HALF_W  ; |dx| - halfw <= w
            bmi .x_ok
            bne .x_big
            bra .x_ok
.x_big      tsta
            bne .off
            cmpb E_SIZEX,u
            bhi .off
.x_ok       ldd E_Y,u
            subd <cam_y
            bpl .below
            ; above the center: y + w < top
            addd #LOGIC_HALF_H
            bpl .on
            coma
            comb
            addd #1
            tsta
            bne .off
            cmpb E_SIZEX,u
            bhi .off
.on         orcc #$04
            rts
.below      subd #LOGIC_HALF_H  ; y - h > bottom
            ble .on
            tsta
            bne .off
            cmpb E_SIZEY,u
            bls .on
.off        andcc #$FB
            rts

; The cell at (E_X, E_Y + 6), through the GC_* cache in the record. Returns A=type.
\p_Ground   ldd E_X,u
            cmpd GC_X,u
            bne .miss
            ldd E_Y,u
            cmpd GC_Y,u
            bne .miss
            lda cell_gen
            cmpa GC_GEN,u
            bne .hit
            lda GC_TYPE,u
            rts
.hit        ldx GC_COL,u
            ldb GC_ROW,u
            jsr Main_GetCell
            sta GC_TYPE,u
            ldb cell_gen
            stb GC_GEN,u
            rts
.miss       ldd E_X,u
            std GC_X,u
            jsr \p_CellOf
            std GC_COL,u
            ldd E_Y,u
            std GC_Y,u
            addd #6
            jsr \p_CellOf
            stb GC_ROW,u
            bra .hit

; Alien_Init, then centered in the cell with the start time set: X=cell x, B=cell y. Everything was spawned at level
; start in the C, and the spawner now does it late, so "time since start" must count from here.
\p_InitCentered
            jsr Alien_Init
            ldd E_X,u
            addd #6
            std E_X,u
            ldd E_Y,u
            addd #6
            std E_Y,u
            ldd <now
            std E_START,u
            rts

; Heading toward the man's x: returns A=1 or -1. Sets flags for A.
\p_AimX     ldd <man_x
            cmpd E_X,u
            blt .left
            lda #1
            rts
.left       lda #-1
            rts

; e->active = false, and the spawner must not bring it back.
\p_Kill     lda E_FLAGS,u
            anda #~EF_ACTIVE&$FF
            sta E_FLAGS,u
            jmp Ent_MarkDead

; D = D * 12 + 6, from the C's cellX * TILE_SIZE + TILE_SIZE / 2.
\p_CellMid  jsr Times12
            addd #6
            rts

; Sinks the entity: arg0/arg1 = the two sprites, A=area byte, X, Y=position. Ends it.
\p_Sink     pshs a,x,y
            bsr \p_Kill
            puls a,x,y
            tfr a,b
            jsr SinkingEntity_New
            rts
            endm

; ---------------------------------------------------------------------------------------------
            bank 10
            org messages_end
            AL_HELPERS AL

; ---- Hopper.as and ExplodingHopper.as: the same record ----------------------------------------
HOP_XF      equ E_DATA+0        ; x2 = E_X + this / 256
HOP_YF      equ E_DATA+1
HOP_SX      equ E_DATA+2
HOP_SY      equ E_DATA+4
HOP_NEXT    equ E_DATA+6        ; ticks
HOP_STATE   equ E_DATA+7
HOP_HEAD    equ E_DATA+8
            assert E_DATA+9<=ENT_SIZE,"hopper record"
HOPS_IDLE   equ 0
HOPS_HOP    equ 1
HOPS_SUSP   equ 2

HOP_X_SPEED equ 307             ; 36 px/s, both classes
HOP_SUSPEND_T equ 4             ; 125 ms
HOP_ARM_NEAR equ 6              ; 3/16 s before the hop
HOP_ARM_FAR equ 11              ; 3/8 s before the hop

HOPPER_BASE equ 96
HOPPER_GRAV equ 17              ; 60 px/s^2
HOPPER_RANGE equ 171            ; hop y speed: -(r * 20 + 40) px/s
HOPPER_FLOOR equ 341
HOPPER_HOP_T equ 9              ; 312 ms
EHOPPER_BASE equ 192
EHOPPER_GRAV equ 27             ; 96 px/s^2
EHOPPER_RANGE equ 205           ; -(r * 24 + 48) px/s
EHOPPER_FLOOR equ 410
EHOPPER_HOP_T equ 8             ; 250 ms

; A=range, X=floor: speedY = -(Random * range / 256 + floor).
Hop_RandomSY
            jsr Random
            mul
            tfr a,b
            clra
            leax d,x
            tfr x,d
            coma
            comb
            addd #1
            std HOP_SY,u
            rts

; State, start time, heading and speedX of Hop(). Call after Hop_RandomSY, as the C draws in that order.
Hop_Launch  lda #HOPS_HOP
            sta HOP_STATE,u
            ldd <now
            std E_START,u
            ldd <man_x
            cmpd E_X,u
            blt .neg
            bgt .pos
            tst HOP_XF,u        ; the man's int against the Number x2
            bne .neg
.pos        lda #1
            bra .h
.neg        lda #-1
.h          sta HOP_HEAD,u
            jsr Random
            cmpb #51            ; JUMP_AWAY, 1/5
            bhs .noflip
            neg HOP_HEAD,u
.noflip     ldd #HOP_X_SPEED
            tst HOP_HEAD,u
            bpl .sx
            ldd #-HOP_X_SPEED
.sx         std HOP_SX,u
            rts

; Bounce off a wall. A=range, X=floor for the wall jump, Y=base sprite. Size is 3 in both classes.
Hop_Wall    pshs a,x,y
            ldb #3
            tst HOP_HEAD,u
            bpl .e
            ldb #-3
.e          sex
            addd E_X,u
            jsr AL_CellOf
            jsr AL_CellMid
            pshs d
            tst HOP_HEAD,u
            bpl .right
            addd #9
            bra .setx
.right      subd #9
.setx       std E_X,u
            clr HOP_XF,u
            ldd #0
            subd HOP_SX,u
            std HOP_SX,u
            neg HOP_HEAD,u
            ldd 5,s
            addd #4
            std E_SPRITE,u
            ldd <man_y
            cmpd E_Y,u
            blt .jump
            bgt .plain
            tst HOP_YF,u
            beq .plain
.jump       lda 2,s
            ldx 3,s
            jsr Hop_RandomSY
            ldd ,s
            tst HOP_HEAD,u
            bpl .ir
            subd #6
            bra .imp
.ir         addd #6
.imp        tfr d,x
            ldy E_Y,u
            lda #COLOR_RED
            jsr LaserImpact_New
            ldb #2
            tst HOP_HEAD,u
            bpl .sp
            ldb #3
.sp         clra
            addd 5,s
            std E_SPRITE,u
.plain      leas 7,s
            jmp AL_PosCells

; ---- ExplodingHopper ----
ExplodingHopper_vt
            fdb ExplodingHopper_Update,0,ExplodingHopper_Die,ExplodingHopper_DeathEffect,0

ExplodingHopper_New
            pshs b,x
            ALIEN_ALLOC ExplodingHopper_vt
            beq .full
            puls b,x
            jsr AL_InitCentered
            lda #HOPS_SUSP
            sta HOP_STATE,u
            ldd #EHOPPER_BASE
            std E_SPRITE,u
            ldd #3*256+3
            std E_SIZEX,u
            lda #6
            sta E_SCORE,u
            jmp Main_AddToKillCount
.full       puls b,x,pc

ExplodingHopper_DeathEffect
            lda #SND_EXPLOSION
            jsr Sound_Play
            ldd E_SPRITE,u
            std <arg0
            ldx E_X,u
            ldy E_Y,u
            jsr DeathFlash_New
            rts

; Laser2 outward: D=target dx*256+dy (signed bytes).
ehop_shot   pshs d
            tfr a,b
            sex
            addd E_X,u
            std <arg0
            ldb 1,s
            sex
            addd E_Y,u
            std <arg1
            leas 2,s
            ldx E_X,u
            ldy E_Y,u
            jsr Laser2_New
            rts

; The C runs the death effect twice: once here, once where Alien.Die would.
ExplodingHopper_Die
            jsr Entity_DeathEffect
            jsr Main_RecordKill
            ldb E_SCORE,u
            ldx E_X,u
            ldy E_Y,u
            jsr Main_RecordScore
            jsr Entity_DeathEffect
            jsr AL_Kill
            ldd #1*256+0
            bsr ehop_shot
            ldd #1*256+255
            bsr ehop_shot
            ldd #0*256+255
            bsr ehop_shot
            ldd #255*256+255
            bsr ehop_shot
            ldd #255*256+0
            bsr ehop_shot
            ldd #255*256+1
            bsr ehop_shot
            ldd #0*256+1
            bsr ehop_shot
            ldd #1*256+1
            bra ehop_shot

ExplodingHopper_SwitchState
            sta HOP_STATE,u
            beq .idle
            cmpa #HOPS_HOP
            beq .hop
            rts
.idle       ldd <now
            std E_START,u
            ldd #EHOPPER_BASE+1
            std E_SPRITE,u
            rts
.hop        lda #EHOPPER_RANGE
            ldx #EHOPPER_FLOOR
            jsr Hop_RandomSY
            jsr Hop_Launch
            lda #EHOPPER_HOP_T
            sta HOP_NEXT,u
            ldd #EHOPPER_BASE+4
            std E_SPRITE,u
            rts

ExplodingHopper_Update
            lda HOP_STATE,u
            beq .idle
            cmpa #HOPS_HOP
            beq .hop
            ldd <now
            subd E_START,u
            cmpd #HOP_SUSPEND_T
            bls .done
            ldx E_X,u
            ldy E_Y,u
            jsr Main_OnScreen
            bne .done
            clra
            jsr ExplodingHopper_SwitchState
            bra .done
.idle       ldd <now
            subd E_START,u
            tsta
            bne .tohop
            cmpb HOP_NEXT,u
            bhs .tohop
            addb #HOP_ARM_NEAR
            cmpb HOP_NEXT,u
            bhi .s0
            addb #HOP_ARM_FAR-HOP_ARM_NEAR
            cmpb HOP_NEXT,u
            bls .done
            ldd #EHOPPER_BASE+1
            bra .setsp
.s0         ldd #EHOPPER_BASE
.setsp      std E_SPRITE,u
            bra .done
.tohop      lda #HOPS_HOP
            jsr ExplodingHopper_SwitchState
.done       TOUCH_X 5,.draw
            jsr Alien_ContactKillCheck
.draw       ldd E_SPRITE,u
            jmp Alien_DrawSelf

.hop        ADDPOS HOP_SX,HOP_XF,E_X
            ADDPOS HOP_SY,HOP_YF,E_Y
            ldd HOP_SY,u
            addd #EHOPPER_GRAV
            std HOP_SY,u
            jsr AL_PosCells
            lda #3
            tst HOP_HEAD,u
            bpl .wa
            lda #-3
.wa         clrb
            jsr AL_Near
            cmpa #PLATFORM
            beq .wall
            cmpa #PLATFORM_DESTRUCTIBLE
            beq .wall
            cmpa #EXPLODING_PLATFORM
            bne .nowall
.wall       lda #EHOPPER_RANGE
            ldx #EHOPPER_FLOOR
            ldy #EHOPPER_BASE
            jsr Hop_Wall
.nowall     ldb #2              ; sizeY - 1
            jsr AL_NearY
            tsta
            beq .nofloor
            cmpa #LAVA
            blo .floor
            cmpa #EXPLODING_PLATFORM
            bne .nofloor
.floor      ldd HOP_SY,u
            ble .nofloor
            ldd E_Y,u
            addd #2
            jsr AL_CellOf
            jsr Times12
            subd #3
            std E_Y,u
            clr HOP_YF,u
            clra
            jsr ExplodingHopper_SwitchState
            jsr AL_PosCells
.nofloor    ldb #-4
            jsr AL_NearY
            tsta
            beq .done2
            cmpa #LAVA
            beq .done2
            cmpa #FLOATY_PLATFORM
            beq .done2
            ldd E_Y,u
            subd #4
            jsr AL_CellOf
            jsr Times12
            addd #16
            std E_Y,u
            clr HOP_YF,u
            ldd #0
            subd HOP_SY,u
            std HOP_SY,u
.done2      lbra .done

; ---- Flyer.as ---------------------------------------------------------------------------------
FLY_TIMER   equ E_DATA+0        ; 0-9: animation position, ticks
FLY_RADIUS  equ E_DATA+1        ; signed; a narrow gap gives a negative radius, as in the C
FLY_YF      equ E_DATA+2
FLY_FIRET   equ E_DATA+3
FLY_SPEEDY  equ E_DATA+5
FLY_CENTER  equ E_DATA+7
FLY_CHARGED equ E_DATA+9
            assert E_DATA+10<=ENT_SIZE,"flyer record"
FLY_SPEED   equ 307             ; 36 px/s
FLY_ACCEL   equ 14              ; 48 px/s^2
FLY_FIRE_T  equ 60              ; 2000 ms
FLY_CHARGE_SPRITE equ 70
FLY_START_FRAME equ 60

Flyer_vt    fdb Flyer_Update,0,0,Flyer_DeathEffect,Flyer_HitEffect
fly_frames  fcb 0,0,0,1,1,2,2,2,3,3     ; timer / 5 % 4, in steps of two 60 Hz frames

Flyer_New   pshs b,x
            ALIEN_ALLOC Flyer_vt
            lbeq .full
            ldx 1,s
            ldb ,s
            jsr Alien_Init
            ; Flyer_PlaceCenter: scan up and down for what bounds the column.
            clr ,-s             ; offset
.up         ldx 2,s
            ldb 1,s
            subb ,s
            jsr Main_GetCell
            tsta
            bne .ceil
            inc ,s
            bra .up
.ceil       ldb 1,s
            subb ,s
            incb
            stb ,s              ; ceiling row
            clr ,-s             ; offset
.down       ldx 3,s
            ldb 2,s
            addb ,s
            jsr Main_GetCell
            tsta
            bne .floor
            inc ,s
            bra .down
.floor      ldb 2,s
            addb ,s
            decb                ; floor row
            stb ,s
            ; center = (floor + ceiling) * 6 + 6, radius = (floor - ceiling) * 6 - 12, at most 36
            clra
            addb 1,s
            adca #0
            aslb
            rola
            std <t0
            aslb
            rola
            addd <t0
            addd #6
            std FLY_CENTER,u
            std E_Y,u
            ldb ,s
            subb 1,s            ; signed result
            bmi .negr
            lda #6
            mul
            subd #12
            cmpd #36
            ble .rok
            ldb #36
            bra .rok
.negr       negb
            lda #6
            mul
            coma
            comb
            addd #1
            subd #12
.rok        stb FLY_RADIUS,u
            leas 2,s
            puls b,x
            ; x
            tfr x,d
            jsr AL_CellMid
            std E_X,u
            ldd #FLY_SPEED
            std FLY_SPEEDY,u
            ldd <now
            std FLY_FIRET,u
            std E_START,u
            ldd #2*256+2
            std E_SIZEX,u
            lda #6
            sta E_SCORE,u
            ldd #FLY_START_FRAME
            std E_SPRITE,u
            jmp Main_AddToKillCount
.full       puls b,x,pc

; y2 = center + radius + 18, speedY = -18 px/s. U=entity. Far-callable.
Flyer_StartBeneathLava
            ldb FLY_RADIUS,u
            sex
            addd FLY_CENTER,u
            addd #18
            std E_Y,u
            clr FLY_YF,u
            ldd #-154
            std FLY_SPEEDY,u
            rts

Flyer_DeathEffect
            lda #SND_MACHINE_EXPLOSION
            jsr Sound_Play
            FX_COUNT CircleLarge_New,7
            FX_COUNT Explosion_New,16
            rts

Flyer_HitEffect
            lda #SND_MACHINE_HIT
            jsr Sound_Play
            ldd #8*257
            ldx <hit_x
            ldy <hit_y
            jsr Explosion_New
            lda E_FLAGS,u
            ora #EF_FLASHING
            sta E_FLAGS,u
            ldb <now+1
            stb E_FLASHT,u
            rts

Flyer_Update
            ; y2 against the two turn points: decelerate within 12 pixels of either end of the orbit.
            ldd E_Y,u
            cmpd FLY_CENTER,u
            bge .lower
            ; y2 < center
            ldb FLY_RADIUS,u
            sex
            std <t0
            ldd FLY_CENTER,u
            subd <t0
            addd #12
            cmpd E_Y,u
            ble .cruise         ; y2 >= center - radius + 12
            ldd FLY_SPEEDY,u
            addd #FLY_ACCEL
            bra .sets
.lower      bne .below
            tst FLY_YF,u
            beq .cruise         ; exactly on center
.below      ldb FLY_RADIUS,u
            sex
            addd FLY_CENTER,u
            subd #12
            cmpd E_Y,u
            bgt .cruise         ; turn point below us
            blt .up
            tst FLY_YF,u
            beq .cruise
.up         ldd FLY_SPEEDY,u
            subd #FLY_ACCEL
            bra .sets
.cruise     ldd #FLY_SPEED
            tst FLY_SPEEDY,u
            bpl .sets
            ldd #-FLY_SPEED
.sets       std FLY_SPEEDY,u
            ADDPOS FLY_SPEEDY,FLY_YF,E_Y
            ; Charge, then fire on the following tick.
            ldd <now
            subd FLY_FIRET,u
            cmpd #FLY_FIRE_T
            blo .anim
            tst FLY_CHARGED,u
            bne .fire
            tst <firing_allowed
            beq .anim
            inc FLY_CHARGED,u
            clra
            clrb
            stu <arg0
            jsr Charge_New
            ldx E_X,u
            ldy E_Y,u
            jsr Main_OnScreen
            bne .anim
            lda #SND_CHARGE
            jsr Sound_Play
            bra .anim
.fire       clr FLY_CHARGED,u
            ldx E_X,u
            ldy E_Y,u
            jsr Main_OnScreen
            bne .fired
            lda #SND_ALIEN_FIRE
            jsr Sound_Play
            ldd <man_x
            std <arg0
            ldd <man_y
            std <arg1
            ldx E_X,u
            ldy E_Y,u
            jsr Laser2_New
.fired      ldd <now
            std FLY_FIRET,u
.anim       ldb FLY_TIMER,u
            ldx #fly_frames
            abx
            ldb ,x
            clra
            addd #FLY_START_FRAME
            std E_SPRITE,u
            jsr Alien_DrawSelf
            tst FLY_CHARGED,u
            beq .touch
            ldx E_X,u
            leax -6,x
            ldy E_Y,u
            leay -6,y
            ldd #FLY_CHARGE_SPRITE
            jsr Draw_Sprite
.touch      TOUCH_X 4,.tick
            jsr Ent_TouchesMan
            bne .tick
            lda #LASER_DEATH
            jsr Man_Die
.tick       ldb FLY_TIMER,u
            incb
            cmpb #10
            blo .st
            clrb
.st         stb FLY_TIMER,u
            rts

; ---- Piglet.as --------------------------------------------------------------------------------
PGL_DIR     equ E_DATA+0        ; 0 east, 1 north, 2 west, 3 south: left turn is +1
PGL_HX      equ E_DATA+1
PGL_HY      equ E_DATA+2
PGL_SEG     equ E_DATA+3        ; 0 head, 24 segment: sprite offset
PGL_ANIM    equ E_DATA+4
PGL_ANIMT   equ E_DATA+5
PGL_DESTX   equ E_DATA+7
PGL_DESTY   equ E_DATA+9
PGL_K       equ E_DATA+11       ; 3 * (direction + 4 * animation + 8 * segment): its images, by flame offset
PGL_M       equ E_DATA+12       ; animation flips since the level began
            assert E_DATA+14<=ENT_SIZE,"piglet record"
PGL_STEP_T  equ 8               ; 250 ms: the C steps on the first frame past it, 266 ms
PGL_ANIM_F  equ 27              ; 437 ms: the C flips on the first frame past it, every 27 frames (13.5 ticks)
PGL_ENGINE  equ 132
PGL_SPRITE  equ 228

Piglet_vt   fdb Piglet_Update,Piglet_Hurt,0,0,0
pgl_hxtab   fcb 1,0,-1,0
pgl_hytab   fcb 0,-1,0,1
pgl_flicker fcb 0,1,2,1         ; the flame is 2 + this behind it

; A=parameter: bit 7 segment, low bits direction.
Piglet_New  pshs a,b,x
            ALIEN_ALLOC Piglet_vt
            bne .ok
            puls a,b,x,pc
.ok         ldx 2,s
            ldb 1,s
            jsr AL_InitCentered
            ldd #6*256+6
            std E_SIZEX,u
            lda ,s
            bpl .head
            ldb #24
            stb PGL_SEG,u
.head       anda #3
            sta PGL_DIR,u
            ; IsEven(x, y) is a % 2 == b % 2
            ldb 3,s
            eorb 1,s
            andb #1
            stb PGL_ANIM,u
            bsr pgl_face
            ldd E_X,u
            std PGL_DESTX,u
            ldd E_Y,u
            std PGL_DESTY,u
            leas 4,s
            jsr pgl_new_dest
            ldd <now
            std PGL_ANIMT,u
            ; Piglet.as makes every piglet when the level loads, and they all roll from then on. This one is made only now
            ; that the view is near: its first update puts it where the original's would be by now (pgl_sync, which needs
            ; E_OBJ, set when this returns).
            subd #PGL_STEP_T*2
            std E_START,u
            rts

; Heading and sprite from PGL_DIR.
pgl_face    ldb PGL_DIR,u
            ldx #pgl_hxtab
            lda b,x
            sta PGL_HX,u
            ldx #pgl_hytab
            lda b,x
            sta PGL_HY,u
            addb PGL_SEG,u
            lda PGL_ANIM,u
            beq .s
            addb #4
.s          clra
            addd #PGL_SPRITE
            std E_SPRITE,u
            ldb PGL_DIR,u
            lda PGL_ANIM,u
            beq .k1
            addb #4
.k1         lda PGL_SEG,u
            beq .k2
            addb #8
.k2         pshs b
            aslb
            addb ,s+
            stb PGL_K,u
            rts

; True (Z set) if the next cell along the heading is passable. t2 is free: Main_GetCell's std t2 comes after.
pgl_clear   ldb PGL_HX,u
            sex
            addd <PC_COL
            tfr d,x
            ldb <PC_ROW
            addb PGL_HY,u
            jsr Main_GetCell
            tsta
            beq .out
            cmpa #FLOATY_PLATFORM
.out        rts

pgl_turn    addb PGL_DIR,u
            andb #3
            stb PGL_DIR,u
            bra pgl_face

; GetNewDestination: recenter, try ahead, right, left, back.
pgl_new_dest
            ldd E_X,u
            jsr AL_CellOf
            std <PC_COL
            jsr AL_CellMid
            std E_X,u
            ldd E_Y,u
            jsr AL_CellOf
            stb <PC_ROW
            clra
            jsr AL_CellMid
            std E_Y,u
            ; AL_CellMid uses t3 through Times12: redo the column.
            ldd E_X,u
            jsr AL_CellOf
            std <PC_COL
            bsr pgl_clear
            beq .go
            ldb #-1
            bsr pgl_turn
            bsr pgl_clear
            beq .go
            ldb #2
            bsr pgl_turn
            bsr pgl_clear
            beq .go
            ldb #1
            bsr pgl_turn
            bsr pgl_clear
            bne .out
.go         ldb PGL_HX,u
            beq .gy
            bmi .gxn
            ldd PGL_DESTX,u
            addd #12
            bra .gxs
.gxn        ldd PGL_DESTX,u
            subd #12
.gxs        std PGL_DESTX,u
.gy         ldb PGL_HY,u
            beq .out
            bmi .gyn
            ldd PGL_DESTY,u
            addd #12
            bra .gys
.gyn        ldd PGL_DESTY,u
            subd #12
.gys        std PGL_DESTY,u
.out        rts

Piglet_Update
            TOUCH_X 8,.move
            jsr Ent_TouchesMan
            bne .move
            lda #PHYSICAL_DEATH
            jsr Man_Die
.move       ldd <now
            subd E_START,u
            cmpd #PGL_STEP_T*2
            blo .timely
            ; It has been asleep, far from the view, while the original's went on rolling.
            jsr pgl_sync
            ldd <now
            subd E_START,u
.timely     tsta
            bne .full
            cmpb #PGL_STEP_T
            blo .part
.full       ldb #PGL_STEP_T
.part       stb <t0             ; elapsed, at most the step time
            ; offset = 12 * t / T = elapsed * 3 / 2, position = dest - heading * (12 - offset)
            lda #3
            mul
            lsrb
            subb #12            ; -(12 - offset)
            lda PGL_HX,u
            beq .ny
            bpl .xok
            negb
.xok        sex
            addd PGL_DESTX,u
            std E_X,u
            bra .step
.ny         lda PGL_HY,u
            beq .step
            bpl .yok
            negb
.yok        sex
            addd PGL_DESTY,u
            std E_Y,u
.step       lda <t0
            cmpa #PGL_STEP_T
            blo .engine
            ldd <now
            subd E_START,u
            cmpd #PGL_STEP_T*2
            bhs .restart
            ldd E_START,u
            addd #PGL_STEP_T
            bra .started
.restart    ldd <now
.started    std E_START,u
            jsr pgl_new_dest
            ; Animation.
.engine     ldd <now
            subd PGL_ANIMT,u
            bmi .draw           ; before the next flip
            ldd PGL_M,u
            addd #1
            std PGL_M,u
            jsr pgl_next_flip
            lda PGL_ANIM,u
            eora #1
            sta PGL_ANIM,u
            ldb #4
            pshs a
            lda PGL_K,u
            adda #12
            tst ,s+
            bne .up
            suba #24
            ldb #-4
.up         sta PGL_K,u
            sex
            addd E_SPRITE,u
            std E_SPRITE,u
            ; It and its flame are one image. ENGINE_FLICKER: 62.5 ms is 1.875 ticks, taken as 2.
.draw       ldb <now+1
            lsrb
            andb #3
            ldx #pgl_flicker
            ldb b,x
            addb PGL_K,u
            clra
            addd #PGL_COMP
            ldx E_X,u
            leax -10,x
            ldy E_Y,u
            leay -10,y
            jmp Draw_Sprite

; U=piglet. PGL_ANIMT = the tick of the flip after PGL_M flips: level start + 27 * (m + 1) / 2.
pgl_next_flip
            ldd PGL_M,u
            addd #1
            pshs d
            ldb #PGL_ANIM_F
            mul                 ; high byte * 27
            tfr b,a
            clrb
            pshs d
            lda 3,s
            ldb #PGL_ANIM_F
            mul                 ; low byte * 27
            addd ,s++
            leas 2,s
            lsra
            rorb
            addd <level_start_t
            std PGL_ANIMT,u
            rts

; D=dividend, t2=divisor (a word, not 0). Returns X=quotient, D=remainder. Keeps Y, U.
pgl_div     pshs d
            ldd #0
            ldx #16
.bit        asl 1,s
            rol ,s
            rolb
            rola
            cmpd <t2
            blo .no
            subd <t2
            inc 1,s
.no         leax -1,x
            bne .bit
            puls x,pc

; U=piglet: puts it where the original's is by now. gen_assets.py's piglet_routes gives each piglet's loop of moves
; (after the level's objects: a count, then object index, length and address of the moves, four to a byte). From the
; ticks since the level began follow the step it is on, its cell, heading and step time, and its animation. A piglet
; with no route is left as it is. The level's bank is read through lvl_byte.
pgl_sync    pshs y
            ldd <lvl_objcount
            aslb
            rola
            aslb
            rola
            addd <lvl_objects
            tfr d,x
            jsr lvl_byte
            sta <t4             ; routes
            beq .out
.find       jsr lvl_byte
            tfr a,b
            jsr lvl_byte
            exg a,b
            cmpd E_OBJ,u
            beq .found
            leax 3,x
            dec <t4
            bne .find
.out        puls y,pc
.found      jsr lvl_byte
            sta <t2+1           ; the loop's length
            clr <t2
            jsr lvl_byte
            tfr a,b
            jsr lvl_byte
            exg a,b
            tfr d,y             ; its moves
            ldd <now
            subd <level_start_t
            pshs d              ; ticks since the level began (t3 and t4 are PC_COL and PC_ROW)
            lsra
            rorb
            lsra
            rorb
            lsra
            rorb
            pshs d              ; steps
            jsr pgl_div
            incb
            stb <t0             ; moves to take: the step within the loop, and the constructor's
            puls d
            aslb
            rola
            aslb
            rola
            aslb
            rola
            addd <level_start_t
            std E_START,u
            ; From its cell in the object list.
            ldd E_OBJ,u
            aslb
            rola
            aslb
            rola
            addd <lvl_objects
            tfr d,x
            leax 1,x
            jsr lvl_byte
            tfr a,b
            jsr lvl_byte
            exg a,b
            std <PC_COL
            jsr lvl_byte
            sta <PC_ROW
            eora <PC_COL+1      ; IsEven: its first animation state
            anda #1
            sta PGL_ANIM,u
            tfr y,x
            clr <t1
.walk       lda <t1
            inc <t1
            anda #3
            bne .have
            jsr lvl_byte
            sta <t5
.have       clrb
            lsl <t5
            rolb
            lsl <t5
            rolb
            stb PGL_DIR,u
            ldy #pgl_hytab
            lda b,y
            adda <PC_ROW
            sta <PC_ROW
            ldy #pgl_hxtab
            ldb b,y
            sex
            addd <PC_COL
            std <PC_COL
            dec <t0
            bne .walk
            ldd <PC_COL
            jsr AL_CellMid
            std PGL_DESTX,u
            std E_X,u
            ldb <PC_ROW
            clra
            jsr AL_CellMid
            std PGL_DESTY,u
            std E_Y,u
            ; Animation flips at frames 27, 54, ... since the level began.
            ldd #PGL_ANIM_F
            std <t2
            puls d
            aslb
            rola
            jsr pgl_div
            stx PGL_M,u
            tfr x,d
            andb #1
            eorb PGL_ANIM,u
            stb PGL_ANIM,u
            jsr pgl_next_flip
            jsr pgl_face
            puls y,pc

; Invulnerable: a spark at the laser, clipped to the sprite.
Piglet_Hurt ldx <hurt_laser
            beq .out
            ldd L_VX,x
            std <arg0
            ldd L_X,x
            subd E_X,u
            cmpd #6
            bgt .right
            cmpd #-7
            blt .left
            ldd L_X,x
            bra .have
.right      ldd E_X,u
            addd #6
            bra .have
.left       ldd E_X,u
            subd #7
.have       ldy L_Y,x
            tfr d,x
            jsr NoDamage_New
            lda #SND_NO_DAMAGE
            jmp Sound_Play
.out        rts

; ---- Popper.as --------------------------------------------------------------------------------
POP_YF      equ E_DATA+0
POP_SY      equ E_DATA+1        ; signed 8.8, pixels per update
POP_LAST    equ E_DATA+3        ; lastUpdateTime
POP_FREQ    equ E_DATA+5        ; ticks between updates
POP_STATE   equ E_DATA+6
POP_HEAD    equ E_DATA+7
POP_FIRED   equ E_DATA+8        ; fireCount
POP_Q       equ E_DATA+9        ; its height, to 4 pixels, when it last looked ahead. $FF: it must look
POP_GEN     equ E_DATA+10       ; cell_gen then
            assert E_DATA+11<=ENT_SIZE,"popper record"
POPS_MOVE   equ 0
POPS_SQIN   equ 1
POPS_SQOUT  equ 2
POPS_PAUSE  equ 3
POPS_SUSP   equ 4
POP_BASE    equ 204
; The C's "elapsed > 33 ms" is true every second 60 Hz frame, which is every tick; 66 ms every fourth, two ticks.
POP_MOVE_F  equ 1
POP_SLOW_F  equ 2
POP_SQUISH_T equ 2              ; 66 ms, tested only on a 2-tick update
POP_PAUSE_T equ 10              ; 333 ms
POP_ANIM_T  equ 8               ; 250 ms
POP_ANIM_H  equ 4               ; 125 ms

Popper_vt   fdb Popper_Update,0,0,0,0

Popper_New  pshs b,x
            ALIEN_ALLOC Popper_vt
            beq .full
            puls b,x
            jsr AL_InitCentered
            lda #POPS_SUSP
            sta POP_STATE,u
            lda #POP_SLOW_F
            sta POP_FREQ,u
            lda #1
            sta POP_HEAD,u
            ldd #48
            std E_HEALTH,u
            lda #6
            sta E_SCORE,u
            ldd #POP_BASE
            std E_SPRITE,u
            ldd #6*256+3
            std E_SIZEX,u
            jmp Main_AddToKillCount
.full       puls b,x,pc

; 3 - 3 * heading: 0 going down, 6 going up.
pop_turn    ldb #0
            tst POP_HEAD,u
            bpl .out
            ldb #6
.out        rts

; A=state.
Popper_SwitchState
            sta POP_STATE,u
            ldb #$FF
            stb POP_Q,u
            ldx <now
            stx E_START,u
            ldx #4*256+5
            stx E_SIZEX,u
            cmpa #POPS_MOVE
            beq .move
            cmpa #POPS_SQIN
            beq .sqin
            cmpa #POPS_SQOUT
            beq .sqout
            lda #POP_SLOW_F
            sta POP_FREQ,u
            lda POP_STATE,u
            cmpa #POPS_PAUSE
            beq .pause
            ldd #POP_BASE
            std E_SPRITE,u
            rts
.pause      bsr pop_turn
            bra .sprite
.move       lda #POP_MOVE_F
            sta POP_FREQ,u
            ldb #2
            lda POP_HEAD,u
            bpl .m1
            ldb #-2
.m1         sex
            addd E_Y,u
            std E_Y,u
            ldd #0
            std POP_SY,u
            bsr pop_turn
            addb #4
            bra .sprite
.sqin       clr POP_YF,u
            clr POP_FIRED,u
            neg POP_HEAD,u
.sqout      lda #POP_SLOW_F
            sta POP_FREQ,u
            bsr pop_turn
            incb
.sprite     clra
            addd #POP_BASE
            std E_SPRITE,u
            rts

; Two shots out to the sides.
Popper_Fire jsr AL_RectOn
            lbne .count
            tst <firing_allowed
            lbeq .count
            lda #SND_ALIEN_FIRE
            jsr Sound_Play
            ; shotY = int(y2 + 1 + 1.5 * heading)
            ldd E_Y,u
            tst POP_HEAD,u
            bmi .up
            addd #2
            tst POP_YF,u
            bpl .sy
            addd #1
            bra .sy
.up         subd #1
            tst POP_YF,u
            bpl .sy
            addd #1
.sy         tfr d,y
            pshs y
            ldb E_SIZEX,u
            clra
            addd E_X,u
            tfr d,x
            ldd #3*257
            jsr Circle_New
            ; right shot
            ldb E_SIZEX,u
            clra
            addd E_X,u
            pshs d
            addd #1
            std <arg0
            ldd 2,s
            std <arg1
            puls d
            subd #1
            tfr d,x
            ldy ,s
            jsr Laser2_New
            ; left
            ldb E_SIZEX,u
            clra
            std <t0
            ldd E_X,u
            subd <t0
            tfr d,x
            ldy ,s
            ldd #3*257
            jsr Circle_New
            ldb E_SIZEX,u
            clra
            std <t0
            ldd E_X,u
            subd <t0
            pshs d
            subd #1
            std <arg0
            ldd 2,s
            std <arg1
            puls d
            addd #1
            tfr d,x
            puls y
            jsr Laser2_New
.count      inc POP_FIRED,u
            rts

Popper_Update
            ldd <now
            subd POP_LAST,u
            cmpb POP_FREQ,u
            lblo .contact
            ldd <now
            std POP_LAST,u
            lda POP_STATE,u
            beq .move
            cmpa #POPS_SUSP
            beq .susp
            ; The timed states.
            ldd <now
            subd E_START,u
            tfr b,a
            ldb POP_STATE,u
            cmpb #POPS_PAUSE
            beq .pause
            cmpa #POP_SQUISH_T
            lblo .contact
            cmpb #POPS_SQIN
            bne .out
            lda #POPS_PAUSE
            bra .switch
.out        lda #POPS_MOVE
            bra .switch
.pause      cmpa #POP_PAUSE_T
            lblo .contact
            lda #POPS_SQOUT
            bra .switch
.susp       jsr AL_RectOn
            lbne .contact
            lda #POPS_MOVE
.switch     jsr Popper_SwitchState
            lbra .contact
.move       ADDPOS POP_SY,POP_YF,E_Y
            ; Accelerate toward +-1.
            ldd POP_SY,u
            addd #($0100)-1
            cmpd #(($0100)-1)*2
            bhi .anim
            ldd #$0040
            tst POP_HEAD,u
            bpl .ac
            ldd #-$0040
.ac         addd POP_SY,u
            std POP_SY,u
.anim       ldd <now
            subd E_START,u
            cmpd #POP_ANIM_T
            bls .a1
            ldx <now
            stx E_START,u
.a1         cmpd #POP_ANIM_H
            bls .a2
            jsr pop_turn
            addb #4
            bra .a3
.a2         jsr pop_turn
            addb #5
.a3         clra
            addd #POP_BASE
            std E_SPRITE,u
            ldb E_Y+1,u
            andb #$FC
            lda cell_gen
            cmpb POP_Q,u
            bne .look
            cmpa POP_GEN,u
            lbeq .contact
.look       stb POP_Q,u
            sta POP_GEN,u
            jsr AL_PosCells
            tst POP_FIRED,u
            bne .wall
            ; Fire just before arriving: sizeY + 3 = 8 pixels ahead.
            clra
            ldb #8
            tst POP_HEAD,u
            bpl .e1
            ldb #-8
.e1         jsr AL_Near
            tsta
            beq .wall
            cmpa #FLOATY_PLATFORM
            beq .wall
            jsr Popper_Fire
            jsr AL_PosCells
.wall       clra
            ldb #4              ; sizeY - 1
            tst POP_HEAD,u
            bpl .w1
            ldb #-4
.w1         jsr AL_Near
            tsta
            beq .contact
            cmpa #FLOATY_PLATFORM
            beq .contact
            lda #POPS_SQIN
            jsr Popper_SwitchState
.contact    TOUCH_X 8,.draw
            jsr Ent_TouchesMan
            bne .draw
            lda #PHYSICAL_DEATH
            jsr Man_Die
.draw       ldd E_SPRITE,u
            jmp Alien_DrawSelf

; ---- Seeker.as --------------------------------------------------------------------------------
SKR_XF      equ E_DATA+0
SKR_YF      equ E_DATA+1
SKR_VX      equ E_DATA+2
SKR_VY      equ E_DATA+4
SKR_FLASHT  equ E_DATA+6
            assert E_DATA+8<=ENT_SIZE,"seeker record"
SKR_ACCEL   equ 27              ; 96 px/s^2 is 27.3
SKR_LIMIT2  equ 41943           ; (limit / 2)^2 where the limit is 48 px/s = 409.6
SKR_BIRTH_T equ 30              ; 1000 ms
SKR_FLASH_INT equ 15            ; 500 ms
SKR_FLASH_T equ 8               ; 250 ms
SKR_LIFE_T  equ 540             ; 18000 ms
SKR_SPRITE  equ 150
SKR_FLASH_SPRITE equ 65
; Scratch of the vector code.
SKR_ABSX    equ t0
SKR_ABSY    equ t1
SKR_SIGNS   equ t2              ; negative flags, x then y
SKR_UX      equ t4              ; unit vector, 0.8 magnitudes
SKR_UY      equ t4+1

Seeker_vt   fdb Seeker_Update,Seeker_Hurt,Seeker_Die,Seeker_DeathEffect,Seeker_HitEffect

; X=x, Y=y in pixels, arg0=speed x, arg1=speed y, 8.8 per tick. Returns U=record or 0. Like a spawn-table constructor it
; does not keep the caller's U. No level object, so it never despawns or respawns.
Seeker_New  pshs x,y
            ALIEN_ALLOC Seeker_vt
            bne .ok
            puls x,y,pc
.ok         puls x,y
            stx E_X,u
            sty E_Y,u
            lda E_FLAGS,u
            ora #EF_SOLID
            sta E_FLAGS,u
            ldd #16
            std E_HEALTH,u
            lda #2
            sta E_SCORE,u
            ldd #2*256+2
            std E_SIZEX,u
            ldd #SKR_SPRITE
            std E_SPRITE,u
            ldd <arg0
            std SKR_VX,u
            ldd <arg1
            std SKR_VY,u
            ldd <now
            std E_START,u
            std SKR_FLASHT,u
            ; Contrail_New(CONTRAIL_SEEKER, 0, 0, this)
            ldd #0
            std <arg0
            stu <arg1
            jsr Contrail_New
            rts

Seeker_Die  lda E_FLAGS,u
            anda #~EF_ACTIVE&$FF
            sta E_FLAGS,u
            lda #4              ; BLAST_RADIUS
            ldb #ALLIES
            ldx E_X,u
            ldy E_Y,u
            jsr AreaEffect_New
            jmp Entity_DeathEffect

Seeker_HitEffect
            lda #SND_MACHINE_HIT
            jsr Sound_Play
            lda #3
            ldb #COLOR_GREEN
            ldx <hit_x
            ldy <hit_y
            jsr CircleColored_New
            ldx <hit_x
            ldy <hit_y
            jmp skr_distort

; Distortion_New(DISTORTION_STATIC, DISTORTION_SIZE_2, DISTORTION_OFFSET_2, x, y). X, Y set.
skr_distort ldd #6
            std <arg0
            lda #1
            ldb #6
            jsr Distortion_New
            rts

Seeker_DeathEffect
            lda #4
            ldb #COLOR_RED
            ldx E_X,u
            ldy E_Y,u
            jsr CircleColored_New
            ldx E_X,u
            ldy E_Y,u
            bsr skr_distort
            FX_COUNT Explosion_New,8
            lda #SND_QUIET_EXPLOSION
            jmp Sound_Play

; The HitEffect comes first here, unlike Alien.Hurt.
Seeker_Hurt ldx <hurt_laser
            beq .self
            ldd L_X,x
            ldx L_Y,x
            bra .hit
.self       ldd E_X,u
            ldx E_Y,u
.hit        jsr Entity_HitEffect
            ldd E_HEALTH,u
            subd <hurt_damage
            std E_HEALTH,u
            bgt .out
            jmp Entity_Die
.out        rts

; D=x, X=y, signed. Loads SKR_ABS*, SKR_SIGNS.
skr_abs     clr <SKR_SIGNS
            clr <SKR_SIGNS+1
            tsta
            bpl .xp
            coma
            comb
            addd #1
            com <SKR_SIGNS
.xp         std <SKR_ABSX
            tfr x,d
            tsta
            bpl .yp
            coma
            comb
            addd #1
            com <SKR_SIGNS+1
.yp         std <SKR_ABSY
            ; falls through
; Normalize: scales SKR_ABS* into 8 bits, then the minor/major ratio r (x256) picks the unit vector.
; The minor axis is r * major, so a small offset still steers (the old 4-bit table gave 0 below 1/16).
; Uses t3.
skr_unit    ldd <SKR_ABSX
            ora <SKR_ABSY
            beq .low
            lsr <SKR_ABSX
            ror <SKR_ABSX+1
            lsr <SKR_ABSY
            ror <SKR_ABSY+1
            bra skr_unit
.low        lda <SKR_ABSX+1
            ldb <SKR_ABSY+1
            clr <t3             ; 0: x is the major axis
            pshs a
            cmpb ,s+
            bls .ord
            exg a,b
            com <t3
.ord        tsta
            bne .norm
            clr <SKR_UX         ; both zero
            clr <SKR_UY
            rts
.norm       tsta
            bmi .rec
            asla
            aslb
            bra .norm
.rec        stb <t3+1           ; minor, major in A is 128..255
            ldx #skr_recip+128
            ldb a,x             ; 32768 / major
            lda <t3+1
            mul
            aslb
            rola
            bcc .r
            lda #255
.r          sta <t3+1           ; r = minor * 256 / major
            lsra
            lsra
            ldx #skr_cos
            ldb a,x             ; major unit = 255 / sqrt(1 + r^2)
            pshs b
            lda <t3+1
            mul
            aslb
            adca #0             ; minor unit = r * major unit
            puls b
            tst <t3
            bne .ymaj
            stb <SKR_UX
            sta <SKR_UY
            rts
.ymaj       sta <SKR_UX
            stb <SKR_UY
            rts

; min(255, 32768 / (128 + i)).
skr_recip   fcb 255,254,252,250,248,246,245,243,241,239,237,236,234,232,231,229
            fcb 228,226,224,223,221,220,218,217,216,214,213,211,210,209,207,206
            fcb 205,204,202,201,200,199,197,196,195,194,193,192,191,189,188,187
            fcb 186,185,184,183,182,181,180,179,178,177,176,175,174,173,172,172
            fcb 171,170,169,168,167,166,165,165,164,163,162,161,161,160,159,158
            fcb 158,157,156,155,155,154,153,152,152,151,150,150,149,148,148,147
            fcb 146,146,145,144,144,143,142,142,141,141,140,139,139,138,138,137
            fcb 137,136,135,135,134,134,133,133,132,132,131,131,130,130,129,129
; 255 / sqrt(1 + r^2), r = (4i + 2) / 256.
skr_cos     fcb 255,255,255,255,254,254,254,253,253,252,252,251,250,250,249,248
            fcb 247,246,245,244,243,242,241,239,238,237,236,234,233,232,230,229
            fcb 227,226,224,223,222,220,219,217,215,214,212,211,209,208,206,205
            fcb 203,202,200,199,197,196,194,193,191,190,188,187,185,184,182,181

; D += accel along one axis. B=unit magnitude, A=sign flag. Returns D=signed accel.
skr_acc     pshs a
            lda #SKR_ACCEL
            mul
            aslb
            adca #0
            tfr a,b
            clra
            tst ,s+
            beq .out
            coma
            comb
            addd #1
.out        rts

; B=unit magnitude, A=sign. Returns D=signed speed at the limit: 409.6 / 255 is 1.606.
skr_limit   pshs a,b
            lda #155
            mul
            tfr a,b
            clra
            addb 1,s
            adca #0
            tst ,s
            leas 2,s
            beq .out
            coma
            comb
            addd #1
.out        rts

; Integer part of position + unit vector: X=integer, A=fraction, B=unit magnitude (0.8), t1 non-zero if negative.
skr_probe   tst <t1
            bne .neg
            pshs b
            adda ,s+
            tfr x,d
            bcc .out
            addd #1
.out        rts
.neg        pshs b
            suba ,s+
            tfr x,d
            bcc .out2
            subd #1
.out2       rts

Seeker_Update
            ldd <man_x
            subd E_X,u
            pshs d
            ldd <man_y
            subd E_Y,u
            tfr d,x
            puls d
            jsr skr_abs
            lda <SKR_SIGNS
            ldb <SKR_UX
            jsr skr_acc
            addd SKR_VX,u
            std SKR_VX,u
            lda <SKR_SIGNS+1
            ldb <SKR_UY
            jsr skr_acc
            addd SKR_VY,u
            std SKR_VY,u
            ; Over the limit? Half-speeds squared, so that they fit a word.
            ldd SKR_VX,u
            jsr Abs_D
            lsra
            rorb
            tsta
            bne .over
            tfr b,a
            mul
            std <t3
            ldd SKR_VY,u
            jsr Abs_D
            lsra
            rorb
            tsta
            bne .over
            tfr b,a
            mul
            addd <t3
            bcs .over
            cmpd #SKR_LIMIT2
            bhi .over
            ; Under it. Normalize the velocity for the probe below.
            ldd SKR_VX,u
            ldx SKR_VY,u
            jsr skr_abs
            bra .move
.over       ldd SKR_VX,u
            ldx SKR_VY,u
            jsr skr_abs
            lda <SKR_SIGNS
            ldb <SKR_UX
            jsr skr_limit
            std SKR_VX,u
            lda <SKR_SIGNS+1
            ldb <SKR_UY
            jsr skr_limit
            std SKR_VY,u
.move       ADDPOS SKR_VX,SKR_XF,E_X
            ADDPOS SKR_VY,SKR_YF,E_Y
            ; Cell at position + unit velocity.
            lda <SKR_SIGNS+1
            sta <t1
            ldx E_Y,u
            lda SKR_YF,u
            ldb <SKR_UY
            jsr skr_probe
            jsr AL_CellOf
            pshs b
            lda <SKR_SIGNS
            sta <t1
            ldx E_X,u
            lda SKR_XF,u
            ldb <SKR_UX
            jsr skr_probe
            jsr AL_CellOf
            tfr d,x
            puls b
            jsr Main_GetCell
            tsta
            beq .contact
            cmpa #FLOATY_PLATFORM
            beq .contact
            jsr Entity_Die
.contact    TOUCH_X 4,.draw
            jsr Ent_TouchesMan
            bne .draw
            jsr Entity_Die
            lda <man_flags
            bita #MF_INVULN
            bne .draw
            lda #PHYSICAL_DEATH
            jsr Man_Die
.draw       ldd <now
            subd E_START,u
            cmpd #SKR_BIRTH_T
            bhs .plain
            lda #COLOR_WHITE
            sta <draw_color
            ldx E_X,u
            leax -6,x
            ldy E_Y,u
            leay -6,y
            ldd E_SPRITE,u
            jsr Draw_ColoredSprite
            bra .flash
.plain      ldd E_SPRITE,u
            jsr Alien_DrawSelf
.flash      ldd <now
            subd SKR_FLASHT,u
            cmpd #SKR_FLASH_INT
            blo .fl2
            ldd <now
            std SKR_FLASHT,u
            bra .age
.fl2        cmpd #SKR_FLASH_T
            bhs .age
            ldx E_X,u
            leax -6,x
            ldy E_Y,u
            leay -6,y
            ldd #SKR_FLASH_SPRITE
            jsr Draw_Sprite
.age        ldd <now
            subd E_START,u
            cmpd #SKR_LIFE_T
            blo .out
            FX_COUNT Circle_New,4
            jmp Entity_Die
.out        rts

; ---- Trooper.as -------------------------------------------------------------------------------
TRP_HEAD    equ GC_END+0
TRP_NEXT    equ GC_END+1        ; nextBlast, ticks
TRP_PATROL  equ GC_END+2
TRP_WAIT    equ GC_END+3        ; signed, in the C's 60 Hz frames, less 2 per tick
TRP_STATE   equ GC_END+4
TRP_FIRET   equ GC_END+5
TRP_RUNF    equ GC_END+7
TRP_PAUSET  equ GC_END+8
TRP_DIST    equ GC_END+10
TRP_CHARGED equ GC_END+11
TRP_SY      equ GC_END+12
TRP_SX      equ GC_END+13
TRP_FRAME   equ GC_END+14
            assert GC_END+15<=ENT_SIZE,"trooper record"
; The C's state numbers, which the ambushes use.
TRPS_FIRE   equ 0
TRPS_RUN    equ 1
TRPS_PAUSE  equ 2
TRPS_JUMP   equ 3
TRPS_SUSP   equ 4
TRP_FIRE_T  equ 56              ; 1875 ms
TRP_FIRE_T2 equ 28              ; half
TRP_ANIM_T  equ 2               ; 66 ms
TRP_CHARGE_T equ 11             ; 375 ms
TRP_SUSP_T  equ 10              ; 333 ms
TRP_PAUSE_T equ 30              ; 1000 ms
TRP_START   equ 72
TRP_CHARGE_SPRITE equ 70
TRP_RUN_WAIT equ 6              ; frames
TRP_JUMP_WAIT equ 3             ; frames: alternately 1 and 2 ticks

Trooper_vt  fdb Trooper_Update,0,0,0,0

; A: 1 moves, 0 stationary.
Trooper_New pshs a,b,x
            ALIEN_ALLOC Trooper_vt
            bne .ok
            puls a,b,x,pc
.ok         puls a,b,x
            pshs a
            jsr AL_InitCentered
            puls a
            sta TRP_PATROL,u
            lda #TRPS_SUSP
            sta TRP_STATE,u
            lda #-1
            sta TRP_HEAD,u
            ldd #TRP_START
            std E_SPRITE,u
            lda #5
            sta E_SCORE,u
            ldd #4*256+6
            std E_SIZEX,u
            ; pauseTime stays 0: a late spawn has long passed SUSPEND_TIME, like an ambush child in the C.
            jmp Main_AddToKillCount

; U=entity, A=state. Far-callable.
Trooper_SwitchState
            sta TRP_STATE,u
            beq .fire
            cmpa #TRPS_RUN
            beq .run
            cmpa #TRPS_PAUSE
            beq .pause
            cmpa #TRPS_JUMP
            beq .jump
            rts
.fire       jsr AL_AimX
            sta TRP_HEAD,u
            ; CheckForWall: one whole cell ahead.
            jsr AL_PosCells
            ldb #12
            tst TRP_HEAD,u
            bpl .f1
            ldb #-12
.f1         tfr b,a
            clrb
            jsr AL_Near
            tsta
            beq .f2
            cmpa #FLOATY_PLATFORM
            beq .f2
            neg TRP_HEAD,u
.f2         ldd <now
            std TRP_FIRET,u
            lda #TRP_FIRE_T2
            sta TRP_NEXT,u
            rts
.run        lda #TRP_RUN_WAIT
            sta TRP_WAIT,u
            jsr Random
            lda #72             ; RUN_DISTANCE
            mul
            sta TRP_DIST,u
            rts
.pause      ldd <now
            std TRP_PAUSET,u
            rts
.jump       lda TRP_HEAD,u
            sta TRP_SX,u
            lda #-3
            sta TRP_SY,u
            rts

Trooper_CheckGround
            jsr AL_Ground
            tsta
            beq .air
            cmpa #LAVA
            beq .lava
            cmpa #LAVA2
            beq .lava
            rts
.air        lda #TRPS_JUMP
            jsr Trooper_SwitchState
            clr TRP_CHARGED,u
            rts
.lava       ldd E_SPRITE,u
            std <arg0
            std <arg1
            ldx E_X,u
            ldy E_Y,u
            lda #96             ; 2 * sizeX * 2 * sizeY
            jmp AL_Sink

Trooper_Update
            clr TRP_FRAME,u
            lda TRP_STATE,u
            beq .fire
            cmpa #TRPS_RUN
            lbeq .run
            cmpa #TRPS_PAUSE
            lbeq .pause
            cmpa #TRPS_JUMP
            lbeq .jump
            ; Suspended.
            ldd <now
            subd TRP_PAUSET,u
            cmpd #TRP_SUSP_T
            lblo .end
            jsr AL_RectOn
            lbne .end
            clra
            jsr Trooper_SwitchState
            lbra .end

.fire       jsr AL_RectOn
            lbne .offscr
            tst <firing_allowed
            lbeq .offscr
            ldd <now
            subd TRP_FIRET,u
            tsta
            beq .e8
            ldb #255
.e8         pshs b
            tst TRP_CHARGED,u
            bne .nocharge
            lda TRP_NEXT,u
            suba #TRP_CHARGE_T
            cmpa ,s
            bhi .nocharge
            inc TRP_CHARGED,u
            lda #5
            tst TRP_HEAD,u
            bpl .c1
            lda #-6
.c1         ldb #1
            stu <arg0
            jsr Charge_New
            bra .anim
.nocharge   lda TRP_NEXT,u
            cmpa ,s
            bhi .anim
            clr TRP_CHARGED,u
            lda #SND_ALIEN_FIRE
            jsr Sound_Play
            ldd E_Y,u
            addd #1
            tfr d,y
            ldx E_X,u
            lda TRP_HEAD,u
            jsr AlienLaser_New
            clra
            jsr Trooper_SwitchState
            lda #TRP_FIRE_T
            sta TRP_NEXT,u
            tst TRP_PATROL,u
            beq .anim
            jsr Random
            cmpb #64
            bhs .anim
            lda #TRPS_PAUSE
            jsr Trooper_SwitchState
.anim       puls b
            cmpb #TRP_ANIM_T
            bhi .ground
            lda #1
            sta TRP_FRAME,u
.ground     jsr Trooper_CheckGround
            lbra .end
.offscr     clr TRP_CHARGED,u
            tst TRP_PATROL,u
            beq .ground
            lda #TRPS_RUN
            jsr Trooper_SwitchState
            bra .ground

.run        tst TRP_WAIT,u
            lbgt .runwait
            ; A step: x moves one pixel, checked sizeX ahead.
            ldb TRP_HEAD,u
            sex
            addd E_X,u
            std E_X,u
            jsr AL_PosCells
            lda #4
            tst TRP_HEAD,u
            bpl .r1
            lda #-4
.r1         pshs a
            clrb
            jsr AL_Near
            tsta
            bne .rback
            lda ,s
            ldb #6
            jsr AL_Near
            tsta
            bne .rstep
            ; A drop ahead: jump it if something safe is below.
            ldb ,s
            sex
            addd E_X,u
            tfr d,x
            ldy E_Y,u
            lda #3
            jsr Main_PitCheck
            tsta
            beq .rback
            cmpa #LAVA
            beq .rback
            cmpa #GOAL
            beq .rback
            lda #TRPS_JUMP
            jsr Trooper_SwitchState
            bra .rstep
.rback      ldb TRP_HEAD,u
            sex
            coma
            comb
            addd #1
            addd E_X,u
            std E_X,u
            neg TRP_HEAD,u
.rstep      leas 1,s
            lda TRP_RUNF,u
            inca
            cmpa #4
            blo .rf
            clra
.rf         sta TRP_RUNF,u
            dec TRP_DIST,u
            pshs cc
            lda TRP_WAIT,u
            adda #TRP_RUN_WAIT
            sta TRP_WAIT,u
            puls cc
            bgt .runwait
            lda #TRPS_FIRE
            tst <firing_allowed
            bne .r9
            lda #TRPS_PAUSE
.r9         jsr Trooper_SwitchState
.runwait    lda TRP_WAIT,u
            suba #2
            sta TRP_WAIT,u
            lda TRP_RUNF,u
            adda #2
            sta TRP_FRAME,u
            jsr Trooper_CheckGround
            lbra .end

.pause      ldd <now
            subd TRP_PAUSET,u
            cmpd #TRP_PAUSE_T
            bls .pg
            lda #TRPS_RUN
            jsr Trooper_SwitchState
.pg         jsr Trooper_CheckGround
            lbra .end

.jump       tst TRP_WAIT,u
            lbgt .jwait
            ldb TRP_SX,u
            sex
            addd E_X,u
            std E_X,u
            ldb TRP_SY,u
            sex
            addd E_Y,u
            std E_Y,u
            inc TRP_SY,u
            lda TRP_WAIT,u
            adda #TRP_JUMP_WAIT
            sta TRP_WAIT,u
            jsr AL_PosCells
            ldb #6
            jsr AL_NearY
            tsta
            beq .jahead
            cmpa #LAVA
            bne .jland
            ; Into the lava.
            ldb TRP_HEAD,u
            lda #3
            tstb
            bpl .jl1
            nega
            bra .jl2
.jl1        lda #3
.jl2        adda #3
            tfr a,b
            clra
            addd #TRP_START
            std <arg0
            std <arg1
            ldd E_Y,u
            addd #6
            jsr AL_CellOf
            jsr Times12
            subd #4
            tfr d,y
            ldx E_X,u
            lda #24             ; sizeX * sizeY
            jsr AL_Sink
            bra .jwait
.jland      clr TRP_SX,u
            clr TRP_SY,u
            ldd E_Y,u
            addd #6
            jsr AL_CellOf
            jsr Times12
            subd #6
            std E_Y,u
            lda #TRPS_FIRE
            tst <firing_allowed
            bne .jl9
            lda #TRPS_RUN
.jl9        jsr Trooper_SwitchState
            bra .jwait
.jahead     lda #4
            tst TRP_HEAD,u
            bpl .ja1
            lda #-4
.ja1        clrb
            jsr AL_Near
            tsta
            beq .jwait
            ldb #4
            tst TRP_HEAD,u
            bpl .ja2
            ldb #-4
.ja2        sex
            addd E_X,u
            jsr AL_CellOf
            jsr AL_CellMid
            tst TRP_HEAD,u
            bpl .ja3
            addd #10
            bra .ja4
.ja3        subd #10
.ja4        std E_X,u
            neg TRP_SX,u
.jwait      lda TRP_WAIT,u
            suba #2
            sta TRP_WAIT,u

.end        TOUCH_X 6,.spr
            jsr Alien_ContactKillCheck
.spr        ldb #TRP_START
            tst TRP_HEAD,u
            bmi .e1
            addb #6
.e1         addb TRP_FRAME,u
            clra
            std E_SPRITE,u
            jsr Alien_DrawSelf
            tst TRP_CHARGED,u
            beq .out
            ldb #5-6
            tst TRP_HEAD,u
            bpl .e2
            ldb #-6-6
.e2         sex
            addd E_X,u
            tfr d,x
            ldy E_Y,u
            leay -5,y
            ldd #TRP_CHARGE_SPRITE
            jmp Draw_Sprite
.out        rts

            assert *<=$4000,"bank 12 is full"
aliens_end equ *
            endbank
