#include "syscall.h"
#include "print.h"
#include "debug.h"
#include "stddef.h"

static int sys_write(int64_t *argptr)
{
    write_screen((char*)argptr[0], (int)argptr[1], 0xe);
    return (int)argptr[1];
}

static int (*syscalls[])(int64_t *argptr) = {
    [SYS_WRITE]    sys_write,
};



//xv6 system call
/*
void
syscall(void)
{
  int num;

  num = proc->tf->eax;
  if(num > 0 && num < NELEM(syscalls) && syscalls[num]) {
    proc->tf->eax = syscalls[num]();
  } else {
    cprintf("%d %s: unknown sys call %d\n",
            proc->pid, proc->name, num);
    proc->tf->eax = -1;
  }
}
*/

void system_call(struct TrapFrame *tf)
{
    int64_t i = tf->rax;                    //index of system call
    int64_t param_count = tf->rdi;
    int64_t *argptr = (int64_t*)tf->rsi;

    if (param_count < 0 || i != 0) {
        tf->rax = -1;
        return;
    }

    ASSERT(syscalls[i] != NULL);
    tf->rax = syscalls[i](argptr);      //further plan: chech user input argument
}



