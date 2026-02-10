;-----------------------------------------------------------------------------
; Mockingboard Driver for Apple II
; Supports AY-3-8910 PSG chips with configurable slot
;-----------------------------------------------------------------------------

.export mb_init, mb_reset, mb_write, mb_silence, mb_set_slot, mb_detect

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
via1_base:  .res 2              ; VIA #1 base address (chip 1)
via2_base:  .res 2              ; VIA #2 base address (chip 2)

;-----------------------------------------------------------------------------
; Code segment
;-----------------------------------------------------------------------------
.segment "CODE"

;-----------------------------------------------------------------------------
; mb_set_slot - Set Mockingboard slot number
; Input: A = slot number (1-7)
;-----------------------------------------------------------------------------
.proc mb_set_slot
        ; Calculate VIA1 base: $C000 + (slot * $100)
        ; Low byte is always $00
        lda     #$00
        sta     via1_base
        sta     via2_base

        ; High byte is $C0 + slot
        txa                     ; X = slot number
        clc
        adc     #$C0
        sta     via1_base+1

        ; VIA2 is at base + $80, so same high byte
        sta     via2_base+1

        rts
.endproc

;-----------------------------------------------------------------------------
; mb_detect - Detect Mockingboard in slot
; Input: X = slot number (1-7)
; Output: Carry clear = found, Carry set = not found
;-----------------------------------------------------------------------------
.proc mb_detect
        ; Set up the slot
        jsr     mb_set_slot

        ; Try to detect 6522 VIA by writing/reading timer
        ; Write to VIA timer latch and read back
        ldy     #$04            ; Timer 1 low-order latch (offset $04)
        lda     #$55            ; Test pattern
        sta     (via1_base),y
        lda     (via1_base),y
        cmp     #$55
        bne     @not_found

        lda     #$AA            ; Another test pattern
        sta     (via1_base),y
        lda     (via1_base),y
        cmp     #$AA
        bne     @not_found

        clc                     ; Found
        rts

@not_found:
        sec                     ; Not found
        rts
.endproc

;-----------------------------------------------------------------------------
; mb_init - Initialize Mockingboard
; Assumes mb_set_slot was called first
;-----------------------------------------------------------------------------
.proc mb_init
        ; Initialize VIA #1
        lda     #$FF            ; All pins output
        ldy     #$03            ; DDRA offset
        sta     (via1_base),y
        lda     #$07            ; Bits 0-2 output (control)
        ldy     #$02            ; DDRB offset
        sta     (via1_base),y

        ; Initialize VIA #2
        lda     #$FF
        ldy     #$03
        sta     (via2_base),y
        lda     #$07
        ldy     #$02
        sta     (via2_base),y

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
        ldy     #$00            ; ORB offset
        sta     (via1_base),y
        lda     #PSG_INACTIVE
        sta     (via1_base),y

        ; Hardware reset pulse for PSG 2
        lda     #PSG_RESET
        ldy     #$00
        sta     (via2_base),y
        lda     #PSG_INACTIVE
        sta     (via2_base),y

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
; mb_write - Write to PSG register (both chips for stereo)
; Input: A = register, X = value
;-----------------------------------------------------------------------------
.proc mb_write
        sta     mb_reg
        stx     mb_val
        jsr     write_psg1
        jmp     write_psg2      ; Write same value to chip 2
.endproc

;-----------------------------------------------------------------------------
; write_psg1 - Write mb_val to register mb_reg on PSG chip 1
;-----------------------------------------------------------------------------
.proc write_psg1
        ; Latch register address
        lda     mb_reg
        ldy     #$01            ; ORA offset
        sta     (via1_base),y
        lda     #PSG_LATCH
        ldy     #$00            ; ORB offset
        sta     (via1_base),y
        lda     #PSG_INACTIVE
        sta     (via1_base),y

        ; Write data
        lda     mb_val
        ldy     #$01            ; ORA offset
        sta     (via1_base),y
        lda     #PSG_WRITE
        ldy     #$00            ; ORB offset
        sta     (via1_base),y
        lda     #PSG_INACTIVE
        sta     (via1_base),y

        rts
.endproc

;-----------------------------------------------------------------------------
; write_psg2 - Write mb_val to register mb_reg on PSG chip 2
; VIA2 is at via1_base + $80
;-----------------------------------------------------------------------------
.proc write_psg2
        ; Calculate VIA2 address (base + $80)
        clc
        lda     via1_base
        adc     #$80
        sta     via2_base
        lda     via1_base+1
        adc     #$00
        sta     via2_base+1

        ; Latch register address
        lda     mb_reg
        ldy     #$01            ; ORA offset
        sta     (via2_base),y
        lda     #PSG_LATCH
        ldy     #$00            ; ORB offset
        sta     (via2_base),y
        lda     #PSG_INACTIVE
        sta     (via2_base),y

        ; Write data
        lda     mb_val
        ldy     #$01            ; ORA offset
        sta     (via2_base),y
        lda     #PSG_WRITE
        ldy     #$00            ; ORB offset
        sta     (via2_base),y
        lda     #PSG_INACTIVE
        sta     (via2_base),y

        rts
.endproc
