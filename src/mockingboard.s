;-----------------------------------------------------------------------------
; Mockingboard Driver for Apple II
; Supports AY-3-8910 PSG chips in Slot 4
;-----------------------------------------------------------------------------

.export mb_init, mb_reset, mb_write, mb_silence

;-----------------------------------------------------------------------------
; Mockingboard hardware addresses (Slot 4)
;-----------------------------------------------------------------------------
MB_SLOT     = 4
MB_BASE     = $C000 + (MB_SLOT * $100)   ; $C400

; 6522 VIA #1 (Chip 1)
VIA1_ORB    = MB_BASE + $00     ; $C400 - Output Register B (control)
VIA1_ORA    = MB_BASE + $01     ; $C401 - Output Register A (data)
VIA1_DDRB   = MB_BASE + $02     ; $C402 - Data Direction Register B
VIA1_DDRA   = MB_BASE + $03     ; $C403 - Data Direction Register A

; 6522 VIA #2 (Chip 2)
VIA2_ORB    = MB_BASE + $80     ; $C480 - Output Register B (control)
VIA2_ORA    = MB_BASE + $81     ; $C481 - Output Register A (data)
VIA2_DDRB   = MB_BASE + $82     ; $C482 - Data Direction Register B
VIA2_DDRA   = MB_BASE + $83     ; $C483 - Data Direction Register A

;-----------------------------------------------------------------------------
; PSG Control Codes (directly drive BC1/BDIR via VIA ORB)
;-----------------------------------------------------------------------------
PSG_RESET    = $00              ; BDIR=0, BC1=0 - Reset
PSG_INACTIVE = $04              ; BDIR=0, BC1=0 - Inactive
PSG_LATCH    = $07              ; BDIR=1, BC1=1 - Latch Address
PSG_WRITE    = $06              ; BDIR=1, BC1=0 - Write Data
PSG_READ     = $05              ; BDIR=0, BC1=1 - Read Data

;-----------------------------------------------------------------------------
; Zero page variables
;-----------------------------------------------------------------------------
.segment "ZEROPAGE"
mb_reg:     .res 1              ; Current register number
mb_val:     .res 1              ; Value to write

;-----------------------------------------------------------------------------
; Code segment
;-----------------------------------------------------------------------------
.segment "CODE"

;-----------------------------------------------------------------------------
; mb_init - Initialize Mockingboard
; Initializes both 6522 VIAs and resets both PSG chips
;-----------------------------------------------------------------------------
.proc mb_init
        ; Initialize VIA #1
        lda     #$FF            ; All pins output
        sta     VIA1_DDRA       ; Port A = output (data)
        lda     #$07            ; Bits 0-2 output (control)
        sta     VIA1_DDRB       ; Port B = control signals

        ; Initialize VIA #2
        lda     #$FF
        sta     VIA2_DDRA
        lda     #$07
        sta     VIA2_DDRB

        ; Reset both PSG chips
        jsr     mb_reset

        rts
.endproc

;-----------------------------------------------------------------------------
; mb_reset - Reset both PSG chips and silence all channels
;-----------------------------------------------------------------------------
.proc mb_reset
        ; Hardware reset pulse for PSG 1
        lda     #PSG_RESET
        sta     VIA1_ORB
        lda     #PSG_INACTIVE
        sta     VIA1_ORB

        ; Hardware reset pulse for PSG 2
        lda     #PSG_RESET
        sta     VIA2_ORB
        lda     #PSG_INACTIVE
        sta     VIA2_ORB

        ; Silence all channels
        jsr     mb_silence

        rts
.endproc

;-----------------------------------------------------------------------------
; mb_silence - Silence all channels on both chips
;-----------------------------------------------------------------------------
.proc mb_silence
        ; Disable all channels on chip 1 (register 7 = mixer)
        lda     #$07
        sta     mb_reg
        lda     #$3F            ; All channels off
        sta     mb_val
        jsr     write_psg1

        ; Set all volumes to 0 on chip 1
        lda     #$08            ; Channel A volume
        sta     mb_reg
        lda     #$00
        sta     mb_val
        jsr     write_psg1

        lda     #$09            ; Channel B volume
        sta     mb_reg
        jsr     write_psg1

        lda     #$0A            ; Channel C volume
        sta     mb_reg
        jsr     write_psg1

        ; Same for chip 2
        lda     #$07
        sta     mb_reg
        lda     #$3F
        sta     mb_val
        jsr     write_psg2

        lda     #$08
        sta     mb_reg
        lda     #$00
        sta     mb_val
        jsr     write_psg2

        lda     #$09
        sta     mb_reg
        jsr     write_psg2

        lda     #$0A
        sta     mb_reg
        jsr     write_psg2

        rts
.endproc

;-----------------------------------------------------------------------------
; mb_write - Write to PSG register (chip 1 only for now)
; Input: A = register, X = value
;-----------------------------------------------------------------------------
.proc mb_write
        sta     mb_reg
        stx     mb_val
        ; Fall through to write_psg1
.endproc

;-----------------------------------------------------------------------------
; write_psg1 - Write mb_val to register mb_reg on PSG chip 1
;-----------------------------------------------------------------------------
.proc write_psg1
        ; Latch register address
        lda     mb_reg
        sta     VIA1_ORA        ; Put register number on data bus
        lda     #PSG_LATCH
        sta     VIA1_ORB        ; Latch it
        lda     #PSG_INACTIVE
        sta     VIA1_ORB        ; Deactivate

        ; Write data
        lda     mb_val
        sta     VIA1_ORA        ; Put value on data bus
        lda     #PSG_WRITE
        sta     VIA1_ORB        ; Write it
        lda     #PSG_INACTIVE
        sta     VIA1_ORB        ; Deactivate

        rts
.endproc

;-----------------------------------------------------------------------------
; write_psg2 - Write mb_val to register mb_reg on PSG chip 2
;-----------------------------------------------------------------------------
.proc write_psg2
        ; Latch register address
        lda     mb_reg
        sta     VIA2_ORA
        lda     #PSG_LATCH
        sta     VIA2_ORB
        lda     #PSG_INACTIVE
        sta     VIA2_ORB

        ; Write data
        lda     mb_val
        sta     VIA2_ORA
        lda     #PSG_WRITE
        sta     VIA2_ORB
        lda     #PSG_INACTIVE
        sta     VIA2_ORB

        rts
.endproc
