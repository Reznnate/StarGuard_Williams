; Star Guard for the Williams Blaster board.
            include "hw.inc"
            include "gen/assets.inc"
            include "vars.inc"

DRAW_DEAD_ZONE equ 9

COLOR_RED   equ 1
COLOR_YELLOW equ 2
COLOR_GREEN equ 3
COLOR_CYAN  equ 4
COLOR_BLUE  equ 5
COLOR_MAGENTA equ 6
COLOR_WHITE equ 7

LASER_DEATH equ 0
LASER_HEAVY_DEATH equ 1
LAVA_DEATH  equ 2
LAVA2_DEATH equ 3
PHYSICAL_DEATH equ 4
EXPLOSION_ONLY equ 5

; Sound ids, in the C's order.
SND_LASER   equ 0
SND_EXPLOSION equ 1
SND_MACHINE_EXPLOSION equ 2
SND_PLATFORM_EXPLOSION equ 3
SND_QUIET_EXPLOSION equ 4
SND_MISS    equ 5
SND_QUIET_MISS equ 6
SND_HIT     equ 7
SND_HIT_LOW equ 8
SND_MACHINE_HIT equ 9
SND_PIGLET  equ 10
SND_NO_DAMAGE equ 11
SND_JUMP    equ 12
SND_LAND    equ 13
SND_ALIEN_FIRE equ 14
SND_ALIEN_FIRE_HEAVY equ 15
SND_CHARGE  equ 16
SND_CHARGE_HEAVY equ 17
SND_ALIEN_BEAM equ 18
SND_WARNING_BEEP equ 19
SND_MINE    equ 20
SND_MINE_DROP equ 21
SND_DEBRIS_IMPACT equ 22
SND_LAVA_IMPACT equ 23
SND_ZOMBOID equ 24
SND_CRYSTAL equ 25
SND_WIN     equ 26
SND_GUI_01  equ 27
SND_GUI_02  equ 28
SND_GUI_03  equ 29
SND_GUI_04  equ 30
SND_GUI_05  equ 31
SND_MAN_DEATH equ 32
SND_MAN_LAVA_DEATH equ 33
SND_COUNT   equ 34

; Notes the raster position, for tools/phases.lua. Costs 26 cycles.
PROF        macro n
            lda <vphase
            sta prof+\n*2
            lda VCOUNT
            sta prof+\n*2+1
            endm

; Calls a label in another ROM bank. Banked code uses this for anything outside its own bank and fixed ROM.
FAR         macro target
            jsr far_call
            fdb \target
            fcb bank(\target)
            endm

            org $D000
            include "engine.asm"
            include "man.asm"
            include "pools.asm"
            include "services.asm"
            include "game.asm"
UNDEF_STUB  rts
            assert *<=SPRFIX2_ORG,"fixed ROM code has met the sprites below the vectors"
            org SPRFIX2_ORG
            incbin "gen/sprfix2.bin"     ; worm images: the blitter reads fixed ROM whatever the bank

            org $FFF0
            fdb unused_vector,unused_vector,unused_vector,unused_vector
            fdb irq,unused_vector,unused_vector,reset

            org $4000
sprite_table incbin "gen/sprtable.bin"
TAB_ALT     incbin "gen/tabalt.bin"     ; for walls: in fixed ROM, which the blitter can read whatever the bank
trail_shapes incbin "gen/trailshapes.bin"
            include "spawn_table.asm"
            include "lasers.asm"
            include "effects.asm"
            include "render.asm"
            assert *<=$8800,"fixed ROM has met the sprites at its top"
            org $8800
            incbin "gen/sprfix.bin"
            include "edge.asm"
            include "far_rows.asm"
            assert *<=$9000,"fixed ROM ends here"

            bank 0
            org $0000
            incbin "gen/sprites.bin"
            endbank
            bank 1
            org $0000
            incbin "gen/level1.bin"
            org ATLAS1_ORG
            incbin "gen/atlas1.bin"
            endbank
            bank 2
            org $0000
            incbin "gen/level2.bin"
            org ATLAS2_ORG
            incbin "gen/atlas2.bin"
            endbank
            bank 3
            org $0000
            incbin "gen/level3.bin"
            org ATLAS3_ORG
            incbin "gen/atlas3.bin"
            endbank
            bank 4
            org $0000
            incbin "gen/level4.bin"
            endbank
            bank 5
            org $0000
            incbin "gen/level5.bin"
            endbank
            bank 6
            org $0000
            incbin "gen/level6.bin"
            include "screens.asm"
            include "settings.asm"
            assert *<=$4000,"the screens overflow bank 6"
            endbank
            bank 7
            org $0000
            incbin "gen/level7.bin"
            endbank
            bank 8
            org $0000
            incbin "gen/level8.bin"
            endbank
            bank 9
            org $0000
            incbin "gen/level9.bin"
            include "wizard_body.asm"
            include "boot.asm"
            include "wizard_p2draw.asm"
            include "wizard_p3draw.asm"
            include "boss_terrain.asm"
            endbank
            bank 10
            org $0000
            incbin "gen/messages.bin"
messages_end equ *
            endbank
            include "entities.asm"
            include "aliens.asm"
            include "aliens2.asm"
            include "wizard.asm"
