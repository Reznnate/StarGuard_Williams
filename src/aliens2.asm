; aliens/*.as, second part: Hulk, TrooperHeavy, Zomboid. Ported from ../port/src/aliens2.c. Bank 13.
; The cell helpers, macros and scratch names are defined in aliens.asm; this bank has its own copy with prefix AL2.
            bank 10
            org aliens_end
            AL_HELPERS AL2

; ---- Hulk.as ----------------------------------------------------------------------------------
HUK_PAUSET  equ E_DATA+0
HUK_DIST    equ E_DATA+2        ; runDistance
HUK_RUNW    equ E_DATA+3        ; AS_Int(runWaitTime): it falls 3.0, 2.85, ..., so 3 once and then 2
HUK_WAIT    equ E_DATA+4        ; signed, the C's 60 Hz frames, less 2 per tick
HUK_SX      equ E_DATA+5
HUK_SY      equ E_DATA+6
HUK_STATE   equ E_DATA+7
HUK_HEAD    equ E_DATA+8
HUK_RUNF    equ E_DATA+9
HUK_FRAME   equ E_DATA+10
            assert E_DATA+11<=ENT_SIZE,"hulk record"
; The C's state numbers.
HUKS_KILL   equ 0
HUKS_PAUSE  equ 1
HUKS_JUMP   equ 2
HUKS_PACE   equ 3
HUKS_SUSP   equ 4
HUK_START   equ 108
HUK_RUN_DIST equ 36
HUK_MAX_WAIT equ 3
HUK_JUMP_WAIT equ 2
HUK_PACE_DIST equ 8
HUK_PACE_WAIT equ 10
HUK_PAUSE_T equ 23              ; 750 ms
HUK_SUSP_T  equ 5               ; 166 ms

Hulk_vt     fdb Hulk_Update,Hulk_Hurt,0,Hulk_DeathEffect,Hulk_HitEffect

Hulk_New    pshs b,x
            ALIEN_ALLOC Hulk_vt
            beq .full
            puls b,x
            jsr AL2_InitCentered
            lda #HUKS_SUSP
            sta HUK_STATE,u
            ldd <now
            std HUK_PAUSET,u
            lda #-1
            sta HUK_HEAD,u
            ldd #72
            std E_SPRITE,u
            ldd #384
            std E_HEALTH,u
            lda #15
            sta E_SCORE,u
            ldd #6*256+6
            std E_SIZEX,u
            jmp Main_AddToKillCount
.full       puls b,x,pc

Hulk_DeathEffect
            lda #SND_EXPLOSION
            jsr Sound_Play
            ldd E_SPRITE,u
            std <arg0
            ldx E_X,u
            ldy E_Y,u
            jsr DeathFlash_New
            FX_COUNT CircleLarge_New,7
            lda #3
.loop       pshs a
            jsr Random
            lda #6
            mul
            tfr a,b
            clra
            addd E_X,u
            subd #6
            pshs d
            jsr Random
            lda #6
            mul
            tfr a,b
            clra
            addd E_Y,u
            subd #6
            tfr d,y
            puls x
            ldd #16*257
            jsr Explosion_New
            puls a
            deca
            bne .loop
            rts

Hulk_HitEffect
            lda #SND_HIT_LOW
            jsr Sound_Play
            ldd #1*257
            ldx <hit_x
            ldy <hit_y
            jsr Explosion_New
            lda E_FLAGS,u
            ora #EF_FLASHING
            sta E_FLAGS,u
            ldb <now+1
            stb E_FLASHT,u
            rts

; U=entity, A=state. Far-callable.
Hulk_SwitchState
            sta HUK_STATE,u
            beq .kill
            cmpa #HUKS_PAUSE
            beq .pause
            cmpa #HUKS_JUMP
            beq .jump
            cmpa #HUKS_PACE
            beq .pace
            rts
.kill       lda #HUK_MAX_WAIT
            sta HUK_RUNW,u
            sta HUK_WAIT,u
            lda #HUK_RUN_DIST
            sta HUK_DIST,u
            rts
.pause      ldd <now
            std HUK_PAUSET,u
            rts
.jump       lda HUK_HEAD,u
            asla
            sta HUK_SX,u
            lda #-2
            sta HUK_SY,u
            rts
.pace       lda #HUK_PACE_WAIT
            sta HUK_WAIT,u
            lda #HUK_PACE_DIST
            sta HUK_DIST,u
            rts

Hulk_Aim    jsr AL2_AimX
            sta HUK_HEAD,u
            rts

; x += 2 * heading.
huk_step_x  ldb HUK_HEAD,u
            aslb
            sex
            addd E_X,u
            std E_X,u
            rts
; x -= 2 * heading.
huk_back_x  ldb HUK_HEAD,u
            aslb
            sex
            coma
            comb
            addd #1
            addd E_X,u
            std E_X,u
            rts
; A=size in pixels: A = heading * size. Preserves B.
huk_ahead   tst HUK_HEAD,u
            bpl .out
            nega
.out        rts
; True (Z set) if the man is within a cell vertically.
huk_man_near
            ldd <man_y
            subd E_Y,u
            jsr Abs_D
            cmpd #12
            bhs .no
            orcc #$04
            rts
.no         andcc #$FB
            rts
; D = (cell of y + sizeY) * 12.
huk_floor_y ldd E_Y,u
            addd #6
            jsr AL2_CellOf
            jmp Times12
; Advances the run frame.
huk_nextf   lda HUK_RUNF,u
            inca
            cmpa #4
            blo .s
            clra
.s          sta HUK_RUNF,u
            rts
; Sprite of the sinking hulk into arg0 and arg1.
huk_sink_sprite
            ldb HUK_FRAME,u
            tst HUK_HEAD,u
            bmi .s
            addb #6
.s          clra
            addd #HUK_START
            std <arg0
            std <arg1
            rts
; Kill and score for a fall into lava.
huk_lava_score
            jsr Main_RecordKill
            ldb #8
            ldx E_X,u
            ldy E_Y,u
            jsr Main_RecordScore
            rts

Hulk_Update clr HUK_FRAME,u
            lda HUK_STATE,u
            beq .kill
            cmpa #HUKS_PAUSE
            lbeq .pause
            cmpa #HUKS_JUMP
            lbeq .jump
            cmpa #HUKS_PACE
            lbeq .pace
            lda #5
            sta HUK_FRAME,u
            ldd <now
            subd HUK_PAUSET,u
            cmpd #HUK_SUSP_T
            lbls .end
            ldx E_X,u
            ldy E_Y,u
            jsr Main_OnScreen
            lbne .end
            lda #HUKS_PACE
            jsr Hulk_SwitchState
            lbra .end

.kill       tst HUK_WAIT,u
            lbgt .kwait
            jsr huk_step_x
            jsr AL2_PosCells
            lda #9              ; sizeX + 3
            jsr huk_ahead
            pshs a
            clrb
            jsr AL2_Near
            tsta
            beq .kfloor
            cmpa #PLATFORM_DESTRUCTIBLE
            beq .kblast
            cmpa #EXPLODING_PLATFORM
            beq .kblast
            ; Solid ahead: hop onto it if there is room above.
            lda ,s
            ldb #-12
            jsr AL2_Near
            tsta
            bne .kstop
            ldb ,s
            sex
            addd E_X,u
            jsr AL2_CellOf
            jsr AL2_CellMid
            tst HUK_HEAD,u
            bpl .kh1
            addd #16            ; sizeX + 4 + 6
            bra .kh2
.kh1        subd #16
.kh2        std E_X,u
            lda #HUKS_JUMP
            jsr Hulk_SwitchState
            lda #-6
            sta HUK_SY,u
            bra .kdone
.kstop      lda #HUKS_PAUSE
            jsr Hulk_SwitchState
            bra .kdone
.kblast     ldb ,s
            sex
            addd E_X,u
            jsr AL2_CellOf
            jsr Times12
            tfr d,x
            pshs x
            ldd E_Y,u
            jsr AL2_CellOf
            clra
            jsr Times12
            tfr d,y
            puls x
            lda #6
            ldb #ALIENS
            jsr AreaEffect_New
            bra .kdone
.kfloor     ldb #6
            jsr AL2_NearY
            tsta
            bne .kdone
            ldb #6
            lda HUK_HEAD,u
            bpl .kp1
            ldb #-6
.kp1        sex
            addd E_X,u
            tfr d,x
            ldy E_Y,u
            lda #4
            jsr Main_PitCheck
            tsta
            beq .kpitno
            cmpa #GOAL
            beq .kpitno
            lda #HUKS_JUMP
            jsr Hulk_SwitchState
            bra .kdone
.kpitno     jsr huk_back_x
            lda #HUKS_PAUSE
            jsr Hulk_SwitchState
.kdone      leas 1,s
            jsr huk_nextf
            dec HUK_DIST,u
            pshs cc
            lda HUK_WAIT,u
            adda HUK_RUNW,u
            sta HUK_WAIT,u
            lda #2
            sta HUK_RUNW,u
            puls cc
            bgt .kwait
            ; Still running at the man?
            ldd <man_x
            cmpd E_X,u
            beq .kend
            pshs cc
            lda HUK_HEAD,u
            bmi .kl
            puls cc
            bgt .kkeep
            bra .kend
.kl         puls cc
            blt .kkeep
.kend       lda #HUKS_PAUSE
            jsr Hulk_SwitchState
            bra .kwait
.kkeep      jsr Random
            lda #18
            mul
            adda #27            ; (r * 0.5 + 0.75) * RUN_DISTANCE
            sta HUK_DIST,u
.kwait      lda HUK_WAIT,u
            suba #2
            sta HUK_WAIT,u
            lda HUK_RUNF,u
            sta HUK_FRAME,u
            lbra .end

.pause      lda #5
            sta HUK_FRAME,u
            ldd <now
            subd HUK_PAUSET,u
            cmpd #HUK_PAUSE_T
            lbls .end
            jsr huk_man_near
            bne .pturn
            jsr Hulk_Aim
            lda #HUKS_KILL
            jsr Hulk_SwitchState
            lbra .end
.pturn      neg HUK_HEAD,u
            lda #HUKS_PACE
            jsr Hulk_SwitchState
            lbra .end

.jump       lda #2
            sta HUK_FRAME,u
            tst HUK_WAIT,u
            lbgt .jwait
            ldb HUK_SX,u
            sex
            addd E_X,u
            std E_X,u
            ldb HUK_SY,u
            sex
            addd E_Y,u
            std E_Y,u
            lda HUK_SY,u
            inca
            cmpa #5
            ble .jsy
            lda #5
.jsy        sta HUK_SY,u
            lda HUK_WAIT,u
            adda #HUK_JUMP_WAIT
            sta HUK_WAIT,u
            jsr AL2_PosCells
            lda #6
            jsr huk_ahead
            clrb
            jsr AL2_Near
            tsta
            beq .jbelow
            cmpa #FLOATY_PLATFORM
            beq .jbelow
            ; x = cell * 12 - sizeX * heading, as written in the C.
            lda #6
            jsr huk_ahead
            tfr a,b
            sex
            pshs d
            addd E_X,u
            jsr AL2_CellOf
            jsr Times12
            subd ,s++
            std E_X,u
            clr HUK_SX,u
            jsr AL2_PosCells
.jbelow     ldb #6
            jsr AL2_NearY
            tsta
            beq .jwait
            sta <t0+1           ; below
            cmpa #LAVA
            bne .jnl
            pshs a
            jsr huk_lava_score
            jsr huk_sink_sprite
            jsr huk_floor_y
            subd #1
            tfr d,y
            ldx E_X,u
            lda #72             ; 2 * sizeX * sizeY
            jsr AL2_Sink
            puls a
            sta <t0+1
.jnl        lda <t0+1
            cmpa #LAVA2
            bne .jland
            jsr huk_lava_score
            jsr huk_sink_sprite
            jsr huk_floor_y
            subd #1
            tfr d,y
            ldx E_X,u
            lda #72
            pshs a,x,y
            jsr AL2_Kill
            puls a,x,y
            tfr a,b
            jsr SinkingEntity2_New
            bra .jwait
.jland      jsr Hulk_Aim
            lda #HUKS_KILL
            jsr Hulk_SwitchState
            jsr huk_floor_y
            subd #6
            std E_Y,u
.jwait      lda HUK_WAIT,u
            suba #2
            sta HUK_WAIT,u
            bra .end

.pace       tst HUK_WAIT,u
            bgt .pwait
            jsr huk_man_near
            bne .pmove
            jsr Hulk_Aim
            lda #HUKS_KILL
            jsr Hulk_SwitchState
.pmove      lda HUK_WAIT,u
            adda #HUK_PACE_WAIT
            sta HUK_WAIT,u
            jsr huk_step_x
            jsr AL2_PosCells
            lda #6
            jsr huk_ahead
            clrb
            jsr AL2_Near
            tsta
            bne .pblock
            ldb #6
            jsr AL2_NearY
            tsta
            bne .pstep
.pblock     jsr huk_back_x
            lda #HUKS_PAUSE
            jsr Hulk_SwitchState
.pstep      jsr huk_nextf
            dec HUK_DIST,u
            bgt .pwait
            lda #HUKS_PAUSE
            jsr Hulk_SwitchState
.pwait      lda HUK_WAIT,u
            suba #2
            sta HUK_WAIT,u
            lda HUK_RUNF,u
            sta HUK_FRAME,u

.end        TOUCH_X 8,.spr
            jsr Alien_ContactKillCheck
.spr        ldb HUK_FRAME,u
            tst HUK_HEAD,u
            bmi .e1
            addb #6
.e1         clra
            addd #HUK_START
            std E_SPRITE,u
            jmp Alien_DrawSelf

Hulk_Hurt   lda HUK_STATE,u
            beq .base
            cmpa #HUKS_PAUSE
            beq .base
            ldx <hurt_laser
            beq .state
            lda #-1
            ldx L_VX,x
            bpl .h
            lda #1
.h          sta HUK_HEAD,u
.state      lda HUK_STATE,u
            cmpa #HUKS_JUMP
            beq .base
            clra
            jsr Hulk_SwitchState
.base       jmp Alien_Base_Hurt

; ---- TrooperHeavy.as --------------------------------------------------------------------------
; THEAVY_SHIELD is false, so Hurt never blocks (BLOCK stays, for its state number), and with KILL_LIMIT 1 any kill is final.
THV_HEAD    equ GC_END+0
THV_NEXT    equ GC_END+1        ; nextBlast, ticks
THV_WAIT    equ GC_END+2
THV_STATE   equ GC_END+3
THV_JIGGLE  equ GC_END+4
THV_FIRET   equ GC_END+5
THV_DIST    equ GC_END+7
THV_CHARGED equ GC_END+8
THV_SY      equ GC_END+9
THV_PUPPET  equ GC_END+10
THV_SX      equ GC_END+11
THV_RUNF    equ GC_END+12
THV_FRAME   equ GC_END+13       ; signed
            assert GC_END+14<=ENT_SIZE,"heavy trooper record"
; The C's state numbers, which the ambushes use.
THVS_FIRE   equ 0
THVS_RUN    equ 1
THVS_PAUSE  equ 2
THVS_JUMP   equ 3
THVS_SUSP   equ 4
THVS_BLOCK  equ 5
THVS_DEAD   equ 6
THVS_GETUP  equ 7
THV_START   equ 168
THV_HEALTH  equ 32              ; HEALTH * 2 with no shield
THV_FIRE_T2 equ 30              ; 2000 ms / 2
THV_CHARGE_T equ 19             ; 625 ms
THV_ANIM_T  equ 2               ; 66 ms
THV_PAUSE_T equ 30              ; 1000 ms
THV_SUSP_T  equ 10              ; 333 ms
THV_BLOCK_T equ 15              ; 500 ms
THV_CORPSE_T equ 150            ; 5000 ms
THV_JIGGLE_T equ 128            ; 4250 ms
THV_GETUP_T equ 20              ; 666 ms
THV_RUN_WAIT equ 6
THV_JUMP_WAIT equ 3
THV_CHARGE_SPRITE equ 70
THV_L3_SPEED equ 410            ; LASER3_SPEED_1, 48 px/s

TrooperHeavy_vt
            fdb TrooperHeavy_Update,TrooperHeavy_Hurt,TrooperHeavy_Die,TrooperHeavy_DeathEffect,0

TrooperHeavy_New
            pshs b,x
            ALIEN_ALLOC TrooperHeavy_vt
            beq .full
            puls b,x
            jsr AL2_InitCentered
            lda #THVS_SUSP
            sta THV_STATE,u
            lda #-1
            sta THV_HEAD,u
            ldd #156
            std E_SPRITE,u
            ldd #THV_HEALTH
            std E_HEALTH,u
            lda #6
            sta E_SCORE,u
            ldd #4*256+6
            std E_SIZEX,u
            jmp Main_AddToKillCount
.full       puls b,x,pc

; U=entity, A=0/1. Far-callable.
TrooperHeavy_SetPuppet
            sta THV_PUPPET,u
            rts

TrooperHeavy_DeathEffect
            lda #SND_MACHINE_EXPLOSION
            jsr Sound_Play
            FX_COUNT Explosion_New,16
            FX_COUNT CircleLarge_New,6
            ldd E_SPRITE,u
            std <arg0
            ldx E_X,u
            ldy E_Y,u
            jsr DeathFlash_New
            rts

TrooperHeavy_Die
            jsr Entity_DeathEffect
            jsr Main_RecordKill
            ldb E_SCORE,u
            ldx E_X,u
            ldy E_Y,u
            jsr Main_RecordScore
            jmp AL2_Kill

TrooperHeavy_Hurt
            ldd E_HEALTH,u
            subd <hurt_damage
            std E_HEALTH,u
            bgt .hit
            jmp Entity_Die
.hit        ldx <hurt_laser
            beq .self
            ldd L_X,x
            ldx L_Y,x
            jmp Entity_HitEffect
.self       ldd E_X,u
            ldx E_Y,u
            jmp Entity_HitEffect

; U=entity, A=state. Far-callable. Off screen, anything but a corpse waits in SUSPENDED instead.
TrooperHeavy_SwitchState
            pshs a
            jsr AL2_RectOn
            puls a
            beq .go
            ldb THV_STATE,u
            cmpb #THVS_DEAD
            beq .go
            cmpa #THVS_DEAD
            beq .go
            lda #THVS_SUSP
            sta THV_STATE,u
            ldd <now
            std E_START,u
            rts
.go         sta THV_STATE,u
            beq .fire
            cmpa #THVS_RUN
            beq .run
            cmpa #THVS_PAUSE
            beq .start
            cmpa #THVS_JUMP
            beq .jump
            cmpa #THVS_BLOCK
            beq .block
            cmpa #THVS_DEAD
            beq .dead
            cmpa #THVS_GETUP
            beq .getup
            rts
.fire       jsr AL2_AimX
            sta THV_HEAD,u
            ldd <now
            std THV_FIRET,u
            lda #THV_FIRE_T2
            sta THV_NEXT,u
            rts
.run        lda #THV_RUN_WAIT
            sta THV_WAIT,u
            jsr Random
            lda #1
            tstb
            bmi .r1
            lda #-1             ; Random < 1/2
.r1         sta THV_HEAD,u
            jsr Random
            lda #24             ; RUN_DISTANCE
            mul
            sta THV_DIST,u
            rts
.jump       lda THV_HEAD,u
            sta THV_SX,u
            lda #-3
            sta THV_SY,u
            rts
.block      clr THV_CHARGED,u
.start      ldd <now
            std E_START,u
            rts
.dead       lda E_FLAGS,u
            anda #~EF_SOLID&$FF
            sta E_FLAGS,u
            clr THV_CHARGED,u
            lda #-1
            sta THV_HEAD,u
            ldd #107
            std E_SPRITE,u
            bra .start
.getup      lda #SND_ZOMBOID
            jsr Sound_Play
            ldd #THV_START-7
            std E_SPRITE,u
            bra .start

TrooperHeavy_CheckGround
            jsr AL2_Ground
            tsta
            beq .air
            cmpa #LAVA
            beq .lava
            cmpa #LAVA2
            beq .lava
            rts
.air        lda #THVS_JUMP
            jsr TrooperHeavy_SwitchState
            clr THV_CHARGED,u
            rts
.lava       ldd E_SPRITE,u
            std <arg0
            std <arg1
            ldx E_X,u
            ldy E_Y,u
            lda #96
            jmp AL2_Sink

; firing allowed: FIRE, else PAUSE.
thv_fire_or_pause
            clra
            tst <firing_allowed
            bne .s
            lda #THVS_PAUSE
.s          jmp TrooperHeavy_SwitchState

TrooperHeavy_Update
            clr THV_FRAME,u
            lda THV_STATE,u
            beq .fire
            cmpa #THVS_RUN
            lbeq .run
            cmpa #THVS_PAUSE
            lbeq .pause
            cmpa #THVS_JUMP
            lbeq .jump
            cmpa #THVS_BLOCK
            lbeq .block
            cmpa #THVS_SUSP
            lbeq .susp
            cmpa #THVS_DEAD
            lbeq .dead
            lbra .getup

.fire       lda #-11
            sta THV_FRAME,u
            ldd <now
            subd THV_FIRET,u
            tsta
            beq .e8
            ldb #255
.e8         pshs b
            lda THV_NEXT,u
            suba #THV_CHARGE_T
            cmpa ,s
            lbhi .norm           ; not yet in the charge window
            clr THV_FRAME,u
            tst THV_CHARGED,u
            bne .check
            inc THV_CHARGED,u
            jsr AL2_AimX
            sta THV_HEAD,u
            ; offset x = 3 or -4, offset y = -1
            ldb #3
            tst THV_HEAD,u
            bpl .c1
            ldb #-4
.c1         sex
            addd E_X,u
            tfr d,x
            ldd E_Y,u
            subd #1
            tfr d,y
            lda #THV_CHARGE_T
            jsr ChargeHeavy_New
            lda #3
            tst THV_HEAD,u
            bpl .c2
            lda #-4
.c2         ldb #-1
            stu <arg0
            jsr Charge_New
            lda #SND_CHARGE
            jsr Sound_Play
            lbra .norm
.check      lda THV_NEXT,u
            cmpa ,s
            lbhi .norm
            ; Fire.
            clr THV_FRAME,u
            clr THV_CHARGED,u
            jsr AL2_RectOn
            bne .fired
            tst <firing_allowed
            beq .fired
            lda #SND_ALIEN_FIRE
            jsr Sound_Play
            ldd <man_x
            std <arg0
            ldd <man_y
            std <arg1
            ldx E_X,u
            ldy E_Y,u
            ldd #THV_L3_SPEED
            jsr Laser3_New
            ldb #3
            tst THV_HEAD,u
            bpl .f1
            ldb #-3
.f1         sex
            addd E_X,u
            tfr d,x
            ldy E_Y,u
            ldd #4*257
            jsr Circle_New
.fired      ldd <now
            std THV_FIRET,u
            jsr Random
            cmpb #64
            blo .topause
            tst <firing_allowed
            beq .topause
            clra
            jsr TrooperHeavy_SwitchState
            jsr Random
            lda #38             ; 2000 - r * 1250 ms
            mul
            nega
            adda #60
            sta THV_NEXT,u
            bra .norm
.topause    lda #THVS_PAUSE
            jsr TrooperHeavy_SwitchState
.norm       puls b
            cmpb #THV_ANIM_T
            bhi .fg
            lda #1
            sta THV_FRAME,u
.fg         jsr TrooperHeavy_CheckGround
            lbra .end

.run        tst THV_WAIT,u
            lbgt .rwait
            ldb THV_HEAD,u
            sex
            addd E_X,u
            std E_X,u
            jsr AL2_PosCells
            lda #4
            tst THV_HEAD,u
            bpl .r1
            lda #-4
.r1         pshs a
            clrb
            jsr AL2_Near
            tsta
            beq .rdrop
            bsr .rback
            neg THV_HEAD,u
            bra .rstep
.rback      ldb THV_HEAD,u
            sex
            coma
            comb
            addd #1
            addd E_X,u
            std E_X,u
            rts
.rdrop      lda ,s
            ldb #6
            jsr AL2_Near
            tsta
            bne .rstep
            ldb ,s
            sex
            addd E_X,u
            tfr d,x
            ldy E_Y,u
            lda #3
            jsr Main_PitCheck
            tsta
            beq .rno
            cmpa #GOAL
            beq .rno
            cmpa #LAVA
            beq .rno
            cmpa #LAVA2
            beq .rno
            lda #THVS_JUMP
            jsr TrooperHeavy_SwitchState
            bra .rstep
.rno        bsr .rback
            jsr thv_fire_or_pause
.rstep      leas 1,s
            jsr TrooperHeavy_CheckGround
            lda THV_RUNF,u
            inca
            cmpa #4
            blo .rf
            clra
.rf         sta THV_RUNF,u
            lda THV_WAIT,u
            adda #THV_RUN_WAIT
            sta THV_WAIT,u
            dec THV_DIST,u
            bgt .rwait
            jsr thv_fire_or_pause
.rwait      lda THV_WAIT,u
            suba #2
            sta THV_WAIT,u
            lda THV_RUNF,u
            adda #2
            sta THV_FRAME,u
            lbra .end

.pause      lda #-11
            sta THV_FRAME,u
            ldd <now
            subd E_START,u
            cmpd #THV_PAUSE_T
            bls .pg
            lda #THVS_RUN
            jsr TrooperHeavy_SwitchState
.pg         jsr TrooperHeavy_CheckGround
            lbra .end

.jump       tst THV_WAIT,u
            bgt .jwait
            ldb THV_SX,u
            sex
            addd E_X,u
            std E_X,u
            ldb THV_SY,u
            sex
            addd E_Y,u
            std E_Y,u
            inc THV_SY,u
            lda THV_WAIT,u
            adda #THV_JUMP_WAIT
            sta THV_WAIT,u
            jsr AL2_Ground
            tsta
            beq .jwait
            lda #THVS_RUN
            jsr TrooperHeavy_SwitchState
            ldd E_Y,u
            addd #6
            jsr AL2_CellOf
            jsr Times12
            subd #6
            std E_Y,u
.jwait      lda THV_WAIT,u
            suba #2
            sta THV_WAIT,u
            lbra .end

.block      lda #-12
            sta THV_FRAME,u
            ldd <now
            subd E_START,u
            cmpd #THV_BLOCK_T
            blo .bw
            lda #THVS_PAUSE
            jsr TrooperHeavy_SwitchState
.bw         lda THV_WAIT,u
            suba #2
            sta THV_WAIT,u
            lbra .end

.susp       ldd <now
            subd E_START,u
            cmpd #THV_SUSP_T
            lblo .end
            clra
            jsr TrooperHeavy_SwitchState
            lbra .end

.dead       tst THV_PUPPET,u
            bne .end
            ldd <now
            subd E_START,u
            cmpd #THV_CORPSE_T
            bls .djig
            ldx E_X,u
            ldy E_Y,u
            jsr Main_OnScreen
            bne .dwait
            lda #THVS_GETUP
            jsr TrooperHeavy_SwitchState
            bra .dfall
.dwait      ldd <now
            std E_START,u
            bra .dfall
.djig       tst THV_JIGGLE,u
            bne .dfall
            cmpd #THV_JIGGLE_T
            bls .dfall
            inc THV_JIGGLE,u
            stu <arg0
            jsr Jiggle_New
            ; Two 60 Hz frames' worth of falling: one pixel at a time, each with its own look.
.dfall      jsr AL2_Ground
            tsta
            bne .end
            ldd E_Y,u
            addd #1
            std E_Y,u
            jsr AL2_Ground
            tsta
            bne .end
            ldd E_Y,u
            addd #1
            std E_Y,u
            bra .end

.getup      ldd <now
            subd E_START,u
            cmpd #THV_GETUP_T
            bhs .gdone
            ; frame = -12 + 5 - int(progress * 4): elapsed * 4 / 20
            lda #52
            mul
            nega
            adda #-7
            sta THV_FRAME,u
            bra .end
.gdone      ldd #THV_HEALTH
            std E_HEALTH,u
            clra
            jsr TrooperHeavy_SwitchState
            clr THV_JIGGLE,u
            lda E_FLAGS,u
            ora #EF_SOLID
            sta E_FLAGS,u

.end        lda E_FLAGS,u
            bita #EF_SOLID
            beq .nosolid
            TOUCH_X 6,.nosolid
            jsr Alien_ContactKillCheck
.nosolid    lda THV_STATE,u
            cmpa #THVS_DEAD
            beq .draw
            ldb THV_FRAME,u
            sex
            addd #THV_START
            tst THV_HEAD,u
            bmi .e1
            addd #6
.e1         std E_SPRITE,u
.draw       ldd E_SPRITE,u
            jsr Alien_DrawSelf
            tst THV_CHARGED,u
            beq .out
            ldb #3-6
            tst THV_HEAD,u
            bpl .e2
            ldb #-4-6
.e2         sex
            addd E_X,u
            tfr d,x
            ldy E_Y,u
            leay -7,y
            ldd #THV_CHARGE_SPRITE
            jmp Draw_Sprite
.out        rts

; ---- Zomboid.as -------------------------------------------------------------------------------
ZOM_PHYS    equ E_DATA+0
ZOM_HEAD    equ E_DATA+1
ZOM_TIMER   equ E_DATA+2
ZOM_WAITING equ E_DATA+3        ; signed, the C's 60 Hz frames, less 2 per tick
ZOM_CACHED  equ E_DATA+4
ZOM_STATE   equ E_DATA+5
ZOM_KILLS   equ E_DATA+6
ZOM_WALKF   equ E_DATA+7
ZOM_WANDER  equ E_DATA+8
ZOM_SUPPORTED equ E_DATA+9
ZOM_SY      equ E_DATA+10
ZOM_SX      equ E_DATA+11
ZOM_WAITT   equ E_DATA+12
ZOM_PUPPET  equ E_DATA+13
ZOM_DX      equ E_DATA+14       ; man - self, kept across the step
ZOM_DY      equ E_DATA+16
            assert E_DATA+18<=ENT_SIZE,"zomboid record"
; The C's state numbers, which the ambushes use.
ZOMS_WANDER equ 0
ZOMS_KILL   equ 1
ZOMS_JUMP   equ 2
ZOMS_PAUSE  equ 3
ZOMS_DEAD   equ 4
ZOMS_REALLY equ 5
ZOMS_JIGGLE equ 6
ZOMS_GETUP  equ 7
ZOMS_SUSP   equ 8
ZOM_BASE    equ 84
ZOM_DEAD_SPRITE equ 107
ZOM_FALL_SPRITE equ 101
ZOM_HEALTH  equ 64
ZOM_KILL_LIMIT equ 2
ZOM_WANDER_DIST equ 36
ZOM_WANDER_WAIT equ 5
ZOM_GETUP_WAIT equ 5
ZOM_KILL_WAIT equ 3
ZOM_JUMP_WAIT equ 3
ZOM_SUSP_WAIT equ 10
ZOM_GETUP_FRAMES equ 6
ZOM_WALK_FRAMES equ 5
ZOM_CORPSE_T equ 150            ; 5000 ms
ZOM_JIGGLE_T equ 15             ; 500 ms

Zomboid_vt  fdb Zomboid_Update,0,Zomboid_Die,0,0

Zomboid_New pshs b,x
            ALIEN_ALLOC Zomboid_vt
            beq .full
            puls b,x
            jsr AL2_InitCentered
            lda #1
            sta ZOM_SUPPORTED,u
            sta ZOM_HEAD,u
            lda #ZOMS_SUSP
            sta ZOM_STATE,u
            lda #ZOM_SUSP_WAIT
            sta ZOM_WAITT,u
            ldd #ZOM_HEALTH
            std E_HEALTH,u
            lda #4
            sta E_SCORE,u
            ldd #5*256+6
            std E_SIZEX,u
            ldd #ZOM_BASE
            std E_SPRITE,u
            jmp Main_AddToKillCount
.full       puls b,x,pc

; U=entity, A=0/1. Far-callable.
Zomboid_SetPuppet
            sta ZOM_PUPPET,u
            rts

; 1 or -1 at random.
zom_randomize
            jsr Random
            lda #1
            tstb
            bpl .s
            lda #-1
.s          sta ZOM_HEAD,u
            rts

; U=entity, A=state. Far-callable.
Zomboid_SwitchState
            ; Anything it does next, it does now.
            ldb E_FLAGS,u
            andb #~(EF_NAP+EF_ASLEEP)&$FF
            stb E_FLAGS,u
            ldb ZOM_STATE,u
            stb ZOM_CACHED,u
            sta ZOM_STATE,u
            beq .wander
            cmpa #ZOMS_KILL
            beq .kill
            cmpa #ZOMS_JUMP
            beq .jump
            cmpa #ZOMS_PAUSE
            beq .pause
            cmpa #ZOMS_DEAD
            beq .dead
            cmpa #ZOMS_REALLY
            beq .really
            cmpa #ZOMS_JIGGLE
            beq .jiggle
            cmpa #ZOMS_GETUP
            beq .getup
            rts
.wander     lda #ZOM_WANDER_WAIT
            sta ZOM_WAITT,u
            clr ZOM_WALKF,u
            jsr Random
            lda #ZOM_WANDER_DIST
            mul
            sta ZOM_WANDER,u
            rts
.kill       lda #ZOM_KILL_WAIT
            sta ZOM_WAITT,u
            clr ZOM_WALKF,u
            rts
.pause      jsr Random
            lda #12             ; r * 60 / WANDER_WAIT + 60 / WANDER_WAIT
            mul
            adda #12
            sta ZOM_TIMER,u
            rts
.jump       lda ZOM_HEAD,u
            sta ZOM_SX,u
            lda #1
            sta ZOM_PHYS,u
            clr ZOM_SUPPORTED,u
            lda #ZOM_JUMP_WAIT
            sta ZOM_WAITT,u
            rts
.dead       ldd #ZOM_DEAD_SPRITE
            std E_SPRITE,u
            lda E_FLAGS,u
            anda #~EF_SOLID&$FF
            sta E_FLAGS,u
            lda #ZOM_WANDER_WAIT
            sta ZOM_WAITT,u
            ldd <now
            std E_START,u
            rts
.really     ldd #ZOM_DEAD_SPRITE
            std E_SPRITE,u
            lda E_FLAGS,u
            anda #~EF_SOLID&$FF
            sta E_FLAGS,u
            jmp AL2_Kill
.jiggle     ldd <now
            std E_START,u
            lda #ZOM_GETUP_WAIT
            sta ZOM_WAITT,u
            ldd #ZOM_DEAD_SPRITE
            std E_SPRITE,u
            stu <arg0
            jsr Jiggle_New
            rts
.getup      jsr AL2_AimX
            sta ZOM_HEAD,u
            lda #SND_ZOMBOID
            jsr Sound_Play
            lda E_FLAGS,u
            ora #EF_SOLID
            sta E_FLAGS,u
            ldd #ZOM_HEALTH
            std E_HEALTH,u
            lda #ZOM_GETUP_WAIT
            sta ZOM_WAITT,u
            lda #ZOM_GETUP_FRAMES
            sta ZOM_TIMER,u
            rts

Zomboid_Die inc ZOM_KILLS,u
            lda ZOM_KILLS,u
            cmpa #1
            bne .again
            jsr Main_RecordKill
            ldb E_SCORE,u
            bra .score
.again      clrb
.score      ldx E_X,u
            ldy E_Y,u
            jsr Main_RecordScore
            jsr Entity_DeathEffect
            ldd E_SPRITE,u
            std <arg0
            ldx E_X,u
            ldy E_Y,u
            jsr DeathFlash_New
            lda ZOM_KILLS,u
            cmpa #ZOM_KILL_LIMIT
            blo .corpse
            lda #ZOMS_REALLY
            jsr Zomboid_SwitchState
            bra .fall
.corpse     lda #ZOMS_DEAD
            jsr Zomboid_SwitchState
            ldd #ZOM_FALL_SPRITE
            std E_SPRITE,u
            ; The C never forgets a corpse, and it must not respawn fresh and score again.
            lda E_FLAGS,u
            ora #EF_KEEP
            sta E_FLAGS,u
.fall       lda #1
            sta ZOM_PHYS,u
            clr ZOM_SUPPORTED,u
            rts

Zomboid_CheckGround
            ldd E_X,u
            jsr AL2_CellOf
            pshs d
            ldd E_Y,u
            addd #6
            jsr AL2_CellOf
            puls x
            jsr Main_GetCell
            tsta
            beq .air
            cmpa #LAVA
            beq .lava
            cmpa #LAVA2
            beq .lava
            rts
.air        lda #ZOMS_JUMP
            jsr Zomboid_SwitchState
            lda #-3
            sta ZOM_SY,u
            rts
.lava       ldd E_SPRITE,u
            std <arg0
            std <arg1
            ldx E_X,u
            ldy E_Y,u
            lda #120            ; 2 * sizeX * 2 * sizeY
            jmp AL2_Sink

; E_SPRITE = D, plus 6 when heading right.
zom_facing  tst ZOM_HEAD,u
            bmi .s
            addd #6
.s          std E_SPRITE,u
            rts

Zomboid_Update
            lda ZOM_WAITING,u
            suba #2
            sta ZOM_WAITING,u
            lbgt .draw
            adda ZOM_WAITT,u
            sta ZOM_WAITING,u
            ; dx, dy and the first look at the man.
            ldd <man_x
            subd E_X,u
            std ZOM_DX,u
            ldd <man_y
            subd E_Y,u
            std ZOM_DY,u
            lda ZOM_STATE,u
            bne .notw
            ldd ZOM_DY,u
            jsr Abs_D
            cmpd #16
            bhs .notw
            lda #ZOMS_KILL
            jsr Zomboid_SwitchState
.notw       lda ZOM_STATE,u
            beq .look
            cmpa #ZOMS_PAUSE
            bne .wstate
.look       ldd ZOM_DY,u
            jsr Abs_D
            cmpd #8
            bhs .wstate
            jsr AL2_RectOn
            bne .wstate
            lda #ZOMS_KILL
            jsr Zomboid_SwitchState
.wstate     lda ZOM_STATE,u
            bne .kstate
            dec ZOM_WANDER,u
            bgt .wg
            jsr Random
            tstb
            bmi .again
            lda #ZOMS_PAUSE
            jsr Zomboid_SwitchState
            bra .wg
.again      clra
            jsr Zomboid_SwitchState
            jsr zom_randomize
.wg         jsr Zomboid_CheckGround
            ; The chain below tests the state as it is now.
.kstate     lda ZOM_STATE,u
            cmpa #ZOMS_KILL
            bne .jstate
            ldd #ZOM_BASE
            std E_SPRITE,u
            ldd ZOM_DY,u
            cmpd #-36
            ble .far
            cmpd #4
            bge .far
            ldd ZOM_DX,u
            cmpd #-12
            bge .kx
            lda #-1
            sta ZOM_HEAD,u
            bra .far
.kx         cmpd #12
            ble .far
            lda #1
            sta ZOM_HEAD,u
.far        ldd ZOM_DX,u
            jsr Abs_D
            cmpd #144
            bgt .lost
            ldd ZOM_DY,u
            jsr Abs_D
            cmpd #60
            ble .kc
.lost       lda #ZOMS_PAUSE
            jsr Zomboid_SwitchState
.kc         TOUCH_X 7,.kc2
            jsr Alien_ContactKillCheck
.kc2
            lbra .phys

.jstate     cmpa #ZOMS_JUMP
            bne .pstate
            ldd #ZOM_BASE+3
            jsr zom_facing
            TOUCH_X 7,.jc2
            jsr Alien_ContactKillCheck
.jc2        tst ZOM_SUPPORTED,u
            lbeq .phys
            lda ZOM_CACHED,u
            jsr Zomboid_SwitchState
            lbra .phys

.pstate     cmpa #ZOMS_PAUSE
            bne .gstate
            dec ZOM_TIMER,u
            ldd #ZOM_BASE
            jsr zom_facing
            tst ZOM_TIMER,u
            lbgt .phys
            clra
            jsr Zomboid_SwitchState
            jsr zom_randomize
            lbra .phys

.gstate     cmpa #ZOMS_JIGGLE
            bne .dstate
            ldd <now
            subd E_START,u
            cmpd #ZOM_JIGGLE_T
            lbls .phys
            lda #ZOMS_GETUP
            jsr Zomboid_SwitchState
            bra .phys

.dstate     cmpa #ZOMS_DEAD
            bne .ustate
            ; Lying still, it has nothing to do far from the view: its time to get up runs only on screen, and an ambush wakes it.
            tst ZOM_PHYS,u
            bne .dfall
            lda E_FLAGS,u
            ora #EF_NAP
            sta E_FLAGS,u
.dfall      tst ZOM_PUPPET,u
            bne .phys
            ldx E_X,u
            ldy E_Y,u
            jsr Main_OnScreen
            beq .don
            ldd <now
            std E_START,u
            bra .phys
.don        ldd <now
            subd E_START,u
            cmpd #ZOM_CORPSE_T
            bls .phys
            lda #ZOMS_JIGGLE
            jsr Zomboid_SwitchState
            bra .phys

.ustate     cmpa #ZOMS_GETUP
            bne .sstate
            dec ZOM_TIMER,u
            ldb ZOM_TIMER,u
            clra
            addd #ZOM_DEAD_SPRITE-ZOM_GETUP_FRAMES
            std E_SPRITE,u
            tst ZOM_TIMER,u
            bne .phys
            lda #ZOMS_KILL
            jsr Zomboid_SwitchState
            bra .phys

.sstate     cmpa #ZOMS_SUSP
            bne .phys
            dec ZOM_TIMER,u
            ldd #ZOM_BASE
            std E_SPRITE,u
            jsr AL2_RectOn
            bne .swait
            clra
            jsr Zomboid_SwitchState
            lda #-1
            sta ZOM_HEAD,u
            lda #ZOM_WANDER_DIST
            sta ZOM_WANDER,u
            bra .phys
.swait      lda ZOM_WAITT,u
            sta ZOM_WAITING,u

.phys       tst ZOM_PHYS,u
            lbeq .walk
            ldb ZOM_SX,u
            sex
            addd E_X,u
            std E_X,u
            ldb ZOM_SY,u
            sex
            addd E_Y,u
            std E_Y,u
            lda ZOM_SY,u
            inca
            cmpa #5
            ble .phy1
            lda #5
.phy1       sta ZOM_SY,u
            jsr AL2_PosCells
            lda #5
            tst ZOM_HEAD,u
            bpl .pa1
            lda #-5
.pa1        clrb
            jsr AL2_Near
            cmpa #PLATFORM
            beq .phit
            cmpa #PLATFORM_DESTRUCTIBLE
            beq .phit
            cmpa #EXPLODING_PLATFORM
            bne .pbelow
.phit       ldb #5
            tst ZOM_HEAD,u
            bpl .ph1
            ldb #-5
.ph1        sex
            addd E_X,u
            jsr AL2_CellOf
            jsr AL2_CellMid
            tst ZOM_HEAD,u
            bpl .ph2
            addd #11
            bra .ph3
.ph2        subd #11
.ph3        std E_X,u
            neg ZOM_SX,u
            jsr AL2_PosCells
.pbelow     ldb #6
            jsr AL2_NearY
            tsta
            beq .walk
            cmpa #LAVA
            beq .plava
            cmpa #LAVA2
            beq .plava
            clr ZOM_PHYS,u
            lda #1
            sta ZOM_SUPPORTED,u
            lda ZOM_STATE,u
            cmpa #ZOMS_DEAD
            bne .pl1
            ldd #ZOM_DEAD_SPRITE
            std E_SPRITE,u
.pl1        clr ZOM_SX,u
            clr ZOM_SY,u
            ldd E_Y,u
            addd #6
            jsr AL2_CellOf
            jsr Times12
            subd #6
            std E_Y,u
            bra .walk
.plava      jsr Main_RecordKill
            ldb E_SCORE,u
            lsrb
            ldx E_X,u
            ldy E_Y,u
            jsr Main_RecordScore
            ldb #ZOM_BASE+1+3-3
            tst ZOM_HEAD,u
            bmi .pv1
            addb #6
.pv1        clra
            std <arg0
            addd #1
            std <arg1
            ldd E_Y,u
            addd #6
            jsr AL2_CellOf
            jsr Times12
            subd #4
            tfr d,y
            ldx E_X,u
            lda #120
            jsr AL2_Sink

.walk       lda ZOM_STATE,u
            cmpa #ZOMS_KILL
            lbhi .draw
            ; WANDER or KILL.
            ldb ZOM_HEAD,u
            sex
            addd E_X,u
            std E_X,u
            lda ZOM_WALKF,u
            inca
            cmpa #ZOM_WALK_FRAMES
            blo .wf
            clra
.wf         sta ZOM_WALKF,u
            tfr a,b
            clra
            addd #ZOM_BASE+1
            jsr zom_facing
            jsr AL2_PosCells
            lda #8              ; sizeX + JUMP_CHECK_DISTANCE
            tst ZOM_HEAD,u
            bpl .w1
            lda #-8
.w1         pshs a
            clrb
            jsr AL2_Near
            tsta
            beq .wdrop
            ; Blocked: jump if the man is above or there is room on top.
            ldd ZOM_DY,u
            bmi .wjump
            lda ,s
            ldb #-12
            jsr AL2_Near
            tsta
            bne .wturn
.wjump      lda ZOM_STATE,u
            cmpa #ZOMS_KILL
            bne .wturn
            lda #ZOMS_JUMP
            jsr Zomboid_SwitchState
            lda #-5
            sta ZOM_SY,u
            bra .wprev
.wturn      ldb ZOM_HEAD,u
            neg ZOM_HEAD,u
            bra .wback
.wprev      ldb ZOM_HEAD,u
.wback      sex
            coma
            comb
            addd #1
            addd E_X,u
            std E_X,u
            bra .wdone
.wdrop      ldb #6
            jsr AL2_NearY
            tsta
            bne .wdone
            lda ZOM_STATE,u
            cmpa #ZOMS_KILL
            bne .wturn2
            ldb #5
            tst ZOM_HEAD,u
            bpl .wp1
            ldb #-5
.wp1        sex
            addd E_X,u
            tfr d,x
            ldy E_Y,u
            lda #4
            jsr Main_PitCheck
            tsta
            beq .wturn2
            cmpa #GOAL
            beq .wturn2
            lda #ZOMS_JUMP
            jsr Zomboid_SwitchState
            lda #-3
            sta ZOM_SY,u
            bra .wdone
.wturn2     ldb ZOM_HEAD,u
            neg ZOM_HEAD,u
            sex
            coma
            comb
            addd #1
            addd E_X,u
            std E_X,u
.wdone      leas 1,s

.draw       lda ZOM_KILLS,u
            beq .plain
            lda ZOM_STATE,u
            cmpa #ZOMS_DEAD
            beq .plain
            lda #COLOR_WHITE
            sta <draw_color
            ldx E_X,u
            leax -6,x
            ldy E_Y,u
            leay -6,y
            ldd E_SPRITE,u
            jmp Draw_ColoredSprite
.plain      ldd E_SPRITE,u
            jmp Alien_DrawSelf

; ---- the entity pool, full -------------------------------------------------------------------
; Ent_Alloc found no free slot. An entity asleep well out of view that can be forgotten (it came from the object list and
; nothing keeps it) gives up its slot, as it would anyway once the view is DESPAWN_DIST away, and comes back when the view
; is near. Without this, 22 exploding platforms and a few sleepers on level 8 left no slot for a shot block's entity, and
; the way on could not be opened. Returns A=1 and U=the freed slot, or A=0 and U=0. Keeps t0 and t1, Ent_Alloc's arguments.
ent_evict   ldu #ent_pool
            ldb <ent_count
            pshs b              ; slots left to look at
.next       lda E_FLAGS,u
            anda #EF_ASLEEP+EF_KEEP
            cmpa #EF_ASLEEP
            bne .skip
            ldx E_VT,u
            beq .skip
            ldx E_OBJ,u
            leax 1,x            ; $FFFF: made by another entity, with no object to come back from
            beq .skip
            ; Not in this tick's list of targets for lasers, which would still name its slot.
            ldd E_X,u
            subd <cam_x
            addd #TARGET_RANGE
            cmpd #TARGET_RANGE*2
            bhs .found
            ldd E_Y,u
            subd <cam_y
            addd #TARGET_RANGE
            cmpd #TARGET_RANGE*2
            bhs .found
.skip       leau ENT_SIZE,u
            dec ,s
            bne .next
            puls b
            ldu #0
            clra
            rts
.found      puls b
            jsr ent_forget
            lda #1
            rts

            assert *<=$4000,"bank 13 is full"
aliens2_end equ *
            endbank
