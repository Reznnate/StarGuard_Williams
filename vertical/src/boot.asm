; The end of reset, moved out of the fixed bank, which is full. Runs once, with ROM in view.
reset_rest  ldx #hw_palette
            ldu #PALETTE
            ldb #16
.pal        lda ,x+
            sta ,u+
            decb
            bne .pal
            ldd #$A55A
            std <rng
            ldd #still_list
            std still_bhi
            ldd #still_list+STILL_BANNER*S_SIZE
            std still_rhi
            ldd #dl_a
            std <dl_new
            std <dl_newp
            addd #DL_ROOM*DL_SIZE
            std <dl_limit
            ldd #dl_b
            std <dl_old
            std <dl_oldend
            rts
