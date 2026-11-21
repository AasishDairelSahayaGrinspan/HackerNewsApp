#pragma once

namespace hn {

/// Feed identifiers owned by the native engine. Swift never constructs API
/// paths: it only passes one of these values across the bridge.
enum class Feed : int {
    Top = 0,
    New = 1,
    Best = 2,
    Ask = 3,
    Show = 4,
    Jobs = 5
};

const char* feedPath(Feed feed);
const char* feedName(Feed feed);
const char* feedDescription(Feed feed);
Feed feedFromInt(int value);

} // namespace hn
