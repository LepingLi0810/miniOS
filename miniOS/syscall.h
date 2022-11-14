#ifndef _SYSCALL_H_
#define _SYSCALL_H_

#include "trap.h"

#define SYS_WRITE    0

void system_call(struct TrapFrame *tf);

#endif