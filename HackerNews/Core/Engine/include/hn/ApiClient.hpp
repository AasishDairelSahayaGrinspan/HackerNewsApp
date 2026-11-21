#pragma once

#include "hn/Dispatcher.hpp"
#include "hn/Transport.hpp"
#include "hn/Types.hpp"

#include <functional>
#include <memory>
#include <optional>
#include <string>
#include <unordered_map>
#include <unordered_set>
#include <vector>

namespace hn {

/// Market-data style feed client: request coalescing, bounded in-flight
/// requests, per-request retries and ordered batch results. Every callback is
/// delivered on the engine dispatcher thread.
class ApiClient {
public:
    using ItemCallback = std::function<void(std::optional<Item>, Error)>;
    using ItemsCallback = std::function<void(std::vector<Item>)>;
    using IdsCallback = std::function<void(std::optional<std::vector<int>>, Error)>;

    ApiClient(Transport& transport,
              std::string baseUrl,
              std::shared_ptr<Dispatcher> dispatcher,
              Metrics& metrics);
    ~ApiClient();

    ApiClient(const ApiClient&) = delete;
    ApiClient& operator=(const ApiClient&) = delete;

    void fetchFeedIDs(Feed feed, IdsCallback callback);
    void fetchItems(const std::vector<int>& ids, int maxConcurrency, ItemsCallback callback);
    void fetchItem(int itemId, ItemCallback callback);
    void fetchMaxItemID(std::function<void(std::optional<int>, Error)> callback);
    void cancelAll();

    int inFlight() const { return inFlight_; }

private:
    void send(const std::string& path, int attempt, std::function<void(const HttpResponse&)> callback);
    void handleItemResponse(int itemId, const HttpResponse& response);
    std::string urlForPath(const std::string& path) const;

    Transport& transport_;
    std::string baseUrl_;
    std::shared_ptr<Dispatcher> dispatcher_;
    Metrics& metrics_;
    int inFlight_ = 0;
    std::unordered_map<int, std::vector<ItemCallback>> itemWaiters_;
};

} // namespace hn
