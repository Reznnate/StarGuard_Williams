; Object pools and the base classes: Entity/Alien/Ally, Laser, Effect. Far calls. The spawner. Fixed ROM.
; See DESIGN.md and PORTING.md for how game classes use these.

; ---- far calls ------------------------------------------------------------------------------
; Inline: jsr far_call / fdb target / fcb bank. Passes A, B, X, Y, U through in both directions; flags do not survive.
far_call    std <fc_d
            stx <fc_x
            puls x
            ldd ,x++
            std <fc_t
            lda ,x+
            pshs x
            ldb <cur_bank
            pshs b
            sta <cur_bank
            sta BANK_SELECT
            ldd <fc_d
            ldx <fc_x
            jsr [fc_t]
            std <fc_d
            puls b
            stb <cur_bank
            stb BANK_SELECT
            ldd <fc_d
            rts

; ---- entities -------------------------------------------------------------------------------
; X=class descriptor, A=its bank (the bank holding the code and descriptor; 0 if fixed ROM).
; B=kind (KIND_ALIEN etc). Returns U=zeroed record with Z clear, or Z set if the pool is full.
; The record is active, and solid only if the class says so. It is on the update list immediately.
Ent_Alloc   stx <t0
            sta <t1
            stb <t1+1
            ldu #ent_pool
            lda <ent_count
.scan       ldx E_VT,u
            beq .found
            leau ENT_SIZE,u
            deca
            bne .scan
            FAR ent_evict       ; full: one asleep far off may give up its slot (U=0 if none)
            tsta
            bne .found
            orcc #$04
            rts
.found      ldd #0
            std 2,u
            std 4,u
            std 6,u
            std 8,u
            std 10,u
            std 12,u
            std 14,u
            std 16,u
            std 18,u
            std 20,u
            std 22,u
            std 24,u
            std 26,u
            std 28,u
            std 30,u
            std 32,u
            std 34,u
            std 36,u
            std 38,u
            std 40,u
            std 42,u
            std 44,u
            std 46,u
            leax ENT_SIZE,u
            cmpx ent_hi
            bls .marked
            stx ent_hi
.marked     ldd <t0
            std E_VT,u
            ldd <t1
            tsta
            bne .banked         ; fixed code runs with the level's bank in view
            lda <level_bank
.banked     sta E_BANK,u
            stb E_KIND,u
            lda #EF_ACTIVE
            sta E_FLAGS,u
            ldd #$FFFF
            std E_OBJ,u         ; not from the level's object list
            lda #1
            sta tgt_new         ; it wants to be in the list of targets
            andcc #$FB
            rts

; Alien() base constructor: X=cell x, B=cell y, U=record. World position is cell * 12, as in the C.
Alien_Init  bsr Entity_InitPos
            lda E_FLAGS,u
            ora #EF_SOLID
            sta E_FLAGS,u
            ldd #16
            std E_HEALTH,u
            lda #2
            sta E_SCORE,u
            rts

; Entity() base constructor.
Entity_InitPos
            pshs b
            tfr x,d
            bsr Times12
            std E_X,u
            puls b
            clra
            bsr Times12
            std E_Y,u
            rts

; D = D * 12. Preserves X, Y, U.
Times12     aslb
            rola
            aslb
            rola
            std <t3
            aslb
            rola
            addd <t3
            rts

; Virtual dispatch. U=entity. Each selects the entity's bank around the call and preserves cur_bank.
Entity_Update
            ldb #V_UPDATE
            bra ent_virtual
Entity_DeathEffect
            ldb #V_DEATH
            bra ent_virtual
Entity_Die  ldb #V_DIE
            bra ent_virtual
; D=hit x, X=hit y, for HitEffect. Saved to hit_x/hit_y where handlers read them.
Entity_HitEffect
            std <hit_x
            stx <hit_y
            ldb #V_HIT
            bra ent_virtual
; D=damage, X=laser. Handlers read hurt_laser and hurt_damage.
Entity_Hurt clr E_WAIT,u        ; whatever it was waiting for, it must answer this
            std <hurt_damage
            stx <hurt_laser
            ldb #V_HURT
            ; falls through
ent_virtual lda <cur_bank
            pshs a
            lda E_BANK,u
            beq .fixed
            sta <cur_bank
            sta BANK_SELECT
.fixed      ldx E_VT,u
            abx
            ldx ,x
            bne .call
            ; Slot 0 means the base behaviour.
            ldx #base_table
            abx
            ldx ,x
.call       jsr ,x
            puls a
            sta <cur_bank
            sta BANK_SELECT
            rts

; A class descriptor is five words: update, hurt, die, death effect, hit effect. 0 = inherit from Alien.
base_table  fdb Entity_Base_Update,Alien_Base_Hurt,Alien_Base_Die,Alien_Base_DeathEffect,Alien_Base_HitEffect

Entity_Base_Update
            rts

Alien_Base_DeathEffect
            lda #SND_EXPLOSION
            jsr Sound_Play
            ldx E_X,u
            ldy E_Y,u
            ldb #16
            jsr Explosion_New
            ldx E_X,u
            ldy E_Y,u
            ldb #4
            jsr Circle_New
            ldd E_SPRITE,u
            std <arg0
            ldx E_X,u
            ldy E_Y,u
            jmp DeathFlash_New

Alien_Base_Die
            jsr Main_RecordKill
            ldb E_SCORE,u
            ldx E_X,u
            ldy E_Y,u
            jsr Main_RecordScore
            jsr Entity_DeathEffect
            ; Remember the object is gone so the spawner never brings it back.
            jsr Ent_MarkDead
            lda E_FLAGS,u
            anda #~EF_ACTIVE&$FF
            sta E_FLAGS,u
            rts

Alien_Base_HitEffect
            lda #SND_HIT
            jsr Sound_Play
            ldx E_X,u
            ldy E_Y,u
            ldb #1
            jsr Explosion_New
            lda E_FLAGS,u
            ora #EF_FLASHING
            sta E_FLAGS,u
            ldb <now+1
            stb E_FLASHT,u
            rts

Alien_Base_Hurt
            ldd E_HEALTH,u
            subd <hurt_damage
            std E_HEALTH,u
            bgt .alive
            jmp Entity_Die
.alive      ldx <hurt_laser
            ldd L_X,x
            ldx L_Y,x
            jmp Entity_HitEffect

; Ally.Hurt.
Ally_Base_Hurt
            ldd E_HEALTH,u
            subd <hurt_damage
            std E_HEALTH,u
            bgt .alive
            lda #SND_EXPLOSION
            jsr Sound_Play
            ldx E_X,u
            ldy E_Y,u
            ldb #16
            jsr Explosion_New
            lda E_FLAGS,u
            anda #~EF_ACTIVE&$FF
            sta E_FLAGS,u
            ldx E_X,u
            ldy E_Y,u
            ldd #48*256+48
            jmp Remains_New
.alive      lda #SND_HIT
            jsr Sound_Play
            ldx E_X,u
            ldy E_Y,u
            ldb #1
            jsr Explosion_New
            ldx E_X,u
            ldy E_Y,u
            lda #COLOR_RED
            jmp LaserImpact_New

; Alien.DrawSelf: D=sprite id. Draws at (E_X - 6, E_Y - 6), white while flashing.
Alien_DrawSelf
            ldx E_X,u
            leax -6,x
            ldy E_Y,u
            leay -6,y
            sta <t4
            lda E_FLAGS,u
            anda #EF_FLASHING
            bne .flashing
            lda <t4
            jmp Draw_Sprite
.flashing   lda <t4
            pshs d
            ldb <now+1
            subb E_FLASHT,u
            cmpb #ALIEN_FLASH_T
            bls .flash
            lda E_FLAGS,u
            anda #~EF_FLASHING&$FF
            sta E_FLAGS,u
            puls d
            jmp Draw_Sprite
.flash      lda #COLOR_WHITE
            sta <draw_color
            puls d
            jmp Draw_ColoredSprite

; Alien.ContactKillCheck.
Alien_ContactKillCheck
            bsr Ent_TouchesMan
            bne .out
            lda <man_flags
            bita #MF_INVULN
            bne .shielded
            lda #PHYSICAL_DEATH
            jmp Man_Die
.shielded   clr E_SCORE,u
            jmp Entity_Die
.out        rts

; Z set if the entity's box overlaps the man's: |dx| < sizeX + 2, |dy| < sizeY + 3.
Ent_TouchesMan
            ldd <man_x
            subd E_X,u
            bsr Abs_D
            pshs d
            ldb E_SIZEX,u
            clra
            addd #2
            cmpd ,s++
            ble .no
            ldd <man_y
            subd E_Y,u
            bsr Abs_D
            pshs d
            ldb E_SIZEY,u
            clra
            addd #3
            cmpd ,s++
            ble .no
            orcc #$04
            rts
.no         andcc #$FB
            rts

Abs_D       tsta
            bpl .pos
            coma
            comb
            addd #1
.pos        rts

; Marks the entity's source object as dead, so it will not respawn.
Ent_MarkDead
            ldd E_OBJ,u
            cmpd #$FFFF
            beq .out
            ldx #obj_dead
            jsr bit_set
.out        rts

; D = bit index into the bit array at X. Sets the bit.
bit_set     pshs b
            lsra
            rorb
            lsra
            rorb
            lsra
            rorb
            leax d,x
            puls b
            andb #7
            lda #1
.sh         tstb
            beq .sh_done
            asla
            decb
            bra .sh
.sh_done    ora ,x
            sta ,x
            rts

; Updates every entity, then frees the inactive ones. Slots are freed by clearing E_VT.
Ent_UpdateAll
            ; A few slots each tick ask how far they are from the view: all of them, about every 10 ticks.
            ldd ent_hi
            subd #ent_pool
            lsra
            inca
            sta <ent_left
            ldu ent_ask_at
.ask        cmpu ent_hi
            blo .asking
            ldu #ent_pool
.asking     ldd E_VT,u
            beq .asked
            lbsr ent_ask
.asked      leau ENT_SIZE,u
            dec <ent_left
            bne .ask
            stu ent_ask_at
            ; An update runs in its class's bank, and most neighbours share one, so the bank only changes when it must.
            lda <cur_bank
            pshs a
            ldu #ent_pool
            ; The list of targets holds from one tick to the next: lasers check each target's exact position themselves,
            ; and the near test leaves room for how far one can move. So there are two walks, and only one builds the list.
            lda <now+1
            anda #3
            beq .newlist
            tst tgt_new
            lbeq .walkn
.newlist    clr tgt_new
            clr <target_n
            clr <target_m
            ldd <cam_x
            std tgt_cam_x
            ldd <cam_y
            std tgt_cam_y
            cmpu ent_hi
            blo .topt
            lbra .done
.topt      ldx E_VT,u
            beq .skipt
            lda E_FLAGS,u
            bita #EF_ASLEEP
            bne .skipt
            tst E_WAIT,u        ; nothing to do yet, but it is still a target
            bne .waitt
            tsta                ; EF_OFF is the top bit
            bmi .quiett
.runt       lda E_BANK,u
            cmpa <cur_bank
            bne .switcht
.inbankt   ldx ,x              ; the class's update
            beq .noupdt
            jsr ,x
.noupdt    lda E_FLAGS,u
            bita #EF_ACTIVE
            beq .deadt
            lda E_KIND,u        ; KIND_ENTITY is 0: those are no target
            beq .skipt
            lbsr target_add
.skipt      leau ENT_SIZE,u
            cmpu ent_hi
            blo .topt
            lbra .done
.waitt      dec E_WAIT,u
            bra .noupdt
.quiett     lbsr ent_off_turn
            bne .skipt
            ldx E_VT,u
            bra .runt
.switcht   sta <cur_bank
            sta BANK_SELECT
            bra .inbankt
.deadt     jsr ent_end
            bra .skipt
.walkn      cmpu ent_hi
            lbhs .done
.topn      ldx E_VT,u
            beq .skipn
            lda E_FLAGS,u
            bita #EF_ASLEEP
            bne .skipn
            tst E_WAIT,u
            bne .waitn
            tsta                ; EF_OFF is the top bit
            bmi .quietn
.runn       lda E_BANK,u
            cmpa <cur_bank
            bne .switchn
.inbankn   ldx ,x              ; the class's update
            beq .noupdn
            jsr ,x
.noupdn    lda E_FLAGS,u
            bita #EF_ACTIVE
            beq .deadn
.skipn      leau ENT_SIZE,u
            cmpu ent_hi
            blo .topn
            lbra .done
.waitn      dec E_WAIT,u
            bra .skipn
.quietn     lbsr ent_off_turn
            bne .skipn
            ldx E_VT,u
            bra .runn
.switchn   sta <cur_bank
            sta BANK_SELECT
            bra .inbankn
.deadn     jsr ent_end
            bra .skipn
.done       ldx ent_hi          ; give back the slots at the top that are empty now
.back       cmpx #ent_pool
            bls .set
            ldd E_VT-ENT_SIZE,x
            bne .set
            leax -ENT_SIZE,x
            bra .back
.set        stx ent_hi
            puls a
            cmpa <cur_bank
            beq .out
            sta <cur_bank
            sta BANK_SELECT
.out        rts

; It has EF_OFF. Z set if it runs this tick: one tick in four, by slot, when it also asks where it is,
; so that it is back to every tick before it can come into view. Keeps U.
ent_off_turn
            tfr u,d
            lsrb
            lsrb
            lsrb
            lsrb
            addb <now+1
            andb #3
            bne .out
            lbsr ent_ask
            ldx E_VT,u
            beq .gone
            lda E_FLAGS,u
            bita #EF_ASLEEP
.out        rts
.gone       andcc #$FB
            rts

; U=entity. Is it far from the view? Far enough and it goes back to the object list, or to sleep if it has no object there.
; A little less far and it sleeps. A sleeper's timers run on the game's clock, so it only
; misses movement that nobody can see. Anything that must go on running has EF_KEEP, and allies follow the man. Keeps U.
ent_ask     lda E_FLAGS,u
            bita #EF_KEEP
            beq .free
            bita #EF_NAP
            beq .wake
            ; Remembered, but with nothing to do far away.
.near_or_nap
            ldd E_X,u
            subd <cam_x
            addd #SLEEP_X
            cmpd #SLEEP_X*2
            lbhs .sleep
            ldd E_Y,u
            subd <cam_y
            addd #SLEEP_Y
            cmpd #SLEEP_Y*2
            lbhs .sleep
            bra .wake
.free
            ; An ally is never forgotten either. Far from the view it waits, and the enemies around it are asleep too.
            ldb E_KIND,u
            cmpb #KIND_ALLY
            beq .near_or_nap
            ; A piglet's loop is wide: asleep where it stopped, it would miss coming round into view. It never sleeps, and
            ; out of sight it rolls one tick in four (pgl_sync keeps it on the original's clock) until it is forgotten.
            ldd E_VT,u
            cmpd #Piglet_vt
            bne .any
            ldd E_X,u
            subd <cam_x
            addd #DESPAWN_DIST
            cmpd #DESPAWN_DIST*2
            bhs .gone
            ldd E_Y,u
            subd <cam_y
            addd #DESPAWN_DIST
            cmpd #DESPAWN_DIST*2
            bhs .gone
            bra .wake
.any        ldd E_X,u
            subd <cam_x
            addd #DESPAWN_DIST
            cmpd #DESPAWN_DIST*2
            bhs .gone
            subd #DESPAWN_DIST-SLEEP_X
            cmpd #SLEEP_X*2
            bhs .sleep
            ldd E_Y,u
            subd <cam_y
            addd #DESPAWN_DIST
            cmpd #DESPAWN_DIST*2
            bhs .gone
            subd #DESPAWN_DIST-SLEEP_Y
            cmpd #SLEEP_Y*2
            bhs .sleep
.wake       lda E_FLAGS,u
            anda #~(EF_ASLEEP+EF_OFF)&$FF
            sta E_FLAGS,u
            ; Out of sight, it need not run every tick. What keeps running for a reason, and a boss, do.
            bita #EF_KEEP
            bne .seen
            ldb E_KIND,u
            cmpb #KIND_ALLY
            beq .seen
            tst wiz_live
            bne .seen
            ldd E_X,u
            subd <cam_x
            addd #OFF_X
            cmpd #OFF_X*2
            bhs .off
            ldd E_Y,u
            subd <cam_y
            addd #OFF_Y
            cmpd #OFF_Y*2
            bhs .off
.seen       rts
.off        lda E_FLAGS,u
            ora #EF_OFF
            sta E_FLAGS,u
            rts
            ; Beyond the far limit in x, it may still be near enough in y, or the reverse: either way it is out of sight.
.gone       ldd E_OBJ,u
            cmpd #$FFFF
            beq .sleep
            lbra ent_forget
.sleep      clr E_WAIT,u
            lda E_FLAGS,u
            ora #EF_ASLEEP
            sta E_FLAGS,u
            ; With the still layer filling up, its images go to what is near. Not otherwise: what sleeps and wakes at the
            ; edge of the distance would add and draw them again each time, which cost level 9 2.6% before its boss.
            lda still_rem
            cmpa #STILL_MAX-STILL_BANNER-12
            bhs ent_still_drop
            rts

TARGET_RANGE equ 192
HIT_REACH   equ 48          ; in list units, as a full width (96 pixels): more than any target's size plus any laser's
; U=entity, added to the targets for lasers.
target_add  ldd E_X,u           ; a target well out of view is not worth every laser's time
            subd <cam_x
            addd #TARGET_RANGE
            cmpd #TARGET_RANGE*2
            bhs .out
            lsra                ; half a pixel's precision, centered on 128
            rorb
            addb #128-TARGET_RANGE/2
            stb <t0
            ldd E_Y,u
            subd <cam_y
            addd #TARGET_RANGE
            cmpd #TARGET_RANGE*2
            bhs .out
            lsra
            rorb
            addb #128-TARGET_RANGE/2
            stb <t0+1
            ldx #target_mid
            lda E_KIND,u
            cmpa #KIND_ALIEN
            bne .other
            ldb <target_n
            cmpb #TARGET_ALIENS
            bhs .out
            incb
            stb <target_n
            ; Aliens go downward from the middle.
            negb
            aslb
            aslb
            leax b,x
            bra .put
.other      ldb <target_m
            cmpb #TARGET_OTHERS
            bhs .out
            inc <target_m
            aslb
            aslb
            abx
.put        ldd <t0
            std ,x
            stu 2,x
.out        rts

; U=entity: gives back its images in the still layer, if it has any, and forgets them. One asleep is well out of view,
; and makes them again when it wakes: their slots are better used by what is near. Keeps U.
ent_still_drop
            lda E_FLAGS,u
            bita #EF_STILL
            beq .out
            leax E_STILL,u
            bsr .one
            ldd E_VT,u          ; a beam turret has an image at each end
            cmpd #BeamTurret_vt
            bne .out
            leax BEAMT_S2,u
.one        pshs x
            ldx ,x
            beq .none
            jsr Still_Release
.none       puls x
            clr ,x
            clr 1,x
.out        rts

ent_forget  ldd E_OBJ,u
            cmpd <spawn_lo      ; outside the window, the spawner sees it when it comes in
            blo .out
            cmpd <spawn_hi
            bhs .out
            inc spawn_ev
.out        ldx #obj_spawned
            jsr bit_clear
            ; falls through
; U=entity. Frees its slot, and its image if it has one in the still layer.
ent_end     bsr ent_still_drop
            clr E_VT,u
            clr E_VT+1,u
            ; falls through
; A slot has come free: a constructor that had no room can try again. Keeps A, B, X, Y, U.
spawn_room  tst spawn_want
            beq .out
            clr spawn_want
            inc spawn_ev
.out        rts

bit_clear   pshs b
            lsra
            rorb
            lsra
            rorb
            lsra
            rorb
            leax d,x
            puls b
            andb #7
            lda #1
.sh         tstb
            beq .sh_done
            asla
            decb
            bra .sh
.sh_done    coma
            anda ,x
            sta ,x
            rts

; ---- lasers ---------------------------------------------------------------------------------
; X=class handlers (update, draw; 0 = base), A=target (ALIENS etc). Y=world x, D not used.
; Returns U=zeroed record with Z clear, or Z set if firing is off or the pool is full.
GOV_SHOTS   equ 8
; Under load, every other one of something that is only for show is not made, and at the most load three in four, as when
; the boss's worm eats its barrier and the debris of 15 blocks would take the game to half speed. Z clear if this one is not.
; Keeps A.
gov_thin    tst gov_load
            beq .out
            inc gov_bit
            pshs a
            lda gov_load
            cmpa #3
            lda gov_bit         ; keeps the carry
            bhs .most
            bita #1
            puls a,pc
.most       bita #3
            puls a,pc
.out        rts

Laser_Alloc stx <t0
            sta <t1
            tst <firing_allowed
            beq .none
            ldu #laser_pool
            lda #LASER_COUNT
            ; Heavily loaded: enemy shots keep to the lower slots, so there are only so many at once. A beam is a gate, and is never refused.
            ldb gov_load
            cmpb #2
            blo .scan
            tst gov_free
            bne .scan
            ldb <t1
            cmpb #ALLIES
            bne .scan
            cmpx #laserbeam_vt
            beq .scan
            lda #GOV_SHOTS
.scan       ldx L_VT,u
            beq .found
            leau LASER_SIZE,u
            deca
            bne .scan
.none       orcc #$04
            rts
.found      leax LASER_SIZE,u
            cmpx laser_hi
            bls .marked
            stx laser_hi
.marked     ldd #0
            std 2,u
            std 4,u
            std 6,u
            std 8,u
            std 10,u
            std 12,u
            std 14,u
            std 16,u
            std 18,u
            std 20,u
            std 22,u
            std 24,u
            std 26,u
            std 28,u
            ldd <t0
            std L_VT,u
            lda <t1
            sta L_TARGET,u
            lda #16
            sta L_DAMAGE,u
            lda #1
            sta L_SIZEX,u
            sta L_SIZEY,u
            lda #LF_ACTIVE+LF_CANCEL
            sta L_FLAGS,u
            ldd <now
            std L_START,u
            ldd #36
            std L_SPRITE,u
            andcc #$FB
            rts

; Moves all lasers, checks them against targets, draws them, frees the dead.
Laser_UpdateAll
            ldu #laser_pool
            bra .check
.next       ldx L_VT,u
            beq .skip
            ldx ,x
            bne .upd
            ldx #Laser_Base_Update
.upd        jsr ,x
            jsr laser_hits
            ldx L_VT,u
            ldx 2,x
            bne .draw
            ldx #Laser_Base_Draw
.draw       jsr ,x
.after      lda L_FLAGS,u
            bita #LF_ACTIVE
            bne .skip
            clr L_VT,u
            clr L_VT+1,u
.skip       leau LASER_SIZE,u
.check      cmpu laser_hi
            blo .next
            ldx laser_hi        ; give back the slots at the top that are empty now
.back       cmpx #laser_pool
            bls .set
            ldd L_VT-LASER_SIZE,x
            bne .set
            leax -LASER_SIZE,x
            bra .back
.set        stx laser_hi
            rts

; ---- bolts in a row ------------------------------------------------------------------------------
; A bolt is a few pixels going straight down or up. A row of turrets fires together, so its bolts share their height and everything else but the column
; they are in. One laser holds up to 6 of them, as a list. A bolt leaves the list when it lands or hits, and the laser ends with its last.
; When anything else may be near, each bolt goes through laser_hits as a laser of its own would, so that it follows the same rules.
BR_BASE     equ L_VX            ; the x that a column of 0 is at
BR_N        equ L_DATA          ; how many
BR_LIST     equ L_DATA+1        ; 6 bytes, each a bolt's column less the base's, with the top bit set if it is in lava. Two are LM_COL and LM_ROW:
BR_MAX      equ 6               ; br_h_hit keeps them safe from Laser_CellHere. LM_TYPE is not used, as Main_SetCell clears it.
BR_ROW      equ L_SPRITE        ; the row of cells it last looked at
BR_GEN      equ L_SPRITE+1      ; and cell_gen then
LF_BRSLOW   equ $10             ; a bolt is over a block
LF_BRLAVA   equ $20             ; a bolt is in lava

; X, Y=the bolt, A=1 or -1. X=the laser, Z clear; Z set if there was no room.
AlienLaserVertical_New
            pshs d,x,y,u
            ldu #laser_pool
.scan       cmpu laser_hi
            bhs .make
            ldd L_VT,u
            cmpd #alienlaserv_vt
            bne .no
            ldd L_START,u
            cmpd <now
            bne .no
            ldd L_Y,u
            cmpd 4,s
            bne .no
            lda L_VY,u
            eora ,s
            bmi .no
            ldb BR_N,u
            cmpb #BR_MAX
            bhs .no
            ldd 2,s
            subd BR_BASE,u
            bmi .no
            cmpd #127*12
            bhs .no
            jsr Div12
            pshs b
            ldb BR_N,u
            leax BR_LIST,u
            abx
            puls b
            stb ,x
            inc BR_N,u
            jmp lz_done
.no         leau LASER_SIZE,u
            bra .scan
.make       ldx #lz_row_alienv
            jsr lz_make
            ldd #ALIENLASER_SPEED
            jsr lz_signed
            std L_VY,u
            ldd 2,s
            subd #60*12         ; room either side
            std BR_BASE,u
            lda #60
            sta BR_LIST,u
            lda #1
            sta BR_N,u
            lda #$FF
            sta BR_ROW,u
            jmp lz_done

BoltRow_Update
            leas 2,s            ; it does its own hits and drawing
            ldd L_VY,u
            jsr Laser_MoveY
            ; A new row of cells, or cells that have changed: what is each bolt in now?
            ldd L_Y,u
            jsr Div12
            cmpb BR_ROW,u
            bne .look
            lda cell_gen
            cmpa BR_GEN,u
            beq .looked
.look       stb BR_ROW,u
            lda cell_gen
            sta BR_GEN,u
            lda L_FLAGS,u
            anda #~(LF_BRSLOW+LF_BRLAVA)&$FF
            sta L_FLAGS,u
            ldy #br_h_cell
            bsr br_walk
.looked     lda L_FLAGS,u
            bita #LF_BRLAVA
            beq .nolava
            ldy #br_h_lava
            bsr br_walk
.nolava     ; Hits. With no one about but the man, and him not at this height, there are none.
            tst <target_m
            bne .slow
            lda L_FLAGS,u
            bita #LF_BRSLOW
            bne .slow
            lda <man_flags
            bita #MF_ACTIVE
            beq .draw
            ldd L_Y,u
            subd <man_y
            bpl .my
            coma
            comb
            addd #1
.my         cmpd #4
            bhs .draw
.slow       ldy #br_h_hit
            bsr br_walk
.draw       jsr br_draw
            ; Its last bolt gone, it goes.
            tst BR_N,u
            bne .live
            lda L_FLAGS,u
            ora #LZ_SELF
            anda #~LF_ACTIVE&$FF
            sta L_FLAGS,u
.live       jmp Laser_UpdateAll.after

; Y=a routine to call for each bolt, last first, with L_X its x. It finds its place in the list at 2,s.
br_walk     pshs y
            ldb BR_N,u
            pshs b
.next       dec ,s
            bmi .out
            ldb ,s
            leax BR_LIST,u
            abx
            ldb ,x
            andb #$7F
            lda #12
            mul
            addd BR_BASE,u
            std L_X,u
            jsr [1,s]
            bra .next
.out        leas 3,s
            rts

; B=its place in the list. The last takes its place.
br_kill     leax BR_LIST,u
            abx
            dec BR_N,u
            ldb BR_N,u
            leay BR_LIST,u
            lda b,y
            sta ,x
            rts

; What this bolt is in.
br_h_cell   ldb 2,s
            leax BR_LIST,u
            abx
            lda ,x
            anda #$7F
            sta ,x
            ldx L_X,u
            ldy L_Y,u
            jsr Cell_At
            cmpa #PLATFORM
            bne .notwall
            ldb 2,s
            bsr br_kill
            jsr gov_thin
            bne .out
            lda #COLOR_RED
            jmp lz_impact_y
.notwall    cmpa #LAVA
            bne .notlava
            ldb 2,s
            leax BR_LIST,u
            abx
            lda ,x
            ora #$80
            sta ,x
            lda L_FLAGS,u
            ora #LF_BRLAVA
            sta L_FLAGS,u
            rts
.notlava    cmpa #PLATFORM_DESTRUCTIBLE
            bne .out
            lda L_FLAGS,u
            ora #LF_BRSLOW
            sta L_FLAGS,u
.out        rts

; This bolt, as a laser of its own.
br_h_hit    ldd LM_COL,u
            pshs d
            clr LM_TYPE,u
            jsr laser_hits
            puls d
            std LM_COL,u
            lda L_FLAGS,u
            bita #LF_ACTIVE
            bne .out
            ora #LF_ACTIVE
            sta L_FLAGS,u
            ldb 2,s
            bra br_kill
.out        rts

; Each bolt into the display list. Only the column differs, so an entry takes little work. One crossing the edge of the window goes the usual way.
BRD_COL     equ 0               ; 2 bytes: signed, a column of 0's
BRD_CTRL    equ 2
BRD_ROW     equ 3
BRD_I       equ 4
BRD_ALL     equ 5               ; they all cross the top or the bottom
BRD_SPR     equ 6               ; 2 bytes
BRD_SIZE    equ 8
br_draw     leas -BRD_SIZE,s
            ldy #sprite_table+218*SPRITE_ENTRY
            ldd #218
            std BRD_SPR,s
            ldd <now
            subd L_START,u
            cmpd #LZ_FLASH_T
            bhs .late
            ldy #sprite_table+217*SPRITE_ENTRY
            ldd #217
            std BRD_SPR,s
.late       clr BRD_ALL,s
            ; The line: as Draw_Sprite.
            ldd L_Y,u
            subd #6
            addb 5,y
            adca #0
            subd <spr_oy
            tsta
            lbne .out
            subb #12
            lblo .out
            stb BRD_ROW,s
            cmpb #VIEW_BOTTOM
            lbhs .out
            addb 3,y
            cmpb #VIEW_ROW0
            lbls .out
            cmpb #VIEW_BOTTOM
            bhi .cross
            lda BRD_ROW,s
            cmpa #VIEW_ROW0
            bhs .along
.cross      inc BRD_ALL,s
.along      ldd BR_BASE,u
            subd #6
            addb 4,y
            adca #0
            subd <spr_ox
            asra
            rorb
            std BRD_COL,s
            lda #BC_DST256+BC_FG_ONLY
            bcc .even
            lda #BC_DST256+BC_FG_ONLY+BC_SHIFT
.even       sta BRD_CTRL,s
            lda BR_N,u
            sta BRD_I,s
.next       dec BRD_I,s
            bmi .out
            ldb BRD_I,s
            leax BR_LIST,u
            abx
            ldb ,x
            andb #$7F
            lda #6
            mul
            addd BRD_COL,s
            tsta
            bne .next           ; off the screen
            tst BRD_ALL,s
            bne .edge
            cmpb #VIEW_COL0
            blo .edge
            tfr b,a
            adda 2,y
            cmpa #VIEW_COL0+VIEW_COLS-1
            bhi .edge
            ldx <dl_newp
            cmpx <dl_limit
            bhs .edge
            stb 2,x
            ldd ,y
            std ,x
            ldd 2,y
            std 4,x
            lda BRD_ROW,s
            sta 3,x
            lda BRD_CTRL,s
            sta 6,x
            clr 7,x
            leax DL_SIZE,x
            stx <dl_newp
            bra .next
.out        leas BRD_SIZE,s
            rts
            ; The usual way: this bolt's x from its column.
.edge       pshs y
            ldb BRD_I+2,s
            leax BR_LIST,u
            abx
            ldb ,x
            andb #$7F
            lda #12
            mul
            addd BR_BASE,u
            subd #6
            tfr d,x
            ldd L_Y,u
            subd #6
            tfr d,y
            ldd BRD_SPR+2,s
            jsr Draw_Sprite
            puls y
            bra .next

; Laser.Update: straight line, ended by solid platforms.
Laser_Base_Update
            ldd L_VX,u
            ADD_8_8U L_X
            jsr Laser_CellHere
            cmpa #PLATFORM
            bne .out
            lda L_FLAGS,u
            ora #LF_HITWALL
            anda #~LF_ACTIVE&$FF
            sta L_FLAGS,u
            lda #SND_MISS
            jsr Sound_Play
.out        rts

Laser_Base_Draw
            ldx L_X,u
            leax -6,x
            ldy L_Y,u
            leay -6,y
            ldd L_SPRITE,u
            jmp Draw_Sprite

; D = signed 8.8 step; adds to the laser's x.
laser_move_x
            leax L_X,u
            jmp add_8_8
Laser_MoveY leax L_Y,u
            jmp add_8_8

; A = type of the cell under the laser. A shot crosses a cell in many ticks, so each laser keeps the last answer until it leaves
; that cell. A block that can be shot is not kept: Block_Activate wants its raw type. Main_SetCellType forgets them all.
Laser_CellHere
            lda LM_TYPE,u       ; 1 + the type; 0 for none kept
            beq .miss
            ldb L_X+1,u
            subb LM_COL,u
            cmpb #12
            bhs .miss
            ldb L_Y+1,u
            subb LM_ROW,u
            cmpb #12
            bhs .miss
            deca
            rts
.miss       pshs y,a            ; 0,s=the type kept, if any
            ldx L_X,u
            ldy L_Y,u
            jsr Cell_At
            clr LM_TYPE,u
            cmpa #PLATFORM_DESTRUCTIBLE
            beq .out
            ldx L_X,u           ; off the level's top or left has no cell to keep
            bmi .out
            ldx L_Y,u
            bmi .out
            pshs a
            ; Most often it has only gone on into the next cell along. That takes no division.
            tst 1,s
            beq .full
            ldb L_Y+1,u
            subb LM_ROW,u
            cmpb #12
            bhs .full
            ldb L_X+1,u
            subb LM_COL,u
            subb #12
            cmpb #12
            blo .right
            addb #24
            cmpb #12
            blo .left
.full       ldd L_X,u
            jsr Div12
            jsr Times12
            stb LM_COL,u
            ldd L_Y,u
            jsr Div12
            jsr Times12
            stb LM_ROW,u
.kept       puls a
            inca
            sta LM_TYPE,u
            deca
.out        leas 1,s
            puls y,pc
.right      ldb LM_COL,u
            addb #12
            stb LM_COL,u
            bra .kept
.left       ldb LM_COL,u
            subb #12
            stb LM_COL,u
            bra .kept

; Laser against aliens, allies, neutrals and the man, following Main.UpdateLasers.
            ; Shots move so little in a tick against what they hit that each looks every other tick, by slot.
laser_hits  lda L_TARGET,u       ; a shot at the man, with no allies about, has only him to look at
            cmpa #ALLIES
            bne .list0
            tst <target_m
            bne .list0
            tst LM_TYPE,u       ; if the cell it is in is known, there is no block in it to wake
            lbne .man
.list0      tfr u,d
            lsrb
            eorb <now+1
            lsrb
            lbcs .man
            ; A block under the laser becomes a real entity now, so the box test below can hit it.
            jsr Laser_CellHere
            cmpa #PLATFORM_DESTRUCTIBLE
            bne .plat
            jsr Block_Activate
            bra .list
            ; A platform at rest there, the same: it waits in a keeper, with no entity of its own (pk_shot).
.plat       cmpa #EXPLODING_PLATFORM
            bne .list
            FAR pk_shot
            ; Each laser only looks at the kinds it can hit: lasers aimed at allies skip the aliens.
            ; The laser's position in the units of the target list, less half the reach. Then a target is near when the
            ; difference, as an unsigned byte, is at most the reach.
.list       ldd L_X,u
            subd tgt_cam_x
            addd #TARGET_RANGE+HIT_REACH
            cmpd #(TARGET_RANGE+HIT_REACH)*2
            lbhs .man           ; further out than any target can reach
            lsra
            rorb
            addb #128-(TARGET_RANGE+HIT_REACH)/2-HIT_REACH/2
            stb <t0
            ldd L_Y,u
            subd tgt_cam_y
            addd #TARGET_RANGE+HIT_REACH
            cmpd #(TARGET_RANGE+HIT_REACH)*2
            lbhs .man
            lsra
            rorb
            addb #128-(TARGET_RANGE+HIT_REACH)/2-HIT_REACH/2
            stb <t0+1
            ldb <target_m
            ldy #target_mid
            lda L_TARGET,u
            cmpa #ALLIES
            beq .count
            addb <target_n      ; aliens + the rest
            lda <target_n
            nega
            asla
            asla
            leay a,y
.count      tstb
            lbeq .man
            ; Most targets are far away: this rejects them in 8 bits, about 23 cycles each.
.ent        lda ,y
            suba <t0
            cmpa #HIT_REACH
            bhi .reject
            lda 1,y
            suba <t0+1
            cmpa #HIT_REACH
            bls .near
.reject     leay TARGET_SIZE,y
            decb
            bne .ent
            lbra .man
.near       stb <hit_left
            ldx 2,y             ; X = target
            ; Now exactly, with where it is now.
            ldd L_X,u
            subd E_X,x
            bpl .xpos
            coma
            comb
            addd #1
.xpos       tsta
            lbne .enext
            stb hit_d
            ldb E_SIZEX,x
            addb L_SIZEX,u
            cmpb hit_d
            lbls .enext
            ldd L_Y,u
            subd E_Y,x
            bpl .ypos
            coma
            comb
            addd #1
.ypos       tsta
            bne .enext
            stb hit_d
            ldb E_SIZEY,x
            addb L_SIZEY,u
            cmpb hit_d
            bls .enext
            ldd E_VT,x
            beq .enext
            lda L_FLAGS,u
            bita #LF_ACTIVE+LF_HITWALL
            beq .man            ; dead in flight: no more hits
            ; Which kinds can this laser hit?
            ldb E_KIND,x
            cmpb #KIND_NEUTRAL
            beq .canhit
            cmpb #KIND_ALIEN
            bne .ally
            lda L_TARGET,u
            cmpa #ALLIES
            beq .enext
            bra .canhit
.ally       lda L_TARGET,u
            cmpa #ALIENS
            beq .enext
.canhit     lda E_FLAGS,x
            bita #EF_ACTIVE
            beq .enext
            ; Allies are hit regardless of solid; everything else must be solid.
            cmpb #KIND_ALLY
            beq .hit
            bita #EF_SOLID
            beq .enext
            ; Hit. Damage goes to the entity; the laser ends either way.
.hit
            ldd <t0             ; a piercing laser goes on down the list
            pshs u,y,d
            ldb L_DAMAGE,u
            beq .nodmg
            clra
            pshs x
            tfr u,x             ; X = laser
            puls u              ; U = entity
            jsr Entity_Hurt
.nodmg      puls u,y,d
            std <t0
            lda L_FLAGS,u
            anda #~LF_ACTIVE&$FF
            sta L_FLAGS,u
.enext      leay TARGET_SIZE,y
            ldb <hit_left
            decb
            lbne .ent
.man        lda L_TARGET,u
            cmpa #ALIENS
            beq .out
            lda <man_flags
            bita #MF_ACTIVE
            beq .out
            lda L_FLAGS,u
            bita #LF_ACTIVE
            beq .out
            ldd L_X,u
            subd <man_x
            bpl .mx
            coma
            comb
            addd #1
.mx         tsta
            bne .out
            stb <t0
            ldb L_SIZEX,u
            addb #2
            cmpb <t0
            bls .out
            ldd L_Y,u
            subd <man_y
            bpl .my
            coma
            comb
            addd #1
.my         tsta
            bne .out
            stb <t0
            ldb L_SIZEY,u
            addb #3
            cmpb <t0
            bls .out
            tst L_DAMAGE,u
            beq .out
            lda L_DEATH,u
            jsr Man_Die
            lda L_FLAGS,u
            anda #~LF_ACTIVE&$FF
            sta L_FLAGS,u
.out        rts

; U=laser, over a destructible block, whose raw type is in cell_raw. Makes the block's entity if it has none yet.
Block_Activate
            lda <cell_raw
            sta <block_buried
            ldd L_Y,u
            jsr Div12
            stb <block_y
            ldd L_X,u
            jsr Div12
            std <block_x
; The same for the cell in block_x and block_y, whose raw type is in block_buried. Returns A=0 if the pool was full, else
; X=the block's entity. Keeps U.
block_make  ldd <block_x
            ; Is there one already? Blocks sit at the center of their cell.
            jsr Times12
            addd #6
            std <t0
            ldb <block_y
            clra
            jsr Times12
            addd #6
            std <t1
            ldx #ent_pool
            ldb <ent_count
.scan       lda E_KIND,x
            cmpa #KIND_NEUTRAL
            bne .no
            ldy E_VT,x
            beq .no
            ldy E_X,x
            cmpy <t0
            bne .no
            ldy E_Y,x
            cmpy <t1
            beq .have
.no         leax ENT_SIZE,x
            decb
            bne .scan
            ; Make one.
            pshs u
            lda <block_buried
            cmpa #8
            bne .plain
            lda #1
            bra .make
.plain      clra
.make       ldx <block_x
            ldb <block_y
            FAR PlatformDestructible_New
            cmpu #0
            beq .none
            jsr target_add
            tfr u,x
            puls u
.have       lda #1              ; X=its entity
            rts
.none       puls u
            clra
            rts

; ---- effects --------------------------------------------------------------------------------
; X=update handler (fixed ROM), Y=world y, D=world x. Returns U=zeroed record, Z clear; Z set if the pool is full.
; A full pool drops the effect: they are cosmetic.
Effect_Alloc
            std <t0
            stx <t1
            sty <t2
            ldu fx_free         ; the first slot that may be free
.scan       cmpu #effect_pool+EFFECT_COUNT*EFFECT_SIZE
            bhs .full
            ldx FX_UPDATE,u
            beq .found
            leau EFFECT_SIZE,u
            bra .scan
.full       orcc #$04
            rts
.found      leax EFFECT_SIZE,u
            stx fx_free
            ldd #0
            std 2,u
            std 4,u
            std 6,u
            std 8,u
            std 10,u
            std 12,u
            std 14,u
            std 16,u
            std 18,u
            std 20,u
            std 22,u
            leax EFFECT_SIZE,u
            cmpx fx_hi
            bls .fxm
            stx fx_hi
.fxm        ldd <t1
            std FX_UPDATE,u
            ldd <t0
            std FX_X,u
            ldd <t2
            std FX_Y,u
            andcc #$FB
            rts

; A handler ends its effect by clearing FX_UPDATE. Most of a level's remains are at rest, and look around only every 16 ticks.
Effect_UpdateAll
            ldu #effect_pool
            bra .check
.rest       lda <now+1
            adda FX_TIMER+1,u
            anda #15
            bne .skip
            ldx #Remains_Update
            stx FX_UPDATE,u
            lda #15             ; Remains_Update counts it up to the tick that looks
            sta FX_TIMER+1,u
            bra .run
.next       ldx FX_UPDATE,u
            beq .skip
            cmpx #Remains_Rest
            beq .rest
.run        jsr ,x
.skip       leau EFFECT_SIZE,u
.check      cmpu fx_hi
            blo .next
            ldx fx_hi           ; give back the slots at the top that are empty now
.back       cmpx #effect_pool
            bls .set
            ldd FX_UPDATE-EFFECT_SIZE,x
            bne .set
            leax -EFFECT_SIZE,x
            bra .back
.set        stx fx_hi
            rts
Effect_ClearAll
            jsr Still_Reset
            ldd #effect_pool
            std fx_hi
            std fx_free
            ldx #effect_pool
            ldd #EFFECT_COUNT*EFFECT_SIZE
.clr        clr ,x+
            subd #1
            bne .clr
            rts

; ---- scoring --------------------------------------------------------------------------------
Main_RecordKill
            ldx <kills
            leax 1,x
            stx <kills
            rts
; B=score units, X, Y=position. One unit is 100 points, and level_score counts units so it cannot overflow.
Main_RecordScore
            pshs b
            clra
            addd <level_score
            std <level_score
            puls b
            jmp ScoreText_New

; ---- spawner --------------------------------------------------------------------------------
; The object list is sorted by x, so the spawner keeps a window of the objects near the camera and walks that.
SPAWN_SYMBOLS equ 73
SPAWN_PER_TICK equ 6
SPAWN_NEAR_X equ 156        ; pixels from the camera: the view's half width plus a margin
SPAWN_NEAR_Y equ 114
DESPAWN_DIST equ 266
OFF_X       equ 138             ; half the view, a sprite, and room for what can happen in the four ticks before it asks again
OFF_Y       equ 84 
SLEEP_X     equ 162         ; half the view's width and a margin: the camera cannot cross it in the 10 ticks between checks
SLEEP_Y     equ 152         ; half its height, the view's dead zone, and the same margin

Spawner_Reset
            ldx #obj_spawned
            ldd #OBJ_BITS*2
.clr        clr ,x+
            subd #1
            bne .clr
            ldd #0
            std <spawn_cursor
            std <spawn_lo
            std <spawn_hi
            std spawn_clo
            std spawn_chi
            lda #1
            sta spawn_ev
            sta spawn_mv
            clr spawn_look
            clr spawn_want
            ldd #$FFFF
            std spawn_pcx
            std spawn_pcy
            std spawn_k1        ; and spawn_k2
            std spawn_new
            std spawn_new2
            ldd <lvl_objcount
            beq .out
            ; Settle the window, then consider everything in it once.
            ldd <lvl_objcount
.settle     pshs d
            jsr spawn_window
            puls d
            subd #1
            bne .settle
            ldd <spawn_lo
            std <spawn_cursor
.all        ldd <spawn_cursor
            cmpd <spawn_hi
            bhs .out
            jsr spawn_one
            ldd <spawn_cursor
            addd #1
            std <spawn_cursor
            bra .all
.out        rts

; A look at an object changes nothing unless something has changed since the last look: the window, the camera's height, an
; object forgotten, or a constructor that made nothing and wants another try. Until then the walk goes round without looking.
Spawner_Update
            ldd <lvl_objcount
            lbeq .out
            jsr spawn_window
            jsr far_rows
            ldd spawn_new
            cmpd #$FFFF
            beq .nonew
            ldx #$FFFF
            stx spawn_new
            ldx <spawn_cursor
            pshs x
            std <spawn_cursor
            jsr spawn_one
            puls x
            stx <spawn_cursor
.nonew
            ldd spawn_new2
            cmpd #$FFFF
            beq .nonew2
            ldx #$FFFF
            stx spawn_new2
            ldx <spawn_cursor
            pshs x
            std <spawn_cursor
            jsr spawn_one
            puls x
            stx <spawn_cursor
.nonew2
            ; Objects are in whole cells, so the camera's height matters only when an edge of its band crosses a cell.
            ldd <cam_y
            cmpd spawn_pcy
            beq .same_y
            std spawn_pcy
            addd #SPAWN_NEAR_Y
            jsr Div12
            cmpb spawn_k1
            beq .k1
            stb spawn_k1
            lda #1
            sta spawn_ev
.k1         ldd <cam_y
            addd #240+11-SPAWN_NEAR_Y   ; a multiple of 12 ahead, to stay above 0
            jsr Div12
            cmpb spawn_k2
            beq .same_y
            stb spawn_k2
            lda #1
            sta spawn_ev
.same_y     tst spawn_ev
            beq .quiet
            clr spawn_ev
            ldd <spawn_hi
            subd <spawn_lo
            addd #SPAWN_PER_TICK
            tsta
            beq .count
            ldb #255
.count      stb spawn_look
.quiet      tst spawn_look
            bne .walk
            rts
.walk       lda #SPAWN_PER_TICK
            sta <spawn_left
.next       ldd <spawn_cursor
            cmpd <spawn_hi
            blo .inside
            ldd <spawn_lo
            cmpd <spawn_hi
            bhs .out            ; nothing in the window
.inside     cmpd <spawn_lo
            bhs .go
            ldd <spawn_lo
.go         tst spawn_look
            beq .step
            dec spawn_look
            std <spawn_cursor
            jsr spawn_one
            ldd <spawn_cursor
.step       addd #1
            std <spawn_cursor
            dec <spawn_left
            bne .next
.out        rts

; Moves spawn_lo and spawn_hi one step each toward the camera's window of cells. With the camera in the same place and no step
; taken last time, or the same two cells, there is nothing to find.
spawn_window
            ldd <cam_x
            cmpd spawn_pcx
            bne .moved
            tst spawn_mv
            lbeq .out
            bra .steps
.moved      std spawn_pcx
            subd #SPAWN_NEAR_X
            bpl .lo_pos
            ldd #0
.lo_pos     jsr Div12
            pshs d
            ldd <cam_x
            addd #SPAWN_NEAR_X
            jsr Div12
            addd #1
            cmpd spawn_chi
            bne .new
            ldx ,s
            cmpx spawn_clo
            bne .new
            leas 2,s
            tst spawn_mv
            lbeq .out
            bra .steps
.new        std spawn_chi
            puls d
            std spawn_clo
.steps      clr spawn_mv
            ldd spawn_clo
            std <spawn_cell
            ; lo: first object with cell x >= the window's left edge.
            ldd <spawn_lo
            cmpd <lvl_objcount
            bhs .lo_back
            jsr spawn_obj_x
            cmpd <spawn_cell
            bhs .lo_back
            ldx <spawn_lo
            leax 1,x
            stx <spawn_lo
            inc spawn_mv
            bra .hi
.lo_back    ldd <spawn_lo
            beq .hi
            subd #1
            jsr spawn_obj_x
            cmpd <spawn_cell
            blo .hi
            ldx <spawn_lo
            leax -1,x
            stx <spawn_lo
            stx spawn_new       ; it has just come into the window
            inc spawn_mv
            ; hi: first object past the window's right edge.
.hi         ldd spawn_chi
            std <spawn_cell
            ldd <spawn_hi
            cmpd <lvl_objcount
            bhs .hi_back
            jsr spawn_obj_x
            cmpd <spawn_cell
            bhs .hi_back
            ldx <spawn_hi
            stx spawn_new2      ; it has just come into the window
            leax 1,x
            stx <spawn_hi
            inc spawn_mv
            bra .done
.hi_back    ldd <spawn_hi
            beq .done
            subd #1
            jsr spawn_obj_x
            cmpd <spawn_cell
            blo .done
            ldx <spawn_hi
            leax -1,x
            stx <spawn_hi
            inc spawn_mv
.done
.out        rts

; D=object index. Returns D=its cell x. The level bank is the home bank, so the data is visible. Preserves Y.
spawn_obj_x aslb
            rola
            aslb
            rola
            addd <lvl_objects
            tfr d,x
            ldd 1,x
            rts

bit_masks   fcb 1,2,4,8,16,32,64,128

; Considers the object at spawn_cursor. Objects are 4 bytes: symbol, cell x (2), cell y.
spawn_one   ; Already spawned or dead? The two bit arrays run one after the other. Most in the window are.
            ldd <spawn_cursor
            lsra
            rorb
            lsra
            rorb
            lsra
            rorb
            addd #obj_spawned
            tfr d,x
            lda ,x
            ora OBJ_BITS,x
            ldb <spawn_cursor+1
            andb #7
            ldx #bit_masks
            anda b,x
            bne .out
            ldd <spawn_cursor
            aslb
            rola
            aslb
            rola
            addd <lvl_objects
            tfr d,y
            ldb 3,y
            lda #12
            mul
            subd <cam_y
            addd #SPAWN_NEAR_Y
            cmpd #SPAWN_NEAR_Y*2
            bhi .out
            ; Spawn through the table: symbol * 4 gives constructor, bank, parameter.
            ldb ,y
            cmpb #SPAWN_SYMBOLS
            bhs .out
            clra
            aslb
            rola
            aslb
            rola
            addd #spawn_table
            tfr d,x
            ldd ,x
            beq .out            ; not an entity
            std <fc_s
            ldd 2,x
            sta <fc_sb
            stb <fc_sp
            ldx 1,y
            ldb 3,y
            pshs u
            ldu #0
            jsr spawn_call
            cmpu #0
            bne .made
            lda #1              ; pool full, or too few effect slots: try again when a slot comes free
            sta spawn_want
            bra .none
.made
            ldd <spawn_cursor
            std E_OBJ,u
            ldd <spawn_cursor
            ldx #obj_spawned
            jsr bit_set
.none       puls u
.out        rts

; Calls fc_s in bank fc_sb, with X, B and A holding the constructor's arguments.
spawn_call  stx <fc_x
            stb <fc_d+1
            ldb <cur_bank
            pshs b
            lda <fc_sb
            beq .fixed
            sta <cur_bank
            sta BANK_SELECT
.fixed      ldx <fc_x
            ldb <fc_d+1
            lda <fc_sp
            jsr [fc_s]
            puls b
            stb <cur_bank
            stb BANK_SELECT
            rts

; D=bit index, X=bit array. Z clear if the bit is set.
bit_test    pshs b
            lsra
            rorb
            lsra
            rorb
            lsra
            rorb
            leax d,x
            puls b
            andb #7
            lda ,x
.sh         tstb
            beq .sh_done
            lsra
            decb
            bra .sh
.sh_done    anda #1
            rts
