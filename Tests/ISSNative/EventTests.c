#include "../../Sources/ISS/event_serialize.h"
#include <assert.h>
#include <float.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static uint32_t read_u32(const uint8_t *bytes) {
    uint32_t value;
    memcpy(&value, bytes, sizeof(value));
    return CFSwapInt32LittleToHost(value);
}

static const uint8_t *payload_in(CFDataRef data, unsigned int length) {
    const uint8_t *bytes = CFDataGetBytePtr(data);
    CFIndex count = CFDataGetLength(data);
    for (CFIndex i = 0; i + 4 + length <= count; i++) {
        if (bytes[i] == 0 && bytes[i + 1] == length &&
            bytes[i + 2] == 0x10 && bytes[i + 3] == 0x6d) {
            return bytes + i + 4;
        }
    }
    return NULL;
}

static void test_sign_selection(void) {
    const char *current[] = {"26A428", "26A5416b", "26A6000", "26B5000", "27A5000", "", NULL};
    for (unsigned int i = 0; i < sizeof(current) / sizeof(current[0]); i++) {
        assert(iss_invert_swipe_for_build(current[i], true));
        assert(!iss_invert_swipe_for_build(current[i], false));
    }
    assert(iss_invert_swipe_for_build("26A5388g", false));
    assert(iss_invert_swipe_for_build("26A5415a", false));
    assert(iss_invert_swipe_for_build("26A5000", false));
    assert(!iss_invert_swipe_for_build("26A4999", false));
}

static void test_events(void) {
    const int phases[] = {1, 2, 4};
    for (int modern = 0; modern <= 1; modern++) {
        for (int inverted = 0; inverted <= 1; inverted++) {
            for (int right = 0; right <= 1; right++) {
                for (int i = 0; i < 3; i++) {
                    int phase = phases[i];
                    CGEventRef event = iss_create_dock_swipe_event(phase, right, 2000, modern, inverted);
                    assert(event);
                    double sign = right ? 1 : -1;
                    if (modern && inverted) sign = -sign;
                    assert(CGEventGetIntegerValueField(event, 55) == 30);
                    assert(CGEventGetIntegerValueField(event, 110) == 23);
                    assert(CGEventGetIntegerValueField(event, 123) == 1);
                    assert(CGEventGetIntegerValueField(event, 132) == phase);
                    assert(CGEventGetIntegerValueField(event, kCGEventSourceUserData) == 0x495353);
                    assert(CGEventGetDoubleValueField(event, 124) * sign > 0);
                    double expectedVelocity = modern && phase != 4 ? 0 : sign * 2000;
                    assert(CGEventGetDoubleValueField(event, 129) == expectedVelocity);
                    assert(CGEventGetDoubleValueField(event, 130) == (modern ? 0 : sign * 2000));
                    CFDataRef data = CGEventCreateData(NULL, event);
                    assert(data);
                    unsigned int length = phase == 4 ? 96 : 68;
                    const uint8_t *payload = payload_in(data, length);
                    if (modern) {
                        assert(payload);
                        assert(CGEventGetIntegerValueField(event, 134) == phase);
                        assert(read_u32(payload + 24) == (phase == 4 ? 2 : 1));
                        assert(read_u32(payload + 28) == 40);
                        assert(read_u32(payload + 32) == 23);
                        assert(read_u32(payload + 36) == (uint32_t)phase << 24);
                        assert((int32_t)read_u32(payload + 64) == (int32_t)(sign * (phase == 1 ? 1 : 65536)));
                        if (phase == 4) {
                            assert(read_u32(payload + 68) == 28);
                            assert(read_u32(payload + 72) == 9);
                            assert(payload[80] == 1);
                            assert((int32_t)read_u32(payload + 84) == (int32_t)(sign * 2000 * 65536));
                        }
                    } else {
                        assert(!payload);
                        assert(CGEventGetDoubleValueField(event, 124) == sign * FLT_TRUE_MIN);
                    }
                    CFRelease(data);
                    CFRelease(event);
                }
            }
        }
    }
}

static void test_invalid_and_extreme_values(void) {
    assert(!iss_augment_dock_swipe_event(NULL));
    const double invalid[] = {0, -1, NAN, INFINITY, -INFINITY};
    for (unsigned int i = 0; i < sizeof(invalid) / sizeof(invalid[0]); i++) {
        assert(!iss_create_dock_swipe_event(4, ISSDirectionRight, invalid[i], true, false));
    }
    assert(!iss_create_dock_swipe_event(8, ISSDirectionRight, 2000, true, false));
    assert(!iss_create_dock_swipe_event(4, 2, 2000, true, false));
    for (int right = 0; right <= 1; right++) {
        CGEventRef event = iss_create_dock_swipe_event(4, right, DBL_MAX, true, false);
        assert(event);
        CFDataRef data = CGEventCreateData(NULL, event);
        assert(data);
        const uint8_t *payload = payload_in(data, 96);
        assert(payload);
        assert((int32_t)read_u32(payload + 84) == (right ? INT32_MAX : INT32_MIN));
        CFRelease(data);
        CFRelease(event);
    }
}

static bool verify_move(ISSDirection direction, const ISSSpaceInfo *before) {
    unsigned int expected = direction == ISSDirectionRight ? before->currentIndex + 1 : before->currentIndex - 1;
    iss_reset_predictions();
    if (!iss_switch(direction)) return false;
    bool reached = false;
    ISSSpaceInfo after = {0};
    for (int i = 0; i < 20; i++) {
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.1, false);
        if (!iss_get_space_info(&after) || strcmp(before->displayID, after.displayID) != 0) return false;
        if (after.currentIndex == expected) reached = true;
        if (after.currentIndex != before->currentIndex && after.currentIndex != expected) break;
    }
    printf("display=%s from=%u expected=%u actual=%u confirmed=%d\n",
           before->displayID, before->currentIndex, expected, after.currentIndex, reached);
    return reached && after.currentIndex == expected;
}

static int test_live_round_trip(void) {
    ISSSpaceInfo before, adjacent;
    if (!AXIsProcessTrusted() || !iss_get_space_info(&before) || before.spaceCount < 2) {
        fputs("Live test requires Accessibility permission and at least two spaces.\n", stderr);
        return 1;
    }
    if (!iss_init()) return 1;
    iss_set_swipe_override(true);
    ISSDirection direction = before.currentIndex + 1 < before.spaceCount ? ISSDirectionRight : ISSDirectionLeft;
    bool success = verify_move(direction, &before) && iss_get_space_info(&adjacent) &&
        verify_move(direction == ISSDirectionRight ? ISSDirectionLeft : ISSDirectionRight, &adjacent);
    iss_destroy();
    return success ? 0 : 1;
}

int main(void) {
    test_sign_selection();
    test_events();
    test_invalid_and_extreme_values();
    puts("PASS: sign selection, legacy/modern events, HID payloads, invalid inputs, fixed-point bounds");
    const char *live = getenv("ISS_TEST_LIVE");
    return live && strcmp(live, "1") == 0 ? test_live_round_trip() : 0;
}
