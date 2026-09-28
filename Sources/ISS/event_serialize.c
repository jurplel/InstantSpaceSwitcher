#include "event_serialize.h"

#include <ApplicationServices/ApplicationServices.h>
#include <CoreFoundation/CoreFoundation.h>
#include <mach/mach_time.h>
#include <math.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/sysctl.h>

#pragma pack(push, 1)

typedef struct {
    uint32_t size;
    uint32_t type;
    uint32_t options;
    uint8_t depth;
    uint8_t reserved[3];
} IOHIDEventBase;

typedef struct {
    IOHIDEventBase base;
    int32_t position_x;
    int32_t position_y;
    int32_t position_z;
    uint32_t swipe_mask;
    uint16_t gesture_motion;
    uint16_t gesture_flavor;
    int32_t swipe_progress;
} IOHIDFluidTouchGestureData;

typedef struct {
    IOHIDEventBase base;
    int32_t velocity_x;
    int32_t velocity_y;
    int32_t velocity_z;
} IOHIDVelocityEventData;

typedef struct {
    uint64_t timestamp;
    uint64_t sender_id;
    uint32_t options;
    uint32_t attribute_length;
    uint32_t event_count;
} IOHIDSystemQueueElementHeader;

#pragma pack(pop)

_Static_assert(sizeof(IOHIDEventBase) == 16, "unexpected IOHID base layout");
_Static_assert(sizeof(IOHIDFluidTouchGestureData) == 40, "unexpected swipe layout");
_Static_assert(sizeof(IOHIDVelocityEventData) == 28, "unexpected velocity layout");
_Static_assert(sizeof(IOHIDSystemQueueElementHeader) == 28, "unexpected queue layout");
_Static_assert(offsetof(IOHIDFluidTouchGestureData, swipe_progress) == 36,
               "unexpected progress offset");

// Mark after CGEventCreateFromData, which discards eventSourceUserData.
// This identifies ISS events even when a tap observes sourcePid == 0.
static const int64_t kISSSyntheticEventMarker = INT64_C(0x4953537769706531);

void iss_mark_synthetic_event(CGEventRef event) {
    if (event) CGEventSetIntegerValueField(event, kCGEventSourceUserData, kISSSyntheticEventMarker);
}

bool iss_is_synthetic_event(CGEventRef event) {
    return event && CGEventGetIntegerValueField(event, kCGEventSourceUserData) == kISSSyntheticEventMarker;
}

static const uint32_t kIOHIDEventTypeVelocity = 9;
static const uint32_t kIOHIDEventTypeFluidTouchGesture = 23;
static const uint16_t kIOHIDGestureFlavorDockPrimary = 3;

bool iss_double_to_fixed1616(double value, int32_t *result) {
    if (!result || !isfinite(value)) return false;
    // Check before multiplication and conversion. A cast outside int32_t's
    // range is undefined in C, including finite velocities from large jumps.
    if (value >= (double)INT32_MAX / 65536.0) {
        *result = INT32_MAX;
    } else if (value <= (double)INT32_MIN / 65536.0) {
        *result = INT32_MIN;
    } else {
        *result = (int32_t)(value * 65536.0);
        if (*result == 0 && value != 0.0) *result = value > 0.0 ? 1 : -1;
    }
    return true;
}

static uint8_t *iss_generate_iohid_payload(CGEventRef event, size_t *out_length) {
    int64_t phase = CGEventGetIntegerValueField(event, (CGEventField)132);
    int64_t motion = CGEventGetIntegerValueField(event, (CGEventField)123);
    double progress = CGEventGetDoubleValueField(event, (CGEventField)124);
    double pos_x = CGEventGetDoubleValueField(event, (CGEventField)125);
    double pos_y = CGEventGetDoubleValueField(event, (CGEventField)126);
    double vel_x = CGEventGetDoubleValueField(event, (CGEventField)129);
    double vel_y = CGEventGetDoubleValueField(event, (CGEventField)130);
    int64_t swipe_mask = CGEventGetIntegerValueField(event, (CGEventField)115);

    int32_t fixed_progress, fixed_pos_x, fixed_pos_y, fixed_vel_x, fixed_vel_y;
    if (!iss_double_to_fixed1616(progress, &fixed_progress) ||
        !iss_double_to_fixed1616(pos_x, &fixed_pos_x) ||
        !iss_double_to_fixed1616(pos_y, &fixed_pos_y) ||
        !iss_double_to_fixed1616(vel_x, &fixed_vel_x) ||
        !iss_double_to_fixed1616(vel_y, &fixed_vel_y)) return NULL;

    bool include_velocity = (vel_x != 0.0 || vel_y != 0.0 || phase == 4);
    uint32_t event_count = include_velocity ? 2 : 1;
    size_t payload_length = sizeof(IOHIDSystemQueueElementHeader) + sizeof(IOHIDFluidTouchGestureData);
    if (include_velocity) {
        payload_length += sizeof(IOHIDVelocityEventData);
    }

    uint8_t *payload = (uint8_t *)malloc(payload_length);
    if (!payload) {
        return NULL;
    }
    memset(payload, 0, payload_length);

    IOHIDSystemQueueElementHeader *header = (IOHIDSystemQueueElementHeader *)payload;
    uint64_t timestamp = CGEventGetTimestamp(event);
    if (timestamp == 0) {
        timestamp = mach_absolute_time();
    }
    header->timestamp = timestamp;
    header->sender_id = 0;
    header->options = 0;
    header->attribute_length = 0;
    header->event_count = event_count;

    IOHIDFluidTouchGestureData *fluid = (IOHIDFluidTouchGestureData *)(payload + sizeof(IOHIDSystemQueueElementHeader));
    fluid->base.size = sizeof(IOHIDFluidTouchGestureData);
    fluid->base.type = kIOHIDEventTypeFluidTouchGesture;
    fluid->base.options = (uint32_t)((phase & 0xFF) << 24);
    fluid->base.depth = 0;
    fluid->position_x = fixed_pos_x;
    fluid->position_y = fixed_pos_y;
    fluid->position_z = 0;
    fluid->swipe_mask = (uint32_t)swipe_mask;
    fluid->gesture_motion = (uint16_t)motion;
    fluid->gesture_flavor = kIOHIDGestureFlavorDockPrimary;
    fluid->swipe_progress = fixed_progress;

    if (include_velocity) {
        IOHIDVelocityEventData *velocity = (IOHIDVelocityEventData *)(payload + sizeof(IOHIDSystemQueueElementHeader) + sizeof(IOHIDFluidTouchGestureData));
        velocity->base.size = sizeof(IOHIDVelocityEventData);
        velocity->base.type = kIOHIDEventTypeVelocity;
        velocity->base.options = 0;
        velocity->base.depth = 1;
        velocity->velocity_x = fixed_vel_x;
        velocity->velocity_y = fixed_vel_y;
        velocity->velocity_z = 0;
    }

    *out_length = payload_length;
    return payload;
}

CFDataRef iss_copy_dock_swipe_data(CGEventRef event, CFDataRef serialized) {
    if (!event || !serialized) return NULL;
    const uint8_t *bytes = CFDataGetBytePtr(serialized);
    const CFIndex length = CFDataGetLength(serialized);
    if (length < 4 || memcmp(bytes, "\0\0\0\2", 4) != 0) return NULL;

    CFMutableDataRef result = CFDataCreateMutable(NULL, 0);
    if (!result) return NULL;
    CFDataAppendBytes(result, bytes, 4);

    // Format 2 uses big-endian tags. Type 0 holds either one 64-bit
    // integer or a byte block padded to four bytes; types 1 and 3 hold
    // four-byte words. Type 2 is reserved. Validate before copying.
    for (CFIndex offset = 4; offset < length;) {
        if (length - offset < 4) goto invalid;
        const uint16_t count = ((uint16_t)bytes[offset] << 8) | bytes[offset + 1];
        const uint16_t tag = ((uint16_t)bytes[offset + 2] << 8) | bytes[offset + 3];
        const unsigned type = tag >> 14;
        if (count == 0 || type == 2) goto invalid;
        const CFIndex size = type == 0
            ? (count == 1 ? 8 : ((CFIndex)count + 3) & ~3)
            : (CFIndex)count * 4;
        if (size > length - offset - 4) goto invalid;
        // Replace an existing payload instead of appending a duplicate.
        // This also permits rebuilding a consumed hardware terminal event.
        if ((tag & 0x3fff) != 4205) {
            CFDataAppendBytes(result, bytes + offset, 4 + size);
        }
        offset += 4 + size;
    }

    size_t payload_length = 0;
    uint8_t *payload = iss_generate_iohid_payload(event, &payload_length);
    if (!payload) {
        goto invalid;
    }
    const uint8_t tag[4] = {(uint8_t)(payload_length >> 8), (uint8_t)payload_length,
                            (uint8_t)(4205 >> 8), (uint8_t)(4205 & 0xff)};
    CFDataAppendBytes(result, tag, sizeof(tag));
    CFDataAppendBytes(result, payload, (CFIndex)payload_length);
    free(payload);
    return result;

invalid:
    CFRelease(result);
    return NULL;
}

CGEventRef iss_augment_dock_swipe_event(CGEventRef event) {
    if (!event) return NULL;
    CFDataRef data = CGEventCreateData(kCFAllocatorDefault, event);
    if (!data) return NULL;
    CFDataRef new_data = iss_copy_dock_swipe_data(event, data);
    CFRelease(data);
    if (!new_data) return NULL;
    CGEventRef result = CGEventCreateFromData(kCFAllocatorDefault, new_data);
    CFRelease(new_data);
    iss_mark_synthetic_event(result);
    return result;
}

bool iss_requires_event_augmentation(void) {
    static int cached_result = -1;
    if (cached_result != -1) {
        return cached_result;
    }

    const char *force_override = getenv("ISS_FORCE_EVENT_AUGMENTATION");
    if (force_override) {
        cached_result = (strcmp(force_override, "1") == 0) ? 1 : 0;
        return cached_result;
    }

    char version[32];
    size_t size = sizeof(version);
    if (sysctlbyname("kern.osproductversion", version, &size, NULL, 0) != 0) {
        cached_result = 0;
        return false;
    }

    int major = 0, minor = 0, patch = 0;
    int matched = sscanf(version, "%d.%d.%d", &major, &minor, &patch);
    if (matched < 1) {
        cached_result = 0;
        return false;
    }

    cached_result = (major >= 27) ? 1 : 0;
    return cached_result;
}
