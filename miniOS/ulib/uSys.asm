section .text
global write

write:
    sub rsp,16          ; reserve space for arguments
    xor eax,eax         ; zero eax register

    mov [rsp], rdi      ; get first argument
    mov [rsp+8], rsi    ; get second argument

    mov rdi,2           ; set argument for system call, argnum
    mov rsi, rsp        ; set argument for system call, argptr
    int 0x80            ; interrupt 0x80(system call)

    add rsp,16
    ret