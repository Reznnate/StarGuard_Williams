; The screens between levels: the title, the level's score counted up, the scores, the win. Bank 6, after that level's data.
; They lay out as Main.as does on its 192x108 screen, placed inside the window, with the bezel around them.
; Their RAM is the entity pool, which no screen uses: Game_Reset clears it, and clears it again before a level.

SC_OX       equ 50              ; the original's 0,0, in the coordinates of Text_Draw
SC_OY       equ 67
SC_BTNS     equ BTN_FIRE+BTN_JUMP+BTN_ALTJUMP+BTN_START1+BTN_START2
ST_COUNT    equ 32
; The title's stars fill the monitor, which shows byte columns SCH_C0 on and lines SCH_LN0 to SCH_LN1; in the original's 108
; lines, only those free of text (ti_lines). The title shows no bezel.
SCH_C0      equ 3
SCH_NC      equ 146
SCH_LN0     equ 7
SCH_LN1     equ 246
SC_NSTAR    equ 80              ; for as many to the area as the original's 32
SC_STAR     equ 5               ; a star: column (8.8), line on the screen, speed (8.8)

lc_ticks    equ ent_pool+0
lc_tbonus   equ ent_pool+2
lc_kbonus   equ ent_pool+4
lc_high     equ ent_pool+6
lc_rank     equ ent_pool+8      ; where this score goes in the level's three, or 3
lc_skip     equ ent_pool+9
sc_col      equ ent_pool+10
sc_tmp      equ ent_pool+11
sc_n        equ ent_pool+12
sc_i        equ ent_pool+13
sc_d        equ ent_pool+14
sc_fn       equ ent_pool+15
sc_p        equ ent_pool+17     ; 3 bytes: a product
sc_rem      equ ent_pool+20
sc_div      equ ent_pool+21
sc_mulc     equ ent_pool+22
sc_buf      equ ent_pool+23     ; 5 bytes of text
sc_cn       equ ent_pool+28
g_score     equ ent_pool+29     ; an entry in the CMOS
g_time      equ ent_pool+31
g_kills     equ ent_pool+33
g_total     equ ent_pool+35
g_ini       equ ent_pool+37     ; 3 letters, and an end
sc_sel      equ ent_pool+41
sc_lasty    equ ent_pool+42
sc_lastx    equ ent_pool+43
sc_timer    equ ent_pool+44
sc_seed     equ ent_pool+46
sc_any      equ ent_pool+48
sc_x        equ ent_pool+49
sc_y        equ ent_pool+51
sc_mode     equ ent_pool+53
sc_flash    equ ent_pool+54
sc_r        equ ent_pool+55
sc_ry       equ ent_pool+56
sc_rep      equ ent_pool+58
sc_stars    equ ent_pool+60

; ---- text, and what screens share. These left fixed ROM for the room. -------------------------------
; Static text, drawn straight to the screen with the blitter: for screens that do not change.
; X=screen x, Y=screen y, U=ASCII string ending in 0. draw_color=0 means white.
TEXT_W      equ 5
TEXT_LINE   equ 8

Text_Draw   stx text_x
            stx text_x0
            sty text_y
.next       lda ,u+
            beq .done
            cmpa #10
            beq .newline
            bsr ascii_glyph
            cmpb #255
            beq .advance
            pshs u
            jsr glyph_blit
            puls u
.advance    ldd text_x
            addd #TEXT_W
            std text_x
            bra .next
.newline    ldd text_x0
            std text_x
            ldd text_y
            addd #TEXT_LINE
            std text_y
            bra .next
.done       rts

; A=ASCII. Returns B=font 2 glyph, or 255 for a blank.
ascii_glyph cmpa #'A'
            blo .digit
            cmpa #'Z'
            bhi .blank
            suba #'A'
            tfr a,b
            rts
.digit      cmpa #'0'
            blo .punct
            cmpa #'9'
            bhi .punct
            suba #'0'
            adda #26
            tfr a,b
            rts
.punct      ldx #punct_table
.scan       ldb ,x++
            beq .blank
            cmpb #0
            pshs a
            cmpb ,s+
            bne .scan
            ldb -1,x
            rts
.blank      ldb #255
            rts

punct_table fcb 46,36,44,37,39,38,63,39,33,40,47,41,45,42,0,0

; X, Y=position, D=value. Prints it in decimal with no leading zeros.
Text_Number std num_val
            stx text_x
            stx text_x0
            sty text_y
            clr num_started
            ldx #num_powers
.digit      ldd ,x++
            beq .done
            std num_pow
            clr num_digit
.sub        ldd num_val
            cmpd num_pow
            blo .emit
            subd num_pow
            std num_val
            inc num_digit
            bra .sub
.emit       lda num_digit
            bne .show
            tst num_started
            bne .show
            ldd num_pow
            cmpd #1
            bne .digit
.show       lda #1
            sta num_started
            ldb num_digit
            addb #26
            pshs x
            jsr glyph_blit
            puls x
            ldd text_x
            addd #TEXT_W
            std text_x
            bra .digit
.done       rts

num_powers  fdb 10000,1000,100,10,1,0

; Waits for the fire or start button to go down. Keeps the watchdog happy.
Wait_Press  jsr Tick_Begin
            jsr Bezel_Tick
            lda <inp_pressed
            bita #BTN_FIRE+BTN_JUMP+BTN_START1+BTN_START2
            beq Wait_Press
            rts

; A screen with nothing but text.
Screen_Begin
            jsr Game_Reset
            clr <draw_color
            rts

; ---- drawing ------------------------------------------------------------------------------------
; X, Y=position on the original's screen, U=text.
S_Text      leax SC_OX,x
            leay SC_OY,y
            jmp Text_Draw

; X, Y=position, D=value.
S_Num       leax SC_OX,x
            leay SC_OY,y
            jmp Text_Number

; X=right edge, Y=line, D=value.
S_NumR      leax -5,x
            cmpd #10
            blo S_Num
            leax -5,x
            cmpd #100
            blo S_Num
            leax -5,x
            cmpd #1000
            blo S_Num
            leax -5,x
            cmpd #10000
            blo S_Num
            leax -5,x
            bra S_Num

; X=left of a field 6 wide, Y=line, D=score in units of 100.
S_Score     cmpd #0
            bne .units
            leax 30,x
            bra S_NumR
.units      leax 20,x
            pshs x,y
            bsr S_NumR
            puls x,y
            ldu #sc_txt00
            bra S_Text

; X, Y=position, A=width in pixels, B=lines, sc_col=the color in both pixels of a byte.
S_Fill      pshs a,b
            tfr x,d
            addd #SC_OX+SCR_COL0*2
            lsra
            rorb
            stb sc_tmp
            tfr y,d
            addd #SC_OY+SCR_ROW0
            lda sc_tmp
            std BLIT_DST
            puls a,b
            inca
            lsra
            std BLIT_W
            lda sc_col
            sta BLIT_SOLID
            lda #BC_SOLID+BC_DST256
            sta BLIT_CTRL
            clr BLIT_SOLID
            rts

S_Erase     clr sc_col
            bra S_Fill

; D=sprite, X, Y=the top left of its 12x12 frame. Takes draw_color.
S_Spr       pshs d
            aslb
            rola
            aslb
            rola
            aslb
            rola
            addd #sprite_table
            tfr d,u
            tfr x,d
            addd #SC_OX
            std text_x
            tfr y,d
            addd #SC_OY
            std text_y
            puls d
            jmp sprite_blit

; X=value, A=by, B=over. D=value*A/B, sc_rem=the remainder.
S_Scale     stb sc_div
            sta sc_mulc
            tfr x,d
            pshs a
            lda sc_mulc
            mul
            std sc_p+1
            puls b
            lda sc_mulc
            mul
            addb sc_p+1
            adca #0
            std sc_p
            clr sc_rem
            ldb #24
.bit        asl sc_p+2
            rol sc_p+1
            rol sc_p
            rol sc_rem
            lda sc_rem
            cmpa sc_div
            blo .next
            suba sc_div
            sta sc_rem
            inc sc_p+2
.next       decb
            bne .bit
            ldd sc_p+1
            rts

; D=ticks. Makes the two figures after the point, with the point, in sc_buf. D=seconds.
S_TimeParts tfr d,x
            lda #1
            ldb #30
            bsr S_Scale
            pshs d
            lda sc_rem
            ldb #10
            mul
            tfr d,x
            lda #1
            ldb #3
            bsr S_Scale         ; hundredths, in B
            lda #'0'-1
.ten        inca
            subb #10
            bhs .ten
            addb #'0'+10
            ldu #sc_buf
            pshs a
            lda #'.'
            sta ,u+
            puls a
            std ,u++
            clr ,u
            puls d,pc

; X, Y=position, D=ticks. Prints seconds with hundredths.
S_Time      pshs x,y
            bsr S_TimeParts
            puls x,y
            jsr S_Num
            ldx text_x
            ldy text_y
            ldu #sc_buf
            jmp Text_Draw

; A tick of a screen. Z clear if a button has just gone down.
S_Tick      jsr Tick_Begin
            jsr Bezel_Tick
            lda <inp_pressed
            bita #SC_BTNS
            rts

; ---- the CMOS: 4 bits a byte ---------------------------------------------------------------------
CM_ESIZE    equ 17              ; nibbles: letters 6, score 4, time 4, kills 3
CM_LEVEL    equ 3+3*CM_ESIZE    ; the level's total of kills 3, and three entries

; A=count, X=the place. D=the value, and X is moved on.
cm_read     sta sc_cn
            ldd #0
.next       aslb
            rola
            aslb
            rola
            aslb
            rola
            aslb
            rola
            pshs a
            lda ,x+
            anda #$0F
            pshs a
            orb ,s+
            puls a
            dec sc_cn
            bne .next
            rts

; A=count, D is taken from the stack's copy: top nibble first. X=the place, moved on.
cm_write    sta sc_cn
            puls d              ; the return
            std sc_y
            puls d              ; the value
.next       pshs a
            lsra
            lsra
            lsra
            lsra
            sta ,x+
            puls a
            aslb
            rola
            aslb
            rola
            aslb
            rola
            aslb
            rola
            dec sc_cn
            bne .next
            jmp [sc_y]

; A=level. X=its record.
cm_place    deca
            ldb #CM_LEVEL
            mul
            addd #CMOS+4
            tfr d,x
            rts

; A=level, B=rank. X=that entry.
cm_entry    pshs b
            bsr cm_place
            leax 3,x
            puls b
            lda #CM_ESIZE
            mul
            leax d,x
            rts

; A=level, B=rank. Reads the entry to g_ini and so on, and the level's total to g_total.
Cmos_Get    pshs a,b
            bsr cm_place
            lda #3
            bsr cm_read
            std g_total
            puls a,b
            lbsr cm_entry
            ldu #g_ini
            ldb #3
.letters    pshs b
            lda #2
            bsr cm_read
            stb ,u+
            puls b
            decb
            bne .letters
            clr ,u
            lda #4
            lbsr cm_read
            std g_score
            lda #4
            lbsr cm_read
            std g_time
            lda #3
            lbsr cm_read
            std g_kills
            rts

; Puts g_ini and so on in the level's place lc_rank, moving those below it down.
Cmos_Put    lda <game_level
            ldb #2
            lbsr cm_entry
            leax CM_ESIZE-1,x   ; the last nibble of the last entry
            lda #2
            suba lc_rank
            ldb #CM_ESIZE
            mul
            tstb
            beq .moved
.move       lda -CM_ESIZE,x
            sta ,x
            leax -1,x
            decb
            bne .move
.moved      lda <game_level
            bsr cm_place
            ldd g_total
            aslb
            rola
            aslb
            rola
            aslb
            rola
            aslb
            rola
            pshs d
            lda #3
            lbsr cm_write
            lda <game_level
            ldb lc_rank
            lbsr cm_entry
            ldu #g_ini
            ldb #3
.letters    pshs b
            ldb ,u+
            clra
            exg a,b
            pshs d
            lda #2
            lbsr cm_write
            puls b
            decb
            bne .letters
            ldd g_score
            pshs d
            lda #4
            lbsr cm_write
            ldd g_time
            pshs d
            lda #4
            lbsr cm_write
            ldd g_kills
            aslb
            rola
            aslb
            rola
            aslb
            rola
            aslb
            rola
            pshs d
            lda #3
            jsr cm_write
            rts

; Makes the CMOS ours if it is not yet, and clears what lives above $BF00.
Cmos_Check  clr gov_free
            clr trial_on
            clr trial_new
            clr lv_exit
            ldx #CMOS
            ldu #cm_magic
            ldb #4
.look       lda ,x+
            anda #$0F
            cmpa ,u+
            bne .fresh
            decb
            bne .look
            jmp st_masks
.fresh      ldx #CMOS+4
.clear      clr ,x+
            cmpx #CM_SET_END    ; the scores and the settings
            blo .clear
            ldx #CMOS
            ldu #cm_magic
            ldb #4
.mark       lda ,u+
            sta ,x+
            decb
            bne .mark
            jmp st_masks
cm_magic    fcb 5,10,12,4

; ---- the level's score ---------------------------------------------------------------------------
LC_X        equ 42              ; as LevelCompleteLoop lays it out
LC_Y        equ 26
LC_LINE     equ 12
LC_W        equ 108
LC_NUM      equ 119             ; the left of the figures on the right
LC_TEXT     equ 52

; Main.EndLevel, RecordNormalModeScores and LevelCompleteLoop.
Level_Complete
            jsr Screen_Begin
            ldd <now
            subd <level_start_t
            std lc_ticks
            ; What was earned by killing: all but the crystals.
            ldb <crystals
            lda #20
            mul
            std sc_x
            ldd <level_score
            subd sc_x
            bhs .kb
            ldd #0
.kb         std lc_kbonus
            ; The time bonus: 2 units a second under 80 seconds.
            ldd #80*30
            subd lc_ticks
            bhs .tb
            ldd #0
.tb         tfr d,x
            lda #1
            ldb #15
            jsr S_Scale
            std lc_tbonus
            addd <level_score
            std <level_score
            ; The best so far for this level.
            lda <game_level
            clrb
            jsr Cmos_Get
            ldd g_score
            std lc_high
            clr <draw_color
            ; Step 0: nothing yet. Step 1: the heading.
            ldb #24
            jsr lc_wait
            jsr lc_heading
            ldb #24
            jsr lc_wait
            ; Step 2: the time counted up, over at most 2 seconds.
            ldx lc_ticks
            lda #1
            ldb #30
            jsr S_Scale
            cmpd #30
            blo .t1
            ldd #30
.t1         aslb
            bne .t2
            ldb #1
.t2         ldx #lc_show_time
            jsr lc_count
            ; Step 3.
            jsr lc_time_done
            ldb #12
            jsr lc_wait
            ; Step 4: the kills counted up.
            ldd <kills
            cmpd #30
            blo .k1
            ldd #30
.k1         aslb
            beq .k2
            ldx #lc_show_kills
            jsr lc_count
            bra .k3
.k2         clr sc_i
            lda #1
            sta sc_d
            jsr lc_show_kills
            ; Step 5: their bonus.
.k3         jsr lc_kills_done
            ldb #24
            jsr lc_wait
            ; Step 6: the score counted up. It leaves out the crystals until the end.
            jsr lc_score_line
            jsr lc_high_show
            jsr lc_no_crystals
            cmpd #300
            blo .s1
            ldb #60
            bra .s2
.s1         tfr d,x
            lda #1
            ldb #5
            jsr S_Scale
            tstb
            beq .s3
.s2         ldx #lc_show_score
            jsr lc_count
            ; Step 7.
.s3         jsr lc_score_part
            ldb #24
            jsr lc_wait
            ; Step 8. A button at any time comes straight here, with everything shown.
            jsr lc_heading
            jsr lc_time_done
            jsr lc_kills_done
            jsr lc_score_line
            jsr lc_score_all
            jsr lc_deaths
            ldd <level_score
            cmpd lc_high
            bls .plain
            std lc_high
            lda #SND_GUI_03
            bra .snd
.plain      lda #SND_GUI_02
.snd        jsr Sound_Play
            jsr lc_high_show
            jsr lc_record
            ; The prompt flashes, and a crystal turns if there is one.
            lda #15
            sta sc_i
.wait       jsr S_Tick
            lda <inp_pressed
            bita #BTN_JUMP
            bne .exit
            bita #BTN_FIRE+BTN_START1+BTN_START2
            bne .out
            lda <now+1
            anda #1
            bne .noturn
            jsr lc_crystal
.noturn     inc sc_i
            lda sc_i
            cmpa #16
            blo .even
            clr sc_i
            clra
.even       cmpa #8
            beq .hide
            tsta
            bne .wait
            ldx #29
            ldy #98
            ldu #sc_txtgoex
            jsr S_Text
            bra .wait
.hide       ldx #28
            ldy #98
            lda #138
            ldb #6
            jsr S_Erase
            bra .wait
.exit       lda #1
            sta lv_exit
.out        rts

; Does this score go in the level's three? If so, takes the letters and writes it.
lc_record   clr lc_rank
.look       lda <game_level
            ldb lc_rank
            jsr Cmos_Get
            ldd g_time
            beq .found          ; nothing here yet
            ldd <level_score
            cmpd g_score
            bhi .found
            inc lc_rank
            lda lc_rank
            cmpa #3
            blo .look
            rts
.found      lda <game_level
            sta trial_new
            bsr lc_letters
            ldd <level_score
            std g_score
            ldd lc_ticks
            bne .tnz
            ldd #1              ; a time of 0 means an empty entry
.tnz        std g_time
            ldd <kills
            std g_kills
            ldd <kill_total
            std g_total
            jmp Cmos_Put

; ENTER INITIALS. The stick changes a letter, fire goes on, jump goes back. After 20 seconds it takes what it has.
LI_X        equ 88
LI_Y        equ 82
lc_letters  ldx #61
            ldy #72
            ldu #sc_txtenter
            jsr S_Text
            ldd #'A'*256+'A'
            std g_ini
            std g_ini+1
            clr g_ini+3
            clr sc_i
            clr sc_rep
            lda <inp_ydir
            sta sc_lasty
            ldd #20*30
            std sc_timer
            lbsr li_show
.loop       jsr S_Tick
            lda <inp_pressed
            bita #BTN_FIRE+BTN_START1+BTN_START2
            beq .nofire
            lda #SND_GUI_02
            jsr Sound_Play
            inc sc_i
            lda sc_i
            cmpa #3
            bhs .done
            bsr li_show
            bra .timer
.nofire     bita #BTN_JUMP
            beq .stick
            tst sc_i
            beq .edge
            dec sc_i
            lda #SND_GUI_01
            jsr Sound_Play
            bsr li_show
            bra .timer
.edge       lda #SND_GUI_04
            jsr Sound_Play
            bra .timer
.stick      lda <inp_ydir
            beq .center
            cmpa sc_lasty
            bne .turn
            dec sc_rep          ; held: it goes on changing
            bne .timer
            ldb #5
            bra .change
.turn       ldb #12
.change     stb sc_rep
            sta sc_lasty
            bsr li_turn
            lda #SND_GUI_01
            jsr Sound_Play
            bsr li_show
            bra .timer
.center     sta sc_lasty
.timer      ldd sc_timer
            subd #1
            std sc_timer
            bne .loop
.done       ldx #60
            ldy #72
            lda #74
            ldb #17
            jmp S_Erase

; The letters, and a line under the one being chosen.
li_show     ldx #LI_X-2
            ldy #LI_Y
            lda #20
            ldb #8
            jsr S_Erase
            ldx #LI_X
            ldy #LI_Y
            ldu #g_ini
            jsr S_Text
            lda #5
            ldb sc_i
            mul
            addd #LI_X
            tfr d,x
            ldy #LI_Y+6
            lda #$22
            sta sc_col
            lda #4
            ldb #1
            jmp S_Fill

; A=-1 or 1. Moves the letter being chosen along A to Z, a point, a space.
li_turn     nega                ; up is the next letter
            pshs a
            ldb sc_i
            ldx #g_ini
            abx
            lda ,x
            ldu #li_chars
            clrb
.find       cmpa b,u
            beq .found
            incb
            cmpb #28
            blo .find
            clrb
.found      addb ,s+
            bpl .notlow
            ldb #27
.notlow     cmpb #28
            blo .ok
            clrb
.ok         lda b,u
            sta ,x
            rts
li_chars    fcc "ABCDEFGHIJKLMNOPQRSTUVWXYZ. "

; B=ticks. Comes back early once a button has gone down, and does not wait from then on.
lc_wait     tst lc_skip
            bne .out
            stb sc_n
.next       jsr S_Tick
            beq .on
            inc lc_skip
            rts
.on         dec sc_n
            bne .next
.out        rts

; B=ticks, X=what shows the count at sc_i of sc_d. Every other tick it shows and ticks, as the original does 15 times a second.
lc_count    tst lc_skip
            bne .out
            stb sc_d
            stx sc_fn
            clr sc_i
.next       jsr S_Tick
            beq .on
            inc lc_skip
            rts
.on         inc sc_i
            lda sc_i
            anda #1
            bne .more
            jsr [sc_fn]
            lda #SND_GUI_01
            jsr Sound_Play
.more       lda sc_i
            cmpa sc_d
            blo .next
.out        rts

; X=a final value. D=it as far as the count has got.
lc_part     lda sc_i
            ldb sc_d
            jmp S_Scale

lc_heading  ldx #LC_X
            ldy #LC_Y
            ldu #sc_txtlevel
            jsr S_Text
            ldb <game_level
            clra
            ldx text_x
            ldy text_y
            jsr Text_Number
            ldx text_x
            ldy text_y
            ldu #sc_txtcomp
            jsr Text_Draw
            ldx #LC_X
            ldy #LC_Y+6
            lda #$77
            sta sc_col
            lda #LC_W
            ldb #1
            jmp S_Fill

lc_show_time
            ldx lc_ticks
            bsr lc_part
            pshs d
            ldx lc_tbonus
            bsr lc_part
            tfr d,x
            puls d
; D=ticks, X=the bonus.
lc_time_row pshs x
            pshs d
            ldx #LC_TEXT
            ldy #LC_Y+LC_LINE
            lda #98
            ldb #6
            jsr S_Erase
            ldd #239
            ldx #LC_X-2
            ldy #LC_Y+LC_LINE-4
            jsr S_Spr
            ldx #LC_TEXT
            ldy #LC_Y+LC_LINE
            ldu #sc_txttime
            jsr S_Text
            puls d
            ldx #LC_TEXT+35
            ldy #LC_Y+LC_LINE
            jsr S_Time
            puls d
            ldx #LC_NUM
            ldy #LC_Y+LC_LINE
            jmp S_Score

lc_time_done
            ldd lc_ticks
            ldx lc_tbonus
            bsr lc_time_row
            lda #SND_GUI_02
            tst lc_skip
            bne .out
            jmp Sound_Play
.out        rts

lc_show_kills
            ldx <kills
            jsr lc_part
; D=kills.
lc_kills_row
            pshs d
            ldx #LC_TEXT
            ldy #LC_Y+2*LC_LINE
            lda #66
            ldb #6
            jsr S_Erase
            ldd #238
            ldx #LC_X-2
            ldy #LC_Y+2*LC_LINE-4
            jsr S_Spr
            ldx #LC_TEXT
            ldy #LC_Y+2*LC_LINE
            ldu #sc_txtkills
            jsr S_Text
            puls d
            ldx #LC_TEXT+30
            ldy #LC_Y+2*LC_LINE
            jsr S_Num
            ldx text_x
            ldy text_y
            ldu #sc_txtof
            jsr Text_Draw
            ldd <kill_total
            ldx text_x
            ldy text_y
            jmp Text_Number

lc_kills_done
            ldd <kills
            bsr lc_kills_row
            ldd lc_kbonus
            ldx #LC_NUM
            ldy #LC_Y+2*LC_LINE
            jsr S_Score
            lda #SND_GUI_02
            tst lc_skip
            bne .out
            jmp Sound_Play
.out        rts

lc_score_line
            ldx #LC_X
            ldy #LC_Y+2*LC_LINE+10
            lda #$77
            sta sc_col
            lda #LC_W
            ldb #1
            jmp S_Fill

; D=the score leaving out the crystals.
lc_no_crystals
            ldb <crystals
            lda #20
            mul
            std sc_x
            ldd <level_score
            subd sc_x
            bhs .ok
            ldd #0
.ok         rts

lc_show_score
            bsr lc_no_crystals
            tfr d,x
            jsr lc_part
; D=the score.
lc_score_row
            pshs d
            ldx #LC_NUM-6
            ldy #LC_Y+3*LC_LINE
            lda #36
            ldb #6
            jsr S_Erase
            puls d
            ldx #LC_NUM
            ldy #LC_Y+3*LC_LINE
            jmp S_Score

lc_score_part
            bsr lc_no_crystals
            bsr lc_score_row
            lda #SND_GUI_02
            tst lc_skip
            bne .out
            jmp Sound_Play
.out        rts

lc_score_all
            ldd <level_score
            bra lc_score_row

lc_high_show
            ldd #237
            ldx #151
            ldy #0
            jsr S_Spr
            ldx #157
            ldy #4
            lda #30
            ldb #6
            jsr S_Erase
            ldd lc_high
            ldx #157
            ldy #4
            jmp S_Score

; NO DEATHS, or how many, and a man for each.
lc_deaths   ldx #4
            ldy #4
            ldd <deaths
            bne .some
            ldu #sc_txtnone
            jmp S_Text
.some       jsr S_Num
            ldx text_x
            ldy text_y
            ldd <deaths
            cmpd #1
            bne .many
            ldu #sc_txtdeath1
            bra .said
.many       ldu #sc_txtdeaths
.said       jsr Text_Draw
            ldd text_x
            subd #SC_OX-6
            std sc_x
            ldd <deaths
            cmpd #13
            blo .count
            ldb #13
.count      stb sc_n
.man        cmpb #0
            beq .out
            ldd #0
            ldx sc_x
            ldy #-3
            jsr S_Spr
            ldd sc_x
            addd #6
            std sc_x
            dec sc_n
            ldb sc_n
            bra .man
.out        rts

lc_crystal  tst <crystals
            beq .out
            ldx #104
            ldy #LC_Y+3*LC_LINE
            lda #12
            ldb #6
            jsr S_Erase
            lda <now+1
            lsra
            anda #3
            tfr a,b
            clra
            addd #264
            ldx #103
            ldy #LC_Y+3*LC_LINE-4
            jsr S_Spr
.out        rts

; ---- the win --------------------------------------------------------------------------------------
Win_Screen  jsr Screen_Begin
            lda #SND_WIN
            jsr Sound_Play
            ldx #26
            ldy #50
            ldu #sc_txtwin
            jsr S_Text
            ldx #48
            ldy #98
            ldu #sc_txtgo
            jsr S_Text
            jmp Wait_Press

; ---- the title ------------------------------------------------------------------------------------
TI_Y        equ 77              ; the first line of the menu
TI_X        equ 71
TI_TIME     equ 360             ; ticks before it shows the scores

; A=0 to start, 1 for the scores.
Title_Screen
            tst adv_req         ; Advance, here or on an attract screen
            beq .title
            jsr Bezel_On        ; the settings show the bezel
            jsr Settings_Screen
            ; The title shows none: its stars fill the monitor. Off at once, before the screen is cleared, which takes a few
            ; frames. Bezel_On brings it back.
.title      clr VIDEO_CTRL
            clr bz_dirty
            jsr Screen_Begin
            ldd <now
            addd #$ACE1
            std sc_seed
            jsr ti_any
            ; The emblem, the name, and the two lines the menu sits between.
            ldd #248
            ldx #83
            ldy #36
            jsr S_Spr
            ldd #249
            ldx #95
            ldy #36
            jsr S_Spr
            ldd #250
            ldx #83
            ldy #48
            jsr S_Spr
            ldd #251
            ldx #95
            ldy #48
            jsr S_Spr
            ldx #70
            ldy #56
            ldu #sc_txtstar
            jsr S_Text
            ldx #98
            ldy #56
            ldu #sc_txtguard
            jsr S_Text
            lda #$77
            sta sc_col
            ldx #0
            ldy #TI_Y-6
            lda #192
            ldb #1
            jsr S_Fill
            ldx #0
            ldy #TI_Y+15
            lda #192
            ldb #1
            jsr S_Fill
            ldx #TI_X
            ldy #TI_Y
            ldu #sc_txtstart
            jsr S_Text
            tst sc_any
            bne .open
            lda #COLOR_RED
            sta <draw_color
            ldu #sc_txtlocked
            bra .trial
.open       ldu #sc_txttrial
.trial      ldx #TI_X
            ldy #TI_Y+7
            jsr S_Text
            clr <draw_color
            jsr ti_stars_new
            ; TitleFlash: the screen goes white as it appears.
            lda #$FF
            ldx #PALETTE
            ldb #16
.white      sta ,x+
            decb
            bne .white
            ldd #TI_TIME
            std sc_timer
            lda <inp_ydir       ; a stick already held is not a push
            sta sc_lasty
.loop       jsr st_tick
            bne .press
            jsr ti_flash_end
            jsr ti_stars
            jsr ti_cursor
            lda <inp_ydir
            cmpa sc_lasty
            beq .same
            sta sc_lasty
            tsta
            beq .same
            ldx #TI_X-12
            ldy #TI_Y-4
            lda #12
            ldb #17
            jsr S_Erase
            lda sc_sel
            eora #1
            sta sc_sel
            lda #SND_GUI_01
            jsr Sound_Play
            ldd #TI_TIME
            std sc_timer
.same       ldd sc_timer
            subd #1
            std sc_timer
            bne .loop
            ; Left alone, as the original: the story, the bestiary. Then the scores, and back. A button comes back at once.
            jsr ti_palette
            jsr Bezel_On
            jsr Story_Screen
            lbne Title_Screen
            jsr Bestiary_Screen
            lbne Title_Screen
            lda #1
            jsr sc_show
            lbra Title_Screen
.press      jsr ti_palette
            tst adv_req
            lbne Title_Screen
            lda sc_sel
            beq .go
            tst sc_any
            bne .go
            lda #SND_GUI_05
            jsr Sound_Play
            bra .loop
.go         lda #SND_GUI_02
            jsr Sound_Play
            jsr Bezel_On
            lda sc_sel
            rts

; Any level finished?
ti_any      clr sc_any
            lda #9
.next       pshs a
            clrb
            jsr Cmos_Get
            puls a
            ldx g_time
            beq .none
            inc sc_any
.none       deca
            bne .next
            rts

ti_flash_end
            ldd #TI_TIME
            subd sc_timer
            cmpd #4
            beq ti_palette
            rts
ti_palette  ldx #hw_palette
            ldu #PALETTE
            ldb #16
.next       lda ,x+
            sta ,u+
            decb
            bne .next
            rts

; The picture of the cursor that goes by the menu line. It is a crystal that turns.
ti_cursor   lda <now+1
            anda #3
            bne .out
            lda sc_sel
            ldb #7
            mul
            addb #TI_Y-4
            clra
            tfr d,y
            ldx #TI_X-12
            lda #12
            ldb #10
            pshs y
            jsr S_Erase
            puls y
            lda <now+1
            lsra
            lsra
            ldb #6
            pshs b
.mod        cmpa ,s
            blo .modded
            suba ,s
            bra .mod
.modded     leas 1,s
            suba #3
            bpl .abs
            nega
.abs        tfr a,b
            clra
            addd #260
            ldx #TI_X-12
            jmp S_Spr
.out        rts

; A random number in D, kept apart from the game's own.
ti_rand     ldd sc_seed
            lsra
            rorb
            bcc .done
            eora #$B4
.done       std sc_seed
            rts

; Y=a star. Starts it at the right on a line with nothing else on it.
ti_star_new bsr ti_rand
            stb sc_tmp
            cmpa #SCH_LN1-SCH_LN0+1
            bhs ti_star_new
            adda #SCH_LN0       ; the line
            cmpa #SC_OY+SCR_ROW0
            blo .line
            cmpa #SC_OY+SCR_ROW0+107
            bhi .line
            lda sc_tmp          ; in the original's lines: one with nothing else on it
            lsra
            lsra
            lsra
            ldx #ti_lines
            lda a,x
            adda #SC_OY+SCR_ROW0
.line       sta 2,y
            lda sc_tmp
            anda #7
            asla
            ldx #ti_speeds
            ldd a,x
            std 3,y
            ldd #(SCH_NC-1)*256
            std ,y
            rts

; The lines that have no text or emblem.
ti_lines    fcb 0,2,4,6,8,10,12,14,16,18,20,22,24,26,28,30
            fcb 32,62,63,65,67,69,96,98,100,102,104,106,1,5,9,13
; As Star: from a twentieth of top speed to all of it, most of them slow.
ti_speeds   fdb 82,100,130,180,260,400,700,1600

ti_stars_new
            ldy #sc_stars
            lda #SC_NSTAR
            sta sc_n
.next       jsr ti_star_new
            jsr ti_rand
            cmpa #SCH_NC
            blo .col
            suba #SCH_NC
.col        sta ,y
            leay SC_STAR,y
            dec sc_n
            bne .next
            rts

; Each moves left. A star is written straight to the screen.
ti_stars    ldy #sc_stars
            lda #SC_NSTAR
            sta sc_n
.next       ldd ,y
            sta sc_tmp
            subd 3,y
            bcs .off
            std ,y
            cmpa sc_tmp
            beq .on
            adda #SCH_C0
            ldb 2,y
            tfr d,x
            lda #$77
            sta ,x
            lda sc_tmp
            adda #SCH_C0
            ldb 2,y
            tfr d,x
            clr ,x
            bra .on
.off        lda sc_tmp
            adda #SCH_C0
            ldb 2,y
            tfr d,x
            clr ,x
            jsr ti_star_new
            lda #SCH_C0+SCH_NC-1
            ldb 2,y
            tfr d,x
            lda #$77
            sta ,x
.on         leay SC_STAR,y
            dec sc_n
            bne .next
            rts

; ---- the story and the bestiary --------------------------------------------------------------------
; Z clear if a button ended it. Y=ticks left, on entry.
sc_wait_tick
            jsr st_tick
            bne .pressed
            lda sc_i
            inca
            anda #15
            sta sc_i
            cmpa #8
            beq .hide
            tsta
            bne .quiet
            ldx #48
            ldy #98
            ldu #sc_txtgo
            jsr S_Text
            bra .quiet
.hide       ldx #48
            ldy #98
            lda #96
            ldb #6
            jsr S_Erase
.quiet      clra
.pressed    rts

Story_Screen
            jsr Screen_Begin
            ldx #70
            ldy #14
            ldu #sc_txtsg
            jsr S_Text
            ldx #18
            ldy #28
            ldu #sc_txtstory
            jsr S_Text
            lda #15
            sta sc_i
            ldd #12*30
            std sc_timer
.loop       bsr sc_wait_tick
            bne .out
            ldd sc_timer
            subd #1
            std sc_timer
            bne .loop
            clra
.out        rts

Bestiary_Screen
            jsr Screen_Begin
            ldx #70
            ldy #7
            ldu #sc_txtsg
            jsr S_Text
            ldx #70
            ldy #21
            ldu #sc_txtb1
            jsr S_Text
            ldx #70
            ldy #35
            ldu #sc_txtb2
            jsr S_Text
            ldx #70
            ldy #49
            ldu #sc_txtb3
            jsr S_Text
            ldx #70
            ldy #63
            ldu #sc_txtb4
            jsr S_Text
            ldx #18
            ldy #73
            ldu #sc_txtb5
            jsr S_Text
            lda #15
            sta sc_i
            ldd #8*30
            std sc_timer
.loop       lbsr sc_wait_tick
            bne .out
            lda sc_timer+1
            anda #1
            bne .still
            jsr bs_draw
.still      ldd sc_timer
            subd #1
            std sc_timer
            bne .loop
            clra
.out        rts

; X=the time, A/B=its rate, sc_tmp=how many frames. A=which frame now.
bs_frame    jsr S_Scale
.mod        cmpd #0
            beq .done
            cmpb sc_n
            blo .done
            subb sc_n
            bra .mod
.done       tfr b,a
            rts

; The four monsters, each moving as it does in BestiaryLoop.
bs_draw     ldd #8*30
            subd sc_timer
            std sc_x            ; ticks so far
            ; The zomboid.
            ldx #48
            ldy #15
            lda #12
            ldb #12
            jsr S_Erase
            lda #5
            sta sc_n
            ldx sc_x
            lda #2
            ldb #5
            bsr bs_frame
            tfr a,b
            clra
            addd #91
            ldx #48
            ldy #15
            jsr S_Spr
            ; The trooper: it stands, then fires.
            ldx #48
            ldy #29
            lda #12
            ldb #12
            jsr S_Erase
            lda #21
            sta sc_n
            ldx sc_x
            lda #1
            ldb #3
            bsr bs_frame
            cmpa #9
            bhi .fire
            clra
            bra .tset
.fire       anda #3
            adda #2
.tset       tfr a,b
            clra
            addd #78
            ldx #48
            ldy #29
            jsr S_Spr
            ; The flier.
            ldx #48
            ldy #45
            lda #12
            ldb #12
            jsr S_Erase
            lda #4
            sta sc_n
            ldx sc_x
            lda #2
            ldb #5
            lbsr bs_frame
            tfr a,b
            clra
            addd #60
            ldx #48
            ldy #45
            jsr S_Spr
            ; The jumper: it crouches and leaps.
            ldx #48
            ldy #59
            lda #12
            ldb #12
            jsr S_Erase
            lda #8
            sta sc_n
            ldx sc_x
            lda #4
            ldb #15
            lbsr bs_frame
            ldb #1
            tsta
            beq .jset
            clrb
            cmpa #3
            bne .jtwo
            ldb #1
            bra .jset
.jtwo       cmpa #4
            blo .jset
            ldb #4
.jset       clra
            addd #192
            ldx #48
            ldy #59
            jmp S_Spr

; ---- the scores -----------------------------------------------------------------------------------
; This screen is all of the picture: the bezel is off while it shows. Positions are from the corner of the screen, less the origin of the others.
SG_X        equ -SC_OX
SG_Y        equ -SC_OY
SG_BOXW     equ 92
SG_BOXH     equ 70
SG_STEPX    equ 96
SG_STEPY    equ 76
SG_ROW      equ 19              ; an entry's height

; From the title or after a trial. A=the level chosen, or 0.
Scores_Screen
            clra
            jsr sc_show
            rts

; A=0 for a choice, 1 to show them for a while.
sc_show     pshs a
            jsr Screen_Begin
            puls a
            sta sc_mode
            clr VIDEO_CTRL
            clr sc_sel
            tst trial_on
            beq .first
            lda <game_level
            deca
            sta sc_sel
.first      ldx #SG_X+101
            ldy #SG_Y+2
            ldu #sc_txthead
            jsr S_Text
            lda #1
            sta sc_i
.boxes      jsr sc_box
            lda #WATCHDOG_KEY
            sta WATCHDOG
            inc sc_i
            lda sc_i
            cmpa #10
            blo .boxes
            ldd #8*30
            std sc_timer
            lda <inp_dir        ; a stick already held is not a push
            sta sc_lastx
            lda <inp_ydir
            sta sc_lasty
            clr sc_flash
            lda #1
            jsr sc_outline
.loop       jsr Tick_Begin
            lda <inp_pressed
            bita #SC_BTNS
            bne .press
            jsr st_adv
            lbne .back
            jsr sc_keys
            inc sc_flash
            lda sc_flash
            cmpa #16
            blo .even
            clr sc_flash
            clra
.even       cmpa #8
            bne .notoff
            clra
            jsr sc_outline
            bra .timer
.notoff     tsta
            bne .timer
            lda #1
            jsr sc_outline
.timer      tst sc_mode
            beq .loop
            ldd sc_timer
            subd #1
            std sc_timer
            bne .loop
.back       clr trial_new
            clra
            bra .leave
.press      tst sc_mode
            bne .back
            lda <inp_pressed
            bita #BTN_JUMP
            beq .choose
            lda #SND_GUI_01
            jsr Sound_Play
            bra .back
.choose     lda sc_sel
            inca
            clrb
            jsr Cmos_Get
            ldd g_time
            bne .chosen
            lda #SND_GUI_05
            jsr Sound_Play
            bra .loop
.chosen     lda #SND_GUI_02
            jsr Sound_Play
            clr trial_new
            lda sc_sel
            inca
.leave      pshs a
            lda #1              ; the bezel again: the screen is cleared after this, which brings back its rails
            sta VIDEO_CTRL
            puls a,pc

; A=level less 1. sc_x, sc_y=the box's corner.
sc_corner   pshs a
            clr sc_tmp
.row        cmpa #3
            blo .rowed
            suba #3
            inc sc_tmp
            bra .row
.rowed      ldb #SG_STEPX
            mul
            addd #SG_X+2
            std sc_x
            lda sc_tmp
            ldb #SG_STEPY
            mul
            addd #SG_Y+12
            std sc_y
            puls a,pc

; sc_i=level. Its box: the level's name, and its three.
sc_box      lda sc_i
            deca
            bsr sc_corner
            lda sc_i
            clrb
            jsr Cmos_Get
            ; The frame: white, yellow for a record just set, red if not finished.
            lda #$11
            ldx g_time
            beq .framed
            lda #$77
            ldb sc_i
            cmpb trial_new
            bne .framed
            lda #$22
.framed     sta sc_col
            ldx sc_x
            ldy sc_y
            lda #SG_BOXW
            ldb #SG_BOXH
            jsr S_Fill
            ldx sc_x
            leax 2,x
            ldy sc_y
            leay 1,y
            lda #SG_BOXW-4
            ldb #SG_BOXH-2
            jsr S_Erase
            ldx g_time
            lbeq .open
            lda #COLOR_YELLOW
            sta <draw_color
            ldd sc_x
            addd #28
            tfr d,x
            ldy sc_y
            leay 3,y
            jsr sc_name
            clr <draw_color
            clr sc_r
            ldd sc_y
            addd #12
            std sc_ry
.entry      lda sc_i
            ldb sc_r
            jsr Cmos_Get
            ldd g_time
            lbeq .empty
            ldx sc_x
            leax 4,x
            ldy sc_ry
            ldu #g_ini
            jsr S_Text
            ldd sc_x
            addd #4+25
            tfr d,x
            ldy sc_ry
            ldd g_score
            jsr S_Score
            ; The time and the kills beneath.
            ldx sc_x
            leax 2,x
            ldd sc_ry
            addd #3
            tfr d,y
            ldd #239
            jsr S_Spr
            ldd g_time
            jsr S_TimeParts
            pshs d
            ldx sc_x
            leax 44-15,x
            ldd sc_ry
            addd #8
            tfr d,y
            puls d
            jsr S_NumR
            ldx text_x
            ldy text_y
            ldu #sc_buf
            jsr Text_Draw
            lda #COLOR_RED
            sta <draw_color
            ldx sc_x
            leax 44,x
            ldd sc_ry
            addd #4
            tfr d,y
            ldd #238
            jsr S_Spr
            clr <draw_color
            ldx sc_x
            leax 57,x
            ldd sc_ry
            addd #8
            tfr d,y
            ldd g_kills
            jsr S_Num
            ldx text_x
            ldy text_y
            ldu #sc_txtof
            jsr Text_Draw
            ldd g_total
            ldx text_x
            ldy text_y
            jsr Text_Number
            bra .nextr
.empty      ldx sc_x
            leax 4,x
            ldy sc_ry
            ldu #sc_txtdots
            jsr S_Text
.nextr      ldd sc_ry
            addd #SG_ROW
            std sc_ry
            inc sc_r
            lda sc_r
            cmpa #3
            lblo .entry
            rts
.open       lda #COLOR_RED
            sta <draw_color
            ldd sc_x
            addd #28
            tfr d,x
            ldy sc_y
            leay 24,y
            jsr sc_name
            lda #COLOR_RED
            sta <draw_color
            ldx sc_x
            leax 21,x
            ldy sc_y
            leay 36,y
            ldu #sc_txtinc
            jsr S_Text
            clr <draw_color
            rts

; X, Y=position, sc_i=level. LEVEL n.
sc_name     ldu #sc_txtlevel
            jsr S_Text
            ldb sc_i
            clra
            ldx text_x
            ldy text_y
            jmp Text_Number

; A=1 to draw the mark round the box chosen, 0 to take it away.
sc_outline  beq .black
            ldb #$77
            bra .col
.black      clrb
.col        stb sc_col
            lda sc_sel
            jsr sc_corner
            ldd sc_x
            subd #2
            tfr d,x
            ldd sc_y
            subd #2
            tfr d,y
            lda #SG_BOXW+4
            ldb #1
            jsr S_Fill
            ldd sc_x
            subd #2
            tfr d,x
            ldd sc_y
            addd #SG_BOXH+1
            tfr d,y
            lda #SG_BOXW+4
            ldb #1
            jsr S_Fill
            ldd sc_x
            subd #2
            tfr d,x
            ldd sc_y
            subd #2
            tfr d,y
            lda #2
            ldb #SG_BOXH+4
            jsr S_Fill
            ldd sc_x
            addd #SG_BOXW
            tfr d,x
            ldd sc_y
            subd #2
            tfr d,y
            lda #2
            ldb #SG_BOXH+4
            jmp S_Fill

; The stick moves the choice, one box a push.
sc_keys     tst sc_mode
            lbne .out
            lda <inp_dir
            cmpa sc_lastx
            beq .y
            sta sc_lastx
            tsta
            beq .y
            bmi .left
            lda sc_sel
.rmod       cmpa #3
            blo .rm
            suba #3
            bra .rmod
.rm         cmpa #2
            bhs .edge
            ldb #1
            bra .move
.left       lda sc_sel
.lmod       cmpa #3
            blo .lm
            suba #3
            bra .lmod
.lm         tsta
            beq .edge
            ldb #-1
            bra .move
.y          lda <inp_ydir
            cmpa sc_lasty
            beq .out
            sta sc_lasty
            tsta
            beq .out
            bmi .up
            lda sc_sel
            cmpa #6
            bhs .edge
            ldb #3
            bra .move
.up         lda sc_sel
            cmpa #3
            blo .edge
            ldb #-3
.move       pshs b
            clra
            jsr sc_outline
            puls b
            addb sc_sel
            stb sc_sel
            clr sc_flash
            lda #1
            jsr sc_outline
            lda #SND_GUI_01
            jmp Sound_Play
.edge       lda #SND_GUI_04
            jmp Sound_Play
.out        rts

; The bands above and below the window, as the board's color for each line. No pixel is drawn for them, so nothing has to be erased or repaired.
Bezel_On    ldx #COLOR0_TABLE+1
.all        lda #$FF            ; color 0 is pen(value^$FF): black
            sta ,x
            lda #1              ; this line takes a color of its own
            sta $100,x
            leax 1,x
            cmpx #COLOR0_TABLE+249  ; the rest of the table holds variables
            blo .all
            ldx #COLOR0_TABLE
            ldy #COLOR0_TABLE+255
            pshs u
            ldu #bz_band
            ldb #VIEW_ROW0-1
.band       lda ,u+
            sta b,x
            negb
            sta b,y
            negb
            decb
            cmpb #7
            bhs .band
            puls u
            ldb #VIEW_ROW0-2
            stb bz_line
            lda b,x
            sta bz_save
            lda #2
            sta bz_dirty
            ldb #1
            jsr st_bzoff
            bne .show
            clr VIDEO_CTRL      ; turned off in the settings: the table is not used, and the rails, if drawn, go
            clr BLIT_SOLID
            ldx #(VIEW_COL0-1)*256+VIEW_ROW0-1
            stx BLIT_DST
            ldx #256+VIEW_H+2
            stx BLIT_W
            lda #BC_SOLID+BC_DST256
            sta BLIT_CTRL
            ldx #(VIEW_COL0+VIEW_COLS)*256+VIEW_ROW0-1
            stx BLIT_DST
            sta BLIT_CTRL
            rts
.show       stb VIDEO_CTRL
            rts
bz_band
            fcb $F8,$FF,$FD,$FC,$FD,$FD,$FC,$FD,$FD,$FD,$FB,$FE,$FE,$FE,$FE,$FB
            fcb $FE,$FE,$FE,$FE,$FE,$FA,$FF,$FF,$FF,$FF,$FF,$FF,$F9,$FF,$FF,$FF
            fcb $FF,$FF,$FF,$FF,$F8,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$F0,$FF,$FF
            fcb $FF,$FF,$FF,$FF,$FF,$FF,$FF,$E8,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
            fcb $FF,$FF,$E0

; ---- text -----------------------------------------------------------------------------------------
sc_txt00    fcc "00"
            fcb 0
sc_txtlevel fcc "LEVEL "
            fcb 0
sc_txtcomp  fcc " COMPLETE"
            fcb 0
sc_txttime  fcc "TIME"
            fcb 0
sc_txtkills fcc "KILLS"
            fcb 0
sc_txtof    fcc "/"
            fcb 0
sc_txtnone  fcc "NO DEATHS"
            fcb 0
sc_txtdeath1 fcc " DEATH"
            fcb 0
sc_txtdeaths fcc " DEATHS"
            fcb 0
sc_txtgo    fcc "PRESS FIRE TO START"
            fcb 0
sc_txtgoex  fcc "FIRE TO START  JUMP TO EXIT"
            fcb 0
sc_txtenter fcc "ENTER INITIALS"
            fcb 0
sc_txtdots  fcc "..."
            fcb 0
sc_txtsg    fcc "STAR GUARD"
            fcb 0
sc_txtstory fcc "AT THE HEART OF THE STEAMING"
            fcb 10
            fcc "JUNGLES OF VENUS, WE HAVE COME"
            fcb 10
            fcc "UPON THE DEAD CITY. BENEATH ITS"
            fcb 10
            fcc "BROKEN TOWERS, IN THE DIMNESS"
            fcb 10
            fcc "OF ITS DEEPEST VAULT, THE"
            fcb 10
            fcc "WIZARD AWAITS US. IS THERE"
            fcb 10
            fcc "HOPE? NO MAN HAS ENTERED THE"
            fcb 10
            fcc "CATACOMBS AND LIVED."
            fcb 0
sc_txtb1    fcc "ZOMBOID   400"
            fcb 0
sc_txtb2    fcc "TROOPER   500"
            fcb 0
sc_txtb3    fcc "FLIER     600"
            fcb 0
sc_txtb4    fcc "JUMPER    600"
            fcb 0
sc_txtb5    fcc "THE DEEPEST RECESSES OF THE"
            fcb 10
            fcc "KEEP ARE SURE TO HIDE WORSE"
            fcb 10
            fcc "HORRORS"
            fcb 0
sc_txtwin   fcc "THE WIZARD HAS BEEN DEFEATED"
            fcb 0
sc_txtstar  fcc "STAR"
            fcb 0
sc_txtguard fcc "GUARD"
            fcb 0
sc_txtstart fcc "START"
            fcb 0
sc_txttrial fcc "TRIAL"
            fcb 0
sc_txtlocked fcc "TRIAL LOCKED"
            fcb 0
sc_txthead  fcc "SINGLE LEVEL TRIAL"
            fcb 0
sc_txtinc   fcc "INCOMPLETE"
            fcb 0
