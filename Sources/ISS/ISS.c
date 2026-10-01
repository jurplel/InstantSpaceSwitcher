#include "include/ISS.h"

#include <ApplicationServices/ApplicationServices.h>
#include <CoreFoundation/CoreFoundation.h>
#include <CoreGraphics/CGEventTypes.h>
#include <assert.h>
#include <dlfcn.h>
#include <float.h>
#include <math.h>
#include <stdbool.h>
#include <stdio.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

static const CGEventField kCGSEventTypeField = (CGEventField)55;
static const CGEventField kCGEventGestureHIDType = (CGEventField)110;
static const CGEventField kCGEventGestureSwipeMotion = (CGEventField)123;
static const CGEventField kCGEventGestureSwipeProgress = (CGEventField)124;
static const CGEventField kCGEventGestureSwipeVelocityX = (CGEventField)129;
static const CGEventField kCGEventGestureSwipeVelocityY = (CGEventField)130;
static const CGEventField kCGEventGesturePhase = (CGEventField)132;

// See IOHIDEventType enum in IOHIDFamily
static const uint32_t kIOHIDEventTypeDockSwipe = 23;

typedef uint32_t CGSEventType;
enum {
    kCGSEventScrollWheel = 22,
    kCGSEventZoom = 28,
    kCGSEventGesture = 29,
    kCGSEventDockControl = 30,
    kCGSEventFluidTouchGesture = 31,
};

typedef CF_ENUM(uint8_t, CGSGesturePhase) {
    kCGSGesturePhaseNone = 0,
    kCGSGesturePhaseBegan = 1,
    kCGSGesturePhaseChanged = 2,
    kCGSGesturePhaseEnded = 4,
    kCGSGesturePhaseCancelled = 8,
    kCGSGesturePhaseMayBegin = 128,
};

// Limited subset of motion constants observed in synthetic Dock swipe traces.
typedef CF_ENUM(uint16_t, CGGestureMotion) {
    kCGGestureMotionHorizontal = 1,
};

typedef int32_t CGSConnectionID;
typedef uint64_t CGSSpaceID;

extern CFArrayRef CGSCopyManagedDisplaySpaces(CGSConnectionID connection, CFStringRef display) __attribute__((weak_import));
extern CFStringRef CGSCopyActiveMenuBarDisplayIdentifier(CGSConnectionID connection) __attribute__((weak_import));
extern CGSConnectionID CGSMainConnectionID(void) __attribute__((weak_import));
extern CGSSpaceID CGSGetActiveSpace(CGSConnectionID connection) __attribute__((weak_import));

extern CFArrayRef CGSCopySpacesForWindows(CGSConnectionID connection, int mask, CFArrayRef windows) __attribute__((weak_import));

static CGPoint gestureLocation;
static bool hasGestureLocation = false;

static CFMachPortRef globalTap = NULL;
static CFRunLoopSourceRef globalSource = NULL;

// Overlay detection state
static bool overlayDetectionEnabled = false;

// Swipe override state
static bool swipeOverrideEnabled = false;
static bool swipeTracking = false;
static bool swipeFired = false;

// Gesture speed state
static double gestureSpeed = ISS_DEFAULT_GESTURE_SPEED;
static double animationDuration = 0.0;
static double animationEaseIn = 0.1;
static double animationEaseOut = 0.1;

static ISSSwitchCallback switchCallback = NULL;
static ISSUserInputCallback userInputCallback = NULL;

void iss_set_user_input_callback(ISSUserInputCallback callback) {
    userInputCallback = callback;
}

// Shared with regression tests. Only observes; never edits or consumes events.
void iss_observe_user_input(CGEventType type, CGEventRef event) {
    if (!userInputCallback || !event) return;
    // Our synthetic swipe must not look like a physical Space navigation.
    if (CGEventGetIntegerValueField(event, kCGEventSourceUnixProcessID) != 0) return;
    if (type == kCGEventKeyDown) {
        int64_t key = CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode);
        CGEventFlags flags = CGEventGetFlags(event);
        if (key == 48 && (flags & kCGEventFlagMaskCommand)) {
            userInputCallback(ISSUserInputCommandTab);
        } else if ((key == 123 || key == 124) && (flags & kCGEventFlagMaskControl)) {
            userInputCallback(ISSUserInputSpaceNavigation);
        }
    } else if (type == kCGEventLeftMouseDown) {
        userInputCallback(ISSUserInputMouseClick);
    } else if (CGEventGetIntegerValueField(event, kCGSEventTypeField) == kCGSEventDockControl &&
               CGEventGetIntegerValueField(event, kCGEventGestureHIDType) == kIOHIDEventTypeDockSwipe &&
               CGEventGetIntegerValueField(event, kCGEventGestureSwipeMotion) == kCGGestureMotionHorizontal) {
        userInputCallback(ISSUserInputSpaceNavigation);
    }
}

// Predictions dictionary: DisplayID (CFStringRef) -> Index (CFNumberRef)
static CFMutableDictionaryRef predictionsDict = NULL;

static bool get_prediction(const char *displayID, unsigned int *outIndex) {
    if (!displayID || !predictionsDict) return false;
    
    CFStringRef key = CFStringCreateWithCString(NULL, displayID, kCFStringEncodingUTF8);
    const void *value = CFDictionaryGetValue(predictionsDict, key);
    CFRelease(key);

    if (value) {
        CFNumberGetValue((CFNumberRef)value, kCFNumberIntType, outIndex);
        return true;
    }
    return false;
}

static void set_prediction(const char *displayID, unsigned int index) {
    if (!displayID || !predictionsDict) return;
    
    CFStringRef key = CFStringCreateWithCString(NULL, displayID, kCFStringEncodingUTF8);
    CFNumberRef val = CFNumberCreate(NULL, kCFNumberIntType, &index);
    CFDictionarySetValue(predictionsDict, key, val);
    CFRelease(key);
    CFRelease(val);
}

static bool extract_space_info_from_display(CFDictionaryRef displayDict,
                                            CGSSpaceID activeSpace,
                                            bool hasActiveSpace,
                                            ISSSpaceInfo *outInfo);
static bool load_space_info_for_display(ISSSpaceInfo *info, bool useCursorDisplay);
static bool iss_perform_switch_gesture(ISSDirection direction, double velocity);
static bool iss_switch_with_info(const ISSSpaceInfo *info, ISSDirection direction);
static bool iss_should_block_switch(const ISSSpaceInfo *info, ISSDirection direction);

// Perform a swipe-override switch: get space info, compute target, switch,
// and notify the handler with the target index.
static void swipe_override_switch(ISSDirection dir) {
    ISSSpaceInfo info;
    if (!iss_get_space_info(&info)) {
        iss_perform_switch_gesture(dir, gestureSpeed);
        return;
    }

    unsigned int predicted;
    unsigned int current = get_prediction(info.displayID, &predicted) ? predicted : info.currentIndex;
    unsigned int target = dir == ISSDirectionLeft ? current - 1 : current + 1;

    if (iss_switch_with_info(&info, dir)) {
        set_prediction(info.displayID, target);
        if (switchCallback) { switchCallback(target); }
    }
}

static CGEventRef eventTapCallback(CGEventTapProxy proxy, CGEventType type,
                                   CGEventRef event, void *refcon) {
    (void)proxy;
    (void)refcon;

    // Re-enable if the system disabled our tap for being too slow
    if (type == kCGEventTapDisabledByTimeout || type == kCGEventTapDisabledByUserInput) {
        if (globalTap) CGEventTapEnable(globalTap, true);
        return event;
    }

    iss_observe_user_input(type, event);
    if (!swipeOverrideEnabled) return event;

    CGSEventType eventType =
        (CGSEventType)CGEventGetIntegerValueField(event, kCGSEventTypeField);

    // Pass through synthetic events (non-HID source). Real gesture events
    // from the trackpad have sourcePid == 0 (HID kernel).
    if (eventType == kCGSEventDockControl || eventType == kCGSEventGesture) {
        pid_t sourcePid = (pid_t)CGEventGetIntegerValueField(event, kCGEventSourceUnixProcessID);
        if (sourcePid != 0) return event;
    }

    if (eventType == kCGSEventDockControl) {
        uint32_t hidType =
            (uint32_t)CGEventGetIntegerValueField(event, kCGEventGestureHIDType);
        if (hidType != kIOHIDEventTypeDockSwipe) return event;

        uint16_t motion =
            (uint16_t)CGEventGetIntegerValueField(event, kCGEventGestureSwipeMotion);
        if (motion != kCGGestureMotionHorizontal) return event;

        CGSGesturePhase phase =
            (CGSGesturePhase)CGEventGetIntegerValueField(event, kCGEventGesturePhase);

        switch (phase) {
        case kCGSGesturePhaseBegan:
            if (iss_is_expose_active()) return event;
            swipeTracking = true;
            swipeFired = false;
            return NULL;

        case kCGSGesturePhaseChanged: {
            if (!swipeTracking) return event;
            if (!swipeFired) {
                double progress =
                    CGEventGetDoubleValueField(event, kCGEventGestureSwipeProgress);
                if (progress != 0.0) {
                    ISSDirection dir =
                        progress > 0 ? ISSDirectionRight : ISSDirectionLeft;
                    swipeFired = true;
                    swipe_override_switch(dir);
                }
            }
            return NULL;
        }

        case kCGSGesturePhaseEnded: {
            if (!swipeTracking) return event;
            if (!swipeFired) {
                double velocity =
                    CGEventGetDoubleValueField(event, kCGEventGestureSwipeVelocityX);
                if (velocity != 0.0) {
                    ISSDirection dir =
                        velocity > 0 ? ISSDirectionRight : ISSDirectionLeft;
                    swipeFired = true;
                    swipe_override_switch(dir);
                }
            }
            swipeTracking = false;
            swipeFired = false;
            return NULL;
        }

        case kCGSGesturePhaseCancelled:
            swipeTracking = false;
            swipeFired = false;
            return NULL;

        default:
            return swipeTracking ? NULL : event;
        }
    }

    // Suppress companion gesture events during active swipe tracking
    if (eventType == kCGSEventGesture && swipeTracking) {
        return NULL;
    }

    return event;
}

static bool cgs_symbols_available(void) {
    return (&CGSMainConnectionID != NULL) &&
           (&CGSGetActiveSpace != NULL) &&
           (&CGSCopyManagedDisplaySpaces != NULL);
}

static bool extract_space_info_from_display(CFDictionaryRef displayDict,
                                            CGSSpaceID activeSpace,
                                            bool hasActiveSpace,
                                            ISSSpaceInfo *outInfo) {
    if (!displayDict || !outInfo) {
        return false;
    }

    memset(outInfo->displayID, 0, sizeof(outInfo->displayID));
    CFStringRef identifier = (CFStringRef)CFDictionaryGetValue(displayDict, CFSTR("Display Identifier"));
    if (identifier && CFGetTypeID(identifier) == CFStringGetTypeID()) {
        CFStringGetCString(identifier, outInfo->displayID, sizeof(outInfo->displayID), kCFStringEncodingUTF8);
    }

    const void *spacesValue = CFDictionaryGetValue(displayDict, CFSTR("Spaces"));
    if (!spacesValue || CFGetTypeID(spacesValue) != CFArrayGetTypeID()) {
        return false;
    }

    // Try to get current space from display dict (more accurate per-display)
    CGSSpaceID displayActiveSpace = 0;
    const void *currentSpaceValue = CFDictionaryGetValue(displayDict, CFSTR("Current Space"));
    if (currentSpaceValue && CFGetTypeID(currentSpaceValue) == CFDictionaryGetTypeID()) {
        CFDictionaryRef currentSpaceDict = (CFDictionaryRef)currentSpaceValue;
        CFNumberRef currentSpaceID = (CFNumberRef)CFDictionaryGetValue(currentSpaceDict, CFSTR("id64"));
        if (currentSpaceID && CFGetTypeID(currentSpaceID) == CFNumberGetTypeID()) {
            CFNumberGetValue(currentSpaceID, kCFNumberSInt64Type, &displayActiveSpace);
        }
    }
    
    // Use display-specific active space if available, otherwise use global
    CGSSpaceID targetActiveSpace = displayActiveSpace != 0 ? displayActiveSpace : activeSpace;
    bool hasTargetActiveSpace = displayActiveSpace != 0 || hasActiveSpace;

    CFArrayRef spaces = (CFArrayRef)spacesValue;
    const CFIndex spaceCount = CFArrayGetCount(spaces);

    unsigned int totalSpaces = 0;
    unsigned int activeIndex = 0;
    bool foundActive = false;

    for (CFIndex i = 0; i < spaceCount; i++) {
        const void *spaceValue = CFArrayGetValueAtIndex(spaces, i);
        if (!spaceValue || CFGetTypeID(spaceValue) != CFDictionaryGetTypeID()) {
            continue;
        }

        CFDictionaryRef spaceDict = (CFDictionaryRef)spaceValue;
        CFNumberRef idNumber = (CFNumberRef)CFDictionaryGetValue(spaceDict, CFSTR("id64"));
        if (!idNumber || CFGetTypeID(idNumber) != CFNumberGetTypeID()) {
            continue;
        }

        CGSSpaceID candidate = 0;
        if (CFNumberGetValue(idNumber, kCFNumberSInt64Type, &candidate)) {
            if (!foundActive && hasTargetActiveSpace && candidate == targetActiveSpace) {
                activeIndex = totalSpaces;
                foundActive = true;
            }
            totalSpaces++;
        }
    }

    if (totalSpaces == 0 || (hasTargetActiveSpace && !foundActive)) {
        return false;
    }

    outInfo->spaceCount = totalSpaces;
    outInfo->currentIndex = foundActive ? activeIndex : 0;
    return true;
}

static bool load_space_info_for_display(ISSSpaceInfo *info, bool useCursorDisplay) {
    if (!cgs_symbols_available()) {
        fprintf(stderr, "ISS: required CGS symbols missing\n");
        return false;
    }

    CGSConnectionID connection = CGSMainConnectionID();
    if (connection == 0) {
        fprintf(stderr, "ISS: CGSMainConnectionID returned 0\n");
        return false;
    }

    CGSSpaceID activeSpace = 0;
    bool hasActiveSpace = false;
    if (&CGSGetActiveSpace != NULL) {
        activeSpace = CGSGetActiveSpace(connection);
        if (activeSpace != 0) {
            hasActiveSpace = true;
        } else {
            fprintf(stderr, "ISS: CGSGetActiveSpace returned 0\n");
            return false;
        }
    }

    // Get display identifier based on mode
    CFStringRef activeDisplayIdentifier = NULL;
    
    if (useCursorDisplay) {
        // Get display where cursor is located
        CGEventRef tempEvent = CGEventCreate(NULL);
        if (tempEvent) {
            CGPoint cursorLocation = CGEventGetLocation(tempEvent);
            CFRelease(tempEvent);

            CGDirectDisplayID cursorDisplay = 0;
            uint32_t cursorDisplayCount = 0;

            if (CGGetDisplaysWithPoint(cursorLocation, 1, &cursorDisplay, &cursorDisplayCount) == kCGErrorSuccess && cursorDisplayCount > 0) {
                CFUUIDRef displayUUID = CGDisplayCreateUUIDFromDisplayID(cursorDisplay);
                if (displayUUID) {
                    activeDisplayIdentifier = CFUUIDCreateString(NULL, displayUUID);
                    CFRelease(displayUUID);
                }
            }
        }
    } else {
        // Get menubar display
        if (&CGSCopyActiveMenuBarDisplayIdentifier != NULL) {
            activeDisplayIdentifier = CGSCopyActiveMenuBarDisplayIdentifier(connection);
        }
    }

    CFArrayRef displays = CGSCopyManagedDisplaySpaces(connection, activeDisplayIdentifier);
    if (!displays && activeDisplayIdentifier) {
        displays = CGSCopyManagedDisplaySpaces(connection, NULL);
    }
    if (!displays) {
        if (activeDisplayIdentifier) {
            CFRelease(activeDisplayIdentifier);
        }
        return false;
    }

    const CFIndex displayCount = CFArrayGetCount(displays);
    CFDictionaryRef targetDisplay = NULL;
    CFDictionaryRef fallbackDisplay = NULL;

    for (CFIndex i = 0; i < displayCount; i++) {
        const void *displayValue = CFArrayGetValueAtIndex(displays, i);
        if (!displayValue || CFGetTypeID(displayValue) != CFDictionaryGetTypeID()) {
            continue;
        }

        CFDictionaryRef displayDict = (CFDictionaryRef)displayValue;

        if (!fallbackDisplay) {
            fallbackDisplay = displayDict;
        }

        if (!activeDisplayIdentifier || targetDisplay) {
            continue;
        }

        CFStringRef identifier = (CFStringRef)CFDictionaryGetValue(displayDict, CFSTR("Display Identifier"));
        if (identifier && CFGetTypeID(identifier) == CFStringGetTypeID() && CFEqual(identifier, activeDisplayIdentifier)) {
            targetDisplay = displayDict;
        }
    }

    if (!targetDisplay) {
        targetDisplay = fallbackDisplay;
    }

    bool success = false;
    if (targetDisplay) {
        success = extract_space_info_from_display(targetDisplay, activeSpace, hasActiveSpace, info);
    }

    if (activeDisplayIdentifier) {
        CFRelease(activeDisplayIdentifier);
    }
    CFRelease(displays);

    return success;
}

static bool iss_should_block_switch(const ISSSpaceInfo *info, ISSDirection direction) {
    if (!info) {
        return false;
    }
    if (info->spaceCount == 0) {
        return true;
    }

    unsigned int predicted;
    unsigned int current = get_prediction(info->displayID, &predicted) ? predicted : info->currentIndex;

    if (direction == ISSDirectionLeft) {
        return current == 0;
    }

    return current + 1 >= info->spaceCount;
}

bool iss_can_move(ISSSpaceInfo info, ISSDirection direction) {
    return !iss_should_block_switch(&info, direction);
}

// One gesture at a time, on the main run loop. New requests finish the current
// slide first, so repeated shortcuts cannot build up a queue of animations.
// Dock progress is gesture travel, not a normalized desktop position. In the
// macOS 26.6.2 trial, travel 1 reached roughly halfway before release. Keep this
// calibration separate from the timing curve; verify it on other macOS builds.
static const double swipeTravel = 2.0;
static struct {
    CGEventRef event;
    CFRunLoopTimerRef timer;
    uint64_t start;
    double duration;
    double easeIn;
    double easeOut;
    double sign;
    bool controlled;
    bool destinationPosted;
    void (*post)(CGEventRef);
} animation;

static CGEventRef iss_create_dock_swipe(ISSDirection direction) {
    const bool isRight = (direction == ISSDirectionRight);
    CGEventRef ev = CGEventCreate(NULL);
    if (!ev) return NULL;
    if (hasGestureLocation) CGEventSetLocation(ev, gestureLocation);
    CGEventSetIntegerValueField(ev, kCGSEventTypeField, kCGSEventDockControl);
    CGEventSetIntegerValueField(ev, kCGEventGestureHIDType, kIOHIDEventTypeDockSwipe);
    CGEventSetIntegerValueField(ev, kCGEventGestureSwipeMotion, kCGGestureMotionHorizontal);
    CGEventSetDoubleValueField(ev, kCGEventGestureSwipeProgress,
                              isRight ? FLT_TRUE_MIN : -FLT_TRUE_MIN);
    return ev;
}

static void iss_emit_swipe(CGSGesturePhase phase, double progress, double velocity) {
    CGEventSetTimestamp(animation.event, clock_gettime_nsec_np(CLOCK_UPTIME_RAW));
    CGEventSetIntegerValueField(animation.event, kCGEventGesturePhase, phase);
    CGEventSetDoubleValueField(animation.event, kCGEventGestureSwipeProgress, animation.sign * progress);
    CGEventSetDoubleValueField(animation.event, kCGEventGestureSwipeVelocityX, animation.sign * velocity);
    CGEventSetDoubleValueField(animation.event, kCGEventGestureSwipeVelocityY, animation.sign * velocity);
    if (animation.controlled) {
        // The native gesture also carries phase/progress in companion fields.
        // Field 135 stores the raw bits of a float, widened as an unsigned int.
        float offset = (float)(animation.sign * progress);
        uint32_t offsetBits;
        memcpy(&offsetBits, &offset, sizeof(offsetBits));
        CGEventSetIntegerValueField(animation.event, (CGEventField)134, phase);
        CGEventSetIntegerValueField(animation.event, (CGEventField)135, offsetBits);
    }
    animation.post(animation.event);
}

static void iss_finish_animation(bool interrupted) {
    if (!animation.event) return;
    CFRunLoopTimerInvalidate(animation.timer);
    CFRelease(animation.timer);
    animation.timer = NULL;
    // A normal slide has already reached its final travel on the previous
    // tick. Release at rest: a huge exit velocity causes a visible acceleration
    // if the Dock has not rendered all the preceding progress yet.
    // Only interruption/shutdown should force an immediate finish.
    if (interrupted) iss_emit_swipe(kCGSGesturePhaseChanged, swipeTravel, 0.0);
    iss_emit_swipe(kCGSGesturePhaseEnded, swipeTravel, interrupted ? 2000.0 : 0.0);
    CFRelease(animation.event);
    animation.event = NULL;
}

double iss_animation_progress(double time, double easeIn, double easeOut) {
    double t = isfinite(time) ? fmax(0.0, fmin(1.0, time)) : 0.0;
    double start = isfinite(easeIn) ? fmax(0.0, fmin(0.5, easeIn)) : 0.1;
    double end = isfinite(easeOut) ? fmax(0.0, fmin(0.5, easeOut)) : 0.1;
    // Integrate a trapezoidal velocity profile. Normalizing by its area
    // guarantees a full slide at t=1 for asymmetric ramps and linear motion.
    double area = 1.0 - (start + end) / 2.0;
    if (start > 0.0 && t < start) return t * t / (2.0 * start * area);
    if (end > 0.0 && t > 1.0 - end) {
        double remaining = 1.0 - t;
        return 1.0 - remaining * remaining / (2.0 * end * area);
    }
    return (t - start / 2.0) / area;
}

void iss_set_animation_duration(double seconds) {
    if (!isfinite(seconds) || seconds < 0.0) return;
    animationDuration = seconds == 0.0 ? 0.0 : fmax(0.08, fmin(1.0, seconds));
}

void iss_set_animation_curve(double easeIn, double easeOut) {
    if (!isfinite(easeIn) || !isfinite(easeOut)) return;
    animationEaseIn = fmax(0.0, fmin(0.5, easeIn));
    animationEaseOut = fmax(0.0, fmin(0.5, easeOut));
}

static void iss_animation_tick(CFRunLoopTimerRef timer, void *context) {
    (void)timer;
    (void)context;
    if (animation.destinationPosted) {
        iss_finish_animation(false);
        return;
    }
    double elapsed = (clock_gettime_nsec_np(CLOCK_UPTIME_RAW) - animation.start) / 1e9;
    double t = elapsed / animation.duration;
    if (t >= 1.0) {
        // Dock forwards progress through an asynchronous dispatch source.
        // Leave one update interval between final progress and release so the
        // final changed event can be consumed before the ended event.
        iss_emit_swipe(kCGSGesturePhaseChanged, swipeTravel, 0.0);
        animation.destinationPosted = true;
        return;
    }
    double progress = iss_animation_progress(t, animation.easeIn, animation.easeOut);
    iss_emit_swipe(kCGSGesturePhaseChanged, swipeTravel * progress, 0.0);
}

// Internal entry point accepts an event sink so tests can exercise the real
// scheduling and interruption behavior without switching the user's desktop.
bool iss_start_switch_animation(ISSDirection direction, double speed, void (*post)(CGEventRef)) {
    if (!post || !isfinite(speed) || speed <= 0.0) return false;
    CGEventRef event = iss_create_dock_swipe(direction);
    if (!event) return false;

    iss_finish_animation(true);
    animation.event = event;
    animation.sign = direction == ISSDirectionRight ? 1.0 : -1.0;
    animation.post = post;
    animation.controlled = speed < 2000.0;
    animation.destinationPosted = false;

    if (speed >= 2000.0) {
        // Preserve the original three-event instant gesture, including its
        // tiny signed progress. Mission Control needs the changed phase.
        iss_emit_swipe(kCGSGesturePhaseBegan, FLT_TRUE_MIN, speed);
        iss_emit_swipe(kCGSGesturePhaseChanged, FLT_TRUE_MIN, speed);
        iss_emit_swipe(kCGSGesturePhaseEnded, FLT_TRUE_MIN, speed);
        CFRelease(animation.event);
        animation.event = NULL;
        return true;
    }

    animation.duration = animationDuration > 0.0 ? animationDuration : fmax(0.08, fmin(0.35, 11.0 / speed));
    animation.easeIn = animationEaseIn;
    animation.easeOut = animationEaseOut;
    animation.start = clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
    animation.timer = CFRunLoopTimerCreate(NULL, CFAbsoluteTimeGetCurrent() + 1.0 / 120.0,
                                         1.0 / 120.0, 0, 0, iss_animation_tick, NULL);
    if (!animation.timer) {
        CFRelease(animation.event);
        animation.event = NULL;
        return false;
    }
    iss_emit_swipe(kCGSGesturePhaseBegan, FLT_TRUE_MIN, 0.0);
    CFRunLoopAddTimer(CFRunLoopGetMain(), animation.timer, kCFRunLoopCommonModes);
    return true;
}

void iss_wait_for_pending_switch(void) {
    while (animation.event) {
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.01, false);
    }
}

static void iss_post_gesture_event(CGEventRef event) {
    CGEventPost(kCGSessionEventTap, event);
}

static bool iss_perform_switch_gesture(ISSDirection direction, double velocity) {
    return iss_start_switch_animation(direction, velocity, iss_post_gesture_event);
}

/** @brief Walks a CGWindowListCopyWindowInfo result
 *
 * Used for trying to determine if Exposé or Mission Control is active.
 *
 * @param windowList The window list to scan
 * @param outLayer18Count The count of layer-18 windows
 * @param outLayer20Count The count of layer-20 windows
 */
static void scan_dock_window_list(CFArrayRef windowList,
                                  int *outLayer18Count,
                                  int *outLayer20Count) {
    *outLayer18Count = 0;
    *outLayer20Count = 0;
    CFIndex count = CFArrayGetCount(windowList);
    for (CFIndex i = 0; i < count; i++) {
        CFDictionaryRef info = (CFDictionaryRef)CFArrayGetValueAtIndex(windowList, i);
        CFStringRef owner = (CFStringRef)CFDictionaryGetValue(info, CFSTR("kCGWindowOwnerName"));
        if (!owner || !CFEqual(owner, CFSTR("Dock"))) continue;
        int layer = 0;
        CFNumberRef layerNum = (CFNumberRef)CFDictionaryGetValue(info, CFSTR("kCGWindowLayer"));
        if (layerNum) {
            CFNumberGetValue(layerNum, kCFNumberIntType, &layer);
        }
        if (layer == 18) {
            (*outLayer18Count)++;
            continue;
        }
        if (layer == 20) {
            (*outLayer20Count)++;
        }
    }
}

// Testable helpers
bool iss_is_expose_detected_in_window_list(CFArrayRef windowList) {
    int layer18Count = 0;
    int layer20Count = 0;
    scan_dock_window_list(windowList, &layer18Count, &layer20Count);
    // App Exposé: layer-18 present, at least one layer-20, AND count(layer=20) <= count(layer=18)
    return layer18Count > 0 && layer20Count > 0 && layer20Count <= layer18Count;
}

bool iss_is_mission_control_detected_in_window_list(CFArrayRef windowList) {
    int layer18Count = 0;
    int layer20Count = 0;
    scan_dock_window_list(windowList, &layer18Count, &layer20Count);
    // Mission Control: layer-18 present AND count(layer=20) > count(layer=18)
    return layer18Count > 0 && layer20Count > layer18Count;
}

/// Returns true when App Exposé is active (1-2 layer-20 windows)
/// This heuristic is empirical and may not work in all cases.
bool iss_is_expose_active(void) {
    if (!overlayDetectionEnabled) return false;
    CFArrayRef windowList = CGWindowListCopyWindowInfo(
        kCGWindowListOptionOnScreenOnly, kCGNullWindowID);
    if (!windowList) return false;
    bool result = iss_is_expose_detected_in_window_list(windowList);
    CFRelease(windowList);
    return result;
}

/// Returns true when Mission Control is active (3+ layer-20 windows)
/// This heuristic is empirical and may not work in all cases.
bool iss_is_mission_control_active(void) {
    if (!overlayDetectionEnabled) return false;
    CFArrayRef windowList = CGWindowListCopyWindowInfo(
        kCGWindowListOptionOnScreenOnly, kCGNullWindowID);
    if (!windowList) return false;
    bool result = iss_is_mission_control_detected_in_window_list(windowList);
    CFRelease(windowList);
    return result;
}

void iss_set_overlay_detection_enabled(bool enabled) {
    overlayDetectionEnabled = enabled;
}

bool iss_init(void) {
    if (globalTap) {
        return true;
    }

    if (!predictionsDict) {
        predictionsDict = CFDictionaryCreateMutable(NULL, 0, &kCFCopyStringDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    }

    CGEventMask mask = CGEventMaskBit(kCGEventKeyDown) | CGEventMaskBit(kCGEventKeyUp)
        | CGEventMaskBit(kCGEventLeftMouseDown)
        | (1ULL << kCGSEventGesture) | (1ULL << kCGSEventDockControl);
    globalTap = CGEventTapCreate(
        kCGSessionEventTap,
        kCGHeadInsertEventTap,
        kCGEventTapOptionDefault,
        mask,
        eventTapCallback,
        NULL
    );

    if (!globalTap) {
        return false;
    }

    globalSource = CFMachPortCreateRunLoopSource(NULL, globalTap, 0);
    if (!globalSource) {
        CFRelease(globalTap);
        globalTap = NULL;
        return false;
    }
    CFRunLoopAddSource(CFRunLoopGetMain(), globalSource, kCFRunLoopCommonModes);
    CGEventTapEnable(globalTap, true);

    return true;
}

void iss_destroy(void) {
    iss_finish_animation(true);
    if (predictionsDict) {
        CFRelease(predictionsDict);
        predictionsDict = NULL;
    }
    if (globalTap) {
        CGEventTapEnable(globalTap, false);
        if (globalSource) {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), globalSource, kCFRunLoopCommonModes);
            CFRelease(globalSource);
            globalSource = NULL;
        }
        CFRelease(globalTap);
        globalTap = NULL;
    }
}

bool iss_get_space_info(ISSSpaceInfo *info) {
    if (!info) {
        return false;
    }

    memset(info, 0, sizeof(*info));
    return load_space_info_for_display(info, true);
}

bool iss_get_menubar_space_info(ISSSpaceInfo *info) {
    if (!info) {
        return false;
    }

    memset(info, 0, sizeof(*info));
    return load_space_info_for_display(info, false);
}

static bool iss_switch_with_info(const ISSSpaceInfo *info, ISSDirection direction) {
    if (iss_should_block_switch(info, direction)) {
        return false;
    }
    if (!iss_perform_switch_gesture(direction, gestureSpeed)) {
        return false;
    }

    return true;
}

bool iss_switch(ISSDirection direction) {
    ISSSpaceInfo info;
    if (iss_get_space_info(&info)) {
        unsigned int predicted;
        unsigned int current = get_prediction(info.displayID, &predicted) ? predicted : info.currentIndex;
        unsigned int target = direction == ISSDirectionLeft ? current - 1 : current + 1;

        if (!iss_switch_with_info(&info, direction)) {
            return false;
        }
        set_prediction(info.displayID, target);
        if (switchCallback) { switchCallback(target); }
        return true;
    }

    return iss_perform_switch_gesture(direction, gestureSpeed);
}

bool iss_switch_to_index(unsigned int targetIndex) {
    ISSSpaceInfo info;
    if (!iss_get_space_info(&info)) {
        return false;
    }

    assert(info.spaceCount > 0);

    bool outOfBounds = targetIndex >= info.spaceCount;
    if (outOfBounds) {
        targetIndex = info.spaceCount - 1;
    }

    unsigned int predicted;
    unsigned int currentIndex = get_prediction(info.displayID, &predicted) ? predicted : info.currentIndex;

    if (currentIndex == targetIndex) {
        return !outOfBounds;
    }

    ISSDirection direction = currentIndex < targetIndex ? ISSDirectionRight : ISSDirectionLeft;
    unsigned int steps = direction == ISSDirectionRight ? (targetIndex - currentIndex) : (currentIndex - targetIndex);

    // Multiply velocity by number of steps for faster multi-space switching
    double velocity = gestureSpeed * steps;

    for (unsigned int i = 0; i < steps; i++) {
        if (!iss_perform_switch_gesture(direction, velocity)) {
            return false;
        }
    }

    set_prediction(info.displayID, targetIndex);
    if (switchCallback) { switchCallback(targetIndex); }
    return !outOfBounds;
}

bool iss_has_pending_switch(void) {
    return animation.event != NULL;
}

// Internal entry point shared with fixture tests; no live WindowServer calls.
bool iss_resolve_window_space(CFArrayRef displays, CFArrayRef memberships,
                              ISSSpaceInfo *info, unsigned int *targetIndex) {
    if (!displays || !memberships || !info || !targetIndex) return false;
    bool found = false;
    for (CFIndex d = 0; d < CFArrayGetCount(displays); d++) {
        CFDictionaryRef display = CFArrayGetValueAtIndex(displays, d);
        if (CFGetTypeID(display) != CFDictionaryGetTypeID()) continue;
        CFDictionaryRef current = CFDictionaryGetValue(display, CFSTR("Current Space"));
        if (!current || CFGetTypeID(current) != CFDictionaryGetTypeID()) continue;
        CFNumberRef activeID = CFDictionaryGetValue(current, CFSTR("id64"));
        CGSSpaceID active = 0;
        if (!activeID || CFGetTypeID(activeID) != CFNumberGetTypeID() ||
            !CFNumberGetValue(activeID, kCFNumberSInt64Type, &active) || !active) continue;
        ISSSpaceInfo candidate;
        if (!extract_space_info_from_display(display, active, true, &candidate)) continue;
        CFArrayRef spaces = CFDictionaryGetValue(display, CFSTR("Spaces"));
        unsigned int index = 0;
        for (CFIndex s = 0; s < CFArrayGetCount(spaces); s++) {
            CFDictionaryRef space = CFArrayGetValueAtIndex(spaces, s);
            if (CFGetTypeID(space) != CFDictionaryGetTypeID()) continue;
            CFNumberRef sid = CFDictionaryGetValue(space, CFSTR("id64"));
            if (!sid || CFGetTypeID(sid) != CFNumberGetTypeID()) continue;
            if (CFArrayContainsValue(memberships, CFRangeMake(0, CFArrayGetCount(memberships)), sid)) {
                if (!found || index == candidate.currentIndex) {
                    *info = candidate;
                    *targetIndex = index;
                    found = true;
                }
                if (index == candidate.currentIndex) goto done;
            }
            index++;
        }
    }
done:
    return found;
}

// Prefer an already visible membership (including windows on all desktops).
// Otherwise find the window's display and zero-based destination index.
static bool window_space_info(unsigned int windowID, ISSSpaceInfo *info,
                              unsigned int *targetIndex) {
    if (!windowID || !cgs_symbols_available() || !CGSCopySpacesForWindows) return false;
    CGSConnectionID connection = CGSMainConnectionID();
    if (!connection) return false;
    CFNumberRef number = CFNumberCreate(NULL, kCFNumberIntType, &windowID);
    CFArrayRef windows = CFArrayCreate(NULL, (const void **)&number, 1, &kCFTypeArrayCallBacks);
    CFArrayRef memberships = CGSCopySpacesForWindows(connection, 7, windows);
    CFRelease(windows);
    CFRelease(number);
    if (!memberships) return false;
    CFArrayRef displays = CGSCopyManagedDisplaySpaces(connection, NULL);
    if (!displays) { CFRelease(memberships); return false; }
    bool found = iss_resolve_window_space(displays, memberships, info, targetIndex);
    CFRelease(displays);
    CFRelease(memberships);
    return found;
}

bool iss_window_is_on_active_space(unsigned int windowID) {
    ISSSpaceInfo info;
    unsigned int target;
    return window_space_info(windowID, &info, &target) && info.currentIndex == target;
}

bool iss_switch_to_window(unsigned int windowID) {
    ISSSpaceInfo info;
    unsigned int target;
    if (!window_space_info(windowID, &info, &target)) return false;
    unsigned int predicted;
    unsigned int current = get_prediction(info.displayID, &predicted) ? predicted : info.currentIndex;
    if (target == current) return true;
    iss_finish_animation(true);

    CFStringRef identifier = CFStringCreateWithCString(NULL, info.displayID, kCFStringEncodingUTF8);
    CGDirectDisplayID display = CGMainDisplayID();
    if (!CFEqual(identifier, CFSTR("Main"))) {
        CFUUIDRef uuid = CFUUIDCreateFromString(NULL, identifier);
        CFRelease(identifier);
        if (!uuid) return false;
        display = CGDisplayGetDisplayIDFromUUID(uuid);
        CFRelease(uuid);
    } else {
        CFRelease(identifier);
    }
    if (!display || !CGDisplayIsActive(display)) return false;
    CGRect bounds = CGDisplayBounds(display);
    gestureLocation = CGPointMake(CGRectGetMidX(bounds), CGRectGetMidY(bounds));
    hasGestureLocation = true;
    ISSDirection direction = target > current ? ISSDirectionRight : ISSDirectionLeft;
    unsigned int steps = target > current ? target - current : current - target;
    bool success = true;
    for (unsigned int step = 0; step < steps; step++) {
        if (!iss_perform_switch_gesture(direction, gestureSpeed * steps)) {
            success = false;
            break;
        }
    }
    hasGestureLocation = false;
    if (success) {
        set_prediction(info.displayID, target);
        if (switchCallback) switchCallback(target);
    }
    return success;
}

void iss_set_swipe_override(bool enabled) {
    swipeOverrideEnabled = enabled;
    if (!enabled) {
        swipeTracking = false;
        swipeFired = false;
    }
}

void iss_set_gesture_speed(double speed) {
    if (isfinite(speed) && speed > 0.0) gestureSpeed = speed;
}

void iss_reset_predictions(void) {
    if (predictionsDict) {
        CFDictionaryRemoveAllValues(predictionsDict);
    }
}

void iss_set_switch_callback(ISSSwitchCallback callback) {
    switchCallback = callback;
}
