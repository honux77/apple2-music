;-----------------------------------------------------------------------------
; Apple II Mockingboard Music Player
; Plays .a2m format music files
;-----------------------------------------------------------------------------

.export main

.import mb_init, mb_reset, mb_write, mb_silence, mb_set_slot

;-----------------------------------------------------------------------------
; A2M Format Constants
;-----------------------------------------------------------------------------
A2M_END      = $FE              ; End of song marker
A2M_LOOP     = $FD              ; Loop start marker
A2M_WAIT_EXT = $FF              ; Extended wait (followed by 2-byte count)

;-----------------------------------------------------------------------------
; Apple II System Addresses
;-----------------------------------------------------------------------------
KEYBOARD     = $C000            ; Keyboard data
KEYSTROBE    = $C010            ; Keyboard strobe (clear)
COUT         = $FDED            ; Character output
CROUT        = $FD8E            ; Carriage return
HOME         = $FC58            ; Clear screen

; Slot number stored at $0300 (written by auto-detect for menu display)
SLOT_ADDR    = $0300

;-----------------------------------------------------------------------------
; Zero Page Variables
;-----------------------------------------------------------------------------
.segment "ZEROPAGE"

data_ptr:   .res 2              ; Pointer to current position in music data
loop_ptr:   .res 2              ; Pointer to loop start position
wait_count: .res 2              ; Frames to wait (16-bit)
temp:       .res 1              ; Temporary storage
vol_a:      .res 1              ; Channel A volume (0-15)
vol_b:      .res 1              ; Channel B volume (0-15)
vol_c:      .res 1              ; Channel C volume (0-15)
bar_ptr:    .res 2              ; Pointer to screen line for bar drawing

;-----------------------------------------------------------------------------
; BSS segment (uninitialized data)
;-----------------------------------------------------------------------------
.segment "BSS"
zp_save:    .res 32             ; Buffer to save/restore DOS zero page $80-$9F

;-----------------------------------------------------------------------------
; Main Code
;-----------------------------------------------------------------------------
.segment "CODE"

;-----------------------------------------------------------------------------
; Entry point
;-----------------------------------------------------------------------------
.proc main
        jsr     save_zp         ; Save DOS zero page state ($80-$9F)
        jsr     HOME            ; Clear screen
        jsr     show_title

        ; Use Mockingboard in slot 4 (fixed)
        ldx     #4
        stx     SLOT_ADDR       ; Store slot for menu display
        jsr     mb_set_slot     ; Set VIA base addresses for slot 4
        jsr     mb_init         ; Initialize Mockingboard

        jsr     show_playing    ; Show "Playing..." message

        ; Set up data pointer to music data
        lda     #<music_data
        sta     data_ptr
        lda     #>music_data
        sta     data_ptr+1

        ; Clear loop pointer
        lda     #$00
        sta     loop_ptr
        sta     loop_ptr+1

        ; Clear volume trackers
        sta     vol_a
        sta     vol_b
        sta     vol_c

        ; Skip A2M header (16 bytes)
        clc
        lda     data_ptr
        adc     #16
        sta     data_ptr
        lda     data_ptr+1
        adc     #0
        sta     data_ptr+1

        ; Main playback loop
@play_loop:
        jsr     play_frame      ; Process one frame of music data
        bcs     @done           ; Carry set = end of song

        jsr     wait_frame      ; Wait for next frame (60Hz timing)
        jsr     show_visualizer ; Update volume display

        ; Check for keypress to exit
        lda     KEYBOARD
        bpl     @play_loop      ; No key pressed, continue
        sta     KEYSTROBE       ; Clear keyboard strobe

        ; ESC key ($9B) exits
        cmp     #$9B
        bne     @play_loop

@done:
        jsr     mb_silence      ; Silence the Mockingboard
        jsr     restore_zp      ; Restore DOS zero page state
        jsr     dos_run_menu    ; Run HELLO via DOS command
        jmp     $03D0           ; Fallback: return to BASIC ]
.endproc

;-----------------------------------------------------------------------------
; show_title - Display title screen
;-----------------------------------------------------------------------------
.proc show_title
        ldy     #0
@loop:
        lda     msg_title,y
        beq     @done
        ora     #$80            ; Set high bit for Apple II
        jsr     COUT
        iny
        bne     @loop
@done:
        jsr     CROUT
        jsr     CROUT
        rts
.endproc

;-----------------------------------------------------------------------------
; show_not_found - Display Mockingboard not found error
;-----------------------------------------------------------------------------
.proc show_not_found
        jsr     CROUT
        ldy     #0
@loop:
        lda     msg_not_found,y
        beq     @done
        ora     #$80
        jsr     COUT
        iny
        bne     @loop
@done:
        jsr     CROUT
        ; Wait for keypress before returning to menu
        lda     KEYSTROBE       ; Clear any pending key
@wait:
        lda     KEYBOARD
        bpl     @wait
        sta     KEYSTROBE
        rts
.endproc

;-----------------------------------------------------------------------------
; show_playing - Display "Playing..." message
;-----------------------------------------------------------------------------
.proc show_playing
        jsr     CROUT
        ldy     #0
@loop:
        lda     msg_playing,y
        beq     @done
        ora     #$80
        jsr     COUT
        iny
        bne     @loop
@done:
        jsr     CROUT
        rts
.endproc


;-----------------------------------------------------------------------------
; show_visualizer - Display simple volume bars for 3 channels
; Uses direct screen memory writes for speed
;-----------------------------------------------------------------------------
SCREEN_LINE6  = $0700            ; Line 6 of text screen (Channel A)
SCREEN_LINE8  = $0428            ; Line 8 of text screen (Channel B)
SCREEN_LINE10 = $0528            ; Line 10 of text screen (Channel C)

.proc show_visualizer
        ; Channel A bar - line 6
        lda     #<SCREEN_LINE6
        sta     bar_ptr
        lda     #>SCREEN_LINE6
        sta     bar_ptr+1
        lda     vol_a
        and     #$0F            ; Mask to 0-15
        jsr     draw_bar

        ; Channel B bar - line 8
        lda     #<SCREEN_LINE8
        sta     bar_ptr
        lda     #>SCREEN_LINE8
        sta     bar_ptr+1
        lda     vol_b
        and     #$0F
        jsr     draw_bar

        ; Channel C bar - line 10
        lda     #<SCREEN_LINE10
        sta     bar_ptr
        lda     #>SCREEN_LINE10
        sta     bar_ptr+1
        lda     vol_c
        and     #$0F
        jsr     draw_bar

        rts
.endproc

;-----------------------------------------------------------------------------
; draw_bar - Draw a volume bar
; Input: A = volume (0-15), bar_ptr = screen line address
;-----------------------------------------------------------------------------
.proc draw_bar
        sta     temp            ; Save volume
        tay                     ; Y = volume (bar length)
        beq     @clear_all      ; If volume is 0, clear entire bar

        ; Draw filled part (use inverse block character)
        ldy     #0
@draw_filled:
        lda     #$20            ; Inverse space (solid block)
        sta     (bar_ptr),y
        iny
        cpy     temp
        bne     @draw_filled

        ; Clear remaining part (up to 15 chars)
@clear_rest:
        cpy     #15
        beq     @done
        lda     #$A0            ; Normal space
        sta     (bar_ptr),y
        iny
        jmp     @clear_rest

@clear_all:
        ldy     #0
@clear_loop:
        lda     #$A0            ; Normal space
        sta     (bar_ptr),y
        iny
        cpy     #15
        bne     @clear_loop

@done:
        rts
.endproc


;-----------------------------------------------------------------------------
; dos_run_menu - Execute DOS "RUN HELLO" to return to menu
; Must be called after restore_zp so DOS COUT hook works
;-----------------------------------------------------------------------------
.proc dos_run_menu
        lda     #$84            ; CHR$(4) with high bit - DOS command prefix
        jsr     COUT
        ldy     #0
@loop:
        lda     msg_run,y
        beq     @cr
        ora     #$80            ; Set high bit for Apple II
        jsr     COUT
        iny
        bne     @loop
@cr:
        lda     #$8D            ; CR with high bit - triggers DOS execution
        jsr     COUT
        rts                     ; (not reached - DOS takes over)
.endproc

;-----------------------------------------------------------------------------
; save_zp / restore_zp - Preserve DOS 3.3 zero page state ($80-$9F)
; DOS uses this area for file management; player must not corrupt it
;-----------------------------------------------------------------------------
.proc save_zp
        ldx     #31
@loop:
        lda     $80,x
        sta     zp_save,x
        dex
        bpl     @loop
        rts
.endproc

.proc restore_zp
        ldx     #31
@loop:
        lda     zp_save,x
        sta     $80,x
        dex
        bpl     @loop
        rts
.endproc

;-----------------------------------------------------------------------------
; play_frame - Process music data until we hit a wait command
; Output: Carry clear = continue, Carry set = end of song
;-----------------------------------------------------------------------------
.proc play_frame
@next_byte:
        ldy     #0
        lda     (data_ptr),y    ; Get next byte

        ; Check for special commands
        cmp     #A2M_END
        beq     @end_song

        cmp     #A2M_LOOP
        beq     @mark_loop

        cmp     #A2M_WAIT_EXT
        beq     @extended_wait

        ; Check if it's a wait command ($80-$FD)
        cmp     #$80
        bcs     @short_wait

        ; It's a register write ($00-$0D)
        ; A = register number, save it
        sta     temp            ; Save register number
        jsr     inc_data_ptr    ; Move to value byte

        ldy     #0
        lda     (data_ptr),y    ; A = value
        tax                     ; X = value

        ; Track volume for visualizer (registers 8, 9, 10)
        lda     temp
        cmp     #8
        bne     @not_vol_a
        stx     vol_a
        jmp     @do_write
@not_vol_a:
        cmp     #9
        bne     @not_vol_b
        stx     vol_b
        jmp     @do_write
@not_vol_b:
        cmp     #10
        bne     @do_write
        stx     vol_c

@do_write:
        lda     temp            ; A = register
        jsr     mb_write        ; Write to Mockingboard (A=reg, X=val)

        jsr     inc_data_ptr    ; Move past value byte
        jmp     @next_byte      ; Continue processing

@short_wait:
        ; Wait command: $80-$FD = wait 1-126 frames
        sec
        sbc     #$7F            ; Convert to frame count (1-126)
        sta     wait_count
        lda     #0
        sta     wait_count+1

        jsr     inc_data_ptr
        clc                     ; Continue playing
        rts

@extended_wait:
        ; Extended wait: $FF nn nn
        jsr     inc_data_ptr
        ldy     #0
        lda     (data_ptr),y    ; Low byte of count
        sta     wait_count
        jsr     inc_data_ptr
        ldy     #0
        lda     (data_ptr),y    ; High byte of count
        sta     wait_count+1
        jsr     inc_data_ptr

        clc                     ; Continue playing
        rts

@mark_loop:
        ; Mark loop point
        lda     data_ptr
        sta     loop_ptr
        lda     data_ptr+1
        sta     loop_ptr+1

        jsr     inc_data_ptr
        jmp     @next_byte

@end_song:
        ; Check if we have a loop point
        lda     loop_ptr
        ora     loop_ptr+1
        beq     @really_end     ; No loop, end song

        ; Jump to loop point
        lda     loop_ptr
        sta     data_ptr
        lda     loop_ptr+1
        sta     data_ptr+1

        jsr     inc_data_ptr    ; Skip the loop marker
        jmp     @next_byte

@really_end:
        sec                     ; Signal end of song
        rts
.endproc

;-----------------------------------------------------------------------------
; inc_data_ptr - Increment data pointer
;-----------------------------------------------------------------------------
.proc inc_data_ptr
        inc     data_ptr
        bne     @done
        inc     data_ptr+1
@done:
        rts
.endproc

;-----------------------------------------------------------------------------
; wait_frame - Wait for approximately 1/60th second
; Uses CPU cycle counting for timing
; Apple II runs at ~1.023 MHz, so 1/60 sec = ~17050 cycles
;-----------------------------------------------------------------------------
.proc wait_frame
        ; Check if we need to wait multiple frames
@frame_loop:
        lda     wait_count
        ora     wait_count+1
        beq     @done           ; No more frames to wait

        ; Decrement frame counter
        lda     wait_count
        bne     @no_borrow
        dec     wait_count+1
@no_borrow:
        dec     wait_count

        ; Wait approximately 17050 cycles (1/60 sec at 1.023 MHz)
        ; Outer loop: 256 iterations
        ; Inner loop: ~66 cycles per outer iteration = 16896 cycles
        ldx     #0              ; 2 cycles
@outer:
        ldy     #13             ; 2 cycles
@inner:
        dey                     ; 2 cycles
        bne     @inner          ; 3 cycles (taken), 2 (not taken)
                                ; Inner: 13 * 5 - 1 = 64 cycles
        dex                     ; 2 cycles
        bne     @outer          ; 3 cycles (taken)
                                ; Outer: 256 * (64 + 2 + 2 + 3) = 18176 cycles
                                ; Close enough to 17050

        jmp     @frame_loop

@done:
        rts
.endproc

;-----------------------------------------------------------------------------
; Message strings
;-----------------------------------------------------------------------------
.segment "RODATA"

msg_title:
        .byte   "   HONUX MUSIC PLAYER", $0D
        .byte   "   ==================", $00

msg_playing:
        .byte   "PLAYING... (ESC TO STOP)", $00

msg_not_found:
        .byte   "MOCKINGBOARD NOT FOUND!", $0D
        .byte   "PRESS ANY KEY...", $00

msg_run:
        .byte   "RUN HELLO", $00

;-----------------------------------------------------------------------------
; Music data location
; Music is loaded at $4000 by BASIC before calling player
;-----------------------------------------------------------------------------
music_data = $4000
