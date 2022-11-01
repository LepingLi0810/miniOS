[BITS 16]
[ORG 0x7c00]

; set data segment, extra segment, stack segment, and stack pointer
Start:
    xor ax,ax
    mov ds,ax
    mov es,ax
    mov ss,ax
    mov sp,0x7c00

; test computer supports disk extentsion or not
TestDiskExtension:
    mov [DriveId],dl
    mov ah,0x41       ; parameter 41 = function number for extensions check
    mov bx,0x55aa     ; parameter 55aa is used to compare result later
    int 0x13          ; BIOS interrupt
    jc NotSupport     ; carry flag set, not suport
    cmp bx,0xaa55     ; aa55 = return value
    jne NotSupport    ; if not equal, not support

; load Loader
LoadLoader:
    mov si,ReadPacket      ; structure contains information(Loader) to read
    mov word[si],0x10      ; size of structure
    mov word[si+2],5       ; number of sectors
    mov word[si+4],0x7e00  ; offset
    mov word[si+6],0       ; segment
    mov dword[si+8],1      ; lower part address, write loader file into second sector of disk
    mov dword[si+0xc],0    ; upper part address, 0, upper-lower = 64 bits
    mov dl,[DriveId]
    mov ah,0x42            ; parameter 42 = Extended Read Sectors From Drive
    int 0x13               ; BIOS interrupt
    jc  ReadError          ; carry flag set, error occured

    mov dl,[DriveId]
    jmp 0x7e00             ; jump to loader

; print out error message
ReadError:
NotSupport:
    mov ah,0x13      ; parameter 13 = print string
    mov al,1         ; parameter 1 = cursor will be placed at the end of string
    mov bx,0xa       ; parameter a = string is printed in bright green
    xor dx,dx        ; clear register dx, so message is printed at the beginning of screen
    mov bp,Message
    mov cx,MessageLen
    int 0x10         ; interrupt 10 print

; infinite loop
End:
    hlt
    jmp End

DriveId:    db 0
Message:    db "An error has occured during boot process"
MessageLen: equ $-Message
ReadPacket: times 16 db 0

; space from the current address to 0x1be is filled with 0
; want BIOS to boot the usb flash driver as hard disk so we create this illusion
times (0x1be-($-$$)) db 0

    db 80h               ; boot indicator
    db 0,2,0             ; starting CHS
    db 0f0h              ; type
    db 0ffh,0ffh,0ffh    ; ending CHS
    dd 1                 ; logical block address of sector
    dd (20*16*63-1)      ; size, how many sectors

    times (16*3) db 0

    db 0x55
    db 0xaa    ; signature


