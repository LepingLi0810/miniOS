#include "vm.h"
#include "print.h"
#include "debug.h"
#include "stddef.h"
#include "lib.h"
#include "stdbool.h"

static struct FreeMemRegion free_mem_region[50];
static struct Page free_memory;     //head of free list
static uint64_t memory_end;
extern char end;

static void free_region(uint64_t v, uint64_t e)
{
    for (uint64_t start = PA_UP(v); start + PAGE_SIZE <= e; start += PAGE_SIZE) {
        if (start + PAGE_SIZE <= 0xffff800040000000) {     //since only use the 1st g of ram, do not want go beyond it
           kfree(start);
        }
    }
}

void init_memory(void)
{
    int32_t count = *(int32_t *)0x9000;           //physical memory
    uint64_t total_mem = 0;
    struct E820 *mem_map = (struct E820 *)0x9008; //physical memory
    int free_region_count = 0;

    ASSERT(count <= 50);
    //get information of free memory
    //already did the memory detection when loading kernel
	for(int32_t i = 0; i < count; i++) {
        if(mem_map[i].type == 1) {
            free_mem_region[free_region_count].address = mem_map[i].address;
            free_mem_region[free_region_count].length = mem_map[i].length;
            total_mem += mem_map[i].length;
            free_region_count++;
        }
        printk("%x  %uKB  %u\n", mem_map[i].address, mem_map[i].length / 1024, (uint64_t)mem_map[i].type);
	}

    //check free memory can be used or not
    for (int i = 0; i < free_region_count; i++) {
        uint64_t vstart = P2V(free_mem_region[i].address);
        uint64_t vend = vstart + free_mem_region[i].length;

        if (vstart > (uint64_t)&end) {
            free_region(vstart, vend);
        }
        else if (vend > (uint64_t)&end) {
            free_region((uint64_t)&end, vend);
        }
    }

    memory_end = (uint64_t)free_memory.next + PAGE_SIZE;
    printk("%x\n", memory_end);
    init_kvm();
}

void kfree(uint64_t v)
{
    ASSERT(v % PAGE_SIZE == 0);         //make sure page is aligned with 2mb
    ASSERT(v >= (uint64_t)&end);        //make sure this is beyond kernel
    ASSERT(v + PAGE_SIZE <= 0xffff800040000000);        //check 1g limit

    struct Page *page_address = (struct Page*)v;
    page_address->next = free_memory.next;
    free_memory.next = page_address;
}

void* kalloc(void)
{
    struct Page *page_address = free_memory.next;

    if (page_address != NULL) {
        ASSERT((uint64_t)page_address % PAGE_SIZE == 0);        //make sure page is aligned with 2mb
        ASSERT((uint64_t)page_address >= (uint64_t)&end);       //make sure this is beyond kernel
        ASSERT((uint64_t)page_address + PAGE_SIZE <= 0xffff800040000000);   //check 1g limit

        free_memory.next = page_address->next;
    }

    return page_address;
}

//calculate the address of pml4t entry and set its value(Physical address)
static PDPTR find_pml4t_entry(uint64_t map, uint64_t v, int alloc, uint32_t attribute)
{
    PDPTR *map_entry = (PDPTR*)map;
    PDPTR pdptr = NULL;
    unsigned int index = (v >> 39) & 0x1FF;

    if ((uint64_t)map_entry[index] & PTE_P) {
        pdptr = (PDPTR)P2V(PDE_ADDR(map_entry[index]));
    }
    else if (alloc == 1) {
        pdptr = (PDPTR)kalloc();
        if (pdptr != NULL) {
            memset(pdptr, 0, PAGE_SIZE);
            map_entry[index] = (PDPTR)(V2P(pdptr) | attribute);
        }
    }

    return pdptr;
}

//calculate the address of pdpt entry and set its value(Physical address)
static PD find_pdpt_entry(uint64_t map, uint64_t v, int alloc, uint32_t attribute)
{
    PDPTR pdptr = NULL;
    PD pd = NULL;
    unsigned int index = (v >> 30) & 0x1FF;

    pdptr = find_pml4t_entry(map, v, alloc, attribute);     //find page map level 4 table entry
    if (pdptr == NULL)
        return NULL;

    if ((uint64_t)pdptr[index] & PTE_P) {
        pd = (PD)P2V(PDE_ADDR(pdptr[index]));
    }
    else if (alloc == 1) {
        pd = (PD)kalloc();
        if (pd != NULL) {
            memset(pd, 0, PAGE_SIZE);
            pdptr[index] = (PD)(V2P(pd) | attribute);
        }
    }

    return pd;
}

//setup page table and fill entries
bool map_pages(uint64_t map, uint64_t v, uint64_t e, uint64_t pa, uint32_t attribute)
{
    uint64_t vstart = PA_DOWN(v);
    uint64_t vend = PA_UP(e);
    printk("vstart: %x\n", vstart);
    printk("vend: %x\n", vend);
    PD pd = NULL;
    unsigned int index;

    ASSERT(v < e);
    ASSERT(pa % PAGE_SIZE == 0);                            //check alignment
    ASSERT(pa + vend - vstart <= 1024 * 1024 * 1024);       //check limit 1g

    do {
        pd = find_pdpt_entry(map, vstart, 1, attribute);    //find page directory pointer entry
        if (pd == NULL) {
            return false;
        }

        index = (vstart >> 21) & 0x1FF;             //get page directory entry index
        ASSERT(((uint64_t)pd[index] & PTE_P) == 0);     //check present bit

        pd[index] = (PDE)(pa | attribute | PTE_ENTRY);  //map to some physical address

        vstart += PAGE_SIZE;
        pa += PAGE_SIZE;
    } while (vstart + PAGE_SIZE <= vend);
    printk("vstart: %x\n", vstart);
    printk("vend: %x\n", vend);
    return true;
}

//load the new page table base address to cr3 register
void switch_vm(uint64_t map)
{
    load_cr3(V2P(map));
}

//setup kernel virtual memory
uint64_t setup_kvm(void)
{
    uint64_t page_map = (uint64_t)kalloc();

    if (page_map != 0) {
        memset((void*)page_map, 0, PAGE_SIZE);
        if (!map_pages(page_map, KERNEL_BASE, memory_end, V2P(KERNEL_BASE), PTE_P | PTE_W)) {
            free_vm(page_map);
            page_map = 0;
        }
    }
    return page_map;
}

void init_kvm(void)
{
    uint64_t page_map = setup_kvm();                    //set up page map level 4 table
    ASSERT(page_map != 0);
    switch_vm(page_map);
    printk("memory manager is working now\n");
}

//setup user virtual memory
bool setup_uvm(uint64_t map, uint64_t start, int size)
{
    bool status = false;
    void *page = kalloc();      //currently only allocate one page to store code and data, and stack for user program

    if (page != NULL) {
        memset(page, 0, PAGE_SIZE);
        status = map_pages(map, 0x400000, 0x400000 + PAGE_SIZE, V2P(page), PTE_P | PTE_W | PTE_U);
        if (status == true) {
            memcpy(page, (void*)start, size);
        }
        else {
            kfree((uint64_t)page);
            free_vm(map);
        }
    }

    return status;
}

void free_pages(uint64_t map, uint64_t vstart, uint64_t vend)
{
    unsigned int index;

    ASSERT(vstart % PAGE_SIZE == 0);
    ASSERT(vend % PAGE_SIZE == 0);

    do {
        PD pd = find_pdpt_entry(map, vstart, 0, 0);

        if (pd != NULL) {
            index = (vstart >> 21) & 0x1FF;
            ASSERT(pd[index] & PTE_P);
            kfree(P2V(PTE_ADDR(pd[index])));
            pd[index] = 0;
        }

        vstart += PAGE_SIZE;
    } while (vstart + PAGE_SIZE <= vend);
}

static void free_pdt(uint64_t map)
{
    PDPTR *map_entry = (PDPTR*)map;

    for (int i = 0; i < 512; i++) {
        if ((uint64_t)map_entry[i] & PTE_P) {
            PD *pdptr = (PD*)P2V(PDE_ADDR(map_entry[i]));

            for (int j = 0; j < 512; j++) {
                if ((uint64_t)pdptr[j] & PTE_P) {
                    kfree(P2V(PDE_ADDR(pdptr[j])));
                    pdptr[j] = 0;
                }
            }
        }
    }
}

static void free_pdpt(uint64_t map)
{
    PDPTR *map_entry = (PDPTR*)map;

    for (int i = 0; i < 512; i++) {
        if ((uint64_t)map_entry[i] & PTE_P) {
            kfree(P2V(PDE_ADDR(map_entry[i])));
            map_entry[i] = 0;
        }
    }
}

static void free_pml4t(uint64_t map)
{
    kfree(map);
}

void free_vm(uint64_t map)
{
    free_pages(map, 0x400000, 0x400000 + PAGE_SIZE);
    free_pdt(map);
    free_pdpt(map);
    free_pml4t(map);
}