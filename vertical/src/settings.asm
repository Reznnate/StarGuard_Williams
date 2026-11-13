; ---- advanced settings: the coin door's Advance --------------------------------------------------
; Bank 6, with the screens. Advance on the title or the attract screens opens it. Up and down, or Advance, pick a line;
; left and right, Start or High Score Reset change a button's line, and any of those or a player button does the others.
; The menu reads the buttons as wired, so a bad mapping cannot lock anyone out of it, and it marks each button held, for
; checking a harness: so a player button does not change a button's line.
; The settings live in the CMOS after the scores, a nibble a button: 0, or anything past ST_NONE, is that button's default.
; Then a nibble for the bezel: ST_OFF turns it off, anything else leaves it on.

CM_SET      equ CMOS+4+9*CM_LEVEL
ST_BUTTONS  equ 3
CM_BEZEL    equ CM_SET+ST_BUTTONS
CM_SET_END  equ CM_BEZEL+1
            assert CM_SET_END<=CMOS+$400,"the settings overflow the CMOS"
ST_FIRE     equ 1               ; what a button does
ST_JUMP     equ 2
ST_NONE     equ 3
ST_ON       equ 1               ; the bezel
ST_OFF      equ 2
ST_LINES    equ 7               ; the lines: the three buttons, then these
ST_BEZEL    equ 3
ST_RESET    equ 4
ST_DEFAULTS equ 5
ST_EXIT     equ 6
ST_X        equ 24              ; on the original's 192x108 screen, as S_Text takes them
ST_VX       equ 116
ST_HX       equ 158             ; the mark for a button held
ST_Y        equ 22
ST_STEP     equ 9               ; so that the last line is clear of the help below
ST_COLOR_HELD equ $33           ; green, both pixels

st_ln       equ ent_pool+240    ; st_line: the line
st_ly       equ ent_pool+241    ; and its y (word)
st_raw      equ ent_pool+243    ; the buttons and starts as wired, last tick
st_door     equ ent_pool+244    ; Advance and High Score Reset, last tick
st_ind      equ ent_pool+245    ; the buttons whose marks show
st_dy       equ ent_pool+246    ; this tick: -1 up a line, 1 down
st_chg      equ ent_pool+247    ; this tick: -1 or 1 from the stick, for a button's line
st_btn      equ ent_pool+248    ; this tick: a button, Start or High Score Reset went down
st_start    equ ent_pool+249    ; this tick: Start or High Score Reset went down

st_bits     fcb BTN_FIRE,BTN_JUMP,BTN_ALTJUMP  ; buttons 1, 2, 3 in PIA0_B
st_default  fcb ST_FIRE,ST_JUMP,ST_JUMP

; B=button, 0-2. Returns A=what it does, ST_FIRE to ST_NONE. Keeps B, Y, U.
st_get      ldx #CM_SET
            lda b,x
            anda #$0F
            beq .def
            cmpa #ST_NONE
            bls .ok
.def        ldx #st_default
            lda b,x
.ok         rts

; The masks Input_Read uses, from the CMOS. Cmos_Check calls this at power on. Keeps Y, U.
st_masks    clr map_fire
            clr map_jump
            ldb #ST_BUTTONS-1
.next       bsr st_get
            ldx #st_bits
            cmpa #ST_FIRE
            bne .nf
            lda b,x
            ora map_fire
            sta map_fire
            bra .on
.nf         cmpa #ST_JUMP
            bne .on
            lda b,x
            ora map_jump
            sta map_jump
.on         decb
            bpl .next
            rts

; Z set if the bezel is turned off. Keeps B, X, Y, U.
st_bzoff    lda CM_BEZEL
            anda #$0F
            cmpa #ST_OFF
            rts

; Z clear if Advance is down, and then the title opens the settings.
st_adv      lda PIA1_A
            anda #IN2_ADVANCE
            beq .no
            sta adv_req
.no         rts

; S_Tick for the title and the attract screens: Z clear if a button has just gone down, or Advance is down.
st_tick     jsr S_Tick
            bne .out
            bra st_adv
.out        rts

; A=the buttons and starts as wired.
st_raw_read lda PIA0_B
            anda #BTN_FIRE+BTN_JUMP+BTN_ALTJUMP+BTN_START1+BTN_START2
            rts

Settings_Screen
            jsr Screen_Begin
            jsr ti_palette
            clr sc_sel
            clr sc_mode         ; the line picked: 1 asks again, 2 has been done
            clr st_ind
            bsr st_raw_read     ; what is held as it opens is not a press
            sta st_raw
            lda PIA1_A
            anda #IN2_ADVANCE+IN2_HSRESET
            sta st_door
            lda <inp_ydir
            sta sc_lasty
            lda <inp_dir
            sta sc_lastx
            lda #COLOR_CYAN
            sta <draw_color
            ldx #53
            ldy #6
            ldu #st_txthead
            jsr S_Text
            clr <draw_color
            ldx #31
            ldy #88
            ldu #st_txthelp1
            jsr S_Text
            ldx #23
            ldy #97
            ldu #st_txthelp2
            jsr S_Text
            jsr st_all
.loop       jsr S_Tick
            jsr st_held
            clr st_dy
            clr st_chg
            clr st_btn
            clr st_start
            ; The stick, as it moves.
            lda <inp_ydir
            cmpa sc_lasty
            beq .ny
            sta sc_lasty
            sta st_dy
.ny         lda <inp_dir
            cmpa sc_lastx
            beq .nx
            sta sc_lastx
            sta st_chg
            ; The buttons, as they go down.
.nx         jsr st_raw_read
            ldb st_raw
            sta st_raw
            comb
            pshs b
            anda ,s+
            beq .nb
            inc st_btn
            bita #BTN_START1+BTN_START2
            beq .nb
            inc st_start
            ; The coin door, as its buttons go down.
.nb         lda PIA1_A
            anda #IN2_ADVANCE+IN2_HSRESET
            ldb st_door
            sta st_door
            comb
            pshs b
            anda ,s+
            bita #IN2_HSRESET
            beq .nh
            inc st_btn
            inc st_start
.nh         bita #IN2_ADVANCE
            beq .move
            lda #1
            sta st_dy
            ; Another line.
.move       lda st_dy
            beq .here
            ldb sc_sel
            pshs b
            adda sc_sel
            bpl .wrap
            lda #ST_LINES-1
.wrap       cmpa #ST_LINES
            blo .new
            clra
.new        sta sc_sel
            clr sc_mode
            puls a
            jsr st_line
            lda sc_sel
            jsr st_line
            lda #SND_GUI_01
            jsr Sound_Play
            lbra .loop
            ; This line.
.here       lda sc_sel
            cmpa #ST_BUTTONS
            bhs .action
            ldb st_chg
            bne .cycle
            tst st_start
            lbeq .loop
            ldb #1
.cycle      pshs b
            tfr a,b
            jsr st_get
            adda ,s+
            bne .low
            lda #ST_NONE
.low        cmpa #ST_NONE
            bls .set
            lda #ST_FIRE
.set        ldx #CM_SET
            sta b,x
            jsr st_masks
            lda sc_sel
            jsr st_line
            bra .ding
.action     cmpa #ST_BEZEL
            bne .act
            tst st_chg          ; the bezel: the stick or any button turns it on or off
            bne .bz
            tst st_btn
            lbeq .loop
.bz         ldb #ST_OFF
            jsr st_bzoff
            bne .bzset
            ldb #ST_ON
.bzset      stb CM_BEZEL
            jsr Bezel_On        ; shows it or hides it at once
            bra .redraw
.act        tst st_btn
            lbeq .loop
            cmpa #ST_EXIT
            beq .exit
            cmpa #ST_DEFAULTS
            beq .defaults
            ; The scores: the first press asks, the next clears them.
            tst sc_mode
            bne .reset
            inc sc_mode
            bra .redraw
.reset      ldx #CMOS+4
.clear      clr ,x+
            cmpx #CM_SET
            blo .clear
            lda #2
            sta sc_mode
            bra .redraw
.defaults   ldx #CM_SET
            ldb #CM_SET_END-CM_SET
.dclr       clr ,x+
            decb
            bne .dclr
            jsr st_masks
            jsr Bezel_On
            lda #2
            sta sc_mode
            jsr st_all
            bra .ding
.redraw     lda sc_sel
            jsr st_line
.ding       lda #SND_GUI_02
            jsr Sound_Play
            lbra .loop
.exit       lda #SND_GUI_02
            jsr Sound_Play
            clr adv_req
.wait       jsr S_Tick          ; Advance still down would open it again
            lda PIA1_A
            bita #IN2_ADVANCE
            bne .wait
            rts

; Every line.
st_all      clra
.next       pshs a
            bsr st_line
            puls a
            inca
            cmpa #ST_LINES
            blo .next
            rts

; A=line: erased and drawn again, yellow if it is the one picked.
st_line     sta st_ln
            ldb #ST_STEP
            mul
            addd #ST_Y
            std st_ly
            tfr d,y
            ldx #ST_X
            lda #ST_HX-ST_X-4
            ldb #7
            jsr S_Erase
            clr <draw_color
            lda st_ln
            cmpa sc_sel
            bne .label
            lda #COLOR_YELLOW
            sta <draw_color
.label      lda st_ln
            asla
            ldx #st_labels
            ldu a,x
            ldx #ST_X
            ldy st_ly
            jsr S_Text
            lda st_ln
            cmpa #ST_BUTTONS
            bhs .bezel
            tfr a,b
            jsr st_get
            deca
            asla
            ldx #st_funcs
            ldu a,x
            bra .value
.bezel      cmpa #ST_BEZEL
            bne .act
            ldu #st_txton
            jsr st_bzoff
            bne .value
            ldu #st_txtoff
            bra .value
.act        cmpa sc_sel
            bne .out
            ldb sc_mode
            beq .out
            ldu #st_txtdone
            cmpb #2
            beq .value
            ldu #st_txtsure
.value      ldx #ST_VX
            ldy st_ly
            jsr S_Text
.out        clr <draw_color
            rts

; A mark beside each button held, as wired.
st_held     jsr st_raw_read
            anda #BTN_FIRE+BTN_JUMP+BTN_ALTJUMP
            cmpa st_ind
            beq .same
            sta st_ind
            clrb
.each       pshs b
            ldx #st_bits
            lda b,x
            ldb #ST_COLOR_HELD
            bita st_ind
            bne .on
            clrb
.on         stb sc_col
            lda ,s
            ldb #ST_STEP
            mul
            addd #ST_Y
            tfr d,y
            ldx #ST_HX
            lda #6
            ldb #6
            jsr S_Fill
            puls b
            incb
            cmpb #ST_BUTTONS
            blo .each
.same       rts

st_labels   fdb st_txtb1,st_txtb2,st_txtb3,st_txtbezel,st_txtreset,st_txtdef,st_txtexit
st_funcs    fdb st_txtfire,st_txtjump,st_txtnone
st_txthead  fcc "ADVANCED SETTINGS"
            fcb 0
st_txthelp1 fcc "UP/DOWN OR ADVANCE TO PICK"
            fcb 0
st_txthelp2 fcc "START OR LEFT/RIGHT TO CHANGE"
            fcb 0
st_txtb1    fcc "BUTTON 1"
            fcb 0
st_txtb2    fcc "BUTTON 2"
            fcb 0
st_txtb3    fcc "BUTTON 3"
            fcb 0
st_txtbezel fcc "BEZEL"
            fcb 0
st_txtreset fcc "RESET HIGH SCORES"
            fcb 0
st_txtdef   fcc "RESTORE DEFAULTS"
            fcb 0
st_txtexit  fcc "EXIT"
            fcb 0
st_txtfire  fcc "FIRE"
            fcb 0
st_txtjump  fcc "JUMP"
            fcb 0
st_txtnone  fcc "NONE"
            fcb 0
st_txton    fcc "ON"
            fcb 0
st_txtoff   fcc "OFF"
            fcb 0
st_txtsure  fcc "SURE?"
            fcb 0
st_txtdone  fcc "DONE"
            fcb 0
