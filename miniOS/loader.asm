[BITS 16]
[ORG 0x7e00]

; print loaded message
Start:
    mov [DriverId], dl
    mov eax, 0x80000000     ; parameter 0x80000001 = process features
    cpuid                   ; instruction to discover details of the processor
    cmp eax,0x80000001      ; check support input value or not
    jb NotSupport
    mov eax,0x80000001
    cpuid
    test edx,(1<<29)        ; check bit 29(support long mode or not)
    jz NotSupport           ; if zero, not support
    test edx,(1<<26)        ; also check support 1g page or not
    jz NotSupport           ; if zero, not support

; load Kernel
LoadKernel:
    mov si,ReadPacket       ; structure contains information(Kernel) to read
    mov word[si],0x10       ; size of structure
    mov word[si+2],100      ; number of sectors
    mov word[si+4],0        ; offset
    mov word[si+6],0x1000   ; segment
    mov dword[si+8],6       ; lower part address, write kernel file into seventh sector of disk
    mov dword[si+0xc],0     ; upper part address, 0, upper-lower = 64 bits
    mov dl,[DriverId]
    mov ah,0x42             ; parameter 42 = Extended Read Sectors From Drive
    int 0x13                ; BIOS interrupt
    jc  ReadError           ; carry flag set, error occured

; load User
LoadUser:
    mov si,ReadPacket       ; structure contains information(Kernel) to read
    mov word[si],0x10       ; size of structure
    mov word[si+2],10       ; number of sectors
    mov word[si+4],0        ; offset
    mov word[si+6],0x2000   ; segment
    mov dword[si+8],106     ; lower part address, write kernel file into seventh sector of disk
    mov dword[si+0xc],0     ; upper part address, 0, upper-lower = 64 bits
    mov dl,[DriverId]
    mov ah,0x42             ; parameter 42 = Extended Read Sectors From Drive
    int 0x13                ; BIOS interrupt
    jc  ReadError           ; carry flag set, error occured

; detect memory
DetectMemory:
    mov eax, 0xe820         ; BIOS function code
    mov edx, 0x534d4150     ; magic number
    mov ecx, 20             ; length of memory block
    mov dword[0x9000], 0    ; initialize it to 0
    mov edi, 0x9008         ; destination buffer, return address
    xor ebx, ebx            ; clears ebx before interrupt
    int 0x15                ; BIOS interrupt, detect memory
    jc NotSupport           ; carry flag set, not support

; keep detecting memory
KeepDetecting:
    add edi, 20             ; move to next memory block
    inc dword[0x9000]       ; count how many memory block
    test ebx, ebx
    jz DetectingDone        ; done

    mov eax, 0xe820         ; BIOS function code
    mov edx, 0x534d4150     ; magic number
    mov ecx, 20             ; length of memory block
    int 0x15                ; BIOS interrupt, detect memory
    jnc KeepDetecting       ; carry flag set, reach the end of memory block

; finished detecting memory
DetectingDone:

; test address line 20 is enabled or not
; if not enabled, bit 20 of memory address would always be 0
TestA20:
    mov ax, 0xffff
    mov es, ax
    mov word[0x7c00], 0xa200        ; use the boot region to do the test since we no longer need boot code
    cmp word[es:0x7c10], 0xa200     ; 0xffff * 16 + 0x7c10 = 0x107c00; if A20 is disabled, this address would be 0x007c00
    jne A20Enabled
    mov word[0x7c00], 0xb200        ; one more test, it is possible that 0x107c00 has the same value as our test value
    cmp word[es:0x7c10], 0xb200     ;
    je NotSupport

A20Enabled:
    xor ax, ax              ; clear ax register
    mov es, ax              ; clear es register

; use other interrupt to print
SetTextMode:
    mov ax, 3               ; set up text/video mode
    int 0x10                ; BIOS interrupt to enable text/video mode

    cli                     ; clear registers
    lgdt [Gdt32Ptr]         ; load global descriptor table
    lidt [Idt32Ptr]         ; load interrupt descriptor table

    mov eax, cr0
    or eax, 1
    mov cr0, eax            ; cr0 is control register that changes the behavior or processor
                            ; 1 means protected mode

    jmp 8:PMEntry           ; index of the segment selector is 8, 2nd entry in GDT

ReadError:
NotSupport:
End:
    hlt
    jmp End

[BITS 32]
PMEntry:
    mov ax, 0x10                    ; offset for data segment(3rd entry in GDT)
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov esp, 0x7c00

    cld                             ; clear direction flag
    mov edi, 0x70000
    xor eax, eax
    mov ecx, 0x10000/4              ; zero 10000 bytes of memory starting from 0x70000
    rep stosd

    mov dword[0x70000], 0x71003     ; set first entry of page map level 4 table
    mov dword[0x71000], 10000011b   ; set first entry of page directory pointer table
                                    ; bit 7 is 1 means this is 1g physical page translation
                                    ; base address of physical page is set to 0

    ; remap kernel
    mov eax, (0xffff800000000000 >> 39)     ; retrieve 9-bit page map level 4 at bit 39
    and eax, 0x1ff                          ; clear other bits
    mov dword[0x70000 + eax*8], 0x72003     ; attribute U(user):W(write):P(present)
    mov dword[0x72000], 10000011b

    lgdt [Gdt64Ptr]                 ; load global descriptor table

    mov eax, cr4
    or eax, (1<<5)
    mov cr4, eax                    ; set physical address extension mode

    mov eax, 0x70000
    mov cr3, eax                    ; copy the address of paging structure here

    mov ecx, 0xc0000080
    rdmsr   ; Reads the contents of a 64-bit model specific register (MSR) specified in the ECX register into registers EDX:EAX
    or eax, (1<<8)                  ; bit 8 indicates long mode
    wrmsr   ; Writes the contents of registers EDX:EAX into the 64-bit model specific register (MSR) specified in the ECX register

    mov eax, cr0
    or eax, (1<<31)
    mov cr0, eax                    ; set bit 31 to 1 to enable paging

    jmp 8:LMEntry                   ; index of the code selector is 8, 2nd entry in GDT

PMEnd:
    hlt
    jmp PMEnd

[BITS 64]
LMEntry:
    mov rsp, 0x7c00

    cld                 ; clear direction flag
    mov rdi, 0x200000   ; rdi register is destination
    mov rsi, 0x10000    ; current kernel location
    mov rcx, 51200/8    ; counter, how many move
    rep movsq

    mov rax, 0xffff800000200000
    jmp rax            ; jump to new kernel location

LMEnd:
    hlt
    jmp LMEnd

DriverId:   db 0
ReadPacket: times 16 db 0

Gdt32:
    dq 0
Code32:
    dw 0xffff   ; maximum size
    dw 0
    db 0
    db 0x9a     ; attribute, four parts P:DPL:S:TYPE
                ; P: present bit, set to 1
                ; DPL: privilege level of segment, set to 0 meanig that running at ring 0
                ; S: system descriptor or not, set to 1 indicates it is code or data segment descriptor
                ; TPYE, set to 1010 meaning that the segment is non-conforming readable code segment
    db 0xcf     ; combination of segment size and attribute, five parts G:D:0:A:LIMIT
                ; G: granularity bit, set to 1 meaning that the size field is scaled by 4kb
                ; D: operand size, set to 1, 32 bits
                ; A: available bit, set to 0, ignore it
                ; LIMIT set to 1111, maximum size
    db 0        ; upper 8 bits of base address
Data32:
    dw 0xffff   ; maximum size
    dw 0
    db 0
    db 0x92     ; attribute, four parts P:DPL:S:TYPE
                ; P: present bit, set to 1
                ; DPL: privilege level of segment, set to 0 meanig that running at ring 0
                ; S: system descriptor or not, set to 1 indicates it is code or data segment descriptor
                ; TPYE, set to 0010 meaning that the segment is readable and writeable data segment
    db 0xcf     ; combination of segment size and attribute, five parts G:D:0:A:LIMIT
                ; G: granularity bit, set to 1 meaning that the size field is scaled by 4kb
                ; D: operand size, set to 1, 32 bits
                ; A: available bit, set to 0, ignore it
                ; LIMIT set to 1111, maximum size
    db 0        ; upper 8 bits of base address

Gdt32Len: equ $-Gdt32

Gdt32Ptr: dw Gdt32Len-1
          dd Gdt32

Idt32Ptr: dw 0
          dd 0

Gdt64:
    dq 0
    dq 0x0020980000000000       ; attribute, 7 parts D:L:P:DPL:1:1:c
                                ; D set to 0 since long bit is set to 1
                                ; L: long bit, set to 1
                                ; P: present bit, set to 1
                                ; DPL: privilege level, set to 0 meanig that running at ring 0
                                ; 1s indicate code segment descriptor
                                ; C: conforming bit, set to 0, non-conforming code segment

Gdt64Len: equ $-Gdt64

Gdt64Ptr: dw Gdt64Len-1
          dd Gdt64