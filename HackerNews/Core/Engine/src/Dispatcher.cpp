#include "hn/Dispatcher.hpp"

#include <chrono>

namespace hn {

Dispatcher::~Dispatcher() {
    stop();
}

void Dispatcher::start() {
    if (running_.exchange(true, std::memory_order_acq_rel)) return;
    worker_ = std::thread(&Dispatcher::workerLoop, this);
    timer_ = std::thread(&Dispatcher::timerLoop, this);
}

void Dispatcher::stop() {
    if (!running_.exchange(false, std::memory_order_acq_rel)) {
        if (worker_.joinable()) worker_.join();
        if (timer_.joinable()) timer_.join();
        return;
    }
    workCv_.notify_all();
    timerCv_.notify_all();
    if (worker_.joinable()) worker_.join();
    if (timer_.joinable()) timer_.join();

    std::lock_guard<std::mutex> lock(mutex_);
    queue_.clear();
    while (!timers_.empty()) timers_.pop();
}

bool Dispatcher::post(std::function<void()> task) {
    if (!task) return false;
    {
        std::lock_guard<std::mutex> lock(mutex_);
        if (!running_.load(std::memory_order_acquire)) return false;
        queue_.push_back(std::move(task));
    }
    workCv_.notify_one();
    return true;
}

void Dispatcher::postDelayed(int delayMs, std::function<void()> task) {
    if (!task) return;
    {
        std::lock_guard<std::mutex> lock(mutex_);
        if (!running_.load(std::memory_order_acquire)) return;
        const auto due = std::chrono::steady_clock::now() + std::chrono::milliseconds(delayMs < 0 ? 0 : delayMs);
        timers_.push(TimedTask{due, sequence_++, std::move(task)});
    }
    timerCv_.notify_one();
}

void Dispatcher::workerLoop() {
    while (true) {
        std::function<void()> task;
        {
            std::unique_lock<std::mutex> lock(mutex_);
            workCv_.wait(lock, [this] {
                return !running_.load(std::memory_order_acquire) || !queue_.empty();
            });
            if (!running_.load(std::memory_order_acquire) && queue_.empty()) return;
            if (queue_.empty()) continue;
            task = std::move(queue_.front());
            queue_.pop_front();
        }
        try {
            task();
        } catch (...) {
            // A command must never take down the dispatcher. The specific
            // command is responsible for reporting its own error state.
        }
    }
}

void Dispatcher::timerLoop() {
    std::unique_lock<std::mutex> lock(mutex_);
    while (running_.load(std::memory_order_acquire)) {
        if (timers_.empty()) {
            timerCv_.wait(lock, [this] {
                return !running_.load(std::memory_order_acquire) || !timers_.empty();
            });
            continue;
        }

        const auto due = timers_.top().due;
        if (timerCv_.wait_until(lock, due, [this, due] {
                return !running_.load(std::memory_order_acquire) || timers_.empty() || timers_.top().due < due;
            })) {
            continue;
        }
        if (!running_.load(std::memory_order_acquire)) return;

        const auto now = std::chrono::steady_clock::now();
        while (!timers_.empty() && timers_.top().due <= now) {
            auto task = timers_.top().task;
            timers_.pop();
            if (!running_.load(std::memory_order_acquire)) return;
            queue_.push_back(std::move(task));
        }
        workCv_.notify_all();
    }
}

} // namespace hn
