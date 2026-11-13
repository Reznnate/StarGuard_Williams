; The game flow: Main.as's states, on the fixed tick. Fixed ROM.

; ---- start ------------------------------------------------------------------------------------
game_start  lda #1
            sta <game_level
            FAR Cmos_Check
            FAR Bezel_On
.title      clr trial_on
            FAR Title_Screen
            tsta
            bne .scores
            ; Run levels until the game ends.
.play       jsr Level_Run
            tst lv_exit
            bne .over
            tst trial_on
            bne .scores
            lda <game_level
            cmpa #LEVEL_COUNT
            bhs .over
            inc <game_level
            bra .play
.scores     FAR Scores_Screen   ; A=the level to try, or 0
            sta <game_level
            sta trial_on
            tsta
            bne .play
.over       clr lv_exit
            lda #1
            sta <game_level
            bra .title

LEVEL_COUNT equ 9
UP_HOLD     equ 90          ; ticks: 3 seconds

; Clears the pools, the display lists and the screen.
Game_Reset  ldx #ent_pool
            stx ent_hi
            stx ent_ask_at
            ldx #0
            stx ban_fresh
            ldx #ent_pool
            ldx #laser_pool
            stx laser_hi
            ldx #ent_pool
            ldd #CLASS_END-ent_pool
            jsr mem_clear
            ldx #laser_pool
            ldd #LASER_SIZE*LASER_COUNT
            jsr mem_clear
            jsr Effect_ClearAll
            FAR MessageTrigger_Initialize
            jsr MessageBanner_ClearBanners
            ldd #dl_a
            std <dl_new
            std <dl_newp
            addd #DL_ENTRIES*DL_SIZE
            std <dl_limit
            ldd #dl_b
            std <dl_old
            std <dl_oldend
            clr <terrain_on
            clr <terrain_dirty
            clr <target_n
            clr <target_m
            clr wiz_live
            clr queue_on
            clr tl_valid
            clr tl_wait
            ldx #reg_ram        ; no region is marked or looks other than as the level began
            ldb #REG_BYTES
.regs       clr ,x+
            decb
            bne .regs
            clr <repair_rect
            clr <repair_rect+1
            clr <cam_fixed
            clr <death_cam
            clr <man_lock
            clr <level_done
            jmp Screen_Clear

; X=start, D=length.
mem_clear   clr ,x+
            subd #1
            bne mem_clear
            rts

; ---- a level ----------------------------------------------------------------------------------
Level_Run   jsr Game_Reset
            lda <game_level
            jsr Level_Load
            ; The level header gives the man's start: +16 cell x, +18 cell y, +20 heading (0 right, 1 left).
            ldy #0
            ldd 16,y
            std <spawn_x
            ldb 19,y
            stb <spawn_y
            lda #1
            tst 21,y
            beq .right
            lda #-1
.right      sta <spawn_h
            ldx <spawn_x
            ldb <spawn_y
            jsr Man_New
            jsr Camera_Apply
            lda #1
            sta <firing_allowed
            ldd #0
            std <kills
            std <level_score
            std <deaths
            clr <crystals
            ; The kill total comes from the level, because lazily spawned enemies can be counted twice.
            ldy #0
            ldd 14,y
            std <kill_total
            ldd <now
            std <level_start_t
            jsr Spawner_Reset
            jsr Tick_Begin

; Main.MainLoop. Draw order is the C's: man, lasers, entities, effects.
.loop       jsr Tick_Begin
            PROF 0
            lda <man_flags
            bita #MF_ACTIVE
            beq .noman
            jsr Man_Update
.noman      ldx <man_x
            ldy <man_y
            jsr Camera_Update
            jsr Man_Draw
            PROF 1
            jsr Laser_UpdateAll
            PROF 2
            jsr Ent_UpdateAll
            PROF 3
            lda #WATCHDOG_KEY
            sta WATCHDOG
            jsr Effect_UpdateAll
            PROF 4
            ; Objects come into being well out of sight: every other tick will do.
            lda <now+1
            lsra
            bcs .nospawn
            jsr Spawner_Update
.nospawn    PROF 5
            jsr Present
            PROF 6
            jsr Bezel_Tick
            ; Holding 1-up for 3 seconds leaves for the title.
            lda <inp_buttons
            bita #BTN_START1
            bne .up
            clr up_held
.noup       tst <level_done
            lbeq .loop
            ; Main.EndLevel: the last level has its win screen first.
            lda <game_level
            cmpa #LEVEL_COUNT
            blo .complete
            FAR Win_Screen
.complete   lda #SND_GUI_02
            jsr Sound_Play
            FAR Level_Complete
            rts
.up         inc up_held
            lda up_held
            cmpa #UP_HOLD
            blo .noup
            clr up_held
            lda #1
            sta lv_exit
            lda #SND_GUI_02
            jmp Sound_Play

; Main.RecordSpacemanDeath, with Man.Die's effects. A=death type.
Game_ManDie sta <die_type
            lda <man_flags
            bita #MF_ACTIVE
            beq .out
            bita #MF_INVULN
            beq .kill
            ; Invulnerable men only die in lava.
            lda <die_type
            cmpa #LAVA_DEATH
            beq .kill
            cmpa #LAVA2_DEATH
            beq .kill
            lda #SND_NO_DAMAGE
            jsr Sound_Play
            jsr Random
            clra
            subd #128
            std <arg0
            ldx <man_x
            ldy <man_y
            jmp NoDamage_New
.out        rts
.kill       ldd <deaths
            addd #1
            std <deaths
            clr <firing_allowed
            ; Enemy shots in flight fizzle out.
            jsr Lasers_Cancel
            ; Effects of the death.
            lda <die_type
            cmpa #LAVA_DEATH
            beq .lava
            cmpa #LAVA2_DEATH
            beq .quiet
            cmpa #EXPLOSION_ONLY
            beq .boom
            ldx <man_x
            ldy <man_y
            ldb #4
            jsr Circle_New
            ldx <man_x
            ldy <man_y
            ldb #16
            jsr Explosion_New
            ldd <man_sprite
            std <arg0
            ldx <man_x
            ldd <man_y
            subd #3
            tfr d,y
            jsr DeathFlash_New
            lda <die_type
            cmpa #LASER_HEAVY_DEATH
            beq .quiet
            ldx <man_x
            ldy <man_y
            leay -3,y
            ldd #48*256+47
            jsr Remains_New
            bra .quiet
.boom       ldx <man_x
            ldy <man_y
            ldb #16
            jsr Explosion_New
.quiet      lda #SND_MAN_DEATH
            jsr Sound_Play
            bra .respawn
.lava       ldd <man_y
            addd #3
            jsr Div12
            jsr Times12
            subd #1
            tfr d,y
            ldx <man_x
            ldb #16
            jsr LavaSplash_New
            lda #SND_MAN_LAVA_DEATH
            jsr Sound_Play
.respawn    ; The camera eases from here to the respawn point over a second.
            ldd <cam_x
            std <death_from_x
            ldd <cam_y
            std <death_from_y
            lda #DEATH_CAM_T
            sta <death_cam
            lda <spawn_h
            ldx <spawn_x
            ldb <spawn_y
            jsr Man_New
            ; Man_New keeps the camera while death_cam is set. Aim the man camera at the new man.
            ldd <man_x
            std <camm_x
            ldd <man_y
            std <camm_y
            std <cam_target_y
            clr <cam_nudge
            clr <cam_nudge+1
            lda #1
            sta <man_lock
            sta <firing_allowed ; Man_SetLockControls allows firing again, whichever way it sets the lock
            lda <spawn_h
            ldx <spawn_x
            ldb <spawn_y
            pshs u
            FAR ManCreator_New
            puls u,pc

DEATH_CAM_T equ 30

; Cancels every cancellable laser that can hit allies. This runs from inside the laser pass when a laser kills the
; man, so it keeps its own count.
Lasers_Cancel
            pshs u
            ldu #laser_pool
            lda #LASER_COUNT
            pshs a
.next       ldx L_VT,u
            beq .skip
            lda L_TARGET,u
            cmpa #ALIENS
            beq .skip
            lda L_FLAGS,u
            bita #LF_CANCEL
            beq .skip
            ora #LF_CANCELLED
            anda #~LF_ACTIVE&$FF
            sta L_FLAGS,u
            ldx L_X,u
            ldy L_Y,u
            ldb #3
            jsr Circle_New
.skip       leau LASER_SIZE,u
            dec ,s
            bne .next
            leas 1,s
            puls u,pc

; ---- bookkeeping called by the classes --------------------------------------------------------
Main_AddToKillCount
            rts
Main_RecordCrystal
            inc <crystals
            rts
Main_AddLife
            rts

; ---- goal cells -------------------------------------------------------------------------------
; Goal.as: a flickering sprite. Spawned from the object list like everything else.
GOAL_FLICKER equ 2          ; bit of the tick clock

goal_vt     fdb Goal_Update,0,0,0,0

Goal_New    pshs b,x
            ldx #goal_vt
            clra
            ldb #KIND_ENTITY
            jsr Ent_Alloc
            beq .full
            puls b,x
            jsr Entity_InitPos
            ldd E_X,u
            addd #6
            std E_X,u
            ldd E_Y,u
            addd #6
            std E_Y,u
            rts
.full       puls b,x,pc

Goal_Update lda <now+1
            anda #GOAL_FLICKER
            bne .out
            ldx E_X,u
            leax -6,x
            ldy E_Y,u
            leay -6,y
            ldd #59
            jmp Draw_Sprite
.out        rts

; ---- text -------------------------------------------------------------------------------------
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
            ldd text_x
            addd #SCR_COL0*2
            addb 4,u
            adca #0
            lsra
            rorb
            pshs cc
            tfr b,a
            ldb text_y+1
            addb #SCR_ROW0
            addb 5,u
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

; ---- screens ----------------------------------------------------------------------------------
; ---- sound ------------------------------------------------------------------------------------
; Commands for Robotron's sound ROM by SND_* id, chosen by measured length and pitch shape. 0 = silent.
sound_commands
            fcb 59              ; LASER: 0.12 s, mid falling
            fcb 7               ; EXPLOSION: 1.06 s, high falling
            fcb 56              ; MACHINE_EXPLOSION: 1.51 s, mid falling
            fcb 37              ; PLATFORM_EXPLOSION: 1.75 s, low falling
            fcb 53              ; QUIET_EXPLOSION: 1.09 s, mid falling, very quiet
            fcb 3               ; MISS: 0.19 s, mid steady
            fcb 27              ; QUIET_MISS: 0.02 s, low falling, very quiet
            fcb 32              ; HIT: 0.16 s, mid falling
            fcb 44              ; HIT_LOW: 0.54 s, mid falling
            fcb 48              ; MACHINE_HIT: 0.37 s, mid falling, quiet
            fcb 45              ; PIGLET: 0.47 s, high falling
            fcb 32              ; NO_DAMAGE: 0.16 s, mid falling
            fcb 8               ; JUMP: 0.24 s, mid rising
            fcb 6               ; LAND: 0.61 s, low steady
            fcb 12              ; ALIEN_FIRE: 0.61 s, mid falling
            fcb 42              ; ALIEN_FIRE_HEAVY: 0.39 s, high rising
            fcb 11              ; CHARGE: 0.84 s, high rising
            fcb 33              ; CHARGE_HEAVY: 2.26 s, mid steady
            fcb 36              ; ALIEN_BEAM: 1.54 s, high steady, quiet
            fcb 6               ; WARNING_BEEP: 0.61 s, low steady
            fcb 21              ; MINE: 1.09 s, mid rising
            fcb 45              ; MINE_DROP: 0.47 s, high falling
            fcb 44              ; DEBRIS_IMPACT: 0.54 s, mid falling
            fcb 55              ; LAVA_IMPACT: 0.92 s, high steady
            fcb 40              ; ZOMBOID: 1.64 s, mid steady
            fcb 53              ; CRYSTAL: 1.09 s, mid falling, very quiet
            fcb 47              ; WIN: 2.84 s, mid steady
            fcb 8               ; GUI_01: 0.24 s, mid rising
            fcb 25              ; GUI_02: 2.28 s, low steady
            fcb 13              ; GUI_03: 2.09 s, mid steady
            fcb 32              ; GUI_04: 0.16 s, mid falling
            fcb 10              ; GUI_05: 3.15 s, mid steady
            fcb 56              ; MAN_DEATH: 1.51 s, mid falling
            fcb 61              ; MAN_LAVA_DEATH: 2.17 s, high falling
; Each sound's priority.
            fcb 1,3,3,2,2,0,0,2,2,1,1,1,1,1,1,2,1,2,2,3,2,1,1,1,1,3,4,0,2,4,0,2,3,2
; The frames for which it is protected: less than its length where cutting off its tail costs little.
            fcb 6,30,30,30,15,4,4,8,15,8,12,8,8,4,12,20,20,30,40,30,30,12,12,20,30,60,120,4,15,60,4,20,30,20
