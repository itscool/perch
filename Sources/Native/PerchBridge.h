#ifndef PERCH_BRIDGE_H
#define PERCH_BRIDGE_H
// Everything Perch's Swift code needs from C. This was EventParser.h, which
// also carried the Agent Kill Switch's process-event parser until that feature
// was removed on November 12, 2026.
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "DDCWire.h"
#include <IOKit/IOMessage.h>
// IOMessage macros use a form Swift cannot import directly.
static const uint32_t PerchCanSystemSleep = kIOMessageCanSystemSleep;
static const uint32_t PerchSystemWillSleep = kIOMessageSystemWillSleep;
static const uint32_t PerchSystemHasPoweredOn = kIOMessageSystemHasPoweredOn;
static const uint32_t PerchSystemWillNotSleep = kIOMessageSystemWillNotSleep;
#endif
