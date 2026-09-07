#ifndef PERCH_DDC_WIRE_H
#define PERCH_DDC_WIRE_H
#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>
size_t perch_ddc_request(uint8_t *out, uint8_t address, uint8_t command, const uint8_t *payload, size_t length);
bool perch_ddc_frame(const uint8_t *bytes, size_t available, uint8_t command, size_t *payload_length);
bool perch_ddc_value(const uint8_t *bytes, size_t available, uint8_t feature, uint16_t *value);
#endif
