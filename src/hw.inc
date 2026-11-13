; Williams "Blaster" board hardware, confirmed against MAME 0.287 williams.cpp / williams_m.cpp /
; williams_v.cpp / williamsblitter.cpp.
;
; CPU: 6809E at 1 MHz (12 MHz / 3 / 4). 260 scanlines at 60.1 Hz, so about 16,640 cycles per frame.
; Memory: 0000-97FF video RAM. While C900 bit 0 is set, reads of 0000-3FFF see the selected ROM bank
;         and reads of 4000-8FFF see fixed ROM. Writes always reach RAM.
;         9700-BFFF plain RAM, C000-CFFF I/O, D000-FFFF fixed ROM.
;         BB00-BBFF per-line color 0 and BC00-BCFF per-line flags are read by the video hardware.
;         Color 0 is pen(BB00 XOR $FF), so BB00 must hold $FF for black.
; The blitter does not clip, and it will write through the I/O registers: clip every blit in software.
; Video: column-major, one byte holds 2 pixels (high nibble left). addr = (x >> 1) << 8 | y.
;        Visible x 6..297 (292 pixels), y 7..246 (240 lines).

PALETTE     equ $C000       ; 16 write-only registers, BBGGGRRR
PIA0_A      equ $C804       ; 49-way stick: X code in high nibble, Y code in low nibble
PIA0_CA     equ $C805
PIA0_B      equ $C806       ; bit 0 button 2 (jump), bit 1 button 1 (fire), bit 2 button 3, bit 4 Start 1, bit 5 Start 2
PIA0_CB     equ $C807
PIA1_A      equ $C80C       ; IN2: AutoUp, Advance, Coin3, HiScoreReset, Coin1, Coin2, Tilt
PIA1_CA     equ $C80D       ; CA1 = line 240 or later (COUNT240)
PIA1_B      equ $C80E       ; sound command, active low (idle is $3F; the board ORs in $C0)
PIA1_CB     equ $C80F       ; CB1 = VA11, toggles every 32 scanlines
ROM_SELECT  equ $C900       ; bit 0: reads of 0000-8FFF see ROM. bit 2: blits cannot write at or above $9700 (below $C000)
REMAP_SELECT equ $C940      ; which 16-byte row of blaster.col remaps blit sources (ours is all identity)
BANK_SELECT equ $C980       ; ROM bank at 0000-3FFF, 0-15
VIDEO_CTRL  equ $C9C0       ; bit 0: per-line color 0, bit 1: erase behind the beam. We use neither.
BLIT_CTRL   equ $CA00       ; writing here runs the blit; the CPU halts until it is done
BLIT_SOLID  equ $CA01
BLIT_SRC    equ $CA02       ; 16-bit
BLIT_DST    equ $CA04       ; 16-bit
BLIT_W      equ $CA06       ; width in bytes (SC2 has no XOR 4 quirk); 0 acts as 1
BLIT_H      equ $CA07       ; height in lines; 0 acts as 1
VCOUNT      equ $CB00       ; read: video counter bits 7..2
WATCHDOG    equ $CBFF       ; write WATCHDOG_KEY at least once a frame or so
WATCHDOG_KEY equ $39
CMOS        equ $CC00       ; 1K, low nibble only

; Blitter control bits
BC_NO_EVEN  equ $80
BC_NO_ODD   equ $40
BC_SHIFT    equ $20         ; shift the source right one pixel (odd x)
BC_SOLID    equ $10         ; write BLIT_SOLID instead of the source
BC_FG_ONLY  equ $08         ; source pixels of 0 are transparent
BC_SLOW     equ $04         ; 2 us per byte instead of 1 us
BC_DST256   equ $02         ; destination steps 256 per byte, which is what column-major video needs
BC_SRC256   equ $01

; Input bits
BTN_JUMP    equ $01         ; PIA0_B, button 2
BTN_FIRE    equ $02         ; PIA0_B, button 1
BTN_ALTJUMP equ $04         ; PIA0_B, button 3
BTN_START1  equ $10
BTN_START2  equ $20
IN2_COIN1   equ $10
IN2_COIN2   equ $20
IN2_COIN3   equ $04
; 49-way axis codes, 7 positions: 0000 full left/up, 0100, 0110, 0111 center, 1011, 1001, 1000 full right/down.

; RAM
RAM_START   equ $9700
COLOR0_TABLE equ $BB00
LINE_FLAGS  equ $BC00
RAM_END     equ $BFFF
