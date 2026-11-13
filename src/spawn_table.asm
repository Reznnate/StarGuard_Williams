; Level object symbols to constructors, from Loader.as. Indexed by symbol, 4 bytes each.
; A constructor is called with X=cell x, B=cell y, A=the parameter here, and returns U=its record (0 if none).
; Parameter encodings:
;   Trooper                 1 = moves, 0 = stationary
;   Piglet                  bit 7 = segment, low bits: 0 east, 1 north, 2 west, 3 south
;   BurstTurret             color (COLOR_GREEN allied, COLOR_RED alien)
;   BoltTurret              high nibble color, low nibble phase
;   BeamTurret              high nibble orientation (0 horizontal, 1 vertical), low nibble phase
;   TurretRemainsPlacer     color
;   RemainsPlacer           0: 48,48   1: 61,63   2: 48,47 (the two sprite ids)
;   TinierSpaceman          1 = right, $FF = left
;   ExplodingPlatform       1 = respawns
;   PlatformDestructible    1 = buried crystal
;   ZomboidAmbush, TrooperAmbush, HeavyTrooperAmbush    child count
;   MessageBanner           text color

SPAWN       macro ctor,param
            fdb \ctor
            fcb bank(\ctor)
            fcb \param
            endm
NOSPAWN     macro
            fdb 0,0
            endm

spawn_table
            NOSPAWN                             ; 0
            NOSPAWN                             ; 1 platform
            NOSPAWN                             ; 2 floaty platform
            NOSPAWN                             ; 3 lava: terrain, see Lava_Tick
            SPAWN Goal_New,0                    ; 4
            NOSPAWN                             ; 5 block: terrain until hit, see Block_Activate
            NOSPAWN                             ; 6 block with a crystal
            SPAWN Crystal_New,0                 ; 7
            SPAWN GoalElevator_New,0            ; 8
            NOSPAWN                             ; 9 lava 2
            SPAWN ExplodingPlatform_Spawn,0     ; 10
            SPAWN ExplodingPlatform_Spawn,1     ; 11
            SPAWN Flyer_New,0                   ; 12
            SPAWN Trooper_New,1                 ; 13
            SPAWN Zomboid_New,0                 ; 14
            NOSPAWN                             ; 15 hopper: no level places one
            SPAWN Hulk_New,0                    ; 16
            SPAWN TrooperHeavy_New,0            ; 17
            SPAWN ExplodingHopper_New,0         ; 18
            SPAWN Popper_New,0                  ; 19
            NOSPAWN                             ; 20 man
            NOSPAWN                             ; 21 man
            SPAWN TinierSpaceman_New,1          ; 22
            SPAWN TinierSpaceman_New,$FF        ; 23
            SPAWN Mine_New,0                    ; 24
            SPAWN DropMine_New,0                ; 25
            SPAWN BurstTurret_New,COLOR_GREEN   ; 26
            SPAWN BurstTurret_New,COLOR_RED     ; 27
            SPAWN BoltTurret_New,COLOR_GREEN*16+1 ; 28
            NOSPAWN                             ; 29
            SPAWN BeamTurret_New,$00            ; 30
            SPAWN BeamTurret_New,$10            ; 31
            SPAWN BeamTurret_New,$01            ; 32
            SPAWN BeamTurret_New,$11            ; 33
            SPAWN BeamTurret_New,$02            ; 34
            SPAWN BeamTurret_New,$12            ; 35
            SPAWN FlierAmbush_New,0             ; 36
            NOSPAWN                             ; 37 trooper ambush: no level places one
            SPAWN ZomboidAmbush_New,5           ; 38
            NOSPAWN                             ; 39 hopper ambush: no level places one
            SPAWN ZomboidAmbush_New,1           ; 40
            SPAWN HeavyTrooperAmbush_New,1      ; 41
            SPAWN ExplodingHopperAmbush_New,0   ; 42
            SPAWN RemainsPlacer_New,1           ; 43
            SPAWN RemainsPlacer_New,0           ; 44
            SPAWN RemainsPlacer_New,2           ; 45
            NOSPAWN                             ; 46 no level places one
            NOSPAWN                             ; 47 no level places one
            SPAWN Trigger_New,0                 ; 48
            SPAWN MessageTrigger_New,0          ; 49
            SPAWN RespawnPoint_New,0            ; 50
            SPAWN Piglet_New,$00                ; 51
            SPAWN Piglet_New,$01                ; 52
            SPAWN Piglet_New,$02                ; 53
            SPAWN Piglet_New,$03                ; 54
            NOSPAWN                             ; 55
            SPAWN GroupedTurretController_New,0 ; 56
            SPAWN BoltTurret_New,COLOR_RED*16+0 ; 57
            SPAWN BoltTurret_New,COLOR_RED*16+1 ; 58
            SPAWN BoltTurret_New,COLOR_RED*16+2 ; 59
            SPAWN Wizard_New,0                  ; 60
            SPAWN Trooper_New,0                 ; 61
            SPAWN MessageBanner_Spawn,COLOR_WHITE ; 62
            SPAWN Piglet_New,$80                ; 63
            SPAWN Piglet_New,$81                ; 64
            SPAWN Piglet_New,$82                ; 65
            SPAWN Piglet_New,$83                ; 66
            NOSPAWN                             ; 67
            NOSPAWN                             ; 68
            NOSPAWN                             ; 69
            NOSPAWN                             ; 70
            NOSPAWN                             ; 71
            SPAWN MessageBanner_Spawn,COLOR_RED ; 72
