#include "exception_queue.h"
#include "../core/native_api.h"
#include <stdio.h>
#include <stdlib.h>
#include <chrono>
#include <ctime>
#include <sstream>
#include <iomanip>

ExceptionQueue& ExceptionQueue::instance()
{
    static ExceptionQueue instance;
    return instance;
}

void ExceptionQueue::push(const ExceptionInfo& info)
{
    std::lock_guard<std::mutex> lock(mutex_);
    queue_.push_back(info);
    cv_.notify_one();

    if (callback_)
    {
        callback_(info);
    }

    debug_log(LOG_DEBUG, "ExceptionQueue: pushed exception type=%d, thread=%llu, pc=0x%llx",
              (int)info.type, info.thread_id, info.pc_address);
}

bool ExceptionQueue::pop(ExceptionInfo& info, int timeout_ms)
{
    std::unique_lock<std::mutex> lock(mutex_);

    if (timeout_ms > 0)
    {
        cv_.wait_for(lock, std::chrono::milliseconds(timeout_ms), [this] { return !queue_.empty(); });
    }

    if (queue_.empty())
    {
        return false;
    }

    info = queue_.front();
    queue_.pop_front();
    return true;
}

std::vector<ExceptionInfo> ExceptionQueue::popAll(int timeout_ms)
{
    std::unique_lock<std::mutex> lock(mutex_);

    if (timeout_ms > 0)
    {
        cv_.wait_for(lock, std::chrono::milliseconds(timeout_ms), [this] { return !queue_.empty(); });
    }

    std::vector<ExceptionInfo> result;
    while (!queue_.empty())
    {
        result.push_back(queue_.front());
        queue_.pop_front();
    }
    return result;
}

void ExceptionQueue::clear()
{
    std::lock_guard<std::mutex> lock(mutex_);
    queue_.clear();
}

size_t ExceptionQueue::size()
{
    std::lock_guard<std::mutex> lock(mutex_);
    return queue_.size();
}

bool ExceptionQueue::empty()
{
    std::lock_guard<std::mutex> lock(mutex_);
    return queue_.empty();
}

void ExceptionQueue::setCallback(std::function<void(const ExceptionInfo&)> callback)
{
    std::lock_guard<std::mutex> lock(mutex_);
    callback_ = callback;
}

void ExceptionQueue::clearCallback()
{
    std::lock_guard<std::mutex> lock(mutex_);
    callback_ = nullptr;
}

ExceptionInfo ExceptionQueue::convertFromNative(const NativeExceptionInfo& native, pid_t pid)
{
    ExceptionInfo info;
    info.type = (int)native.exception_type;
    info.thread_id = native.thread_id;
    info.pc_address = native.regs.arm64.pc;
    info.memory_address = native.memory_address;
    info.single_step_mode = static_cast<SingleStepMode>(native.singlestep_mode);
    info.is_trace = native.is_trace != 0;
    
    if (native.architecture == ARCH_ARM64)
    {
        for (int i = 0; i < 30; i++)
        {
            info.registers.x[i] = native.regs.arm64.x[i];
        }
        info.registers.lr = native.regs.arm64.lr;
        info.registers.sp = native.regs.arm64.sp;
        info.registers.pc = native.regs.arm64.pc;
        info.registers.cpsr = native.regs.arm64.cpsr;
        info.registers.fp = native.regs.arm64.fp;
    }
    
    auto now = std::chrono::system_clock::now();
    auto now_time = std::chrono::system_clock::to_time_t(now);
    std::stringstream ss;
    ss << std::put_time(std::localtime(&now_time), "%Y-%m-%dT%H:%M:%S");
    info.timestamp = ss.str();
    
    return info;
}

std::string ExceptionQueue::toJson(const ExceptionInfo& info)
{
    std::ostringstream ss;
    ss << "{";
    ss << "\"type\":" << info.type << ",";
    ss << "\"type_str\":\"";
    switch (info.type)
    {
        case EXCEPTION_BREAKPOINT: ss << "breakpoint"; break;
        case EXCEPTION_WATCHPOINT: ss << "watchpoint"; break;
        case EXCEPTION_SINGLESTEP: ss << "singlestep"; break;
        default: ss << "unknown"; break;
    }
    ss << "\",";
    ss << "\"thread_id\":" << info.thread_id << ",";
    ss << "\"pc_address\":\"0x" << std::hex << info.pc_address << std::dec << "\",";
    ss << "\"memory_address\":\"0x" << std::hex << info.memory_address << std::dec << "\",";
    ss << "\"watchpoint_index\":" << info.watchpoint_index << ",";
    ss << "\"breakpoint_index\":" << info.breakpoint_index << ",";
    ss << "\"single_step_mode\":" << static_cast<int>(info.single_step_mode) << ",";
    ss << "\"is_trace\":" << (info.is_trace ? "true" : "false") << ",";
    
    ss << "\"registers\":{";
    for (int i = 0; i < 30; i++)
    {
        ss << "\"x" << i << "\":\"" << std::hex << info.registers.x[i] << std::dec << "\"";
        if (i < 29) ss << ",";
    }
    ss << ",\"lr\":\"" << std::hex << info.registers.lr << std::dec << "\",";
    ss << "\"sp\":\"" << std::hex << info.registers.sp << std::dec << "\",";
    ss << "\"pc\":\"" << std::hex << info.registers.pc << std::dec << "\",";
    ss << "\"cpsr\":\"" << std::hex << info.registers.cpsr << std::dec << "\",";
    ss << "\"fp\":\"" << std::hex << info.registers.fp << std::dec << "\"";
    ss << "},";
    
    ss << "\"instruction\":\"" << info.instruction << "\",";
    ss << "\"timestamp\":\"" << info.timestamp << "\"";
    ss << "}";
    return ss.str();
}

extern "C" {

void exception_queue_push(const ExceptionInfo* info)
{
    if (info)
    {
        ExceptionQueue::instance().push(*info);
    }
}

int exception_queue_pop(ExceptionInfo* out_info, int timeout_ms)
{
    if (!out_info) return 0;
    return ExceptionQueue::instance().pop(*out_info, timeout_ms) ? 1 : 0;
}

char* exception_queue_pop_all_json(int timeout_ms)
{
    auto exceptions = ExceptionQueue::instance().popAll(timeout_ms);
    if (exceptions.empty())
    {
        return nullptr;
    }

    std::ostringstream ss;
    ss << "{\"success\":true,\"exceptions\":[";
    for (size_t i = 0; i < exceptions.size(); i++)
    {
        if (i > 0) ss << ",";
        ss << ExceptionQueue::instance().toJson(exceptions[i]);
    }
    ss << "]}";

    std::string result = ss.str();
    char* cstr = (char*)malloc(result.size() + 1);
    if (cstr)
    {
        memcpy(cstr, result.c_str(), result.size() + 1);
    }
    return cstr;
}

void exception_queue_free_string(char* str)
{
    if (str)
    {
        free(str);
    }
}

void exception_queue_clear()
{
    ExceptionQueue::instance().clear();
}

int exception_queue_size()
{
    return (int)ExceptionQueue::instance().size();
}

bool send_exception_info_to_queue(const NativeExceptionInfo* info, pid_t pid)
{
    if (!info)
    {
        return false;
    }
    
    ExceptionInfo exc_info = ExceptionQueue::instance().convertFromNative(*info, pid);
    ExceptionQueue::instance().push(exc_info);
    
    debug_log(LOG_INFO, "Exception pushed to queue: type=%d, thread=%llu, pc=0x%llx",
              (int)exc_info.type, exc_info.thread_id, exc_info.pc_address);
    
    return true;
}

}
