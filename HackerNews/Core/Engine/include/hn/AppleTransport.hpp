#pragma once

#include "hn/Transport.hpp"

#include <memory>

namespace hn {

/// Creates the Apple URLSession transport. The implementation lives in
/// AppleTransport.mm so the rest of the engine stays platform-neutral.
std::unique_ptr<Transport> makeAppleTransport();

} // namespace hn
