#include "trap.h"
#include "print.h"
#include "debug.h"
#include "vm.h"
#include "proc.h"

void KernelMain()
{
    init_idt();
    init_memory();
    init_process();
    launch();
}