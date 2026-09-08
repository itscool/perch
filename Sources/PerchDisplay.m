// Restricted DDC adapter: input control and bounded read-only monitor identity.
// IOAV display routing is provided by the MIT-licensed m1ddc adapter in Vendor.
@import Foundation;
@import IOKit;
@import CoreGraphics;
#include "ioregistry.h"
#include "DDCWire.h"
#include <unistd.h>
extern IOReturn IOAVServiceReadI2C(IOAVServiceRef, uint32_t, uint32_t, void *, uint32_t);
extern IOReturn IOAVServiceWriteI2C(IOAVServiceRef, uint32_t, uint32_t, void *, uint32_t);
static void emit(id object) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:object options:0 error:nil];
    if (data) { fwrite(data.bytes, 1, data.length, stdout); fputc('\n', stdout); }
}
static int failure(NSString *text) { emit(@{@"error":text}); return 1; }
static bool query(DDCTransport t, uint8_t address, uint8_t command, const uint8_t *payload, size_t count, uint8_t *reply, uint32_t size) {
    uint8_t bytes[36] = {0};
    size_t length = perch_ddc_request(bytes, address, command, payload, count);
    if (!length || IOAVServiceWriteI2C(t.service, t.chipAddress, address, bytes, (uint32_t)length)) return false;
    usleep(50000);
    memset(reply, 0, size);
    return IOAVServiceReadI2C(t.service, t.chipAddress, address, reply, size) == kIOReturnSuccess;
}
static NSNumber *current(DDCTransport t, bool alternate) {
    uint8_t feature = alternate ? 0xf4 : 0x60, reply[12] = {0};
    uint16_t value = 0;
    for (int attempt = 0; attempt < 2; attempt++) {
        if (query(t, alternate ? 0x50 : 0x51, 0x01, &feature, 1, reply, sizeof(reply)) && perch_ddc_value(reply, sizeof(reply), feature, &value) && value > 0) return @(value);
        usleep(50000);
    }
    return nil;
}
// LG OSC 7.20 uses standard Get VCP identity reads, not firmware mode.
static NSNumber *lgIdentityValue(DDCTransport t, uint8_t feature) {
    if (feature != 0xef && feature != 0xa1) return nil;
    uint8_t reply[12] = {0}; uint16_t value = 0;
    if (query(t, 0x51, 0x01, &feature, 1, reply, sizeof(reply)) &&
        perch_ddc_value(reply, sizeof(reply), feature, &value)) return @(value);
    return nil;
}
static NSString *capabilities(DDCTransport t) {
    uint8_t result[4096] = {0}; size_t offset = 0;
    for (int chunk = 0; chunk < 128 && offset < sizeof(result)-1; chunk++) {
        uint8_t payload[2] = {(uint8_t)(offset >> 8), (uint8_t)offset}, reply[38] = {0}; size_t length = 0;
        if (!query(t, 0x51, 0xf3, payload, 2, reply, sizeof(reply)) || !perch_ddc_frame(reply, sizeof(reply), 0xe3, &length) || length < 3 || reply[3] != payload[0] || reply[4] != payload[1]) return nil;
        size_t bytes = length-3;
        if (bytes == 0) return [[NSString alloc] initWithBytes:result length:offset encoding:NSASCIIStringEncoding];
        if (offset+bytes >= sizeof(result)) return nil;
        for (size_t i = 0; i < bytes; i++) {
            if (reply[5+i] == 0) return [[NSString alloc] initWithBytes:result length:offset encoding:NSASCIIStringEncoding];
            if (reply[5+i] < 0x20 || reply[5+i] > 0x7e) return nil;
            result[offset++] = reply[5+i];
        }
    }
    return nil;
}
int main(int argc, const char **argv) { @autoreleasepool {
    alarm(8); // A wedged driver must not pin Perch's UI/input/guardian process.
    if (argc < 2) return failure(@"Missing display command.");
    NSString *command = @(argv[1]);
    bool list = [command isEqual:@"list"], inspect = [command isEqual:@"inspect"], read = [command isEqual:@"read"], change = [command isEqual:@"switch"];
    if ((!list && !inspect && !read && !change) || (list && argc != 2) || ((inspect || read) && argc != 4) || (change && argc != 5)) return failure(@"Invalid display command.");
    DisplayInfos displays[MAX_DISPLAYS] = {0};
    int count = (int)getOnlineDisplayInfos(displays);
    if (list) {
        NSMutableArray *result = [NSMutableArray array];
        for (int i = 0; i < count; i++) {
            DisplayInfos *d = &displays[i];
            if (CGDisplayIsBuiltin(d->id) || !d->uuid) continue;
            DDCTransport t = getDisplayDDCTransport(d);
            [result addObject:@{@"id":d->uuid,@"displayID":@(d->id),@"name":d->productName ?: @"External monitor",@"vendor":@(d->vendor),@"model":@(d->model),@"connection":d->ioLocation ?: @"unknown",@"ddcAvailable":t.service ? @YES : @NO}];
            if (t.service) CFRelease(t.service);
        }
        emit(result); return 0;
    }
    NSString *identifier = @(argv[2]);
    if (![[NSUUID alloc] initWithUUIDString:identifier]) return failure(@"Invalid monitor identity.");
    DisplayInfos *selected = NULL;
    for (int i = 0; i < count; i++) if (!CGDisplayIsBuiltin(displays[i].id) && [displays[i].uuid isEqual:identifier]) {
        if (selected) return failure(@"Monitor identity is ambiguous; reconnect and reselect it.");
        selected = &displays[i];
    }
    if (!selected) return failure(@"The selected monitor is not connected to this Mac.");
    NSString *mode = @(argv[3]);
    bool alternate = [mode isEqual:@"lg"];
    if (![mode isEqual:@"standard"] && !alternate) return failure(@"Invalid input protocol.");
    if (alternate && selected->vendor != 0x1e6d) return failure(@"LG input protocol is only available for LG monitors.");
    DDCTransport t = getDisplayDDCTransport(selected);
    if (!t.service) return failure(@"This display connection does not expose DDC input control.");
    if (inspect || read) {
        NSNumber *value = current(t, alternate);
        NSString *caps = inspect && !alternate ? capabilities(t) : nil;
        NSMutableDictionary *result = [@{@"current":value ?: (id)[NSNull null], @"capabilities":caps ?: (id)[NSNull null]} mutableCopy];
        if (inspect && selected->vendor == 0x1e6d) {
            NSNumber *identity = lgIdentityValue(t, 0xef);
            NSNumber *extended = identity && (identity.unsignedIntValue & 0x8000) ? lgIdentityValue(t, 0xa1) : nil;
            result[@"lgIdentity"] = identity ?: (id)[NSNull null];
            result[@"lgExtendedIdentity"] = extended ?: (id)[NSNull null];
        }
        emit(result);
        CFRelease(t.service); return 0;
    }
    char *end = NULL; long value = strtol(argv[4], &end, 10);
    if (!*argv[4] || *end || value <= 0 || value > 65535) { CFRelease(t.service); return failure(@"Input code must be between 1 and 65535."); }
    uint8_t payload[3] = {alternate ? 0xf4 : 0x60, (uint8_t)(value >> 8), (uint8_t)value}, bytes[36] = {0};
    size_t length = perch_ddc_request(bytes, alternate ? 0x50 : 0x51, 0x03, payload, sizeof(payload));
    IOReturn status = IOAVServiceWriteI2C(t.service, t.chipAddress, alternate ? 0x50 : 0x51, bytes, (uint32_t)length);
    CFRelease(t.service);
    if (status) return failure(@"The monitor did not accept the input command. The cycle position was not advanced.");
    emit(@{@"sent":@YES}); return 0; // Transport success is not monitor confirmation.
}}
