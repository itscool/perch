#include "EventParser.h"
#include <string.h>

typedef struct { const uint8_t *s; size_t n, i; PerchParsedEvent *out; } Parser;
enum Context { IGNORE, ROOT, ACTOR, SUBJECT, TOKEN_A, TOKEN_S, FILE_A, FILE_S, EVENT, FORK, EXEC };

static void space(Parser *p) {
    while (p->i < p->n) {
        uint8_t c = p->s[p->i];
        if (c != ' ' && c != '\t' && c != '\r' && c != '\n') break;
        ++p->i;
    }
}
static int hex(uint8_t c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
}
static bool u16(Parser *p, uint32_t *out) {
    if (p->n - p->i < 4) return false;
    uint32_t v = 0;
    for (unsigned j = 0; j < 4; ++j) {
        int h = hex(p->s[p->i++]); if (h < 0) return false;
        v = (v << 4) | (unsigned)h;
    }
    *out = v; return true;
}
static bool escape(Parser *p, uint32_t *out) {
    if (p->i == p->n) return false;
    switch (p->s[p->i++]) {
        case '"': *out = '"'; return true;
        case '\\': *out = '\\'; return true;
        case '/': *out = '/'; return true;
        case 'b': *out = 8; return true;
        case 'f': *out = 12; return true;
        case 'n': *out = 10; return true;
        case 'r': *out = 13; return true;
        case 't': *out = 9; return true;
        case 'u': {
            uint32_t a, b;
            if (!u16(p, &a)) return false;
            if (a >= 0xdc00 && a <= 0xdfff) return false;
            if (a >= 0xd800 && a <= 0xdbff) {
                if (p->n - p->i < 6 || p->s[p->i] != '\\' || p->s[p->i + 1] != 'u') return false;
                p->i += 2;
                if (!u16(p, &b) || b < 0xdc00 || b > 0xdfff) return false;
                a = 0x10000 + ((a - 0xd800) << 10) + b - 0xdc00;
            }
            *out = a; return true;
        }
        default: return false;
    }
}
static bool utf8(Parser *p, uint8_t first) {
    unsigned count; uint32_t v, minimum;
    if (first >= 0xc2 && first <= 0xdf) { count = 1; v = first & 31; minimum = 0x80; }
    else if (first >= 0xe0 && first <= 0xef) { count = 2; v = first & 15; minimum = 0x800; }
    else if (first >= 0xf0 && first <= 0xf4) { count = 3; v = first & 7; minimum = 0x10000; }
    else return false;
    if (p->n - p->i < count) return false;
    while (count--) {
        uint8_t c = p->s[p->i++]; if ((c & 0xc0) != 0x80) return false;
        v = (v << 6) | (c & 63);
    }
    return v >= minimum && v <= 0x10ffff && !(v >= 0xd800 && v <= 0xdfff);
}
static bool has_zero(uint64_t v) {
    return ((v - UINT64_C(0x0101010101010101)) & ~v & UINT64_C(0x8080808080808080)) != 0;
}
static bool text(Parser *p, PerchJSONText *out) {
    if (p->i == p->n || p->s[p->i++] != '"') return false;
    size_t start = p->i; uint32_t flags = 1;
    while (p->i < p->n) {
        // Skip ordinary ASCII eight bytes at a time, with no read past input.
        if (p->n - p->i >= 8) {
            uint64_t w; memcpy(&w, p->s + p->i, 8);
            if (!(w & UINT64_C(0x8080808080808080)) &&
                !has_zero(w ^ UINT64_C(0x2222222222222222)) &&
                !has_zero(w ^ UINT64_C(0x5c5c5c5c5c5c5c5c)) &&
                !((w - UINT64_C(0x2020202020202020)) & ~w & UINT64_C(0x8080808080808080))) {
                p->i += 8; continue;
            }
        }
        uint8_t c = p->s[p->i++];
        if (c == '"') {
            *out = (PerchJSONText){ (uint32_t)start, (uint32_t)(p->i - start - 1), flags };
            return true;
        }
        if (c < 32) return false;
        if (c == '\\') { uint32_t ignored; flags |= 2; if (!escape(p, &ignored)) return false; }
        else if (c >= 128 && !utf8(p, c)) return false;
    }
    return false;
}
// UTF-8 byte cursor over validated JSON strings. Copyable state supports matching
// escaped paths/keys without allocating a decoded string.
typedef struct { Parser p; uint8_t pending[4]; unsigned next, count; } Cursor;
static Cursor cursor(const uint8_t *s, PerchJSONText t) {
    return (Cursor){ .p = { s, (size_t)t.offset + t.length, t.offset, NULL } };
}
static int next_byte(Cursor *c) {
    if (c->next < c->count) return c->pending[c->next++];
    if (c->p.i >= c->p.n) return -1;
    uint8_t b = c->p.s[c->p.i++];
    if (b != '\\') return b;
    uint32_t u;
    if (!escape(&c->p, &u)) return -1;
    c->next = 1;
    if (u < 0x80) { c->count = 1; c->pending[0] = (uint8_t)u; }
    else if (u < 0x800) { c->count = 2; c->pending[0] = 0xc0 | (u >> 6); c->pending[1] = 0x80 | (u & 63); }
    else if (u < 0x10000) {
        c->count = 3; c->pending[0] = 0xe0 | (u >> 12); c->pending[1] = 0x80 | ((u >> 6) & 63); c->pending[2] = 0x80 | (u & 63);
    } else {
        c->count = 4; c->pending[0] = 0xf0 | (u >> 18); c->pending[1] = 0x80 | ((u >> 12) & 63);
        c->pending[2] = 0x80 | ((u >> 6) & 63); c->pending[3] = 0x80 | (u & 63);
    }
    return c->pending[0];
}
bool perch_text_prefix(const uint8_t *s, PerchJSONText t, const uint8_t *other, size_t n) {
    if (!(t.flags & 1)) return false;
    if (!(t.flags & 2)) return t.length >= n && (!n || memcmp(s + t.offset, other, n) == 0);
    Cursor c = cursor(s, t);
    for (size_t i = 0; i < n; ++i) if (next_byte(&c) != other[i]) return false;
    return true;
}
bool perch_text_equal(const uint8_t *s, PerchJSONText t, const uint8_t *other, size_t n) {
    if (!(t.flags & 1)) return false;
    if (!(t.flags & 2)) return t.length == n && (!n || memcmp(s + t.offset, other, n) == 0);
    Cursor c = cursor(s, t);
    for (size_t i = 0; i < n; ++i) if (next_byte(&c) != other[i]) return false;
    return next_byte(&c) == -1;
}
bool perch_text_contains(const uint8_t *s, PerchJSONText t, const uint8_t *other, size_t n) {
    if (!(t.flags & 1)) return false;
    if (!n) return true;
    if (!(t.flags & 2)) {
        if (n > t.length) return false;
        for (size_t i = 0; i <= t.length - n; ++i)
            if (s[t.offset + i] == other[0] && memcmp(s + t.offset + i, other, n) == 0) return true;
        return false;
    }
    Cursor c = cursor(s, t);
    while (c.p.i < c.p.n || c.next < c.count) {
        Cursor candidate = c; size_t i = 0;
        while (i < n && next_byte(&candidate) == other[i]) ++i;
        if (i == n) return true;
        (void)next_byte(&c);
    }
    return false;
}
bool perch_text_basename(const uint8_t *s, PerchJSONText t, const uint8_t *other, size_t n) {
    if (!(t.flags & 1)) return false;
    if (!(t.flags & 2)) {
        size_t end = t.length;
        while (end && s[t.offset + end - 1] == '/') --end;
        size_t start = end;
        while (start && s[t.offset + start - 1] != '/') --start;
        return end > start && end - start == n && (!n || memcmp(s + t.offset + start, other, n) == 0);
    }
    Cursor c = cursor(s, t), start = c, last = c; bool in_component = false, found = false;
    size_t length = 0, last_length = 0;
    for (;;) {
        Cursor before = c; int b = next_byte(&c);
        if (b < 0) break;
        if (b == '/') { in_component = false; continue; }
        if (!in_component) { start = before; length = 0; in_component = true; }
        ++length; last = start; last_length = length; found = true;
    }
    if (!found || last_length != n) return false;
    for (size_t i = 0; i < n; ++i) if (next_byte(&last) != other[i]) return false;
    return true;
}
size_t perch_text_copy(const uint8_t *s, PerchJSONText t, uint8_t *out, size_t capacity) {
    if (!(t.flags & 1)) return 0;
    if (!(t.flags & 2)) {
        if (t.length > capacity) return SIZE_MAX;
        if (t.length) memcpy(out, s + t.offset, t.length);
        return t.length;
    }
    Cursor c = cursor(s, t); size_t n = 0; int b;
    while ((b = next_byte(&c)) >= 0) {
        if (n == capacity) return SIZE_MAX;
        out[n++] = (uint8_t)b;
    }
    return n;
}
void perch_timestamp_copy(const uint8_t *s, PerchJSONText t, PerchEventTimestamp *out) {
    out->length = perch_text_copy(s, t, out->bytes, sizeof(out->bytes));
}
static bool key(Parser *p, PerchJSONText t, const char *s) {
    return perch_text_equal(p->s, t, (const uint8_t *)s, strlen(s));
}
static unsigned field(Parser *p, enum Context ctx, PerchJSONText t) {
    const char *const *names = NULL; unsigned count = 0;
    static const char *const root[] = { "process", "event", "global_seq_num", "time" };
    static const char *const process[] = { "audit_token", "executable", "signing_id" };
    static const char *const token[] = { "auid", "euid", "egid", "ruid", "rgid", "pid", "asid", "pidversion" };
    static const char *const file[] = { "path" }, *const event[] = { "fork", "exec", "exit" };
    static const char *const fork[] = { "child" }, *const exec[] = { "target", "args" };
    switch (ctx) {
        case ROOT: names = root; count = 4; break;
        case ACTOR: case SUBJECT: names = process; count = 3; break;
        case TOKEN_A: case TOKEN_S: names = token; count = 8; break;
        case FILE_A: case FILE_S: names = file; count = 1; break;
        case EVENT: names = event; count = 3; break;
        case FORK: names = fork; count = 1; break;
        case EXEC: names = exec; count = 2; break;
        default: return 0;
    }
    for (unsigned i = 0; i < count; ++i) if (key(p, t, names[i])) return i + 1;
    return 0;
}
static bool digit(uint8_t b) { return b >= '0' && b <= '9'; }
static bool number(Parser *p, uint64_t *integer) {
    size_t start = p->i;
    bool integral = true, negative = p->s[p->i] == '-';
    if (negative) ++p->i;
    if (p->i == p->n) return false;
    if (p->s[p->i] == '0') ++p->i;
    else {
        if (p->s[p->i] < '1' || p->s[p->i] > '9') return false;
        do { ++p->i; } while (p->i < p->n && digit(p->s[p->i]));
    }
    if (p->i < p->n && p->s[p->i] == '.') {
        integral = false; ++p->i; size_t begin = p->i;
        while (p->i < p->n && digit(p->s[p->i])) ++p->i;
        if (begin == p->i) return false;
    }
    if (p->i < p->n && (p->s[p->i] == 'e' || p->s[p->i] == 'E')) {
        integral = false; ++p->i;
        if (p->i < p->n && (p->s[p->i] == '+' || p->s[p->i] == '-')) ++p->i;
        size_t begin = p->i;
        while (p->i < p->n && digit(p->s[p->i])) ++p->i;
        if (begin == p->i) return false;
    }
    if (integer) {
        if (negative || !integral) return false;
        uint64_t n = 0;
        for (size_t i = start; i < p->i; ++i) {
            unsigned d = p->s[i] - '0';
            if (n > (UINT64_MAX - d) / 10) return false;
            n = n * 10 + d;
        }
        *integer = n;
    }
    return true;
}
static bool value(Parser *, unsigned, enum Context);
static bool args(Parser *p, unsigned depth) {
    if (depth >= PERCH_JSON_MAX_DEPTH) return false;
    p->out->arguments_present = true;
    p->out->arguments_valid = p->s[p->i] == '[';
    if (!p->out->arguments_valid) return value(p, depth, IGNORE);
    ++p->i; space(p);
    if (p->i < p->n && p->s[p->i] == ']') { ++p->i; return true; }
    size_t count = 0;
    for (;;) {
        space(p); if (p->i == p->n) return false;
        if (count < 4 && p->s[p->i] == '"') {
            if (!text(p, &p->out->arguments[count])) return false;
        } else {
            if (count < 4) p->out->arguments_valid = false;
            if (!value(p, depth + 1, IGNORE)) return false;
        }
        ++count; space(p);
        if (p->i == p->n) return false;
        uint8_t c = p->s[p->i++];
        if (c == ']') break;
        if (c != ',') return false;
    }
    p->out->argument_count = (uint32_t)(count < 4 ? count : 4);
    return true;
}
static bool member(Parser *p, unsigned depth, enum Context ctx, unsigned id) {
    if (!id) return value(p, depth, IGNORE);
    PerchEventProcess *proc = (ctx == SUBJECT || ctx == TOKEN_S || ctx == FILE_S) ? &p->out->subject : &p->out->actor;
    uint64_t n;
    switch (ctx) {
        case ROOT:
            switch (id) {
                case 1: return value(p, depth, ACTOR);
                case 2: return value(p, depth, EVENT);
                case 3: return number(p, &p->out->sequence);
                case 4: return text(p, &p->out->time);
            }
            break;
        case ACTOR: case SUBJECT:
            if (id == 1) return value(p, depth, ctx == ACTOR ? TOKEN_A : TOKEN_S);
            if (id == 2) return value(p, depth, ctx == ACTOR ? FILE_A : FILE_S);
            if (p->s[p->i] == '"') return text(p, &proc->signing_id);
            return value(p, depth, IGNORE);
        case TOKEN_A: case TOKEN_S:
            if (!number(p, &n) || n > UINT32_MAX) return false;
            proc->token.values[id - 1] = (uint32_t)n; return true;
        case FILE_A: case FILE_S: return text(p, &proc->path);
        case EVENT:
            if (p->out->kind) return false;
            p->out->kind = id;
            return value(p, depth, id == 1 ? FORK : id == 2 ? EXEC : IGNORE);
        case FORK: return value(p, depth, SUBJECT);
        case EXEC:
            if (id == 1) return value(p, depth, SUBJECT);
            return args(p, depth);
        default: break;
    }
    return false;
}
static bool value(Parser *p, unsigned depth, enum Context ctx) {
    space(p);
    if (p->i == p->n || depth >= PERCH_JSON_MAX_DEPTH) return false;
    uint8_t c = p->s[p->i];
    if (ctx != IGNORE && c != '{') return false;
    if (c == '{') {
        ++p->i; uint32_t seen = 0; space(p);
        if (p->i == p->n) return false;
        if (p->s[p->i] != '}') for (;;) {
            PerchJSONText name;
            if (!text(p, &name)) return false;
            unsigned id = field(p, ctx, name);
            if (id && (seen & (1u << id))) return false;
            seen |= 1u << id;
            space(p);
            if (p->i == p->n || p->s[p->i++] != ':') return false;
            space(p);
            if (p->i == p->n || !member(p, depth + 1, ctx, id)) return false;
            space(p);
            if (p->i == p->n) return false;
            if (p->s[p->i] == '}') break;
            if (p->s[p->i++] != ',') return false;
            space(p);
        }
        ++p->i;
        uint32_t required = ctx == ROOT ? 14 : (ctx == ACTOR || ctx == SUBJECT) ? 6 :
            (ctx == TOKEN_A || ctx == TOKEN_S) ? 510 : (ctx == FILE_A || ctx == FILE_S || ctx == FORK || ctx == EXEC) ? 2 : 0;
        return (seen & required) == required && (ctx != EVENT || (seen & 14));
    }
    if (c == '[') {
        ++p->i; space(p);
        if (p->i < p->n && p->s[p->i] == ']') { ++p->i; return true; }
        for (;;) {
            if (!value(p, depth + 1, IGNORE)) return false;
            space(p); if (p->i == p->n) return false;
            c = p->s[p->i++];
            if (c == ']') return true;
            if (c != ',') return false;
        }
    }
    if (c == '"') { PerchJSONText ignored; return text(p, &ignored); }
    const char *literal = c == 't' ? "true" : c == 'f' ? "false" : c == 'n' ? "null" : NULL;
    if (literal) {
        size_t n = strlen(literal);
        if (p->n - p->i < n || memcmp(p->s + p->i, literal, n)) return false;
        p->i += n; return true;
    }
    return number(p, NULL);
}
bool perch_event_parse(const uint8_t *input, size_t length, PerchParsedEvent *event) {
    if (!input || !event || !length || length > PERCH_EVENT_MAX_BYTES) return false;
    memset(event, 0, sizeof(*event));
    Parser p = { input, length, 0, event };
    if (!value(&p, 0, ROOT)) return false;
    space(&p);
    if (p.i != p.n) return false;
    if (event->kind == 3) event->subject = event->actor;
    return true;
}
