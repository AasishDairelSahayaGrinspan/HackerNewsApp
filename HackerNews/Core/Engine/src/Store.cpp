#include "hn/Store.hpp"

#include "hn/Json.hpp"
#include "hn/Text.hpp"

#include <sqlite3.h>

#include <sys/stat.h>

#include <algorithm>
#include <cstdio>
#include <cstring>
#include <unordered_set>

namespace hn {

namespace {

struct Stmt {
    sqlite3_stmt* stmt = nullptr;
    ~Stmt() {
        if (stmt) sqlite3_finalize(stmt);
    }
};

std::string columnText(sqlite3_stmt* stmt, int index) {
    const unsigned char* text = sqlite3_column_text(stmt, index);
    return text ? reinterpret_cast<const char*>(text) : "";
}

std::vector<int> columnIntArray(sqlite3_stmt* stmt, int index) {
    std::vector<int> values;
    parseIntArray(columnText(stmt, index), values);
    return values;
}

void bindText(sqlite3_stmt* stmt, int index, const std::string& value) {
    sqlite3_bind_text(stmt, index, value.c_str(), static_cast<int>(value.size()), SQLITE_TRANSIENT);
}

Story readStoryRow(sqlite3_stmt* stmt) {
    Story story;
    story.id = sqlite3_column_int(stmt, 0);
    story.type = columnText(stmt, 1);
    story.title = columnText(stmt, 2);
    story.author = columnText(stmt, 3);
    story.createdAt = sqlite3_column_double(stmt, 4);
    story.score = sqlite3_column_int(stmt, 5);
    story.url = columnText(stmt, 6);
    story.text = columnText(stmt, 7);
    story.commentCount = sqlite3_column_int(stmt, 8);
    story.dead = sqlite3_column_int(stmt, 9) != 0;
    story.deleted = sqlite3_column_int(stmt, 10) != 0;
    story.fetchedAt = sqlite3_column_double(stmt, 11);
    story.kids = columnIntArray(stmt, 12);
    story.parts = columnIntArray(stmt, 13);
    story.domain = domainFromURL(story.url);
    story.timeAgo = timeAgoFromUnix(story.createdAt);
    return story;
}

Comment readCommentRow(sqlite3_stmt* stmt) {
    Comment comment;
    comment.id = sqlite3_column_int(stmt, 0);
    comment.storyId = sqlite3_column_int(stmt, 1);
    comment.parentId = sqlite3_column_int(stmt, 2);
    comment.author = columnText(stmt, 3);
    comment.text = columnText(stmt, 4);
    comment.createdAt = sqlite3_column_double(stmt, 5);
    comment.dead = sqlite3_column_int(stmt, 6) != 0;
    comment.deleted = sqlite3_column_int(stmt, 7) != 0;
    comment.kids = columnIntArray(stmt, 8);
    comment.fetchedAt = sqlite3_column_double(stmt, 9);
    return comment;
}

constexpr const char* kStoryColumns =
    "id, type, title, author, created_at, score, url, text, comment_count, dead, deleted, fetched_at, kids, parts";

constexpr const char* kCommentColumns =
    "id, story_id, parent_id, author, text, created_at, dead, deleted, kids, fetched_at";

} // namespace

Store::Store() = default;

Store::~Store() {
    close();
}

bool Store::open(const std::string& path, std::string* error) {
    std::lock_guard<std::mutex> lock(mutex_);
    if (db_) {
        sqlite3_close_v2(db_);
        db_ = nullptr;
    }
    path_ = path;
    lastError_.clear();

    int flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX;
    if (sqlite3_open_v2(path.c_str(), &db_, flags, nullptr) != SQLITE_OK) {
        setError(db_ ? sqlite3_errmsg(db_) : "unable to open database");
        if (error) *error = lastError_;
        if (db_) {
            sqlite3_close_v2(db_);
            db_ = nullptr;
        }
        return false;
    }

    sqlite3_busy_timeout(db_, 3000);
    exec("PRAGMA journal_mode=WAL;");
    exec("PRAGMA synchronous=NORMAL;");
    exec("PRAGMA foreign_keys=ON;");
    exec("PRAGMA temp_store=MEMORY;");

    if (!ensureSchema(error)) {
        sqlite3_close_v2(db_);
        db_ = nullptr;
        return false;
    }
    return true;
}

void Store::close() {
    std::lock_guard<std::mutex> lock(mutex_);
    if (db_) {
        sqlite3_close_v2(db_);
        db_ = nullptr;
    }
}

bool Store::isOpen() const {
    std::lock_guard<std::mutex> lock(mutex_);
    return db_ != nullptr;
}

bool Store::exec(const char* sql, std::string* error) const {
    char* message = nullptr;
    if (sqlite3_exec(db_, sql, nullptr, nullptr, &message) != SQLITE_OK) {
        lastError_ = message ? message : "sqlite error";
        if (message) sqlite3_free(message);
        if (error) *error = lastError_;
        return false;
    }
    return true;
}

bool Store::ensureSchema(std::string* error) {
    const char* schema = R"SQL(
        CREATE TABLE IF NOT EXISTS stories (
            id INTEGER PRIMARY KEY,
            type TEXT NOT NULL DEFAULT '',
            title TEXT NOT NULL DEFAULT '',
            author TEXT NOT NULL DEFAULT '',
            created_at REAL NOT NULL DEFAULT 0,
            score INTEGER NOT NULL DEFAULT 0,
            url TEXT NOT NULL DEFAULT '',
            text TEXT NOT NULL DEFAULT '',
            comment_count INTEGER NOT NULL DEFAULT 0,
            dead INTEGER NOT NULL DEFAULT 0,
            deleted INTEGER NOT NULL DEFAULT 0,
            fetched_at REAL NOT NULL DEFAULT 0,
            kids TEXT NOT NULL DEFAULT '[]',
            parts TEXT NOT NULL DEFAULT '[]'
        );
        CREATE INDEX IF NOT EXISTS idx_stories_fetched ON stories(fetched_at);

        CREATE TABLE IF NOT EXISTS comments (
            id INTEGER PRIMARY KEY,
            story_id INTEGER NOT NULL,
            parent_id INTEGER NOT NULL DEFAULT 0,
            author TEXT NOT NULL DEFAULT '',
            text TEXT NOT NULL DEFAULT '',
            created_at REAL NOT NULL DEFAULT 0,
            dead INTEGER NOT NULL DEFAULT 0,
            deleted INTEGER NOT NULL DEFAULT 0,
            kids TEXT NOT NULL DEFAULT '[]',
            fetched_at REAL NOT NULL DEFAULT 0
        );
        CREATE INDEX IF NOT EXISTS idx_comments_story ON comments(story_id);

        CREATE TABLE IF NOT EXISTS saved (
            story_id INTEGER PRIMARY KEY,
            saved_at REAL NOT NULL,
            title TEXT NOT NULL DEFAULT '',
            author TEXT NOT NULL DEFAULT '',
            url TEXT NOT NULL DEFAULT '',
            score INTEGER NOT NULL DEFAULT 0
        );

        CREATE TABLE IF NOT EXISTS feed_meta (
            feed INTEGER PRIMARY KEY,
            fetched_at REAL NOT NULL DEFAULT 0,
            ids TEXT NOT NULL DEFAULT '[]'
        );

        PRAGMA user_version = 1;
    )SQL";
    return exec(schema, error);
}

void Store::setError(const std::string& message) const {
    lastError_ = message;
}

bool Store::upsertStory(const Story& story) {
    return upsertStories({story});
}

bool Store::upsertStories(const std::vector<Story>& stories) {
    if (stories.empty()) return true;
    std::lock_guard<std::mutex> lock(mutex_);
    if (!db_) return false;

    if (!exec("BEGIN IMMEDIATE;")) return false;

    Stmt stmt;
    const char* sql = R"SQL(
        INSERT INTO stories
            (id, type, title, author, created_at, score, url, text, comment_count, dead, deleted, fetched_at, kids, parts)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            type=excluded.type,
            title=excluded.title,
            author=excluded.author,
            created_at=excluded.created_at,
            score=excluded.score,
            url=excluded.url,
            text=excluded.text,
            comment_count=excluded.comment_count,
            dead=excluded.dead,
            deleted=excluded.deleted,
            fetched_at=excluded.fetched_at,
            kids=excluded.kids,
            parts=excluded.parts
    )SQL";
    if (sqlite3_prepare_v2(db_, sql, -1, &stmt.stmt, nullptr) != SQLITE_OK) {
        setError(sqlite3_errmsg(db_));
        exec("ROLLBACK;");
        return false;
    }

    for (const auto& story : stories) {        sqlite3_reset(stmt.stmt);
        sqlite3_clear_bindings(stmt.stmt);
        sqlite3_bind_int(stmt.stmt, 1, story.id);
        bindText(stmt.stmt, 2, story.type);
        bindText(stmt.stmt, 3, story.title);
        bindText(stmt.stmt, 4, story.author);
        sqlite3_bind_double(stmt.stmt, 5, story.createdAt);
        sqlite3_bind_int(stmt.stmt, 6, story.score);
        bindText(stmt.stmt, 7, story.url);
        bindText(stmt.stmt, 8, story.text);
        sqlite3_bind_int(stmt.stmt, 9, story.commentCount);
        sqlite3_bind_int(stmt.stmt, 10, story.dead ? 1 : 0);
        sqlite3_bind_int(stmt.stmt, 11, story.deleted ? 1 : 0);
        sqlite3_bind_double(stmt.stmt, 12, story.fetchedAt);
        bindText(stmt.stmt, 13, jsonIntArray(story.kids));
        bindText(stmt.stmt, 14, jsonIntArray(story.parts));
        if (sqlite3_step(stmt.stmt) != SQLITE_DONE) {
            setError(sqlite3_errmsg(db_));
            exec("ROLLBACK;");
            return false;
        }
    }

    if (!exec("COMMIT;")) {
        exec("ROLLBACK;");
        return false;
    }
    return true;
}

std::optional<Story> Store::story(int storyId) const {
    std::lock_guard<std::mutex> lock(mutex_);
    if (!db_) return std::nullopt;

    Stmt stmt;
    const std::string sql = std::string("SELECT ") + kStoryColumns + " FROM stories WHERE id = ? LIMIT 1";
    if (sqlite3_prepare_v2(db_, sql.c_str(), -1, &stmt.stmt, nullptr) != SQLITE_OK) return std::nullopt;
    sqlite3_bind_int(stmt.stmt, 1, storyId);
    if (sqlite3_step(stmt.stmt) != SQLITE_ROW) return std::nullopt;
    return readStoryRow(stmt.stmt);
}

std::vector<Story> Store::stories(const std::vector<int>& ids) const {
    std::vector<Story> result;
    if (ids.empty()) return result;
    std::lock_guard<std::mutex> lock(mutex_);
    if (!db_) return result;

    Stmt stmt;
    const std::string sql = std::string("SELECT ") + kStoryColumns + " FROM stories WHERE id = ? LIMIT 1";
    if (sqlite3_prepare_v2(db_, sql.c_str(), -1, &stmt.stmt, nullptr) != SQLITE_OK) return result;

    result.reserve(ids.size());
    for (int id : ids) {
        sqlite3_reset(stmt.stmt);
        sqlite3_clear_bindings(stmt.stmt);
        sqlite3_bind_int(stmt.stmt, 1, id);
        if (sqlite3_step(stmt.stmt) == SQLITE_ROW) {
            result.push_back(readStoryRow(stmt.stmt));
        }
    }
    return result;
}

std::vector<Story> Store::allStories() const {
    std::vector<Story> result;
    std::lock_guard<std::mutex> lock(mutex_);
    if (!db_) return result;

    Stmt stmt;
    const std::string sql = std::string("SELECT ") + kStoryColumns + " FROM stories ORDER BY fetched_at DESC";
    if (sqlite3_prepare_v2(db_, sql.c_str(), -1, &stmt.stmt, nullptr) != SQLITE_OK) return result;
    while (sqlite3_step(stmt.stmt) == SQLITE_ROW) {
        result.push_back(readStoryRow(stmt.stmt));
    }
    return result;
}

bool Store::setFeedMeta(const FeedMeta& meta) {
    std::lock_guard<std::mutex> lock(mutex_);
    if (!db_) return false;

    Stmt stmt;
    const char* sql = R"SQL(
        INSERT INTO feed_meta (feed, fetched_at, ids) VALUES (?, ?, ?)
        ON CONFLICT(feed) DO UPDATE SET fetched_at=excluded.fetched_at, ids=excluded.ids
    )SQL";
    if (sqlite3_prepare_v2(db_, sql, -1, &stmt.stmt, nullptr) != SQLITE_OK) {
        setError(sqlite3_errmsg(db_));
        return false;
    }
    sqlite3_bind_int(stmt.stmt, 1, static_cast<int>(meta.feed));
    sqlite3_bind_double(stmt.stmt, 2, meta.fetchedAt);
    bindText(stmt.stmt, 3, jsonIntArray(meta.ids));
    if (sqlite3_step(stmt.stmt) != SQLITE_DONE) {
        setError(sqlite3_errmsg(db_));
        return false;
    }
    return true;
}

std::optional<FeedMeta> Store::feedMeta(Feed feed) const {
    std::lock_guard<std::mutex> lock(mutex_);
    if (!db_) return std::nullopt;

    Stmt stmt;
    const char* sql = "SELECT feed, fetched_at, ids FROM feed_meta WHERE feed = ? LIMIT 1";
    if (sqlite3_prepare_v2(db_, sql, -1, &stmt.stmt, nullptr) != SQLITE_OK) return std::nullopt;
    sqlite3_bind_int(stmt.stmt, 1, static_cast<int>(feed));
    if (sqlite3_step(stmt.stmt) != SQLITE_ROW) return std::nullopt;

    FeedMeta meta;
    meta.feed = feedFromInt(sqlite3_column_int(stmt.stmt, 0));
    meta.fetchedAt = sqlite3_column_double(stmt.stmt, 1);
    parseIntArray(columnText(stmt.stmt, 2), meta.ids);
    return meta;
}

bool Store::upsertComments(const std::vector<Comment>& comments) {
    if (comments.empty()) return true;
    std::lock_guard<std::mutex> lock(mutex_);
    if (!db_) return false;

    if (!exec("BEGIN IMMEDIATE;")) return false;

    Stmt stmt;
    const char* sql = R"SQL(
        INSERT INTO comments
            (id, story_id, parent_id, author, text, created_at, dead, deleted, kids, fetched_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            story_id=excluded.story_id,
            parent_id=excluded.parent_id,
            author=excluded.author,
            text=excluded.text,
            created_at=excluded.created_at,
            dead=excluded.dead,
            deleted=excluded.deleted,
            kids=excluded.kids,
            fetched_at=excluded.fetched_at
    )SQL";
    if (sqlite3_prepare_v2(db_, sql, -1, &stmt.stmt, nullptr) != SQLITE_OK) {
        setError(sqlite3_errmsg(db_));
        exec("ROLLBACK;");
        return false;
    }

    for (const auto& comment : comments) {
        sqlite3_reset(stmt.stmt);
        sqlite3_clear_bindings(stmt.stmt);
        sqlite3_bind_int(stmt.stmt, 1, comment.id);
        sqlite3_bind_int(stmt.stmt, 2, comment.storyId);
        sqlite3_bind_int(stmt.stmt, 3, comment.parentId);
        bindText(stmt.stmt, 4, comment.author);
        bindText(stmt.stmt, 5, comment.text);
        sqlite3_bind_double(stmt.stmt, 6, comment.createdAt);
        sqlite3_bind_int(stmt.stmt, 7, comment.dead ? 1 : 0);
        sqlite3_bind_int(stmt.stmt, 8, comment.deleted ? 1 : 0);
        bindText(stmt.stmt, 9, jsonIntArray(comment.kids));
        sqlite3_bind_double(stmt.stmt, 10, comment.fetchedAt);
        if (sqlite3_step(stmt.stmt) != SQLITE_DONE) {
            setError(sqlite3_errmsg(db_));
            exec("ROLLBACK;");
            return false;
        }
    }

    if (!exec("COMMIT;")) {
        exec("ROLLBACK;");
        return false;
    }
    return true;
}

std::vector<Comment> Store::comments(int storyId) const {
    std::vector<Comment> result;
    std::lock_guard<std::mutex> lock(mutex_);
    if (!db_) return result;

    Stmt stmt;
    const std::string sql = std::string("SELECT ") + kCommentColumns +
                            " FROM comments WHERE story_id = ? ORDER BY id ASC";
    if (sqlite3_prepare_v2(db_, sql.c_str(), -1, &stmt.stmt, nullptr) != SQLITE_OK) return result;
    sqlite3_bind_int(stmt.stmt, 1, storyId);
    while (sqlite3_step(stmt.stmt) == SQLITE_ROW) {
        result.push_back(readCommentRow(stmt.stmt));
    }
    return result;
}

bool Store::setSaved(int storyId, bool saved, const Story* story) {
    std::lock_guard<std::mutex> lock(mutex_);
    if (!db_) return false;

    if (!saved) {
        Stmt stmt;
        if (sqlite3_prepare_v2(db_, "DELETE FROM saved WHERE story_id = ?", -1, &stmt.stmt, nullptr) != SQLITE_OK) {
            setError(sqlite3_errmsg(db_));
            return false;
        }
        sqlite3_bind_int(stmt.stmt, 1, storyId);
        return sqlite3_step(stmt.stmt) == SQLITE_DONE;
    }

    Stmt stmt;
    const char* sql = R"SQL(
        INSERT INTO saved (story_id, saved_at, title, author, url, score)
        VALUES (?, ?, ?, ?, ?, ?)
        ON CONFLICT(story_id) DO UPDATE SET
            saved_at=excluded.saved_at,
            title=CASE WHEN excluded.title <> '' THEN excluded.title ELSE saved.title END,
            author=CASE WHEN excluded.author <> '' THEN excluded.author ELSE saved.author END,
            url=CASE WHEN excluded.url <> '' THEN excluded.url ELSE saved.url END,
            score=CASE WHEN excluded.score <> 0 THEN excluded.score ELSE saved.score END
    )SQL";
    if (sqlite3_prepare_v2(db_, sql, -1, &stmt.stmt, nullptr) != SQLITE_OK) {
        setError(sqlite3_errmsg(db_));
        return false;
    }
    sqlite3_bind_int(stmt.stmt, 1, storyId);
    sqlite3_bind_double(stmt.stmt, 2, nowUnix());
    bindText(stmt.stmt, 3, story ? story->title : "");
    bindText(stmt.stmt, 4, story ? story->author : "");
    bindText(stmt.stmt, 5, story ? story->url : "");
    sqlite3_bind_int(stmt.stmt, 6, story ? story->score : 0);
    if (sqlite3_step(stmt.stmt) != SQLITE_DONE) {
        setError(sqlite3_errmsg(db_));
        return false;
    }
    return true;
}

std::optional<SavedStory> Store::savedStory(int storyId) const {
    std::lock_guard<std::mutex> lock(mutex_);
    if (!db_) return std::nullopt;

    Stmt stmt;
    const char* sql = R"SQL(
        SELECT s.story_id, s.saved_at,
               CASE WHEN st.title <> '' THEN st.title ELSE s.title END,
               CASE WHEN st.author <> '' THEN st.author ELSE s.author END,
               CASE WHEN st.url <> '' THEN st.url ELSE s.url END,
               CASE WHEN st.score <> 0 THEN st.score ELSE s.score END
        FROM saved s LEFT JOIN stories st ON st.id = s.story_id
        WHERE s.story_id = ? LIMIT 1
    )SQL";
    if (sqlite3_prepare_v2(db_, sql, -1, &stmt.stmt, nullptr) != SQLITE_OK) return std::nullopt;
    sqlite3_bind_int(stmt.stmt, 1, storyId);
    if (sqlite3_step(stmt.stmt) != SQLITE_ROW) return std::nullopt;

    SavedStory saved;
    saved.storyId = sqlite3_column_int(stmt.stmt, 0);
    saved.savedAt = sqlite3_column_double(stmt.stmt, 1);
    saved.title = columnText(stmt.stmt, 2);
    saved.author = columnText(stmt.stmt, 3);
    saved.url = columnText(stmt.stmt, 4);
    saved.score = sqlite3_column_int(stmt.stmt, 5);
    saved.domain = domainFromURL(saved.url);
    return saved;
}

std::vector<SavedStory> Store::savedStories() const {
    std::vector<SavedStory> result;
    std::lock_guard<std::mutex> lock(mutex_);
    if (!db_) return result;

    Stmt stmt;
    const char* sql = R"SQL(
        SELECT s.story_id, s.saved_at,
               CASE WHEN st.title <> '' THEN st.title ELSE s.title END,
               CASE WHEN st.author <> '' THEN st.author ELSE s.author END,
               CASE WHEN st.url <> '' THEN st.url ELSE s.url END,
               CASE WHEN st.score <> 0 THEN st.score ELSE s.score END
        FROM saved s LEFT JOIN stories st ON st.id = s.story_id
        ORDER BY s.saved_at DESC
    )SQL";
    if (sqlite3_prepare_v2(db_, sql, -1, &stmt.stmt, nullptr) != SQLITE_OK) return result;
    while (sqlite3_step(stmt.stmt) == SQLITE_ROW) {
        SavedStory saved;
        saved.storyId = sqlite3_column_int(stmt.stmt, 0);
        saved.savedAt = sqlite3_column_double(stmt.stmt, 1);
        saved.title = columnText(stmt.stmt, 2);
        saved.author = columnText(stmt.stmt, 3);
        saved.url = columnText(stmt.stmt, 4);
        saved.score = sqlite3_column_int(stmt.stmt, 5);
        saved.domain = domainFromURL(saved.url);
        result.push_back(std::move(saved));
    }
    return result;
}

std::unordered_set<int> Store::savedIds() const {
    std::unordered_set<int> result;
    std::lock_guard<std::mutex> lock(mutex_);
    if (!db_) return result;

    Stmt stmt;
    if (sqlite3_prepare_v2(db_, "SELECT story_id FROM saved", -1, &stmt.stmt, nullptr) != SQLITE_OK) return result;
    while (sqlite3_step(stmt.stmt) == SQLITE_ROW) {
        result.insert(sqlite3_column_int(stmt.stmt, 0));
    }
    return result;
}

int Store::countStories() const {
    std::lock_guard<std::mutex> lock(mutex_);
    if (!db_) return 0;
    Stmt stmt;
    if (sqlite3_prepare_v2(db_, "SELECT COUNT(*) FROM stories", -1, &stmt.stmt, nullptr) != SQLITE_OK) return 0;
    return sqlite3_step(stmt.stmt) == SQLITE_ROW ? sqlite3_column_int(stmt.stmt, 0) : 0;
}

int Store::countComments() const {
    std::lock_guard<std::mutex> lock(mutex_);
    if (!db_) return 0;
    Stmt stmt;
    if (sqlite3_prepare_v2(db_, "SELECT COUNT(*) FROM comments", -1, &stmt.stmt, nullptr) != SQLITE_OK) return 0;
    return sqlite3_step(stmt.stmt) == SQLITE_ROW ? sqlite3_column_int(stmt.stmt, 0) : 0;
}

int Store::countSaved() const {
    std::lock_guard<std::mutex> lock(mutex_);
    if (!db_) return 0;
    Stmt stmt;
    if (sqlite3_prepare_v2(db_, "SELECT COUNT(*) FROM saved", -1, &stmt.stmt, nullptr) != SQLITE_OK) return 0;
    return sqlite3_step(stmt.stmt) == SQLITE_ROW ? sqlite3_column_int(stmt.stmt, 0) : 0;
}

int64_t Store::databaseBytes() const {
    std::lock_guard<std::mutex> lock(mutex_);
    if (!db_) return 0;
    if (path_ == ":memory:") {
        int pageCount = 0;
        int pageSize = 0;
        Stmt a;
        Stmt b;
        if (sqlite3_prepare_v2(db_, "PRAGMA page_count", -1, &a.stmt, nullptr) == SQLITE_OK &&
            sqlite3_step(a.stmt) == SQLITE_ROW) {
            pageCount = sqlite3_column_int(a.stmt, 0);
        }
        if (sqlite3_prepare_v2(db_, "PRAGMA page_size", -1, &b.stmt, nullptr) == SQLITE_OK &&
            sqlite3_step(b.stmt) == SQLITE_ROW) {
            pageSize = sqlite3_column_int(b.stmt, 0);
        }
        return static_cast<int64_t>(pageCount) * pageSize;
    }

    int64_t total = 0;
    for (const char* suffix : {"", "-wal", "-shm"}) {
        struct stat info;
        const std::string file = path_ + suffix;
        if (stat(file.c_str(), &info) == 0) total += info.st_size;
    }
    return total;
}

bool Store::evict(int maxFeedItems, double maxAgeSeconds) {
    std::lock_guard<std::mutex> lock(mutex_);
    if (!db_) return false;

    const double cutoff = nowUnix() - maxAgeSeconds;
    std::unordered_set<int> keep;

    {
        Stmt saved;
        if (sqlite3_prepare_v2(db_, "SELECT story_id FROM saved", -1, &saved.stmt, nullptr) == SQLITE_OK) {
            while (sqlite3_step(saved.stmt) == SQLITE_ROW) keep.insert(sqlite3_column_int(saved.stmt, 0));
        }
    }
    {
        Stmt recent;
        const char* sql = "SELECT id FROM stories WHERE fetched_at >= ?";
        if (sqlite3_prepare_v2(db_, sql, -1, &recent.stmt, nullptr) == SQLITE_OK) {
            sqlite3_bind_double(recent.stmt, 1, cutoff);
            while (sqlite3_step(recent.stmt) == SQLITE_ROW) keep.insert(sqlite3_column_int(recent.stmt, 0));
        }
    }
    {
        Stmt meta;
        if (sqlite3_prepare_v2(db_, "SELECT feed, ids FROM feed_meta", -1, &meta.stmt, nullptr) == SQLITE_OK) {
            while (sqlite3_step(meta.stmt) == SQLITE_ROW) {
                std::vector<int> ids;
                parseIntArray(columnText(meta.stmt, 1), ids);
                const int limit = std::min<int>(maxFeedItems, static_cast<int>(ids.size()));
                for (int i = 0; i < limit; ++i) keep.insert(ids[i]);
            }
        }
    }

    std::vector<int> allIds;
    {
        Stmt all;
        if (sqlite3_prepare_v2(db_, "SELECT id FROM stories", -1, &all.stmt, nullptr) != SQLITE_OK) return false;
        while (sqlite3_step(all.stmt) == SQLITE_ROW) allIds.push_back(sqlite3_column_int(all.stmt, 0));
    }

    if (!exec("BEGIN IMMEDIATE;")) return false;

    Stmt remove;
    if (sqlite3_prepare_v2(db_, "DELETE FROM stories WHERE id = ?", -1, &remove.stmt, nullptr) != SQLITE_OK) {
        setError(sqlite3_errmsg(db_));
        exec("ROLLBACK;");
        return false;
    }
    for (int id : allIds) {
        if (keep.count(id)) continue;
        sqlite3_reset(remove.stmt);
        sqlite3_bind_int(remove.stmt, 1, id);
        if (sqlite3_step(remove.stmt) != SQLITE_DONE) {
            setError(sqlite3_errmsg(db_));
            exec("ROLLBACK;");
            return false;
        }
    }

    if (!exec("DELETE FROM comments WHERE story_id NOT IN (SELECT id FROM stories) "
              "AND story_id NOT IN (SELECT story_id FROM saved);")) {
        exec("ROLLBACK;");
        return false;
    }

    if (!exec("COMMIT;")) {
        exec("ROLLBACK;");
        return false;
    }
    return true;
}

bool Store::clear(bool keepSaved) {
    std::lock_guard<std::mutex> lock(mutex_);
    if (!db_) return false;
    if (!exec("BEGIN IMMEDIATE;")) return false;

    bool ok = true;
    if (keepSaved) {
        ok = exec("DELETE FROM stories WHERE id NOT IN (SELECT story_id FROM saved);") &&
             exec("DELETE FROM comments WHERE story_id NOT IN (SELECT id FROM stories) "
                  "AND story_id NOT IN (SELECT story_id FROM saved);") &&
             exec("DELETE FROM feed_meta;");
    } else {
        ok = exec("DELETE FROM comments;") &&
             exec("DELETE FROM stories;") &&
             exec("DELETE FROM saved;") &&
             exec("DELETE FROM feed_meta;");
    }

    if (!ok || !exec("COMMIT;")) {
        exec("ROLLBACK;");
        return false;
    }
    return true;
}

bool Store::vacuum() {
    std::lock_guard<std::mutex> lock(mutex_);
    if (!db_) return false;
    return exec("VACUUM;");
}

std::string Store::lastError() const {
    std::lock_guard<std::mutex> lock(mutex_);
    return lastError_;
}

} // namespace hn
