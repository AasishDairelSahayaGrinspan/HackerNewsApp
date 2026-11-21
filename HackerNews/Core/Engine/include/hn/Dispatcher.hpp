#pragma once

#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstdint>
#include <deque>
#include <functional>
#include <mutex>
#include <queue>
#include <thread>
#include <vector>

namespace hn {

/// Single-consumer command loop with a delayed-task timer. This is the
/// engine's "matching thread": all mutable state is touched here, so state
/// transitions are deterministic and lock-free from the engine's point of
/// view. Network callbacks only enqueue work.
class Dispatcher {
public:
    Dispatcher() = default;
    ~Dispatcher();

    Dispatcher(const Dispatcher&) = delete;
    Dispatcher& operator=(const Dispatcher&) = delete;

    void start();
    void stop();
    bool isRunning() const { return running_.load(std::memory_order_acquire); }

    bool post(std::function<void()> task);
    void postDelayed(int delayMs, std::function<void()> task);

private:
    struct TimedTask {
        std::chrono::steady_clock::time_point due;
        uint64_t sequence = 0;
        std::function<void()> task;
    };

    struct TimedCompare {
        bool operator()(const TimedTask& a, const TimedTask& b) const {
            if (a.due != b.due) return a.due > b.due;
            return a.sequence > b.sequence;
        }
    };

    void workerLoop();
    void timerLoop();

    mutable std::mutex mutex_;
    std::condition_variable workCv_;
    std::condition_variable timerCv_;
    std::deque<std::function<void()>> queue_;
    std::priority_queue<TimedTask, std::vector<TimedTask>, TimedCompare> timers_;
    std::atomic<bool> running_{false};
    std::thread worker_;
    std::thread timer_;
    uint64_t sequence_ = 0;
};

} // namespace hn
