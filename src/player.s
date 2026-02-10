;-----------------------------------------------------------------------------
; Apple II Mockingboard Music Player
; Plays .a2m format music files
;-----------------------------------------------------------------------------

.export main

.import mb_init, mb_reset, mb_write, mb_silence, mb_set_slot, mb_detect

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

; Slot number stored by BASIC at $0300
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

;-----------------------------------------------------------------------------
; BSS segment (uninitialized data)
;-----------------------------------------------------------------------------
.segment "BSS"

;-----------------------------------------------------------------------------
; Main Code
;-----------------------------------------------------------------------------
.segment "CODE"

;-----------------------------------------------------------------------------
; Entry point
;-----------------------------------------------------------------------------
.proc main
        jsr     HOME            ; Clear screen
        jsr     show_title

        ; Read slot number from BASIC (stored at $0300)
        ldx     SLOT_ADDR
        cpx     #4
        bcc     @use_default    ; < 4, use default
        cpx     #8
        bcs     @use_default    ; >= 8, use default
        jmp     @set_slot

@use_default:
        ldx     #4              ; Default to slot 4

@set_slot:
        jsr     mb_set_slot     ; Set slot (X = slot number)
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
@exit:
        rts
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
SCREEN_LINE5 = $0680            ; Line 5 of text screen (for visualizer)

.proc show_visualizer
        ; Channel A bar
        ldx     #0              ; Screen position
        lda     vol_a
        and     #$0F            ; Mask to 0-15
        jsr     draw_bar

        ; Channel B bar
        ldx     #14             ; Screen position
        lda     vol_b
        and     #$0F
        jsr     draw_bar

        ; Channel C bar
        ldx     #28             ; Screen position
        lda     vol_c
        and     #$0F
        jsr     draw_bar

        rts
.endproc

;-----------------------------------------------------------------------------
; draw_bar - Draw a volume bar
; Input: A = volume (0-15), X = screen offset
;-----------------------------------------------------------------------------
.proc draw_bar
        sta     temp            ; Save volume
        tay                     ; Y = volume (bar length)
        beq     @clear_all      ; If volume is 0, clear entire bar

        ; Draw filled part (use inverse block character $A0)
@draw_filled:
        lda     #$20            ; Inverse space (solid block)
        sta     SCREEN_LINE5,x
        inx
        dey
        bne     @draw_filled

        ; Clear remaining part (up to 15 chars)
        lda     #15
        sec
        sbc     temp            ; A = 15 - volume = empty chars
        tay
        beq     @done

@clear_rest:
        lda     #$A0            ; Normal space
        sta     SCREEN_LINE5,x
        inx
        dey
        bne     @clear_rest
        jmp     @done

@clear_all:
        ldy     #15
@clear_loop:
        lda     #$A0            ; Normal space
        sta     SCREEN_LINE5,x
        inx
        dey
        bne     @clear_loop

@done:
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

;-----------------------------------------------------------------------------
; Music data location
; Music is loaded at $4000 by BASIC before calling player
;-----------------------------------------------------------------------------
music_data = $4000
