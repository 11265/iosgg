/*
 * Copyright (C) 2026 kaidev
 *
 * SPDX-License-Identifier: Apache-2.0
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

/*
 * Apple-only internals shared by the Mach VM region and Mach VM read backends.
 */

#ifndef PTRSCAN_PLAT_MACH_H
#define PTRSCAN_PLAT_MACH_H

#if defined(__APPLE__)

#include <mach/mach.h>
#include <mach/vm_region.h>
#include <sys/types.h>

/*
 * mach_vm.h is macOS-only. The iPhoneOS SDK ships it as a stub whose entire
 * content is `#error mach_vm.h unsupported.`, because the mach_vm_* entry
 * points are not part of the public iOS API surface -- but libSystem still
 * exports them on iOS (they are listed in the SDK's libSystem.tbd), so on iOS
 * the two prototypes used by the backends are declared here, with the
 * signatures from the macOS header. Everywhere else the real header is used.
 */
#if defined(__has_include)
#if __has_include(<TargetConditionals.h>)
#include <TargetConditionals.h>
#endif
#endif

#ifndef TARGET_OS_IPHONE
#define TARGET_OS_IPHONE 0
#endif

#if TARGET_OS_IPHONE

extern kern_return_t mach_vm_read_overwrite(vm_map_t target_task,
                                            mach_vm_address_t address,
                                            mach_vm_size_t size,
                                            mach_vm_address_t data,
                                            mach_vm_size_t *outsize);

extern kern_return_t mach_vm_region_recurse(vm_map_t target_task,
                                            mach_vm_address_t *address,
                                            mach_vm_size_t *size,
                                            natural_t *nesting_depth,
                                            vm_region_recurse_info_t info,
                                            mach_msg_type_number_t *infoCnt);

/*
 * The non-recursive variant. It reports the top-level map entry for an address
 * -- a plain lookup plus "the next entry", with no submap descent -- which is
 * what makes it the fallback when the recursive call does not come back.
 */
extern kern_return_t mach_vm_region(vm_map_t target_task,
                                    mach_vm_address_t *address,
                                    mach_vm_size_t *size,
                                    vm_region_flavor_t flavor,
                                    vm_region_info_t info,
                                    mach_msg_type_number_t *infoCnt,
                                    mach_port_t *object_name);

/* plat_map_fixed(), the self-test's fixed target address. */
extern kern_return_t mach_vm_allocate(vm_map_t target_task,
                                      mach_vm_address_t *address,
                                      mach_vm_size_t size,
                                      int flags);

#else

#include <mach/mach_vm.h>

#endif

/*
 * Cached task port for `pid`, or MACH_PORT_NULL when the process cannot be
 * inspected. The port is cached because task_for_pid() is expensive and the
 * index builder calls the reader from every worker thread.
 *
 * On failure errno is set to a value derived from the kern_return_t.
 */
mach_port_t plat_mach_task(pid_t pid);

/* Drop the cached task port if it belongs to `pid`. */
void plat_mach_task_release(pid_t pid);

/* Map a kern_return_t onto an errno value. */
int plat_mach_errno(kern_return_t kr);

#endif /* __APPLE__ */

#endif /* PTRSCAN_PLAT_MACH_H */
