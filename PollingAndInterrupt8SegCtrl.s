.equ    REG_UART_DATA,      0xff201000
.equ    REG_UART_CTRL,      0xff201004
.equ    BASE_PBUTTONS,      0xFF200050
.equ    BASE_DISPLAYS,      0xFF200020

// GIC base addresses
.equ    GIC_CPU_INTERFACE_BASE, 0xFFFEC100
.equ    GIC_DISTRIBUTOR_BASE,  0xFFFED000

// Push button interrupt ID 
.equ    PUSH_BUTTON_IRQ_ID, 73

.text
// Interrupt vector table
B _start               // Reset vector
B SERVICE_UND          // Undefined instruction vector
B SERVICE_SVC          // Software interrupt vector
B SERVICE_ABT_INST     // Prefetch abort vector
B SERVICE_ABT_DATA     // Data abort vector
.word 0                // Reserved
B SERVICE_IRQ          // IRQ vector
B SERVICE_FIQ          // FIQ vector

// Dummy handlers for other exceptions CANVAS
SERVICE_UND:
    B SERVICE_UND
SERVICE_SVC:
    B SERVICE_SVC
SERVICE_ABT_INST:
    B SERVICE_ABT_INST
SERVICE_ABT_DATA:
    B SERVICE_ABT_DATA
SERVICE_FIQ:
    B SERVICE_FIQ

.data
lookup_segments:
    .word 0x3F    // 0
    .word 0x06    // 1
    .word 0x5B    // 2
    .word 0x4F    // 3
    .word 0x66    // 4
    .word 0x6D    // 5
    .word 0x7D    // 6
    .word 0x07    // 7
    .word 0x7F    // 8
    .word 0x6F    // 9
    .word 0x77    // A
    .word 0x7C    // B
    .word 0x39    // C
    .word 0x5E    // D
    .word 0x79    // E
    .word 0x71    // F

// Store counter in memory
counter:
    .word 0 // display current value

.text
.global _start

_start:
    // Enter SVC mode with IRQ disabled
    MSR CPSR_c, #0xD3        // SVC mode, IRQ disabled

    // Configure the GIC for push button interrupts
    MOV     R0, #PUSH_BUTTON_IRQ_ID
    BL      CONFIG_GIC

    // Configure push buttons to generate interrupts
    LDR     R0, =BASE_PBUTTONS
    MOV     R1, #0x3         // Enable interrupts on PB1 and PB2
    STR     R1, [R0, #0x8]   // Write to interrupt mask register meaning that we enabled Interrupts for those buttons
    // Clear any pending interrupts
    LDR     R1, [R0, #0xC]
    STR     R1, [R0, #0xC]

    // Enable IRQ in CPSR (SVC mode, IRQ enabled)
    MSR CPSR_c, #0b01010011

    // Display initial value
    BL      update_display

main_loop:
    // Poll UART
    LDR     r0, =REG_UART_DATA

wait_for_input:
    LDR     r1, [r0]         // Read UART data register
    TST     r1, #0x8000      // Check the valid bit
    BEQ     wait_for_input

    UXTB    r1, r1           // Extract the character
    CMP     r1, #'w'
    BEQ     inc_counter
    CMP     r1, #'s'
    BEQ     dec_counter

    B       main_loop

inc_counter:
    PUSH    {lr}
    LDR     r0, =counter
    LDR     r1, [r0]
    ADD     r1, r1, #1
    AND     r1, r1, #0xF
    STR     r1, [r0]
    BL      update_display
    POP     {lr}
    B       main_loop

dec_counter:
    PUSH    {lr}
    LDR     r0, =counter
    LDR     r1, [r0]
    SUB     r1, r1, #1
    ADD     r1, r1, #16  // handle underflow
    AND     r1, r1, #0xF
    STR     r1, [r0]
    BL      update_display
    POP     {lr}
    B       main_loop

// IRQ Service Routine
SERVICE_IRQ: // canvas
    PUSH    {r0-r7, lr}
    LDR     r4, =GIC_CPU_INTERFACE_BASE
    LDR     r5, [r4, #0x0C]      // Read current Interrupt ID (ICCIAR)

    CMP     r5, #PUSH_BUTTON_IRQ_ID
    BEQ     BUTTON_IRQ_HANDLER

SERVICE_IRQ_DONE: // canvas
    // Write ICCEOIR to signal completion of interrupt
    STR     r5, [r4, #0x10]

    POP     {r0-r7, lr}
    SUBS    PC, lr, #4           // Return from interrupt

BUTTON_IRQ_HANDLER:
    // Handle push button interrupt
    PUSH    {r0, r1, lr}
    LDR     r0, =BASE_PBUTTONS
    LDR     r1, [r0, #0xC]       // Read edge capture register
    STR     r1, [r0, #0xC]       // Clear it

    // PB1 is bit 1 (0x2), PB0 is bit 0 (0x1)
    TST     r1, #0x2            // PB1 pressed?
    BEQ     check_pb0
    // Increment if PB1
    BL      increment_counter_irq
    B       finish_btn_irq

check_pb0:
    TST     r1, #0x1            // PB0 pressed?
    BEQ     finish_btn_irq
    // Decrement if PB0
    BL      decrement_counter_irq

finish_btn_irq:
    POP     {r0, r1, lr}
    B       SERVICE_IRQ_DONE


// Increment counter called from IRQ
increment_counter_irq:
    PUSH    {lr}
    LDR     r0, =counter
    LDR     r1, [r0]
    ADD     r1, r1, #1
    AND     r1, r1, #0xF
    STR     r1, [r0]
    BL      update_display
    POP     {lr}
    BX      lr

// Decrement counter called from IRQ
decrement_counter_irq:
    PUSH    {lr}
    LDR     r0, =counter
    LDR     r1, [r0]
    SUB     r1, r1, #1
    ADD     r1, r1, #16
    AND     r1, r1, #0xF
    STR     r1, [r0]
    BL      update_display
    POP     {lr}
    BX      lr

// Update display subroutine
update_display:
    PUSH    {r0, r1, r3, lr}
    LDR     r0, =BASE_DISPLAYS
    LDR     r1, =lookup_segments
    LDR     r3, =counter
    LDR     r2, [r3]
    LSL     r3, r2, #2     // r3 = r2 * 4
    ADD     r1, r1, r3
    LDR     r3, [r1]
    STR     r3, [r0]
    POP     {r0, r1, r3, lr}
    BX      lr

// Configure GIC function
CONFIG_GIC: // canvas
    PUSH {lr}
    MOV R1, #1
    BL CONFIG_INTERRUPT

    LDR R0, =GIC_CPU_INTERFACE_BASE
    LDR R1, =0xFFFF
    STR R1, [R0, #0x04]
    MOV R1, #1
    STR R1, [R0]

    LDR R0, =GIC_DISTRIBUTOR_BASE
    STR R1, [R0]

    POP {lr}
    BX lr

CONFIG_INTERRUPT: // canvas
    PUSH {r4-r5, lr}
    LSR r4, r0, #3
    BIC r4, r4, #3
    LDR r2, =0xFFFED100
    ADD r4, r2, r4
    AND r2, r0, #0x1F
    MOV r5, #1
    LSL r2, r5, r2
    LDR r3, [r4]
    ORR r3, r3, r2
    STR r3, [r4]

    BIC r4, r0, #3
    LDR r2, =0xFFFED800
    ADD r4, r2, r4
    AND r2, r0, #0x3
    ADD r4, r4, r2
    STRB r1, [r4]

    POP {r4-r5, lr}
    BX lr