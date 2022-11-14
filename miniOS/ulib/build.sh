nasm -f elf64 -o uSys.o uSys.asm
gcc -std=c99 -mcmodel=large -ffreestanding -fno-stack-protector -mno-red-zone -c printf.c
ar rcs ulib.a printf.o uSys.o
