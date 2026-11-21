#pragma once

#include <string>
#include <utility>
#include <vector>

namespace hn {

/// Minimal, allocation-conscious JSON value + recursive descent parser.
/// The engine only needs the Hacker News Firebase schema, so this avoids a
/// third-party dependency and keeps decoding on the native side.
class Json {
public:
    enum class Type {
        Null,
        Bool,
        Number,
        String,
        Array,
        Object
    };

    using Array = std::vector<Json>;
    using Member = std::pair<std::string, Json>;
    using Object = std::vector<Member>;

    Type type = Type::Null;
    bool boolean = false;
    double number = 0;
    std::string string;
    Array array;
    Object object;

    static bool parse(const std::string& text, Json& out, std::string* error = nullptr);

    const Json* find(const std::string& key) const;

    bool isNull() const { return type == Type::Null; }
    bool isObject() const { return type == Type::Object; }
    bool isArray() const { return type == Type::Array; }
    bool isString() const { return type == Type::String; }
    bool isNumber() const { return type == Type::Number; }
    bool isBool() const { return type == Type::Bool; }

    std::string stringOr(const std::string& fallback = "") const {
        return type == Type::String ? string : fallback;
    }
    int intOr(int fallback = 0) const;
    double numberOr(double fallback = 0) const;
    bool boolOr(bool fallback = false) const;
};

/// Serializes a vector<int> as a compact JSON array, used by the SQLite store.
std::string jsonIntArray(const std::vector<int>& values);

/// Parses a JSON array of integers. Returns false on malformed input.
bool parseIntArray(const std::string& text, std::vector<int>& out);

} // namespace hn
