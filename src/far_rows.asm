; Turret rows that fire sideways are made while the camera is anywhere along their shots, not only near the row: else
; the shots already in flight (nt_gtc_prefill) appear in view all at once. gen_assets.py's far_rows, found through the
; level header's word at +24: object index, lowest and highest camera x, ended by $FFFF. The level bank is the home bank.
; Called by Spawner_Update. spawn_cursor is put back: the walk looks at a few objects a tick from there, and moving it
; every tick kept the walk from reaching the rest of the window (a checkpoint never appeared).
LVL_FAR     equ 24
far_rows    ldx <spawn_cursor
            pshs u,x
            ldu >LVL_FAR        ; U: spawn_one keeps it
.next       ldd ,u
            bmi .done
            std <spawn_cursor
            ldd <cam_x
            cmpd 2,u
            blo .skip
            cmpd 4,u
            bhi .skip
            jsr spawn_one       ; does nothing if the row is already made, or out of the camera's height
.skip       leau 6,u
            bra .next
.done       puls x,u
            stx <spawn_cursor
            rts
