#include "proc.h"
#include "trap.h"
#include "vm.h"
#include "print.h"
#include "assert.h"
#include "lib.h"
#include "debug.h"

extern struct TSS TSS;
static struct proc ptable[NPROC];
static int pid_num = 1;

static void set_tss(struct proc *p)
{
    TSS.rsp0 = p->kstack + kKSTACK_SIZE;
}

//look in the process table for an UNUSED proc
static struct proc* find_unused_process(void)
{
    struct proc *process = NULL;

    for (int i = 0; i < NPROC; i++) {
        if (ptable[i].state == UNUSED) {
            process = &ptable[i];
            break;
        }
    }

    return process;
}

//change process state to EMBRYO and initialize state required to run in the kernel
static void allocproc(struct proc *p)
{
    uint64_t kstack_top;

    p->state = EMBRYO;
    p->pid = pid_num++;

    p->kstack = (uint64_t)kalloc();
    ASSERT(p->kstack != 0);

    memset((void*)p->kstack, 0, PAGE_SIZE);
    kstack_top = p->kstack + kKSTACK_SIZE;

    p->tf = (struct TrapFrame*)(kstack_top - sizeof(struct TrapFrame));
    p->tf->cs = 0x10|3;
    p->tf->rip = 0x400000;
    p->tf->ss = 0x18|3;
    p->tf->rsp = 0x400000 + PAGE_SIZE;
    p->tf->rflags = 0x202;

    p->pml4t = setup_kvm();
    ASSERT(p->pml4t != 0);
    ASSERT(setup_uvm(p->pml4t, (uint64_t)P2V(0x20000), 5120));
}

void init_process(void)
{
    struct proc *process = find_unused_process();
    ASSERT(process == &ptable[0]);

    allocproc(process);
}

void launch(void)
{
    set_tss(&ptable[0]);
    switch_vm(ptable[0].pml4t);
    pstart(ptable[0].tf);
}

