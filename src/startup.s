;-----------------------------------------------------------------------------
; Apple II Startup Code for Mockingboard Player
; Creates a binary that can be CALLed from BASIC
;-----------------------------------------------------------------------------

.import main

;-----------------------------------------------------------------------------
; Header segment - Load address for Apple II DOS/ProDOS
;-----------------------------------------------------------------------------
.segment "HEADER"
        .word   $6000           ; Load address

;-----------------------------------------------------------------------------
; Startup segment
;-----------------------------------------------------------------------------
.segment "STARTUP"

;-----------------------------------------------------------------------------
; Entry point - called via CALL 2051 from BASIC
;-----------------------------------------------------------------------------
start:
        ; Jump to main player code
        jsr     main

        ; Return to BASIC (CALL sets up return address)
        rts
