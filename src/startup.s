;-----------------------------------------------------------------------------
; Apple II Startup Code for Mockingboard Player
; Creates a binary that can be BRUNned from ProDOS or DOS 3.3
;-----------------------------------------------------------------------------

.import main

;-----------------------------------------------------------------------------
; Header segment - Load address for Apple II DOS/ProDOS
;-----------------------------------------------------------------------------
.segment "HEADER"
        .word   $0803           ; Load address

;-----------------------------------------------------------------------------
; Startup segment
;-----------------------------------------------------------------------------
.segment "STARTUP"

;-----------------------------------------------------------------------------
; Entry point - called when binary is BRUNned
;-----------------------------------------------------------------------------
start:
        ; Disable interrupts during playback
        sei

        ; Save current stack pointer
        tsx
        stx     save_sp

        ; Jump to main player code
        jsr     main

        ; Restore stack pointer
        ldx     save_sp
        txs

        ; Re-enable interrupts
        cli

        ; Return to caller (DOS/ProDOS)
        rts

;-----------------------------------------------------------------------------
; Data
;-----------------------------------------------------------------------------
save_sp:
        .byte   $00
