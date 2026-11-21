#include "hn/Json.hpp"

#include <cmath>
#include <cstdlib>
#include <cstring>
#include <limits>

namespace hn {

namespace {

class Parser {
public:
    explicit Parser(const std::string& text) : text_(text) {}

    bool parseValue(Json& out, std::string& error) {
        skipWhitespace();
        if (pos_ >= text_.size()) {
            return fail("unexpected end of input", error);
        }
        const char ch = text_[pos_];
        switch (ch) {
            case '{': return parseObject(out, error);
            case '[': return parseArray(out, error);
            case '"': {
                out.type = Json::Type::String;
                return parseString(out.string, error);
            }
            case 't': return parseLiteral("true", out, true, error);
            case 'f': return parseLiteral("false", out, false, error);
            case 'n': return parseNull(out, error);
            default:
                if (ch == '-' || (ch >= '0' && ch <= '9')) {
                    return parseNumber(out, error);
                }
                return fail("unexpected character", error);
        }
    }

    bool parseDocument(Json& out, std::string& error) {
        if (!parseValue(out, error)) return false;
        skipWhitespace();
        if (pos_ != text_.size()) {
            return fail("trailing characters", error);
        }
        return true;
    }

private:
    bool fail(const std::string& message, std::string& error) {
        error = message + " at offset " + std::to_string(pos_);
        return false;
    }

    void skipWhitespace() {
        while (pos_ < text_.size()) {
            const char c = text_[pos_];
            if (c == ' ' || c == '\t' || c == '\n' || c == '\r') {
                ++pos_;
            } else {
                break;
            }
        }
    }

    bool parseObject(Json& out, std::string& error) {
        if (++depth_ > kMaxDepth) return fail("object nesting too deep", error);
        ++pos_; // {
        out.type = Json::Type::Object;
        out.object.clear();
        skipWhitespace();
        if (pos_ < text_.size() && text_[pos_] == '}') {
            ++pos_;
            --depth_;
            return true;
        }
        while (true) {
            skipWhitespace();
            if (pos_ >= text_.size() || text_[pos_] != '"') {
                return fail("expected object key", error);
            }
            std::string key;
            if (!parseString(key, error)) return false;
            skipWhitespace();
            if (pos_ >= text_.size() || text_[pos_] != ':') {
                return fail("expected ':'", error);
            }
            ++pos_;
            Json value;
            if (!parseValue(value, error)) return false;
            out.object.emplace_back(std::move(key), std::move(value));
            skipWhitespace();
            if (pos_ >= text_.size()) return fail("unterminated object", error);
            if (text_[pos_] == ',') {
                ++pos_;
                continue;
            }
            if (text_[pos_] == '}') {
                ++pos_;
                --depth_;
                return true;
            }
            return fail("expected ',' or '}'", error);
        }
    }

    bool parseArray(Json& out, std::string& error) {
        if (++depth_ > kMaxDepth) return fail("array nesting too deep", error);
        ++pos_; // [
        out.type = Json::Type::Array;
        out.array.clear();
        skipWhitespace();
        if (pos_ < text_.size() && text_[pos_] == ']') {
            ++pos_;
            --depth_;
            return true;
        }
        while (true) {
            Json value;
            if (!parseValue(value, error)) return false;
            out.array.emplace_back(std::move(value));
            skipWhitespace();
            if (pos_ >= text_.size()) return fail("unterminated array", error);
            if (text_[pos_] == ',') {
                ++pos_;
                continue;
            }
            if (text_[pos_] == ']') {
                ++pos_;
                --depth_;
                return true;
            }
            return fail("expected ',' or ']'", error);
        }
    }

    static void appendUtf8(std::string& out, unsigned int codepoint) {
        if (codepoint <= 0x7F) {
            out.push_back(static_cast<char>(codepoint));
        } else if (codepoint <= 0x7FF) {
            out.push_back(static_cast<char>(0xC0 | (codepoint >> 6)));
            out.push_back(static_cast<char>(0x80 | (codepoint & 0x3F)));
        } else if (codepoint <= 0xFFFF) {
            out.push_back(static_cast<char>(0xE0 | (codepoint >> 12)));
            out.push_back(static_cast<char>(0x80 | ((codepoint >> 6) & 0x3F)));
            out.push_back(static_cast<char>(0x80 | (codepoint & 0x3F)));
        } else {
            out.push_back(static_cast<char>(0xF0 | (codepoint >> 18)));
            out.push_back(static_cast<char>(0x80 | ((codepoint >> 12) & 0x3F)));
            out.push_back(static_cast<char>(0x80 | ((codepoint >> 6) & 0x3F)));
            out.push_back(static_cast<char>(0x80 | (codepoint & 0x3F)));
        }
    }

    bool parseHex4(unsigned int& value, std::string& error) {
        if (pos_ + 4 > text_.size()) return fail("truncated unicode escape", error);
        value = 0;
        for (int i = 0; i < 4; ++i) {
            const char c = text_[pos_++];
            value <<= 4;
            if (c >= '0' && c <= '9') value |= static_cast<unsigned int>(c - '0');
            else if (c >= 'a' && c <= 'f') value |= static_cast<unsigned int>(c - 'a' + 10);
            else if (c >= 'A' && c <= 'F') value |= static_cast<unsigned int>(c - 'A' + 10);
            else return fail("invalid unicode escape", error);
        }
        return true;
    }

    bool parseString(std::string& out, std::string& error) {
        ++pos_; // opening quote
        out.clear();
        while (pos_ < text_.size()) {
            const unsigned char c = static_cast<unsigned char>(text_[pos_++]);
            if (c == '"') return true;
            if (c == '\\') {
                if (pos_ >= text_.size()) return fail("truncated escape", error);
                const char esc = text_[pos_++];
                switch (esc) {
                    case '"': out.push_back('"'); break;
                    case '\\': out.push_back('\\'); break;
                    case '/': out.push_back('/'); break;
                    case 'b': out.push_back('\b'); break;
                    case 'f': out.push_back('\f'); break;
                    case 'n': out.push_back('\n'); break;
                    case 'r': out.push_back('\r'); break;
                    case 't': out.push_back('\t'); break;
                    case 'u': {
                        unsigned int high = 0;
                        if (!parseHex4(high, error)) return false;
                        unsigned int codepoint = high;
                        if (high >= 0xD800 && high <= 0xDBFF) {
                            if (pos_ + 1 >= text_.size() || text_[pos_] != '\\' || text_[pos_ + 1] != 'u') {
                                return fail("expected low surrogate", error);
                            }
                            pos_ += 2;
                            unsigned int low = 0;
                            if (!parseHex4(low, error)) return false;
                            if (low < 0xDC00 || low > 0xDFFF) {
                                return fail("invalid low surrogate", error);
                            }
                            codepoint = 0x10000 + ((high - 0xD800) << 10) + (low - 0xDC00);
                        }
                        appendUtf8(out, codepoint);
                        break;
                    }
                    default: return fail("invalid escape", error);
                }
            } else if (c < 0x20) {
                return fail("control character in string", error);
            } else {
                out.push_back(static_cast<char>(c));
            }
        }
        return fail("unterminated string", error);
    }

    bool parseNumber(Json& out, std::string& error) {
        const size_t start = pos_;
        if (text_[pos_] == '-') ++pos_;
        if (pos_ >= text_.size()) return fail("truncated number", error);
        if (text_[pos_] == '0') {
            ++pos_;
        } else if (text_[pos_] >= '1' && text_[pos_] <= '9') {
            while (pos_ < text_.size() && text_[pos_] >= '0' && text_[pos_] <= '9') ++pos_;
        } else {
            return fail("invalid number", error);
        }
        if (pos_ < text_.size() && text_[pos_] == '.') {
            ++pos_;
            if (pos_ >= text_.size() || text_[pos_] < '0' || text_[pos_] > '9') {
                return fail("invalid fraction", error);
            }
            while (pos_ < text_.size() && text_[pos_] >= '0' && text_[pos_] <= '9') ++pos_;
        }
        if (pos_ < text_.size() && (text_[pos_] == 'e' || text_[pos_] == 'E')) {
            ++pos_;
            if (pos_ < text_.size() && (text_[pos_] == '+' || text_[pos_] == '-')) ++pos_;
            if (pos_ >= text_.size() || text_[pos_] < '0' || text_[pos_] > '9') {
                return fail("invalid exponent", error);
            }
            while (pos_ < text_.size() && text_[pos_] >= '0' && text_[pos_] <= '9') ++pos_;
        }
        const std::string token = text_.substr(start, pos_ - start);
        char* end = nullptr;
        const double value = std::strtod(token.c_str(), &end);
        if (end == token.c_str() || *end != '\0' || !std::isfinite(value)) {
            return fail("invalid number value", error);
        }
        out.type = Json::Type::Number;
        out.number = value;
        return true;
    }

    bool parseLiteral(const char* literal, Json& out, bool value, std::string& error) {
        const size_t length = std::strlen(literal);
        if (text_.compare(pos_, length, literal) != 0) {
            return fail("invalid literal", error);
        }
        pos_ += length;
        out.type = Json::Type::Bool;
        out.boolean = value;
        return true;
    }

    bool parseNull(Json& out, std::string& error) {
        if (text_.compare(pos_, 4, "null") != 0) {
            return fail("invalid literal", error);
        }
        pos_ += 4;
        out.type = Json::Type::Null;
        return true;
    }

    static constexpr int kMaxDepth = 64;
    const std::string& text_;
    size_t pos_ = 0;
    int depth_ = 0;
};

} // namespace

bool Json::parse(const std::string& text, Json& out, std::string* error) {
    std::string localError;
    Parser parser(text);
    out = Json{};
    if (!parser.parseDocument(out, localError)) {
        if (error) *error = localError;
        return false;
    }
    if (error) error->clear();
    return true;
}

const Json* Json::find(const std::string& key) const {
    if (type != Type::Object) return nullptr;
    for (const auto& member : object) {
        if (member.first == key) return &member.second;
    }
    return nullptr;
}

int Json::intOr(int fallback) const {
    if (type != Type::Number) return fallback;
    if (number < static_cast<double>(std::numeric_limits<int>::min()) ||
        number > static_cast<double>(std::numeric_limits<int>::max())) {
        return fallback;
    }
    return static_cast<int>(number);
}

double Json::numberOr(double fallback) const {
    return type == Type::Number ? number : fallback;
}

bool Json::boolOr(bool fallback) const {
    return type == Type::Bool ? boolean : fallback;
}

std::string jsonIntArray(const std::vector<int>& values) {
    std::string out;
    out.reserve(values.size() * 8 + 2);
    out.push_back('[');
    for (size_t i = 0; i < values.size(); ++i) {
        if (i) out.push_back(',');
        out += std::to_string(values[i]);
    }
    out.push_back(']');
    return out;
}

bool parseIntArray(const std::string& text, std::vector<int>& out) {
    out.clear();
    if (text.empty()) return true;
    Json json;
    std::string error;
    if (!Json::parse(text, json, &error) || !json.isArray()) return false;
    out.reserve(json.array.size());
    for (const auto& value : json.array) {
        if (!value.isNumber()) return false;
        out.push_back(value.intOr());
    }
    return true;
}

} // namespace hn
