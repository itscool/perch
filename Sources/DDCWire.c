#include "DDCWire.h"
size_t perch_ddc_request(uint8_t *out, uint8_t address, uint8_t command, const uint8_t *payload, size_t length) {
    if (!out || length > 32 || (length && !payload)) return 0;
    out[0] = 0x80 | (uint8_t)(length + 1); out[1] = command;
    uint8_t checksum = 0x6e ^ address ^ out[0] ^ command;
    for (size_t i = 0; i < length; i++) { out[i+2] = payload[i]; checksum ^= payload[i]; }
    out[length+2] = checksum;
    return length+3;
}
bool perch_ddc_frame(const uint8_t *bytes, size_t available, uint8_t command, size_t *payload_length) {
    if (!bytes || !payload_length || available < 4 || bytes[0] != 0x6e || !(bytes[1] & 0x80)) return false;
    size_t length = bytes[1] & 0x7f;
    if (!length || length+3 > available || bytes[2] != command) return false;
    uint8_t sum = 0x50;
    for (size_t i = 0; i < length+3; i++) sum ^= bytes[i];
    if (sum) return false;
    *payload_length = length;
    return true;
}
bool perch_ddc_value(const uint8_t *bytes, size_t available, uint8_t feature, uint16_t *value) {
    size_t length = 0;
    if (!value || !perch_ddc_frame(bytes, available, 0x02, &length) || length != 8 || bytes[3] != 0 || bytes[4] != feature) return false;
    *value = (uint16_t)((bytes[8] << 8) | bytes[9]); return true;
}
