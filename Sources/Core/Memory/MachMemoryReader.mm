#include "Core/Memory/MachMemoryReader.h"

#include "Core/Platform/ProcessMemory.h"

#include <mach/mach.h>

namespace sscore {

MachMemoryReader::MachMemoryReader(mach_port_t task) : _task(task) {}

bool MachMemoryReader::read(uint64_t address, void* buffer, size_t size, size_t* bytesRead) {
    if (bytesRead) *bytesRead = 0;
    if (_task == MACH_PORT_NULL || !buffer) return false;

    mach_vm_size_t out = 0;
    kern_return_t kr = mach_vm_read_overwrite(_task,
                                              (mach_vm_address_t)address,
                                              (mach_vm_size_t)size,
                                              (mach_vm_address_t)buffer,
                                              &out);
    if (bytesRead) *bytesRead = (size_t)out;
    return kr == KERN_SUCCESS;
}

MachMemoryWriter::MachMemoryWriter(mach_port_t task) : _task(task) {}

bool MachMemoryWriter::write(uint64_t address, const void* buffer, size_t size, size_t* bytesWritten) {
    if (bytesWritten) *bytesWritten = 0;
    if (_task == MACH_PORT_NULL || !buffer) return false;

    kern_return_t kr = mach_vm_write(_task,
                                     (mach_vm_address_t)address,
                                     (vm_offset_t)buffer,
                                     (mach_msg_type_number_t)size);
    if (kr != KERN_SUCCESS) return false;
    if (bytesWritten) *bytesWritten = size;
    return true;
}

} // namespace sscore
