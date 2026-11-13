; aliens/wizard/*.as: the three-phase boss. Ported from ../port/src/wizard.c, wizard2.c, wizard3.c. Bank 14.
; Everything fits one bank, so nothing here needs FAR to reach anything else here. Bank 15 stays free.
;
; All boss state lives in wiz_ram: there is one boss, and pool slots are reused the moment an entity dies, so the C's
; habit of reading fields of dead objects does not carry over. Pointers to entities from other families are kept as
; handles (pointer + class descriptor, see wz_alive), and own phases are checked against their own descriptor.

; ---- wiz_ram ------------------------------------------------------------------------------------
; Controller
wc_phase    equ wiz_ram+0       ; 0 suspended, 1-3 running, 4 finished
wc_pending  equ wiz_ram+1       ; phase whose constructor found the pool full and must be retried
wc_sx       equ wiz_ram+2       ; startCellX (word)
wc_sy       equ wiz_ram+4       ; startCellY
wc_deaths   equ wiz_ram+5       ; initialDeaths + deaths, as one word
wc_p1reset  equ wiz_ram+7
wc_p2reset  equ wiz_ram+8
wc_p1       equ wiz_ram+9       ; phase records
wc_p2       equ wiz_ram+11
wc_p3       equ wiz_ram+13
wc_p1killed equ wiz_ram+15      ; phase 1 was brought to health <= 0
wc_flash    equ wiz_ram+16      ; ticks left of the final white flash
wc_needtrig equ wiz_ram+17      ; the trigger for another try found the pool full
; Scratch
wq_cx       equ wiz_ram+18
wq_cy       equ wiz_ram+20
wq_tx       equ wiz_ram+22
wq_ty       equ wiz_ram+24
wq_best     equ wiz_ram+26
wq_d        equ wiz_ram+28
wq_side     equ wiz_ram+30      ; $FF = none
wq_try      equ wiz_ram+31
wq_fx       equ wiz_ram+32
wq_fy       equ wiz_ram+34
wq_tmp      equ wiz_ram+36
wq_i        equ wiz_ram+38
wq_n        equ wiz_ram+39
wd_x        equ wiz_ram+40
wd_y        equ wiz_ram+42
wd_w        equ wiz_ram+44
wd_h        equ wiz_ram+45
wd_p        equ wiz_ram+46
wd_n        equ wiz_ram+48
wd_g        equ wiz_ram+49
wd_top      equ wiz_ram+50
wd_cur      equ wiz_ram+52
wd_phase    equ wiz_ram+54
; Phase 1
wp1_x       equ wiz_ram+56      ; 16.8
wp1_y       equ wiz_ram+59      ; 16.8
wp1_vx      equ wiz_ram+62
wp1_vy      equ wiz_ram+64
wp1_sx      equ wiz_ram+66      ; startPosition
wp1_sy      equ wiz_ram+68
wp1_t       equ wiz_ram+70
wp1_dist    equ wiz_ram+72      ; distortionStartTime
wp1_state   equ wiz_ram+74
wp1_head    equ wiz_ram+75
wp1_cached  equ wiz_ram+76
wp1_pause   equ wiz_ram+77
wp1_reset   equ wiz_ram+78
wp1_charged equ wiz_ram+79
wp1_support equ wiz_ram+80
wp1_fire    equ wiz_ram+81
wp1_chg     equ wiz_ram+82
wp1_scount  equ wiz_ram+83
wp1_seek    equ wiz_ram+84      ; 6 handles, 24 bytes
; Phase 3 borrows the start of wp1_seek: phase 1 never comes back once phase 3 exists. See p3_body_reuse.
wk_ok       equ wiz_ram+84      ; the body's entries in the last list can be reused
wk_gen      equ wiz_ram+85      ; dl_gen when they were made
wk_idx      equ wiz_ram+86      ; their first entry's index in that list
wk_y        equ wiz_ram+87      ; low bytes of what they depend on: y2, spr_ox, spr_oy, and G
wk_ox       equ wiz_ram+88
wk_oy       equ wiz_ram+89
wk_g        equ wiz_ram+90
; Phase 2
wp2_x       equ wiz_ram+108     ; 16.8
wp2_y       equ wiz_ram+111     ; word
wp2_cy      equ wiz_ram+113     ; cell row of the worm's center
wp2_state   equ wiz_ram+114
wp2_fixed   equ wiz_ram+115
wp2_fireh   equ wiz_ram+116
wp2_firec   equ wiz_ram+117
wp2_charged equ wiz_ram+118
wp2_open    equ wiz_ram+119     ; p2_hallwayOpen: outlives each worm
wp2_tstart  equ wiz_ram+120
wp2_tdist   equ wiz_ram+122
wp2_segt    equ wiz_ram+124
wp2_hall    equ wiz_ram+126     ; 10 slots of 5 bytes, one per mine: handle, pending. 50 bytes
wp2_barcol  equ wiz_ram+176     ; the barrier's columns the mouth has passed, 0 to P2_BAR_W
wp2_lo      equ wiz_ram+251     ; slots below this are done: behind the mouth, never to be made, and not alive
P2_SLOT_SIZE equ 5
P2_SLOTS    equ 10
P2_MINES    equ 10
P2_BAR_X    equ 48              ; the barrier: 4 + 44 + startX / 12, its first cell column
P2_BAR_W    equ 5
; Phase 3
wp3_x       equ wiz_ram+252     ; word: x2 never changes
wp3_y       equ wiz_ram+254     ; 16.8
wp3_starty  equ wiz_ram+257
wp3_cx      equ wiz_ram+259
wp3_cy      equ wiz_ram+261
wp3_tvel    equ wiz_ram+262     ; tentacleVelocity, 8.8 per tick
wp3_rel     equ wiz_ram+264     ; tentacleRelativePosition, 8.8
wp3_prevy   equ wiz_ram+266     ; low bytes of y2 last tick
wp3_t3      equ wiz_ram+268
wp3_t2      equ wiz_ram+270
wp3_state   equ wiz_ram+272
wp3_phase   equ wiz_ram+273
wp3_cached  equ wiz_ram+274
wp3_pause   equ wiz_ram+275
wp3_fire    equ wiz_ram+276
wp3_charged equ wiz_ram+277
wp3_cur     equ wiz_ram+278
wp3_fireh   equ wiz_ram+279
wp3_create  equ wiz_ram+280
wp3_red     equ wiz_ram+281     ; palette index in use for red: 1 or 9, see p3_heal
wp3_heal    equ wiz_ram+282
wp3_ly      equ wiz_ram+283     ; what the body looked like last tick
wp3_lg      equ wiz_ram+285
wp3_lc      equ wiz_ram+286
wp3_tcur    equ wiz_ram+287     ; tentacle dot cycle
wp3_lcount  equ wiz_ram+288
wp3_bcount  equ wiz_ram+289
wp3_mcount  equ wiz_ram+290
wp3_seeker  equ wiz_ram+291     ; handle, 4 bytes
wp3_sturret equ wiz_ram+295     ; WizardSeekerTurret or 0
wp3_laser   equ wiz_ram+297     ; 6 of: pointer, x, y, heading. 7 bytes each, 42 bytes
WLT_ENTRY    equ 7
wp3_beam    equ wiz_ram+339     ; 3 of: pointer, x, end1y, end2y. 8 bytes each, 24 bytes
WBT_ENTRY    equ 8
wp3_minion  equ wiz_ram+363     ; 8 handles, 32 bytes
wz_peek     equ wiz_ram+395     ; RAM copy of wz_peek_src, 17 bytes
WIZ_RAM_END equ wiz_ram+412
            assert WIZ_RAM_END<=wiz_ram+512,"wiz_ram overflow"

; Handle layout
WZH_PTR       equ 0
WZH_VT        equ 2

; Effect constants that the C spells by name.
WZ_DIST_OFFSET equ 0
WZ_DIST_STATIC equ 1
WZ_DIST_SIZE_1 equ 3
WZ_DIST_SIZE_2 equ 6
WZ_DIST_OFFSET_1 equ 2
WZ_DIST_OFFSET_2 equ 6
WZ_DIST_FADE_FORWARD equ 0
WZ_DIST_FADE_BACKWARD equ 1
WZ_BEAM_VERTICAL equ 1

; Constructors from other families may return their record in U. Ours is kept around them.
WZ_KEEPU       macro target
            pshs u
            jsr \target
            puls u
            endm

            bank 11
            org entities_end
            ; A descriptor or handler at address 0 would read as "free slot" or "inherit".
            fcb 0,0

; ---- shared helpers -----------------------------------------------------------------------------
; D = now - E_START.
wz_t        ldd <now
            subd E_START,u
            rts

wz_neg      coma
            comb
            addd #1
            rts

; D = D mod X. D must be non-negative.
wz_mod      stx wq_tmp
.l          cmpd wq_tmp
            blo .out
            subd wq_tmp
            bra .l
.out        rts

; D = D / X, unsigned. Clobbers wq_tmp and wq_d. Divisor 0 returns 0.
wz_div      stx wq_tmp
            beq .zero
            std wq_d
            ldd #0
            ldx #16
            pshs x
.step       lsl wq_d+1
            rol wq_d
            rolb
            rola
            cmpd wq_tmp
            blo .no
            subd wq_tmp
            inc wq_d+1
.no         dec 1,s
            bne .step
            puls x
            ldd wq_d
            rts
.zero       ldd #0
            rts

; X = address of a handle. Z clear when the entity is alive, with Y = entity.
wz_alive    ldy WZH_PTR,x
            beq .out
            ldd E_VT,y
            cmpd WZH_VT,x
            bne .dead
            lda E_FLAGS,y
            bita #EF_ACTIVE
            rts
.dead       orcc #$04
.out        rts

; X = address of a handle, Y = entity or 0.
wz_store    sty WZH_PTR,x
            beq .out
            ldd E_VT,y
            std WZH_VT,x
.out        rts

; X = address of a handle. Kills the entity if it is alive.
wz_die_h    bsr wz_alive
            beq wz_die_out
; Y = entity to kill.
wz_die_y    pshs u
            tfr y,u
            jsr Entity_Die
            puls u
wz_die_out  rts

; Single-byte effect constructors take the value in A or B depending on who wrote them: give it in both.
; X, Y = position, B = value.
wz_circle   tfr b,a
            WZ_KEEPU Circle_New
            rts
wz_explosion tfr b,a
            WZ_KEEPU Explosion_New
            rts
wz_circlelarge tfr b,a
            WZ_KEEPU CircleLarge_New
            rts
wz_impact_green
            lda #COLOR_GREEN
            tfr a,b
            WZ_KEEPU LaserImpact_New
            rts
; X, Y = position, A = size. Red.
wz_circle_red
            ldb #COLOR_RED
            WZ_KEEPU CircleColored_New
            rts
; X, Y = position, A = direction.
wz_fadein   tfr a,b
            WZ_KEEPU DistortionFadeIn_New
            rts
; X, Y = position, A = type, B = size, arg0 = offset. The C: Distortion_New(type, size, offset, x, y).
wz_distortion
            WZ_KEEPU Distortion_New
            rts
; A = offset x, B = offset y, U = owner: Charge_New(offsetX, offsetY, owner).
wz_charge   stu <arg0
            WZ_KEEPU Charge_New
            rts
; Target the man.
wz_aim_man  ldd <man_x
            std <arg0
            ldd <man_y
            std <arg1
            rts

; ---- terrain rectangles -------------------------------------------------------------------------
; Followed inline by: type, dx, dy, w, h. wz_rect_w is relative to the controller's start cell, wz_rect_3 to phase 3's
; start cell, wz_rect_a to absolute column 0 and the controller's row (Wizard_p2_3's startX is always 0, see P2_New).
wz_rect_3   ldx wp3_cx
            lda wp3_cy
            bra wz_rect_i
wz_rect_a   ldx #0
            lda wc_sy
            bra wz_rect_i
wz_rect_w   ldx wc_sx
            lda wc_sy
wz_rect_i   puls y
            pshs a
            ldb 1,y
            sex
            leax d,x
            ldb 2,y
            addb ,s+
            pshs b
            clra
            ldb 3,y
            std <arg0
            ldb 4,y
            std <arg1
            lda ,y
            puls b
            leay 5,y
            pshs y
            jmp Main_SetCellRectangle

; ---- Wizard.as: the controller ------------------------------------------------------------------
WZ_TRIGGER_RANGE equ 120

Wizard_vt   fdb Wizard_Update,0,0,0,0

; Spawn-table form: X=cell x, B=cell y. Returns U=record or 0.
Wizard_New  pshs b,x
            ldx #Wizard_vt
            lda #bank(Wizard_vt)
            ldb #KIND_ALIEN
            jsr Ent_Alloc
            bne .ok
            puls b,x,pc
            ; Wizard_p2_3_ResetHallwayArrays and all the other statics.
.ok         ldx #wiz_ram
.clr        clr ,x+
            cmpx #WIZ_RAM_END
            blo .clr
            lda #1              ; from now on the blit queue and the terrain list keep out of this RAM
            sta wiz_live
            jsr tl_boss
            ldx 1,s
            ldb ,s
            stx wc_sx
            stb wc_sy
            jsr Alien_Init
            ldd E_X,u
            addd #6
            std E_X,u
            ldd E_Y,u
            addd #6
            std E_Y,u
            ldd #512
            std E_HEALTH,u
            lda E_FLAGS,u
            anda #~EF_SOLID&$FF
            ora #EF_KEEP        ; spawned by the camera, but it runs the whole fight
            sta E_FLAGS,u
            lda #6
            sta E_SIZEX,u
            sta E_SIZEY,u
            ldd #240
            std E_SPRITE,u
            ldd <now
            std E_START,u
            jsr Main_AddToKillCount
            puls b,x,pc

Wizard_Update
            ; The final white flash is a palette change: see p3_dying.
            lda wc_flash
            beq .noflash
            dec wc_flash
            bne .noflash
            jsr wz_palette_restore
.noflash    lda wc_pending
            beq .go
            jsr wz_build_phase
            lda wc_pending
            beq .go
            rts
.go         lda wc_phase
            bne .running
            tst wc_needtrig
            beq .check
            jsr wz_make_trigger
.check      jsr wizard_TriggerCheck
            lda wc_phase
.running    cmpa #1
            bne .n1
            ; Phase1Update, then ManDeathCheck.
            tst wc_p1killed
            beq .p1_dc
            jsr wizard_SetupPhase2
.p1_dc      jmp wizard_ManDeathCheck
.n1         cmpa #2
            bne .n2
            jsr wizard_ManDeathCheck
            lda wc_phase
            cmpa #2
            bne .out
            lda wc_pending      ; a replacement worm may still be waiting for a slot
            bne .out
            ldy wc_p2
            ldd E_VT,y
            cmpd #P2_vt
            bne .p2_over
            lda E_FLAGS,y
            bita #EF_ACTIVE
            bne .out
.p2_over    jmp wizard_SetupPhase3
.n2         cmpa #3
            bne .out
            ldy wc_p3
            ldd E_VT,y
            cmpd #P3_vt
            bne .p3_over
            lda E_FLAGS,y
            bita #EF_ACTIVE
            bne .p3_dc
.p3_over    lda #4
            sta wc_phase
.p3_dc      jmp wizard_ManDeathCheck
.out        rts

; Runs the constructor of the phase in wc_pending. The pending flag stays up if the pool is full.
wz_build_phase
            pshs u
            lda wc_pending
            cmpa #1
            bne .n1
            ldx wc_sx
            leax 6,x
            ldb wc_sy
            addb #4
            lda wc_p1reset
            jsr P1_New
            stu wc_p1
            bra .done
.n1         cmpa #2
            bne .n2
            ldd wc_sx
            subd #3
            tfr d,x
            ldb wc_sy
            addb #6
            jsr P2_New
            stu wc_p2
            bra .done
.n2         ldd wc_sx
            addd #70            ; WIZARD_PHASE_2_TRAVEL_DISTANCE
            tfr d,x
            ldb wc_sy
            addb #6
            jsr P3_New
            stu wc_p3
.done       cmpu #0
            beq .full
            clr wc_pending
.full       puls u,pc

wizard_SetCameraOnArena
            ldd E_X,u
            addd #48            ; (SCREEN_WIDTH / 2 - 4) * TILE_SIZE
            std <cam_fixed_x
            ldd E_Y,u
            addd #54            ; (SCREEN_HEIGHT / 2) * TILE_SIZE
            std <cam_fixed_y
            lda #1
            sta <cam_fixed
            rts

wizard_SetupPhase1
            bsr wizard_SetCameraOnArena
            jsr wz_rect_w       ; SetupBarriers1(true)
            fcb PLATFORM,-3,5,3,1
            inc wc_p1reset
            lda #1
            sta wc_phase
            sta wc_pending
            clr wc_p1killed
            jmp wz_build_phase

wizard_SetupPhase2
            lda #2
            sta wc_phase
            sta wc_pending
            jsr wz_build_phase
            jsr wz_rect_w       ; SetupHallwayLeft
            fcb EMPTY,-6,5,8,3
            bsr wizard_SetCameraOnArena
            inc wc_p2reset
            lda wc_p2reset
            cmpa #1
            bne .out
            pshs u
            ldx wc_sx
            leax 6,x
            ldb wc_sy
            addb #7
            clra
            FAR RespawnPoint_New
            cmpu #0
            beq .none
            FAR RespawnPoint_Activate
.none       puls u
.out        rts

wizard_SetupPhase3
            lda #3
            sta wc_phase
            sta wc_pending
            jsr wz_build_phase
            ; Draw_SetCameraTarget((cellX - 4.5) * 12, (cellY + 0.5) * 12), with cellX = sx + 70, cellY = sy + 6.
            ldd wc_sx
            addd #70
            jsr Times12
            subd #54
            std <cam_fixed_x
            ldb wc_sy
            clra
            addd #6
            jsr Times12
            addd #6
            std <cam_fixed_y
            lda #1
            sta <cam_fixed
            rts

wizard_ManDeathCheck
            ldd <deaths
            cmpd wc_deaths
            beq .out
            std wc_deaths
            lda wc_phase
            cmpa #1
            bne .n1
            clr wc_phase
            jsr wz_rect_w       ; SetupBarriers1(false)
            fcb EMPTY,-3,5,3,1
            ; wc_pending may still hold phase 1 if the pool was full: nothing to fade then.
            lda wc_pending
            bne .nofade1
            pshs u
            ldu wc_p1
            jsr P1_FadeOut
            puls u
.nofade1    clr wc_pending
            clr <cam_fixed
            jmp wz_make_trigger
.n1         cmpa #2
            bne .out
            clr wc_phase
            lda wc_pending
            bne .nofade2
            pshs u
            ldu wc_p2
            jsr P2_FadeOut
            puls u
.nofade2    clr wc_pending
            jmp wizard_SetupPhase2
.out        rts

; The trigger that restarts the fight. Without it the player could never restart, so it is retried until it fits.
wz_make_trigger
            pshs u
            ldx wc_sx
            leax 1,x
            ldb wc_sy
            addb #5
            clra
            FAR Trigger_New
            clra
            cmpu #0
            bne .made
            inca
.made       sta wc_needtrig
            puls u,pc

wizard_TriggerCheck
            ; The C's WIZARD_SUSPEND_TIME of 10 ms is below one tick: this is every tick.
            FAR Trigger_GetTrigger
            tsta
            beq .out
            ldd <deaths
            std wc_deaths
            ldd trigger_x
            subd E_X,u
            jsr Abs_D
            cmpd #WZ_TRIGGER_RANGE
            bgt .out
            ldd trigger_y
            subd E_Y,u
            jsr Abs_D
            cmpd #WZ_TRIGGER_RANGE
            bgt .out
            jmp wizard_SetupPhase1
.out        rts

; ---- WizardBeamTurret.as ------------------------------------------------------------------------
WBT_ORIENT   equ E_DATA+0
WBT_END2Y    equ E_DATA+1
WBT_CHARGED  equ E_DATA+3

WBT_vt      fdb WBT_Update,0,0,0,0

; Returns B = the last cell row before PLATFORM. X=cell x, B=first row, A=direction (1 or -1). Y preserved.
wbt_endpoint
            stx wq_cx
            stb wq_cy
            sta wq_try
.scan       ldx wq_cx
            ldb wq_cy
            jsr Main_GetCell
            cmpa #PLATFORM
            beq .found
            lda wq_cy
            adda wq_try
            sta wq_cy
            bra .scan
.found      ldb wq_cy
            subb wq_try
            rts

; A=orientation, X=cell x, B=cell y. Returns U=record or 0. The caller saves its own U.
WizardBeamTurret_New
            pshs a,b,x
            ldx #WBT_vt
            lda #bank(WBT_vt)
            ldb #KIND_ALIEN
            jsr Ent_Alloc
            bne .ok
            puls a,b,x,pc
.ok         ldx 2,s
            ldb 1,s
            jsr Alien_Init
            lda ,s
            sta WBT_ORIENT,u
            ; Only WZ_BEAM_VERTICAL is ever built, as in the C.
            ldx 2,s
            ldb 1,s
            lda #-1
            jsr wbt_endpoint
            clra
            jsr Times12
            std E_Y,u           ; end1Y = row * 12
            ldx 2,s
            ldb 1,s
            lda #1
            jsr wbt_endpoint
            clra
            jsr Times12
            addd #12
            std WBT_END2Y,u      ; end2Y = row * 12 + 12
            ldd E_X,u
            addd #6
            std E_X,u           ; end1X, end2X
            ldd #152
            std E_SPRITE,u
            lda #4
            sta E_SIZEX,u
            sta E_SIZEY,u
            ldx E_X,u
            ldy E_Y,u
            ldb #4
            jsr wz_circle
            ldx E_X,u
            ldy WBT_END2Y,u
            ldb #4
            jsr wz_circle
            leas 4,s
            rts

; DrawSelf: both ends, or end 1 alone in white while flashing.
WBT_Update  lda E_FLAGS,u
            bita #EF_ACTIVE
            beq .out
            bita #EF_FLASHING
            beq .plain
            ldb <now+1
            subb E_FLASHT,u
            cmpb #ALIEN_FLASH_T
            bls .flash
            lda E_FLAGS,u
            anda #~EF_FLASHING&$FF
            sta E_FLAGS,u
.plain      ldx E_X,u
            leax -6,x
            ldy E_Y,u
            leay -6,y
            ldd E_SPRITE,u
            jsr Draw_Sprite
            ldx E_X,u
            leax -6,x
            ldy WBT_END2Y,u
            leay -6,y
            ldd E_SPRITE,u
            jmp Draw_Sprite
.flash      lda #COLOR_WHITE
            sta <draw_color
            ldx E_X,u
            leax -6,x
            ldy E_Y,u
            leay -6,y
            ldd E_SPRITE,u
            jmp Draw_ColoredSprite
.out        rts

; WizardBeamTurret.ChargeEffect. U=turret.
WBT_ChargeEffect
            lda #1
            sta WBT_CHARGED,u
            clra
            ldb #7
            jsr wz_charge
            ldd WBT_END2Y,u
            subd E_Y,u
            subd #7
            clra
            jmp wz_charge

; ---- WizardLaserTurret.as -----------------------------------------------------------------------
WLT_HEAD     equ E_DATA+0
WLT_CHARGED  equ E_DATA+1
WZ_TURRET_CHARGE equ 69

WLT_vt      fdb WLT_Update,0,0,0,0

; X=cell x, B=cell y. Returns U=record or 0. The caller saves its own U.
WizardLaserTurret_New
            pshs b,x
            ldx #WLT_vt
            lda #bank(WLT_vt)
            ldb #KIND_ALIEN
            jsr Ent_Alloc
            bne .ok
            puls b,x,pc
.ok         ldx 1,s
            ldb ,s
            jsr Alien_Init
            ldd E_X,u
            addd #6
            std E_X,u
            ldd E_Y,u
            addd #6
            std E_Y,u
            ; GetHeadingY: above first, then below.
            ldx 1,s
            ldb ,s
            decb
            jsr Main_GetCell
            ldb #1
            cmpa #PLATFORM
            beq .have
            ldx 1,s
            ldb ,s
            incb
            jsr Main_GetCell
            ldb #-1
            cmpa #PLATFORM
            beq .have
            clrb
.have       stb WLT_HEAD,u
            ; e->y -= 6 * heading
            beq .noshift
            bmi .up
            ldd E_Y,u
            subd #6
            bra .sety
.up         ldd E_Y,u
            addd #6
.sety       std E_Y,u
.noshift    lda #4
            sta E_SIZEX,u
            lda #3
            sta E_SIZEY,u
            ldd #165
            std E_SPRITE,u
            ldx E_X,u
            ldy E_Y,u
            ldb #4
            jsr wz_circle
            puls b,x,pc

WLT_Update  lda E_FLAGS,u
            bita #EF_ACTIVE
            beq .out
            tst WLT_CHARGED,u
            beq .plain
            ldx E_X,u
            leax -6,x
            ldd E_Y,u
            tst WLT_HEAD,u
            bpl .below
            subd #8             ; 6 + 2
            bra .draw
.below      subd #5             ; 6 - 1
.draw       tfr d,y
            ldd #WZ_TURRET_CHARGE
            jsr Draw_Sprite
.plain      ldd E_SPRITE,u
            jmp Alien_DrawSelf
.out        rts

; ---- WizardSeekerTurret.as ----------------------------------------------------------------------
WST_SEEKER   equ E_DATA+0        ; handle, 4 bytes
WST_CHARGED  equ E_DATA+4
WST_HEAD     equ E_DATA+5
WST_SPRITE equ 153

WST_vt      fdb WST_Update,WST_Hurt,WST_Die,0,0

; X=cell x, B=cell y. Returns U=record or 0. The caller saves its own U.
WizardSeekerTurret_New
            pshs b,x
            ldx #WST_vt
            lda #bank(WST_vt)
            ldb #KIND_ALIEN
            jsr Ent_Alloc
            bne .ok
            puls b,x,pc
.ok         ldx 1,s
            ldb ,s
            jsr Alien_Init
            ldd E_X,u
            addd #6
            std E_X,u
            ldd E_Y,u
            addd #6
            std E_Y,u
            ; GetHeadingX: left first, then right.
            ldd 1,s
            subd #1
            tfr d,x
            ldb ,s
            jsr Main_GetCell
            ldb #1
            cmpa #PLATFORM
            beq .have
            ldx 1,s
            leax 1,x
            ldb ,s
            jsr Main_GetCell
            ldb #-1
            cmpa #PLATFORM
            beq .have
            clrb
.have       stb WST_HEAD,u
            beq .noshift
            bmi .left
            ldd E_X,u
            subd #6
            bra .setx
.left       ldd E_X,u
            addd #6
.setx       std E_X,u
.noshift    lda #4
            sta E_SIZEX,u
            lda #3
            sta E_SIZEY,u
            ldx E_X,u
            ldy E_Y,u
            ldb #4
            jsr wz_circle
            puls b,x,pc

WST_Update  lda E_FLAGS,u
            bita #EF_ACTIVE
            beq .out
            tst WST_CHARGED,u
            beq .plain
            ldd E_X,u
            tst WST_HEAD,u
            bpl .right
            subd #8             ; 6 + 2
            bra .draw
.right      subd #5             ; 6 - 1
.draw       tfr d,x
            ldy E_Y,u
            leay -6,y
            ldd #WZ_TURRET_CHARGE
            jsr Draw_Sprite
.plain      ldd #WST_SPRITE
            jmp Alien_DrawSelf
.out        rts

WST_Hurt    ldx <hurt_laser
            beq .silent
            ldd L_Y,x
            tfr d,y
            ldx L_X,x
            jsr wz_impact_green
.silent     lda #SND_NO_DAMAGE
            jmp Sound_Play

WST_Die     leax WST_SEEKER,u
            jsr wz_die_h
            jsr Entity_DeathEffect
            lda E_FLAGS,u
            anda #~EF_ACTIVE&$FF
            sta E_FLAGS,u
            rts

; WizardSeekerTurret.ChargeEffect. U=turret.
WST_ChargeEffect
            leax WST_SEEKER,u
            jsr wz_alive
            bne .out            ; its seeker is still flying
            lda #1
            sta WST_CHARGED,u
            clra
            clrb
            jmp wz_charge
.out        rts

; WizardSeekerTurret.Fire. U=turret. Returns A=1 if it fired.
WST_Fire    tst WST_CHARGED,u
            bne .fire
            clra
            rts
.fire       clr WST_CHARGED,u
            lda #SND_ALIEN_FIRE
            jsr Sound_Play
            ldx E_X,u
            ldy E_Y,u
            ldb #4
            jsr wz_circle
            ldd #0
            std <arg0
            std <arg1
            ldb WST_HEAD,u
            sex
            addd E_X,u
            tfr d,x
            ldy E_Y,u
            pshs u
            FAR Seeker_New
            tfr u,y
            puls u
            leax WST_SEEKER,u
            jsr wz_store
            lda #1
            rts

; ---- Wizard_p1_4.as -----------------------------------------------------------------------------
P1S_WAIT    equ 0
P1S_INTRO   equ 1
P1S_CHARGE  equ 2
P1S_JUMP1   equ 3
P1S_JUMP2   equ 4
P1S_PAUSE   equ 5
P1S_FIRE1   equ 6
P1S_BEGIN2  equ 7
P1S_FIRE2   equ 8

P1_CHARGE_SPEED equ 563         ; 66 px/s
P1_CHARGE_ACCEL equ 27          ; 96 px/s^2
P1_GRAVITY  equ 109             ; 384 px/s^2
P1_VY_MAX   equ 2048            ; 8 px a tick: a bigger step would tunnel the floor at 30 Hz
P1_WAIT_T   equ 30
P1_INTRO_T  equ 135
P1_J1X      equ 435             ; 51 px/s
P1_J1Y      equ 1178            ; 138 px/s
P1_J1_PAUSE equ 8
P1_J2X      equ 410             ; 48 px/s
P1_J2Y      equ 717             ; 84 px/s
P1_LEDGE    equ 24
P1_FIRE_COUNT equ 3
P1_FIRE_RATE equ 9
P1_F1_PAUSE equ 15
P1_FIRE_COUNT2 equ 6
P1_FIRE_RATE2 equ 15
P1_CHARGE_COUNT equ 3
P1_CENTER_SPEED equ 205         ; 410 / 2: see p1u_begin2
P1_BASE_SPRITE equ 276
P1_CLOAK_T  equ 6
P1_AURA_STABLE_T equ 8
P1_AURA_FLICKER_T equ 1
P1_LASER_SPEED equ 614          ; LASER3_SPEED_2, 72 px/s

P1_vt       fdb P1_Update,P1_Hurt,P1_Die,P1_DeathEffect,P1_HitEffect

; A=resetCount, X=cell x, B=cell y. Returns U=record or 0. The caller saves its own U.
P1_New      pshs a,b,x
            ldx #P1_vt
            lda #bank(P1_vt)
            ldb #KIND_ALIEN
            jsr Ent_Alloc
            bne .ok
            puls a,b,x,pc
.ok         ldx 2,s
            ldb 1,s
            jsr Alien_Init
            lda E_FLAGS,u
            ora #EF_KEEP        ; each phase of the boss runs however far the view is
            sta E_FLAGS,u
            ldd E_X,u
            addd #6
            std wp1_x
            std wp1_sx
            ldd E_Y,u
            addd #6
            std wp1_y
            std wp1_sy
            clr wp1_x+2
            clr wp1_y+2
            ldd #0
            std wp1_vx
            std wp1_vy
            std wp1_dist
            ldd #768
            std E_HEALTH,u
            lda #45
            sta E_SCORE,u
            lda #5
            sta E_SIZEX,u
            lda #6
            sta E_SIZEY,u
            jsr Main_AddToKillCount
            clr wp1_chg
            clr wp1_scount
            clr wp1_charged
            clr wp1_support
            clr wp1_fire
            lda #-1
            sta wp1_head
            lda ,s
            sta wp1_reset
            lda #P1S_WAIT
            jsr p1_switch
            ldd #146
            std E_SPRITE,u
            leas 4,s
            rts

; A=frame.
p1_sprite   ldb wp1_head
            bmi .left
            adda #6
.left       tfr a,b
            clra
            addd #P1_BASE_SPRITE
            std E_SPRITE,u
            rts

; D = magnitude, returned with the sign of the heading.
p1_h        tst wp1_head
            bpl .out
            jmp wz_neg
.out        rts

p1_toward_center
            ldd wp1_x
            cmpd wp1_sx
            bge .left
            lda #1
            bra .set
.left       lda #-1
.set        sta wp1_head
            rts
p1_toward_man
            ldd <man_x
            cmpd wp1_x
            blt .left
            lda #1
            bra .set
.left       lda #-1
.set        sta wp1_head
            rts

; SwitchState. A=state.
p1_switch   sta wp1_state
            ldx <now
            stx E_START,u
            cmpa #P1S_INTRO
            bne .n1
            clra
            jsr p1_sprite
            lda wp1_reset
            cmpa #1
            bne .nomsg
            jsr p1_trigger_message
.nomsg      ldd wp1_sx
            addd #60
            std wp1_x
            ldd wp1_sy
            addd #18
            std wp1_y
            clr wp1_x+2
            clr wp1_y+2
            ldx wp1_x
            ldd wp1_y
            subd #18
            tfr d,y
            lda #WZ_DIST_FADE_FORWARD
            jmp wz_fadein
.n1         cmpa #P1S_CHARGE
            bne .n2
            inc wp1_chg
            lda #1
            jsr p1_sprite
            ldd #P1_CHARGE_SPEED
            jsr p1_h
            std wp1_vx
            rts
.n2         cmpa #P1S_PAUSE
            bne .n3
            clra
            jmp p1_sprite
.n3         cmpa #P1S_JUMP1
            bne .n4
            ldd #P1_J1X
            jsr p1_h
            std wp1_vx
            ldd #-P1_J1Y
            std wp1_vy
            clr wp1_support
            lda #1
            jmp p1_sprite
.n4         cmpa #P1S_JUMP2
            bne .n5
            jsr p1_toward_center
            ldd #P1_J2X
            jsr p1_h
            std wp1_vx
            ldd #-P1_J2Y
            std wp1_vy
            clr wp1_support
            lda #1
            jmp p1_sprite
.n5         cmpa #P1S_FIRE1
            bne .n6
            clr wp1_fire
            jsr p1_toward_man
            lda #3
            jmp p1_sprite
.n6         cmpa #P1S_BEGIN2
            bne .n7
            jsr p1_toward_center
            lda #1
            jmp p1_sprite
.n7         cmpa #P1S_FIRE2
            bne .out
            clr wp1_scount
            clr wp1_fire
            lda #5
            jmp p1_sprite
.out        rts

; TriggerMessage: the wall banner nearest the boss gets the level's next message.
p1_trigger_message
            pshs u
            FAR MessageTrigger_GetTriggerCount
            sta wq_i
            FAR MessageTrigger_IncrementTriggerCount
            puls u
            ; Main_GetMessage(index). Bank 10: a word per level, offset of a count byte followed by a word per message.
            ldx #wz_peek_src
            ldy #wz_peek
            ldb #wz_peek_end-wz_peek_src
.copy       lda ,x+
            sta ,y+
            decb
            bne .copy
            ldb <level_bank     ; the table's index is the level, as in nt_get_message
            aslb
            clra
            tfr d,x
            jsr wz_peek
            addd #1
            std wq_tx
            ldb wq_i
            clra
            aslb
            rola
            addd wq_tx
            tfr d,x
            jsr wz_peek
            std <arg0
            ldx E_X,u
            ldy E_Y,u
            WZ_KEEPU MessageBanner_TriggerNearestBanner
            rts

; Reads the word at X in bank 10. Copied to RAM to run: code in a bank cannot switch away from itself.
wz_peek_src lda #10
            sta BANK_SELECT
            ldd ,x
            pshs a
            lda <cur_bank
            sta BANK_SELECT
            puls a
            rts
wz_peek_end
            assert wz_peek_end-wz_peek_src<=17,"wz_peek: too long"

P1_Update   lda E_FLAGS,u
            bita #EF_ACTIVE
            bne .live
            rts
.live       jsr wz_t
            std wp1_t
            lda wp1_state
            bne .state
            ldd wp1_t
            cmpd #P1_WAIT_T
            ble .state
            lda #P1S_INTRO
            jsr p1_switch
.state      lda wp1_state
            cmpa #P1S_INTRO
            beq p1u_intro
            cmpa #P1S_CHARGE
            lbeq p1u_charge
            cmpa #P1S_PAUSE
            lbeq p1u_pause
            cmpa #P1S_JUMP1
            lbeq p1u_jump1
            cmpa #P1S_JUMP2
            lbeq p1u_jump2
            cmpa #P1S_BEGIN2
            lbeq p1u_begin2
            cmpa #P1S_FIRE1
            lbeq p1u_fire1
            cmpa #P1S_FIRE2
            lbeq p1u_fire2
p1u_end     ldd wp1_x
            std E_X,u
            ldd wp1_y
            std E_Y,u
            jsr Alien_ContactKillCheck
            lda E_FLAGS,u
            bita #EF_ACTIVE
            beq .out
            ; Intro: the C overlays a white sprite on a quarter of the frames. Swapping it in keeps the entry count.
            lda wp1_state
            cmpa #P1S_INTRO
            bne .plain
            jsr wz_t
            andb #3
            cmpb #2
            bne .plain
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
.out        rts

p1u_intro   jsr p1_aura_stable
            ldd wp1_t
            cmpd #68            ; 0.5 * P1_INTRO_DURATION
            bge .settled
            ; y = start + 21 - 9 * k, k = t / 67.5. 9 / 67.5 * 256 = 34.
            ldd wp1_sy
            addd #21
            std wp1_y
            clr wp1_y+2
            ldb wp1_t+1
            lda #34
            mul
            jsr wz_neg
            ldx #wp1_y
            jsr add_8_8
            bra .tcheck
.settled    ldd wp1_sy
            addd #12
            std wp1_y
            clr wp1_y+2
.tcheck     ldd wp1_t
            cmpd #P1_INTRO_T
            ble p1u_end
            jsr MessageBanner_ResetBanners
            lda #P1S_CHARGE
            jsr p1_switch
            lbra p1u_end

; Applies velocity and gravity, then collides.
p1_move     ldd wp1_vx
            ldx #wp1_x
            jsr add_8_8
            ldd wp1_vy
            ldx #wp1_y
            jsr add_8_8
            ldd wp1_vy
            addd #P1_GRAVITY
            cmpd #P1_VY_MAX
            ble .ok
            ldd #P1_VY_MAX
.ok         std wp1_vy
            jmp p1_collide

p1_cloak    ldd wp1_t
            ldx #P1_CLOAK_T
            jsr wz_mod
            cmpb #3
            blo .f1
            lda #2
            jmp p1_sprite
.f1         lda #1
            jmp p1_sprite

p1u_charge  jsr p1_cloak
            ldd wp1_vx
            jsr Abs_D
            cmpd #P1_CHARGE_SPEED
            bge .fast
            ldd #P1_CHARGE_ACCEL
            jsr p1_h
            addd wp1_vx
            std wp1_vx
.fast       jsr p1_move
            ; The cell ahead at the ledge offset.
            ldd #P1_LEDGE
            jsr p1_h
            addd wp1_x
            jsr Div12
            std wq_tx
            ldd wp1_y
            jsr Div12
            ldx wq_tx
            jsr Main_GetCell
            tsta
            beq .clear
            lda #P1S_JUMP1
            jsr p1_switch
            ; x = cell * 12 - heading * 24 + 6 - heading * 6, the wall-facing edge.
            ldd wq_tx
            jsr Times12
            std wp1_x
            ldd #P1_LEDGE+6
            jsr p1_h
            jsr wz_neg
            addd #6
            addd wp1_x
            std wp1_x
            clr wp1_x+2
.clear      jsr p1_aura_flicker
            lbra p1u_end

p1u_pause   ldd wp1_t
            cmpb wp1_pause
            blo .wait
            lda wp1_cached
            jsr p1_switch
.wait       jsr p1_aura_stable
            lbra p1u_end

p1u_jump1   jsr p1_cloak
            jsr p1_move
            tst wp1_support
            beq .air
            jsr p1_toward_man
            lda #P1S_PAUSE
            jsr p1_switch
            lda #P1_J1_PAUSE
            sta wp1_pause
            lda #P1S_FIRE1
            sta wp1_cached
.air        jsr p1_aura_stable
            lbra p1u_end

p1u_jump2   jsr p1_cloak
            jsr p1_move
            tst wp1_support
            beq .air
            lda #P1S_CHARGE
            jsr p1_switch
.air        jsr p1_aura_flicker
            lbra p1u_end

; Toward the start position at P1_CENTER_SPEED. Distance is max + 3/8 min, good enough for this short trip.
p1u_begin2  jsr p1_cloak
            ldd wp1_sx
            subd wp1_x
            std wd_x
            jsr Abs_D
            std wd_w            ; |dx| (word, spans wd_w and wd_h)
            ldd wp1_sy
            subd wp1_y
            std wd_y
            jsr Abs_D
            std wq_fy           ; |dy|
            cmpd wd_w
            bls .dxbig
            ; |dy| is the larger.
            ldd wd_w
            lsra
            rorb
            std wq_fx
            lsra
            rorb
            addd wq_fx          ; 3/4 min
            lsra
            rorb                ; 3/8 min
            addd wq_fy
            bra .dist
.dxbig      ldd wq_fy
            lsra
            rorb
            std wq_fx
            lsra
            rorb
            addd wq_fx
            lsra
            rorb
            addd wd_w
.dist       std wq_cx
            beq .arrived
            ; dx * 128 / dist, then * 205 / 64: 48 px/s along the unit vector.
            ldd wd_w
            jsr p1_unit
            tst wd_x
            bpl .xpos
            jsr wz_neg
.xpos       ldx #wp1_x
            jsr add_8_8
            ldd wq_fy
            jsr p1_unit
            tst wd_y
            bpl .ypos
            jsr wz_neg
.ypos       ldx #wp1_y
            jsr add_8_8
            ; dist < 3 (1/4 of a cell): the distance before this tick's step, as near as makes no difference.
            ldd wq_cx
            cmpd #3
            bhs .far
.arrived    lda #P1S_FIRE2
            jsr p1_switch
.far        jsr p1_aura_flicker
            lbra p1u_end

; D=|component|, wq_cx=dist. Returns the 8.8 step for that component.
p1_unit     aslb
            rola
            aslb
            rola
            aslb
            rola
            aslb
            rola
            aslb
            rola
            aslb
            rola
            aslb
            rola                ; * 128
            ldx wq_cx
            jsr wz_div
            cmpd #128
            bls .ok
            ldd #128
.ok         lda #P1_CENTER_SPEED
            mul
            jmp wz_shift6       ; 128 * 205 / 64 = 410 at full scale

p1u_fire1   jsr p1_toward_man
            lda #3
            jsr p1_sprite
            tst wp1_charged
            bne .charged
            ; t > P1_FIRE_RATE - P1_CHARGE_TIMING is always true: the rate is shorter than the timing.
            lda #1
            sta wp1_charged
            lda #SND_CHARGE
            jsr Sound_Play
            tst wp1_head
            bmi .cleft
            lda #4              ; (sizeX - 1) * heading
            bra .cgo
.cleft      lda #-5             ; sizeX * heading
.cgo        clrb
            jsr wz_charge
            bra .aura
.charged    ldd wp1_t
            cmpd #P1_FIRE_RATE
            ble .aura
            clr wp1_charged
            inc wp1_fire
            ldx #P1_FIRE_RATE
            jsr wz_mod
            std wq_tx
            ldd <now
            subd wq_tx
            std E_START,u
            jsr p1_fire1
            lda wp1_fire
            cmpa #P1_FIRE_COUNT
            blo .aura
            lda #P1S_JUMP2
            ldb wp1_chg
            cmpb #P1_CHARGE_COUNT
            blo .pause
            clr wp1_chg
            lda #P1S_BEGIN2
.pause      pshs a
            lda #P1S_PAUSE
            jsr p1_switch
            lda #P1_F1_PAUSE
            sta wp1_pause
            puls a
            sta wp1_cached
.aura       jsr p1_aura_stable
            lbra p1u_end

p1_fire1    ldb E_SIZEX,u
            clra
            jsr p1_h
            addd wp1_x
            std wq_fx
            ldd wp1_y
            std wq_fy
            ldx wq_fx
            ldy wq_fy
            ldb #2
            jsr wz_circle
            jsr wz_aim_man
            ldx wq_fx
            ldy wq_fy
            ldd #P1_LASER_SPEED
            jsr Laser3_New
            lda #SND_ALIEN_FIRE
            jmp Sound_Play

p1u_fire2   tst wp1_charged
            bne .check
            lda #1
            sta wp1_charged
            ; (heading - 1) / 2, -3
            lda wp1_head
            bpl .zero
            lda #-1
            bra .cgo
.zero       clra
.cgo        ldb #-3
            jsr wz_charge
.check      ldd wp1_t
            cmpd #P1_FIRE_RATE2
            ble .draw
            clr wp1_charged
            inc wp1_fire
            ldx #P1_FIRE_RATE2
            jsr wz_mod
            std wq_tx
            ldd <now
            subd wq_tx
            std E_START,u
            jsr p1_fire2
            lda wp1_fire
            cmpa #P1_FIRE_COUNT2
            blo .draw
            lda #P1S_JUMP2
            jsr p1_switch
            ldd #P1_J2X/2
            jsr p1_h
            std wp1_vx
            ldd #P1_J2Y/2
            jsr p1_h
            std wp1_vy
.draw       lda #COLOR_RED
            sta <draw_color
            ldx wp1_x
            leax -7,x
            ldy wp1_y
            leay -1,y
            ldd #63
            jsr Draw_ColoredSprite
            jsr p1_aura_stable
            lbra p1u_end

; Seeker_New(x, y - 3, Random * 96 - 48, -96).
p1_fire2    jsr Random
            pshs b
            lda #51
            mul
            sta wq_tmp
            puls a
            ldb #3
            mul                 ; 3 * R
            addb wq_tmp
            adca #0             ; R * 3.2: 0..815
            subd #410           ; -48..48 px/s
            std <arg0
            ldd #-819           ; -96 px/s
            std <arg1
            ldx wp1_x
            ldd wp1_y
            subd #3
            tfr d,y
            pshs u
            FAR Seeker_New
            tfr u,y
            puls u
            lda wp1_scount
            cmpa #P1_FIRE_COUNT2
            bhs .full
            ldb #4
            mul
            addd #wp1_seek
            tfr d,x
            jsr wz_store
            inc wp1_scount
.full       lda #SND_ALIEN_FIRE
            jmp Sound_Play

p1_aura_flicker
            ldd <now
            subd wp1_dist
            cmpd #P1_AURA_FLICKER_T
            ble p1_aura_out
            lda #WZ_DIST_STATIC
            bra p1_aura_go
p1_aura_stable
            ldd <now
            subd wp1_dist
            cmpd #P1_AURA_STABLE_T
            ble p1_aura_out
            lda #WZ_DIST_OFFSET
p1_aura_go  sta wq_try
            ldd <now
            std wp1_dist
            jsr Random
            lda E_SIZEX,u
            asla
            mul                 ; A = Random * 2 * sizeX / 256
            tfr a,b
            clra
            addd E_X,u
            std wq_fx
            ldb E_SIZEX,u
            clra
            std wq_tmp
            ldd wq_fx
            subd wq_tmp
            std wq_fx
            jsr Random
            lda E_SIZEY,u
            asla
            mul
            tfr a,b
            clra
            addd E_Y,u
            std wq_fy
            ldb E_SIZEY,u
            clra
            std wq_tmp
            ldd wq_fy
            subd wq_tmp
            tfr d,y
            ldd #WZ_DIST_OFFSET_1
            std <arg0
            ldx wq_fx
            lda wq_try
            ldb #WZ_DIST_SIZE_1
            jmp wz_distortion
p1_aura_out rts

; ---- collision: CollisionCheck and Main_GetDisplacement ------------------------------------------
; Integer positions: a position changed by a displacement loses its fraction.
p1_collide  ldb E_SIZEY,u
            clra
            std wq_tmp
            ldd wp1_y
            subd wq_tmp
            jsr Div12
            stb wq_cy+1
.row        ldb wq_cy+1
            clra
            jsr Times12
            std wq_ty           ; cy * 12
            ldb E_SIZEY,u
            clra
            addd wp1_y
            cmpd wq_ty
            ble .done           ; cy >= (y + sizeY) / 12
            ldb E_SIZEX,u
            clra
            std wq_tmp
            ldd wp1_x
            subd wq_tmp
            jsr Div12
            std wq_cx
.col        ldd wq_cx
            jsr Times12
            std wq_tx           ; cx * 12
            ldb E_SIZEX,u
            clra
            addd wp1_x
            cmpd wq_tx
            ble .nextrow        ; cx >= (x + sizeX) / 12
            ldx wq_cx
            ldb wq_cy+1
            jsr Main_GetCell
            tsta
            beq .nextcol
            jsr p1_collide_cell
.nextcol    ldx wq_cx
            leax 1,x
            stx wq_cx
            bra .col
.nextrow    inc wq_cy+1
            bra .row
.done       rts

; One cell, whose top-left is wq_tx, wq_ty. Sides are the C's: 0 right, 1 top, 2 left, 3 underside.
WZ_SIDE_RIGHT  equ 0
WZ_SIDE_TOP    equ 1
WZ_SIDE_LEFT   equ 2
WZ_SIDE_UNDER  equ 3
p1_collide_cell
            ; bL >= aR, bR <= aL, bT >= aU, bU <= aT: no overlap.
            ldb E_SIZEX,u
            clra
            addd wp1_x
            subd wq_tx          ; aR - bL
            lble .out
            std wd_x            ; left candidate
            ldb E_SIZEX,u
            clra
            std wq_tmp
            ldd wq_tx
            addd #12
            addd wq_tmp
            subd wp1_x          ; bR - aL
            lble .out
            std wd_y            ; right candidate
            ldb E_SIZEY,u
            clra
            addd wp1_y
            subd wq_ty          ; aU - bT
            std wd_top
            ; A charging boss feels the floor one pixel early.
            lda wp1_state
            cmpa #P1S_CHARGE
            bne .feet_ok
            ldd wd_top
            addd #1
            std wd_top
.feet_ok    ldd wd_top
            lble .out
            ldb E_SIZEY,u
            clra
            std wq_tmp
            ldd wq_ty
            addd #12
            addd wq_tmp
            subd wp1_y          ; bU - aT
            lble .out
            std wd_cur          ; underside candidate
            ldd #1000
            std wq_best
            lda #$FF
            sta wq_side
            ; Left of the cell.
            ldd wd_x
            std wq_d
            ldx wq_cx
            leax -1,x
            ldb wq_cy+1
            lda #WZ_SIDE_LEFT
            lbsr .try
            ; Right of the cell.
            ldd wd_y
            std wq_d
            ldx wq_cx
            leax 1,x
            ldb wq_cy+1
            lda #WZ_SIDE_RIGHT
            lbsr .try
            ; Above the cell.
            ldd wd_top
            std wq_d
            ldx wq_cx
            ldb wq_cy+1
            decb
            lda #WZ_SIDE_TOP
            lbsr .try
            ; Below the cell.
            ldd wd_cur
            std wq_d
            ldx wq_cx
            ldb wq_cy+1
            incb
            lda #WZ_SIDE_UNDER
            bsr .try
            ; With no open side the displacement is zero.
            lda wq_side
            cmpa #$FF
            beq .out
            cmpa #WZ_SIDE_LEFT
            bne .n1
            ldd wp1_x
            subd wq_best
            std wp1_x
            clr wp1_x+2
            rts
.n1         cmpa #WZ_SIDE_RIGHT
            bne .n2
            ldd wp1_x
            addd wq_best
            std wp1_x
            clr wp1_x+2
            rts
.n2         cmpa #WZ_SIDE_UNDER
            bne .top
            ldd wp1_y
            addd wq_best
            std wp1_y
            clr wp1_y+2
            rts
.top        ldd wp1_y
            subd wq_best
            std wp1_y
            clr wp1_y+2
            lda wp1_state
            cmpa #P1S_JUMP1
            beq .land
            cmpa #P1S_JUMP2
            bne .out
.land       ldd wp1_vy
            ble .out
            lda #1
            sta wp1_support
.out        rts
; wq_d=distance, X, B=the neighbor that must be open, A=side.
.try        sta wq_try
            ldy wq_d
            cmpy #12
            bge .tno
            cmpy wq_best
            bge .tno
            jsr Main_GetCell
            tsta
            beq .topen
            cmpa #LAVA
            beq .topen
            cmpa #FLOATY_PLATFORM
            bne .tno
            ; A cell outside the map reads as PLATFORM, so it is not open: as in side_open.
.topen      ldd wq_d
            std wq_best
            lda wq_try
            sta wq_side
.tno        rts

; ---- p1 handlers --------------------------------------------------------------------------------
P1_DeathEffect
            lda #SND_EXPLOSION
            jsr Sound_Play
            ldx wp1_x
            ldy wp1_y
            lda #6
            jsr wz_circle_red
            ldx wp1_x
            ldy wp1_y
            lda #WZ_DIST_FADE_BACKWARD
            jmp wz_fadein

; Wizard_p1_4.FadeOut. U=phase 1.
P1_FadeOut  clr wq_i
            lda wp1_scount
            sta wq_n
            ldx #wp1_seek
            stx wd_p
.scan       lda wq_i
            cmpa wq_n
            bhs .gone
            ldx wd_p
            jsr wz_die_h
            ldx wd_p
            leax 4,x
            stx wd_p
            inc wq_i
            bra .scan
.gone       ldd E_VT,u
            cmpd #P1_vt
            bne .stale          ; already freed: U is someone else now
            lda E_FLAGS,u
            anda #~EF_ACTIVE&$FF
            sta E_FLAGS,u
.stale      ldx wp1_x
            ldy wp1_y
            lda #6
            jsr wz_circle_red
            ldx wp1_x
            ldd wp1_y
            subd #6
            tfr d,y
            lda #WZ_DIST_FADE_BACKWARD
            jmp wz_fadein

P1_Die      ldd E_HEALTH,u
            bgt .nokill         ; killed by touching an invulnerable man: the C's controller stalls on this too
            lda #1
            sta wc_p1killed
.nokill     jsr Main_RecordKill
            ldx wp1_x
            ldd wp1_y
            subd #24
            tfr d,y
            ldb E_SCORE,u
            jsr Main_RecordScore
            jsr Entity_DeathEffect
            lda E_FLAGS,u
            anda #~EF_ACTIVE&$FF
            sta E_FLAGS,u
            rts

P1_Hurt     lda wp1_state
            cmpa #P1S_INTRO
            beq .shielded
            jmp Alien_Base_Hurt
.shielded   lda #SND_NO_DAMAGE
            jsr Sound_Play
            ldy <hurt_laser
            beq .out
            ldd L_VX,y
            std <arg0
            ldx L_X,y
            ldd L_Y,y
            tfr d,y
            WZ_KEEPU NoDamage_New
.out        rts

P1_HitEffect
            lda #SND_HIT
            jsr Sound_Play
            ldx <hit_x
            ldy <hit_y
            jsr wz_impact_green
            ldd #WZ_DIST_OFFSET_1
            std <arg0
            ldx <hit_x
            ldy <hit_y
            lda #WZ_DIST_STATIC
            ldb #WZ_DIST_SIZE_2
            jsr wz_distortion
            ldx E_X,u
            ldy E_Y,u
            ldb #1
            jsr wz_explosion
            lda E_FLAGS,u
            ora #EF_FLASHING
            sta E_FLAGS,u
            ldb <now+1
            stb E_FLASHT,u
            rts

; ---- Wizard_p2_3.as -----------------------------------------------------------------------------
P2S_INTRO   equ 0
P2S_TRAVEL  equ 1
P2S_FIRE    equ 2
P2_SIZEX    equ 36
P2_SIZEY    equ 18
P2_INTRO_T  equ 90
P2_SPEED    equ 410             ; 48 px/s
P2_ANIM_T   equ 90              ; P2_SEGMENT_ANIMATION_PERIOD
P2_HALL_OPEN equ 144            ; 12 cells
P2_FIRE_DIST equ 432            ; 36 cells
P2_FIRE_REPEAT equ 768          ; 64 cells
P2_END_X    equ 780             ; 65 cells
P2_LEAD     equ 48
P2_FIRE_RATE equ 15
P2_BURST    equ 12
P2_LASER_SPEED equ 410          ; LASER4_SPEED_1, 48 px/s
P2_MAX_SEGS equ 12              ; drawn behind the mouth
P2_LAZY_REACH equ 160           ; hallway objects appear this far ahead of the camera or the man
P2_LAZY_PER_TICK equ 2

P2_vt       fdb P2_Update,P2_Hurt,0,0,P2_HitEffect

; X=cell x, B=cell y. Returns U=record or 0. The caller saves its own U.
; The AS reads sizeX before assigning it, so startX, and x2 with it, is NaN -> 0 wherever this phase is spawned. Every
; world column in this class is therefore absolute, and the arena was built around that.
P2_New      pshs b,x
            ldx #P2_vt
            lda #bank(P2_vt)
            ldb #KIND_ALIEN
            jsr Ent_Alloc
            bne .ok
            puls b,x,pc
.ok         ldx 1,s
            ldb ,s
            stb wp2_cy
            jsr Alien_Init
            lda E_FLAGS,u
            ora #EF_KEEP        ; each phase of the boss runs however far the view is
            sta E_FLAGS,u
            ldd #0
            std wp2_x
            clr wp2_x+2
            ldd E_Y,u
            addd #6
            std wp2_y
            lda #P2S_INTRO
            sta wp2_state
            clr wp2_fixed
            clr wp2_firec
            clr wp2_charged
            clr wp2_lo
            ldd <now
            std E_START,u
            std wp2_segt
            ; Health is 9234873 in the C. P2_Hurt never takes any, which is as good on this timescale.
            ldd #32767
            std E_HEALTH,u
            lda #P2_SIZEX
            sta E_SIZEX,u
            lda #P2_SIZEY
            sta E_SIZEY,u
            jsr Main_AddToKillCount
            puls b,x,pc

P2_Hurt     ldx <hurt_laser
            bne .hit
            rts
.hit        ldd L_X,x
            ldx L_Y,x
            jmp Entity_HitEffect

P2_HitEffect
            lda #SND_HIT_LOW
            jsr Sound_Play
            ldd E_X,u
            addd #P2_SIZEX
            tfr d,x
            ldy <hit_y
            lda #1
            ldb #1
            WZ_KEEPU SparkFountain_New
            ldx <hit_x
            ldy <hit_y
            jsr wz_impact_green
            ldd #WZ_DIST_OFFSET_2
            std <arg0
            ldx <hit_x
            ldy <hit_y
            lda #WZ_DIST_STATIC
            ldb #WZ_DIST_SIZE_2
            jsr wz_distortion
            lda E_FLAGS,u
            ora #EF_FLASHING
            sta E_FLAGS,u
            ldb <now+1
            stb E_FLASHT,u
            rts

; Wizard_p2_3.FadeOut. U=phase 2.
P2_FadeOut  ldd E_VT,u
            cmpd #P2_vt
            bne .stale
            lda E_FLAGS,u
            anda #~EF_ACTIVE&$FF
            sta E_FLAGS,u
.stale      jsr wz_rect_a       ; CloseHallwayRight: startX / 12 + 24, startY / 12 - 1
            fcb PLATFORM,24,5,1,3
            clr wp2_open
            ldd wp2_x
            std wq_fx
            lda #6
            sta wq_i
.circles    ldx wq_fx
            ldy wp2_y
            lda #6
            jsr wz_circle_red
            ldd wq_fx
            subd #6
            std wq_fx
            dec wq_i
            bne .circles
            rts

; SetupHallway. The C builds all 25 objects here, which is most of a 32-slot pool. The mines are only marked as wanted,
; and p2_hall_build makes them as the view comes up to them. A slot whose object still lives stays as it is. The
; barrier's blocks are blocks in the level's grid that it began without: each that is gone comes back, as the C makes
; again each that is not alive.
p2_setup_hallway
            clr wp2_barcol
            lda #P2_BAR_W*3
            sta wq_i
.block      lda wq_i
            deca
            clrb
.div3       cmpa #3
            blo .cell
            suba #3
            incb
            bra .div3
.cell       pshs a
            addb #P2_BAR_X
            clra
            tfr d,x
            puls b
            addb wp2_cy
            decb
            lda #PLATFORM_DESTRUCTIBLE ; the grid's own: the block is there again
            jsr Main_SetCellType
            dec wq_i
            bne .block
            clr tl_valid        ; the terrain lists are made again with them
            clr vl_valid
            clr wp2_lo
            ldx #wp2_hall
            stx wd_p
            lda #P2_SLOTS
            sta wq_i
.next       ldx wd_p
            jsr wz_alive
            bne .alive
            ldx wd_p
            lda #1
            sta 4,x
.alive      ldx wd_p
            leax P2_SLOT_SIZE,x
            stx wd_p
            dec wq_i
            bne .next
            rts

; A=slot. Returns X=cell x, B=cell y.
p2_slot_cell
            ; Mine_New(26 + 2 * i, 1 + startY / 12)
            ldb #2
            mul
            addd #26
            tfr d,x
            ldb wp2_cy
            incb
            rts

; Creates a few of the hallway objects that have come into reach.
p2_hall_build
            lda #P2_LAZY_PER_TICK
            sta wq_n
            ; Reach: the further on of the camera and the man.
            ldd <cam_x
            cmpd <man_x
            bge .ref
            ldd <man_x
.ref        addd #P2_LAZY_REACH
            std wq_tx
            lda wp2_lo          ; nothing below it is pending
            sta wq_i
            ldb #P2_SLOT_SIZE
            mul
            addd #wp2_hall
            std wd_p
.next       ldx wd_p
            tst 4,x
            beq .step
            lda wq_i
            jsr p2_slot_cell
            stx wq_cx
            stb wq_cy
            ldd wq_cx
            jsr Times12
            cmpd wq_tx
            bgt .out             ; slots run left to right
            std wq_ty
            ; The worm has already gone past it: the C would have destroyed it there.
            ldd wp2_x
            addd #P2_SIZEX+2
            cmpd wq_ty
            bgt .drop
            pshs u
            ldx wq_cx
            ldb wq_cy
            clra
            FAR Mine_New
            tfr u,y
            puls u
            cmpy #0
            beq .out            ; pool full: try again next tick
            ldx wd_p
            jsr wz_store
            dec wq_n
.drop       ldx wd_p
            clr 4,x
            lda wq_n
            beq .out
.step       ldx wd_p
            leax P2_SLOT_SIZE,x
            stx wd_p
            inc wq_i
            lda wq_i
            cmpa #P2_SLOTS
            blo .next
.out        rts

; A=slot. Returns X = the slot, D = x of its cell.
p2_slot_x   pshs a
            ldb #P2_SLOT_SIZE
            mul
            addd #wp2_hall
            pshs d
            lda 2,s
            jsr p2_slot_cell
            tfr x,d
            jsr Times12
            puls x
            leas 1,s
            rts

; Mines and barriers that the worm's mouth has reached. Slots run left to right and an object is at its cell's x + 6, so
; the first slot whose cell starts at or past the mouth's reach ends the search: the C looks at all 25 to the same effect.
p2_hall_burn
            ldd E_X,u
            cmpd #12
            blo .out            ; cellX == currentCellX: int(x / 12) is 0 at the start, and it is never updated
            ldd wp2_x
            addd #P2_SIZEX+2
            std wq_tx
            ; Step over slots that are done. p2_hall_build never makes an object for a slot behind this reach.
.skip       lda wp2_lo
            cmpa #P2_SLOTS
            bhs .out
            bsr p2_slot_x
            cmpd wq_tx
            bge .scan
            tst 4,x
            bne .scan
            jsr wz_alive
            bne .scan
            inc wp2_lo
            bra .skip
.scan       lda wp2_lo
            sta wq_i
.next       lda wq_i
            cmpa #P2_SLOTS
            bhs .out
            bsr p2_slot_x
            cmpd wq_tx
            bge .out
            jsr wz_alive
            beq .step
            ldd wp2_x
            addd #P2_SIZEX+2
            cmpd E_X,y
            ble .step
            pshs u
            tfr y,u
            FAR Mine_Explode
            puls u
.step       inc wq_i
            bra .next
.out        rts

; The barrier's blocks that the mouth has reached die: barrier[k].GetX() < x2 + sizeX, looked at whenever int(x / 12) is
; not 0, as for the mines. A block is at its cell's x + 6. They are blocks in the level's grid (boss_terrain.ABSENT).
p2_bar_burn ldd E_X,u
            cmpd #12
            blo .out
.col        lda wp2_barcol
            cmpa #P2_BAR_W
            bhs .out
            ldb #12
            mul
            addd #P2_BAR_X*12+6
            std wq_ty
            ldd wp2_x
            addd #P2_SIZEX
            cmpd wq_ty
            ble .out
            lda #3
            sta wq_n
.row        ldb wp2_barcol
            addb #P2_BAR_X
            clra
            tfr d,x
            ldb wp2_cy
            addb wq_n
            subb #2             ; startY / 12 - 1 to + 1
            bsr p2_bar_kill
            dec wq_n
            bne .row
            inc wp2_barcol
            bra .col
.out        rts

; X=cell x, B=cell y of a barrier block: if it is there, it dies as a shot one does. Keeps U.
p2_bar_kill stx wq_cx
            stb wq_cy
            jsr Main_GetCell
            cmpa #PLATFORM_DESTRUCTIBLE
            bne .out
            ldd wq_cx
            std <block_x
            lda wq_cy
            sta <block_y
            lda #PLATFORM_DESTRUCTIBLE
            sta <block_buried
            jsr block_make      ; its entity, the one a shot made or a new one
            tsta
            beq .raw
            tfr x,y
            jmp wz_die_y
            ; No room for one: the block goes without its effects.
.raw        clra
            ldx wq_cx
            ldb wq_cy
            jsr Main_SetCellType
            ldx wq_cx
            ldb wq_cy
            jmp Terrain_Hole
.out        rts

; A=state.
p2_switch   sta wp2_state
            ldx <now
            stx E_START,u
            cmpa #P2S_TRAVEL
            bne .n1
            bra p2_camera
.n1         cmpa #P2S_FIRE
            bne .out
            clr wp2_firec
            clr wp2_charged
.out        rts

; Draw_SetCameraTarget(x2 + sizeX + lead, y2).
p2_camera   ldd wp2_x
            addd #P2_SIZEX+P2_LEAD
            std <cam_fixed_x
            ldd wp2_y
            std <cam_fixed_y
            rts

P2_Update   lda E_FLAGS,u
            bita #EF_ACTIVE
            bne .live
            rts
.live       lda wp2_state
            cmpa #P2S_INTRO
            bne .n0
            jsr Alien_ContactKillCheck
            jsr wz_t
            cmpd #P2_INTRO_T
            ble .end
            lda #P2S_TRAVEL
            jsr p2_switch
            jsr p2_setup_hallway
            ldd #0
            std wp2_tstart
            ldd #P2_FIRE_DIST
            std wp2_tdist
            bra .end
.n0         cmpa #P2S_TRAVEL
            bne .n1
            jsr p2_travel
            bra .end
.n1         jsr p2_firing
.end        ldd wp2_x
            std E_X,u
            ldd wp2_y
            std E_Y,u
            lda E_FLAGS,u
            bita #EF_ACTIVE
            beq .out
            lda wp2_state
            cmpa #P2S_INTRO
            beq .draw
            jsr p2_hall_build
.draw       FAR p2_draw         ; in bank 9, with the rest of the drawing: see wizard_p2draw.asm
.out        rts

p2_travel   ldd #P2_SPEED
            ldx #wp2_x
            jsr add_8_8
            jsr Alien_ContactKillCheck
            lda E_FLAGS,u
            bita #EF_ACTIVE
            beq .noopen
            tst wp2_open
            bne .noopen
            ldd wp2_tstart
            addd #P2_HALL_OPEN
            cmpd wp2_x
            bhi .noopen
            lda #1
            sta wp2_open
            jsr wz_rect_a       ; OpenHallwayRight: startX / 12 + 22, startY / 12 - 1
            fcb EMPTY,22,5,4,3
.noopen     ldd wp2_tstart
            addd wp2_tdist
            cmpd wp2_x
            bhi .nofire
            lda #P2S_FIRE
            jsr p2_switch
.nofire     ldd wp2_x
            cmpd #P2_END_X
            blo .inhall
            ldd #P2_END_X
            std wp2_x
            clr wp2_x+2
            lda E_FLAGS,u
            anda #~EF_ACTIVE&$FF
            sta E_FLAGS,u
.inhall     jsr p2_hall_burn
            jsr p2_bar_burn
            ; Camera: once the mouth has come within the lead, the view is tied to it. The engine's ease of 2 px a tick
            ; outruns the worm's 1.6, so holding the target there does what the C's Draw_SetCamera did, without moving
            ; the view in the middle of a tick's drawing.
            tst wp2_fixed
            bne .tied
            ldd <cam_x
            subd wp2_x
            subd #P2_SIZEX
            cmpd #P2_LEAD
            bgt .out
            lda #1
            sta wp2_fixed
.tied       jmp p2_camera
.out        rts

p2_firing   tst wp2_charged
            bne .charged
            ; t > P2_FIRE_1_RATE - P2_CHARGE_TIMING is always true.
            lda #1
            sta wp2_charged
            lda wp2_firec
.mod3       cmpa #3
            blo .h
            suba #3
            bra .mod3
.h          sta wp2_fireh
            lda #SND_CHARGE
            jsr Sound_Play
            jsr p2_muzzle_dy
            lda #P2_SIZEX
            jmp wz_charge
.charged    jsr wz_t
            cmpd #P2_FIRE_RATE
            ble .out
            ldd <now
            std E_START,u
            clr wp2_charged
            jsr p2_fire1
            inc wp2_firec
            lda wp2_firec
            cmpa #P2_BURST
            blo .out
            lda #P2S_TRAVEL
            jsr p2_switch
            ldd wp2_x
            std wp2_tstart
            ldd #P2_FIRE_REPEAT
            std wp2_tdist
.out        rts

; B = -12 + 12 * fireHeight.
p2_muzzle_dy
            lda wp2_fireh
            ldb #12
            mul
            subb #12
            rts

p2_fire1    lda #SND_ALIEN_FIRE
            jsr Sound_Play
            jsr p2_muzzle_dy
            sex
            addd wp2_y
            std wq_fy
            ldd wp2_x
            addd #P2_SIZEX
            std wq_fx
            ldx wq_fx
            ldy wq_fy
            ldb #4
            jsr wz_circle
            ldd wq_fx
            addd #72            ; 6 cells
            std <arg0
            ldd wq_fy
            std <arg1
            ldx wq_fx
            ldy wq_fy
            ldd #P2_LASER_SPEED
            jmp Laser4_New

; ---- Wizard_p3_3.as -----------------------------------------------------------------------------
P3P_MINIONS equ 1
P3P_LASER   equ 2
P3P_BEAM    equ 3
P3P_HIGHLOW equ 4
P3P_DYING   equ 5
P3S_INTRO1  equ 0
P3S_NOSETUP equ 1
P3S_SUMMON  equ 2
P3S_INTRO2  equ 3
P3S_FIRE1   equ 4
P3S_INTRO3  equ 5
P3S_FIRE2   equ 6
P3S_INTRO4  equ 7
P3S_FIRE3   equ 8
P3S_INTRO5  equ 9
P3S_FIRE4   equ 10
P3S_PAUSE   equ 11

P3_INTRO_T  equ 15
P3_INTRO1_T equ 120
P3_MINIONS  equ 8
P3_FIRE1_RATE equ 30
P3_CHARGE_T equ 15
P3_TURRETS  equ 6
P3_FIRE2_RATE equ 17            ; 583 ms
P3_FIRE2_BURST equ 6
P3_FIRE3_RATE equ 58            ; 1937 ms
P3_BEAM_CHARGE_T equ 23         ; 750 ms, rounded
P3_FIRE3_SEEKERS equ 8
P3_INTRO4_T equ 60
P3_FIRE4_RATE equ 23            ; 750 ms, rounded
P3_FIRE4_BURST equ 8
P3_FIRE4_SPACING equ 14
P3_JAW_T    equ 30
P3_DEATH_T  equ 120
P3_DYING_WHITE_T equ 15
P3_PAUSE_T  equ 15
P3_HEALTH   equ 4352
P3_SIZE     equ 23
P3_HL_PERIOD equ 45             ; P3_FIRE_4_RATE * 2
P3_TENT_DOTS equ 14
P3_TENT_PER_TICK equ 7
P3_TURRET_LASER_SPEED equ 256   ; LASER4_SPEED_2, 30 px/s
P3_RED_ALT  equ 9               ; a second palette index showing the same red

P3_vt       fdb P3_Update,P3_Hurt,P3_Die,P3_DeathEffect,P3_HitEffect

; X=cell x, B=cell y. Returns U=record or 0. The caller saves its own U.
P3_New      pshs b,x
            ldx #P3_vt
            lda #bank(P3_vt)
            ldb #KIND_ALIEN
            jsr Ent_Alloc
            bne .ok
            puls b,x,pc
.ok         ldx 1,s
            ldb ,s
            stx wp3_cx
            stb wp3_cy
            jsr Alien_Init
            lda E_FLAGS,u
            ora #EF_KEEP        ; each phase of the boss runs however far the view is
            sta E_FLAGS,u
            ldd #281
            std E_SPRITE,u
            ldd E_X,u
            addd #6
            std wp3_x
            std E_X,u
            ; startY = (y - 0.5) * 12 + 6 = y * 12. y2 = startY + 48.
            ldd E_Y,u
            std wp3_starty
            addd #48
            std wp3_y
            std E_Y,u
            clr wp3_y+2
            ldd wp3_y+1
            std wp3_prevy
            ldd #0
            std wp3_tvel
            std wp3_rel
            clr wp3_charged
            clr wp3_mcount
            clr wp3_lcount
            clr wp3_cur
            clr wp3_bcount
            clr wp3_fire
            clr wp3_tcur
            clr wp3_heal
            clr wk_ok
            ldd #0
            std wp3_sturret
            std wp3_seeker
            ldd #P3_HEALTH
            std E_HEALTH,u
            lda #60
            sta E_SCORE,u
            lda #P3_SIZE
            sta E_SIZEX,u
            sta E_SIZEY,u
            lda #COLOR_RED
            sta wp3_red
            lda hw_palette+COLOR_RED
            sta PALETTE+P3_RED_ALT
            ldd <now
            std E_START,u
            ; SwitchPhase(MINIONS), then SwitchState(INTRO_1).
            lda #P3P_MINIONS
            sta wp3_phase
            lda #P3S_NOSETUP
            jsr p3_switch_state
            lda #P3S_INTRO1
            jsr p3_switch_state
            puls b,x,pc

; A=state.
p3_switch_state
            sta wp3_state
            ldx <now
            stx E_START,u
            cmpa #P3S_INTRO1
            bne .n1
            jsr wz_rect_3       ; SetupPlatforms1
            fcb PLATFORM,-12,-1,1,3
            rts
.n1         cmpa #P3S_NOSETUP
            bne .n2
            stx wp3_t3
            rts
.n2         cmpa #P3S_SUMMON
            bne .n3
            jsr wz_rect_3
            fcb PLATFORM,-10,-3,7,1
            jsr wz_rect_3
            fcb PLATFORM,-10,3,7,1
            jmp p3_compact_minions
.n3         cmpa #P3S_FIRE1
            bne .n4
            clr wp3_fire
            rts
.n4         cmpa #P3S_FIRE2
            bne .n5
            clr wp3_fire
            rts
.n5         cmpa #P3S_FIRE3
            bne .n6
            jmp p3_setup_fire3
.n6         cmpa #P3S_INTRO5
            bne .n7
            ldd wp3_x
            subd #P3_SIZE
            tfr d,x
            ldy wp3_y
            lda #P3_INTRO4_T    ; duration in ticks
            WZ_KEEPU ChargeHeavy_New
            lda #SND_CHARGE_HEAVY
            jsr Sound_Play
            ldx E_START,u
            stx wp3_t3
            rts
.n7         cmpa #P3S_FIRE4
            bne .n8
            jsr wz_rect_3
            fcb PLATFORM,-10,-3,7,1
            jsr wz_rect_3
            fcb PLATFORM,-10,3,7,1
            ldx E_START,u
            stx wp3_t2
            clr wp3_fire
            rts
.n8         cmpa #P3S_PAUSE
            bne .out
            lda #P3_PAUSE_T
            sta wp3_pause
            lda #P3P_LASER
            sta wp3_cached
.out        rts

; A=phase.
p3_switch_phase
            sta wp3_phase
            cmpa #P3P_MINIONS
            bne .n1
            lda #P3S_NOSETUP
            jmp p3_switch_state
.n1         cmpa #P3P_LASER
            bne .n2
            lda #P3S_INTRO3
            jsr p3_switch_state
            clr wp3_cur
            jsr wz_rect_3
            fcb PLATFORM,-10,-3,7,1
            jsr wz_rect_3
            fcb EMPTY,-10,3,7,1
            jsr wz_rect_3
            fcb PLATFORM,-10,4,7,1
            jmp p3_make_laser_turrets
.n2         cmpa #P3P_BEAM
            bne .n3
            lda #P3S_INTRO4
            jsr p3_switch_state
            jmp p3_kill_laser_turrets
.n3         cmpa #P3P_HIGHLOW
            bne .n4
            lda #P3S_INTRO5
            jsr p3_switch_state
            jsr p3_kill_seeker_turret
            jsr p3_kill_beam_turrets
            clr wp3_fireh
            rts
.n4         cmpa #P3P_DYING
            bne .out
            ; Not in the original: dying during a PAUSE left the state at PAUSE, so the pause's end switched to the
            ; cached phase and the boss, at size 0, could never die. Any other state lets DyingUpdate run.
            lda wp3_state
            cmpa #P3S_PAUSE
            bne .dy
            clr wp3_state
.dy         ldx wp3_x
            ldy wp3_y
            WZ_KEEPU WizardDeathEffect_New
            lda #SND_EXPLOSION
            jsr Sound_Play
            ldd <now
            std E_START,u
            clr E_SIZEX,u
            clr E_SIZEY,u
            lda E_FLAGS,u
            ora #EF_FLASHING
            sta E_FLAGS,u
            clr wp3_charged
.out        rts

; Removes dead minions, then works out how many to make.
p3_compact_minions
            ldx #wp3_minion
            ldy #wp3_minion
            lda wp3_mcount
            sta wq_n
            clr wp3_mcount
.scan       tst wq_n
            beq .counted
            stx wq_cx
            sty wq_tx
            jsr wz_alive
            beq .skip
            ldx wq_cx
            ldy wq_tx
            ldd WZH_PTR,x
            std WZH_PTR,y
            ldd WZH_VT,x
            std WZH_VT,y
            leay 4,y
            sty wq_tx
            inc wp3_mcount
.skip       ldx wq_cx
            ldy wq_tx
            leax 4,x
            dec wq_n
            bra .scan
.counted    lda #P3_MINIONS
            suba wp3_mcount
            sta wp3_create
            rts

p3_make_laser_turrets
            clr wq_i
            ldx #wp3_laser
            stx wd_p
.next       lda wq_i
            lsra
            ldb #2
            mul
            std wq_tmp          ; (i / 2) * 2
            ldd wp3_cx
            subd #5
            subd wq_tmp
            tfr d,x             ; column = c - 5 + (i / 2) * -2
            ldb wp3_cy
            lda wq_i
            bita #1
            bne .low
            subb #2
            bra .make
.low        addb #3
.make       pshs u
            jsr WizardLaserTurret_New
            tfr u,y
            puls u
            cmpy #0
            beq .step
            ldb wp3_lcount
            cmpb #P3_TURRETS
            bhs .step
            ldx wd_p
            sty ,x
            ldd E_X,y
            std 2,x
            ldd E_Y,y
            std 4,x
            lda WLT_HEAD,y
            sta 6,x
            leax WLT_ENTRY,x
            stx wd_p
            inc wp3_lcount
.step       inc wq_i
            lda wq_i
            cmpa #P3_TURRETS
            blo .next
            rts

; Y = laser turret table entry's record, Z set unless it is still that turret.
p3_laser_alive
            ldy ,x
            beq .out
            ldd E_VT,y
            cmpd #WLT_vt
            bne .dead
            lda E_FLAGS,y
            bita #EF_ACTIVE
            rts
.dead       orcc #$04
.out        rts

p3_kill_laser_turrets
            lda wp3_lcount
            sta wq_n
            ldx #wp3_laser
            stx wd_p
.next       tst wq_n
            beq .done
            ldx wd_p
            bsr p3_laser_alive
            beq .step
            jsr wz_die_y
.step       ldx wd_p
            leax WLT_ENTRY,x
            stx wd_p
            dec wq_n
            bra .next
.done       clr wp3_lcount
            rts

p3_beam_alive
            ldy ,x
            beq .out
            ldd E_VT,y
            cmpd #WBT_vt
            bne .dead
            lda E_FLAGS,y
            bita #EF_ACTIVE
            rts
.dead       orcc #$04
.out        rts

p3_kill_beam_turrets
            lda wp3_bcount
            sta wq_n
            ldx #wp3_beam
            stx wd_p
.next       tst wq_n
            beq .done
            ldx wd_p
            bsr p3_beam_alive
            beq .step
            jsr wz_die_y
.step       ldx wd_p
            leax WBT_ENTRY,x
            stx wd_p
            dec wq_n
            bra .next
.done       clr wp3_bcount
            rts

p3_seeker_turret_alive
            ldy wp3_sturret
            beq .out
            ldd E_VT,y
            cmpd #WST_vt
            bne .dead
            lda E_FLAGS,y
            bita #EF_ACTIVE
            rts
.dead       orcc #$04
.out        rts

p3_kill_seeker_turret
            bsr p3_seeker_turret_alive
            beq .none
            jsr wz_die_y
.none       ldd #0
            std wp3_sturret
            rts

; The FIRE_3 half of SwitchState.
p3_setup_fire3
            clr wp3_fire
            lda #1
            sta wp3_cur
            jsr wz_rect_3
            fcb PLATFORM,-10,3,7,1
            clr wq_i
            ldx #wp3_beam
            stx wd_p
.next       lda wq_i
            asla                ; spacing * i
            suba #9
            sta wq_try          ; dx = -9 + 2 * i
            ; EMPTY (c - 9 + 2i, y - 3, 1, 1) and (c - 9 + 2i, y + 3, 1, 1): openings for the beam.
            ldb wq_try
            sex
            addd wp3_cx
            std wq_cx
            ldd #1
            std <arg0
            std <arg1
            lda #EMPTY
            ldx wq_cx
            ldb wp3_cy
            subb #3
            jsr Main_SetCellRectangle
            ldd #1
            std <arg0
            std <arg1
            lda #EMPTY
            ldx wq_cx
            ldb wp3_cy
            addb #3
            jsr Main_SetCellRectangle
            ldx wq_cx
            ldb wp3_cy
            subb #3
            lda #WZ_BEAM_VERTICAL
            pshs u
            jsr WizardBeamTurret_New
            tfr u,y
            puls u
            cmpy #0
            beq .step
            ldb wp3_bcount
            cmpb #3
            bhs .step
            ldx wd_p
            sty ,x
            ldd E_X,y
            std 2,x
            ldd E_Y,y
            std 4,x
            ldd WBT_END2Y,y
            std 6,x
            leax WBT_ENTRY,x
            stx wd_p
            inc wp3_bcount
.step       inc wq_i
            lda wq_i
            cmpa #3
            blo .next
            ldd wp3_cx
            subd #11
            tfr d,x
            ldb wp3_cy
            pshs u
            jsr WizardSeekerTurret_New
            stu wp3_sturret
            puls u
            rts

P3_Update   lda E_FLAGS,u
            bita #EF_ACTIVE
            bne .live
            rts
.live       lda wp3_state
            cmpa #P3S_PAUSE
            bne .run
            jsr wz_t
            cmpb wp3_pause
            bls .draw
            lda wp3_cached
            jsr p3_switch_phase
            bra .draw
.run        lda wp3_phase
            cmpa #P3P_MINIONS
            bne .n1
            jsr p3_minions_update
            bra .draw
.n1         cmpa #P3P_LASER
            bne .n2
            jsr p3_laser_update
            bra .draw
.n2         cmpa #P3P_BEAM
            bne .n3
            jsr p3_beam_update
            bra .draw
.n3         cmpa #P3P_HIGHLOW
            bne .n4
            jsr p3_highlow_update
            bra .draw
.n4         jsr p3_dying_update
.draw       lda E_FLAGS,u
            bita #EF_ACTIVE
            beq .out
            FAR p3_draw_self    ; in bank 9: wizard_p3draw.asm
.out        ldd wp3_x
            std E_X,u
            ldd wp3_y
            std E_Y,u
            rts

; y2 compared with startY. Returns with CC from the integer parts, unless they match and there is a fraction: then "above".
p3_y_gt_start
            ldd wp3_y
            cmpd wp3_starty
            bhi .yes
            blo .no
            tst wp3_y+2
            bne .yes
.no         clra                ; Z set
            rts
.yes        lda #1              ; Z clear
            rts

; if (y2 > startY) y2 -= 2 * 0.5 * (1 - t / 120) per tick.
p3_rise     jsr p3_y_gt_start
            beq .out
            jsr wz_t
            cmpd #120
            bhs .out
            ; 256 - t * 256 / 120, with 256 / 120 about 2.125.
            std wq_tmp
            aslb
            rola
            std wq_d
            ldd wq_tmp
            lsra
            rorb
            lsra
            rorb
            lsra
            rorb
            addd wq_d
            subd #256
            ldx #wp3_y
            jmp add_8_8
.out        rts

p3_minions_update
            jsr Alien_ContactKillCheck
            lda wp3_state
            cmpa #P3S_INTRO1
            bne .n1
            bsr p3_rise
            jsr wz_t
            cmpd #P3_INTRO1_T
            lble .out
            lda #P3S_SUMMON
            jmp p3_switch_state
.n1         cmpa #P3S_NOSETUP
            bne .n2
            ; The C's two steps of 0.1 * k and 0.1 * (1 - k) a frame come to 0.2 px a tick.
            jsr p3_y_gt_start
            beq .low
            ldd #-51
            bra .step
.low        ldd wp3_y
            cmpd wp3_starty
            bhs .timed
            ldd #51
.step       ldx #wp3_y
            jsr add_8_8
.timed      jsr wz_t
            cmpd #P3_JAW_T
            ble .out
            lda #P3S_SUMMON
            jmp p3_switch_state
.n2         cmpa #P3S_SUMMON
            bne .out
            tst wp3_charged
            bne .charged
            jsr wz_t
            cmpd #P3_FIRE1_RATE-P3_CHARGE_T
            ble .out
            lda #1
            sta wp3_charged
            lda #SND_CHARGE
            jmp Sound_Play
            ; No Charge_New: the C passes world coordinates as offsets, which puts it far off screen.
.charged    jsr wz_t
            cmpd #P3_FIRE1_RATE
            ble .out
            ; The AS leaves charged set here, unlike every other firing state.
            ldd <now
            std E_START,u
            lda wp3_create
            beq .count
            jsr p3_summon_one
            dec wp3_create
.count      lda wp3_mcount
            sta wq_n
            ldx #wp3_minion
            stx wd_p
.alive      lda wq_n
            beq .none
            ldx wd_p
            jsr wz_alive
            bne .out            ; somebody is alive
            ldx wd_p
            leax 4,x
            stx wd_p
            dec wq_n
            bra .alive
.none       lda #P3S_PAUSE
            jsr p3_switch_state
            lda #P3P_LASER
            sta wp3_cached
.out        rts

p3_summon_one
            lda #SND_ALIEN_FIRE
            jsr Sound_Play
            ldd wp3_x
            subd #P3_SIZE
            std wq_fx
            ldx wq_fx
            ldy wp3_y
            ldb #4
            jsr wz_circle
            ldd #-307           ; -3 * 12 px/s
            std <arg0
            ; (-4 + Random * 5) * 12 px/s: -410 + 512 * Random, in 8.8.
            jsr Random
            clra
            aslb
            rola
            subd #410
            std <arg1
            ldx wq_fx
            ldy wp3_y
            pshs u
            FAR Seeker_New
            tfr u,y
            puls u
            lda wp3_mcount
            cmpa #P3_MINIONS
            bhs .full
            ldb #4
            mul
            addd #wp3_minion
            tfr d,x
            jsr wz_store
            inc wp3_mcount
.full       rts

p3_laser_update
            jsr Alien_ContactKillCheck
            lda wp3_state
            cmpa #P3S_INTRO3
            bne .n1
            jsr wz_t
            cmpd #P3_INTRO_T
            ble .out
            lda #P3S_FIRE2
            jmp p3_switch_state
.n1         cmpa #P3S_FIRE2
            bne .out
            tst wp3_charged
            bne .charged
            jsr wz_t
            cmpd #P3_FIRE2_RATE-P3_CHARGE_T
            ble .out
            lda #1
            sta wp3_charged
            ; WizardLaserTurret.ChargeEffect: a dead turret still counts in the table, but there is nothing to attach to.
            lda wp3_cur
            cmpa wp3_lcount
            bhs .out
            ldb #WLT_ENTRY
            mul
            addd #wp3_laser
            tfr d,x
            jsr p3_laser_alive
            beq .out
            pshs u
            tfr y,u
            lda #1
            sta WLT_CHARGED,u
            clra
            clrb
            jsr wz_charge
            puls u,pc
.charged    jsr wz_t
            cmpd #P3_FIRE2_RATE
            ble .out
            ldd <now
            std E_START,u
            clr wp3_charged
            lda wp3_cur
            cmpa wp3_lcount
            bhs .nofire
            jsr p3_laser_fire
.nofire     inc wp3_cur
            lda wp3_cur
            cmpa #P3_TURRETS
            blo .wrap
            clr wp3_cur
.wrap       inc wp3_fire
            lda wp3_fire
            cmpa #P3_FIRE2_BURST
            blo .out
            lda #P3S_PAUSE
            jsr p3_switch_state
            lda #P3P_BEAM
            sta wp3_cached
.out        rts

; WizardLaserTurret.Fire on the current turret. The position comes from the table because the C fires a turret that has
; been shot, and its record may be gone by now.
p3_laser_fire
            lda wp3_cur
            ldb #WLT_ENTRY
            mul
            addd #wp3_laser
            tfr d,x
            stx wd_p
            jsr p3_laser_alive
            beq .nocharge
            clr WLT_CHARGED,y
.nocharge   lda #SND_ALIEN_FIRE
            jsr Sound_Play
            ldx wd_p
            ldy 4,x
            ldx 2,x
            ldb #4
            jsr wz_circle
            jsr wz_aim_man
            ldx wd_p
            ldb 6,x             ; y + heading * 3
            sex
            std wq_tmp
            aslb
            rola
            addd wq_tmp
            addd 4,x
            tfr d,y
            ldx 2,x
            ldd #P3_TURRET_LASER_SPEED
            jmp Laser4_New

p3_beam_update
            jsr Alien_ContactKillCheck
            lda wp3_state
            cmpa #P3S_INTRO4
            bne .n1
            jsr wz_t
            cmpd #P3_INTRO_T
            lble .out
            lda #P3S_FIRE3
            jmp p3_switch_state
.n1         cmpa #P3S_FIRE3
            lbne .out
            ; index = |currentTurret % 4 - 1|: 0, 1, 2, 1, 0, 1, ...
            lda wp3_cur
            anda #3
            suba #1
            bpl .ip
            nega
.ip         sta wq_i
            tst wp3_charged
            bne .charged
            jsr wz_t
            cmpd #P3_FIRE3_RATE-P3_BEAM_CHARGE_T
            lble .out
            lda #1
            sta wp3_charged
            lda wq_i
            cmpa wp3_bcount
            bhs .nob
            ldb #WBT_ENTRY
            mul
            addd #wp3_beam
            tfr d,x
            jsr p3_beam_alive
            beq .nob
            pshs u
            tfr y,u
            jsr WBT_ChargeEffect
            puls u
.nob        jsr p3_seeker_turret_alive
            lbeq .out
            pshs u
            tfr y,u
            jsr WST_ChargeEffect
            puls u,pc
.charged    jsr wz_t
            cmpd #P3_FIRE3_RATE
            ble .out
            ldd <now
            std E_START,u
            clr wp3_charged
            lda wq_i
            cmpa wp3_bcount
            bhs .nofire
            jsr p3_beam_fire
.nofire     inc wp3_cur
            ldx #wp3_seeker
            jsr wz_alive
            bne .flying
            ; Its own seeker.
            ldd wp3_x
            subd #P3_SIZE
            std wq_fx
            ldx wq_fx
            ldy wp3_y
            ldb #4
            jsr wz_circle
            ldd #0
            std <arg0
            std <arg1
            ldx wq_fx
            ldy wp3_y
            pshs u
            FAR Seeker_New
            tfr u,y
            puls u
            ldx #wp3_seeker
            jsr wz_store
            inc wp3_fire
.flying     jsr p3_seeker_turret_alive
            beq .count
            pshs u
            tfr y,u
            jsr WST_Fire
            puls u
            tsta
            beq .count
            inc wp3_fire
.count      lda wp3_fire
            cmpa #P3_FIRE3_SEEKERS
            blo .out
            lda #P3S_PAUSE
            jsr p3_switch_state
            lda #P3P_HIGHLOW
            sta wp3_cached
.out        rts

; WizardBeamTurret.Fire on turret wq_i: LaserBeam_New(orientation, x - 6, end1Y - 6, x + 6, end2Y + 6).
p3_beam_fire
            lda wq_i
            ldb #WBT_ENTRY
            mul
            addd #wp3_beam
            tfr d,x
            stx wd_p
            jsr p3_beam_alive
            beq .gone
            clr WBT_CHARGED,y
.gone       lda #SND_ALIEN_BEAM
            jsr Sound_Play
            ldx wd_p
            ldd 2,x
            addd #6
            std <arg0
            ldd 6,x
            addd #6
            std <arg1
            ldy 4,x
            leay -6,y
            ldd 2,x
            subd #6
            tfr d,x
            lda #WZ_BEAM_VERTICAL
            WZ_KEEPU LaserBeam_New
            rts

; SmoothShift of the triangle wave for P3_FIRE_4, one entry per tick, in 1/16 px above startY.
p3_hl_table fcb 192,191,188,183,176,168,158,148,136,124,112,99,86,74,62
            fcb 50,39,29,20,12,7,2,0,0,2,7,12,20,29,39
            fcb 50,62,74,86,99,112,124,136,148,158,168,176,183,188,191

p3_highlow_update
            lda wp3_state
            cmpa #P3S_INTRO5
            bne .n1
            ; if (y2 < startY + 12) y2 += 0.3 * k per tick, k = t / 60: about 1.25 t in 8.8.
            ldd wp3_starty
            addd #12
            cmpd wp3_y
            bls .nomove
            jsr wz_t
            cmpd #P3_INTRO4_T
            bhi .nomove
            std wq_tmp
            lsra
            rorb
            lsra
            rorb
            addd wq_tmp
            ldx #wp3_y
            jsr add_8_8
.nomove     jsr wz_t
            cmpd #P3_INTRO4_T
            lble .out
            lda #P3S_FIRE4
            jmp p3_switch_state
.n1         cmpa #P3S_FIRE4
            lbne .out
            ; y2 = startY + table[t2 mod period] / 16.
            ldd <now
            subd wp3_t2
            ldx #P3_HL_PERIOD
            jsr wz_mod
            ldx #p3_hl_table
            abx
            ldb ,x
            clra
            aslb
            rola
            aslb
            rola
            aslb
            rola
            aslb
            rola                ; D = pixels * 256
            pshs b
            tfr a,b
            clra
            addd wp3_starty
            std wp3_y
            puls b
            stb wp3_y+2
            jsr Alien_ContactKillCheck
            tst wp3_charged
            bne .charged
            jsr wz_t
            cmpd #P3_FIRE4_RATE-P3_CHARGE_T
            ble .out
            lda #1
            sta wp3_charged
            rts                 ; no Charge_New: its y offset is y2, so the C's effect is off screen
.charged    jsr wz_t
            cmpd #P3_FIRE4_RATE
            ble .out
            ldd <now
            std E_START,u
            clr wp3_charged
            lda #SND_ALIEN_FIRE_HEAVY
            jsr Sound_Play
            ; muzzle = (x2 - 18, startY - 7 + fireHeight * 14 + 6)
            lda wp3_fireh
            ldb #P3_FIRE4_SPACING
            mul
            addd wp3_starty
            subd #1
            std wq_fy
            ldd wp3_x
            subd #18
            std wq_fx
            ldx wq_fx
            ldy wq_fy
            ldb #12
            jsr wz_circlelarge
            ldd wp3_x
            subd #2*P3_SIZE
            std <arg0
            ldd wq_fy
            std <arg1
            ldx wq_fx
            ldy wq_fy
            WZ_KEEPU Laser5_New
            lda wp3_fireh
            eora #1
            sta wp3_fireh
            inc wp3_fire
            lda wp3_fire
            cmpa #P3_FIRE4_BURST
            blo .out
            lda #P3S_PAUSE
            jsr p3_switch_state
            lda #P3P_MINIONS
            sta wp3_cached
.out        rts

p3_dying_update
            jsr p3_rise
            jsr wz_t
            cmpd #P3_DEATH_T
            ble .out
            jsr Entity_Die
            ; Draw_ShadedRectangle over the whole screen, for one frame. As a display-list rectangle it would take two
            ; ticks of blitter time and erase the terrain with black, so the screen goes white by palette instead.
            ; The controller puts the colors back.
            ldx #PALETTE
            lda #$FF
            ldb #9
.white      sta ,x+
            decb
            bne .white
            lda #2
            sta wc_flash
.out        rts

wz_palette_restore
            ldx #hw_palette
            ldy #PALETTE
            ldb #16
.copy       lda ,x+
            sta ,y+
            decb
            bne .copy
            rts

P3_Hurt     ldd E_HEALTH,u
            subd <hurt_damage
            std E_HEALTH,u
            bgt .alive
            lda wp3_phase
            cmpa #P3P_DYING
            beq .out
            lda #P3P_DYING
            jmp p3_switch_phase
.alive      ldx <hurt_laser
            beq .here
            ldd L_X,x
            ldx L_Y,x
            jmp Entity_HitEffect
.here       ldd E_X,u
            ldx E_Y,u
            jmp Entity_HitEffect
.out        rts

P3_HitEffect
            lda #SND_HIT_LOW
            jsr Sound_Play
            ldb E_SIZEX,u
            clra
            std wq_tmp
            ldd E_X,u
            subd wq_tmp
            tfr d,x
            ldy <hit_y
            lda #1
            ldb #-1
            WZ_KEEPU SparkFountain_New
            ldx <hit_x
            ldy <hit_y
            jsr wz_impact_green
            ldd #WZ_DIST_OFFSET_1
            std <arg0
            ldx <hit_x
            ldy <hit_y
            lda #WZ_DIST_STATIC
            ldb #WZ_DIST_SIZE_2
            jsr wz_distortion
            lda E_FLAGS,u
            ora #EF_FLASHING
            sta E_FLAGS,u
            ldb <now+1
            stb E_FLASHT,u
            rts

P3_DeathEffect
            lda #SND_EXPLOSION
            jsr Sound_Play
            lda #SND_MACHINE_EXPLOSION
            jsr Sound_Play
            lda #3
            sta wq_i
.boom       jsr Random
            lda #6
            mul
            tfr a,b
            clra
            addd E_X,u
            subd #6
            std wq_fx
            jsr Random
            lda #6
            mul
            tfr a,b
            clra
            addd E_Y,u
            subd #6
            tfr d,y
            ldx wq_fx
            ldb #16
            jsr wz_explosion
            dec wq_i
            bne .boom
            ldd E_SPRITE,u
            std <arg0
            ldx E_X,u
            ldy E_Y,u
            WZ_KEEPU DeathFlash_New
            rts

; The way out: the wall ahead opens and a floating bridge crosses the pit. The man walks out to the GoalElevator, which
; ends the level. The kill itself does not, here or in the C.
P3_Die      jsr Alien_Base_Die
            jsr p3_kill_laser_turrets
            jsr p3_kill_beam_turrets
            jsr p3_kill_seeker_turret
            clr <cam_fixed
            jsr wz_rect_3
            fcb EMPTY,3,-1,1,3
            jsr wz_rect_3
            fcb FLOATY_PLATFORM,-2,2,5,1
            rts

wz_shift6   lsra
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
            rts

            assert *<=$4000,"wizard: bank 14 overflow"
wizard_end equ *
            endbank
