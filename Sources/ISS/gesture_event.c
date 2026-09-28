#include "gesture_event.h"
#include "event_serialize.h"

#include <mach/mach_time.h>
#include <math.h>

CGEventRef iss_create_dock_swipe_event(uint8_t phase, double progress,
                                      double velocity, bool augment) {
    if (!isfinite(progress) || !isfinite(velocity)) return NULL;
    CGEventRef event = CGEventCreate(NULL);
    if (!event) return NULL;

    CGEventSetIntegerValueField(event, (CGEventField)55, 30); // DockControl
    CGEventSetIntegerValueField(event, (CGEventField)110, 23); // DockSwipe
    CGEventSetIntegerValueField(event, (CGEventField)132, phase);
    CGEventSetDoubleValueField(event, (CGEventField)124, progress);
    CGEventSetIntegerValueField(event, (CGEventField)123, 1); // Horizontal

    if (augment) {
        CGEventSetIntegerValueField(event, (CGEventField)134, phase);
        CGEventSetDoubleValueField(event, (CGEventField)138, 3.0);
        CGEventSetDoubleValueField(event, (CGEventField)169, (double)mach_absolute_time());
        CGEventSetDoubleValueField(event, (CGEventField)125, 0.1);
        // Match the existing macOS 27 path: only Ended carries velocity.
        if (phase == 4) {
            CGEventSetDoubleValueField(event, (CGEventField)129, velocity);
        }
        CGEventRef augmented = iss_augment_dock_swipe_event(event);
        CFRelease(event);
        return augmented;
    }

    CGEventSetDoubleValueField(event, (CGEventField)129, velocity);
    CGEventSetDoubleValueField(event, (CGEventField)130, velocity);
    iss_mark_synthetic_event(event);
    return event;
}
