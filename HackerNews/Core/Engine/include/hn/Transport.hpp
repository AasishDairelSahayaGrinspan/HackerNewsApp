#pragma once

#include <cstdint>
#include <functional>
#include <string>

namespace hn {

enum class TransportStatus : int {
    Ok = 0,
    Offline = 1,
    Timeout = 2,
    Cancelled = 3,
    Other = 4
};

struct HttpRequest {
    std::string url;
    std::string method = "GET";
    int timeoutMs = 20000;
};

struct HttpResponse {
    int status = 0;
    std::string body;
    std::string error;
    TransportStatus transport = TransportStatus::Ok;
    int64_t latencyMs = 0;
};

using HttpCallback = std::function<void(HttpResponse)>;

/// Platform boundary. The engine owns retry, coalescing, parsing and
/// scheduling; the platform only performs the HTTP exchange.
class Transport {
public:
    virtual ~Transport() = default;
    virtual uint64_t send(const HttpRequest& request, HttpCallback callback) = 0;
    virtual void cancel(uint64_t requestId) = 0;
    virtual void cancelAll() = 0;
};

} // namespace hn
