#pragma once

#include "hn/Types.hpp"

#include <vector>

namespace hn {

/// Builds the nested comment tree from flat rows. Root ordering comes from
/// the story's `kids` array; missing roots fall back to parent inference.
/// Cycles are broken with a visited set and a hard depth guard.
std::vector<CommentNode> buildCommentTree(const std::vector<Comment>& comments,
                                          const std::vector<int>& rootKids,
                                          int maxDepth = 32);

int countCommentNodes(const std::vector<CommentNode>& roots);

} // namespace hn
