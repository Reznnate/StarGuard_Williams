; entities/*.as. Ported from ../port/src/entities.c and entities2.c. Bank 11.
; Lazy spawning changes a few things; each is marked "LAZY:" below.

; Statics, in the spare stack margin at $BF00-$BF3F. Reset does not clear these; MessageTrigger_Initialize does,
; and Game_Reset calls it before every level.
trigger_x   equ $BF00           ; word
trigger_y   equ $BF02           ; word
trigger_flag equ $BF04          ; Trigger.trigger
trigger_any equ $BF05           ; a trigger has tripped this level, so trigger_x and trigger_y mean something
message_trigger_count equ $BF06
mine_count  equ $BF07
respawn_count equ $BF08
respawn_cells equ $BF09         ; RESPAWN_FLAGGED_MAX entries of cell x (word), cell y (byte): up to $BF2C
RESPAWN_FLAGGED_MAX equ 12
nt_peek     equ $BF2D           ; RAM copy of nt_peek_src, 17 bytes: up to $BF3D

TRIGGER_RANGE equ 120

; Fields shared by the classes that use the heading helpers. Class fields start after these.
NT_HX       equ E_DATA+0
NT_HY       equ E_DATA+1

            bank 11
            org $0000

; ---- helpers --------------------------------------------------------------------------------
nt_deactivate
            lda E_FLAGS,u
            anda #~EF_ACTIVE&$FF
            sta E_FLAGS,u
            rts

nt_keep     lda E_FLAGS,u
            ora #EF_KEEP
            sta E_FLAGS,u
            rts

; Plain entity: Y=class, X=cell x, B=cell y, A=parameter. Returns U (0 with Z set if the pool is full), and on success
; Z clear, position at the cell center, and X, B, A as they came in.
nt_new_plain
            stx <t4
            std <t5
            tfr y,x
            lda #bank(nt_new_plain)
            ldb #KIND_ENTITY
            jsr Ent_Alloc
            beq nt_new_out
            ldx <t4
            ldb <t5+1
            jsr Entity_InitPos
            bra nt_new_center

; Alien-derived entity, in the alien list.
nt_new_alien
            pshs a
            lda #KIND_ALIEN
            sta <t2
            puls a
; The same, with the kind in t2.
nt_new_k    stx <t4
            std <t5
            tfr y,x
            lda #bank(nt_new_plain)
            ldb <t2
            jsr Ent_Alloc
            beq nt_new_out
            ldx <t4
            ldb <t5+1
            jsr Alien_Init
nt_new_center
            ldd E_X,u
            addd #6
            std E_X,u
            ldd E_Y,u
            addd #6
            std E_Y,u
            ldx <t4
            ldd <t5
            andcc #$FB
nt_new_out  rts

; Z set if the man is within B pixels of (X, Y) on both axes.
nt_box      clra
            std <t2
            tfr x,d
            subd <man_x
            bpl .x
            coma
            comb
            addd #1
.x          cmpd <t2
            bgt .no
            tfr y,d
            subd <man_y
            bpl .y
            coma
            comb
            addd #1
.y          cmpd <t2
            bgt .no
            orcc #$04
            rts
.no         andcc #$FB
            rts

nt_self_box ldx E_X,u
            ldy E_Y,u
            bra nt_box

; D=sprite. Draws centered on the entity.
nt_draw     ldx E_X,u
            ldy E_Y,u
; D=sprite, X, Y=center.
nt_draw_at  leax -6,x
            leay -6,y
            jmp Draw_Sprite

nt_draw_self
            ldd E_SPRITE,u
            bra nt_draw

; D=sprite, at the entity's cell, which does not change for a while: it goes to the still layer once. With no room, as a sprite.
nt_still_sprite
            ldx E_STILL,u
            bne .out
            pshs d
            lda E_FLAGS,u
            ora #EF_STILL
            sta E_FLAGS,u
            ldx E_X,u
            leax -6,x
            ldy E_Y,u
            leay -6,y
            puls d
            pshs d
            jsr Still_AddStatic
            stx E_STILL,u
            puls d
            beq nt_draw
.out        rts

; Its image in the still layer, if it has one, goes.
nt_still_drop
            ldx E_STILL,u
            beq .out
            jsr Still_Release
            ldx #0
            stx E_STILL,u
.out        rts

; Z set if the entity is in the 192x108 box.
nt_onscreen ldx E_X,u
            ldy E_Y,u
            jmp Main_OnScreen

; A=sound, played only if the entity is on screen. The C's positional sound fades with distance, and this hardware has no
; volume: off-screen turrets would otherwise be as loud as the man's own gun.
nt_sound_near
            pshs a
            bsr nt_onscreen
            puls a
            bne .out
            jmp Sound_Play
.out        rts

; A=heading (1, 0, -1), B=k>=0. D = heading * k.
nt_mulh     tsta
            beq .zero
            bpl .pos
            negb
            sex
            rts
.pos        clra
            rts
.zero       clrb
            rts

; B=k. X = E_X + hx * k, Y = E_Y + hy * k.
nt_hxy      pshs b
            lda NT_HX,u
            bsr nt_mulh
            addd E_X,u
            tfr d,x
            ldb ,s
            lda NT_HY,u
            bsr nt_mulh
            addd E_Y,u
            tfr d,y
            puls b,pc

; A=heading. D = -6 * heading.
nt_off6     ldb #6
            bsr nt_mulh
            coma
            comb
            addd #1
            rts

; X=cell x, B=cell y. Returns A=hx, B=hy: away from the first platform found left, right, above; otherwise up.
nt_heading  pshs b,x
            leax -1,x
            jsr Main_GetCell
            cmpa #PLATFORM
            beq .east
            ldx 1,s
            leax 1,x
            ldb ,s
            jsr Main_GetCell
            cmpa #PLATFORM
            beq .west
            ldx 1,s
            ldb ,s
            decb
            jsr Main_GetCell
            cmpa #PLATFORM
            beq .south
            ldd #$00FF
            bra .out
.east       ldd #$0100
            bra .out
.west       ldd #$FF00
            bra .out
.south      ldd #$0001
.out        leas 3,s
            rts

; LAZY: the C's turrets all start when the level loads, so their phases interlock. Spawning later would scramble that.
; A=period in ticks, B=offset. Sets E_START so that elapsed = (time since level start - offset) mod period.
nt_lattice  stb <t2
            sta <t2+1
            ldd <now
            subd <level_start_t
            addb <t2+1
            adca #0
            subb <t2
            sbca #0
            std <t3
            clra
            ldb #16
.bit        lsl <t3+1
            rol <t3
            rola
            cmpa <t2+1
            blo .next
            suba <t2+1
.next       decb
            bne .bit
            tfr a,b
            clra
            std <t3
            ldd <now
            subd <t3
            std E_START,u
            rts

nt_phase    fcb 0,19,39,58      ; phase / 3 * 58 ticks

; A=slots needed, at least 1. Z set if the pool has that many free.
nt_room     sta <t2
            ldx #ent_pool
            ldb <ent_count
.scan       pshs b
            ldd E_VT,x
            bne .used
            dec <t2
            beq .yes
.used       leax ENT_SIZE,x
            puls b
            decb
            bne .scan
            andcc #$FB
            rts
.yes        leas 1,s
            orcc #$04
            rts

; A=n. D = (Random * n) >> 8. Preserves X, Y.
nt_rnd      jsr Random
            mul
            tfr a,b
            clra
            rts

; A=k, X=offset. D = ((Random * k) >> 6) - offset: a random signed 8.8 speed. Preserves Y.
nt_rspeed   stx <t2
            jsr Random
            mul
            lsra
            rorb
            lsra
            rorb
            lsra
            rorb
            lsra
            rorb
            lsra
            rorb
            lsra
            rorb
            subd <t2
            rts

; Debris at X, Y, of either kind at random. A=gravity. B=0: +/-36 px/s, the platform's spread of 72.
; B=1: +/-32 px/s, Explosion.BIT_SPEED.
nt_debris   pshs a,b,x
            tstb
            bne .narrow
            lda #154
            ldx #307
            bsr nt_rspeed
            std <arg0
            lda #154
            ldx #307
            bsr nt_rspeed
            std <arg1
            bra .kind
.narrow     lda #137
            ldx #273
            bsr nt_rspeed
            std <arg0
            lda #137
            ldx #273
            bsr nt_rspeed
            std <arg1
.kind       jsr Random
            tstb
            puls a,b,x
            bmi .small
            tfr a,b
            jmp Bit_New
.small      tfr a,b
            jmp SmallBit_New

; X, Y=where the current hurt_laser is, or the entity's center if there is none.
nt_hurt_pos ldx <hurt_laser
            beq .self
            ldy L_Y,x
            ldx L_X,x
            rts
.self       ldx E_X,u
            ldy E_Y,u
            rts

; The invulnerable turret's reply to a shot.
nt_nodamage lda #SND_NO_DAMAGE
            jsr Sound_Play
            ldx <hurt_laser
            beq .zero
            ldd L_VX,x
            bra .have
.zero       ldd #0
.have       std <arg0
            bsr nt_hurt_pos
            jmp NoDamage_New

; Sets the white flash.
nt_flash    lda E_FLAGS,u
            ora #EF_FLASHING
            sta E_FLAGS,u
            ldb <now+1
            stb E_FLASHT,u
            rts

; A=count. A machine's HitEffect: SparkFountain at the hit position with the entity's hx, and the flash.
nt_machine_hit
            pshs a
            lda #SND_MACHINE_HIT
            jsr Sound_Play
            puls a
            ldb NT_HX,u
            ldx <hit_x
            ldy <hit_y
            jsr SparkFountain_New
            bra nt_flash

; A=color, X, Y=position of the slow circle. A turret's DeathEffect.
nt_turret_death
            pshs a,x,y
            lda #SND_MACHINE_EXPLOSION
            jsr Sound_Play
            ldd E_SPRITE,u
            std <arg0
            ldx E_X,u
            ldy E_Y,u
            jsr DeathFlash_New
            puls a
            tfr a,b
            ldx E_X,u
            ldy E_Y,u
            jsr TurretRemains_New
            puls x,y
            ldd #5*256+0
            jsr SlowCircle_New
            lda #16
            ldb NT_HX,u
            ldx E_X,u
            ldy E_Y,u
            jmp SparkFountain_New

; A=size, X, Y.
nt_circle   tfr a,b
            jmp Circle_New

; ---- Trigger.as -----------------------------------------------------------------------------
TRIGGER_WAIT equ E_DATA+0
TRIGGER_TRIPPED equ E_DATA+1
TRIGGER_WAIT_T equ 10           ; frames: 2 go by per tick

Trigger_vt  fdb Trigger_Update,0,0,0,0

; LAZY: the C's constructor clears the flag, which is harmless when everything is built at load. Here a trigger coming into
; range would cancel another's trip, so the flag is cleared only by MessageTrigger_Initialize and by the trigger itself.
Trigger_New ldy #Trigger_vt
            jmp nt_new_plain

; What waits for a trigger is awake when it trips. Anything else that was waiting only looks a little sooner. Keeps U.
nt_wake_all ldx #ent_pool
            ldb <ent_count
.next       clr E_WAIT,x
            leax ENT_SIZE,x
            decb
            bne .next
            rts

; A=0/1. trigger_x and trigger_y are plain words.
Trigger_GetTrigger
            lda trigger_flag
            rts

Trigger_Update
            NT_LIVE
            tst TRIGGER_WAIT,u
            bgt .count
            tst TRIGGER_TRIPPED,u
            beq .check
            clr trigger_flag
            lbsr nt_deactivate
            bra .reload
.check      ldb #18
            lbsr nt_self_box
            bne .reload
            lda #1
            sta trigger_flag
            sta trigger_any
            sta TRIGGER_TRIPPED,u
            bsr nt_wake_all
            ldd E_X,u
            std trigger_x
            ldd E_Y,u
            std trigger_y
            ; LAZY: it must live to clear the flag, whatever the camera does next.
            lbsr nt_keep
.reload     lda #TRIGGER_WAIT_T
            sta TRIGGER_WAIT,u
.count      lda TRIGGER_WAIT,u
            suba #2
            sta TRIGGER_WAIT,u
            rts

; ---- MessageTrigger.as ----------------------------------------------------------------------
MESSAGET_WAIT equ E_DATA+0
MESSAGET_WAIT_T equ 10          ; frames

MessageTrigger_vt fdb MessageTrigger_Update,0,0,0,0

MessageTrigger_New
            ldy #MessageTrigger_vt
            jmp nt_new_plain

; Called at every level start, so it resets all the statics.
MessageTrigger_Initialize
            clra
            sta message_trigger_count
            sta trigger_flag
            sta trigger_any
            sta mine_count
            sta respawn_count
            sta trigger_x
            sta trigger_x+1
            sta trigger_y
            sta trigger_y+1
            rts
MessageTrigger_GetTriggerCount
            lda message_trigger_count
            rts
MessageTrigger_IncrementTriggerCount
            inc message_trigger_count
            rts

; Reads the word at X in bank 10. Copied to RAM to run: code in a bank cannot switch away from itself.
nt_peek_src lda #10
            sta BANK_SELECT
            ldd ,x
            pshs a
            lda <cur_bank
            sta BANK_SELECT
            puls a
            rts
nt_peek_end
            assert nt_peek_end-nt_peek_src<=17,"nt_peek: too long"

; Main.GetMessage(message_trigger_count): arg0 = the text's address in bank 10. A word per level gives the offset of a
; count byte, which is followed by a word per message.
nt_get_message
            ldx #nt_peek_src
            ldy #nt_peek
            ldb #nt_peek_end-nt_peek_src
.copy       lda ,x+
            sta ,y+
            decb
            bne .copy
            ldb <level_bank
            aslb
            clra
            tfr d,x
            jsr nt_peek
            std <t2
            tfr d,x
            jsr nt_peek         ; A=the level's message count
            cmpa message_trigger_count
            bhi .have
            ldd #0              ; not in the original, which shows "ERROR: NO MESSAGE FOUND.": level 6 has a trigger more
            std <arg0           ; than messages, and reading past the list typed garbage, with its sound, for minutes
            rts
.have       ldd <t2
            addd #1
            std <t2
            ldb message_trigger_count
            clra
            aslb
            rola
            addd <t2
            tfr d,x
            jsr nt_peek
            std <arg0
            rts

MessageTrigger_Update
            NT_LIVE
            tst MESSAGET_WAIT,u
            bgt .count
            ldb #18
            lbsr nt_self_box
            bne .reload
            bsr nt_get_message  ; Z set: no message left for it
            beq .none
            ldx E_X,u
            ldy E_Y,u
            jsr MessageBanner_TriggerNearestBanner
.none       inc message_trigger_count
            ; LAZY: alreadyDisplayed would be lost if the record were forgotten, and the next message would then be shown
            ; here. Nothing is left to do after firing, so it leaves now and the spawner never brings it back.
            jmp nt_deactivate
.reload     lda #MESSAGET_WAIT_T
            sta MESSAGET_WAIT,u
.count      lda MESSAGET_WAIT,u
            suba #2
            sta MESSAGET_WAIT,u
            rts

; ---- BeamTurret.as --------------------------------------------------------------------------
BEAMT_O     equ E_DATA+0        ; 0 horizontal, 1 vertical
BEAMT_CHARGED equ E_DATA+1
BEAMT_X2    equ E_DATA+2
BEAMT_Y2    equ E_DATA+4
BEAMT_S2    equ E_DATA+6        ; the far end's entry in the still layer, or 0. The near end's is E_STILL.
BEAMT_FIRE_T equ 58             ; 1937.5 ms
BEAMT_CHARGE_T equ 8            ; 250 ms

BeamTurret_vt fdb BeamTurret_Update,BeamTurret_Hurt,0,0,0

; X=cell x, B=cell y, Y=dx (word), A=dy. Walks to the first cell that is not empty or floaty. Returns X, B.
nt_find_wall
            sta <t4
.loop       stx <t5
            stb <t4+1
            jsr Main_GetCell
            tsta
            beq .step
            cmpa #FLOATY_PLATFORM
            bne .found
.step       tfr y,d
            addd <t5
            tfr d,x
            ldb <t4+1
            addb <t4
            bra .loop
.found      ldx <t5
            ldb <t4+1
            rts

; A=orientation * 16 + phase.
BeamTurret_New
            ldy #BeamTurret_vt
            lbsr nt_new_alien
            bne .made
            rts
.made       pshs a,b,x          ; 0,s=param 1,s=cell y 2,s=cell x
            lsra
            lsra
            lsra
            lsra
            sta BEAMT_O,u
            bne .vert
            ; Horizontal.
            ldd #151
            std E_SPRITE,u
            ldx 2,s
            ldb 1,s
            ldy #-1
            clra
            bsr nt_find_wall
            leax 1,x
            tfr x,d
            jsr Times12
            std E_X,u
            ldx 2,s
            ldb 1,s
            ldy #1
            clra
            bsr nt_find_wall
            tfr x,d
            jsr Times12
            std BEAMT_X2,u
            ldd E_Y,u
            std BEAMT_Y2,u
            bra .common
.vert       ldd #152
            std E_SPRITE,u
            ldx 2,s
            ldb 1,s
            ldy #0
            lda #-1
            bsr nt_find_wall
            incb                ; 255 (above the map) becomes row 0
            clra
            jsr Times12
            std E_Y,u
            ldx 2,s
            ldb 1,s
            ldy #0
            lda #1
            lbsr nt_find_wall
            clra
            jsr Times12
            std BEAMT_Y2,u
            ldd E_X,u
            std BEAMT_X2,u
.common     ldd #0
            std BEAMT_S2,u
            ldd #48
            std E_HEALTH,u
            lda #6
            sta E_SIZEX,u
            sta E_SIZEY,u
            lda ,s
            anda #3
            ldx #nt_phase
            ldb a,x
            lda #BEAMT_FIRE_T
            lbsr nt_lattice
            leas 4,s
            rts

; B=k. X, Y = (X, Y) + k along the beam.
nt_beam_off sex
            tst BEAMT_O,u
            bne .v
            leax d,x
            rts
.v          leay d,y
            rts

; Z set if the beam can be seen: the C's test for its sound. Here it also decides whether its effects are worth their slots.
nt_beam_seen
            lbsr nt_onscreen
            beq .yes
            ldx BEAMT_X2,u
            ldy BEAMT_Y2,u
            jsr Main_OnScreen
            beq .yes
            ldd <man_x
            cmpd E_X,u
            ble .try2
            cmpd BEAMT_X2,u
            bge .try2
            ldd E_Y,u
            subd <cam_y
            jsr Abs_D
            cmpd #LOGIC_HALF_H
            ble .yes
.try2       ldd <man_y
            cmpd E_Y,u
            ble .no
            cmpd BEAMT_Y2,u
            bge .no
            ldd E_X,u
            subd <cam_x
            jsr Abs_D
            cmpd #LOGIC_HALF_W
            ble .yes
.no         andcc #$FB
            rts
.yes        orcc #$04
            rts

BeamTurret_Update
            NT_LIVE
            ldb #5
            lbsr nt_self_box
            beq .die
            ldx BEAMT_X2,u
            ldy BEAMT_Y2,u
            ldb #5
            lbsr nt_box
            bne .alive
.die        lda #LASER_DEATH
            jsr Man_Die
.alive      ldd <now
            subd E_START,u
            cmpd #BEAMT_FIRE_T
            blt .notfire
            ldd E_START,u
            addd #BEAMT_FIRE_T
            std E_START,u
            lda BEAMT_O,u
            ldx BEAMT_X2,u
            stx <arg0
            ldx BEAMT_Y2,u
            stx <arg1
            ldx E_X,u
            ldy E_Y,u
            jsr LaserBeam_New
            clr BEAMT_CHARGED,u
            lbsr nt_beam_seen
            bne .draw
            lda #SND_ALIEN_BEAM
            jsr Sound_Play
            ldx E_X,u
            ldy E_Y,u
            ldb #6
            lbsr nt_beam_off
            lda #3
            lbsr nt_circle
            ldx BEAMT_X2,u
            ldy BEAMT_Y2,u
            ldb #-6
            lbsr nt_beam_off
            lda #3
            lbsr nt_circle
            bra .draw
.notfire    tst BEAMT_CHARGED,u
            bne .draw
            cmpd #BEAMT_FIRE_T-BEAMT_CHARGE_T
            blt .draw
            lda #1
            sta BEAMT_CHARGED,u
            lbsr nt_beam_seen
            bne .draw
            ldx E_X,u
            ldy E_Y,u
            ldb #4
            lbsr nt_beam_off
            ; A, B = the heading.
            ldb BEAMT_O,u
            lda #1
            suba BEAMT_O,u
            jsr ChargeBeam_New
            ldx BEAMT_X2,u
            ldy BEAMT_Y2,u
            ldb #-4
            lbsr nt_beam_off
            ldb BEAMT_O,u
            negb
            lda BEAMT_O,u
            deca                ; -(1 - o)
            jsr ChargeBeam_New
.draw       ldd E_SPRITE,u
            lbsr nt_still_sprite
            ldx BEAMT_S2,u
            bne .tops
            ldx BEAMT_X2,u
            leax -6,x
            ldy BEAMT_Y2,u
            leay -6,y
            ldd E_SPRITE,u
            jsr Still_AddStatic
            stx BEAMT_S2,u
            bne .tops
            ldx BEAMT_X2,u
            ldy BEAMT_Y2,u
            ldd E_SPRITE,u
            lbsr nt_draw_at
            ; A turret shows over its beam, and the beam's last erase crosses it too, one tick after it has gone.
.tops       ldd <now
            subd E_START,u
            cmpd #LASERBEAM_T
            bgt bt_nap
            ldb beam_n
            cmpb #BEAM_TOP_MAX
            bhs .out
            aslb
            ldx #beam_list
            abx
            stu ,x
            inc beam_n
.out        rts

; With its beam gone and not yet charging, it has nothing to do but kill a man who touches it. It waits for its next event, or until
; the man could have reached it: he moves at most 4 pixels a tick.
bt_nap      ldx E_STILL,u
            beq .out
            ldx BEAMT_S2,u
            beq .out
            tst BEAMT_CHARGED,u
            bne .out
            ldd E_START,u
            addd #BEAMT_FIRE_T-BEAMT_CHARGE_T-1
            subd <now
            ble .out
            stb <t0
            ldb #255
            stb <t1
            ldx E_X,u
            ldy E_Y,u
            bsr bt_far
            ldx BEAMT_X2,u
            ldy BEAMT_Y2,u
            bsr bt_far
            ldb <t1
            lsrb
            lsrb
            subb #3
            bls .out
            cmpb <t0
            bls .w
            ldb <t0
.w          stb E_WAIT,u
.out        rts

; X, Y=a place. t1=the least so far of how far the man is from one, on the farther axis.
bt_far      tfr x,d
            subd <man_x
            bsr .abs
            stb <t2
            tfr y,d
            subd <man_y
            bsr .abs
            cmpb <t2
            bhs .far
            ldb <t2
.far        cmpb <t1
            bhs .out
            stb <t1
.out        rts
.abs        bpl .pos
            coma
            comb
            addd #1
.pos        tsta
            beq .ok
            ldb #255
.ok         rts

BeamTurret_Hurt
            ldx <hurt_laser
            beq .out
            lda L_TARGET,x
            cmpa #ALIENS
            bne .out
            lda #SND_NO_DAMAGE
            jsr Sound_Play
            lbsr nt_hurt_pos
            ldd #COLOR_GREEN*256+COLOR_GREEN
            jmp LaserImpact_New
.out        rts

; ---- BoltTurret.as --------------------------------------------------------------------------
BOLTT_COLOR equ E_DATA+2
BOLTT_CHARGED equ E_DATA+3
BOLTT_STATE equ E_DATA+4        ; 0 idle, 1 fire
BOLTT_FLASH equ E_DATA+5
BOLTT_CHARGESPR equ E_DATA+6
BOLTT_IDLE_T equ 58             ; 1937.5 ms
BOLTT_CHARGE_T equ 11           ; 375 ms
BOLTT_WAIT  equ 30              ; frames

BoltTurret_vt fdb BoltTurret_Update,BoltTurret_Hurt,BoltTurret_Die,BoltTurret_DeathEffect,BoltTurret_HitEffect

; A=color * 16 + phase.
BoltTurret_New
            pshs a
            lsra
            lsra
            lsra
            lsra
            cmpa #COLOR_GREEN
            beq .green
            lda #KIND_ALIEN
            bra .kind
.green      lda #KIND_ENTITY
.kind       sta <t2
            puls a
            ldy #BoltTurret_vt
            lbsr nt_new_k
            bne .made
            rts
.made       pshs a
            lsra
            lsra
            lsra
            lsra
            sta BOLTT_COLOR,u
            lbsr nt_heading
            std NT_HX,u
            lda #BOLTT_WAIT
            sta BOLTT_FLASH,u
            tst NT_HX,u
            beq .upright
            ldd #154
            std E_SPRITE,u
            lda #37
            sta BOLTT_CHARGESPR,u
            lda NT_HX,u
            lbsr nt_off6
            addd E_X,u
            std E_X,u
            bra .rest
.upright    ldd #166
            std E_SPRITE,u
            lda #167
            sta BOLTT_CHARGESPR,u
            lda NT_HY,u
            lbsr nt_off6
            addd E_Y,u
            std E_Y,u
.rest       puls a
            anda #3
            ldx #nt_phase
            ldb a,x
            lda #BOLTT_IDLE_T
            lbsr nt_lattice
            ldd #48
            std E_HEALTH,u
            lda #8
            sta E_SCORE,u
            lda #3
            sta E_SIZEX,u
            sta E_SIZEY,u
            lda BOLTT_COLOR,u
            cmpa #COLOR_RED
            bne .out
            tst NT_HX,u
            beq .out
            jsr Main_AddToKillCount
.out        rts

; startTime += elapsed - elapsed mod IDLE.
nt_bolt_whole
            ldd <now
            subd E_START,u
.loop       cmpd #BOLTT_IDLE_T
            blt .out
            subd #BOLTT_IDLE_T
            pshs d
            ldd E_START,u
            addd #BOLTT_IDLE_T
            std E_START,u
            puls d
            bra .loop
.out        rts

BoltTurret_Update
            NT_LIVE
            tst BOLTT_STATE,u
            bne .fire
            ldd <now
            subd E_START,u
            tst BOLTT_CHARGED,u
            beq .uncharged
            cmpd #BOLTT_IDLE_T
            lblt .timer
            bsr nt_bolt_whole
            lda #1
            sta BOLTT_STATE,u
            lbra .timer
.uncharged  cmpd #BOLTT_IDLE_T-BOLTT_CHARGE_T
            lblt .timer
            tst <firing_allowed
            bne .charge
            bsr nt_bolt_whole
            lbra .timer
.charge     lda NT_HX,u
            asla
            ldb NT_HY,u
            stu <arg0
            jsr Charge_New
            lda #1
            sta BOLTT_CHARGED,u
            lda #SND_CHARGE
            lbsr nt_sound_near
            bra .timer
.fire       inc gov_free
            lda BOLTT_COLOR,u
            cmpa #COLOR_RED
            bne .green
            lda #SND_ALIEN_FIRE
            lbsr nt_sound_near
            ldb #2
            lbsr nt_hxy
            lda NT_HX,u
            beq .redv
            jsr AlienLaser_New
            bra .redfin
.redv       lda NT_HY,u
            jsr AlienLaserVertical_New
.redfin     beq .flash
            lda L_FLAGS,x
            anda #~LF_CANCEL&$FF
            sta L_FLAGS,x
            bra .flash
.green      lda #SND_LASER
            lbsr nt_sound_near
            ldb #2
            lbsr nt_hxy
            lda NT_HX,u
            beq .greenv
            ; This one comes back with U=the laser.
            pshs u
            jsr SpacemanLaser_New
            puls u
            bra .flash
.greenv     ldd #1092           ; 128 px/s
            tst NT_HY,u
            bpl .gs
            ldd #-1092
.gs         std <arg0
            jsr SpacemanLaserVertical_New
.flash      clr gov_free
            jsr gov_thin        ; the shot itself is never left out
            bne .noflash
            ldb #2
            lbsr nt_hxy
            jsr SmallFlash_New
.noflash
            clr BOLTT_CHARGED,u
            clr BOLTT_STATE,u
.timer      lda BOLTT_FLASH,u
            suba #2
            sta BOLTT_FLASH,u
            bgt .draw
            tst BOLTT_STATE,u
            bne .reload
            jsr gov_thin        ; the flash of a turret at rest is only for show
            bne .reload
            ldx E_X,u
            ldy E_Y,u
            jsr SmallFlash_New
.reload     lda #BOLTT_WAIT
            sta BOLTT_FLASH,u
            ; The body does not move or change unless hit, so it goes to the still layer. A hit brings it back to flash.
.draw       lda E_FLAGS,u
            bita #EF_FLASHING
            beq .steady
            ldx E_STILL,u
            beq .usual
            jsr Still_Release
            ldx #0
            stx E_STILL,u
.usual      ldd E_SPRITE,u
            jsr Alien_DrawSelf
            bra .body
.steady     ldx E_STILL,u
            bne .body
            ora #EF_STILL
            sta E_FLAGS,u
            ldx E_X,u
            leax -6,x
            ldy E_Y,u
            leay -6,y
            ldd E_SPRITE,u
            jsr Still_AddStatic
            stx E_STILL,u
            beq .usual
.body       tst BOLTT_CHARGED,u
            beq .out
            ldb NT_HX,u
            negb
            sex
            addd E_X,u
            tfr d,x
            ldy E_Y,u
            ldb BOLTT_CHARGESPR,u
            clra
            lbra nt_draw_at
            ; In the still layer, it does nothing until it next charges or flashes, so it waits for exactly that tick.
.out        ldx E_STILL,u
            beq .ret
            ldd E_START,u
            addd #BOLTT_IDLE_T-BOLTT_CHARGE_T-1
            subd <now           ; ticks it may skip before it must charge
            ble .ret
            tsta
            bne .flashw
            cmpb #BOLTT_WAIT/2
            blo .fw
.flashw     ldb #BOLTT_WAIT/2
.fw         stb <t0
            lda BOLTT_FLASH,u
            deca
            lsra                ; and before it must flash
            cmpa <t0
            bhs .use
            sta <t0
.use        lda <t0
            beq .ret
            sta E_WAIT,u
            lda BOLTT_FLASH,u
            suba <t0
            suba <t0
            sta BOLTT_FLASH,u
.ret        rts

BoltTurret_Hurt
            tst NT_HX,u
            lbeq nt_nodamage
            jmp Alien_Base_Hurt

BoltTurret_HitEffect
            lda #4
            lbra nt_machine_hit

BoltTurret_DeathEffect
            ldx E_X,u
            lda NT_HX,u
            cmpa #-1
            bne .x
            leax -1,x
.x          ldy E_Y,u
            lda BOLTT_COLOR,u
            lbra nt_turret_death

BoltTurret_Die
            jsr Main_RecordKill
            ldb #9
            lda NT_HX,u
            lbsr nt_mulh
            addd E_X,u
            tfr d,x
            ldb #6
            lda NT_HY,u
            lbsr nt_mulh
            addd E_Y,u
            tfr d,y
            ldb E_SCORE,u
            jsr Main_RecordScore
nt_turret_finish
            jsr Entity_DeathEffect
            jsr Ent_MarkDead
            lbra nt_deactivate

; ---- BurstTurret.as -------------------------------------------------------------------------
BURSTT_COLOR equ E_DATA+2
BURSTT_STATE equ E_DATA+3       ; 0 idle, 1 fire, 2 pause
BURSTT_SWX  equ E_DATA+4
BURSTT_SWY  equ E_DATA+5
BURSTT_OFFX equ E_DATA+6        ; pixels the aim moves per shot: targetSpeed * FIRE_TIME. Must stay SWX + 2
BURSTT_OFFY equ E_DATA+7
BURSTT_CHARGED equ E_DATA+8
BURSTT_COUNT equ E_DATA+9
BURSTT_TX   equ E_DATA+10
BURSTT_TY   equ E_DATA+12
BURSTT_IDLE_T equ 38            ; 1250 ms
BURSTT_FIRE_T equ 9             ; 300 ms
BURSTT_CHARGE_T equ 11          ; 375 ms
BURSTT_RETRY_T equ BURSTT_IDLE_T-BURSTT_CHARGE_T ; the C's IDLE + CHARGE - 750 is this same 875 ms
BURSTT_OFF_T equ 52             ; IDLE + CHARGE + 100 ms
BURSTT_L3_SPEED equ 410         ; LASER3_SPEED_1, 48 px/s

BurstTurret_vt fdb BurstTurret_Update,0,BurstTurret_Die,BurstTurret_DeathEffect,BurstTurret_HitEffect

; A=color.
BurstTurret_New
            pshs a
            cmpa #COLOR_GREEN
            beq .green
            lda #KIND_ALIEN
            bra .kind
.green      lda #KIND_ENTITY
.kind       sta <t2
            puls a
            ldy #BurstTurret_vt
            lbsr nt_new_k
            bne .made
            rts
.made       sta BURSTT_COLOR,u
            leax -1,x
            jsr Main_GetCell
            ldb #1
            cmpa #PLATFORM
            beq .h
            ldb #-1
.h          stb NT_HX,u
            lda #1
            sta BURSTT_SWX,u
            sta BURSTT_SWY,u
            ldd <now
            std E_START,u
            lda NT_HX,u
            lbsr nt_off6
            addd E_X,u
            std E_X,u
            ldd #48
            std E_HEALTH,u
            lda #10
            sta E_SCORE,u
            lda #3
            sta E_SIZEX,u
            sta E_SIZEY,u
            lda BURSTT_COLOR,u
            cmpa #COLOR_GREEN
            beq .gs
            ldd #153
            std E_SPRITE,u
            jmp Main_AddToKillCount
.gs         ldd #141
            std E_SPRITE,u
            rts

; Main.GetAlienTarget: the last alien in the list with health left. Returns X, or 0.
nt_alien_target
            ldx <ent_last
            ldb <ent_count
.scan       ldy E_VT,x
            beq .next
            lda E_KIND,x
            cmpa #KIND_ALIEN
            bne .next
            lda E_FLAGS,x
            bita #EF_ACTIVE
            beq .next
            ldy E_HEALTH,x
            cmpy #0
            bgt .out
.next       leax -ENT_SIZE,x
            decb
            bne .scan
            ldx #0
.out        rts

nt_burst_retry
            clr BURSTT_STATE,u
            clr BURSTT_CHARGED,u
            ldd <now
            subd #BURSTT_RETRY_T
            std E_START,u
            rts

; D=man's speed on this axis, X=the sweep field. Target speed is sweep * 24 px/s and one shot is 300 ms: 7 pixels (7.2,
; truncated), kept in the offset field two bytes on.
nt_burst_sweep
            cmpd #0
            bgt .pos
            blt .neg
            neg ,x
            bra .set
.pos        lda #1
            sta ,x
            bra .set
.neg        lda #-1
            sta ,x
.set        lda ,x
            ldb #7
            lbsr nt_mulh
            stb 2,x
            rts

nt_burst_target
            lda BURSTT_COLOR,u
            cmpa #COLOR_GREEN
            bne .red
            bsr nt_alien_target
            cmpx #0
            beq nt_burst_retry
            ldd E_X,x
            std BURSTT_TX,u
            ldd E_Y,x
            std BURSTT_TY,u
            lda #1
            sta BURSTT_CHARGED,u
            neg BURSTT_SWX,u
            neg BURSTT_SWY,u
            rts
.red        ldd <man_x
            std BURSTT_TX,u
            ldd <man_y
            std BURSTT_TY,u
            leax BURSTT_SWX,u
            ldd <man_vx
            bsr nt_burst_sweep
            leax BURSTT_SWY,u
            ldd <man_vy
            bsr nt_burst_sweep
            ; Is the man in front of it?
            ldd BURSTT_TX,u
            subd E_X,u
            tst NT_HX,u
            bmi .faceleft
            cmpd #6
            blt nt_burst_retry
            bra .charge
.faceleft   cmpd #-6
            lbgt nt_burst_retry
.charge     lda NT_HX,u
            clrb
            stu <arg0
            jsr Charge_New
            lda #1
            sta BURSTT_CHARGED,u
            rts

BurstTurret_Update
            NT_LIVE
            lda BURSTT_STATE,u
            beq .idle
            cmpa #1
            lbeq .fire
            ; Pause.
            ldd <now
            subd E_START,u
            cmpd #BURSTT_FIRE_T
            lblt .draw
            lda BURSTT_COUNT,u
            cmpa #3
            bhs .rest
            lda #1
            sta BURSTT_STATE,u
            lbra .draw
.rest       clr BURSTT_STATE,u
            clr BURSTT_COUNT,u
            ldd <now
            std E_START,u
            lbra .draw
.idle       ldd <now
            subd E_START,u
            tst BURSTT_CHARGED,u
            beq .wait
            cmpd #BURSTT_IDLE_T
            lblt .draw
            ldd <now
            std E_START,u
            lda #1
            sta BURSTT_STATE,u
            lbra .draw
.wait       cmpd #BURSTT_IDLE_T-BURSTT_CHARGE_T
            lblt .draw
            lda BURSTT_COLOR,u
            cmpa #COLOR_GREEN
            beq .aim
            ; Main.RectangleOnScreen, with w = h = 3.
            ldd E_X,u
            subd <cam_x
            addd #LOGIC_HALF_W+3
            cmpd #(LOGIC_HALF_W+3)*2
            bhi .off
            ldd E_Y,u
            subd <cam_y
            jsr Abs_D
            cmpd #LOGIC_HALF_H+3
            ble .aim
.off        ldd <now
            subd #BURSTT_OFF_T
            std E_START,u
            clr BURSTT_CHARGED,u
            bra .draw
.aim        lbsr nt_burst_target
            bra .draw
.fire       lda #SND_ALIEN_FIRE
            lbsr nt_sound_near
            ; aim = target + offset * (count - 1)
            ldb BURSTT_COUNT,u
            cmpb #1
            beq .centre
            bhi .ahead
            ldb BURSTT_OFFX,u
            negb
            sex
            addd BURSTT_TX,u
            std <arg0
            ldb BURSTT_OFFY,u
            negb
            sex
            addd BURSTT_TY,u
            std <arg1
            bra .shoot
.centre     ldd BURSTT_TX,u
            std <arg0
            ldd BURSTT_TY,u
            std <arg1
            bra .shoot
.ahead      ldb BURSTT_OFFX,u
            sex
            addd BURSTT_TX,u
            std <arg0
            ldb BURSTT_OFFY,u
            sex
            addd BURSTT_TY,u
            std <arg1
.shoot      ldb #4
            lbsr nt_hxy
            ldd #BURSTT_L3_SPEED
            jsr Laser3_New
            inc BURSTT_COUNT,u
            lda BURSTT_COUNT,u
            cmpa #3
            bne .sc
            clr BURSTT_CHARGED,u
.sc         ldx E_X,u
            ldy E_Y,u
            lda #3
            lbsr nt_circle
            lda #2
            sta BURSTT_STATE,u
            ldd <now
            std E_START,u
.draw       ldd E_SPRITE,u
            jsr Alien_DrawSelf
            tst BURSTT_CHARGED,u
            beq .out
            ldb NT_HX,u
            negb
            sex
            addd E_X,u
            tfr d,x
            ldy E_Y,u
            ldd #69
            lbra nt_draw_at
.out        rts

BurstTurret_HitEffect
            lda #6
            lbra nt_machine_hit

BurstTurret_DeathEffect
            ldb NT_HX,u
            negb
            sex
            addd E_X,u
            tfr d,x
            ldy E_Y,u
            lda BURSTT_COLOR,u
            lbra nt_turret_death

BurstTurret_Die
            jsr Main_RecordKill
            ldb #11
            lda NT_HX,u
            lbsr nt_mulh
            addd E_X,u
            tfr d,x
            ldd E_Y,u
            addd #6
            tfr d,y
            ldb E_SCORE,u
            jsr Main_RecordScore
            lbra nt_turret_finish

; ---- Crystal.as -----------------------------------------------------------------------------
CRYSTAL_ANIM equ E_DATA+0
CRYSTAL_REST equ E_DATA+1
CRYSTAL_GEN equ E_DATA+2

Crystal_vt  fdb Crystal_Update,0,0,0,0

Crystal_New ldy #Crystal_vt
            jmp nt_new_plain

; The C falls one pixel on every 60 Hz frame: two per tick, each with its own test.
Crystal_Update
            NT_LIVE
            ldb #5
            lbsr nt_self_box
            bne .fall
            jsr Main_AddLife
            lda #SND_GUI_03
            jsr Sound_Play
            ldd E_Y,u
            subd #3
            tfr d,y
            ldx E_X,u
            ldb #20
            jsr Main_RecordScore
            jsr Main_RecordCrystal
            lbsr nt_deactivate
            ; Once on something, it looks again only if some cell of the level has changed.
.fall       lda cell_gen
            tst CRYSTAL_REST,u
            beq .steps
            cmpa CRYSTAL_GEN,u
            beq .anim
.steps      sta CRYSTAL_GEN,u
            clr CRYSTAL_REST,u
            bsr .step
            bsr .step
.anim
            ; Frame / 3 mod 4: the frame counter only needs to run to 12.
            lda CRYSTAL_ANIM,u
            adda #2
            cmpa #12
            blo .a
            suba #12
.a          sta CRYSTAL_ANIM,u
            ldb #255
.div        incb
            suba #3
            bcc .div
            clra
            addd #264
            lbra nt_draw
.step       ldd E_Y,u
            addd #3
            tfr d,y
            ldx E_X,u
            jsr Cell_At
            tsta
            bne .stop
            ldd E_Y,u
            addd #1
            std E_Y,u
            rts
.stop       inc CRYSTAL_REST,u
            rts

; ---- Mine.as --------------------------------------------------------------------------------
MINE_TIMER  equ E_DATA+0
MINE_WAIT_T equ 60              ; frames

Mine_vt     fdb Mine_Update,0,0,0,0

; Returns A = ++mine_count % 6.
nt_mine_offset
            inc mine_count
            lda mine_count
.mod        cmpa #6
            blo .out
            suba #6
            bra .mod
.out        rts

; The shared part of the Mine() constructor.
nt_mine_init
            bsr nt_mine_offset
            ldb #10
            mul
            stb MINE_TIMER,u
            ldd E_Y,u
            addd #5
            std E_Y,u
            rts

Mine_New    ldy #Mine_vt
            lbsr nt_new_plain
            beq .out
            bsr nt_mine_init
            andcc #$FB
.out        rts

; U=entity.
Mine_Explode
            lda #SND_MACHINE_EXPLOSION
            jsr Sound_Play
            ldx E_X,u
            ldy E_Y,u
            jsr MineBlast_New
            lbra nt_deactivate

; int(sqrt(dx^2 + dy^2)) < 5, which is dx^2 + dy^2 < 25.
Mine_Update
            NT_LIVE
            ldd <man_x
            subd E_X,u
            addd #4             ; within 4 either way?
            cmpd #8
            bhi .timer
            ldd <man_x
            subd E_X,u
            jsr Abs_D
            pshs b
            ldd <man_y
            subd E_Y,u
            jsr Abs_D
            cmpd #5
            bge .far
            tfr b,a
            mul
            stb <t2
            puls a
            tfr a,b
            mul
            addb <t2
            cmpb #25
            bhs .timer
            bsr Mine_Explode
            bra .timer
.far        leas 1,s
.timer      lda MINE_TIMER,u
            suba #2
            sta MINE_TIMER,u
            bgt .draw
            ldx E_X,u
            ldy E_Y,u
            leay -1,y
            jsr SmallFlash_New
            lda #MINE_WAIT_T
            sta MINE_TIMER,u
.draw       ldd #137
            lbra nt_still_sprite

; ---- DropMine.as ----------------------------------------------------------------------------
DROPM_POS   equ E_DATA+1
DROPM_STATE equ E_DATA+2        ; 0 armed, 1 drop, 2 reset
DROPM_FLASHDROP equ E_DATA+3
DROPM_DROPT equ E_DATA+4
DROPM_FLASHT equ E_DATA+6
DROPM_RESET_T equ 90            ; 3000 ms
DROPM_FLASH_T equ 60            ; 2000 ms
DROPM_FLASHDROP_T equ 5         ; 166 ms
DROPM_RESET_WAIT equ 20         ; frames

DropMine_vt fdb DropMine_Update,0,0,0,0

DropMine_New
            ldy #DropMine_vt
            lbsr nt_new_plain
            beq .out
            lbsr nt_mine_init
            lbsr nt_mine_offset
            ldb #10             ; offset / 6 * 2000 ms
            mul
            addd <now
            std DROPM_FLASHT,u
            ldd E_Y,u
            subd #10            ; y * 12 + 1
            std E_Y,u
            andcc #$FB
.out        rts

; The C registers a DropMine twice, so it updates twice a frame. Time-based parts do not care. The frame-counted
; reset animation does: its timer runs at 4 per tick rather than 2.
DropMine_Update
            NT_LIVE
            ldd <now
            subd DROPM_FLASHT,u
            cmpd #DROPM_FLASH_T
            blt .state
            subd #DROPM_FLASH_T
            addd <now
            std DROPM_FLASHT,u
            tst DROPM_STATE,u
            bne .state
            ldx E_X,u
            ldy E_Y,u
            jsr SmallFlash_New
.state      lda DROPM_STATE,u
            beq .armed
            lbsr nt_still_drop
            lda DROPM_STATE,u
            cmpa #1
            lbeq .drop
            ; Reset.
            lda MINE_TIMER,u
            suba #4
            sta MINE_TIMER,u
            ldx E_X,u
            ldb DROPM_POS,u
            sex
            addd E_Y,u
            tfr d,y
            ldd #138
            lbsr nt_draw_at
            tst MINE_TIMER,u
            bgt .reset2
            inc DROPM_POS,u
            lda #DROPM_RESET_WAIT
            sta MINE_TIMER,u
.reset2     lda DROPM_POS,u
            lbmi .frame1
            cmpa #1
            blo .frame1
            clr DROPM_STATE,u
            bra .frame1
.armed      ldd <man_x
            subd E_X,u
            addd #(12)-1
            cmpd #((12)-1)*2
            bhi .frame0
            ldd <man_y
            subd E_Y,u
            ble .frame0
            lbsr nt_onscreen
            bne .frame0
            tst <firing_allowed
            beq .frame0
            ldx E_X,u
            ldy E_Y,u
            jsr MineBomb_New
            lda #1
            sta DROPM_STATE,u
            sta DROPM_FLASHDROP,u
            lda #SND_MINE_DROP
            jsr Sound_Play
            ldd <now
            std DROPM_DROPT,u
            lbsr nt_still_drop  ; it has begun to drop
.frame0     tst DROPM_FLASHDROP,u
            bne .frame0s
            ldd #139
            tst DROPM_STATE,u
            lbeq nt_still_sprite
.frame0s    lbsr nt_still_drop
            ldd #139
            bra .show
.drop       ldd <now
            subd DROPM_DROPT,u
            cmpd #DROPM_FLASHDROP_T
            ble .noclr
            clr DROPM_FLASHDROP,u
.noclr      cmpd #DROPM_RESET_T
            blt .frame1
            lda #2
            sta DROPM_STATE,u
            lda #-2
            sta DROPM_POS,u
.frame1     ldd #140
.show       ldx E_X,u
            ldy E_Y,u
            leax -6,x
            leay -6,y
            tst DROPM_FLASHDROP,u
            bne .white
            jmp Draw_Sprite
.white      pshs a
            lda #COLOR_WHITE
            sta <draw_color
            puls a
            jmp Draw_ColoredSprite

; ---- ExplodingPlatform.as -------------------------------------------------------------------
EXPLAT_RESPAWN equ E_DATA+0
EXPLAT_STATE equ E_DATA+1       ; 0 ready, 1 countdown, 2 exploded
EXPLAT_EFFECT equ E_DATA+2      ; respawnEffectPlayed
EXPLAT_CELLY equ E_DATA+3
EXPLAT_CELLX equ E_DATA+4
EXPLAT_WARNT equ E_DATA+6
EXPLAT_IDLET equ E_DATA+8
EXPLAT_SHOWS equ E_DATA+10      ; the sprite in the still layer
EXPLAT_DELAY_T equ 30           ; 1000 ms
EXPLAT_TICK_T equ 4             ; 125 ms
EXPLAT_IDLE_T equ 30            ; 1000 ms
EXPLAT_FLASH_T equ 2            ; 62 ms
EXPLAT_RESPAWN_T equ 60         ; 2000 ms
EXPLAT_EFFECT_T equ 8           ; 250 ms
EXPLAT_BOOM_T equ 4             ; 125 ms
EXPLAT_PIECES equ 3             ; the C's 6 by 6 would take 36 of the 40 effect slots

ExplodingPlatform_vt fdb ExplodingPlatform_Update,ExplodingPlatform_Hurt,0,0,0

; A=1 if it respawns. The cell is in the ROM grid already, so it is not marked here.
ExplodingPlatform_New
            ldy #ExplodingPlatform_vt
            lbsr nt_new_alien
            beq .out
            sta EXPLAT_RESPAWN,u
            stx EXPLAT_CELLX,u
            stb EXPLAT_CELLY,u
            ldd <now
            std E_START,u
            std EXPLAT_WARNT,u
            std EXPLAT_IDLET,u
            lda #6
            sta E_SIZEX,u
            sta E_SIZEY,u
            andcc #$FB
.out        rts

; A=color: the C's shaded rectangle, 2 pixels inside the cell.
nt_ep_shade sta <draw_color
            ldx E_X,u
            leax -4,x
            ldy E_Y,u
            leay -4,y
            ldd #8*256+8
            jmp Draw_RectWorld

nt_ep_explode
            ldd #8*256+BOTH
            ldx E_X,u
            ldy E_Y,u
            jsr AreaEffect_New
            tst EXPLAT_RESPAWN,u
            beq .gone
            lda #2
            sta EXPLAT_STATE,u
            clr EXPLAT_EFFECT,u
            ldd <now
            std E_START,u
            std EXPLAT_WARNT,u
            ldd #120
            std <arg0
            ldx E_X,u
            ldy E_Y,u
            jsr DeathFlash_New
            lda E_FLAGS,u
            anda #~EF_SOLID&$FF
            sta E_FLAGS,u
            bra .cell
.gone       lbsr nt_deactivate
.cell       clra
            ldx EXPLAT_CELLX,u
            ldb EXPLAT_CELLY,u
            jsr Main_SetCellType
            lda #SND_PLATFORM_EXPLOSION
            jsr Sound_Play
            ; Debris on a grid across the cell.
            lda #EXPLAT_PIECES
            pshs a
.row        lda #EXPLAT_PIECES
            pshs a
.col        lda ,s              ; column left
            ldb #4
            mul
            addd E_X,u
            subd #8
            tfr d,x
            lda 1,s             ; rows left
            ldb #4
            mul
            addd E_Y,u
            subd #8
            tfr d,y
            ldd #BIT_GRAVITY_16*256+0 ; wide spread
            lbsr nt_debris
            dec ,s
            bne .col
            leas 1,s
            dec ,s
            bne .row
            leas 1,s
            rts

; LAZY: from the moment it leaves READY it may have an empty cell, so forgetting it now would bring it back as a platform
; that is drawn but not solid. It stays in memory until it is whole again.
EXPLAT_NEAR equ 28              ; the man cannot come from there into its box in 3 ticks
ExplodingPlatform_Update
            NT_LIVE
            ldd <now
            subd EXPLAT_IDLET,u
            cmpd #EXPLAT_FLASH_T
            bge .red
            ldb #COLOR_WHITE    ; the shade's color, for a platform at rest
            bra .tint
.red        cmpd #EXPLAT_IDLE_T
            ble .redok
            ldd EXPLAT_IDLET,u
            addd #EXPLAT_IDLE_T
            std EXPLAT_IDLET,u
.redok      ldb #COLOR_RED
.tint       stb <draw_color
            lda EXPLAT_STATE,u
            beq .ready
            ; At rest it is an image in the still layer. Not now.
            ldx E_STILL,u
            beq .nostill
            jsr Still_Release
            ldx #0
            stx E_STILL,u
            lda EXPLAT_STATE,u
.nostill    cmpa #1
            lbeq .count
            lbra .exploded
.ready      ldd <man_x
            subd E_X,u
            addd #8
            cmpd #(8)*2
            lbhi .readydraw
            ldd <man_y
            subd E_Y,u
            addd #9
            cmpd #(9)*2
            lbhi .readydraw
            ldd E_Y,u
            subd #8             ; y - sizeY + 1 - man size y
            cmpd <man_y
            ble .readydraw
            lda #1
            sta EXPLAT_STATE,u
            lbsr nt_keep
            ldd <now
            std E_START,u
            lda #SND_WARNING_BEEP
            jsr Sound_Play
.readydraw  ldd #SPR_EP_RED
            lda <draw_color
            cmpa #COLOR_WHITE
            lda #SPR_EP_RED>>8
            bne .shade
            ldb #SPR_EP_WHITE&$FF
.shade      ldx E_STILL,u
            beq .place
            cmpd EXPLAT_SHOWS,u
            beq .shown
            std EXPLAT_SHOWS,u
            jmp Still_Swap
            ; With the man well off to the side, it has nothing to do until its color next changes, for at most 3 ticks.
.shown      ldd <man_x
            subd E_X,u
            addd #EXPLAT_NEAR
            cmpd #EXPLAT_NEAR*2
            bls .wout
            ldd <now
            subd EXPLAT_IDLET,u
            cmpd #EXPLAT_FLASH_T
            blt .wwhite
            subd #EXPLAT_IDLE_T+1
            bra .wleft
.wwhite     subd #EXPLAT_FLASH_T
.wleft      addd #1             ; -(ticks to skip)
            bge .wout
            cmpd #-3
            bge .wset
            ldb #-3
.wset       negb
            stb E_WAIT,u
.wout       rts
.place      std EXPLAT_SHOWS,u
            lda E_FLAGS,u
            ora #EF_STILL
            sta E_FLAGS,u
            ldx E_X,u
            leax -6,x
            ldy E_Y,u
            leay -6,y
            ldd EXPLAT_SHOWS,u
            jsr Still_AddStatic
            stx E_STILL,u
            bne .shown
            ; No room: as a sprite, for now.
            ldd EXPLAT_SHOWS,u
            lbra nt_draw
.count      ldd <now
            subd E_START,u
            cmpd #EXPLAT_DELAY_T-EXPLAT_BOOM_T
            blt .warn
            ldd #144
            lbsr nt_draw
            bra .boom
.warn       ldd #53
            lbsr nt_draw
            ldd <now
            subd EXPLAT_WARNT,u
            cmpd #EXPLAT_FLASH_T
            bge .warnred
            lda #COLOR_WHITE
            lbsr nt_ep_shade
            bra .boom
.warnred    pshs d
            lda #COLOR_RED
            lbsr nt_ep_shade
            puls d
            cmpd #EXPLAT_TICK_T
            ble .boom
            lda #SND_WARNING_BEEP
            jsr Sound_Play
            ldd <now
            std EXPLAT_WARNT,u
.boom       ldd <now
            subd E_START,u
            cmpd #EXPLAT_DELAY_T
            blt .out
            lbra nt_ep_explode
.exploded   ldd <now
            subd E_START,u
            tst EXPLAT_EFFECT,u
            bne .wait
            cmpd #EXPLAT_RESPAWN_T-EXPLAT_EFFECT_T
            blt .wait
            lda #1
            sta EXPLAT_EFFECT,u
            ldx E_X,u
            ldy E_Y,u
            jsr ExplodingPlatformRespawn_New
            ldd <now
            subd E_START,u
.wait       cmpd #EXPLAT_RESPAWN_T
            blt .out
            clr EXPLAT_STATE,u
            lda #EXPLODING_PLATFORM
            ldx EXPLAT_CELLX,u
            ldb EXPLAT_CELLY,u
            jsr Main_SetCellType
            ; Whole again: it can be forgotten.
            lda E_FLAGS,u
            ora #EF_SOLID
            anda #~EF_KEEP&$FF
            sta E_FLAGS,u
.out        rts

ExplodingPlatform_Hurt
            ldd E_HEALTH,u
            subd <hurt_damage
            std E_HEALTH,u
            bgt .alive
            clra
            ldx EXPLAT_CELLX,u
            ldb EXPLAT_CELLY,u
            jsr Main_SetCellType
            lda #1
            sta EXPLAT_STATE,u
            lbsr nt_keep
            ldd <now
            subd #EXPLAT_DELAY_T
            std E_START,u
            rts
.alive      lda #SND_MACHINE_HIT
            jsr Sound_Play
            ldx E_X,u
            ldy E_Y,u
            ldd #$0101
            jsr Explosion_New
            ldx E_X,u
            ldy E_Y,u
            ldd #COLOR_RED*256+COLOR_RED
            jmp LaserImpact_New

; ---- exploding platforms at rest -------------------------------------------------------------------
; A platform at rest is only an image, so it need not hold an entity: up to PK_MAX wait in a keeper, a plain entity that
; holds their still layer entries. Keepers flash them together from the level's clock (the original makes every platform
; as the level loads, so its platforms flash together), and make a platform's entity when the man steps on it, or when a
; shot or a blast reaches its cell (pk_shot, pk_wake). On level 8, 22 platforms at rest took 22 of its 39 entity slots, and
; a shot block then had none. A platform that respawns stays an entity once it has been woken, as before.
PK_N        equ E_DATA+0        ; platforms held
PK_SHOWN    equ E_DATA+1        ; the flash its images show: 0 red, 1 white
PK_LIST     equ E_DATA+2        ; PK_MAX of: cell x (1), cell y (1), still entry (2), object index (2, bit 15 = respawns)
PK_SIZE     equ 6
PK_MAX      equ 4
            assert PK_LIST+PK_MAX*PK_SIZE<=ENT_SIZE,"platform keeper record"
PK_FLASH    equ reg_ram+REG_BYTES   ; for all keepers: 1 while platforms show white
PK_FNEXT    equ reg_ram+REG_BYTES+1 ; when that next changes
PK_NEAR     equ 32              ; a platform this near the man keeps its keeper looking every tick

PlatformKeeper_vt fdb PlatformKeeper_Update,0,0,0,0

; The spawner's constructor for symbols 10 and 11. X=cell x, B=cell y, A=1 if it respawns, spawn_cursor=its object.
; Returns U=the keeper that now holds it, so the spawner marks it made. A platform past column 255, or with no room in a
; keeper or the still layer, is made the old way, as an entity (U=0 if there is no room for that either).
ExplodingPlatform_Spawn
            cmpx #256
            lbhs ExplodingPlatform_New
            pshs a,b,x          ; 0,s=A 1,s=B 2,s=X
            ldy #ent_pool
            ldb <ent_count
.find       ldx E_VT,y
            cmpx #PlatformKeeper_vt
            bne .fnext
            lda PK_N,y
            cmpa #PK_MAX
            blo .room
.fnext      leay ENT_SIZE,y
            decb
            bne .find
            ; A new keeper, where this platform is.
            ldx 2,s
            ldb 1,s
            ldy #PlatformKeeper_vt
            lbsr nt_new_plain
            beq .old
            lbsr nt_keep
            lbsr pk_clock
            tfr u,y
.room       tfr y,u
            ; Its image, in the flash the others show now.
            ldd #SPR_EP_RED
            tst PK_FLASH
            beq .red
            ldd #SPR_EP_WHITE
.red        pshs d
            lda 5,s             ; cell x (its low byte)
            ldb #12
            mul
            tfr d,x
            lda 3,s             ; cell y
            ldb #12
            mul
            tfr d,y
            puls d
            jsr Still_AddStatic
            beq .old
            lda PK_N,u
            ldb #PK_SIZE
            mul
            leay d,u
            leay PK_LIST,y
            stx 2,y
            lda 3,s
            sta ,y
            lda 1,s
            sta 1,y
            ldd <spawn_cursor
            tst ,s
            beq .once
            ora #$80
.once       std 4,y
            inc PK_N,u
            leas 4,s
            andcc #$FB
            rts
.old        puls a,b,x
            lbra ExplodingPlatform_New

; U=keeper. The flash all keepers show, from the level's clock: white for EXPLAT_FLASH_T of every EXPLAT_IDLE_T ticks.
pk_clock    ldd <now
            subd <level_start_t
.big        cmpd #EXPLAT_IDLE_T*10
            blo .small
            subd #EXPLAT_IDLE_T*10
            bra .big
.small      cmpd #EXPLAT_IDLE_T
            blo .mod
            subd #EXPLAT_IDLE_T
            bra .small
.mod        pshs b              ; ticks into this second
            clr PK_FLASH
            ldb #EXPLAT_IDLE_T
            lda ,s
            cmpa #EXPLAT_FLASH_T
            bhs .rest
            inc PK_FLASH
            ldb #EXPLAT_FLASH_T
.rest       subb ,s+
            clra
            addd <now
            std PK_FNEXT
            lda PK_FLASH
            sta PK_SHOWN,u
            rts

PlatformKeeper_Update
            lda PK_N,u
            lbeq nt_deactivate  ; nothing left: it has no object to mark, so it is only freed
            ; The flash, for all keepers: whichever runs first moves it on.
            ldd <now
            subd PK_FNEXT
            bmi .flashed
            lda PK_FLASH
            eora #1
            sta PK_FLASH
            ldb #EXPLAT_IDLE_T-EXPLAT_FLASH_T
            tsta
            beq .long
            ldb #EXPLAT_FLASH_T
.long       clra
            addd PK_FNEXT
            std PK_FNEXT
.flashed    lda PK_FLASH
            cmpa PK_SHOWN,u
            beq .shown
            sta PK_SHOWN,u
            leay PK_LIST,u
            ldb PK_N,u
.swap       pshs b,y            ; Still_Swap uses Y
            ldx 2,y
            ldd #SPR_EP_RED
            tst PK_SHOWN,u
            beq .sred
            ldd #SPR_EP_WHITE
.sred       jsr Still_Swap
            puls b,y
            leay PK_SIZE,y
            decb
            bne .swap
            ; Each platform: gone far from the view, or the man stepping on it.
.shown      clr <t5             ; set when one is near the man
            leay PK_LIST,u
            clrb
.each       cmpb PK_N,u
            lbhs .done
            pshs b
            lda ,y
            ldb #12
            mul
            addd #6
            std <t3             ; its x
            lda 1,y
            ldb #12
            mul
            addd #6
            std <t4             ; its y
            ldd <t3
            subd <cam_x
            jsr Abs_D
            cmpd #DESPAWN_DIST
            bhi .far
            ldd <t4
            subd <cam_y
            jsr Abs_D
            cmpd #DESPAWN_DIST
            bhi .far
            ldd <man_x
            subd <t3
            addd #PK_NEAR
            cmpd #PK_NEAR*2
            bhi .next
            ldd <man_y
            subd <t4
            addd #PK_NEAR
            cmpd #PK_NEAR*2
            bhi .next
            inc <t5
            ; ExplodingPlatform_Update's test at rest.
            ldd <man_x
            subd <t3
            addd #8
            cmpd #(8)*2
            bhi .next
            ldd <man_y
            subd <t4
            addd #9
            cmpd #(9)*2
            bhi .next
            ldd <t4
            subd #8
            cmpd <man_y
            ble .next
            lbsr pk_make
            inc <t5             ; making an entity used t5: the man is near, still
            tstb                ; pk_make's answer, kept in B
            beq .next           ; no room for its entity: it tries again next tick
            lda #1              ; it counts down, as though it had been an entity all along
            sta EXPLAT_STATE,x
            ldd <now
            std E_START,x
            pshs u
            tfr x,u
            lbsr nt_keep
            puls u
            lda #SND_WARNING_BEEP
            jsr Sound_Play
            puls b
            lbra .each          ; the last one has taken its place
.far        ldx 2,y
            jsr Still_Release
            ldd 4,y
            anda #$7F
            cmpd <spawn_lo      ; inside the spawner's window: it looks again
            blo .forget
            cmpd <spawn_hi
            bhs .forget
            inc spawn_ev
.forget     ldx #obj_spawned
            jsr bit_clear
            lbsr pk_drop
            puls b
            lbra .each
.next       leay PK_SIZE,y
            puls b
            incb
            lbra .each
            ; With the man far from all of them, nothing changes before the flash does, for a few ticks.
.done       tst <t5
            bne .out
            ldd PK_FNEXT
            subd <now
            subd #1
            ble .out
            cmpd #3
            bls .w
            ldb #3
.w          stb E_WAIT,u
.out        rts

; U=keeper, Y=one of its platforms: makes the platform's entity, at rest, gives up its image and drops it from the list.
; Returns X=the entity and B=1; or B=0 if there was no room. Keeps U and Y.
pk_make     pshs u,y
            lda 4,y             ; respawns? Bit 15 of its object index, into the carry
            rola
            lda #0              ; not clra, which clears the carry
            rola
            pshs a
            clra
            ldb ,y
            tfr d,x
            ldb 1,y
            puls a
            lbsr ExplodingPlatform_New
            beq .none
            ldy ,s              ; pshs u,y put Y at 0,s and U at 2,s
            ldd 4,y
            anda #$7F
            std E_OBJ,u
            tfr u,x
            ldu 2,s
            pshs x
            ldx 2,y
            jsr Still_Release
            bsr pk_drop
            puls x
            ldb #1
            puls u,y,pc
.none       clrb
            puls u,y,pc

; U=keeper, Y=one of its platforms: the last takes its place. Keeps U and Y.
pk_drop     dec PK_N,u
            lda PK_N,u
            ldb #PK_SIZE
            mul
            leax d,u
            leax PK_LIST,x
            ldd ,x
            std ,y
            ldd 2,x
            std 2,y
            ldd 4,x
            std 4,y
            rts

; U=a laser in a platform's cell (laser_hits). A platform at rest there becomes its entity now, so the box test can hit
; it. A shot at the man passes platforms by. Keeps U.
pk_shot     lda L_TARGET,u
            cmpa #ALLIES
            beq pk_none
            ldd L_Y,u
            jsr Div12
            pshs b
            ldd L_X,u
            jsr Div12
            tfr d,x
            puls b
; X=cell x, B=cell y (Area_Blocks): a platform at rest there, if a keeper holds it, becomes its entity, and a target
; at once. Keeps U.
pk_wake     cmpx #256
            bhs pk_none
            pshs b,x,u          ; 0,s=cell y 1,s=cell x (word) 3,s=caller's U
            ldu #ent_pool
            lda <ent_count
            pshs a              ; 0,s=slots left 1,s=cell y 2,s=cell x 4,s=U
.keeper     ldx E_VT,u
            cmpx #PlatformKeeper_vt
            bne .knext
            leay PK_LIST,u
            ldb PK_N,u
            beq .knext
.entry      lda ,y
            cmpa 3,s            ; cell x, low byte
            bne .enext
            lda 1,y
            cmpa 1,s
            beq .found
.enext      leay PK_SIZE,y
            decb
            bne .entry
.knext      leau ENT_SIZE,u
            dec ,s
            bne .keeper
            leas 4,s
            puls u,pc
.found      lbsr pk_make
            tstb
            beq .gone
            tfr x,u
            jsr target_add
.gone       leas 4,s
            puls u,pc
pk_none     rts

; Bank 11 (from pools.asm, for room in fixed ROM): AreaEffect_New calls it with FAR. U=an area effect: every block it overlaps becomes a real entity now, so the box test can hit it. A blast has no one cell, and a
; level's way out can depend on one. With no room for an entity, a blast that would kill the block still does, without its debris.
Area_Blocks ldd <t0              ; a caller may be counting on these, and making an entity uses them
            pshs d
            ldd <t1
            pshs d
            ldd <t2
            pshs d
            ldd <t3
            pshs d
            ldd <t4
            pshs d
            ldd <t5
            pshs d
            leas -10,s          ; 0 cell x, 2 first cell x, 4 last cell x, 6 cell y, 7 last cell y, 8 reach
            ldb L_SIZEX,u
            clra
            std 8,s
            ldd L_X,u
            addd 8,s
            jsr Div12
            std 4,s
            ldd L_X,u
            subd 8,s
            bpl .x0
            ldd #0
.x0         jsr Div12
            std 2,s
            ldd L_Y,u
            addd 8,s
            jsr Div12
            stb 7,s
            ldd L_Y,u
            subd 8,s
            bpl .y0
            ldd #0
.y0         jsr Div12
            stb 6,s
.row        ldd 2,s
            std ,s
.col        ldx ,s
            ldb 6,s
            jsr Main_GetCell
            cmpa #EXPLODING_PLATFORM
            bne .block
            ldx ,s              ; a platform at rest: its entity now, for the blast to hit (pk_wake)
            ldb 6,s
            lbsr pk_wake
            bra .next
.block      cmpa #PLATFORM_DESTRUCTIBLE
            bne .next
            lda <cell_raw
            sta <block_buried
            ldd ,s
            std <block_x
            ldb 6,s
            stb <block_y
            jsr block_make
            tsta
            bne .next
            lda L_DAMAGE,u
            cmpa #48
            blo .next
            clra                ; EMPTY
            ldx ,s
            ldb 6,s
            jsr Main_SetCellType
            ldx ,s
            ldb 6,s
            jsr Terrain_Hole
.next       ldd ,s
            addd #1
            std ,s
            cmpd 4,s
            bls .col
            inc 6,s
            lda 6,s
            cmpa 7,s
            bls .row
            leas 10,s
            puls d
            std <t5
            puls d
            std <t4
            puls d
            std <t3
            puls d
            std <t2
            puls d
            std <t1
            puls d
            std <t0
            rts

; ---- PlatformDestructible.as ----------------------------------------------------------------
PLATD_CRYSTAL equ E_DATA+0
PLATD_SHOWN equ E_DATA+1        ; its sprite is in the display list, over the terrain's image of it
PLATD_LIFE  equ 60              ; 2 s after the last hit it goes back to being terrain, and the slot is free

PlatformDestructible_vt fdb PlatformDestructible_Update,PlatformDestructible_Hurt,PlatformDestructible_Die,PlatformDestructible_DeathEffect,PlatformDestructible_HitEffect

; A=1 if a crystal is buried here. The cell is in the ROM grid already, so it is not marked here.
PlatformDestructible_New
            pshs a
            lda #KIND_NEUTRAL
            sta <t2
            puls a
            ldy #PlatformDestructible_vt
            lbsr nt_new_k
            beq .out
            sta PLATD_CRYSTAL,u
            ldd #48
            std E_HEALTH,u
            lda #6
            sta E_SIZEX,u
            sta E_SIZEY,u
            lbsr nt_keep        ; it must run to give its slot back
            ldd <now
            std E_START,u
            andcc #$FB
.out        rts

; A block is terrain, and this record exists only while it is being shot at. It draws itself only to flash. Each tick the
; list has a sprite over a block costs as much as any other sprite, and a level of blocks would fill the entity pool.
PlatformDestructible_Update
            NT_LIVE
            lda E_FLAGS,u
            bita #EF_FLASHING
            beq .plain
            lda #1
            sta PLATD_SHOWN,u
            ldd #131
            jmp Alien_DrawSelf
            ; Present is about to erase the sprite, and the terrain's image with it.
.plain      tst PLATD_SHOWN,u
            beq .idle
            clr PLATD_SHOWN,u
            ldx E_X,u
            ldy E_Y,u
            jsr Block_Heal
.idle       ldd <now
            subd E_START,u
            cmpd #PLATD_LIFE
            blo .out
            lbra nt_deactivate
.out        rts

PlatformDestructible_Hurt
            ldd <now
            std E_START,u
            ldd E_HEALTH,u
            subd <hurt_damage
            std E_HEALTH,u
            bgt .alive
            jmp Entity_Die
.alive      lbsr nt_hurt_pos
            tfr x,d
            tfr y,x
            jmp Entity_HitEffect

PlatformDestructible_HitEffect
            lda #SND_MACHINE_HIT
            jsr Sound_Play
            ldx <hit_x
            ldy <hit_y
            ldd #BIT_GRAVITY_32*256+1 ; narrow spread
            lbsr nt_debris
            lbra nt_flash

PlatformDestructible_DeathEffect
            lda #SND_QUIET_EXPLOSION
            jsr Sound_Play
            ldd #53
            std <arg0
            ldx E_X,u
            ldy E_Y,u
            jsr DeathFlash_New
            ldx E_X,u
            ldy E_Y,u
            ldd #$1010
            jmp Explosion_New

PlatformDestructible_Die
            jsr Entity_DeathEffect
            jsr Ent_MarkDead
            ldd E_Y,u
            jsr Div12
            pshs b
            ldd E_X,u
            jsr Div12
            tfr d,x
            puls b
            pshs b,x
            clra                ; EMPTY
            jsr Main_SetCellType
            puls b,x
            jsr Terrain_Hole    ; the block was part of the static terrain
            tst PLATD_CRYSTAL,u
            bne .crystal
            lbra nt_deactivate
            ; The record turns into the crystal, in the same place. The C allocates a new one, but with the pool full
            ; that would lose an extra life for good, since this object is already marked dead.
.crystal    ldd #Crystal_vt
            std E_VT,u
            lda #KIND_ENTITY
            sta E_KIND,u
            lda #EF_ACTIVE
            sta E_FLAGS,u
            ldd #$FFFF
            std E_OBJ,u
            clr CRYSTAL_ANIM,u
            clr CRYSTAL_REST,u
            rts

; ---- GroupedBurstTurret.as ------------------------------------------------------------------
GBT_CHARGED equ E_DATA+2
GBT_INDEX   equ E_DATA+3
GBT_OWNER   equ E_DATA+4
GBT_PEND    equ E_DATA+6        ; its shot found no room in the laser pool: it tries again each tick
GBT_FIRET   equ E_DATA+7        ; the low byte of the tick it fired at
GBT_LATE_MAX equ 24             ; a shot held this long would be at the floor
GBT_CHARGESPR equ 316
GBT_L4_SPEED equ 410            ; LASER4_SPEED_1, 48 px/s

GroupedBurstTurret_vt fdb GroupedBurstTurret_Update,GroupedBurstTurret_Hurt,0,0,0

; X=cell x, B=cell y, arg0=(hx, hy). U=record or 0. Not in the spawn table: the controller makes these.
GroupedBurstTurret_New
            ldy #GroupedBurstTurret_vt
            lbsr nt_new_alien
            beq .out
            ldd <arg0
            std NT_HX,u
            tsta
            beq .upright
            ldd #164
            std E_SPRITE,u
            lda NT_HX,u
            lbsr nt_off6
            addd E_X,u
            std E_X,u
            bra .rest
.upright    ldd #165
            std E_SPRITE,u
            lda NT_HY,u
            lbsr nt_off6
            addd E_Y,u
            std E_Y,u
.rest       ldd <now
            std E_START,u
            clr GBT_PEND,u
            ldd #48
            std E_HEALTH,u
            lda #8
            sta E_SCORE,u
            lda #2
            sta E_SIZEX,u
            lda #3
            sta E_SIZEY,u
            tst NT_HX,u
            beq .made
            jsr Main_AddToKillCount
.made       andcc #$FB
.out        rts

GroupedBurstTurret_Update
            NT_LIVE
            tst GBT_PEND,u
            beq .charge
            ldb <now+1
            subb GBT_FIRET,u
            cmpb #GBT_LATE_MAX
            bhs .drop
            bsr nt_gbt_shot
            beq .charge
.drop       clr GBT_PEND,u
.charge     tst GBT_CHARGED,u
            beq .body
            ldb #1
            lbsr nt_hxy
            ldd #GBT_CHARGESPR
            lbsr nt_draw_at
            ldd E_SPRITE,u
            lbra nt_still_sprite
            ; It never moves or changes, and the controller wakes it: at rest it is only an image.
.body       ldd E_SPRITE,u
            lbsr nt_still_sprite
            ldx E_STILL,u
            beq .out
            tst GBT_PEND,u
            bne .out
            lda #255
            sta E_WAIT,u
.out        rts

GroupedBurstTurret_Hurt
            lbra nt_nodamage

; U=turret.
nt_gbt_prepare
            clr E_WAIT,u
            lda NT_HX,u
            asla
            ldb NT_HY,u
            aslb
            stu <arg0
            jsr Charge_New
            lda #1
            sta GBT_CHARGED,u
            lda #SND_CHARGE
            lbra nt_sound_near

nt_gbt_fire lda #SND_ALIEN_FIRE
            lbsr nt_sound_near
            lda <now+1
            sta GBT_FIRET,u
            bsr nt_gbt_shot
            bne .made
            ; A row's volley is a gate the man times his run by. The last volley's shots hold most of the pool until
            ; they land, a few ticks from now: this one waits for room, and starts where it would be by then.
            lda #1
            sta GBT_PEND,u
            clr E_WAIT,u
.made       ldb #2
            lbsr nt_hxy
            jsr SmallFlash_New
            clr GBT_CHARGED,u
            rts

; The turret's shot, as far along as it would have gone since GBT_FIRET. Z set if there was no room for it.
nt_gbt_shot ldb <now+1
            subb GBT_FIRET,u
            pshs b
            lda #GBT_L4_SPEED-256
            mul
            adda ,s+            ; pixels gone: 410/256 a tick
            pshs a
            adda #12
            tfr a,b
            lbsr nt_hxy         ; where it heads: a cell on from there
            stx <arg0
            sty <arg1
            puls b
            lbsr nt_hxy
            ldd #GBT_L4_SPEED
            ; The governor's cap on shots would leave gaps in the volley.
            inc gov_free
            jsr Laser4_New
            pshs cc
            clr gov_free
            puls cc
            beq .no
            lda L_FLAGS,x
            anda #~LF_CANCEL&$FF
            sta L_FLAGS,x
            andcc #$FB
.no         rts

; ---- GroupedTurretController.as -------------------------------------------------------------
; The turrets never die, so the controller finds them by scanning the pool, and needs only its mask of who fires.
GTC_FIRET   equ E_DATA+0
GTC_COUNT   equ E_DATA+1
GTC_CHARGED equ E_DATA+2
GTC_BITS    equ E_DATA+3        ; 4 bytes
GTC_MAX     equ 32              ; no more can exist; the longest row in the levels is 21
GTC_LOOK_T  equ 15
GTC_FIRE_H  equ 41              ; 1375 ms
GTC_FIRE_V  equ 29              ; 968.75 ms
GTC_CHARGE_T equ 11             ; 375 ms

GroupedTurretController_vt fdb GroupedTurretController_Update,0,0,0,0

; LAZY: its turrets have no object of their own, so the controller stays in memory while it is near and takes them with
; it when it goes (nt_gtc_release). If the row does not fit in the pool it returns U=0, and the spawner tries again later.
GroupedTurretController_New
            pshs b,x            ; 0,s=y 1,s=x
            lbsr nt_heading
            pshs d              ; 0,s=hx 1,s=hy 2,s=y 3,s=x
            clra
            pshs a              ; 0,s=count 1,s=hx 2,s=hy 3,s=y 4,s=x
            ; Count the row: wall behind, empty here.
.count      lda ,s
            cmpa #GTC_MAX
            bhs .counted
            lbsr .cellxy
            pshs b,x            ; 0,s=cell y 1,s=cell x 3,s=count 4,s=hx 5,s=hy
            ldb 4,s
            sex
            pshs d
            ldd 3,s             ; cell x, with the 2 bytes just pushed
            subd ,s++
            tfr d,x
            ldb ,s
            subb 5,s
            jsr Main_GetCell
            cmpa #PLATFORM
            puls b,x
            bne .counted
            jsr Main_GetCell
            tsta
            bne .counted
            inc ,s
            bra .count
.counted    lda ,s
            inca
            lbsr nt_room
            bne .full
            ldx 4,s
            ldb 3,s
            ldy #GroupedTurretController_vt
            lbsr nt_new_plain
            beq .fail
            lbsr nt_keep
            lda ,s
            sta GTC_COUNT,u
            ldb #GTC_FIRE_H
            tst 1,s
            bne .ftime
            ldb #GTC_FIRE_V
.ftime      stb GTC_FIRET,u
            tfr b,a
            clrb
            lbsr nt_lattice
            ; Build the turrets, last to first.
.build      dec ,s
            bmi .done
            bsr .cellxy
            ldy 1,s
            sty <arg0
            pshs u
            lbsr GroupedBurstTurret_New
            tfr u,x
            puls u
            cmpx #0
            beq .build
            stu GBT_OWNER,x
            lda ,s
            sta GBT_INDEX,x
            bra .build
.done       leas 6,s
            lbra nt_gtc_prefill
.full       ldu #0
.fail       leas 6,s
            rts
            ; Returns X, B = the count'th cell of the row. With the return address on top: 2,s=count 3,s=hx 4,s=hy 5,s=y 6,s=x.
.cellxy     tst 3,s
            beq .across
            ldx 6,s             ; the row runs down
            ldb 5,s
            addb 2,s
            rts
.across     ldb 2,s
            clra
            addd 6,s
            tfr d,x
            ldb 5,s
            rts

; A row far from the camera gives its slots back, turrets included, and returns to the object list. The turrets cannot
; be killed, so building the row again later loses nothing. A row that is charging waits, because its charge effects
; follow the turrets. Far means beyond the despawn distance plus the length of the row, which may run toward the camera,
; and for a row firing sideways the reach of its shots too, so that far_rows does not make it again straight away.
nt_gtc_release
            tst GTC_CHARGED,u
            bne .stay
            ldb GTC_COUNT,u
            lda GTC_FIRET,u
            cmpa #GTC_FIRE_H
            bne .down
            addb #21            ; a row firing sideways: as far again as its shots reach, as far_rows makes it
.down       lda #12
            mul
            addd #DESPAWN_DIST
            pshs d
            ldd E_X,u
            subd <cam_x
            jsr Abs_D
            cmpd ,s
            bhi .far
            ldd E_Y,u
            subd <cam_y
            jsr Abs_D
            cmpd ,s
            bhi .far
            leas 2,s
.stay       rts
.far        leas 2,s
            ldy #ent_pool
            lda <ent_count
            pshs a
.next       ldd E_VT,y
            cmpd #GroupedBurstTurret_vt
            bne .skip
            cmpu GBT_OWNER,y
            bne .skip
            ldx E_STILL,y
            beq .nostill
            pshs y
            jsr Still_Release
            puls y
.nostill    clr E_VT,y
            clr E_VT+1,y
            jsr spawn_room
.skip       leay ENT_SIZE,y
            dec ,s
            bne .next
            leas 1,s
            ldd E_OBJ,u
            cmpd #$FFFF
            beq .gone
            jsr ent_forget
.gone       lbsr nt_deactivate
            leas 2,s            ; straight back to the entity pass: there is no controller left to update
            rts

; X=routine. Calls it with U=turret for every turret of the controller U whose bit is set. Keeps U.
nt_gtc_each pshs u,x
            ldy #ent_pool
            lda <ent_count
            pshs a,y            ; 0,s=left 1,s=record 3,s=routine 5,s=controller
.next       ldu 1,s
            ldd E_VT,u
            cmpd #GroupedBurstTurret_vt
            bne .skip
            ldd GBT_OWNER,u
            cmpd 5,s
            bne .skip
            ldb GBT_INDEX,u
            clra
            ldx 5,s
            leax GTC_BITS,x
            jsr bit_test
            beq .skip
            jsr [3,s]
.skip       ldu 1,s
            leau ENT_SIZE,u
            stu 1,s
            dec ,s
            bne .next
            leas 3,s
            puls x,u,pc

GroupedTurretController_Update
            NT_LIVE
            lbsr nt_gtc_release
            ldd <now
            subd E_START,u
            tst GTC_CHARGED,u
            bne .wait
            pshs d
            ldb GTC_FIRET,u
            subb #GTC_CHARGE_T
            clra
            cmpd ,s++
            bgt .rest
            lda #1
            sta GTC_CHARGED,u
            bsr nt_gtc_pick
            ldx #nt_gbt_prepare
            bra nt_gtc_each
.wait       pshs d
            ldb GTC_FIRET,u
            clra
            cmpd ,s++
            bgt .rest
            clr GTC_CHARGED,u
            ldd <now
            std E_START,u
            ldx #nt_gbt_fire
            lbra nt_gtc_each
            ; D=when it next acts. It waits for that tick, but looks now and then at how far off it is.
.rest       subd <now
            addd E_START,u
            subd #1
            ble .out
            tsta
            bne .long
            cmpb #GTC_LOOK_T
            bls .w
.long       ldb #GTC_LOOK_T
.w          stb E_WAIT,u
.out        rts

; Who fires this volley: everybody, except one random turret in each group of three.
nt_gtc_pick leax GTC_BITS,u
            ldb #4
            lda #$FF
.fill       sta ,x+
            decb
            bne .fill
            clra                ; first turret of the group
.group      cmpa GTC_COUNT,u
            bhs .out
            pshs a
            lda #3
            lbsr nt_rnd
            addb ,s
            cmpb GTC_COUNT,u
            bhs .nextg
            clra
            leax GTC_BITS,u
            jsr bit_clear
.nextg      puls a
            adda #3
            bra .group
.out        rts

; LAZY: the C's rows fire from the level's start, so a row made only now, as the view comes near, would leave its
; corridor empty where the original's is full of shots. This makes the shots of its past volleys that would still be in
; flight, where they would be: newest first, while the age fits a byte, and at most GTC_PREFILL of them, for the pool.
GTC_AGE     equ E_DATA+7
GTC_LEFT    equ E_DATA+8
GTC_PREFILL equ 10
GTC_AGE_MAX equ 159             ; nt_gbt_shot's distance is a byte: 159 ticks is 254 px
nt_gtc_prefill
            lda #GTC_PREFILL
            sta GTC_LEFT,u
            ldd <now
            subd E_START,u      ; ticks since its last volley time
.vol        cmpd #GTC_AGE_MAX
            bhi .out
            stb GTC_AGE,u
            ; Fired after the level began? The first volley is a period in.
            ldd <now
            subd <level_start_t
            subb GTC_AGE,u
            sbca #0
            subb GTC_FIRET,u
            sbca #0
            bmi .out
            bsr nt_gtc_pick
            ldx #nt_gtc_ghost
            lbsr nt_gtc_each
            ldb GTC_AGE,u
            clra
            addb GTC_FIRET,u
            adca #0
            bra .vol
.out        rts

; U=turret: its shot of the volley GTC_AGE ticks ago, unless a wall has stopped it or it would be on the man.
nt_gtc_ghost
            ldx GBT_OWNER,u
            tst GTC_LEFT,x
            beq .done
            ldb GTC_AGE,x
            pshs b
            lda #GBT_L4_SPEED-256
            mul
            adda ,s             ; pixels gone, as nt_gbt_shot works it out
            pshs a              ; 0,s=distance 1,s=age
            tfr a,b
.walk       pshs b
            lbsr nt_hxy
            tfr y,d
            jsr Div12
            pshs b
            tfr x,d
            jsr Div12
            tfr d,x
            puls b
            jsr Main_GetCell
            puls b
            deca                ; PLATFORM or PLATFORM_DESTRUCTIBLE stops it
            cmpa #PLATFORM_DESTRUCTIBLE-1
            bls .no
            subb #12
            bcc .walk
            ldb ,s
            lbsr nt_hxy
            tfr x,d
            subd <man_x
            addd #24
            cmpd #48
            bhs .make
            tfr y,d
            subd <man_y
            addd #24
            cmpd #48
            blo .no
.make       ldb <now+1
            subb 1,s
            stb GBT_FIRET,u
            lbsr nt_gbt_shot
            beq .no
            ldx GBT_OWNER,u
            dec GTC_LEFT,x
.no         leas 2,s
.done       rts

; ---- ambushes -------------------------------------------------------------------------------
; LAZY: an ambush may be spawned after the man has already passed its trigger, when the object list's slow walk gets to
; it late. So each ambush's first look also accepts the last trip of this level. An ambush that existed at that trip
; has either run or stays in memory, so this cannot fire one twice.
AMBUSH_FRESH equ E_DATA+0
AMBUSH_STATE equ E_DATA+1       ; 0 active, 1 suspended
AMBUSH_CELLX equ E_DATA+2
AMBUSH_CELLY equ E_DATA+4
AMBUSH_COUNT equ E_DATA+5
AMBUSH_NEXT equ E_DATA+6        ; ticks
AMBUSH_MADE equ E_DATA+7
AMBUSH_VT   equ E_DATA+8        ; the children's class, to tell whether a record is still that child
AMBUSH_KIDS equ E_DATA+10       ; up to 8 pointers
AMBUSH_KID_MAX equ 8
AMBUSH_WAIT_T equ 4             ; 125 ms

; Z set if the trigger has tripped within range.
nt_triggered
            tst AMBUSH_FRESH,u
            beq .flag
            clr AMBUSH_FRESH,u
            tst trigger_any
            bne .range
.flag       tst trigger_flag
            beq .no
.range      ldd trigger_x
            subd E_X,u
            jsr Abs_D
            cmpd #TRIGGER_RANGE
            bgt .no
            ldd trigger_y
            subd E_Y,u
            jsr Abs_D
            cmpd #TRIGGER_RANGE
            bgt .no
            orcc #$04
            rts
.no         andcc #$FB
            rts

; Y=class, X, B=cell, A=child count. Common construction: suspended, remembers its cell.
nt_ambush_new
            lbsr nt_new_plain
            beq .out
            sta AMBUSH_COUNT,u
            stx AMBUSH_CELLX,u
            stb AMBUSH_CELLY,u
            lda #1
            sta AMBUSH_STATE,u
            sta AMBUSH_FRESH,u
            ldd <now
            std E_START,u
            andcc #$FB
.out        rts

; Children exist from the start. LAZY: they have no object of their own, so an ambush that holds them is never forgotten,
; or it would raise a second squad. Without room for the whole squad it returns U=0 for the spawner to retry.
nt_child_ambush_new
            pshs a,b,x
            inca
            lbsr nt_room
            puls a,b,x
            bne .full
            bsr nt_ambush_new
            beq .out
            lbsr nt_keep
            andcc #$FB
            rts
.full       ldu #0
            orcc #$04
.out        rts

; X=child, just made, U=ambush. Z set if there is none, or the squad is complete. Otherwise records it and leaves X.
nt_kid_store
            cmpx #0
            beq .end
            ldb AMBUSH_MADE,u
            cmpb #AMBUSH_KID_MAX
            bhs .end
            ldd E_VT,x
            std AMBUSH_VT,u
            ldb AMBUSH_MADE,u
            aslb
            addb #AMBUSH_KIDS
            clra
            leay d,u
            stx ,y
            inc AMBUSH_MADE,u
            andcc #$FB
            rts
.end        lda AMBUSH_MADE,u
            sta AMBUSH_COUNT,u
            orcc #$04
            rts

; A=index. X=that child, Z clear; or Z set if its record no longer holds that child.
nt_kid_get  asla
            adda #AMBUSH_KIDS
            tfr a,b
            clra
            leax d,u
            ldx ,x
            ldd E_VT,x
            cmpd AMBUSH_VT,u
            beq .ok
            orcc #$04
            rts
.ok         andcc #$FB
            rts

; The common switch to ACTIVE. LAZY: from here on it has spent children, so it may not be forgotten and rebuilt.
nt_ambush_go
            clr AMBUSH_STATE,u
            clr AMBUSH_NEXT,u
            ldd <now
            std E_START,u
            lbra nt_keep

; AMBUSH_SUSPENDED of the children's ambushes.
nt_child_suspended
            ldd <now
            subd E_START,u
            cmpd #AMBUSH_WAIT_T
            ble .out
            lbsr nt_triggered
            beq nt_ambush_go
            lda #255            ; a trigger tripping wakes it
            sta E_WAIT,u
.out        rts

; After a child wakes: ends at zero, and sets the next delay of 250 to 750 ms.
nt_child_step
            lda AMBUSH_COUNT,u
            bgt .more
            lbsr nt_deactivate
.more       ldd <now
            std E_START,u
            lda #15
            lbsr nt_rnd
            addb #8
            stb AMBUSH_NEXT,u
            rts

; Z set if the next child is due.
nt_child_due
            ldd <now
            subd E_START,u
            pshs d
            ldb AMBUSH_NEXT,u
            clra
            cmpd ,s++
            bgt .no
            orcc #$04
            rts
.no         andcc #$FB
            rts

; B=amount. t2 -= B.
nt_t2_sub   clra
            pshs d
            ldd <t2
            subd ,s++
            std <t2
            rts

; ---- ExplodingHopperAmbush.as ---------------------------------------------------------------
EXPHOPPERA_COUNT equ 5
EXPHOPPERA_T equ 30             ; 1000 ms

ExplodingHopperAmbush_vt fdb ExplodingHopperAmbush_Update,0,0,0,0

ExplodingHopperAmbush_New
            lda #EXPHOPPERA_COUNT
            ldy #ExplodingHopperAmbush_vt
            lbra nt_ambush_new

ExplodingHopperAmbush_Update
            NT_LIVE
            tst AMBUSH_STATE,u
            bne .wait
            ldd <now
            subd E_START,u
            cmpd #EXPHOPPERA_T
            blt .out
            pshs u
            ldx AMBUSH_CELLX,u
            ldb AMBUSH_CELLY,u
            clra
            FAR ExplodingHopper_New
            cmpu #0
            beq .none
            lda #HOPS_HOP       ; the AS passes Hopper.HOP
            FAR ExplodingHopper_SwitchState
            puls u
            dec AMBUSH_COUNT,u
            bgt .again
            lbsr nt_deactivate
.again      ldd <now
            std E_START,u
            rts
.none       puls u
            rts
.wait       lbsr nt_triggered
            bne .out
            lbra nt_ambush_go
.out        rts

; ---- HeavyTrooperAmbush.as ------------------------------------------------------------------
HeavyTrooperAmbush_vt fdb HeavyTrooperAmbush_Update,0,0,0,0

; A=child count.
HeavyTrooperAmbush_New
            ldy #HeavyTrooperAmbush_vt
            lbsr nt_child_ambush_new
            beq .out
.loop       lda AMBUSH_MADE,u
            cmpa AMBUSH_COUNT,u
            bhs .made
            pshs u
            ldx AMBUSH_CELLX,u
            ldb AMBUSH_CELLY,u
            clra
            FAR TrooperHeavy_New
            tfr u,x
            puls u
            lbsr nt_kid_store
            beq .made
            ; x = center - spread + random * 2 * spread, spread = count / 3 * 12 = count * 4.
            pshs x
            ldd E_X,u
            std <t2
            lda AMBUSH_COUNT,u
            ldb #4
            mul
            pshs b
            lbsr nt_t2_sub
            lda ,s+
            asla
            lbsr nt_rnd
            addd <t2
            puls x
            std E_X,x
            pshs u
            tfr x,u
            lda #1
            FAR TrooperHeavy_SetPuppet
            lda #THVS_DEAD
            FAR TrooperHeavy_SwitchState
            puls u
            bra .loop
.made       andcc #$FB
.out        rts

HeavyTrooperAmbush_Update
            NT_LIVE
            tst AMBUSH_STATE,u
            bne .wait
            lbsr nt_child_due
            bne .out
            dec AMBUSH_COUNT,u
            bmi .step
            lda AMBUSH_COUNT,u
            lbsr nt_kid_get
            beq .step
            pshs u
            tfr x,u
            lda #THVS_GETUP
            FAR TrooperHeavy_SwitchState
            clra
            FAR TrooperHeavy_SetPuppet
            puls u
.step       lbra nt_child_step
.wait       lbra nt_child_suspended
.out        rts

; ---- ZomboidAmbush.as -----------------------------------------------------------------------
ZomboidAmbush_vt fdb ZomboidAmbush_Update,0,0,0,0

; A=child count.
ZomboidAmbush_New
            ldy #ZomboidAmbush_vt
            lbsr nt_child_ambush_new
            lbeq .out
.loop       lda AMBUSH_MADE,u
            cmpa AMBUSH_COUNT,u
            bhs .made
            pshs u
            ldx AMBUSH_CELLX,u
            ldb AMBUSH_CELLY,u
            clra
            FAR Zomboid_New
            tfr u,x
            puls u
            lbsr nt_kid_store
            beq .made
            ; x = center - spread + r1 * 2 * spread - jitter + r2 * 2 * jitter, spread = (count - 1) * 4.
            pshs x
            lda AMBUSH_COUNT,u
            deca
            ldb #4
            mul
            pshs b              ; spread
            ldb #2
            lda AMBUSH_COUNT,u
            cmpa #1
            bls .jit
            ldb #6
.jit        pshs b              ; 0,s=jitter 1,s=spread 2,s=child
            ldd E_X,u
            std <t2
            ldb 1,s
            lbsr nt_t2_sub
            ldb ,s
            lbsr nt_t2_sub
            lda 1,s
            asla
            lbsr nt_rnd
            addd <t2
            std <t2
            lda ,s
            asla
            lbsr nt_rnd
            addd <t2
            leas 2,s
            puls x
            std E_X,x
            pshs u
            tfr x,u
            lda #1
            FAR Zomboid_SetPuppet
            lda #ZOMS_DEAD
            FAR Zomboid_SwitchState
            puls u
            bra .loop
.made       andcc #$FB
.out        rts

ZomboidAmbush_Update
            NT_LIVE
            tst AMBUSH_STATE,u
            bne .wait
            lbsr nt_child_due
            bne .out
            dec AMBUSH_COUNT,u
            bmi .step
            lda AMBUSH_COUNT,u
            lbsr nt_kid_get
            beq .step
            pshs u
            tfr x,u
            lda #ZOMS_GETUP
            FAR Zomboid_SwitchState
            clra
            FAR Zomboid_SetPuppet
            puls u
.step       lbra nt_child_step
.wait       lbra nt_child_suspended
.out        rts

; ---- FlierAmbush.as -------------------------------------------------------------------------
FlierAmbush_vt fdb FlierAmbush_Update,0,0,0,0

FlierAmbush_New
            clra
            ldy #FlierAmbush_vt
            lbra nt_ambush_new

FlierAmbush_Update
            NT_LIVE
            ldd <now
            subd E_START,u
            cmpd #AMBUSH_WAIT_T
            ble .out
            ldd <now
            std E_START,u
            lbsr nt_triggered
            bne .out
            pshs u
            ldx AMBUSH_CELLX,u
            ldb AMBUSH_CELLY,u
            clra
            FAR Flyer_New
            cmpu #0
            beq .full
            FAR Flyer_StartBeneathLava
            puls u
            ldy E_Y,u
            leay 6,y
            ldx E_X,u
            ldd #$1212
            jsr LavaSplash_New
            lbra nt_deactivate
            ; Pool full: the trip is still recorded, so look again as if new.
.full       puls u
            lda #1
            sta AMBUSH_FRESH,u
.out        rts

; ---- GoalElevator.as ------------------------------------------------------------------------
GOALEL_TIMER equ E_DATA+0
GOALEL_FLICKER equ E_DATA+1
GOALEL_HEIGHT equ E_DATA+2
GOALEL_PARTT equ E_DATA+3
GOALEL_WAIT equ 3               ; frames
GOALEL_PART_T equ 15            ; 500 ms
GOALEL_LIFT equ 133             ; 39 tiles/s^2 = 468 px/s^2

GoalElevator_vt fdb GoalElevator_Update,0,0,0,0

GoalElevator_New
            ldy #GoalElevator_vt
            lbsr nt_new_plain
            beq .out
            pshs b,x
.scan       ldx 1,s
            ldb ,s
            subb GOALEL_HEIGHT,u
            jsr Main_GetCell
            cmpa #PLATFORM
            beq .found
            inc GOALEL_HEIGHT,u
            bra .scan
.found      leas 3,s
            ldd <now
            std GOALEL_PARTT,u
            andcc #$FB
.out        rts

; The column, clipped to the view by hand: it can be taller than B can say.
nt_goalel_rect
            ldb GOALEL_HEIGHT,u
            beq .out
            lda #12
            mul
            std <t5             ; height
            ldd E_Y,u
            addd #6
            std <t4             ; bottom
            subd <t5
            std <t3             ; top
            cmpd <cam_top
            bge .topok
            ldd <cam_top
            std <t3
.topok      ldd <cam_top
            addd #VIEW_H
            cmpd <t4
            bge .botok
            std <t4
.botok      ldd <t4
            subd <t3
            ble .out
            pshs b
            ldy <t3
            ldd E_X,u
            subd #5
            tfr d,x
            lda #COLOR_BLUE
            sta <draw_color
            puls b
            lda #10
            jmp Draw_RectWorld
.out        rts

GoalElevator_Update
            NT_LIVE
            tst GOALEL_TIMER,u
            bgt .count
            com GOALEL_FLICKER,u
            lda #GOALEL_WAIT
            sta GOALEL_TIMER,u
.count      lda GOALEL_TIMER,u
            suba #2
            sta GOALEL_TIMER,u
            tst GOALEL_FLICKER,u
            bne .man
            bsr nt_goalel_rect
.man        ldd <man_x
            subd E_X,u
            pshs d              ; dx
            addd #(6)-1
            cmpd #((6)-1)*2
            bhi .far
            ldd <man_y
            subd E_Y,u
            pshs d              ; dy, with dx at 2,s
            addd #(16*12)-1
            cmpd #((16*12)-1)*2
            bhi .far2
            ldd <man_vy
            subd #GOALEL_LIFT
            std <man_vy
            ldd <man_y
            std <man_jump_y
            ldd 2,s
            addd #(4)-1
            cmpd #((4)-1)*2
            bhi .pull
            ; The C multiplies by 0.75 each frame: two frames make 0.5625 = 1/2 + 1/16.
            ldd <man_vx
            asra
            rorb
            std <t2
            asra
            rorb
            asra
            rorb
            asra
            rorb
            addd <t2
            std <man_vx
            bra .height
            ; speedX -= 5 * dx / framerate: dx * 1.42 in 8.8 per tick, near enough dx * 3 / 2.
.pull       ldd 2,s
            asra
            rorb
            addd 2,s
            pshs d
            ldd <man_vx
            subd ,s++
            std <man_vx
.height     ldb GOALEL_HEIGHT,u
            lda #6
            mul
            addd ,s             ; dy + 6 * height < 0: the man is above half way
            bge .far2
            lda #1
            sta <level_done
.far2       leas 2,s
.far        leas 2,s
            ldd <now
            subd GOALEL_PARTT,u
            cmpd #GOALEL_PART_T
            ble .out
            ldd <now
            std GOALEL_PARTT,u
            lda #8
            lbsr nt_rnd
            addd E_X,u
            subd #4
            tfr d,x
            ldd E_Y,u
            addd #6
            tfr d,y
            jmp GoalElevatorBit_New
.out        rts

; ---- ManCreator.as --------------------------------------------------------------------------
ManCreator_vt fdb ManCreator_Update,0,0,0,0

; A=heading, X=cell x, B=cell y. Called by the engine. The man is locked until this has run; with the pool full there is
; nothing to run it, so the controls are freed now rather than never.
ManCreator_New
            ldy #ManCreator_vt
            lbsr nt_new_plain
            bne .made
            clr <man_lock
            rts
.made       ldd E_X,u
            subd #6
            std E_X,u
            ldd E_Y,u
            subd #6
            std E_Y,u
            rts

ManCreator_Update
            NT_LIVE
            lbsr nt_onscreen
            bne .out
            clr <man_lock
            ldx E_X,u
            ldy E_Y,u
            jsr RespawnLocator_New
            lbra nt_deactivate
.out        rts

; ---- RemainsPlacer.as, TurretRemainsPlacer.as -------------------------------------------------
; LAZY: the C's remains are effects that live for the whole level, and a level has up to 69 of them against 40 effect slots.
; The placers hand the effect record to the spawner as U, so the effect can give its object back when the camera leaves it
; behind (FX_CULL, in effects.asm). No entity slot is used. The placer waits, returning U=0 for the spawner to retry, until
; its place is near the view and enough slots are free that explosions will not go short.
DECOR_NEAR_X equ 220
DECOR_NEAR_Y equ 170
DECOR_MIN_FREE equ 16           ; effect slots that must stay free

; X=cell x, B=cell y. Z set if a decoration may be made there now. Keeps X, B.
nt_decor_ok pshs b,x
            tfr x,d
            jsr Times12
            subd <cam_x
            jsr Abs_D
            cmpd #DECOR_NEAR_X
            bgt .no
            ldb ,s
            clra
            jsr Times12
            subd <cam_y
            jsr Abs_D
            cmpd #DECOR_NEAR_Y
            bgt .no
            ldx #effect_pool
            lda #DECOR_MIN_FREE
            ldb #EFFECT_COUNT
.scan       ldy FX_UPDATE,x
            bne .used
            deca
            beq .yes
.used       leax EFFECT_SIZE,x
            decb
            bne .scan
.no         andcc #$FB
            puls b,x,pc
.yes        orcc #$04
            puls b,x,pc

; Sprites by parameter: while falling, at rest.
nt_remains_sprites fcb 48,48,61,63,48,47

RemainsPlacer_New
            pshs a
            bsr nt_decor_ok
            puls a
            bne nt_placer_none
            pshs a,b            ; 0,s=param 1,s=cell y
            tfr x,d
            jsr Times12
            addd #1
            pshs d
            lda #10
            lbsr nt_rnd
            addd ,s++
            tfr d,x
            ldb 1,s
            clra
            jsr Times12
            addd #10            ; int(TILE_SIZE * 7 / 8)
            tfr d,y
            lda ,s
            asla
            ldu #nt_remains_sprites
            ldd a,u
            leas 2,s
            jsr Remains_New
nt_placer_done
            beq nt_placer_none
            tfr x,u
            rts
nt_placer_none
            ldu #0
            rts

; ---- RespawnPoint.as ------------------------------------------------------------------------
RESPAWNP_CELLX equ E_DATA+0
RESPAWNP_CELLY equ E_DATA+2
RESPAWNP_FLAGGED equ E_DATA+3

RespawnPoint_vt fdb RespawnPoint_Update,0,0,0,0

; LAZY: `flagged` would be lost when the record is forgotten, and the man running back past the point would then pull
; his respawn backwards. The flagged cells are listed in the statics, and a new record looks itself up.
RespawnPoint_New
            ldy #RespawnPoint_vt
            lbsr nt_new_plain
            beq .out
            stx RESPAWNP_CELLX,u
            stb RESPAWNP_CELLY,u
            ldx #respawn_cells
            lda respawn_count
            beq .made
.scan       ldy ,x
            cmpy RESPAWNP_CELLX,u
            bne .next
            ldb 2,x
            cmpb RESPAWNP_CELLY,u
            bne .next
            ldb #1
            stb RESPAWNP_FLAGGED,u
            bra .made
.next       leax 3,x
            deca
            bne .scan
.made       andcc #$FB
.out        rts

; U=entity.
RespawnPoint_Activate
            lda <man_heading
            sta <spawn_h
            ldd RESPAWNP_CELLX,u
            std <spawn_x
            lda RESPAWNP_CELLY,u
            sta <spawn_y
            lda #SND_CRYSTAL
            jsr Sound_Play
            ldd E_Y,u
            addd #2
            tfr d,y
            ldx E_X,u
            jsr RespawnActivation_New
            lda #1
            sta RESPAWNP_FLAGGED,u
            ; Remember it. The levels have at most 11; past the list's end it just stays in memory.
            lda respawn_count
            cmpa #RESPAWN_FLAGGED_MAX
            lbhs nt_keep
            ldb #3
            mul
            ldx #respawn_cells
            leax d,x
            ldd RESPAWNP_CELLX,u
            std ,x
            lda RESPAWNP_CELLY,u
            sta 2,x
            inc respawn_count
            rts

RESPAWNP_LOOK equ 3
RespawnPoint_Update
            NT_LIVE
            tst RESPAWNP_FLAGGED,u
            bne .draw
            ldd <man_x
            subd E_X,u
            jsr Abs_D
            cmpd #6
            bgt .farx
            ; |my - (y - 7.5)| <= 15: my - y runs from -22 to 7.
            ldd <man_y
            subd E_Y,u
            cmpd #-22
            blt .out
            cmpd #7
            bgt .out
            bsr RespawnPoint_Activate
.draw       ldd #130
            lbsr nt_still_sprite
            ldx E_STILL,u
            beq .out
            lda #255            ; a flag once up is only an image
            sta E_WAIT,u
.out        rts
.farx       cmpd #6+RESPAWNP_LOOK*4
            bls .out
            lda #RESPAWNP_LOOK
            sta E_WAIT,u
            rts

; ---- TinierSpaceman.as ----------------------------------------------------------------------
TINYS_STATE equ E_DATA+2        ; NT_HX is the heading; NT_HY stays 0
TINYS_READY equ E_DATA+3
TINYS_RUNDIST equ E_DATA+4
TINYS_RUNFRAME equ E_DATA+5
TINYS_LOOKS equ E_DATA+6
TINYS_SPX   equ E_DATA+7
TINYS_SPY   equ E_DATA+8
TINYS_WAITING equ E_DATA+9
TINYS_SIGHT equ E_DATA+10
TINYS_SIGHTVT equ E_DATA+12
TINYS_FIRE  equ 0
TINYS_RUN   equ 1
TINYS_JUMP  equ 2
TINYS_LOOK  equ 3
TINYS_SUSPENDED equ 4
TINYS_FIRE_T equ 6              ; 200 ms
TINYS_RECOIL_T equ 3            ; 100 ms
TINYS_LOOK_T equ 15             ; 500 ms
TINYS_SUSPEND_T equ 3           ; 100 ms
TINYS_STEP_T equ 1              ; 33 ms
TINYS_SPRITE equ 180
TINYS_SIGHT_SPEED equ 1638      ; 192 px/s

TinierSpaceman_vt fdb TinierSpaceman_Update,Ally_Base_Hurt,0,0,0

; A=heading.
TinierSpaceman_New
            pshs a
            lda #KIND_ALLY
            sta <t2
            puls a
            ldy #TinierSpaceman_vt
            lbsr nt_new_k
            beq .out
            sta NT_HX,u
            lda #TINYS_SUSPENDED
            sta TINYS_STATE,u
            ldd <now
            std E_START,u
            ldd #TINYS_SPRITE
            std E_SPRITE,u
            ldd E_Y,u
            addd #3
            std E_Y,u
            lda #2
            sta E_SIZEX,u
            lda #3
            sta E_SIZEY,u
            andcc #$FB
.out        rts

; A=state.
nt_tinys_switch
            sta TINYS_STATE,u
            cmpa #TINYS_FIRE
            bne .run
            lda #1
            sta TINYS_READY,u
            bra .clock
.run        cmpa #TINYS_RUN
            bne .jump
            lbsr nt_onscreen
            beq .runner
            lda #1
            ldx <man_x
            cmpx E_X,u
            bge .hd
            lda #-1
.hd         sta NT_HX,u
.runner     lda #36
            lbsr nt_rnd
            addb #18
            stb TINYS_RUNDIST,u
            bra .clock
.jump       cmpa #TINYS_JUMP
            bne .look
            lda NT_HX,u
            sta TINYS_SPX,u
            bra .clock
.look       cmpa #TINYS_LOOK
            bne .out
            lda #2
            sta TINYS_LOOKS,u
            clr TINYS_WAITING,u
.clock      ldd <now
            std E_START,u
.out        rts

; U=entity, A=heading.
TinierSpaceman_SetHeading
            sta NT_HX,u
            rts

; A=speed. Into the air.
nt_tinys_jump
            pshs a
            lda #TINYS_JUMP
            bsr nt_tinys_switch
            puls a
            sta TINYS_SPY,u
            rts

nt_tinys_run
            ldb TINYS_RUNFRAME,u
            addb #TINYS_SPRITE+2
            clra
            std E_SPRITE,u
            ldd <now
            subd E_START,u
            cmpd #TINYS_STEP_T
            bge .step
            rts
.step       ldd <now
            std E_START,u
            ldb NT_HX,u
            sex
            addd E_X,u
            std E_X,u
            inc TINYS_RUNFRAME,u
            lda TINYS_RUNFRAME,u
            cmpa #4
            blo .fr
            clr TINYS_RUNFRAME,u
.fr         dec TINYS_RUNDIST,u
            bne .ahead
            lda #TINYS_LOOK
            lbsr nt_tinys_switch
            ; A wall ahead?
.ahead      ldb #7
            lbsr nt_hxy
            jsr Cell_At
            tsta
            beq .floor
            ldb #7
            lbsr nt_hxy
            leay -12,y
            jsr Cell_At
            tsta
            bne .wallturn
            lda #-5
            bsr nt_tinys_jump
            bra .floor
.wallturn   neg NT_HX,u
            ; Ground ahead?
.floor      ldb #2
            lbsr nt_hxy
            leay 3,y
            jsr Cell_At
            tsta
            beq .pit
            rts
            ; Main_PitCheck's depth is a byte, and the C's 562 only means "to the bottom of the map". Asking for exactly
            ; that much also keeps its 8-bit row from wrapping.
.pit        ldd E_Y,u
            jsr Div12
            negb
            addb <lvl_h+1
            pshs b
            ldb #2
            lbsr nt_hxy
            puls a
            jsr Main_PitCheck
            cmpa #LAVA
            beq .lava
            tsta
            beq .back
            cmpa #GOAL
            beq .back
            lda #-3
            lbra nt_tinys_jump
            ; A landing three cells on, past the lava? x + 2h + 36h is the C's cell(x + 2h) + 3h.
.lava       ldb #38
            lbsr nt_hxy
            jsr Cell_At
            tsta
            bne .back
            ldb #38
            lbsr nt_hxy
            leay 12,y
            jsr Cell_At
            tsta
            bne .leap
            ldb #38
            lbsr nt_hxy
            leay 24,y
            jsr Cell_At
            tsta
            beq .back
.leap       lda #-6
            lbsr nt_tinys_jump
            lda NT_HX,u
            ldb #3
            lbsr nt_mulh
            stb TINYS_SPX,u
            rts
.back       ldb NT_HX,u
            negb
            sex
            addd E_X,u
            std E_X,u
            neg NT_HX,u
            rts

nt_tinys_air
            ldd #TINYS_SPRITE+4
            std E_SPRITE,u
            ldd <now
            subd E_START,u
            cmpd #TINYS_STEP_T
            bge .step
            rts
.step       ldd <now
            std E_START,u
            ldb TINYS_SPX,u
            sex
            addd E_X,u
            std E_X,u
            ldb TINYS_SPY,u
            sex
            addd E_Y,u
            std E_Y,u
            inc TINYS_SPY,u
            ldd E_Y,u
            addd #3
            tfr d,y
            ldx E_X,u
            jsr Cell_At
            tsta
            beq .wall
            ldd E_Y,u
            addd #3
            jsr Div12
            jsr Times12
            subd #3
            std E_Y,u
            lda #TINYS_LOOK
            lbra nt_tinys_switch
.wall       ldd E_X,u
            addd #2
            tfr d,x
            ldy E_Y,u
            jsr Cell_At
            tsta
            beq .out
            ldd E_X,u
            addd #2
            jsr Div12
            jsr Times12
            std <t4
            lda NT_HX,u
            ldb #2
            lbsr nt_mulh
            std <t2
            ldd <t4
            subd <t2
            std E_X,u
            neg NT_HX,u
.out        rts

; The sight checker's record can be freed and reused while we wait, so its class is compared with the one remembered.
; TINYS_SIGHT=0 means no laser slot, or firing was off: as if it had looked and seen nothing.
nt_tinys_look
            ldd #TINYS_SPRITE
            std E_SPRITE,u
            tst TINYS_WAITING,u
            bne .wait
            ldd <now
            std E_START,u
            ldd #TINYS_SIGHT_SPEED
            tst NT_HX,u
            bpl .sp
            ldd #-TINYS_SIGHT_SPEED
.sp         std <arg0
            lda #1
            sta TINYS_WAITING,u
            ldx E_X,u
            ldd E_Y,u
            subd #3
            tfr d,y
            jsr SightChecker_New
            beq .none
            ldd L_VT,x
            stx TINYS_SIGHT,u
            std TINYS_SIGHTVT,u
            rts
.none       clr TINYS_SIGHT,u
            clr TINYS_SIGHT+1,u
            rts
.wait       ldx TINYS_SIGHT,u
            beq .nothing
            ldd L_VT,x
            beq .ended
            cmpd TINYS_SIGHTVT,u
            bne .nothing
            lda L_FLAGS,x
            bita #LF_ACTIVE
            beq .ended
            rts                 ; still flying
.ended      jsr SightChecker_IsAlienFound
            beq .nothing
            lda #TINYS_FIRE
            lbsr nt_tinys_switch
            bra .clear
.nothing    ldd <now
            subd E_START,u
            cmpd #TINYS_LOOK_T
            ble .out
            neg NT_HX,u
            dec TINYS_LOOKS,u
            bgt .clear
            lda #TINYS_RUN
            lbsr nt_tinys_switch
.clear      clr TINYS_SIGHT,u
            clr TINYS_SIGHT+1,u
            clr TINYS_WAITING,u
.out        rts

TinierSpaceman_Update
            NT_LIVE
            lda TINYS_STATE,u
            cmpa #TINYS_FIRE
            bne .run
            ldd <now
            subd E_START,u
            pshs d
            tst TINYS_READY,u
            beq .wait
            ldx E_X,u
            ldd E_Y,u
            subd #2
            tfr d,y
            lda NT_HX,u
            jsr AllyLaser_New
            clr TINYS_READY,u
            bra .sprite
.wait       ldd ,s
            cmpd #TINYS_FIRE_T
            blt .sprite
            lda #TINYS_LOOK
            lbsr nt_tinys_switch
            lda #8
            sta TINYS_LOOKS,u
.sprite     puls d
            cmpd #TINYS_RECOIL_T
            bge .plain
            ldd #TINYS_SPRITE+1
            bra .ss
.plain      ldd #TINYS_SPRITE
.ss         std E_SPRITE,u
            bra .draw
.run        cmpa #TINYS_RUN
            bne .jump
            lbsr nt_tinys_run
            bra .draw
.jump       cmpa #TINYS_JUMP
            bne .look
            lbsr nt_tinys_air
            bra .draw
.look       cmpa #TINYS_LOOK
            bne .susp
            lbsr nt_tinys_look
            bra .draw
.susp       ldd <now
            subd E_START,u
            cmpd #TINYS_SUSPEND_T
            blt .draw
            ldd <now
            std E_START,u
            lbsr nt_onscreen
            bne .draw
            lda #TINYS_LOOK
            lbsr nt_tinys_switch
.draw       ldd E_SPRITE,u
            lda NT_HX,u
            cmpa #1
            bne .left
            ldd E_SPRITE,u
            addd #6
            bra .at
.left       ldd E_SPRITE,u
.at         pshs d
            ldx E_X,u
            leax -6,x
            ldy E_Y,u
            leay -9,y
            puls d
            jmp Draw_Sprite

            assert *<=$4000,"entities overflow bank 11"
entities_end equ *
            endbank
