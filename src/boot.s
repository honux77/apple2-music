;-----------------------------------------------------------------------------
; Apple II Boot Sector
; Loads and runs the player directly without DOS
;-----------------------------------------------------------------------------

.segment "BOOT"

;-----------------------------------------------------------------------------
; Boot sector entry point (loaded at $0800 by ROM)
; X = slot * 16, boot ROM is at $Cn00
;-----------------------------------------------------------------------------
boot:
        ; Save slot info
        stx     slot16

        ; Display loading message
        jsr     $FC58           ; HOME - clear screen
        ldy     #0
@msg:   lda     msg_loading,y
        beq     @load
        ora     #$80            ; Set high bit for Apple II
        jsr     $FDED           ; COUT
        iny
        bne     @msg

@load:
        ; Set up RWTS parameters for loading
        ; Load sectors to $0900 onwards
        lda     #$09            ; Start loading at $0900
        sta     load_addr+1
        lda     #$00
        sta     load_addr

        lda     #$01            ; Start from track 0, sector 1
        sta     sector

        lda     #70             ; Load 70 sectors (~17.5KB)
        sta     count

@read_loop:
        ; Read one sector
        ldx     slot16
        lda     #$01            ; Read command
        jsr     $C65C           ; RWTS entry point (slot-relative)

        ; Check for error
        bcs     @error

        ; Increment destination address
        clc
        lda     load_addr+1
        adc     #1              ; Add 256 bytes (1 page)
        sta     load_addr+1

        ; Next sector
        inc     sector
        lda     sector
        cmp     #16             ; Sectors 0-15 per track
        bcc     @no_wrap
        lda     #0
        sta     sector
        inc     track
@no_wrap:

        ; Decrement count
        dec     count
        bne     @read_loop

        ; Jump to loaded code
        jmp     $0900

@error:
        ; Display error message
        ldy     #0
@errmsg:
        lda     msg_error,y
        beq     @halt
        ora     #$80
        jsr     $FDED
        iny
        bne     @errmsg
@halt:
        jmp     @halt           ; Hang

;-----------------------------------------------------------------------------
; Data
;-----------------------------------------------------------------------------
slot16:     .byte   $60         ; Slot * 16 (default slot 6)
track:      .byte   $00         ; Current track
sector:     .byte   $01         ; Current sector
count:      .byte   70          ; Sectors to load
load_addr:  .word   $0900       ; Load address

msg_loading:
        .byte   "LOADING MOCKINGBOARD PLAYER...", $8D, $00

msg_error:
        .byte   "DISK ERROR!", $00

;-----------------------------------------------------------------------------
; Pad to 256 bytes (one sector)
;-----------------------------------------------------------------------------
.res    256 - (* - boot), $00
