; Blaster board bring-up: boot, palette, IRQ, watchdog, inputs, banked blit source, window protection,
; sound commands. Run with tools/hwtest.lua.
            include "hw.inc"

            org $9800
            setdp $98
frames      rmb 2           ; COUNT240 interrupts
ticks       rmb 2           ; completed ticks
spare       rmb 2           ; idle-loop passes in the last tick, 14 cycles each
late        rmb 2           ; ticks over budget
phase       rmb 1
stick       rmb 1           ; raw 49-way port
buttons     rmb 1           ; raw button port
banktest    rmb 1           ; 1 = writes under banked ROM reach video RAM
booted      rmb 1
rombyte     rmb 1           ; first byte of each bank's marker test: bank 5 expected $55
wintest     rmb 1           ; 1 = the window stopped a blit into RAM
guard       rmb 1           ; target of the window test
sndcmd      rmb 1           ; sound command to send, written by the test script

WIN_X       equ $0900       ; column 9
WIN_Y       equ 20

            org $D000
reset       orcc #$50
            lds #$BFFF
            lda #$98
            tfr a,dp
            ldx #$9700
.clr        clr ,x+
            cmpx #$BF00
            blo .clr
            ; Color 0 is pen(BB00 ^ FF): black needs FF. The line flags stay 0 (cleared above).
            lda #$FF
            sta COLOR0_TABLE
            clr VIDEO_CTRL
            clr REMAP_SELECT
            ; PIA 0: inputs. CB2 output low selects the stick and the button group through the muxes.
            clr PIA0_CA
            clr PIA0_A
            lda #$04
            sta PIA0_CA
            clr PIA0_CB
            clr PIA0_B
            lda #$34        ; CB2 output, low; data register selected
            sta PIA0_CB
            ; PIA 1: port A inputs with a rising CA1 interrupt, port B to the sound boards.
            clr PIA1_CA
            clr PIA1_A
            lda #$07
            sta PIA1_CA
            clr PIA1_CB
            lda #$FF
            sta PIA1_B
            lda #$04
            sta PIA1_CB
            lda #$FF
            sta PIA1_B
            ; Palette.
            ldx #pal_data
            ldu #PALETTE
            ldb #16
.pal        lda ,x+
            sta ,u+
            decb
            bne .pal
            ; Writes under ROM.
            clr ROM_SELECT
            lda #1
            sta ROM_SELECT
            lda #$A5
            sta $1001
            clr ROM_SELECT
            lda $1001
            cmpa #$A5
            bne .nofall
            inc <banktest
.nofall     ; ROM visible, blits cannot touch 9700-BFFF.
            lda #$05
            sta ROM_SELECT
            ; Bank switching: bank 5 has its marker at 0000.
            lda #5
            sta BANK_SELECT
            lda $0000
            sta <rombyte
            ; Window test: try to blit a solid byte onto `guard`.
            lda #$77
            sta <guard
            clr BLIT_SOLID
            ldd #guard
            std BLIT_DST
            lda #1
            sta BLIT_W
            sta BLIT_H
            lda #BC_SOLID
            sta BLIT_CTRL
            lda <guard
            cmpa #$77
            bne .nowin
            inc <wintest
.nowin      ; Clear the screen.
            clr BLIT_SOLID
            ldd #0
            std BLIT_DST
            lda #152
            sta BLIT_W
            lda #255
            sta BLIT_H
            lda #BC_SOLID+BC_DST256
            sta BLIT_CTRL
            inc <booted
            andcc #$EF

loop        lda #WATCHDOG_KEY
            sta WATCHDOG
            lda PIA0_A
            sta <stick
            lda PIA0_B
            sta <buttons
            ; Sound command from the test script, active low on the wire.
            lda <sndcmd
            beq .nosnd
            coma
            sta PIA1_B
            clr <sndcmd
            bra .sent
.nosnd      lda #$FF
            sta PIA1_B
.sent       jsr draw_load
            ldx #0
.idle       lda <phase
            cmpa #2
            leax 1,x
            blo .idle
            stx <spare
            suba #2
            beq .ontime
            ldd <late
            addd #1
            std <late
.ontime     clr <phase
            ldd <ticks
            addd #1
            std <ticks
            bra loop

; The sprite comes from bank 5, which also proves the blitter reads the banked ROM.
draw_load   ldb #12
            ldx #WIN_X+WIN_Y
.spr        pshs b
            clr BLIT_SOLID
            stx BLIT_DST
            lda #7
            sta BLIT_W
            lda #12
            sta BLIT_H
            lda #BC_SOLID+BC_DST256
            sta BLIT_CTRL
            ldd #sprite
            std BLIT_SRC
            stx BLIT_DST
            lda #BC_DST256+BC_FG_ONLY
            sta BLIT_CTRL
            leax $0B10,x
            puls b
            decb
            bne .spr
            rts

irq         lda PIA1_A
            inc phase
            ldd frames
            addd #1
            std frames
            rti

unused      rti

pal_data    fcb $00,$07,$3F,$38,$F8,$C0,$C7,$FF,$52,$A4,$07,$38,$C0,$C7,$F8,$FF

            org $FFF0
            fdb unused,unused,unused,unused,irq,unused,unused,reset

            bank 5
            org $0000
            fcb $55
sprite      fcb $00,$00,$22,$00,$00,$00,$00
            fcb $00,$02,$22,$20,$00,$00,$00
            fcb $00,$22,$22,$22,$00,$00,$00
            fcb $00,$22,$22,$22,$00,$00,$00
            fcb $00,$02,$22,$20,$00,$00,$00
            fcb $00,$00,$22,$00,$00,$00,$00
            fcb $00,$02,$22,$20,$00,$00,$00
            fcb $00,$22,$22,$22,$00,$00,$00
            fcb $02,$22,$22,$22,$20,$00,$00
            fcb $00,$22,$00,$22,$00,$00,$00
            fcb $02,$20,$00,$02,$20,$00,$00
            fcb $22,$00,$00,$00,$22,$00,$00
            endbank
