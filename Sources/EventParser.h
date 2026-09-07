#ifndef PERCH_EVENT_PARSER_H
#define PERCH_EVENT_PARSER_H
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#define PERCH_EVENT_MAX_BYTES 2000000
#define PERCH_JSON_MAX_DEPTH 64
typedef struct { uint32_t offset, length, flags; } PerchJSONText;
typedef struct { uint32_t values[8]; } PerchAuditToken;
typedef struct { PerchAuditToken token; PerchJSONText path, signing_id; } PerchEventProcess;
typedef struct {
    PerchEventProcess actor, subject;
    uint64_t sequence;
    PerchJSONText time, arguments[4];
    uint32_t kind, argument_count;
    bool arguments_valid, arguments_present;
} PerchParsedEvent;
typedef struct { uint8_t bytes[128]; size_t length; } PerchEventTimestamp;

// All views borrow bytes from input; no allocation, padding or mutation is needed.
bool perch_event_parse(const uint8_t *input, size_t length, PerchParsedEvent *event);
bool perch_text_equal(const uint8_t *input, PerchJSONText text, const uint8_t *other, size_t length);
bool perch_text_prefix(const uint8_t *input, PerchJSONText text, const uint8_t *other, size_t length);
bool perch_text_contains(const uint8_t *input, PerchJSONText text, const uint8_t *other, size_t length);
bool perch_text_basename(const uint8_t *input, PerchJSONText text, const uint8_t *other, size_t length);
// Returns SIZE_MAX if capacity is insufficient; otherwise returns UTF-8 bytes written.
size_t perch_text_copy(const uint8_t *input, PerchJSONText text, uint8_t *output, size_t capacity);
void perch_timestamp_copy(const uint8_t *input, PerchJSONText text, PerchEventTimestamp *timestamp);
#endif

#include "DDCWire.h"
