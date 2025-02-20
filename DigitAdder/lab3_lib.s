.data
    inputBuffer: .space 64          # Buffer for storing input data from stdin
    outputBuffer: .space 64         # Buffer for storing output data to stdout
    inPtr: .quad 0                  # Pointer to the current position in inputBuffer
    outPtr: .quad 0                 # Pointer to the current position in outputBuffer

.text
    .global inImage, getInt, getText, getChar, getInPos, setInPos
    .global outImage, putInt, putText, putChar, getOutPos, setOutPos

######## INPUT ROUTINES ########

# Reads up to 64 bytes from stdin into inputBuffer and resets inPtr to 0.
inImage:
    movq $0, %rdi               # stdin (file descriptor 0)
    lea inputBuffer, %rsi       # Address of inputBuffer
    movq $64, %rdx              # Number of bytes to read
    movq $0, %rax               # Syscall number for read
    syscall                     # Perform syscall
    lea inPtr, %rax             # Load address of inPtr
    movq $0, (%rax)             # Reset inPtr to 0
    ret

# getInt: Reads an integer from inputBuffer, handling whitespace, signs, and digits.
getInt:
    push %r10                  # Save registers used in this function
    push %r11
    push %r12

retryGetInt:
    lea inputBuffer, %rax      # Address of inputBuffer
    movq inPtr, %r10           # Load current pointer offset
    lea (%rax, %r10), %rdi     # Compute address of current input character

    movq $0, %rax              # Accumulator for the parsed integer
    movq $0, %r11              # Flag for negative sign (0 = positive, 1 = negative)

    # Check if buffer is empty or newline, and refill if needed
    cmpb $0, (%rdi)            # Check if current character is null
    je refillBuffer
    cmpb $'\n', (%rdi)        # Check if current character is newline
    je refillBuffer

skipSpacesInternal:
    cmpb $' ', (%rdi)          # Skip whitespace
    je skipChar
    cmpb $'\t', (%rdi)
    je skipChar
    jmp handlePlusSign

skipChar:
    inc %rdi                   # Move to the next character
    inc %r10                   # Increment inPtr
    cmpb $0, (%rdi)            # Check if buffer is empty
    je refillBuffer
    cmpb $'\n', (%rdi)        # Check if newline
    je refillBuffer
    jmp skipSpacesInternal

handlePlusSign:
    cmpb $'+', (%rdi)          # Handle '+' sign
    jne handleMinusSign
    inc %rdi                   # Move past '+' sign
    inc %r10                   # Increment inPtr
    jmp parseDigits

handleMinusSign:
    cmpb $'-', (%rdi)          # Handle '-' sign
    jne parseDigits
    movq $1, %r11              # Set negative flag
    inc %rdi                   # Move past '-' sign
    inc %r10

parseDigits:
    cmpb $'0', (%rdi)          # Parse digits
    jl invalidDigit
    cmpb $'9', (%rdi)
    jg invalidDigit
    movzbq (%rdi), %r12
    subq $'0', %r12
    imulq $10, %rax
    addq %r12, %rax
    inc %rdi
    inc %r10
    jmp parseDigits

invalidDigit:
    cmpq $1, %r11              # Negate if negative
    jne finishGetInt
    negq %rax

finishGetInt:
    movq %r10, inPtr           # Update inPtr
    pop %r12
    pop %r11
    pop %r10
    ret

refillBuffer:
    pushq %rax                 # Save current value of %rax
    call inImage               # Refill inputBuffer
    popq %rax                  # Restore %rax
    jmp retryGetInt

# getText: Reads a string from inputBuffer into memory pointed to by %rdi.
getText:
    push %r10                  # Save registers used in this function
    movq $0, %r10              # Initialize counter for bytes read
    movq inPtr, %rcx           # Load current input position
    lea inputBuffer, %rax

readTextLoop:
    cmpq $0, %rsi              # Check if requested length is 0
    je finishTextRead
    movq (%rax, %rcx), %rdx    # Load current character
    cmpq $0, %rdx              # Check for null byte
    je finishTextRead
    movq %rdx, (%rdi)          # Store character in destination buffer
    inc %rcx                   # Increment input position
    inc %rdi
    inc %r10                   # Increment read counter
    dec %rsi                   # Decrement requested length
    jmp readTextLoop

finishTextRead:
    movq %rcx, inPtr           # Update inPtr
    movq %r10, %rax            # Return number of bytes read
    pop %r10                   # Restore registers
    ret

# getChar: Reads a single character from inputBuffer. Refills buffer if empty.
getChar:
    push %r10
    movq inPtr, %r10
    lea inputBuffer, %rdx

refillChar:
    cmpb $0, (%rdx, %r10)
    je inImage
    movq (%rdx, %r10), %rax
    inc %r10
    movq %r10, inPtr
    pop %r10
    ret

# getInPos / setInPos: Get or set the current position of inPtr.
getInPos:
    movq inPtr, %rax
    ret

setInPos:
    cmpq $0, %rdi              # Check if position is less than 0
    jl resetInPos              # If less than 0, reset to 0
    cmpq $63, %rdi             # Check if position exceeds 63
    jg maxInPos                # If greater than 63, set to 63
    movq %rdi, inPtr           # If within range, set inPtr
    ret                        # Return

resetInPos:
    movq $0, inPtr             # Reset inPtr to 0
    ret                        # Return

maxInPos:
    movq $63, inPtr            # Set inPtr to 63
    ret                        # Return


######## OUTPUT ROUTINES ########

# Writes everything in outputBuffer (up to outPtr) to stdout.
outImage:
    movq $1, %rdi
    lea outputBuffer, %rsi
    movq outPtr, %rdx
    movq $1, %rax
    syscall
    movq $0, outPtr
    ret

# putInt: Converts a signed 64-bit integer in %rdi to a string and stores it
putInt:
    pushq $0
    movq $10, %rcx
    cmpq $0, %rdi
    jl handleNegativeInt
continuePutInt:
    movq %rdi, %rax
convertDigits:
    cqto
    divq %rcx
    addq $'0', %rdx
    pushq %rdx
    cmpq $0, %rax
    je flushIntChars
    jmp convertDigits

handleNegativeInt:
    pushq %rdi
    movq $'-', %rdi
    call putChar
    popq %rdi
    negq %rdi
    jmp continuePutInt

flushIntChars:
    popq %rdi
    cmpq $0, %rdi
    je donePutInt
    call putChar
    jmp flushIntChars

donePutInt:
    ret

# putText: Writes a null-terminated string to outputBuffer.
putText:
    pushq %rbx
    movq outPtr, %rax
    lea outputBuffer, %rdx
    movq $0, %rbx
writeTextBytes:
    movzbq (%rdi, %rbx), %rcx
    cmpq $0, %rcx
    je donePutText
    movq %rcx, (%rdx, %rax)
    inc %rax
    inc %rbx
    cmpq $64, %rax
    je handleTextOverflow
    jmp writeTextBytes

handleTextOverflow:
    call outImage
    movq $0, %rax
    jmp writeTextBytes

donePutText:
    movq %rax, outPtr
    popq %rbx
    ret

# putChar: Writes a single character to outputBuffer.
putChar:
    movq outPtr, %rax
    cmpq $64, %rax
    jl storeChar
    call outImage
    movq $0, %rax
storeChar:
    lea outputBuffer, %rdx
    movq %rdi, (%rdx, %rax)
    inc %rax
    movq %rax, outPtr
    ret

# getOutPos / setOutPos: Get or set the current position of outPtr.
getOutPos:
    movq outPtr, %rax
    ret

setOutPos: # has to be in bounds (0-63)
    cmpq $0, %rdi
    jl resetOutPos
    cmpq $63, %rdi
    jg maxOutPos
    movq %rdi, outPtr
    ret
resetOutPos:
    movq $0, outPtr
    ret
maxOutPos:
    movq $63, outPtr
    ret
