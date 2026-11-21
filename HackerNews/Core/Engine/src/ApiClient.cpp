#include "hn/ApiClient.hpp"

#include "hn/Json.hpp"
#include "hn/Text.hpp"

#include <algorithm>
#include <cmath>
#include <memory>
#include <unordered_set>

namespace hn {

namespace {

Error errorFromResponse(const HttpResponse& response) {
    Error error;
    if (response.transport == TransportStatus::Offline) {
        error.code = ErrorCode::Offline;
        error.message = "You're offline. Showing cached content.";
        error.retryable = true;
        return error;
    }
    if (response.transport == TransportStatus::Timeout) {
        error.code = ErrorCode::Timeout;
        error.message = "The request timed out. Please try again.";
        error.retryable = true;
        return error;
    }
    if (response.transport == TransportStatus::Cancelled) {
        error.code = ErrorCode::Cancelled;
        error.message = "Request was cancelled.";
        error.retryable = false;
        return error;
    }
    if (response.transport == TransportStatus::Other && response.status == 0) {
        error.code = ErrorCode::Unknown;
        error.message = response.error.empty() ? "Network request failed." : response.error;
        error.retryable = true;
        return error;
    }
    if (response.status < 200 || response.status >= 300) {
        error.code = ErrorCode::Http;
        error.httpStatus = response.status;
        error.message = "Server error (" + std::to_string(response.status) + "). Please try again later.";
        error.retryable = response.status == 429 || response.status >= 500;
        return error;
    }
    return error;
}

Error decodeError(const std::string& message) {
    Error error;
    error.code = ErrorCode::Decode;
    error.message = "Couldn't process the data: " + message;
    error.retryable = false;
    return error;
}

bool parseItem(const std::string& body, std::optional<Item>& out, Error& error) {
    out.reset();
    Json json;
    std::string parseError;
    if (!Json::parse(body, json, &parseError)) {
        error = decodeError(parseError);
        return false;
    }
    if (json.isNull()) {
        error.code = ErrorCode::NotFound;
        error.message = "Item not found.";
        error.retryable = false;
        return false;
    }
    if (!json.isObject()) {
        error = decodeError("expected an item object");
        return false;
    }

    const Json* id = json.find("id");
    if (!id || !id->isNumber()) {
        error = decodeError("item is missing id");
        return false;
    }

    Item item;
    item.id = id->intOr();
    if (const Json* value = json.find("type")) item.type = value->stringOr();
    if (const Json* value = json.find("by")) item.by = value->stringOr();
    if (const Json* value = json.find("title")) item.title = value->stringOr();
    if (const Json* value = json.find("url")) item.url = value->stringOr();
    if (const Json* value = json.find("text")) item.text = value->stringOr();
    if (const Json* value = json.find("time")) item.time = value->numberOr();
    if (const Json* value = json.find("score")) item.score = value->intOr();
    if (const Json* value = json.find("descendants")) item.descendants = value->intOr();
    if (const Json* value = json.find("parent")) item.parent = value->intOr();
    if (const Json* value = json.find("poll")) item.poll = value->intOr();
    if (const Json* value = json.find("deleted")) item.deleted = value->boolOr();
    if (const Json* value = json.find("dead")) item.dead = value->boolOr();

    if (const Json* kids = json.find("kids")) {
        if (kids->isArray()) {
            item.kids.reserve(kids->array.size());
            for (const auto& kid : kids->array) {
                if (kid.isNumber()) item.kids.push_back(kid.intOr());
            }
        }
    }
    if (const Json* parts = json.find("parts")) {
        if (parts->isArray()) {
            item.parts.reserve(parts->array.size());
            for (const auto& part : parts->array) {
                if (part.isNumber()) item.parts.push_back(part.intOr());
            }
        }
    }

    out = std::move(item);
    error = Error{};
    return true;
}

struct Batch {
    std::vector<int> ids;
    std::unordered_map<int, Item> items;
    std::function<void(std::vector<Item>)> done;
    size_t next = 0;
    int active = 0;
    int completed = 0;
    int maxConcurrency = 8;
};

void pumpBatch(ApiClient& api, std::shared_ptr<Batch> batch) {
    while (batch->active < batch->maxConcurrency && batch->next < batch->ids.size()) {
        const int itemId = batch->ids[batch->next++];
        ++batch->active;
        api.fetchItem(itemId, [&api, batch, itemId](std::optional<Item> item, Error) {
            --batch->active;
            if (item) batch->items[itemId] = *item;
            ++batch->completed;

            if (batch->completed >= static_cast<int>(batch->ids.size())) {
                std::vector<Item> ordered;
                ordered.reserve(batch->items.size());
                for (int wanted : batch->ids) {
                    auto it = batch->items.find(wanted);
                    if (it != batch->items.end()) ordered.push_back(it->second);
                }
                auto done = batch->done;
                batch->done = nullptr;
                if (done) done(std::move(ordered));
                return;
            }
            pumpBatch(api, batch);
        });
    }
}

} // namespace

ApiClient::ApiClient(Transport& transport,
                     std::string baseUrl,
                     std::shared_ptr<Dispatcher> dispatcher,
                     Metrics& metrics)
    : transport_(transport),
      baseUrl_(std::move(baseUrl)),
      dispatcher_(std::move(dispatcher)),
      metrics_(metrics) {
    if (!baseUrl_.empty() && baseUrl_.back() != '/') baseUrl_.push_back('/');
}

ApiClient::~ApiClient() {
    cancelAll();
}

std::string ApiClient::urlForPath(const std::string& path) const {
    return baseUrl_ + path;
}

void ApiClient::send(const std::string& path, int attempt, std::function<void(const HttpResponse&)> callback) {
    HttpRequest request;
    request.url = urlForPath(path);
    request.method = "GET";
    request.timeoutMs = 20000;

    ++inFlight_;
    metrics_.inFlight = inFlight_;

    auto dispatcher = dispatcher_;
    transport_.send(request, [this, path, attempt, callback, dispatcher](HttpResponse response) mutable {
        dispatcher->post([this, path, attempt, callback, response]() mutable {
            --inFlight_;
            if (inFlight_ < 0) inFlight_ = 0;
            metrics_.inFlight = inFlight_;
            metrics_.requests++;
            metrics_.bytesReceived += response.body.size();
            metrics_.lastLatencyMs = static_cast<double>(response.latencyMs);
            metrics_.totalLatencyMs += static_cast<double>(response.latencyMs);
            metrics_.latencySamples++;

            const Error error = errorFromResponse(response);
            if (!error && response.status >= 200 && response.status < 300) {
                callback(response);
                return;
            }

            const bool retryable = error.retryable && attempt < 2;
            if (retryable) {
                metrics_.retries++;
                const int backoff = attempt == 0 ? 350 : 800;
                dispatcher_->postDelayed(backoff, [this, path, attempt, callback] {
                    send(path, attempt + 1, callback);
                });
                return;
            }

            metrics_.failures++;
            callback(response);
        });
    });
}

void ApiClient::fetchFeedIDs(Feed feed, IdsCallback callback) {
    send(feedPath(feed), 0, [callback](const HttpResponse& response) {
        const Error responseError = errorFromResponse(response);
        if (responseError) {
            callback(std::nullopt, responseError);
            return;
        }

        Json json;
        std::string parseError;
        if (!Json::parse(response.body, json, &parseError) || !json.isArray()) {
            callback(std::nullopt, decodeError(parseError.empty() ? "expected an array of ids" : parseError));
            return;
        }

        std::vector<int> ids;
        ids.reserve(json.array.size());
        for (const auto& value : json.array) {
            if (value.isNumber()) ids.push_back(value.intOr());
        }
        if (ids.empty()) {
            Error error;
            error.code = ErrorCode::Decode;
            error.message = "Feed returned no story ids.";
            error.retryable = true;
            callback(std::nullopt, error);
            return;
        }
        callback(std::move(ids), Error{});
    });
}

void ApiClient::fetchItem(int itemId, ItemCallback callback) {
    auto existing = itemWaiters_.find(itemId);
    if (existing != itemWaiters_.end()) {
        existing->second.push_back(std::move(callback));
        return;
    }
    itemWaiters_[itemId] = {std::move(callback)};

    send(itemPath(itemId), 0, [this, itemId](const HttpResponse& response) {
        handleItemResponse(itemId, response);
    });
}

void ApiClient::handleItemResponse(int itemId, const HttpResponse& response) {
    std::optional<Item> item;
    Error error;
    const Error responseError = errorFromResponse(response);
    if (responseError) {
        error = responseError;
    } else {
        parseItem(response.body, item, error);
        if (item) metrics_.itemsParsed++;
    }

    auto waitersIt = itemWaiters_.find(itemId);
    if (waitersIt == itemWaiters_.end()) return;
    auto waiters = std::move(waitersIt->second);
    itemWaiters_.erase(waitersIt);

    for (auto& waiter : waiters) {
        if (waiter) waiter(item, error);
    }
}

void ApiClient::fetchItems(const std::vector<int>& ids, int maxConcurrency, ItemsCallback callback) {
    std::vector<int> unique;
    unique.reserve(ids.size());
    std::unordered_set<int> seen;
    seen.reserve(ids.size() * 2);
    for (int id : ids) {
        if (seen.insert(id).second) unique.push_back(id);
    }
    if (unique.empty()) {
        callback({});
        return;
    }

    auto batch = std::make_shared<Batch>();
    batch->ids = std::move(unique);
    batch->done = std::move(callback);
    batch->maxConcurrency = std::clamp(maxConcurrency, 1, 12);
    pumpBatch(*this, batch);
}

void ApiClient::fetchMaxItemID(std::function<void(std::optional<int>, Error)> callback) {
    send("maxitem.json", 0, [callback](const HttpResponse& response) {
        const Error responseError = errorFromResponse(response);
        if (responseError) {
            callback(std::nullopt, responseError);
            return;
        }
        Json json;
        std::string parseError;
        if (!Json::parse(response.body, json, &parseError) || !json.isNumber()) {
            callback(std::nullopt, decodeError(parseError.empty() ? "expected a number" : parseError));
            return;
        }
        callback(json.intOr(), Error{});
    });
}

void ApiClient::cancelAll() {
    transport_.cancelAll();
    itemWaiters_.clear();
    inFlight_ = 0;
    metrics_.inFlight = 0;
}

} // namespace hn
