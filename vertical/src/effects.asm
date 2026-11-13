; effects/*.as. Ported from ../port/src/effects*.c. Fixed ROM.
;
; Constructors keep the caller's U, as the engine relies on. They return X=record with Z clear, or Z set if nothing was
; made. Single byte arguments follow PORTING.md (A, then B), except the ones the engine already calls with B: Explosion_New,
; Circle_New, ScoreText_New, LavaSplash_New. Speeds are the C's px/s as 8.8 per tick (v * 256 / 30). Bit gravity in A is
; a * 256 / 900: use BIT_GRAVITY_32 or BIT_GRAVITY_16 for the C's 32 and 16. Durations are in ticks.
;
; Almost every class here is pushed twice in the C, so it runs 4 updates per tick. Timers add 4, and the flying ones
; move by twice their speed (fx_fly). Spawn before ending: a slot freed first could be handed to the new effect.

CONTRAIL_SEEKER equ 0
DISTORTION_FADE_FORWARD equ 0
DISTORTION_FADE_BACKWARD equ 1
DISTORTION_OFFSET equ 0
DISTORTION_STATIC equ 1
DISTORTION_SIZE_1 equ 3
DISTORTION_SIZE_2 equ 6
DISTORTION_OFFSET_1 equ 2
DISTORTION_OFFSET_2 equ 6
EXPLOSION_BIT_SPEED equ 273     ; 32 px/s
BIT_GRAVITY_32 equ 9
BIT_GRAVITY_16 equ 5
; The title screen sets this; 0 reads as white. It shares the boss's RAM, which is idle on the title screen.
Star_color  equ wiz_ram+511

FX_CULL     equ 340             ; resting decorations free their slot this far from the camera
FX_OBJ      equ 20              ; E_OBJ: the spawner writes the object index here in any record it is handed

; ---- shared helpers -----------------------------------------------------------------------------
; Constructor prologue: jsr fx_open / fdb handler. Continues after the word with U=new record, and A, B, Y as they came.
; The body ends with rts. On a full pool it returns straight to the constructor's caller with Z set.
fx_open     std <t3
            stx <t4
            puls x
            ldd ,x++
            stx <t5
            pshs u
            tfr d,x
            ldd <t4
            jsr Effect_Alloc
            beq .full
            ldd #fx_close
            pshs d
            ldd <t3
            jmp [t5]
.full       puls u,pc
fx_close    tfr u,x
            andcc #$FB
            puls u,pc

fx_end      clr FX_UPDATE,u
            clr FX_UPDATE+1,u
            jsr spawn_room
            cmpu fx_free
            bhs .out
            stu fx_free
.out        rts

; Ends a decoration and lets the spawner bring its object back later, if the spawner made it.
fx_forget   ldd FX_OBJ,u
            cmpd #$FFFF
            beq fx_end
            ldx #obj_spawned
            jsr bit_clear
            bra fx_end

; D=sprite. Draws at (x - 6, y - 6).
fx_drawc    ldx FX_X,u
            leax -6,x
            ldy FX_Y,u
            leay -6,y
            jmp Draw_ColoredSprite
fx_draw     ldx FX_X,u
            leax -6,x
            ldy FX_Y,u
            leay -6,y
            jmp Draw_Sprite

; Returns B=ticks since the start and counts this one. For classes the C times with Main_GetTime.
fx_age      ldb FX_TIMER+1,u
            inc FX_TIMER+1,u
            rts

; A / B, returns the quotient in B.
fx_div      pshs b
            clrb
.loop       suba ,s
            bcs .done
            incb
            bra .loop
.done       leas 1,s
            rts

; A=dx, B=dy, signed. Returns X, Y = this effect's position plus those.
fx_xy       pshs b
            tfr a,b
            sex
            addd FX_X,u
            tfr d,x
            puls b
            sex
            addd FX_Y,u
            tfr d,y
            rts

; A=dx, B=dy, arg1=w,h: a rectangle relative to this effect, in draw_color.
fx_rect     bsr fx_xy
            ldd <arg1
            jmp Draw_RectWorld

; Carry clear when the effect is further than X from the camera on either axis. fx_far uses FX_CULL.
fx_far      ldx #FX_CULL
fx_farx     ldd FX_X,u
            subd <cam_x
            jsr Abs_D
            pshs x
            cmpd ,s++
            bhs .out
            ldd FX_Y,u
            subd <cam_y
            jsr Abs_D
            pshs x
            cmpd ,s++
.out        rts

; X, Y from screen to world. Keeps D.
fx_s2w      pshs d
            tfr x,d
            addd <gcam_left
            tfr d,x
            tfr y,d
            addd <gcam_top
            tfr d,y
            puls d,pc

; A=span. Returns D, a random speed within +-2*span in 8.8.
fx_rspan    pshs a
            jsr Random
            mul
            tfr a,b
            puls a
            lsra
            pshs a
            subb ,s+
            sex
            aslb
            rola
            aslb
            rola
            rts

; B=signed px/s. Returns D=8.8 per tick.
fx_v88      tstb
            bmi .neg
            lda #17
            mul
            lsra
            rorb
            rts
.neg        negb
            lda #17
            mul
            lsra
            rorb
            coma
            comb
            addd #1
            rts

; D=first sprite, X, Y=center, arg1=table of dx, dy pairs ending in $7F: consecutive sprites, for 4-cell images.
fx_quad     pshs y
            pshs x
            pshs d
            ldd <arg1
            pshs d
.loop       ldy ,s
            ldb ,y+
            sex
            addd 4,s
            tfr d,x
            ldb ,y+
            sex
            addd 6,s
            sty ,s
            tfr d,y
            ldd 2,s
            jsr Draw_Sprite
            inc 3,s
            lda [,s]
            cmpa #$7F
            bne .loop
            leas 8,s
            rts

; ---- flying things ------------------------------------------------------------------------------
FXB_VX      equ FX_DATA+0
FXB_VY      equ FX_DATA+2
FXB_G       equ FX_DATA+4
FXB_ACC     equ FX_DATA+5
FXB_FPI     equ FX_DATA+6
FXB_FRAME   equ FX_DATA+7
FXB_SPIN    equ FX_DATA+8
FXB_COLOR   equ FX_DATA+9
FXB_DESC    equ FX_DATA+10
FXB_START   equ FXB_ACC         ; LavaBit, word

; x += 2 vx, y += 2 vy, vy += 2 g.
fx_fly      ldd FXB_VX,u
            aslb
            rola
            ADD_8_8U FX_X
fx_fly_y    ldd FXB_VY,u
            aslb
            rola
            ADD_8_8U FX_Y
            ldb FXB_G,u
            sex
            aslb
            rola
            addd FXB_VY,u
            std FXB_VY,u
            rts

fx_speeds   ldd <arg0
            std FXB_VX,u
            ldd <arg1
            std FXB_VY,u
            rts

; ---- Bit, SmallBit, LargeBit, BitColored: one update and a table ---------------------------------
; Row: sprite, animated, mound size in lava, mound chance of 256, half circle size, circle size.
fxbit_rows
fxbit_large fcb 43,1,3,192,2,2
fxbit_bit   fcb 39,1,2,224,1,1
fxbit_small fcb 71,0,1,255,1,1

; X, Y, arg0=speedX, arg1=speedY, A=gravity. BitColored_New adds B=color.
Bit_New     ldb #fxbit_bit-fxbit_rows
            bra fxbit_new
SmallBit_New
            ldb #fxbit_small-fxbit_rows
            bra fxbit_new
LargeBit_New
            ldb #fxbit_large-fxbit_rows
fxbit_new   jsr gov_thin        ; under load, every other bit of debris is not made
            beq .make
            rts
.make       jsr fx_open
            fdb FxBit_Update
fxbit_init  sta FXB_G,u
            clra
            addd #fxbit_rows
            std FXB_DESC,u
            bsr fx_speeds
            jsr Random
            lda #10
            mul
            adda #5
            sta FXB_FPI,u
            jsr Random
            andb #1
            beq .nospin
            ldb #3
.nospin     stb FXB_SPIN,u
            rts
BitColored_New
            jsr fx_open
            fdb FxBit_Update
            stb FXB_COLOR,u
            ldb #fxbit_small-fxbit_rows
            bra fxbit_init

FxBit_Update
            lbsr fx_fly
            ldx FXB_DESC,u
            ldb ,x
            tst 1,x
            beq .still
            ; The C's timer / framesPerImage % 4, kept as a running count.
            lda FXB_ACC,u
            adda #4
            cmpa FXB_FPI,u
            blo .noadv
            suba FXB_FPI,u
            inc FXB_FRAME,u
.noadv      sta FXB_ACC,u
            lda FXB_FRAME,u
            anda #3
            eora FXB_SPIN,u
            sta <t0
            addb <t0
.still      clra
            tst FXB_COLOR,u
            beq .plain
            pshs d
            lda FXB_COLOR,u
            ldx FX_TIMER,u
            cmpx #20
            bhs .tint
            lda #COLOR_WHITE
.tint       sta <draw_color
            puls d
            jsr fx_drawc
            bra .tick
.plain      jsr fx_draw
.tick       ldd FX_TIMER,u
            addd #4
            std FX_TIMER,u
            cmpd #1800
            lbhi fx_end
            ; Under heavy load it does not last as long.
            cmpd #600
            bls .life
            ldb gov_load
            cmpb #2
            lbhs fx_end
.life
            ; Checked every other tick, by slot: this is the costly part of a bit.
            tfr u,d
            lsrb
            lsrb
            lsrb
            eorb <now+1
            andb gov_mask
            bne .out
            ldx FX_X,u
            ldy FX_Y,u
            jsr Cell_At
            tsta
            beq .out
            cmpa #LAVA
            beq .lava
            cmpa #FLOATY_PLATFORM
            beq .floaty
            cmpa #GOAL
            beq .gone
            ldx FXB_DESC,u
            ldb 5,x
            ldx FX_X,u
            ldy FX_Y,u
            jsr Circle_New
.gone       jmp fx_end
.out        rts
.lava       bsr fx_celltop
            subd #1
            tfr d,y
            ldx FXB_DESC,u
            jsr Random
            cmpb 3,x
            lda 2,x
            ldx FX_X,u
            bhs .bubble
            jsr LavaMound_New
            bra .gone
.bubble     lda #2
            jsr LavaBubble_New
            bra .gone
.floaty     bsr fx_celltop
            subd #5
            tfr d,y
            ldx FXB_DESC,u
            lda 4,x
            ldx FX_X,u
            jsr HalfCircle_New
            bra .gone

; D = int(y / 12) * 12.
fx_celltop  ldd FX_Y,u
            jsr Div12
            jmp Times12

; ---- Explosion and SparkFountain ----------------------------------------------------------------
FXE_COUNT   equ FX_DATA+0
FXE_HEAD    equ FX_DATA+1
FXE_PER_TICK equ 6

; A=0 large, 1 bit, 2 small. X, Y, arg0, arg1 as for Bit_New.
fxbit_kind  ldb #6
            mul
            lda #BIT_GRAVITY_32
            lbra fxbit_new

; B=count, X, Y. The C makes every bit at once; here at most 6 per tick, to spare the tick.
Explosion_New
            jsr fx_open
            fdb Explosion_Update
            stb FXE_COUNT,u
            rts

Explosion_Update
            lda #FXE_PER_TICK
            pshs a
.next       lda FXE_COUNT,u
            beq .done
            dec FXE_COUNT,u
            lda #136
            jsr fx_rspan
            std <arg0
            lda #136
            jsr fx_rspan
            std <arg1
            ldx FX_X,u
            ldy FX_Y,u
            jsr Random
            clra
            cmpb #64
            blo .make
            inca
            cmpb #160
            blo .make
            inca
.make       bsr fxbit_kind
            dec ,s
            bne .next
            puls a,pc
.done       leas 1,s
            jmp fx_end

; A=count, B=heading (1 or -1), X, Y.
SparkFountain_New
            jsr fx_open
            fdb SparkFountain_Update
            stb FXE_HEAD,u
            pshs a
            jsr Random
            mul
            pshs a
            ldb 1,s
            lsrb
            addb ,s+
            leas 1,s
            stb FXE_COUNT,u
            rts

SparkFountain_Update
            lda #77
            jsr fx_rspan
            std <arg1
            lda #38
            jsr fx_rspan
            addd #115
            tst FXE_HEAD,u
            bpl .right
            coma
            comb
            addd #1
.right      std <arg0
            ldx FX_X,u
            ldy FX_Y,u
            jsr Random
            lda #3
            mul
            lbsr fxbit_kind
            lda FXE_COUNT,u
            deca
            sta FXE_COUNT,u
            lble fx_end
            rts

; ---- the plain animations: one update, frames stepping from a sprite ------------------------------
FXA_SPR     equ FX_DATA+0
FXA_FPI     equ FX_DATA+2
FXA_DUR     equ FX_DATA+3
FXA_STEP    equ FX_DATA+4
FXA_COLOR   equ FX_DATA+5
FXA_SIZE    equ FX_DATA+6

; A=frame count, B=frames per image, X=first sprite.
fxa_set     stx FXA_SPR,u
            stb FXA_FPI,u
            mul
            decb
            stb FXA_DUR,u
            rts

; Draws the frame and advances. Carry clear when it has finished.
fxa_body    lda FXA_COLOR,u
            sta <draw_color
            lda FX_TIMER+1,u
            ldb FXA_FPI,u
            jsr fx_div
            lda FXA_STEP,u
            bpl .up
            nega
            mul
            coma
            comb
            addd #1
            bra .have
.up         mul
.have       addd FXA_SPR,u
            tst <draw_color
            beq .plain
            jsr fx_drawc
            bra .tick
.plain      jsr fx_draw
.tick       lda FX_TIMER+1,u
            adda #4
            sta FX_TIMER+1,u
            cmpa FXA_DUR,u
            rts

fxa_update  bsr fxa_body
            lbhs fx_end
            rts

; Circle, HalfCircle and SlowCircle flicker on alternate 60 Hz frames in the C. A tick is 2 of those, and a timer adding 4
; would never land on the visible phase, so they draw on every tick.
; B=size, X, Y.
Circle_New  jsr fx_open
            fdb fxa_update
            ldx #132
            abx
            tfr b,a
            ldb #4
            bra fxa_down

; A=size, X, Y.
HalfCircle_New
            jsr fx_open
            fdb fxa_update
            tfr a,b
            ldx #199
            abx
            ldb #15
fxa_down    bsr fxa_set
            dec FXA_STEP,u
            rts

; A=size, B=color, X, Y.
CircleColored_New
            jsr fx_open
            fdb fxa_update
            stb FXA_COLOR,u
            deca
            tfr a,b
            ldx #131
            abx
            ldb #12
            bra fxa_down

; A=size, B=even, X, Y.
SlowCircle_New
            jsr fx_open
            fdb fxa_update
            ldx #312
            abx
            tfr a,b
            abx
            abx
            inca
            ldb #15
            lbsr fxa_set
            lda #-2
            sta FXA_STEP,u
            rts

; X, Y.
SmallFlash_New
            jsr fx_open
            fdb fxa_update
            ldx #69
            bra fxa_three

; A=color, X, Y.
LaserImpact_New
            jsr fx_open
            fdb fxa_update
            ldb #1
            cmpa #COLOR_RED
            beq .step
            ldb #-1
            cmpa #COLOR_GREEN
            beq .step
            clrb
.step       stb FXA_STEP,u
            ldx #50
            lda #3
            ldb #4
            lbra fxa_set
fxa_three   lda #3
            ldb #4
            lbsr fxa_set
            inc FXA_STEP,u
            rts

; A=size, X, Y.
LavaBubble_New
            jsr fx_open
            fdb LavaBubble_Update
            ldb #20
            ldx #123
            bra fxa_down

LavaBubble_Update
            lbsr fxa_body
            bcs .out
            ldx FX_X,u
            ldy FX_Y,u
            jsr Main_OnScreen
            bne .quiet
            lda #SND_LAVA_IMPACT
            jsr Sound_Play
.quiet      bsr .bit
            jsr Random
            lsrb
            bcc .end
            bsr .bit
.end        jmp fx_end
.out        rts
.bit        ldx FX_X,u
            ldy FX_Y,u
            lda #16
            tfr a,b
            bra fxlava_spray

; X, Y, A=x span, B=y span in whole px/s: a LavaBit with speeds as the C truncates them.
fxlava_spray
            pshs y
            pshs x
            pshs d
            jsr Random
            lda ,s
            mul
            tfr a,b
            lda ,s
            lsra
            pshs a
            subb ,s+
            jsr fx_v88
            std <arg0
            jsr Random
            lda 1,s
            mul
            tfr a,b
            negb
            jsr fx_v88
            std <arg1
            puls d
            puls x
            puls y
            ; falls through

; X, Y, arg0=speedX, arg1=speedY.
LavaBit_New jsr fx_open
            fdb LavaBit_Update
            lda #BIT_GRAVITY_16
            sta FXB_G,u
            jsr fx_speeds
            ldd FX_Y,u
            std FXB_START,u
            rts

LavaBit_Update
            jsr fx_fly
            ldd #123
            jsr fx_draw
            ldd FX_Y,u
            cmpd FXB_START,u
            lbge fx_end
            rts

; B=size, X, Y. The engine calls this one with B. The C's 12 to 21 bits are capped at 8.
FXL_MAX_BITS equ 8
LavaSplash_New
            jsr fx_open
            fdb fxa_update
            pshs b
            ldx #121
            lda #3
            ldb #20
            lbsr fxa_set
            inc FXA_STEP,u
            lda ,s
            cmpa #FXL_MAX_BITS
            bls .n
            lda #FXL_MAX_BITS
.n          pshs a
            tsta
            beq .done
.next       lda 1,s
            lsra
            lsra
            ldb 1,s
            ldx FX_X,u
            ldy FX_Y,u
            bsr fxlava_spray
            dec ,s
            bne .next
.done       leas 2,s
            rts

; A=size, X, Y.
LavaMound_New
            jsr gov_thin
            bne .out
            jsr fx_open
            fdb LavaMound_Update
            sta FXA_SIZE,u
            ldb #40
            mul
            stb FXA_DUR,u
.out        rts

LavaMound_Update
            lda FX_TIMER+1,u
            ldb #20
            jsr fx_div
            cmpb FXA_SIZE,u
            bhs .fall
            negb
            sex
            addd #123
            bra .have
.fall       subb FXA_SIZE,u
            negb
            sex
            addd #125
.have       jsr fx_draw
            lda FX_TIMER+1,u
            adda #4
            sta FX_TIMER+1,u
            cmpa FXA_DUR,u
            lbhs fx_end
            rts

; ---- CircleLarge --------------------------------------------------------------------------------
FXC_START   equ FX_DATA+0
FXC_DUR     equ FX_DATA+1
fxc_cells   fcb 0,-12,-12,-12,-12,0,0,0,$7F

; A=size, X, Y.
CircleLarge_New
            jsr fx_open
            fdb CircleLarge_Update
            sta FXC_START,u
            deca
            ldb #5
            mul
            stb FXC_DUR,u
            rts

CircleLarge_Update
            lda FX_TIMER+1,u
            adda #4
            sta FX_TIMER+1,u
            cmpa FXC_DUR,u
            lbhs fx_end
            adda #4
            ldb #5
            jsr fx_div
            negb
            addb FXC_START,u
            incb
            cmpb #6
            bhi .large
            sex
            addd #130
            jmp fx_draw
.large      negb
            addb #12
            lda #4
            mul
            addd #324
            ldx #fxc_cells
            stx <arg1
            ldx FX_X,u
            ldy FX_Y,u
            jmp fx_quad

; ---- DeathFlash, JumpEffect ----------------------------------------------------------------------
; arg0=sprite, X, Y.
DeathFlash_New
            jsr fx_open
            fdb DeathFlash_Update
            ldd <arg0
            std FXA_SPR,u
            rts

DeathFlash_Update
            lda #COLOR_WHITE
            sta <draw_color
            ldd FXA_SPR,u
            jsr fx_drawc
            jsr fx_age
            cmpb #8
            lbhs fx_end
            rts

; X, Y.
JumpEffect_New
            jsr fx_open
            fdb JumpEffect_Update
            rts

JumpEffect_Update
            jsr fx_age
            cmpb #6
            lbhs fx_end
            lsrb
            cmpb #2
            bne .frame
            clrb
.frame      clra
            addd #306
            pshs d
            lda #COLOR_YELLOW
            sta <draw_color
            puls d
            jmp fx_drawc

; ---- MuzzleFlash and Charge: follow the man or an entity ------------------------------------------
FXF_DX      equ FX_DATA+6
FXF_DY      equ FX_DATA+7
FXF_PARENT  equ FX_DATA+8

; A=dx, B=dy. Follows the man.
MuzzleFlash_New
            jsr fx_open
            fdb fxf_update
            std FXF_DX,u
            ldx #68
            lda #3
            ldb #4
            bra fxf_set

; A=offsetX, B=offsetY, arg0=owner entity.
Charge_New  jsr fx_open
            fdb fxf_update
            std FXF_DX,u
            ldd <arg0
            std FXF_PARENT,u
            ldx #66
            lda #5
            ldb #6
fxf_set     stx FXA_SPR,u
            stb FXA_FPI,u
            deca
            sta FXA_DUR,u       ; the last frame
            rts

fxf_update  ldx FXF_PARENT,u
            beq .man
            ldd E_VT,x
            lbeq fx_end         ; the owner's slot was freed
            ldd E_X,x
            std FX_X,u
            ldd E_Y,x
            bra .have
.man        ldd <man_x
            std FX_X,u
            ldd <man_y
.have       std FX_Y,u
            ldb FXF_DX,u
            sex
            addd FX_X,u
            std FX_X,u
            ldb FXF_DY,u
            sex
            addd FX_Y,u
            std FX_Y,u
            lda FX_TIMER+1,u
            ldb FXA_FPI,u
            jsr fx_div
            pshs b
            cmpb FXA_DUR,u
            blo .live
            jsr fx_end
.live       puls b
            clra
            addd FXA_SPR,u
            jsr fx_draw
            lda FX_TIMER+1,u
            adda #4
            sta FX_TIMER+1,u
            rts

; ---- ChargeBeam ----------------------------------------------------------------------------------
FXH_HX      equ FX_DATA+0
FXH_HY      equ FX_DATA+1

; X, Y, A=heading x, B=heading y.
ChargeBeam_New
            jsr fx_open
            fdb ChargeBeam_Update
            std FXH_HX,u
            rts

ChargeBeam_Update
            jsr fx_age
            cmpb #8
            lbhs fx_end
            lsrb                ; step, 0 to 3
            lda #COLOR_WHITE
            sta <draw_color
            lda FXH_HY,u
            bne .along
            lda FXH_HX,u
.along      pshs a
            pshs b
            ; Offset along the heading, less 1 for the half width.
            tst 1,s
            bmi .back
            subb #4
            bra .off
.back       negb
            addb #3
.off        stb 1,s             ; 0,s step, 1,s offset
            lda #4
            suba ,s             ; size
            tst FXH_HY,u
            bne .vert
            tfr a,b
            lslb
            pshs a
            lda #1
            std <arg1
            puls b
            negb
            lda 1,s
            bra .draw
.vert       pshs a
            tfr a,b
            lslb
            tfr b,a
            ldb #1
            std <arg1
            puls a
            nega
            ldb 1,s
.draw       leas 2,s
            jmp fx_rect

; ---- ChargeBit, ChargeHeavy ----------------------------------------------------------------------
FXG_LEFT    equ FXB_G           ; also ChargeHeavy's remaining ticks
fxg_recip   fcb 0,255,128,85,64,51,43,37

; X, Y, arg0=centerX, arg1=centerY. In ticks the C's 0 to 500 ms at double speed is 1 to 7 ticks, at a constant speed.
ChargeBit_New
            jsr fx_open
            fdb ChargeBit_Update
            jsr Random
            lda #8
            mul
            tsta
            bne .n
            inca
.n          sta FXG_LEFT,u
            ldd <arg0
            subd FX_X,u
            bsr fxg_speed
            std FXB_VX,u
            ldd <arg1
            subd FX_Y,u
            bsr fxg_speed
            std FXB_VY,u
            rts

; D=small signed distance. Returns D=speed to cross it in FXG_LEFT ticks.
fxg_speed   pshs a
            tsta
            bpl .pos
            negb
.pos        ldx #fxg_recip
            lda FXG_LEFT,u
            lda a,x
            mul
            tst ,s+
            bpl .out
            coma
            comb
            addd #1
.out        rts

ChargeBit_Update
            ldd FXB_VX,u
            leax FX_X,u
            jsr add_8_8
            ldd FXB_VY,u
            leax FX_Y,u
            jsr add_8_8
            ldd #71
            jsr fx_draw
            dec FXG_LEFT,u
            lbeq fx_end
            rts

; A=duration in ticks, X, Y. 16 ms per update and 4 updates a tick: it runs at twice the clock, as in the C.
ChargeHeavy_New
            jsr fx_open
            fdb ChargeHeavy_Update
            lsra
            bne .n
            inca
.n          sta FXG_LEFT,u
            rts

; One bit a tick; the C rolls 4 chances of 1 in 2 per tick, which the pool could not hold.
ChargeHeavy_Update
            ldd FX_X,u
            std <arg0
            ldd FX_Y,u
            std <arg1
            jsr Random
            andb #15
            subb #8
            pshs b
            jsr Random
            andb #15
            subb #8
            puls a
            jsr fx_xy
            bsr ChargeBit_New
            dec FXG_LEFT,u
            lbeq fx_end
            rts

; ---- Contrail ------------------------------------------------------------------------------------
FXT_START   equ FX_DATA+0
FXT_PARENT  equ FX_DATA+0
FXT_RATE    equ 3               ; ticks between segments. The C's 1 a frame would fill the pool with one seeker.

; A=type, arg0=startTime, X, Y.
ContrailSegment_New
            jsr fx_open
            fdb ContrailSegment_Update
            ldd <arg0
            std FXT_START,u
            rts

; visible = int(2 * fmod(elapsed, period) / period - progress) >= 1 is true only at these ticks of the 30.
ContrailSegment_Update
            ldd <now
            subd FXT_START,u
            cmpd #30
            lbhs fx_end
            cmpb #3
            beq .show
            cmpb #4
            beq .show
            cmpb #9
            beq .show
            cmpb #14
            bne .out
.show       lda #COLOR_WHITE
            sta <draw_color
            ldd #312
            jmp fx_drawc
.out        rts

; A=type, B=offsetX, arg0=offsetY, arg1=owner entity. The C reads neither offset.
Contrail_New
            jsr fx_open
            fdb Contrail_Update
            ldd <arg1
            std FXT_PARENT,u
            rts

Contrail_Update
            ldx FXT_PARENT,u
            ldd E_VT,x
            lbeq fx_end
            lda E_FLAGS,x
            bita #EF_ACTIVE
            lbeq fx_end
            jsr fx_age
            cmpb #FXT_RATE-1
            blo .out
            clr FX_TIMER+1,u
            ldd <now
            std <arg0
            ldy E_Y,x
            ldx E_X,x
            lda #CONTRAIL_SEEKER
            bra ContrailSegment_New
.out        rts

; ---- Distortion, DistortionFadeIn: the C reads the screen, which this hardware cannot --------------
FXD_DUR     equ FX_DATA+0
FXD_SIZE    equ FX_DATA+1
FXD_DIR     equ FX_DATA+0

; B=radius: a white speck at random within it.
fx_speck    pshs b
            jsr Random
            lda ,s
            lsla
            mul
            suba ,s
            pshs a
            jsr Random
            lda 1,s
            lsla
            mul
            suba 1,s
            tfr a,b
            puls a
            jsr fx_xy
            leax -6,x
            leay -6,y
            leas 1,s
            lda #COLOR_WHITE
            sta <draw_color
            jsr Random
            andb #1
            clra
            addd #312
            jmp Draw_ColoredSprite

; A=type, B=size, arg0=offset (unused, as in the C), X, Y.
Distortion_New
            jsr fx_open
            fdb Distortion_Update
            stb FXD_SIZE,u
            ldb #60
            cmpa #DISTORTION_STATIC
            beq .n
            ldb #90
.n          stb FXD_DUR,u
            rts

Distortion_Update
            ldd #-102           ; 6 px/s, twice
            leax FX_Y,u
            jsr add_8_8
            ldb FXD_SIZE,u
            bsr fx_speck
            lda FX_TIMER+1,u
            adda #4
            sta FX_TIMER+1,u
            cmpa FXD_DUR,u
            lbhs fx_end
            rts

; A=direction, X, Y. 2 seconds; specks thin out going forward, thicken going backward.
DistortionFadeIn_New
            jsr fx_open
            fdb DistortionFadeIn_Update
            sta FXD_DIR,u
            rts

DistortionFadeIn_Update
            jsr fx_age
            cmpb #60
            lbhs fx_end
            lda FXD_DIR,u
            cmpa #DISTORTION_FADE_FORWARD
            bne .have
            negb
            addb #60
.have       pshs b
            jsr Random
            andb #63
            cmpb ,s+
            bhs .out
            ldb #18
            lbsr fx_speck
            ldb #18
            lbra fx_speck
.out        rts

; ---- Remains, TurretRemains ---------------------------------------------------------------------
FXR_START   equ FX_DATA+0
FXR_REST    equ FX_DATA+1
FXR_FLAGS   equ FX_DATA+2
FXR_LANDED  equ 1
FXR_STILL   equ 2
FXR_SENT    equ FX_DATA+3       ; its entry in the still layer, or 0

; Lets go of the still layer entry, if any. Keeps U.
fxr_release ldx FXR_SENT,u
            beq .out
            jsr Still_Release
            ldx #0
            stx FXR_SENT,u
.out        rts

; D=sprite. A resting decoration goes to the still layer once, and costs nothing per tick after that.
fxr_settle  ldx FXR_SENT,u
            bne .out
            lda still_rem       ; when its slots are full, do not search them on every remains on every tick
            cmpa #STILL_MAX-STILL_BANNER
            lda #0              ; the callers' A; it leaves the carry alone
            bhs .dyn
            ldx #still_list+STILL_BANNER*S_SIZE
            stx still_scan
            ldx #still_list+STILL_MAX*S_SIZE
            stx still_end
            ldx #0
            stx still_last
            clr still_full
            clr still_owner
            inc <still_mode
            pshs d
            bsr fxr_draw
            clr <still_mode
            puls d
            tst still_full
            bne .dyn
            ldx still_last
            stx FXR_SENT,u
.out        rts
.dyn        ; falls through

; D=sprite. As fx_draw, but art reaching the bottom of its cell goes a line higher: on the ground's line, every erase
; would take a piece of the ground with it.
fxr_draw    pshs d
            aslb
            rola
            aslb
            rola
            aslb
            rola
            addd #sprite_table
            tfr d,x
            ldb 3,x             ; height
            addb 5,x            ; + top of the art in the cell
            ldy FX_Y,u
            leay -6,y
            cmpb #12
            blo .ok
            leay -1,y
.ok         ldx FX_X,u
            leax -6,x
            puls d
            jmp Draw_SpriteAny

; Decorations live in a small pool here, not in a big list, so one that is far away and at rest gives up its slot.
; A spawn-table constructor that hands this record to the spawner as U (tfr x,u) gets it brought back when the camera
; returns: the spawner writes the object index at FX_OBJ. Otherwise it stays gone.
; A=sprite while falling, B=sprite at rest, X, Y.
Remains_New jsr fx_open
            fdb Remains_Update
            std FXR_START,u
            ldd #$FFFF
            std FX_OBJ,u
            rts

Remains_Rest rts                ; never called: Effect_UpdateAll knows this one
Remains_Update
            lda FXR_FLAGS,u
            bita #FXR_STILL
            beq .fall
            ; At rest it looks around now and then: how far it is from the view, and whether the floor has gone.
            inc FX_TIMER+1,u
            lda FX_TIMER+1,u
            anda #15
            bne .settled
            jsr fx_far
            bcs .near
            jsr fxr_release
            jmp fx_forget
.settled    ldx FXR_SENT,u      ; it is in the still layer: nothing to do, until it next looks around
            lbeq .draw
            ldx #Remains_Rest
            stx FX_UPDATE,u
            lda FX_TIMER+1,u    ; Effect_UpdateAll wakes it when this and the clock add up to a multiple of 16
            suba <now+1
            sta FX_TIMER+1,u
            rts
.near
.fall       ldd FX_Y,u
            addd #4
            std FX_Y,u
            tfr d,y
            leay 1,y
            ldx FX_X,u
            jsr Cell_At
            tsta
            bne .hit
            lda FXR_FLAGS,u
            anda #~FXR_STILL&$FF
            sta FXR_FLAGS,u
            jsr fxr_release
            bra .draw
.hit        pshs a
            ldd FX_Y,u
            addd #1
            jsr Div12
            jsr Times12
            pshs d
            subd #1
            std FX_Y,u
            lda FXR_FLAGS,u
            ora #FXR_LANDED+FXR_STILL
            sta FXR_FLAGS,u
            puls y
            puls a
            cmpa #LAVA
            bne .notlava
            jsr fxr_release
            ldx FX_X,u
            ldb #16
            jsr LavaSplash_New
            jmp fx_end
.notlava    cmpa #LAVA2
            beq .ended
            cmpa #GOAL
            bne .draw
.ended      jsr fxr_release
            jmp fx_end
.draw       ldb FXR_START,u
            lda FXR_FLAGS,u
            bita #FXR_LANDED
            beq .sprite
            ldb FXR_REST,u
            lda FXR_FLAGS,u
            bita #FXR_STILL
            bne .rest
            clra
            jmp fx_draw
.rest       clra
            jmp fxr_settle
.sprite     clra
            jmp fx_draw

; A=color, X, Y.
TurretRemains_New
            jsr fx_open
            fdb TurretRemains_Update
            ldb #155
            cmpa #COLOR_GREEN
            bne .n
            ldb #143
.n          stb FXR_START,u
            ldd #$FFFF
            std FX_OBJ,u
            rts

TurretRemains_Update
            inc FX_TIMER+1,u
            lda FX_TIMER+1,u
            anda #15
            bne .near
            jsr fx_far
            bcs .near
            jsr fxr_release
            jmp fx_forget
.near       ldb FXR_START,u
            clra
            jmp fxr_settle

; ---- NoDamage -----------------------------------------------------------------------------------
; arg0=speed, X, Y. The C's record draws nothing and never ends, so there is no record: returns X=0, Z clear.
NoDamage_New
            pshs y
            pshs x
            ldb <arg0
            pshs b
            jsr SmallFlash_New
            jsr Random
            andb #1
            incb
            pshs b
            ; 0,s count, 1,s speed sign, 2,s x, 4,s y
.next       lda #68
            jsr fx_rspan
            addd #136
            tst 1,s
            bmi .store
            coma
            comb
            addd #1
.store      std <arg0
            lda #136
            jsr fx_rspan
            std <arg1
            ldx 2,s
            ldy 4,s
            lda #BIT_GRAVITY_32
            ldb #COLOR_WHITE
            jsr BitColored_New
            dec ,s
            bne .next
            leas 6,s
            ldx #0
            andcc #$FB
            rts

; ---- GoalElevatorBit -----------------------------------------------------------------------------
; X, Y.
GoalElevatorBit_New
            jsr fx_open
            fdb GoalElevatorBit_Update
            jsr Random
            lda #7
            mul
            adda #3
            nega
            sta FXB_G,u
            rts

GoalElevatorBit_Update
            jsr fx_fly_y
            lda #COLOR_BLUE
            sta <draw_color
            ldd #312
            jsr fx_drawc
            jsr fx_age
            cmpb #120
            lbhs fx_end
            ldx FX_X,u
            ldy FX_Y,u
            jsr Cell_At
            cmpa #PLATFORM
            lbeq fx_end
            rts

; ---- ExplodingPlatformRespawn -----------------------------------------------------------------------
; X, Y.
ExplodingPlatformRespawn_New
            jsr fx_open
            fdb ExplodingPlatformRespawn_Update
            rts

ExplodingPlatformRespawn_Update
            jsr fx_age
            cmpb #8
            lbhs fx_end
            lda #205
            mul
            tsta
            beq .out
            ldb #COLOR_WHITE
            stb <draw_color
            tfr a,b
            pshs b
            lslb
            tfr b,a
            std <arg1
            puls b
            negb
            tfr b,a
            jmp fx_rect
.out        rts

; ---- Jiggle --------------------------------------------------------------------------------------
FXJ_PARENT  equ FX_DATA+0
FXJ_COUNT   equ FX_DATA+2
FXJ_ACC     equ FX_DATA+3

; arg0=target entity.
Jiggle_New  jsr fx_open
            fdb Jiggle_Update
            ldd <arg0
            std FXJ_PARENT,u
            lda #3
            sta FXJ_ACC,u
            rts

; The C steps every 6 updates: 2 steps every 3 ticks.
Jiggle_Update
            ldx FXJ_PARENT,u
            ldd E_VT,x
            lbeq fx_end
            lda FXJ_ACC,u
            adda #2
            cmpa #3
            blo .store
            suba #3
            sta FXJ_ACC,u
            inc FXJ_COUNT,u
            lda FXJ_COUNT,u
            lsra
            ldd #-1
            bcc .add
            ldd #1
.add        addd E_X,x
            std E_X,x
            lda FXJ_COUNT,u
            cmpa #20
            lbhs fx_end
            rts
.store      sta FXJ_ACC,u
            rts

; ---- SinkingEntity, SinkingEntity2 -----------------------------------------------------------------
FXK_S1      equ FX_DATA+0
FXK_S2      equ FX_DATA+2
FXK_BUBBLES equ FX_DATA+4
FXK_NEXT    equ FX_DATA+5
FXK_MAX_BITS equ 6

; Y = Math.round(y / 12 + 1) * 12, the lava surface.
fxk_surface ldd FX_Y,u
            addd #18
            jsr Div12
            jsr Times12
            tfr d,y
            rts

; arg0=sprite1, arg1=sprite2, A=size, X, Y.
SinkingEntity2_New
            clrb
            bra fxk_new
SinkingEntity_New
            ldb #1
fxk_new     jsr fx_open
            fdb SinkingEntity_Update
            stb FXK_BUBBLES,u
            pshs a
            ldd <arg0
            std FXK_S1,u
            ldd <arg1
            std FXK_S2,u
            ldd FX_X,u
            subd #6
            std FX_X,u
            ldd FX_Y,u
            subd #6
            std FX_Y,u
            ; Lava thrown up. The C's count is up to 1.25 * size, which is more than the whole pool.
            tst FXK_BUBBLES,u
            beq .done
            lda ,s
            ldb #6
            jsr fx_div
            stb ,s              ; speed = size / 6
            lda #FXK_MAX_BITS
            pshs a
.next       ldb 1,s
            tfr b,a
            pshs d
            bsr fxk_surface
            puls d
            ldx FX_X,u
            leax 6,x
            jsr fxlava_spray
            dec ,s
            bne .next
            leas 1,s
.done       leas 1,s
            rts

SinkingEntity_Update
            jsr fx_age
            cmpb #90
            lbhs fx_end
            pshs b
            ; Bubbles every 10 ticks.
            tst FXK_BUBBLES,u
            beq .nobub
            inc FXK_NEXT,u
            lda FXK_NEXT,u
            cmpa #10
            blo .nobub
            clr FXK_NEXT,u
            bsr fxk_surface
            jsr Random
            lda #6
            mul
            tfr a,b
            addb #3
            clra
            addd FX_X,u
            tfr d,x
            jsr Random
            andb #1
            addb #2
            tfr b,a
            jsr LavaBubble_New
.nobub      ldb ,s
            lda #34
            mul
            tfr a,b             ; progress * 12
            clra
            addd FX_Y,u
            tfr d,y
            ldb ,s
            lsrb
            andb #1
            clra
            addd FX_X,u
            tfr d,x
            ; The sprite flips every 4 ticks.
            puls b
            andb #4
            bne .second
            ldd FXK_S1,u
            jmp Draw_Sprite
.second     ldd FXK_S2,u
            jmp Draw_Sprite

; ---- RespawnActivation, RespawnLocator ---------------------------------------------------------------
; X, Y.
RespawnActivation_New
            jsr fx_open
            fdb RespawnActivation_Update
            rts

; Solid rectangles erase to black, so a frame crossing terrain leaves marks. When it ends, clearing terrain_on has
; Present draw the terrain again.
RespawnActivation_Update
            jsr fx_age
            cmpb #10
            blo .ok
            jsr fx_end
            inc <terrain_dirty
            ldb #9
.ok         lsrb
            addb #4
            pshs b              ; half size
            lda #COLOR_WHITE
            sta <draw_color
            lda #1
            ldb ,s
            decb
            std <arg1           ; corners: 1 by size - 1
            lda ,s
            ldb ,s
            negb
            jsr fx_rect
            lda ,s
            nega
            ldb ,s
            negb
            jsr fx_rect
            ldb ,s
            decb
            tfr b,a
            ldb #1
            std <arg1
            lda ,s
            nega
            ldb ,s
            negb
            jsr fx_rect
            lda #2
            ldb ,s
            negb
            jsr fx_rect
            lda ,s
            lsla
            ldb #1
            std <arg1
            lda ,s
            nega
            ldb ,s
            leas 1,s
            jmp fx_rect

; X, Y.
RespawnLocator_New
            jsr fx_open
            fdb RespawnLocator_Update
            rts

; Shrinks onto the man. The whole frame can be wider than a rectangle can be, so the top and bottom are two halves.
RespawnLocator_Update
            ldd <man_x
            std FX_X,u
            ldd <man_y
            std FX_Y,u
            jsr fx_age
            cmpb #19
            blo .ok
            jsr fx_end
            inc <terrain_dirty
            ldb #18
.ok         negb
            addb #19
            lda #10
            mul                 ; B=half width
            pshs b
            lda #144
            mul
            pshs a              ; half height
            ldb ,s
            clra
            addd FX_Y,u
            pshs d              ; bottom
            ldd FX_Y,u
            subb 2,s
            sbca #0
            pshs d              ; top
            ldb 5,s
            clra
            addd FX_X,u
            pshs d              ; right
            ldd FX_X,u
            subb 7,s
            sbca #0
            pshs d              ; left
            ; 0,s left, 2,s right, 4,s top, 6,s bottom, 8,s height, 9,s half width
            asl 8,s
            lda #COLOR_WHITE
            sta <draw_color
            ldx 2,s
            ldy 4,s
            lda #1
            ldb 8,s
            jsr Draw_RectWorld
            ldx ,s
            ldy 4,s
            lda #1
            ldb 8,s
            jsr Draw_RectWorld
            ldx ,s
            ldy 4,s
            lda 9,s
            ldb #1
            jsr Draw_RectWorld
            ldx FX_X,u
            ldy 4,s
            lda 9,s
            ldb #1
            jsr Draw_RectWorld
            ldx ,s
            ldy 6,s
            lda 9,s
            ldb #1
            jsr Draw_RectWorld
            ldx FX_X,u
            ldy 6,s
            lda 9,s
            ldb #1
            leas 10,s
            jmp Draw_RectWorld

; ---- WizardDeathEffect ---------------------------------------------------------------------------
; X, Y. The C makes a circle a frame, each up to 4 sprites; here one every 3 ticks.
WizardDeathEffect_New
            jsr fx_open
            fdb WizardDeathEffect_Update
            rts
WizardDeathEffect_Update
            jsr fx_age
            cmpb #90
            lbhi fx_end
            inc FXE_COUNT,u
            lda FXE_COUNT,u
            cmpa #3
            blo .out
            clr FXE_COUNT,u
            negb
            addb #90            ; ticks remaining
            pshs b
            lda #91
            mul                 ; A=spread = 32 * remaining
            pshs a
            lsla
            sta <arg0           ; spread * 2
            jsr Random
            lda <arg0
            mul
            suba ,s
            pshs a
            jsr Random
            lda <arg0
            mul
            suba 1,s
            tfr a,b
            puls a
            jsr fx_xy
            leas 1,s
            puls b
            lda #34
            mul                 ; A=size = 12 * remaining
            tsta
            beq .out
            jmp CircleLarge_New
.out        rts

; ---- ScoreText -----------------------------------------------------------------------------------
FXS_DIG     equ FX_DATA+0       ; digits of the units; the C's two more zeros are implied
FXS_N       equ FX_DATA+3
FXS_LEN     equ FX_DATA+4
FXS_DELAY   equ FX_DATA+5
FXS_Y0      equ FX_DATA+6
; ceil(10 * (1 - (2 * t / duration - 1)^2)) at each timer value / 4
fxs_rise    fcb 0,2,3,4,5,6,7,8,8,9,9,10,10,10,10

; B=score units, X, Y. One unit is 100 points.
ScoreText_New
            jsr fx_open
            fdb ScoreText_Update
            pshs b
            leax FXS_DIG,u
            lda #-1
.h          inca
            subb #100
            bcc .h
            addb #100
            tsta
            beq .noh
            sta ,x+
.noh        lda #-1
.t          inca
            subb #10
            bcc .t
            addb #10
            tsta
            bne .tens
            pshs b
            ldb 1,s
            cmpb #100
            puls b
            blo .ones
.tens       sta ,x+
.ones       stb ,x+
            tfr x,d
            pshs u
            subd ,s++
            subb #FXS_DIG
            stb FXS_N,u
            lda ,s+
            beq .zero
            addb #2
.zero       stb FXS_LEN,u
            incb
            aslb
            clra
            pshs d
            ldd FX_X,u
            subd ,s++
            std FX_X,u
            ldd FX_Y,u
            subd #2
            std FX_Y,u
            std FXS_Y0,u
            inc FXS_DELAY,u
            rts

ScoreText_Update
            lda FX_TIMER+1,u
            tst FXS_DELAY,u
            beq .show
            cmpa #40
            blo .tick
            clr FXS_DELAY,u
            clr FX_TIMER+1,u
            bra .tick
.show       ldb #10
            cmpa #60
            bhs .y
            lsra
            lsra
            ldx #fxs_rise
            ldb a,x
.y          clra
            pshs d
            ldd FXS_Y0,u
            subd ,s++
            std FX_Y,u
            clra
            pshs a
.digit      lda ,s
            cmpa FXS_LEN,u
            bhs .drawn
            clrb
            cmpa FXS_N,u
            bhs .glyph
            leax FXS_DIG,u
            ldb a,x
.glyph      clra
            addd #FONT1_BASE
            pshs d
            ldb 2,s
            lslb
            lslb
            clra
            addd FX_X,u
            tfr d,x
            ldy FX_Y,u
            puls d
            jsr Draw_Sprite
            inc ,s
            bra .digit
.drawn      leas 1,s
.tick       lda FX_TIMER+1,u
            adda #4
            sta FX_TIMER+1,u
            cmpa #119
            lbhs fx_end
            rts

; ---- MessageBanner -------------------------------------------------------------------------------
; A banner is an effect record. Text stays in bank 10 and is wrapped as it is drawn. The glyphs must be drawn every tick
; and in a stable order, or Present would erase them, so the cap works as a window on whole lines: it scrolls while typing,
; and once typed, pages through a long text every 2 seconds. Untriggered banners far away go back to the object list.
BAN_TEXT    equ FX_DATA+0       ; first glyph; 0 = not triggered
BAN_LEN     equ FX_DATA+2
BAN_POS     equ FX_DATA+4       ; amountTyped
BAN_WIN     equ FX_DATA+6       ; first glyph shown, always a line start
BAN_W       equ FX_DATA+8       ; characters per line
BAN_COLOR   equ FX_DATA+9
BAN_FLAGS   equ FX_DATA+12      ; FX_DATA+10 is FX_OBJ
BAN_CURT    equ FX_DATA+13
BF_DONE     equ 1
BF_BLINK    equ 2
BF_NOSLOT   equ 4               ; the still layer had no room for this page
BF_SLOT     equ $F0             ; retained: banner slot + 1. Its glyphs are in the still layer
BAN_WORD    equ FX_TIMER        ; which word of the text starts the page; the low byte times the page
BAN_MAX_GLYPHS equ 48
BAN_PAGE_T  equ 60
; Corner distance from the camera beyond which nothing of it can be seen: half view + the view's 40-line dead zone + size.
BAN_LEFT    equ 260
BAN_RIGHT   equ 150
BAN_UP      equ 240
BAN_DOWN    equ 170
; (cells * 12 - 10) / 5 for 0 to BANNER_MAX_WIDTH cells
ban_widths  fcb 0,0,2,5,7,10,12,14,17,19,22

; X=cell x, B=cell y, A=text color. Spawn-table constructor: leaves U=record, or 0.
MessageBanner_Spawn
            pshs x
            pshs d              ; 0,s color, 1,s cell y, 2,s cell x
            ldy #0
.scan       tfr y,d
            addd 2,s
            tfr d,x
            ldb 1,s
            jsr Main_GetCell
            tsta
            bne .found
            leay 1,y
            cmpy #10
            blo .scan
.found      tfr y,d
            ldx #ban_widths
            ldb b,x
            pshs b              ; 0,s width, 1,s color, 2,s cell y, 3,s cell x
            ldb 2,s
            clra
            jsr Times12
            tfr d,y
            ldd 3,s
            jsr Times12
            ldx #MessageBanner_Update
            jsr Effect_Alloc
            beq .full
            puls d
            sta BAN_W,u
            stb BAN_COLOR,u
            leas 3,s
            rts
.full       ldu #0
            leas 5,s
            rts

MessageBanner_Update
            ldd BAN_TEXT,u
            bne .live
            jsr fx_far
            lbcc fx_forget
            rts
.live       lda BAN_FLAGS,u
            bita #BF_DONE
            bne .typed
            ldd BAN_POS,u
            addd #1
            std BAN_POS,u
            cmpd BAN_LEN,u
            blo .sound
            lda BAN_FLAGS,u
            ora #BF_DONE
            sta BAN_FLAGS,u
.sound      lda #SND_GUI_01
            jsr Sound_Play
            ; A banner extends right and down from its corner, and the view is wider than tall, so the box is lopsided.
.typed      ldd FX_X,u
            subd <cam_x
            addd #BAN_LEFT
            cmpd #BAN_LEFT+BAN_RIGHT
            bhs .far
            ldd FX_Y,u
            subd <cam_y
            addd #BAN_UP
            cmpd #BAN_UP+BAN_DOWN
            blo .near
.far        jmp ban_unretain
.near       lda BAN_COLOR,u
            sta <draw_color
            ; Typed text does not change, so glyphs go to the still layer once. Each tick the glyph loop resumes from where
            ; it stopped, which leaves it only the new glyphs, if any, and then the cursor and timers.
            lda BAN_FLAGS,u
            bita #BF_DONE
            beq .slow
            anda #BF_SLOT
            beq .slow
            lsra
            lsra
            lsra
            lsra
            jsr ban_slot_ptr
            ldd BAN_TEXT,u
            addd BAN_LEN,u
            cmpd 6,x
            bhi .slow           ; there is more to place
            leas -16,s
            ldd ,x
            std ,s
            ldd 2,x
            std 2,s
            ldd 4,x
            std 4,s
            ldd 10,x
            std 12,s
            lbra .notnew
.slow       lda BAN_FLAGS,u
            bita #BF_SLOT
            bne .build
            bita #BF_NOSLOT
            bne .build
            ; Try to retain it.
            lda #1
            ldb ban_used
.find       bitb #1
            beq .free
            lsrb
            inca
            cmpa #BAN_SLOTS
            bls .find
            bra .build
.free       ldx #still_list
            stx still_scan
            ldx #still_list+STILL_BANNER*S_SIZE
            stx still_end
            sta still_owner
            asl still_owner
            asl still_owner
            asl still_owner
            asl still_owner
            clr still_full
            inc <still_mode
            ; Typed words are shown as one image each, kept in the still layer: a screen of text is a few blits, not dozens.
            ; Only the word being typed is drawn a letter at a time, through the display list. The layout is done here, so
            ; that text wraps at the width each banner asks for.
.build      ldd #0
            pshs d              ; 14,s word still being typed; 15,s letters in this word
            lda BAN_WORD,u
            clrb
            pshs d              ; 12,s this word's number; 13,s the number of the first word of the next line
            ldd BAN_TEXT,u
            addd BAN_LEN,u
            pshs d              ; end of the text
            ldd BAN_POS,u
            cmpd BAN_LEN,u
            bls .min
            ldd BAN_LEN,u
.min        addd BAN_TEXT,u
            pshs d              ; end of what is typed
            ldd BAN_WIN,u
            pshs d              ; read pointer
            ldd #0
            pshs d              ; start of the second line shown
            lda #BAN_MAX_GLYPHS
            clrb
            pshs d              ; glyphs left, clipped
            ldd #0
            pshs d              ; column, row
            ; 0,s col, 1,s row, 2,s left, 3,s clipped, 4,s next line, 6,s read, 8,s typed end, 10,s text end
            lda BAN_FLAGS,u
            anda #BF_SLOT
            beq .fresh
            sta still_owner
            clr still_full
            inc <still_mode
            lsra
            lsra
            lsra
            lsra
            jsr ban_slot_ptr
            ldd ,x
            std ,s
            ldd 2,x
            std 2,s
            ldd 4,x
            std 4,s
            ldd 6,x
            std 6,s
            ldd 8,x
            std still_scan
            ldd 10,x
            std 12,s
            ldd #still_list+STILL_BANNER*S_SIZE
            std still_end
.fresh      lda #10
            sta BANK_SELECT
.loop       ldy 6,s
            cmpy 8,s
            lbhs .end
            ldb ,y
            cmpb #44
            lbeq .sep_nl
            cmpb #43
            lbeq .sep_sp
            ; A word starts here. How long is it?
            tfr y,x
            clrb
.len        cmpx 10,s
            bhs .lend
            lda ,x
            cmpa #43
            beq .lend
            cmpa #44
            beq .lend
            leax 1,x
            incb
            bra .len
.lend       stb 15,s
            tst <still_mode
            lbeq .letters
            cmpx 8,s
            lbhi .typing
            ; All of it typed: one image.
            lda 2,s
            cmpa 15,s
            lblo .clip
            suba 15,s
            sta 2,s
            stx 6,s
            ldb 12,s
            inc 12,s
            lda #3
            mul
            addd BAN_TEXT,u
            addd BAN_LEN,u
            tfr d,x
            if VERT
            ; Turned: the image is in pieces of VB_PIECE lines, end to end. Its rows are the last columns of the canvas.
            ldd ,x
            anda #$3F
            std word_row
            ldd #3*256+VROT_W-5 ; 5 rows: 3 bytes
            tst ,x
            bpl .vw
            ldd #4*256+VROT_W-6
.vw         sta word_row+2
            stb word_row+4
            clr word_row+5
            lda 2,x
            sta vb_left
            else
            ldd ,x
            anda #$3F
            std word_row
            lda 2,x
            ldb #5              ; lines
            tst ,x
            bpl .lines
            incb
.lines      std word_row+2
            clr word_row+4
            clr word_row+5
            endif
            lda ,s
            ldb #5
            mul
            addd FX_X,u
            addd #4
            tfr d,x
            lda 1,s
            ldb #7
            mul
            addd FX_Y,u
            addd #5
            tfr d,y
            lda <draw_color
            beq .plain
            ldb #$11
            mul
            stb <t5+1
            lda #BC_SOLID
            sta <t5
            bra .tinted
.plain      clr <t5
            clr <t5+1
.tinted
            if VERT
            ldd #0
            std vb_first
.piece      lda vb_left
            cmpa #VB_PIECE
            bls .plast
            lda #VB_PIECE
.plast      sta word_row+3
            ldd #0
            std still_last      ; so that no room means no word to draw again
            pshs x,y
            ldd <t5             ; still_add adds the shift to it
            pshs d
            VSWAP
            bsr .keep
            puls d
            std <t5
            puls x,y
            ldd still_last
            beq .nokept         ; no room: the banner goes back to letters
            ldd vb_first
            bne .pnext
            ldd still_last
            std vb_first
.pnext      lda word_row+2      ; the next piece
            ldb #VB_PIECE
            mul
            addd word_row
            std word_row
            leax VB_PIECE,x
            lda vb_left
            suba #VB_PIECE
            sta vb_left
            bhi .piece
            ldd vb_first
            std ban_fresh
            ldd still_last
            std ban_fresh_e
            else
            ldd #0
            std still_last      ; so that no room means no word to draw again
            bsr .keep
            ldx still_last
            beq .nokept
            stx ban_fresh
            endif
.nokept     lda 15,s
            adda ,s
            sta ,s
            lbra .loop
.keep       pshs u              ; still_add returns through this
            ldu #word_row
            jmp still_add
            ; The word being typed. What came before goes in the slot first, so next tick starts from this word.
.typing     lda #1
            sta 14,s
            lbra .retain
.letters    inc 12,s
.letter     ldy 6,s
            cmpy 8,s
            lbhs .end
            tst 15,s
            lbeq .loop
            dec 15,s
            ldb ,y+
            sty 6,s
            tst 2,s
            beq .clip
            dec 2,s
            pshs b
            lda 1,s
            ldb #5
            mul
            addd FX_X,u
            addd #4
            tfr d,x
            lda 2,s
            ldb #7
            mul
            addd FX_Y,u
            addd #5
            tfr d,y
            puls b
            jsr Draw_Glyph
            inc ,s
            bra .letter
            ; A space: does the next word still fit? This gives the C's FindLineBreaks without changing the text.
.sep_sp     leay 1,y
            sty 6,s
            tfr y,x
            ldb ,s
            incb
.look       cmpx 10,s
            bhs .looked
            lda ,x+
            cmpa #43
            beq .looked
            cmpa #44
            beq .looked
            incb
            bra .look
.looked     cmpb BAN_W,u
            bhi .newline
            inc ,s
            lbra .loop
.sep_nl     leay 1,y
            sty 6,s
.newline    clr ,s
            inc 1,s
            ldd 4,s
            lbne .loop
            sty 4,s
            lda 12,s
            sta 13,s
            lbra .loop
.clip       inc 3,s
.end        tst <still_mode
            beq .endb
.retain     lda <cur_bank
            sta BANK_SELECT
            ; The words just went to the still layer.
            clr <still_mode
            lda BAN_FLAGS,u
            bita #BF_SLOT
            bne .marked
            ora still_owner
            sta BAN_FLAGS,u
            lda still_owner
            lsra
            lsra
            lsra
            lsra
            jsr ban_slot_bit
            ora ban_used
            sta ban_used
.marked     tst still_full
            bne .nofit
            lda still_owner
            lsra
            lsra
            lsra
            lsra
            jsr ban_slot_ptr
            ldd ,s
            std ,x
            ldd 2,s
            std 2,x
            ldd 4,s
            std 4,x
            ldd 6,s
            std 6,x
            ldd still_scan
            std 8,x
            ldd 12,s
            std 10,x
            bra .kept
.nofit      jsr ban_unretain
            lda BAN_FLAGS,u
            ora #BF_NOSLOT
            sta BAN_FLAGS,u
.kept       tst 14,s
            beq .notnew
            clr 14,s
            lda #10
            sta BANK_SELECT
            lbra .loop
.endb       lda <cur_bank
            sta BANK_SELECT
.notnew
            ; The cursor goes last, and blinks in black: this keeps later display list entries in place.
            tst 3,s
            bne .window
            lda BAN_FLAGS,u
            bita #BF_DONE
            beq .cursor
            lda <now+1
            suba BAN_CURT,u
            cmpa #3
            bls .cursor
            lda <now+1
            sta BAN_CURT,u
            lda BAN_FLAGS,u
            eora #BF_BLINK
            sta BAN_FLAGS,u
.cursor     lda BAN_FLAGS,u
            bita #BF_BLINK
            bne .on
            clr <draw_color
.on         lda ,s
            ldb #5
            mul
            addd FX_X,u
            addd #5
            tfr d,x
            lda 1,s
            ldb #7
            mul
            addd FX_Y,u
            addd #4
            tfr d,y
            lda #5
            ldb #6
            jsr Draw_RectWorld
.window     lda BAN_FLAGS,u
            bita #BF_DONE
            bne .paging
            tst 3,s
            bne .advance
            bra .out
.paging     inc FX_TIMER+1,u
            lda FX_TIMER+1,u
            cmpa #BAN_PAGE_T
            blo .out
            clr FX_TIMER+1,u
            tst 3,s
            bne .advance
            ; One page: nothing changes when it restarts at the same line.
            ldd BAN_WIN,u
            cmpd BAN_TEXT,u
            beq .out
            ldd BAN_TEXT,u
            std BAN_WIN,u
            clr BAN_WORD,u
            jsr ban_unretain
            bra .out
.advance    ldd 4,s
            beq .out
            std BAN_WIN,u
            lda 13,s
            sta BAN_WORD,u
            jsr ban_unretain
            bra .out
.out        leas 16,s
            rts

; A=slot number, 1 up. Returns X=its data. Keeps U.
ban_slot_ptr
            deca
            ldb #12
            mul
            addd #ban_slot_data
            tfr d,x
            rts
; A=slot number, 1 up. Returns A=its bit in ban_used.
ban_slot_bit
            tfr a,b
            lda #1
.sh         decb
            beq .out
            asla
            bra .sh
.out        rts

; The banner's text or page is changing: its glyphs leave the still layer, and it may try again.
ban_unretain
            lda BAN_FLAGS,u
            anda #BF_SLOT
            bne .slot
            lda BAN_FLAGS,u
            anda #~BF_NOSLOT&$FF
            sta BAN_FLAGS,u
            rts
.slot       lsra
            lsra
            lsra
            lsra
            pshs a
            jsr ban_slot_bit
            coma
            anda ban_used
            sta ban_used
            puls a
            jsr Still_ReleaseOwner
            lda BAN_FLAGS,u
            anda #~(BF_SLOT+BF_NOSLOT)&$FF
            sta BAN_FLAGS,u
            rts

; arg0=pointer to the text in bank 10, its first word the length. X, Y=the trigger's position.
; Nearest by |dx| + |dy|, which picks the same banner as the C's distance for every trigger in the 9 levels.
MessageBanner_TriggerNearestBanner
            pshs u
            pshs y
            pshs x
            ldd #0
            pshs d              ; first banner
            pshs d              ; nearest untriggered
            ldd #$FFFF
            pshs d              ; its distance
            lda #EFFECT_COUNT
            pshs a
            ; 0,s count, 1,s best, 3,s nearest, 5,s first, 7,s x, 9,s y, 11,s caller's U
            ldu #effect_pool
.next       ldd FX_UPDATE,u
            cmpd #MessageBanner_Update
            bne .skip
            ldd 5,s
            bne .first
            stu 5,s
.first      ldd BAN_TEXT,u
            bne .skip
            ldd FX_X,u
            subd 7,s
            jsr Abs_D
            pshs d
            ldd FX_Y,u
            subd 11,s
            jsr Abs_D
            addd ,s++
            cmpd 1,s
            bhs .skip
            std 1,s
            stu 3,s
.skip       leau EFFECT_SIZE,u
            dec ,s
            bne .next
            ; With every banner in use, the C writes on the first one.
            ldu 3,s
            bne .go
            ldu 5,s
            beq .out
.go         jsr ban_unretain
            lda #10
            sta BANK_SELECT
            ldx <arg0
            ldd ,x++
            std BAN_LEN,u
            stx BAN_TEXT,u
            stx BAN_WIN,u
            lda <cur_bank
            sta BANK_SELECT
            ldd #0
            std BAN_POS,u
            std FX_TIMER,u
            lda #BF_BLINK
            sta BAN_FLAGS,u
.out        leas 11,s
            puls u,pc

MessageBanner_ClearBanners
            ldx #fx_end
            bra ban_each
MessageBanner_ResetBanners
            ldx #ban_reset
ban_each    pshs u
            pshs x
            lda #EFFECT_COUNT
            pshs a
            ldu #effect_pool
.next       ldd FX_UPDATE,u
            cmpd #MessageBanner_Update
            bne .skip
            jsr [1,s]
.skip       leau EFFECT_SIZE,u
            dec ,s
            bne .next
            leas 3,s
            puls u,pc
ban_reset   jsr ban_unretain
            ldd #0
            std BAN_TEXT,u
            rts

; Nothing makes these: the title screen draws its own stars. The vertical build leaves them out, for the room.
            if VERT==0
; ---- RectangularGUIFlash -------------------------------------------------------------------------
FXU_W       equ FX_DATA+0
FXU_H       equ FX_DATA+1

; X, Y in screen pixels, A=w, B=h. w + 8 must fit a rectangle's width, under 255.
RectangularGUIFlash_New
            leax -2,x
            leay -2,y
            jsr fx_s2w
            jsr fx_open
            fdb RectangularGUIFlash_Update
            adda #4
            addb #4
            std FXU_W,u
            rts

RectangularGUIFlash_Update
            jsr fx_age
            cmpb #10
            lbhi fx_end
            lda #COLOR_WHITE
            sta <draw_color
            pshs b
            cmpb #3
            bhs .frame
            ldx FX_X,u
            leax -2,x
            ldy FX_Y,u
            leay -2,y
            ldd FXU_W,u
            adda #4
            addb #4
            jsr Draw_RectWorld
            ; (1 - progress) * height / 2
.frame      puls b
            negb
            addb #10
            lda #13
            mul
            lda FXU_H,u
            mul
            sta <arg0           ; thickness
            beq .out
            ldx FX_X,u
            ldb FXU_W,u
            subb <arg0
            abx
            ldy FX_Y,u
            lda <arg0
            ldb FXU_H,u
            jsr Draw_RectWorld
            ldx FX_X,u
            ldy FX_Y,u
            lda FXU_W,u
            ldb <arg0
            jsr Draw_RectWorld
            ldx FX_X,u
            ldy FX_Y,u
            lda <arg0
            ldb FXU_H,u
            jsr Draw_RectWorld
            ldb FXU_H,u
            subb <arg0
            clra
            addd FX_Y,u
            tfr d,y
            ldx FX_X,u
            lda FXU_W,u
            ldb <arg0
            jmp Draw_RectWorld
.out        rts

; ---- the title screen ----------------------------------------------------------------------------
FXZ_SIZE    equ FXB_G
FXZ_NEXT    equ FX_DATA+0

; Loads draw_color with the star color.
fxz_color   lda Star_color
            bne .have
            lda #COLOR_WHITE
.have       sta <draw_color
            rts

; arg0=speedX, arg1=speedY, X, Y in screen pixels. The C's bounds are its 192 pixel screen; this one is 292.
Star_New    jsr fx_open
            fdb Star_Update
            jsr fx_speeds
            ldd FXB_VX,u
            jsr Abs_D
            tfr a,b
            lsrb
            lsrb
            pshs b
            adda ,s+            ; |speed| / 24 in px/s
            bne .n
            inca
.n          sta FXZ_SIZE,u
            rts

Star_Update ldd FXB_VX,u
            leax FX_X,u
            jsr add_8_8
            ldd FXB_VY,u
            leax FX_Y,u
            jsr add_8_8
            bsr fxz_color
            ldx FX_X,u
            ldy FX_Y,u
            jsr fx_s2w
            lda FXZ_SIZE,u
            ldb #1
            jsr Draw_RectWorld
            ldd FX_X,u
            lbmi fx_end
            cmpd #GVIEW_W
            lbgt fx_end
            rts

; X, Y in screen pixels.
TitleExplosion_New
            jsr fx_s2w
            jsr fx_open
            fdb TitleExplosion_Update
            jsr Random
            lda #12
            mul
            inca
            sta FXZ_SIZE,u
            rts

TitleExplosion_Update
            jsr fx_age
            cmpb #15
            lbhi fx_end
            cmpb #8
            blo .grow
            negb
            addb #15
.grow       lda FXZ_SIZE,u
            mul
            lda #17
            mul                 ; A = size * progress / 2
            pshs a
            bsr fxz_color
            ldb ,s
            lslb
            incb
            pshs b
            lda #1
            std <arg1
            clra
            ldb 1,s
            negb
            jsr fx_rect
            puls a
            ldb #1
            std <arg1
            puls a
            nega
            clrb
            jmp fx_rect

; dx, dy from the flash's center, then the glyph: STAR GUARD at the C's positions.
fxz_title   fcb -24,9,18,-19,9,19,-14,9,0,-9,9,17
            fcb 4,9,6,9,9,20,14,9,0,19,9,17,24,9,3,$7F
fxz_logo    fcb -12,-12,0,-12,-12,0,0,0,$7F

; The center of the screen. The white-out is the palette, a screenful of blits being more than a tick has.
TitleFlash_New
            ldx #144
            ldy #113
            jsr fx_s2w
            jsr fx_open
            fdb TitleFlash_Update
            lda #15
            sta FXZ_NEXT,u
            rts

; B=half length: the flare, as its two center lines.
fxz_cross   tstb
            beq .out
            pshs b
            tfr b,a
            ldb #1
            std <arg1
            lda ,s
            nega
            clrb
            jsr fx_rect
            ldd #0
            jsr fx_rect
            lda #1
            ldb ,s
            std <arg1
            clra
            ldb ,s
            negb
            jsr fx_rect
            ldd #0
            jsr fx_rect
            leas 1,s
.out        rts

; B=radius: the ellipse, as a cross of two rectangles.
fxz_blob    tstb
            beq .out
            pshs b
            lda ,s
            lsla
            std <arg1
            lda ,s
            nega
            lsrb
            negb
            jsr fx_rect
            lda ,s
            ldb ,s
            lslb
            std <arg1
            lda ,s
            lsra
            nega
            ldb ,s
            negb
            jsr fx_rect
            leas 1,s
.out        rts

TitleFlash_Update
            ldb FX_TIMER+1,u
            cmpb #40
            bhs .timed
            inc FX_TIMER+1,u
.timed      lda #COLOR_WHITE
            sta <draw_color
            cmpb #8
            bhs .white
            ; Growing. The lines are capped at what fx_rect can reach, past the edge of most of the screen.
            pshs b
            lda #27
            mul
            cmpb #120
            bls .glen
            ldb #120
.glen       bsr fxz_cross
            puls b
            lda #13
            mul
            cmpb #60
            bls .grad
            ldb #60
.grad       bsr fxz_blob
            lbra .boom
.white      cmpb #11
            bhs .after
            cmpb #8
            lbne .boom
            ldx #PALETTE
            lda #$FF
            ldb #16
.w          sta ,x+
            decb
            bne .w
            bra .boom
.after      bne .noreset
            ldx #hw_palette
            ldy #PALETTE
            ldb #16
.r          lda ,x+
            sta ,y+
            decb
            bne .r
.noreset    ldb FX_TIMER+1,u
            decb
            cmpb #31
            bhs .text
            ; Fading.
            pshs b
            negb
            addb #31
            pshs b
            lslb
            lslb
            cmpb #12
            bhs .flen
            ldb #12
.flen       lbsr fxz_cross
            puls b
            addb #3
            cmpb #8
            bhs .frad
            ldb #8
.frad       lda ,s+
            lsra
            bcc .text
            lbsr fxz_blob
.text       clr <draw_color
            ldy #fxz_title
.glyph      lda ,y+
            cmpa #$7F
            beq .logo
            ldb ,y+
            pshs y
            jsr fx_xy
            ldb [,s]
            jsr Draw_Glyph
            puls y
            leay 1,y
            bra .glyph
.logo       ldd #fxz_logo
            std <arg1
            ldx FX_X,u
            leax 1,x
            ldy FX_Y,u
            leay 1,y
            ldd #248
            jsr fx_quad
.boom       dec FXZ_NEXT,u
            bne .out
            jsr Random
            lda #15
            mul
            inca
            sta FXZ_NEXT,u
            jsr Random
            lda #146
            mul
            tfr a,b
            clra
            aslb
            rola
            tfr d,x
            jsr Random
            lda #240
            mul
            tfr a,b
            clra
            tfr d,y
            jmp TitleExplosion_New
.out        rts
            endif
