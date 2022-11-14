section .data
global TSS
Gdt64:
    dq 0
    dq 0x0020980000000000       ; attribute, 7 parts D:L:P:DPL:1:1:c
                                ; D set to 0 since long bit is set to 1
                                ; L: long bit, set to 1
                                ; P: present bit, set to 1
                                ; DPL: privilege level, set to 0 meanig that running at ring 0
                                ; 1s indicate code segment descriptor
                                ; C: conforming bit, set to 0, non-conforming code segment
    dq 0x0020f80000000000       ; set ring 3 privilege level for code segment
    dq 0x0000f20000000000       ; set ring 3 privilege level for data segment

TSSDesc:
    dw TSSLen-1                 ; limit
    dw 0                        ; base address
    db 0
    db 0x89                     ; attribute, 3 parts P:DPL:TYPE
                                ; P: present bit, set to 1
                                ; DPL: privilege level, set to 0 meanig that running at ring 0
                                ; TYPE: 01001 indicates this is Task State segment
    db 0
    db 0
    dq 0

Gdt64Len: equ $-Gdt64


Gdt64Ptr: dw Gdt64Len-1
          dq Gdt64

TSS:
    dd 0                        ; reserved
    dq 0xffff800000190000       ; stack pointer
    times 88 db 0
    dd TSSLen

TSSLen: equ $-TSS

section .text
extern KernelMain
global start

start:
    mov rax, Gdt64Ptr
    lgdt [rax]

SetTSS:
    mov rax, TSS
    mov rdi, TSSDesc
    mov [rdi+2], ax
    shr rax, 16
    mov [rdi+4], al
    shr rax, 8
    mov [rdi+7], al
    shr rax, 8
    mov [rdi+8], eax

    mov ax, 0x20
    ltr ax                  ; load task register

; initialize programmable interval timer(system clock)
InitPIT:
    mov al, (1<<2)|(3<<4)           ; code 00 11 010 0
                                    ; 00(channel 0, connect to IRQ0)
                                    ; 11(access mode, write low byte first to register)
                                    ; 010(operating mode 2)
                                    ; 0(binary form)
    out 0x43, al                    ; write to 43(address of mode command register)

    mov ax, 11931                   ; counter value
    out 0x40, al                    ; write lower 6 bits to 40(address of data register of channel 0)
    mov al, ah                      ; now write higher 6 bits
    out 0x40, al                    ; write higher 6 bits to 40(address of data register of channel 0)

; initialize programmable interrupt controller
InitPIC:
    mov al, 0x11                    ; initialization command word 1: 000 1 0 0 0 1
                                    ; bit 4 means the initialization command is follwed by another three initialization command words
                                    ; bit 0 means using the last initialization command word
    out 0x20, al                    ; write to 20(address of the master's command register)
    out 0xa0, al                    ; write to a0(address of the slave's command register)

    mov al, 32                      ; initialization command word 2, starting vector number of first IRQ for master
    out 0x21, al                    ; write to 21(address of the master's data register)
    mov al, 40                      ; starting vector number of first IRQ for slave, since each PIC chip has 8 IRQs, starting would be 32 + 8
    out 0xa1, al                    ; write to a1(address of the slave's data register)

    mov al, 4                       ; initialization command word 3, inidcates which IRQ is used for connecting two PIC chips, IRQ2 in this case
    out 0x21, al                    ; write to 21(address of the master's data register)
    mov al, 2                       ; slave
    out 0xa1, al                    ; write to a1(address of the slave's data register)

    mov al, 1                       ; initialization command word 3, indicates x86 system is used, other modes are not used
    out 0x21, al                    ; write to 21(address of the master's data register)
    out 0xa1, al                    ; write to a1(address of the slave's data register)

    mov al, 11111110b               ; mask all the IRQs except IRQ0(used)
    out 0x21, al                    ; write to 21(address of the master's data register)
    mov al, 11111111b               ; do not use slave at all
    out 0xa1, al                    ; write to a1(address of the master's data register)

    mov rax, KernelEntry
    push 8                  ; code segment is the second entry
    push rax
    db 0x48                 ; add 48 to change the operand size to 64 bits
    retf                    ; return to the same privilege level

KernelEntry:
    mov rsp, 0xffff800000200000
    call KernelMain
End:
    hlt
    jmp End


