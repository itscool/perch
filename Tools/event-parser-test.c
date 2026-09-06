// Standalone sanitizer/guard-page test; only parses synthetic data.
#include "../Sources/EventParser.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

static uint32_t rng = 0x70657263;
static uint32_t random32(void) { rng ^= rng << 13; rng ^= rng >> 17; rng ^= rng << 5; return rng; }
static void inspect_text(const uint8_t *s, size_t n, PerchJSONText t, uint8_t *copy) {
    if (!(t.flags & 1)) return;
    assert((size_t)t.offset + t.length <= n);
    size_t length = perch_text_copy(s, t, copy, PERCH_EVENT_MAX_BYTES);
    assert(length <= t.length);
    assert(perch_text_equal(s, t, copy, length));
    assert(perch_text_prefix(s, t, copy, length));
    assert(perch_text_contains(s, t, copy, length));
    (void)perch_text_basename(s, t, (const uint8_t *)"node", 4);
}
static bool inspect(const uint8_t *s, size_t n, uint8_t *copy) {
    PerchParsedEvent e;
    if (!perch_event_parse(s, n, &e)) return false;
    assert(e.kind >= 1 && e.kind <= 3 && e.argument_count <= 4);
    inspect_text(s, n, e.actor.path, copy); inspect_text(s, n, e.actor.signing_id, copy);
    inspect_text(s, n, e.subject.path, copy); inspect_text(s, n, e.subject.signing_id, copy);
    inspect_text(s, n, e.time, copy);
    for (unsigned i = 0; i < e.argument_count; ++i) inspect_text(s, n, e.arguments[i], copy);
    PerchEventTimestamp timestamp;
    perch_timestamp_copy(s, e.time, &timestamp);
    assert(timestamp.length <= 128 || timestamp.length == SIZE_MAX);
    return true;
}
int main(int argc, char **argv) {
    assert(argc == 2);
    FILE *f = fopen(argv[1], "rb"); assert(f);
    uint8_t *seed = malloc(PERCH_EVENT_MAX_BYTES + 1), *mutated = malloc(PERCH_EVENT_MAX_BYTES + 1), *copy = malloc(PERCH_EVENT_MAX_BYTES);
    assert(seed && mutated && copy);
    size_t n = fread(seed, 1, PERCH_EVENT_MAX_BYTES + 1, f); fclose(f);
    assert(n && n < PERCH_EVENT_MAX_BYTES);
    assert(inspect(seed, n, copy));
    // The record ends directly against inaccessible memory. Neither validation
    // nor borrowed-text operations may rely on vector padding beyond its end.
    size_t page = (size_t)getpagesize(), size = ((n + page - 1) / page) * page;
    uint8_t *mapping = mmap(NULL, size + page, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0);
    assert(mapping != MAP_FAILED && mprotect(mapping + size, page, PROT_NONE) == 0);
    uint8_t *guarded = mapping + size - n;
    memcpy(guarded, seed, n); assert(inspect(guarded, n, copy));
    for (size_t end = 0; end < n; ++end) {
        // Exact-length heap inputs additionally exercise ASan's red zones.
        uint8_t *shortened = malloc(end ? end : 1); assert(shortened);
        memcpy(shortened, seed, end);
        (void)inspect(shortened, end, copy); free(shortened);
    }
    for (unsigned iteration = 0; iteration < 100000; ++iteration) {
        memcpy(mutated, seed, n);
        for (unsigned change = 0, count = 1 + random32() % 8; change < count; ++change)
            mutated[random32() % n] = (uint8_t)random32();
        (void)inspect(mutated, iteration % 3 ? n : random32() % n, copy);
    }
    PerchParsedEvent e;
    assert(!perch_event_parse(NULL, n, &e));
    assert(!perch_event_parse(seed, n, NULL));
    assert(!perch_event_parse(seed, PERCH_EVENT_MAX_BYTES + 1, &e));
    // A valid record exactly at the limit is accepted, without scratch growth.
    memcpy(mutated, seed, n); memset(mutated + n, ' ', PERCH_EVENT_MAX_BYTES - n);
    assert(inspect(mutated, PERCH_EVENT_MAX_BYTES, copy));
    munmap(mapping, size + page); free(seed); free(mutated); free(copy);
    puts("PASS: guard page, every truncation, 100,000 deterministic mutations, bounds and 2 MB record limit");
}
