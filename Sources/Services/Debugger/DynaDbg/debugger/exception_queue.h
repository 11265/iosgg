#ifndef EXCEPTION_QUEUE_H
#define EXCEPTION_QUEUE_H

#include "debugger_types.h"
#include "../common/exception_info.h"
#include <atomic>
#include <condition_variable>
#include <deque>
#include <functional>
#include <mutex>
#include <string>

class ExceptionQueue
{
public:
    static ExceptionQueue& instance();

    void push(const ExceptionInfo& info);
    bool pop(ExceptionInfo& info, int timeout_ms = 0);
    std::vector<ExceptionInfo> popAll(int timeout_ms = 0);
    void clear();
    size_t size();
    bool empty();

    void setCallback(std::function<void(const ExceptionInfo&)> callback);
    void clearCallback();

    std::string toJson(const ExceptionInfo& info);
    
    ExceptionInfo convertFromNative(const NativeExceptionInfo& native, pid_t pid);

private:
    ExceptionQueue() = default;
    ~ExceptionQueue() = default;
    ExceptionQueue(const ExceptionQueue&) = delete;
    ExceptionQueue& operator=(const ExceptionQueue&) = delete;

    std::deque<ExceptionInfo> queue_;
    std::mutex mutex_;
    std::condition_variable cv_;
    std::function<void(const ExceptionInfo&)> callback_;
};

extern "C" {
    void exception_queue_push(const ExceptionInfo* info);
    int exception_queue_pop(ExceptionInfo* out_info, int timeout_ms);
    char* exception_queue_pop_all_json(int timeout_ms);
    void exception_queue_free_string(char* str);
    void exception_queue_clear();
    int exception_queue_size();
    
    bool send_exception_info_to_queue(const NativeExceptionInfo* info, pid_t pid);
}

#endif
