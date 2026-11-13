; D=a signed 8.8 step, with N set from A, as a load or a rola leaves it. Adds it to the 16.8 number at off,u. Keeps X and Y.
ADD_8_8U    macro off
            bmi .n\@
            addd \off+1,u
            std \off+1,u
            bcc .d\@
            inc \off,u
            bra .d\@
.n\@        addd \off+1,u
            std \off+1,u
            bcs .d\@
            dec \off,u
.d\@
            endm

; Ent_UpdateAll still calls an entity deactivated since its last update. A handler opens with this, so a mine set off
; between ticks does not blast twice. Uses A.
NT_LIVE     macro
            lda E_FLAGS,u
            bita #EF_ACTIVE
            bne .l\@
            rts
.l\@
            endm

; RAM layout. Direct page is $98: anything used often belongs in this first page.
TICK_FRAMES equ 2

            org $9800
            setdp $98
; --- engine ---
frames      rmb 2           ; COUNT240 interrupts
vphase      rmb 1           ; frames since the last tick
now         rmb 2           ; game time in ticks
late_ticks  rmb 2           ; ticks that ran over budget
tick_spare  rmb 2           ; idle passes left in the last tick (one is 14 cycles)
cur_bank    rmb 1           ; bank that 0000-3FFF should show
level_bank  rmb 1
rng         rmb 2
snd_pending rmb 1           ; sound command to send next tick, 0 = none
draw_color  rmb 1
; --- input, sampled once a tick ---
inp_dir     rmb 1           ; -1, 0, 1
inp_ydir    rmb 1           ; -1, 0, 1
inp_buttons rmb 1           ; BTN_* bits, with button 3 folded into jump
inp_pressed rmb 1           ; buttons that went down this tick
; --- camera ---
cam_x       rmb 2           ; center of the view, always even
cam_y       rmb 2
cam_left    rmb 2           ; world x of the left visible pixel, always even
cam_top     rmb 2
dl_limit    rmb 2           ; end of the display list being built
tgt_skip    rmb 1
view_y      rmb 2           ; center of the view vertically. Follows cam_y with a dead zone
target_m    rmb 1           ; targets above target_mid
still_mode  rmb 1           ; nonzero: sprites go to the still layer instead of the display list
spr_ox      rmb 2           ; cam_left, less the hidden pixels at the left of the video line
spr_oy      rmb 2           ; cam_top, less the hidden lines and the room for a sprite above them
cam_col     rmb 2           ; cam_left / 2
old_left    rmb 2           ; camera that the terrain on screen was drawn with
old_top     rmb 2
old_col     rmb 2
terrain_on  rmb 1           ; 0 = nothing on screen yet
terrain_dirty rmb 1         ; nonzero = redraw the terrain in view
repair_left rmb 1
repair_rect rmb 2           ; round-robin position of the terrain repair, as an offset into the rects
camm_x      rmb 3           ; man camera x, 16.8
camm_y      rmb 2           ; man camera y
cam_nudge   rmb 2           ; look-ahead, signed 8.8
cam_target_y rmb 2
cam_lock    rmb 1
; --- level ---
lvl_w       rmb 2
lvl_h       rmb 2
lvl_grid    rmb 2
lvl_index   rmb 2
lvl_rects   rmb 2
lvl_objects rmb 2
lvl_objcount rmb 2
cls_stride  rmb 1           ; bytes per row of the cell class map
grid_stride rmb 1           ; bytes per row of the ROM grid
; --- display list ---
dl_new      rmb 2           ; list being built
dl_old      rmb 2           ; list on screen
dl_newp     rmb 2           ; next free entry
dl_oldend   rmb 2
dl_dropped  rmb 2
; --- scratch for the draw and collision code ---
t0          rmb 2
t1          rmb 2
t2          rmb 2
t3          rmb 2
t4          rmb 2
t5          rmb 2
; --- man ---
man_x       rmb 3           ; 16.8
man_y       rmb 3
man_vx      rmb 2           ; 8.8 per tick
man_vy      rmb 2
man_flags   rmb 1           ; MF_* bits
man_heading rmb 1           ; 1 or -1
man_jump_y  rmb 2           ; jumpStartHeight
man_sprite  rmb 2
man_run_t   rmb 2           ; 8.8 animation position
man_fire_t  rmb 2           ; time of last shot
man_unh_t   rmb 2           ; unholsterTime
man_spawn_t rmb 2
man_ledge_t rmb 2
man_jkey_t  rmb 2
man_ground  rmb 1           ; touched ground this tick
spawn_x     rmb 2           ; respawn cell
spawn_y     rmb 1
spawn_h     rmb 1
deaths      rmb 2
game_flags  rmb 1
class_map   rmb 2           ; start of the 2-bit cell class map
lvl_index_max rmb 2
cam_fixed   rmb 1
cam_fixed_x rmb 2
cam_fixed_y rmb 2
death_cam   rmb 1
level_done  rmb 1
man_lock    rmb 1           ; lockControls
man_dir     rmb 1
man_frame   rmb 1
man_rise    rmb 2
man_base_x  rmb 2
man_cell_x  rmb 2
man_cell_y  rmb 1
man_cell_t  rmb 1
man_rows    rmb 1
man_cols    rmb 1
man_rx      rmb 2
man_ry      rmb 2
man_dl      rmb 2
man_dr      rmb 2
man_dt      rmb 2
man_du      rmb 2
man_best    rmb 2
man_side    rmb 1
man_sign    rmb 1
; --- terrain scrolling ---
scroll_k    rmb 2
scroll_lo   rmb 2
flat_row    rmb 1
flat_oa     rmb 2           ; old span
flat_ob     rmb 2
flat_na     rmb 2           ; new span
flat_nb     rmb 2
; --- game ---
game_level  rmb 1
die_type    rmb 1
level_start_t rmb 2
death_from_x rmb 2
death_from_y rmb 2
; --- services ---
kill_total  rmb 2
crystals    rmb 1
; --- pools ---
target_n    rmb 1
block_buried rmb 1
block_y     rmb 1
block_x     rmb 2
cell_raw    rmb 1           ; ROM type from the last class 3 cell read
ent_count   rmb 1
ent_last    rmb 2
spawn_lo    rmb 2           ; object window for the spawner
spawn_hi    rmb 2
spawn_cell  rmb 2
fc_d        rmb 2           ; far call scratch
fc_x        rmb 2
fc_t        rmb 2
fc_s        rmb 2
fc_sb       rmb 1
fc_sp       rmb 1
ent_left    rmb 1
laser_left  rmb 1
hit_left    rmb 1
spawn_left  rmb 1
spawn_cursor rmb 2
hit_x       rmb 2           ; arguments of Entity_HitEffect
hit_y       rmb 2
hurt_damage rmb 2           ; arguments of Entity_Hurt
hurt_laser  rmb 2
arg0        rmb 2           ; extra constructor argument
arg1        rmb 2
firing_allowed rmb 1
kills       rmb 2
level_score rmb 2
            if VERT
vert_xm     rmb 2           ; the level's height in pixels: the game's y is drawn at column vert_xm - 1 - y
gcam_left   rmb 2           ; the game's view, left and top; cam_left and cam_top are the renderer's
gcam_top    rmb 2
vk          rmb 2           ; Draw_Sprite's column for the game's y: vert_xm - VROT_W + 1 - spr_ox
            else
gcam_left   equ cam_left
gcam_top    equ cam_top
            endif
dp_end      equ *
            assert dp_end<=$9900,"direct page overflow"

MF_ACTIVE   equ $01
MF_INVULN   equ $02
MF_FREEFALL equ $04
MF_HOLSTER  equ $08
MF_DESCEND  equ $10
MF_FIREOK   equ $20         ; fire key has been released
MF_NOJUMP   equ $40         ; disableJumpKey
MF_JKEYDOWN equ $80         ; jumpKeyAlreadyPressed

DL_ENTRIES  equ 64
DL_SIZE     equ 8

            org $9900
dl_a        rmb DL_ENTRIES*DL_SIZE
dl_b        rmb DL_ENTRIES*DL_SIZE
; The still layer: images that do not change, kept apart from the display list so a tick with a still camera spends
; nothing on them. An entry: src(2) w(1) h(1) ctrl(1) solid(1) col(2) row(2) state(1), with col and row in the view,
; 16 bits, so an image can wait out of view. The state's high nibble is the owning banner slot, or 0.
S_SRC       equ 0
S_W         equ 2
S_CTRL      equ 4
S_SOLID     equ 5
S_COL       equ 6
S_ROW       equ 8
S_STATE     equ 10
S_SIZE      equ 11
STILL_MAX   equ 80
STILL_BANNER equ 28        ; slots below this are for banners, in text order; the rest are for remains. No level's
                            ; banners have used more than 19; a set that does not fit is drawn a letter at a time
SS_LIVE     equ 1           ; in use
SS_SHOWN    equ 2           ; on screen now, at col and row
SS_NEW      equ 4           ; not placed yet
SS_DIE      equ 8           ; to be erased and freed
SS_TERR     equ $40         ; remains only: its box crosses a cell's edge, so it may be over terrain
SS_CUR      equ $80         ; remains only: its col has every move of the view so far. If not, rem_acc holds those it lacks
still_owner rmb 1           ; owner nibble for new still entries
still_full  rmb 1           ; a sprite did not fit
still_work  rmb 1           ; entries wait to be placed or erased
still_used  rmb 1
still_last  rmb 2           ; the entry just added
still_heal  rmb 2           ; next entry for the repair pass
still_dc    rmb 2           ; columns and lines the images move this tick
still_dr    rmb 2
still_any   rmb 1
ban_used    rmb 1           ; bit per banner slot
; Blit queue for a camera move: terrain blits wait here, by screen half, until the beam is in the other half.
em_dst      rmb 2           ; the blit being emitted
em_wh       rmb 2
em_cs       rmb 2           ; control, solid
em_kind     rmb 1           ; 0 = erase, 1 = draw
queue_on    rmb 1
qa_e        rmb 2           ; upper half: erases grow up from q_base, draws grow down from q_mid
qa_d        rmb 2
qb_e        rmb 2           ; lower half: the same from q_mid and q_end
qb_d        rmb 2
q_base      rmb 2
q_mid       rmb 2
q_end       rmb 2
q_nowait    rmb 1           ; the tick is already late: do not wait for the beam
still_band  rmb 1           ; 0 = every entry, 1 = upper half, 2 = lower half
wiz_live    rmb 1           ; the boss exists, so its RAM cannot hold the queue
still_bhi   rmb 2           ; end of the banner slots in use, so that walks skip the empty rest
still_rhi   rmb 2           ; the same for the other slots
still_rem   rmb 1           ; remains slots in use
; The terrain list: see tl_ in engine.asm.
tl_valid    rmb 1
tl_mode     rmb 1           ; this tick's terrain goes through the list
tl_wait     rmb 1           ; camera moves before trying again after the list did not fit
tl_lo       rmb 1           ; buckets the list holds
tl_hi       rmb 1
tla_t       rmb 2           ; upper half: end of the walls, growing up
tla_k       rmb 2           ; and start of the blocks, growing down
tlb_t       rmb 2           ; lower half the same
tlb_k       rmb 2
tl_r      rmb 1           ; the entry being added
tl_ht        rmb 1
tl_stop      rmb 2
ent_hi      rmb 2           ; end of the entity slots in use, roughly: a loop need not look further
laser_hi    rmb 2           ; end of the laser slots in use, roughly
cell_anychg rmb 1           ; a cell the grid says cannot change has changed: every read must look at the bits
ban_bank    rmb 1           ; the bank holding this level's word images
word_row    rmb 6           ; a word's image, in the form of a sprite table entry
ent_ask_at  rmb 2           ; the next entity to be asked how far it is from the view
fx_free     rmb 2           ; every effect slot below this is taken
fx_hi       rmb 2           ; the same for effects
still_scan  rmb 2           ; where still_add looks for a free slot, and where it stops
still_end   rmb 2
still_list  rmb STILL_MAX*S_SIZE
; What a retained banner needs each tick besides its glyphs: the glyph loop's results.
BAN_SLOTS   equ 4
ban_slot_data rmb BAN_SLOTS*12
; Variables that are not used often enough for the direct page.
            if VERT
vgx         rmb 2           ; Draw_Sprite: the game's x, for the line
rem_accr    rmb 2           ; lines the view has moved since the lists of remains were made (still_lines), as rem_acc for columns
rem_half    rmb 1           ; a step along the lines may have carried remains across the middle: the lists' halves are stale
vb_left     rmb 1           ; a banner's word: lines of its image still to place, in pieces of VB_PIECE
vb_first    rmb 2           ; its first piece's entry in the still layer
ban_fresh_e rmb 2           ; the last piece of the word in ban_fresh
wq_o        rmb 2           ; p2_put: the image's place in its turned canvas, column and line
; The boss's worm has a list of its own: the display list's last entry is its header, and its images' entries go down from
; there (wizard_p2draw.asm, and wm_half in vfast.asm). Nothing else may use that entry, so the list holds one fewer.
WM_MAX      equ 15          ; its images: the head's 3 and P2_MAX_SEGS segments
DL_WM_N     equ DL_ENTRIES*DL_SIZE-1 ; from a list's start: how many of the worm's images it has
DL_WM_AT    equ DL_ENTRIES*DL_SIZE-3 ; and where in the list the worm belongs: what follows is drawn over it
DL_ROOM     equ DL_ENTRIES-1
            else
DL_ROOM     equ DL_ENTRIES
            endif
prof        rmb 16          ; raster position at each phase of the tick: pairs of (frames into the tick, line / 4)
level_bonus rmb 2
level_kills_u rmb 2
text_x      rmb 2
text_x0     rmb 2
text_y      rmb 2
num_val     rmb 2
num_pow     rmb 2
num_digit   rmb 1
num_started rmb 1
rect_type   rmb 1
rect_x      rmb 2
rect_y      rmb 1
rect_cx     rmb 2
rect_rows   rmb 1
rect_cols   rmb 1
pit_depth   rmb 1
pit_x       rmb 2
pit_y       rmb 1
pit_off     rmb 1
OBJ_BITS    equ 40          ; bytes per array: room for 320 objects
obj_spawned rmb OBJ_BITS
obj_dead    rmb OBJ_BITS

; Things lasers can hit, rebuilt each tick so a laser need not scan the whole pool.
; Aliens fill downward from the middle and the rest upward from it, so the list is contiguous: lasers aimed at allies
; start at the middle, and those aimed at aliens start at the last alien.
TARGET_ALIENS equ 28
TARGET_OTHERS equ 12
; An entry: the entity (2), then x and y (1 each) relative to tgt_cam_x and tgt_cam_y, in units of 2 pixels, plus 128.
TARGET_SIZE equ 4
target_list rmb TARGET_ALIENS*TARGET_SIZE
target_mid  rmb TARGET_OTHERS*TARGET_SIZE
tgt_cam_x   rmb 2
tgt_cam_y   rmb 2
hit_d       rmb 1

; The terrain the boss changes (boss_terrain.asm), at the bottom of space whose top is the remains' lists (rem_a).
REG_MAX     equ 24          ; regions a level can have: gen_assets.py holds level 9 to it
reg_ram     rmb 288
reg_look    equ reg_ram             ; per region: its look now, 0 = the level's own
reg_dirty   equ reg_ram+REG_MAX     ; per region: cells near it have been set since its look was worked out
reg_any     equ reg_ram+2*REG_MAX   ; some region is marked
lvl_regions equ reg_ram+2*REG_MAX+1 ; word: the level's region table, 0 if it has none
reg_box     equ reg_ram+2*REG_MAX+3 ; first column, first line, end column, end line on screen of what was drawn again
REG_BYTES   equ 2*REG_MAX+7

; Entity record. Bytes from E_DATA up belong to the class.
E_VT        equ 0           ; class descriptor; 0 = free slot
E_BANK      equ 2           ; bank of the class code; 0 = fixed ROM
E_KIND      equ 3
E_FLAGS     equ 4
E_X         equ 5
E_Y         equ 7
E_SPRITE    equ 9
E_SIZEX     equ 11
E_SIZEY     equ 12
E_SCORE     equ 13
E_HEALTH    equ 14
E_FLASHT    equ 16          ; low byte of the clock
E_WAIT      equ 17          ; ticks it has nothing to do: its update does not run, nor anything else but the count. See Ent_UpdateAll
E_START     equ 18
E_OBJ       equ 20          ; index in the level's object list, or $FFFF
E_DATA      equ 22
ENT_SIZE    equ 48
KIND_ENTITY equ 0
KIND_ALIEN  equ 1
KIND_ALLY   equ 2
KIND_NEUTRAL equ 3
E_STILL     equ 46          ; its entry in the still layer, when EF_STILL is set
EF_ACTIVE   equ 1
EF_SOLID    equ 2
EF_FLASHING equ 4
EF_STILL    equ 16          ; has, or may have, an image in the still layer
EF_ASLEEP   equ 32          ; well out of view: not updated or drawn until the camera comes near
EF_KEEP     equ 8           ; never despawned for being far away, and stays awake unless EF_NAP is set too
EF_OFF      equ 128         ; out of sight, though near: it runs one tick in four
EF_NAP      equ 64          ; with EF_KEEP: it may sleep when far away, since it has nothing to do there
V_UPDATE    equ 0           ; class descriptor slots
V_HURT      equ 2
V_DIE       equ 4
V_DEATH     equ 6
V_HIT       equ 8
ALIEN_FLASH_T equ 3         ; ticks, int(5 / 60 * 1000) ms

; Laser record.
L_VT        equ 0           ; two words: update, draw (0 = base); 0 = free slot
L_X         equ 2           ; 16.8
L_Y         equ 5           ; 16.8
L_VX        equ 8           ; signed 8.8 per tick
L_VY        equ 10
L_FLAGS     equ 12
L_TARGET    equ 13
L_DAMAGE    equ 14
L_DEATH     equ 15
L_SIZEX     equ 16
L_SIZEY     equ 17
L_START     equ 18
L_SPRITE    equ 20
L_DATA      equ 22
LM_COL      equ L_DATA+5    ; the cell Laser_CellHere last read: the low byte of its first column and of its first line
LM_ROW      equ L_DATA+6
LM_TYPE     equ L_DATA+7
LASER_SIZE  equ 30
LASER_COUNT equ 20
LF_ACTIVE   equ 1
LF_HITWALL  equ 2
LF_CANCEL   equ 4
LF_CANCELLED equ 8          ; ended by the man's death; a class's update can tell
ALLIES      equ 0
ALIENS      equ 1
BOTH        equ 2

laser_pool  rmb LASER_SIZE*LASER_COUNT

; Effect record.
FX_UPDATE   equ 0           ; handler; 0 = free slot
FX_X        equ 2           ; 16.8
FX_Y        equ 5           ; 16.8
FX_TIMER    equ 8           ; 16 bits
FX_DATA     equ 10
EFFECT_SIZE equ 24
EFFECT_COUNT equ 40

effect_pool rmb EFFECT_SIZE*EFFECT_COUNT
ban_fresh   rmb 2           ; the word that finished typing this tick
tlo_a       rmb 2           ; end of the other rects in the upper half
tlo_b       rmb 2           ; start of those in the lower half
tlf_a       rmb 2           ; end of the upper half's floors, growing up
tlf_b       rmb 2           ; start of the lower half's, growing down
tl_cut      rmb 1
            if VERT
; The list of rects near the view has these two of the terrain list's own, which are idle while it is the valid one: the two
; lists share their RAM, and building either marks the other invalid. No RAM is added for them, since that would move the
; pools, and what an effect does on a tick depends on its address (FxBit_Update looks for ground by slot).
vl_fcol     equ tlo_a       ; the view's column that the flats near the view have their columns worked out for (vl_fcache)
vl_nlong    equ tl_cut      ; how many of them vl_trail has a strip to erase for
            endif
tl_wv       rmb 1
blk_p       rmb 2           ; end of the queued blocks
blk_fg      rmb 1
blk_half    rmb 1
vl_valid    rmb 1           ; the list of rects near the view can be used
vl_hold     rmb 1           ; sideways camera steps left that use it
vl_any      rmb 1           ; this step takes the long way round
vl_dy       rmb 2           ; lines the camera moved
vl_w        rmb 2           ; end of the walls
vl_f        rmb 2           ; start of the floors and the rest
vl_b        rmb 2           ; end of the blocks
vl_c0       rmb 2           ; the columns and lines the list covers
vl_c1       rmb 2
vl_r0       rmb 2
vl_r1       rmb 2
snd_line    rmb 1           ; a sound command is on the line
snd_cmd     rmb 1           ; the last command accepted
snd_pri     rmb 1           ; its priority
snd_until   rmb 2           ; the frame until which it is protected
; The terrain list's upper half. Its lower half has the RAM the boss will want, so once a boss appears the list keeps to this.
TL_A_BYTES  equ 656
tl_ram      rmb TL_A_BYTES
; The entity pool takes what the level's changed bits leave free, up to ENT_MAX: 40 on the tallest level, 48 on most.
ENT_MAX     equ 48
ent_pool    equ *
ram_pools   equ *
; Changed cells: 1 bit per cell, ending at $BAFF.
CLASS_END   equ $BB00
wiz_ram     equ $BD00       ; 512 bytes, for the boss
tl_rooms    equ $BEFC       ; the terrain list's rooms: tl_rooms_lvl, or tl_rooms_boss once a boss exists (after Q_SMALL)
tl_k        equ $BEFE       ; tl_insert1: the rect's flags, less RECT_HIDE
; The settings' button masks (settings.asm): which PIA0_B buttons fire, and which jump. Kept past a reset; Cmos_Check sets them.
map_fire    equ $BF3E
map_jump    equ $BF3F
; In the stack's spare margin above the entities' statics at $BF00. Reset does not clear these. TL_Level clears heal_n.
HEAL_MAX    equ 4
hole_rect   equ $BF40       ; a block's rect, made up for the terrain routines
heal_n      equ $BF48
heal_list   equ $BF49       ; HEAL_MAX of column, line: up to $BF58
blk_kills   equ $BF59       ; a block on this level has been destroyed
vl_stop     equ $BF5A       ; end of the walk that builds the near list
blk_tmp     equ $BF70       ; one block of a group, as a rect
blk_fn      equ $BF78
blk_cx      equ $BF7A
blk_cy      equ $BF7C
blk_x0      equ $BF7E
blk_nx      equ $BF80
blk_ny      equ $BF81
blk_nw      equ $BF82
blk_nh      equ $BF83
blk_alive   equ $BF84
spawn_k1    equ $BF85       ; which cells the edges of the camera's height band are in
spawn_k2    equ $BF86
mc_row      equ $BF87       ; the man's collision: the low byte of the row's first line
mc_col0     equ $BF88
mc_col      equ $BF89
BEAM_TOP_MAX equ 8
beam_n      equ $BF9E       ; beam turrets to show over their beams this tick
beam_list   equ $BF9F       ; BEAM_TOP_MAX of them: to $BFAE
spawn_new   equ $BFB4       ; an object that has just come into the window, or $FFFF
spawn_new2  equ $BFB6
gov_load    equ $BFB0       ; the load governor: 0 to 3. Late ticks raise it at once, a run of on-time ticks lowers it
gov_calm    equ $BFB1       ; on-time ticks since it last changed
gov_mask    equ $BFB2       ; debris looks for ground when its slot and the clock agree in these bits
gov_bit     equ $BFB3       ; counts debris asked for, so that under load every other one is not made
cell_gen    equ $BFAF       ; counts changes to cells: an answer kept from before a change may be out of date
mc_hit      equ $BF9D       ; a touch this pass, which can have moved the man
mc_cells    equ $BF8A       ; 4 of cell x (2), cell y, type: to $BF99
tgt_new     equ $BF9B       ; an entity has been made since the list of targets
spawn_want  equ $BF9C       ; a constructor found no room
rem_dirty   equ $BF9A       ; the lists of remains need making again
rem_a       equ reg_ram+288-2*(STILL_MAX-STILL_BANNER+1)*2
            assert REG_BYTES+3<=rem_a-reg_ram,"the regions meet the remains" ; +3: entities.asm's PK_FLASH, PK_FNEXT
rem_b       equ rem_a+(STILL_MAX-STILL_BANNER+1)*2
tl_fs       equ $BF67       ; the color of the solid rect being moved
tl_rep      equ $BF68       ; this step, solid rects are painted whole, not just their ends
tl_step     equ $BF69       ; counts camera steps
rem_acc     equ $BF6C       ; columns the view has moved since the lists of remains were made
; The color table and line flags have lines no one sees, past the light's last at line 248: $BBF9-$BBFF, $BCF9-$BCFF. What is here is safe from the stack,
; which goes well below $BFC0.
vl_wa       equ $BBF9       ; the walls in view, in the list of rects near the view
vl_wz       equ $BBFB
vl_wcol     equ $BBFD       ; the column of the view they were found for
bz_line     equ $BCF9       ; the bezel: the line its light is on
bz_save     equ $BCFA       ; what that line was
bz_dirty    equ $BCFB       ; ticks left to redraw its rails, which black covers can nick
            if VERT
; The vertical build's bezel is pixels (vbezel.asm), so the line flags go unused: some of its variables are there.
vbz_clo     equ LINE_FLAGS  ; the lines black covers have reached this tick: band 0 may be nicked there
vbz_chi     equ LINE_FLAGS+1    ; one past the last
vbz_plo     equ LINE_FLAGS+2    ; and last tick, whose covers are erased this tick
vbz_phi     equ LINE_FLAGS+3
vbz_l0      equ LINE_FLAGS+4    ; vbz_px's first line, and how many
vbz_ln      equ LINE_FLAGS+5
            endif
gov_free    equ $BCFC       ; a bolt turret or a turret row is firing: its shots are part of a beat, and the governor leaves them alone
trial_on    equ $BCFD       ; playing one level from the scores
trial_new   equ $BCFE       ; the level with a record just set, for the scores to show
adv_req     equ $BBFF       ; Advance was pressed: the title opens the settings
dl_gen      equ $BCFF       ; counts display list swaps: an entry kept from the list before last is out of date
lv_exit     equ $BF6E       ; leave for the title: jump at the end of a level, or 1-up held
up_held     equ $BF6F       ; ticks 1-up has been held in a level
edge_c      equ $BFB8       ; an image crossing the window's edge. See edge_rects.
edge_r      equ $BFB9
edge_w      equ $BFBA
edge_h      equ $BFBB
edge_mw     equ $BFBC
edge_mh     equ $BFBD
edge_fn     equ $BFBE
tl_rect     equ $BF6A       ; a rectangle was drawn this tick
tl_rectw    equ $BF6B       ; ticks left that its erasing can still reach
spawn_ev    equ $BF5C       ; something has changed that the spawner should look at
spawn_look  equ $BF5D       ; objects left to look at
spawn_mv    equ $BF5E       ; the window moved on its last step
spawn_pcx   equ $BF5F       ; the camera, as the spawner last saw it
spawn_pcy   equ $BF61
spawn_clo   equ $BF63       ; the cells of the window's edges
spawn_chi   equ $BF65
