#include "Core/Memory/SSMemoryBridge.h"

#include "Core/Process/MachProcessSession.h"
#include "Core/Process/SharedProcessSession.h"
#include "Core/Platform/ProcessMemory.h"

#include <mach/mach.h>
#include <mach/vm_region.h>

#include <mutex>
#include <unistd.h>

namespace {

sscore::MachProcessSession g_sharedSession;
std::once_flag g_sharedSessionOnce;

sscore::ProcessSession* ensureSession() {
    std::call_once(g_sharedSessionOnce, [] {
        g_sharedSession.attach(getpid());
    });
    return g_sharedSession.isAttached() ? &g_sharedSession : nullptr;
}

} // namespace

namespace sscore {

ProcessSession* SharedProcessSession() {
    return ensureSession();
}

} // namespace sscore

extern "C" bool SSMemoryRead(uint64_t address, void* buffer, size_t size, size_t* bytesRead) {
    sscore::ProcessSession* session = ensureSession();
    if (!session || !session->memoryReader()) {
        if (bytesRead) *bytesRead = 0;
        return false;
    }
    return session->memoryReader()->read(address, buffer, size, bytesRead);
}

extern "C" bool SSMemoryWrite(uint64_t address, const void* buffer, size_t size, size_t* bytesWritten) {
    sscore::ProcessSession* session = ensureSession();
    if (!session || !session->memoryWriter()) {
        if (bytesWritten) *bytesWritten = 0;
        return false;
    }
    return session->memoryWriter()->write(address, buffer, size, bytesWritten);
}

extern "C" bool SSMemoryProtect(uint64_t address, size_t size, uint32_t protection) {
    sscore::ProcessSession* session = ensureSession();
    if (!session) return false;

    mach_port_t task = g_sharedSession.taskPort();
    if (task == MACH_PORT_NULL) return false;

    vm_prot_t prot = VM_PROT_NONE;
    if (protection & SSMemoryProtRead) prot |= VM_PROT_READ;
    if (protection & SSMemoryProtWrite) prot |= VM_PROT_WRITE;
    if (protection & SSMemoryProtExecute) prot |= VM_PROT_EXECUTE;
    if (protection & SSMemoryProtCopy) prot |= VM_PROT_COPY;

    kern_return_t kr = mach_vm_protect(task,
                                       (mach_vm_address_t)address,
                                       (mach_vm_size_t)size,
                                       FALSE,
                                       prot);
    return kr == KERN_SUCCESS;
}

extern "C" bool SSMemoryNextRegion(uint64_t* cursor, bool writableOnly, SSMemoryRegionInfo* out) {
    if (!cursor || !out) return false;

    sscore::ProcessSession* session = ensureSession();
    if (!session) return false;

    mach_port_t task = g_sharedSession.taskPort();
    if (task == MACH_PORT_NULL) return false;

    vm_address_t address = (vm_address_t)*cursor;

    for (;;) {
        vm_size_t size = 0;
        natural_t depth = 0;
        vm_region_submap_info_data_64_t info = {};
        mach_msg_type_number_t count = VM_REGION_SUBMAP_INFO_COUNT_64;

        kern_return_t kr = vm_region_recurse_64(task, &address, &size, &depth,
                                                (vm_region_info_t)&info, &count);
        if (kr == KERN_INVALID_ADDRESS) return false;
        if (kr != KERN_SUCCESS) {
            if (size == 0) return false;
            address += size;
            *cursor = (uint64_t)address;
            continue;
        }
        if (size == 0) return false;

        const uint64_t start = (uint64_t)address;
        const uint64_t end = start + (uint64_t)size;
        address += size;
        *cursor = (uint64_t)address;

        if (writableOnly && !(info.protection & VM_PROT_WRITE)) continue;

        out->startAddress = start;
        out->endAddress = end;
        out->size = (uint64_t)size;
        out->readable = (info.protection & VM_PROT_READ) != 0;
        out->writable = (info.protection & VM_PROT_WRITE) != 0;
        out->executable = (info.protection & VM_PROT_EXECUTE) != 0;
        return true;
    }
}

extern "C" bool SSMemoryRegionAt(uint64_t address, SSMemoryRegionInfo* out) {
    if (!out) return false;

    sscore::ProcessSession* session = ensureSession();
    if (!session) return false;

    mach_port_t task = g_sharedSession.taskPort();
    if (task == MACH_PORT_NULL) return false;

    mach_vm_address_t regionAddress = (mach_vm_address_t)address;
    mach_vm_size_t regionSize = 0;
    vm_region_basic_info_data_64_t info = {};
    mach_msg_type_number_t count = VM_REGION_BASIC_INFO_COUNT_64;
    mach_port_t objectName = MACH_PORT_NULL;

    kern_return_t kr = mach_vm_region(task, &regionAddress, &regionSize, VM_REGION_BASIC_INFO_64,
                                      (vm_region_info_t)&info, &count, &objectName);
    if (objectName != MACH_PORT_NULL) {
        mach_port_deallocate(mach_task_self(), objectName);
    }
    if (kr != KERN_SUCCESS) return false;

    out->startAddress = (uint64_t)regionAddress;
    out->endAddress = (uint64_t)regionAddress + (uint64_t)regionSize;
    out->size = (uint64_t)regionSize;
    out->readable = (info.protection & VM_PROT_READ) != 0;
    out->writable = (info.protection & VM_PROT_WRITE) != 0;
    out->executable = (info.protection & VM_PROT_EXECUTE) != 0;
    return true;
}

extern "C" pid_t SSMemoryPid(void) {
    sscore::ProcessSession* session = ensureSession();
    return session ? session->pid() : getpid();
}
