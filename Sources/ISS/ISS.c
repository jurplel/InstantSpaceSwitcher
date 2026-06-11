#include "include/ISS.h"

#include <ApplicationServices/ApplicationServices.h>
#include <CoreFoundation/CoreFoundation.h>
#include <CoreGraphics/CGEventTypes.h>
#include <CoreVideo/CoreVideo.h>
#include <assert.h>
#include <dlfcn.h>
#include <float.h>
#include <stdbool.h>
#include <stdio.h>
#include <string.h>
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

static CFMachPortRef globalTap = NULL;
static CFRunLoopSourceRef globalSource = NULL;

// Overlay detection state
static bool overlayDetectionEnabled = false;

// Swipe override state
static bool swipeOverrideEnabled = false;
static bool swipeTracking = false;
static bool swipeFired = false;

// Gesture speed state
static double gestureSpeed = 2000.0;
static const double nonInstantGestureVelocityFloor = 40.0;
static const double nonInstantGestureVelocityLinearMultiplier = 0.45;
static const double nonInstantGestureVelocityQuadraticMultiplier = 0.0175;
static const double instantGestureVelocity = 2000.0;
static const double nonInstantGestureVelocityCeiling = 1999.0;
static const double nonInstantGestureProgress = 0.09;

static ISSSwitchCallback switchCallback = NULL;

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
static bool iss_perform_switch_gesture(ISSDirection direction, double velocity, const char *displayID);
static bool iss_switch_with_info(const ISSSpaceInfo *info, ISSDirection direction);
static bool iss_should_block_switch(const ISSSpaceInfo *info, ISSDirection direction);

static double iss_base_gesture_velocity(double velocity) {
    if (velocity <= 0.0 || velocity >= instantGestureVelocity) {
        return velocity;
    }

    // Keep Normal at the original raw gesture velocity, then use a shallow
    // curved spacing so faster presets stay distinct without entering Dock's
    // overly aggressive completion band.
    double presetOffset = velocity - nonInstantGestureVelocityFloor;
    if (presetOffset < 0.0) {
        presetOffset = 0.0;
    }

    double normalizedVelocity =
        nonInstantGestureVelocityFloor +
        presetOffset * nonInstantGestureVelocityLinearMultiplier +
        presetOffset * presetOffset * nonInstantGestureVelocityQuadraticMultiplier;
    return normalizedVelocity < instantGestureVelocity
        ? normalizedVelocity
        : nonInstantGestureVelocityCeiling;
}

double iss_refresh_rate_normalization_scale(double displayRefreshRate, double baselineRefreshRate) {
    if (displayRefreshRate <= 0.0 || baselineRefreshRate <= 0.0) {
        return 1.0;
    }

    return displayRefreshRate / baselineRefreshRate;
}

double iss_normalize_gesture_velocity_for_refresh_rate(double velocity,
                                                       double displayRefreshRate,
                                                       double baselineRefreshRate) {
    double normalizedVelocity = iss_base_gesture_velocity(velocity);
    if (velocity <= 0.0 || velocity >= instantGestureVelocity) {
        return normalizedVelocity;
    }

    if (normalizedVelocity <= nonInstantGestureVelocityFloor) {
        return normalizedVelocity;
    }

    double scaledOffset =
        (normalizedVelocity - nonInstantGestureVelocityFloor)
        * iss_refresh_rate_normalization_scale(displayRefreshRate, baselineRefreshRate);
    normalizedVelocity = nonInstantGestureVelocityFloor + scaledOffset;
    return normalizedVelocity < instantGestureVelocity
        ? normalizedVelocity
        : nonInstantGestureVelocityCeiling;
}

double iss_normalize_gesture_velocity(double velocity) {
    return iss_normalize_gesture_velocity_for_refresh_rate(velocity, 0.0, 0.0);
}

double iss_dock_swipe_velocity_for_phase(double velocity, int phase) {
    (void)phase;
    return iss_normalize_gesture_velocity(velocity);
}

double iss_dock_swipe_velocity_for_phase_and_refresh_rate(double velocity,
                                                          int phase,
                                                          double displayRefreshRate,
                                                          double baselineRefreshRate) {
    (void)phase;
    return iss_normalize_gesture_velocity_for_refresh_rate(
        velocity,
        displayRefreshRate,
        baselineRefreshRate
    );
}

double iss_dock_swipe_progress_for_phase_and_refresh_rate(double velocity,
                                                          int phase,
                                                          double displayRefreshRate,
                                                          double baselineRefreshRate) {
    if (phase == kCGSGesturePhaseBegan
        || velocity <= nonInstantGestureVelocityFloor
        || velocity >= instantGestureVelocity) {
        return (double)FLT_TRUE_MIN;
    }

    return nonInstantGestureProgress;
}

double iss_dock_swipe_progress_for_phase(double velocity, int phase) {
    return iss_dock_swipe_progress_for_phase_and_refresh_rate(velocity, phase, 0.0, 0.0);
}

// Perform a swipe-override switch: get space info, compute target, switch,
// and notify the handler with the target index.
static void swipe_override_switch(ISSDirection dir) {
    ISSSpaceInfo info;
    if (!iss_get_space_info(&info)) {
        iss_perform_switch_gesture(dir, gestureSpeed, NULL);
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

static bool iss_copy_display_uuid_string(CGDirectDisplayID displayID, char *buffer, size_t bufferSize) {
    if (!buffer || bufferSize == 0) {
        return false;
    }

    buffer[0] = '\0';
    CFUUIDRef uuid = CGDisplayCreateUUIDFromDisplayID(displayID);
    if (!uuid) {
        return false;
    }

    CFStringRef uuidString = CFUUIDCreateString(NULL, uuid);
    CFRelease(uuid);
    if (!uuidString) {
        return false;
    }

    bool success = CFStringGetCString(uuidString, buffer, bufferSize, kCFStringEncodingUTF8);
    CFRelease(uuidString);
    return success;
}

static double iss_refresh_rate_for_display(CGDirectDisplayID displayID) {
    double refreshRate = 0.0;

    CGDisplayModeRef mode = CGDisplayCopyDisplayMode(displayID);
    if (mode) {
        refreshRate = CGDisplayModeGetRefreshRate(mode);
        CGDisplayModeRelease(mode);
    }
    if (refreshRate > 0.0) {
        return refreshRate;
    }

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    CVDisplayLinkRef displayLink = NULL;
    if (CVDisplayLinkCreateWithCGDisplay(displayID, &displayLink) == kCVReturnSuccess && displayLink) {
        CVTime nominalPeriod = CVDisplayLinkGetNominalOutputVideoRefreshPeriod(displayLink);
        if (nominalPeriod.timeValue > 0 && nominalPeriod.timeScale > 0) {
            refreshRate = (double)nominalPeriod.timeScale / (double)nominalPeriod.timeValue;
        }
        CVDisplayLinkRelease(displayLink);
    }
#pragma clang diagnostic pop

    return refreshRate;
}

static double iss_min_active_display_refresh_rate(void) {
    uint32_t displayCount = 0;
    if (CGGetActiveDisplayList(0, NULL, &displayCount) != kCGErrorSuccess || displayCount == 0) {
        return 0.0;
    }

    CGDirectDisplayID displays[32] = {0};
    if (displayCount > 32) {
        displayCount = 32;
    }
    if (CGGetActiveDisplayList(displayCount, displays, &displayCount) != kCGErrorSuccess) {
        return 0.0;
    }

    double minRefreshRate = 0.0;
    for (uint32_t i = 0; i < displayCount; i++) {
        double refreshRate = iss_refresh_rate_for_display(displays[i]);
        if (refreshRate <= 0.0) {
            continue;
        }
        if (minRefreshRate <= 0.0 || refreshRate < minRefreshRate) {
            minRefreshRate = refreshRate;
        }
    }

    return minRefreshRate;
}

static double iss_refresh_rate_for_display_identifier(const char *displayIdentifier) {
    if (!displayIdentifier || displayIdentifier[0] == '\0') {
        return 0.0;
    }

    uint32_t displayCount = 0;
    if (CGGetActiveDisplayList(0, NULL, &displayCount) != kCGErrorSuccess || displayCount == 0) {
        return 0.0;
    }

    CGDirectDisplayID displays[32] = {0};
    if (displayCount > 32) {
        displayCount = 32;
    }
    if (CGGetActiveDisplayList(displayCount, displays, &displayCount) != kCGErrorSuccess) {
        return 0.0;
    }

    for (uint32_t i = 0; i < displayCount; i++) {
        char uuidString[128] = {0};
        if (!iss_copy_display_uuid_string(displays[i], uuidString, sizeof(uuidString))) {
            continue;
        }
        if (strcmp(uuidString, displayIdentifier) == 0) {
            return iss_refresh_rate_for_display(displays[i]);
        }
    }

    return 0.0;
}

static bool iss_post_dock_swipe(CGSGesturePhase phase, ISSDirection direction,
                                double velocity, double progressMagnitude) {
    const bool isRight = (direction == ISSDirectionRight);
    // Velocity controls animation speed; progress gives Dock enough swipe distance
    // to commit non-instant gestures without upgrading them to Instant velocity.
    const double progress = isRight ? progressMagnitude : -progressMagnitude;

    // Velocity of gesture based on speed setting
    const double vel = isRight ? velocity : -velocity;

    CGEventRef ev = CGEventCreate(NULL);
    if (!ev) {
        return false;
    }
    CGEventSetIntegerValueField(ev, kCGSEventTypeField, kCGSEventDockControl);
    CGEventSetIntegerValueField(ev, kCGEventGestureHIDType, kIOHIDEventTypeDockSwipe);
    CGEventSetIntegerValueField(ev, kCGEventGesturePhase, phase);
    CGEventSetDoubleValueField(ev, kCGEventGestureSwipeProgress, progress);
    CGEventSetIntegerValueField(ev, kCGEventGestureSwipeMotion, kCGGestureMotionHorizontal);
    CGEventSetDoubleValueField(ev, kCGEventGestureSwipeVelocityX, vel);
    CGEventSetDoubleValueField(ev, kCGEventGestureSwipeVelocityY, vel);
    CGEventPost(kCGSessionEventTap, ev);
    CFRelease(ev);
    return true;
}

static bool iss_perform_switch_gesture(ISSDirection direction, double velocity, const char *displayID) {
    double displayRefreshRate = iss_refresh_rate_for_display_identifier(displayID);
    double baselineRefreshRate = iss_min_active_display_refresh_rate();

    double beganVelocity = iss_dock_swipe_velocity_for_phase_and_refresh_rate(
        velocity,
        kCGSGesturePhaseBegan,
        displayRefreshRate,
        baselineRefreshRate
    );
    double changedVelocity = iss_dock_swipe_velocity_for_phase_and_refresh_rate(
        velocity,
        kCGSGesturePhaseChanged,
        displayRefreshRate,
        baselineRefreshRate
    );
    double endedVelocity = iss_dock_swipe_velocity_for_phase_and_refresh_rate(
        velocity,
        kCGSGesturePhaseEnded,
        displayRefreshRate,
        baselineRefreshRate
    );
    double beganProgress = iss_dock_swipe_progress_for_phase_and_refresh_rate(
        velocity,
        kCGSGesturePhaseBegan,
        displayRefreshRate,
        baselineRefreshRate
    );
    double changedProgress = iss_dock_swipe_progress_for_phase_and_refresh_rate(
        velocity,
        kCGSGesturePhaseChanged,
        displayRefreshRate,
        baselineRefreshRate
    );
    double endedProgress = iss_dock_swipe_progress_for_phase_and_refresh_rate(
        velocity,
        kCGSGesturePhaseEnded,
        displayRefreshRate,
        baselineRefreshRate
    );

    // Send three gesture events--began, changed, and ended
    // If we only send two then mission control doesn't work.
    return iss_post_dock_swipe(kCGSGesturePhaseBegan,   direction, beganVelocity,   beganProgress)
        && iss_post_dock_swipe(kCGSGesturePhaseChanged, direction, changedVelocity, changedProgress)
        && iss_post_dock_swipe(kCGSGesturePhaseEnded,   direction, endedVelocity,   endedProgress);
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
    CFRunLoopAddSource(CFRunLoopGetMain(), globalSource, kCFRunLoopCommonModes);
    CGEventTapEnable(globalTap, true);

    return true;
}

void iss_destroy(void) {
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
    if (!iss_perform_switch_gesture(direction, gestureSpeed, info ? info->displayID : NULL)) {
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

    return iss_perform_switch_gesture(direction, gestureSpeed, NULL);
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
        if (!iss_perform_switch_gesture(direction, velocity, info.displayID)) {
            return false;
        }
    }

    set_prediction(info.displayID, targetIndex);
    if (switchCallback) { switchCallback(targetIndex); }
    return !outOfBounds;
}

void iss_set_swipe_override(bool enabled) {
    swipeOverrideEnabled = enabled;
    if (!enabled) {
        swipeTracking = false;
        swipeFired = false;
    }
}

void iss_set_gesture_speed(double speed) {
    gestureSpeed = speed;
}

void iss_reset_predictions(void) {
    if (predictionsDict) {
        CFDictionaryRemoveAllValues(predictionsDict);
    }
}

void iss_set_switch_callback(ISSSwitchCallback callback) {
    switchCallback = callback;
}
