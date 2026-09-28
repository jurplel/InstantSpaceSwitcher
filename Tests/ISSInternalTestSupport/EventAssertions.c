#include "ISSInternalTestSupport.h"

#include <float.h>
#include <math.h>
#include <stdio.h>
#include <string.h>

#define CHECK(condition) do { \
    if (!(condition)) { \
        fprintf(stderr, "%s:%d: %s\n", __FILE__, __LINE__, #condition); \
        failures++; \
    } \
} while (0)

// Test decoder, deliberately independent of the production structures.
static uint32_t little32(const uint8_t *bytes) {
    return (uint32_t)bytes[0] | ((uint32_t)bytes[1] << 8) |
           ((uint32_t)bytes[2] << 16) | ((uint32_t)bytes[3] << 24);
}

static const uint8_t *find_payload(CFDataRef data, size_t *size, int *count) {
    if (!data) return NULL;
    const uint8_t *bytes = CFDataGetBytePtr(data);
    const size_t length = (size_t)CFDataGetLength(data);
    const uint8_t *found = NULL;
    *count = 0;
    for (size_t offset = 4; offset + 4 <= length;) {
        unsigned words = bytes[offset] * 256u + bytes[offset + 1];
        unsigned tag = bytes[offset + 2] * 256u + bytes[offset + 3];
        unsigned type = tag >> 14;
        size_t fieldSize = type == 0 ? (words == 1 ? 8 : (words + 3) / 4 * 4) : words * 4;
        if (type == 2 || fieldSize == 0 || fieldSize > length - offset - 4) return NULL;
        if ((tag & 16383) == 4205) {
            found = bytes + offset + 4;
            *size = words;
            (*count)++;
        }
        offset += fieldSize + 4;
    }
    return found;
}

int iss_test_fixed_point(void) {
    int failures = 0;
    const struct { double input; int32_t expected; } cases[] = {
        {0, 0}, {-0.0, 0}, {1, 65536}, {-1, -65536}, {0.5, 32768},
        {1.0 / 65536, 1}, {-1.0 / 65536, -1},
        {DBL_TRUE_MIN, 1}, {-DBL_TRUE_MIN, -1},
        {9999, 655294464}, {-9999, -655294464},
        {(double)INT32_MAX / 65536, INT32_MAX}, {-32768, INT32_MIN},
        {32768, INT32_MAX}, {-32769, INT32_MIN},
        {DBL_MAX, INT32_MAX}, {-DBL_MAX, INT32_MIN}
    };
    for (size_t i = 0; i < sizeof(cases) / sizeof(cases[0]); i++) {
        int32_t result = 42;
        CHECK(iss_double_to_fixed1616(cases[i].input, &result));
        CHECK(result == cases[i].expected);
    }
    for (int i = 0; i < 3; i++) {
        const double invalid[] = {NAN, INFINITY, -INFINITY};
        int32_t result = 42;
        CHECK(!iss_double_to_fixed1616(invalid[i], &result));
        CHECK(result == 42);
    }
    CHECK(!iss_double_to_fixed1616(1, NULL));
    return failures;
}

int iss_test_serialized_payload(void) {
    int failures = 0;
    const uint8_t phases[] = {1, 2, 4};
    for (size_t i = 0; i < sizeof(phases); i++) {
        for (int sign = -1; sign <= 1; sign += 2) {
            CGEventRef event = iss_create_dock_swipe_event(phases[i], sign / 65536.0,
                                                          sign * 9999.0, true);
            CHECK(event != NULL);
            if (!event) continue;
            CFDataRef data = CGEventCreateData(NULL, event);
            size_t size = 0;
            int count = 0;
            const uint8_t *payload = find_payload(data, &size, &count);
            CHECK(payload != NULL);
            CHECK(count == 1);
            CHECK(size == (phases[i] == 4 ? 96 : 68));
            if (payload && size >= 68) {
                CHECK(little32(payload + 24) == (phases[i] == 4 ? 2 : 1));
                CHECK(little32(payload + 28) == 40);
                CHECK(little32(payload + 32) == 23);
                CHECK(little32(payload + 36) == (uint32_t)phases[i] << 24);
                CHECK(payload[60] == 1 && payload[61] == 0);
                CHECK(payload[62] == 3 && payload[63] == 0);
                CHECK((int32_t)little32(payload + 64) == sign);
                if (phases[i] == 4 && size == 96) {
                    CHECK(little32(payload + 68) == 28);
                    CHECK(little32(payload + 72) == 9);
                    CHECK(payload[80] == 1);
                    CHECK((int32_t)little32(payload + 84) == sign * 655294464);
                    CHECK(little32(payload + 88) == 0);
                }
            }
            // Re-augmentation replaces, rather than duplicates, field 4205.
            // Public-field edits must also update the embedded HID payload.
            CGEventSetDoubleValueField(event, (CGEventField)124, 0);
            CGEventSetDoubleValueField(event, (CGEventField)129, 0);
            CGEventRef neutral = iss_augment_dock_swipe_event(event);
            CHECK(neutral != NULL);
            if (neutral) {
                CFDataRef neutralData = CGEventCreateData(NULL, neutral);
                payload = find_payload(neutralData, &size, &count);
                CHECK(payload != NULL && count == 1);
                if (payload && size >= 68) CHECK(little32(payload + 64) == 0);
                if (payload && size == 96) CHECK(little32(payload + 84) == 0);
                if (neutralData) CFRelease(neutralData);
                CFRelease(neutral);
            }
            if (data) CFRelease(data);
            CFRelease(event);
        }
    }
    return failures;
}

int iss_test_serialized_validation(void) {
    int failures = 0;
    CGEventRef event = CGEventCreate(NULL);
    CHECK(event != NULL);
    if (!event) return failures;
    CHECK(iss_augment_dock_swipe_event(NULL) == NULL);
    CHECK(iss_copy_dock_swipe_data(event, NULL) == NULL);
    const struct { uint8_t bytes[12]; CFIndex size; } invalid[] = {
        {{0}, 0}, {{0, 0, 0}, 3}, {{0, 0, 0, 3}, 4},
        {{0, 0, 0, 2, 0}, 5}, // Truncated tag.
        {{0, 0, 0, 2, 0, 1, 0x40, 55}, 8}, // Missing integer.
        {{0, 0, 0, 2, 0, 1, 0, 58, 0, 0, 0, 0}, 12}, // Truncated int64.
        {{0, 0, 0, 2, 0, 5, 0x10, 0x6d, 0, 0, 0, 0}, 12}, // Truncated raw block.
        {{0, 0, 0, 2, 0, 1, 0x80, 55, 0, 0, 0, 0}, 12}, // Reserved type.
        {{0, 0, 0, 2, 0, 0, 0x40, 55}, 8} // Empty field.
    };
    for (size_t i = 0; i < sizeof(invalid) / sizeof(invalid[0]); i++) {
        CFDataRef data = CFDataCreate(NULL, invalid[i].bytes, invalid[i].size);
        CFDataRef result = iss_copy_dock_swipe_data(event, data);
        CHECK(result == NULL);
        if (result) CFRelease(result);
        CFRelease(data);
    }
    for (int i = 0; i < 3; i++) {
        const double invalidValue[] = {NAN, INFINITY, -INFINITY};
        CHECK(iss_create_dock_swipe_event(4, invalidValue[i], 9999, true) == NULL);
        CHECK(iss_create_dock_swipe_event(4, 1.0 / 65536, invalidValue[i], true) == NULL);
    }
    CFRelease(event);
    return failures;
}

int iss_test_synthetic_identity(void) {
    int failures = 0;
    CHECK(!iss_is_synthetic_event(NULL));
    iss_mark_synthetic_event(NULL);
    CGEventRef hardware = CGEventCreate(NULL);
    CHECK(hardware != NULL);
    if (!hardware) return failures;
    CGEventSetIntegerValueField(hardware, kCGEventSourceUnixProcessID, 0);
    CHECK(!iss_is_synthetic_event(hardware));
    CGEventSetIntegerValueField(hardware, kCGEventSourceUserData, 42);
    CHECK(!iss_is_synthetic_event(hardware));
    for (int modern = 0; modern <= 1; modern++) {
        CGEventRef synthetic = iss_create_dock_swipe_event(4, 1.0 / 65536, 9999, modern);
        CHECK(synthetic != NULL);
        if (!synthetic) continue;
        CHECK(iss_is_synthetic_event(synthetic));
        CGEventSetIntegerValueField(synthetic, kCGEventSourceUnixProcessID, 0);
        CHECK(iss_is_synthetic_event(synthetic));
        CHECK(!iss_is_synthetic_event(hardware)); // Interleaved physical input stays physical.
        CGEventRef copied = CGEventCreateCopy(synthetic);
        CHECK(iss_is_synthetic_event(copied));
        if (copied) CFRelease(copied);
        CFRelease(synthetic);
    }
    CFRelease(hardware);
    return failures;
}
