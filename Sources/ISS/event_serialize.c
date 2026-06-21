#include "event_serialize.h"

#include <ApplicationServices/ApplicationServices.h>
#include <CoreFoundation/CoreFoundation.h>
#include <mach/mach_time.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/sysctl.h>

// MARK: - CGEventData serialization format
//
// CGEventCreateData() / CGEventCreateFromData() use a private, big-endian
// serialization format. On macOS 27, the Dock server no longer acts on the
// public CGEvent fields for synthetic dock-swipe events; it requires the raw
// IOHID event payload stored in field 4205.
//
// The layout below is reverse-engineered and matches the notes shared by the
// community in InstantSpaceSwitcher issue #72.

static const int8_t kCGEventDataTagInt64OrBinaryBlob = 0b00;
static const int8_t kCGEventDataTagInt32 = 0b01;
static const int8_t kCGEventDataTagFloatingPoint = 0b11;

static const uint16_t kCGEventFieldGestureRawDataPayload = 4205;

typedef struct {
    uint16_t field_id;
    uint8_t tag;
    uint16_t size_words;
    uint8_t *payload;
    size_t payload_length;
} ISSCGEventParsedField;

typedef struct {
    int32_t version;
    ISSCGEventParsedField *fields;
    size_t field_count;
    size_t field_capacity;
} ISSCGEventParsedData;

static uint16_t iss_read_be16(const uint8_t *data, size_t offset) {
    return (uint16_t)((data[offset] << 8) | data[offset + 1]);
}

static uint32_t iss_read_be32(const uint8_t *data, size_t offset) {
    return ((uint32_t)data[offset] << 24) |
           ((uint32_t)data[offset + 1] << 16) |
           ((uint32_t)data[offset + 2] << 8) |
           (uint32_t)data[offset + 3];
}

static int32_t iss_read_signed_be32(const uint8_t *data, size_t offset) {
    return (int32_t)iss_read_be32(data, offset);
}

static void iss_write_be16(uint8_t *out, size_t offset, uint16_t value) {
    out[offset] = (uint8_t)((value >> 8) & 0xFF);
    out[offset + 1] = (uint8_t)(value & 0xFF);
}

static void iss_write_be32(uint8_t *out, size_t offset, uint32_t value) {
    out[offset] = (uint8_t)((value >> 24) & 0xFF);
    out[offset + 1] = (uint8_t)((value >> 16) & 0xFF);
    out[offset + 2] = (uint8_t)((value >> 8) & 0xFF);
    out[offset + 3] = (uint8_t)(value & 0xFF);
}

static void iss_parsed_event_data_free(ISSCGEventParsedData *parsed) {
    if (!parsed || !parsed->fields) {
        return;
    }
    for (size_t i = 0; i < parsed->field_count; i++) {
        free(parsed->fields[i].payload);
    }
    free(parsed->fields);
    parsed->fields = NULL;
    parsed->field_count = 0;
    parsed->field_capacity = 0;
}

static bool iss_parse_event_data(const uint8_t *data, size_t length, ISSCGEventParsedData *out) {
    memset(out, 0, sizeof(*out));

    if (length < 4) {
        return false;
    }

    out->version = iss_read_signed_be32(data, 0);
    if (out->version != 2) {
        fprintf(stderr, "ISS: unsupported CGEvent data version %d\n", out->version);
        return false;
    }

    out->field_capacity = 16;
    out->fields = (ISSCGEventParsedField *)calloc(out->field_capacity, sizeof(ISSCGEventParsedField));
    if (!out->fields) {
        return false;
    }

    size_t offset = 4;
    while (offset < length) {
        if (offset + 4 > length) {
            iss_parsed_event_data_free(out);
            return false;
        }

        uint16_t size_words = iss_read_be16(data, offset);
        uint16_t tag_and_field = iss_read_be16(data, offset + 2);
        uint8_t tag = (uint8_t)((tag_and_field >> 14) & 0x3);
        uint16_t field_id = (uint16_t)(tag_and_field & 0x3FFF);
        offset += 4;

        size_t payload_length = 0;
        switch (tag) {
        case kCGEventDataTagInt64OrBinaryBlob:
            if (size_words == 1) {
                payload_length = 8;
            } else if (size_words > 1) {
                payload_length = size_words;
            } else {
                iss_parsed_event_data_free(out);
                return false;
            }
            break;
        case kCGEventDataTagInt32:
            payload_length = (size_t)size_words * 4;
            break;
        case kCGEventDataTagFloatingPoint:
            payload_length = (size_t)size_words * 4;
            break;
        default:
            iss_parsed_event_data_free(out);
            return false;
        }

        if (offset + payload_length > length) {
            iss_parsed_event_data_free(out);
            return false;
        }

        if (out->field_count >= out->field_capacity) {
            size_t new_capacity = out->field_capacity * 2;
            ISSCGEventParsedField *new_fields = (ISSCGEventParsedField *)realloc(out->fields, new_capacity * sizeof(ISSCGEventParsedField));
            if (!new_fields) {
                iss_parsed_event_data_free(out);
                return false;
            }
            out->fields = new_fields;
            out->field_capacity = new_capacity;
        }

        ISSCGEventParsedField *field = &out->fields[out->field_count++];
        field->field_id = field_id;
        field->tag = tag;
        field->size_words = size_words;
        field->payload_length = payload_length;
        if (payload_length > 0) {
            field->payload = (uint8_t *)malloc(payload_length);
            if (!field->payload) {
                iss_parsed_event_data_free(out);
                return false;
            }
            memcpy(field->payload, data + offset, payload_length);
        } else {
            field->payload = NULL;
        }
        offset += payload_length;
    }

    return true;
}

static size_t iss_compute_serialized_length(const ISSCGEventParsedData *parsed, size_t new_payload_length) {
    size_t len = 4; // version
    bool has4205 = false;
    for (size_t i = 0; i < parsed->field_count; i++) {
        if (parsed->fields[i].field_id == kCGEventFieldGestureRawDataPayload) {
            len += 4 + new_payload_length;
            has4205 = true;
        } else {
            len += 4 + parsed->fields[i].payload_length;
        }
    }
    if (!has4205) {
        len += 4 + new_payload_length;
    }
    return len;
}

static uint8_t *iss_serialize_event_data(const ISSCGEventParsedData *parsed,
                                         const uint8_t *new_payload,
                                         size_t new_payload_length,
                                         size_t *out_length) {
    size_t total_length = iss_compute_serialized_length(parsed, new_payload_length);
    uint8_t *result = (uint8_t *)malloc(total_length);
    if (!result) {
        return NULL;
    }

    size_t offset = 0;
    iss_write_be32(result, offset, (uint32_t)parsed->version);
    offset += 4;

    bool added4205 = false;
    for (size_t i = 0; i < parsed->field_count; i++) {
        const ISSCGEventParsedField *field = &parsed->fields[i];
        if (field->field_id == kCGEventFieldGestureRawDataPayload) {
            iss_write_be16(result, offset, (uint16_t)new_payload_length);
            offset += 2;
            uint16_t tag_and_field = (uint16_t)((kCGEventDataTagInt64OrBinaryBlob << 14) | kCGEventFieldGestureRawDataPayload);
            iss_write_be16(result, offset, tag_and_field);
            offset += 2;
            memcpy(result + offset, new_payload, new_payload_length);
            offset += new_payload_length;
            added4205 = true;
        } else {
            iss_write_be16(result, offset, field->size_words);
            offset += 2;
            uint16_t tag_and_field = (uint16_t)((field->tag << 14) | field->field_id);
            iss_write_be16(result, offset, tag_and_field);
            offset += 2;
            memcpy(result + offset, field->payload, field->payload_length);
            offset += field->payload_length;
        }
    }

    if (!added4205) {
        iss_write_be16(result, offset, (uint16_t)new_payload_length);
        offset += 2;
        uint16_t tag_and_field = (uint16_t)((kCGEventDataTagInt64OrBinaryBlob << 14) | kCGEventFieldGestureRawDataPayload);
        iss_write_be16(result, offset, tag_and_field);
        offset += 2;
        memcpy(result + offset, new_payload, new_payload_length);
        offset += new_payload_length;
    }

    *out_length = offset;
    return result;
}

// MARK: - IOHID payload generation

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

static const uint32_t kIOHIDEventTypeVelocity = 9;
static const uint32_t kIOHIDEventTypeFluidTouchGesture = 23;
static const uint16_t kIOHIDGestureMotionHorizontalX = 1;
static const uint16_t kIOHIDGestureFlavorDockPrimary = 3;

static int32_t iss_double_to_fixed1616(double val) {
    int32_t fixed = (int32_t)(val * 65536.0);
    if (fixed == 0 && val != 0.0) {
        return val > 0.0 ? 1 : -1;
    }
    return fixed;
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

    size_t offset = 0;

    IOHIDSystemQueueElementHeader *header = (IOHIDSystemQueueElementHeader *)(payload + offset);
    offset += sizeof(IOHIDSystemQueueElementHeader);

    uint64_t timestamp = CGEventGetTimestamp(event);
    if (timestamp == 0) {
        timestamp = mach_absolute_time();
    }
    header->timestamp = timestamp;
    header->sender_id = 0;
    header->options = 0;
    header->attribute_length = 0;
    header->event_count = event_count;

    IOHIDFluidTouchGestureData *fluid = (IOHIDFluidTouchGestureData *)(payload + offset);
    offset += sizeof(IOHIDFluidTouchGestureData);
    fluid->base.size = sizeof(IOHIDFluidTouchGestureData);
    fluid->base.type = kIOHIDEventTypeFluidTouchGesture;
    fluid->base.options = (uint32_t)((phase & 0xFF) << 24);
    fluid->base.depth = 0;
    fluid->position_x = iss_double_to_fixed1616(pos_x);
    fluid->position_y = iss_double_to_fixed1616(pos_y);
    fluid->position_z = 0;
    fluid->swipe_mask = (uint32_t)swipe_mask;
    fluid->gesture_motion = (uint16_t)motion;
    fluid->gesture_flavor = kIOHIDGestureFlavorDockPrimary;
    fluid->swipe_progress = iss_double_to_fixed1616(progress);

    if (include_velocity) {
        IOHIDVelocityEventData *velocity = (IOHIDVelocityEventData *)(payload + offset);
        velocity->base.size = sizeof(IOHIDVelocityEventData);
        velocity->base.type = kIOHIDEventTypeVelocity;
        velocity->base.options = 0;
        velocity->base.depth = 1;
        velocity->velocity_x = iss_double_to_fixed1616(vel_x);
        velocity->velocity_y = iss_double_to_fixed1616(vel_y);
        velocity->velocity_z = 0;
    }

    *out_length = payload_length;
    return payload;
}

// MARK: - Public API

CGEventRef iss_augment_dock_swipe_event(CGEventRef event) {
    if (!event) {
        return NULL;
    }

    CFDataRef data = CGEventCreateData(kCFAllocatorDefault, event);
    if (!data) {
        fprintf(stderr, "ISS: CGEventCreateData failed during augmentation\n");
        return NULL;
    }

    const uint8_t *bytes = CFDataGetBytePtr(data);
    CFIndex length = CFDataGetLength(data);

    ISSCGEventParsedData parsed = {0};
    if (!iss_parse_event_data(bytes, (size_t)length, &parsed)) {
        CFRelease(data);
        return NULL;
    }

    size_t payload_length = 0;
    uint8_t *payload = iss_generate_iohid_payload(event, &payload_length);
    if (!payload) {
        fprintf(stderr, "ISS: failed to generate IOHID payload\n");
        iss_parsed_event_data_free(&parsed);
        CFRelease(data);
        return NULL;
    }

    size_t new_length = 0;
    uint8_t *new_bytes = iss_serialize_event_data(&parsed, payload, payload_length, &new_length);
    iss_parsed_event_data_free(&parsed);
    free(payload);
    CFRelease(data);

    if (!new_bytes) {
        fprintf(stderr, "ISS: failed to serialize augmented CGEvent\n");
        return NULL;
    }

    CFDataRef new_data = CFDataCreate(kCFAllocatorDefault, new_bytes, (CFIndex)new_length);
    free(new_bytes);
    if (!new_data) {
        return NULL;
    }

    CGEventRef result = CGEventCreateFromData(kCFAllocatorDefault, new_data);
    CFRelease(new_data);
    if (!result) {
        fprintf(stderr, "ISS: CGEventCreateFromData failed during augmentation\n");
    }

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
