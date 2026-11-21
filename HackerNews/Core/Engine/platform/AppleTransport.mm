#include "hn/AppleTransport.hpp"

#import <Foundation/Foundation.h>

#include <atomic>
#include <chrono>
#include <memory>
#include <mutex>
#include <unordered_map>
#include <vector>

namespace hn {

namespace {

TransportStatus mapError(NSError* error) {
    if (!error) return TransportStatus::Ok;
    switch (error.code) {
        case NSURLErrorNotConnectedToInternet:
        case NSURLErrorNetworkConnectionLost:
        case NSURLErrorCannotConnectToHost:
        case NSURLErrorCannotFindHost:
            return TransportStatus::Offline;
        case NSURLErrorTimedOut:
            return TransportStatus::Timeout;
        case NSURLErrorCancelled:
            return TransportStatus::Cancelled;
        default:
            return TransportStatus::Other;
    }
}

} // namespace

class AppleTransport final : public Transport {
public:
    AppleTransport() {
        state_ = std::make_shared<State>();

        NSOperationQueue* queue = [[NSOperationQueue alloc] init];
        queue.maxConcurrentOperationCount = 1;
        queue.name = @"com.hacknews.engine.transport";
        queue_ = queue;

        NSURLSessionConfiguration* configuration = [NSURLSessionConfiguration ephemeralSessionConfiguration];
        configuration.timeoutIntervalForRequest = 15;
        configuration.timeoutIntervalForResource = 30;
        configuration.HTTPMaximumConnectionsPerHost = 12;
        configuration.HTTPShouldUsePipelining = YES;
        configuration.waitsForConnectivity = YES;
        configuration.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
        session_ = [NSURLSession sessionWithConfiguration:configuration delegate:nil delegateQueue:queue_];
    }

    ~AppleTransport() override {
        state_->alive.store(false, std::memory_order_release);
        cancelAll();
        [session_ invalidateAndCancel];
        session_ = nil;
    }

    uint64_t send(const HttpRequest& request, HttpCallback callback) override {
        const uint64_t requestId = ++nextId_;
        NSURL* url = [NSURL URLWithString:[NSString stringWithUTF8String:request.url.c_str()]];
        if (!url) {
            if (callback) {
                HttpResponse response;
                response.error = "invalid URL";
                response.transport = TransportStatus::Other;
                callback(std::move(response));
            }
            return requestId;
        }

        NSMutableURLRequest* urlRequest = [NSMutableURLRequest requestWithURL:url];
        urlRequest.HTTPMethod = [NSString stringWithUTF8String:request.method.c_str()];
        urlRequest.timeoutInterval = request.timeoutMs / 1000.0;
        urlRequest.cachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
        [urlRequest setValue:@"application/json" forHTTPHeaderField:@"Accept"];

        const auto started = std::chrono::steady_clock::now();
        auto state = state_;
        NSURLSessionDataTask* task =
            [session_ dataTaskWithRequest:urlRequest
                        completionHandler:^(NSData* data, NSURLResponse* response, NSError* error) {
            if (!state->alive.load(std::memory_order_acquire)) return;

            HttpResponse output;
            const auto elapsed = std::chrono::steady_clock::now() - started;
            output.latencyMs = std::chrono::duration_cast<std::chrono::milliseconds>(elapsed).count();
            output.transport = mapError(error);

            if (error) {
                output.error = error.localizedDescription.UTF8String ?: "";
                if (error.code == NSURLErrorCancelled) {
                    output.transport = TransportStatus::Cancelled;
                }
            } else {
                if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
                    output.status = static_cast<int>(((NSHTTPURLResponse*)response).statusCode);
                }
                if (data && data.length > 0) {
                    output.body.assign(reinterpret_cast<const char*>(data.bytes), data.length);
                }
            }

            {
                std::lock_guard<std::mutex> lock(state->mutex);
                state->tasks.erase(requestId);
            }
            if (callback) callback(std::move(output));
        }];

        {
            std::lock_guard<std::mutex> lock(state_->mutex);
            state_->tasks[requestId] = task;
        }
        [task resume];
        return requestId;
    }

    void cancel(uint64_t requestId) override {
        NSURLSessionDataTask* task = nil;
        {
            std::lock_guard<std::mutex> lock(state_->mutex);
            auto it = state_->tasks.find(requestId);
            if (it != state_->tasks.end()) {
                task = it->second;
                state_->tasks.erase(it);
            }
        }
        [task cancel];
    }

    void cancelAll() override {
        std::vector<NSURLSessionDataTask*> tasks;
        {
            std::lock_guard<std::mutex> lock(state_->mutex);
            tasks.reserve(state_->tasks.size());
            for (const auto& entry : state_->tasks) tasks.push_back(entry.second);
            state_->tasks.clear();
        }
        for (NSURLSessionDataTask* task : tasks) [task cancel];
    }

private:
    struct State {
        std::mutex mutex;
        std::unordered_map<uint64_t, NSURLSessionDataTask*> tasks;
        std::atomic<bool> alive{true};
    };

    NSURLSession* session_ = nil;
    NSOperationQueue* queue_ = nil;
    std::shared_ptr<State> state_;
    std::atomic<uint64_t> nextId_{0};
};

std::unique_ptr<Transport> makeAppleTransport() {
    return std::make_unique<AppleTransport>();
}

} // namespace hn
