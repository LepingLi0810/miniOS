#ifndef _PROC_H_
#define _PROC_H_

#include "trap.h"

enum procstate { UNUSED, EMBRYO, SLEEPING, RUNNABLE, RUNNING, ZOMBIE };

//per-process state
struct proc {
    int pid;                 //process id
		enum procstate state;		 //process state
		uint64_t pml4t;			     //address of page map level 4 table
		uint64_t kstack;				 //kernel stack
		struct TrapFrame *tf;		 //trap frame
};

//used only for setting up stack pointer for ring0
struct TSS {
    uint32_t res0;
    uint64_t rsp0;
    uint64_t rsp1;
    uint64_t rsp2;
		uint64_t res1;
		uint64_t ist1;		//interrupt stack table
		uint64_t ist2;
		uint64_t ist3;
		uint64_t ist4;
		uint64_t ist5;
		uint64_t ist6;
		uint64_t ist7;
		uint64_t res2;
		uint16_t res3;
		uint16_t iopb;
} __attribute__((packed));

#define kKSTACK_SIZE (2*1024*1024)
#define NPROC 10

void init_process(void);
void launch(void);
void pstart(struct TrapFrame *tf);

#endif