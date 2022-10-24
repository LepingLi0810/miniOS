section .text
global memset
global memcpy
global memmove
global memcmp

memset:
    cld             ; clear direction flag
    mov ecx, edx    ; edx register stores the size
    mov al, sil     ; sil register stores the char value
    rep stosb       ; copy the value in al register to the memory address stored in rdi register
    ret

memcmp:
    cld             ; clear direction flag
    xor eax, eax    ; clear eax register since return value would be stored here
    mov ecx, edx    ; edx register stores the size
    repe cmpsb      ; compare memory and set resume flag, repeat if they are equal and ecx is non-zero
    setnz al        ; if zero flag is cleared, al register is set to 1
    ret

memcpy:
memmove:
    cld             ; clear direction flag
    cmp rsi,rdi     ; compare two memory addresses to check overlap situation
    jae .copy       ; jump if above or equal(destination > source)
    mov r8,rsi      ; rsi register stores source
    add r8,rdx      ; rdx register stores the size, get to the end of source memory address
    cmp r8,rdi      ; check the end of source is in the middle of destination or not
    jbe .copy       ; jump if below or equal

.overlap:
    std             ; set direction flag(from high memory address to low memory address)
    add rdi,rdx     ; get the end of destination
    add rsi,rdx     ; get the end of source
    sub rdi,1       ; then do backward copy
    sub rsi,1

.copy:
    mov ecx,edx     ; edx register stores the size
    rep movsb       ; copy the value
    cld
    ret