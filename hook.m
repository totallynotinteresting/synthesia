#import <Foundation/Foundation.h>
#import <libkern/OSCacheControl.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <mach/mach.h>
#import <mach/mach_vm.h>

// arm instructs: mov w0, #1; ret
// wtaf??? fucking help me
static const uint32_t patch_insns[] = {0x52800020, 0xd65f03c0};

// declare vm functions because the ones included are shit
extern kern_return_t mach_vm_allocate(vm_map_t target,
                                      mach_vm_address_t *address,
                                      mach_vm_size_t size, int flags);
extern kern_return_t mach_vm_protect(vm_map_t target_task,
                                     mach_vm_address_t address,
                                     mach_vm_size_t size, boolean_t set_maximum,
                                     vm_prot_t new_protection);
extern kern_return_t
mach_vm_remap(vm_map_t target_navp, mach_vm_address_t *target_address,
              mach_vm_size_t size, mach_vm_offset_t mask, int flags,
              vm_map_t src_task, mach_vm_address_t src_address, boolean_t copy,
              vm_prot_t *cur_protection, vm_prot_t *max_protection,
              vm_inherit_t inheritance);

// find the main executable because for some ungodly reason macos decides to
// target the dylib first??????
uintptr_t get_main_executable_base() {
  uint32_t count = _dyld_image_count();
  for (uint32_t i = 0; i < count; i++) {
    const struct mach_header *header = _dyld_get_image_header(i);
    // kys kys kys
    if (header->filetype == MH_EXECUTE) {
      const char *name = _dyld_get_image_name(i);
      NSLog(@"kill yourserlf: %d: %s", i, name);
      return (uintptr_t)header;
    }
  }
  return 0;
}

__attribute__((constructor)) static void initialize_patch() {
  // find the base addr
  uintptr_t base_addr = get_main_executable_base();
  if (base_addr == 0) {
    NSLog(@"you fucked up big man");
    return;
  }

  uintptr_t offset = 0x23d204;
  mach_vm_address_t target_addr = (mach_vm_address_t)(base_addr + offset);

  vm_size_t page_size = vm_kernel_page_size;
  NSLog(@"kill yourself: 0x%llx (Base: 0x%lx) | Page Size: 0x%lx", target_addr,
        base_addr, page_size);

  // align to page boundary
  mach_vm_address_t target_page = target_addr & ~(page_size - 1);
  uintptr_t page_offset = target_addr - target_page;

  // allocate a NEW anonymous page (which is r-w bc macos is finnicky)
  // i need to fucking do this manually becuase MACOS IS FUCKING FINNICKY AND I
  // CANT JUST USE MACH_VM_REMAP and oyu need to do this to avoid kernel
  // restrictions on remapping signed pages directly
  mach_vm_address_t writable_addr = 0;
  kern_return_t kr = mach_vm_allocate(mach_task_self(), &writable_addr,
                                      page_size, VM_FLAGS_ANYWHERE);
  if (kr != KERN_SUCCESS) {
    NSLog(@"mach_vm_allocate failed: %d", kr);
    return;
  }

  mach_vm_protect(mach_task_self(), target_page, page_size, FALSE, VM_PROT_READ | VM_PROT_EXECUTE);

  // copy original data to our new page. at least bnow you can read the
  // executable page, so memcpy works
  memcpy((void *)writable_addr, (void *)target_page, page_size);

  // apply the patch to our own copy
  uint32_t *patch_location = (uint32_t *)(writable_addr + page_offset);
  patch_location[0] = patch_insns[0];
  patch_location[1] = patch_insns[1];
  NSLog(@"patch was applied to shadow page at 0x%llx", writable_addr);

  // set protections on the new page to match the target which is read exec
  // thing is the kernel requires the source page to be executable before we
  // remap it over the text seg ??? i hate macos
  kr = mach_vm_protect(mach_task_self(), writable_addr, page_size, FALSE,
                       VM_PROT_READ | VM_PROT_EXECUTE);
  if (kr != KERN_SUCCESS) {
    NSLog(@"mach_vm_protect (R-X) failed: %d", kr);
  }

  // so now we can remap the new page over the original executable page
  vm_prot_t cur_prot, max_prot;
  kr = mach_vm_remap(mach_task_self(),
                     &target_page, // so this is the addr
                     page_size, 0,
                     VM_FLAGS_OVERWRITE, // overwrite flag
                     mach_task_self(),
                     writable_addr, // src
                     FALSE,         // our copy
                     &cur_prot, &max_prot, VM_INHERIT_COPY);

  if (kr == KERN_SUCCESS) {
    sys_icache_invalidate((void *)target_page, page_size);
    NSLog(@"woop dee doo u fucking did it");
  } else {
    NSLog(@" kys mach_vm_remap failed: %d", kr);
    NSLog(@"hardened runtime is enabled or some shit");
  }
}