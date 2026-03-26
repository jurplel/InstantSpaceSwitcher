#include "include/ISS.h"

#include <ApplicationServices/ApplicationServices.h>
#include <CoreFoundation/CoreFoundation.h>
#include <CoreGraphics/CGEventTypes.h>
#include <float.h>
#include <stdbool.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

static const CGEventField kCGSEventTypeField = (CGEventField)55;
static const CGEventField kCGEventGestureHIDType = (CGEventField)110;
static const CGEventField kCGEventGestureScrollY = (CGEventField)119;
static const CGEventField kCGEventGestureSwipeMotion = (CGEventField)123;
static const CGEventField kCGEventGestureSwipeProgress = (CGEventField)124;
static const CGEventField kCGEventGestureSwipeVelocityX = (CGEventField)129;
static const CGEventField kCGEventGestureSwipeVelocityY = (CGEventField)130;
static const CGEventField kCGEventGesturePhase = (CGEventField)132;
static const CGEventField kCGEventScrollGestureFlagBits = (CGEventField)135;
static const CGEventField kCGEventGestureZoomDeltaX = (CGEventField)139;

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

static bool extract_space_info_from_display(CFDictionaryRef displayDict,
                                            CGSSpaceID activeSpace,
                                            bool hasActiveSpace,
                                            ISSSpaceInfo *outInfo);
static bool load_space_info_for_display(ISSSpaceInfo *info, bool useCursorDisplay);
static bool iss_post_switch_gesture(ISSDirection direction);
static bool iss_switch_with_info(const ISSSpaceInfo *info, ISSDirection direction);
static bool iss_should_block_switch(const ISSSpaceInfo *info, ISSDirection direction);

// Event tap callback (required but can be empty)
static CGEventRef eventTapCallback(CGEventTapProxy proxy, CGEventType type, 
                                   CGEventRef event, void *refcon) {
    (void)proxy;
    (void)type;
    (void)refcon;
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

    if (direction == ISSDirectionLeft) {
        return info->currentIndex == 0;
    }

    return info->currentIndex + 1 >= info->spaceCount;
}

bool iss_can_move(ISSSpaceInfo info, ISSDirection direction) {
    return !iss_should_block_switch(&info, direction);
}

static bool iss_post_switch_gesture(ISSDirection direction) {
    const bool isRight = (direction == ISSDirectionRight);

    // ScrollGestureFlagBits seem to mark direction (anything non-zero)
    int32_t scrollGestureFlagDirection = isRight ? 1 : 0;

    // Corresponds to distance, or something along those lines
    const double swipeProgress = isRight ? 2.0 : -2.0;

    // self-explanatory
    const double swipeVelocity = isRight ? 400.0 : -400.0;

    //
    // -- Begin gesture --
    //
    CGEventRef evA = CGEventCreate(NULL);
    if (!evA) {
        return false;
    }
    CGEventSetIntegerValueField(evA, kCGSEventTypeField, kCGSEventGesture);

    CGEventRef evB = CGEventCreate(NULL);
    if (!evB) {
        CFRelease(evA);
        return false;
    }
    CGEventSetIntegerValueField(evB, kCGSEventTypeField, kCGSEventDockControl);
    CGEventSetIntegerValueField(evB, kCGEventGestureHIDType, kIOHIDEventTypeDockSwipe);
    CGEventSetIntegerValueField(evB, kCGEventGesturePhase, kCGSGesturePhaseBegan);
    CGEventSetIntegerValueField(evB, kCGEventScrollGestureFlagBits, scrollGestureFlagDirection);
    CGEventSetIntegerValueField(evB, kCGEventGestureSwipeMotion, kCGGestureMotionHorizontal);
    CGEventSetDoubleValueField(evB, kCGEventGestureScrollY, 0);
    // Cannot explain this
    CGEventSetDoubleValueField(evB, kCGEventGestureZoomDeltaX, FLT_TRUE_MIN);

    CGEventPost(kCGSessionEventTap, evB);
    CGEventPost(kCGSessionEventTap, evA);
    CFRelease(evA);
    CFRelease(evB);

    //
    // -- End gesture --
    //
    evA = CGEventCreate(NULL);
    if (!evA) {
        return false;
    }
    CGEventSetIntegerValueField(evA, kCGSEventTypeField, kCGSEventGesture);

    evB = CGEventCreate(NULL);
    if (!evB) {
        CFRelease(evA);
        return false;
    }
    CGEventSetIntegerValueField(evB, kCGSEventTypeField, kCGSEventDockControl);
    CGEventSetIntegerValueField(evB, kCGEventGestureHIDType, kIOHIDEventTypeDockSwipe);
    CGEventSetIntegerValueField(evB, kCGEventGesturePhase, kCGSGesturePhaseEnded);
    CGEventSetDoubleValueField(evB, kCGEventGestureSwipeProgress, swipeProgress);
    CGEventSetIntegerValueField(evB, kCGEventScrollGestureFlagBits, scrollGestureFlagDirection);
    CGEventSetIntegerValueField(evB, kCGEventGestureSwipeMotion, kCGGestureMotionHorizontal);
    CGEventSetDoubleValueField(evB, kCGEventGestureScrollY, 0);
    CGEventSetDoubleValueField(evB, kCGEventGestureSwipeVelocityX, swipeVelocity);
    CGEventSetDoubleValueField(evB, kCGEventGestureSwipeVelocityY, 0);
    // Cannot explain this
    CGEventSetDoubleValueField(evB, kCGEventGestureZoomDeltaX, FLT_TRUE_MIN);

    CGEventPost(kCGSessionEventTap, evB);
    CGEventPost(kCGSessionEventTap, evA);
    CFRelease(evA);
    CFRelease(evB);

    return true;
}

bool iss_init(void) {
    if (globalTap) {
        return true;
    }

    CGEventMask mask = CGEventMaskBit(kCGEventKeyDown) | CGEventMaskBit(kCGEventKeyUp);
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
    if (!iss_post_switch_gesture(direction)) {
        return false;
    }

    return true;
}

bool iss_switch(ISSDirection direction) {
    ISSSpaceInfo info;
    if (iss_get_space_info(&info)) {
        return iss_switch_with_info(&info, direction);
    }

    return iss_post_switch_gesture(direction);
}

bool iss_get_all_displays_info(ISSAllDisplaysInfo *info) {
    if (!info) {
        return false;
    }
    memset(info, 0, sizeof(*info));

    if (!cgs_symbols_available()) {
        return false;
    }

    CGSConnectionID connection = CGSMainConnectionID();
    if (connection == 0) {
        return false;
    }

    CGDirectDisplayID activeDisplays[ISS_MAX_DISPLAYS];
    uint32_t activeDisplayCount = 0;
    if (CGGetActiveDisplayList(ISS_MAX_DISPLAYS, activeDisplays, &activeDisplayCount) != kCGErrorSuccess
        || activeDisplayCount == 0) {
        return false;
    }

    // Get all display space data in one call
    CFArrayRef allDisplayData = CGSCopyManagedDisplaySpaces(connection, NULL);
    if (!allDisplayData) {
        return false;
    }

    info->displayCount = activeDisplayCount > ISS_MAX_DISPLAYS ? ISS_MAX_DISPLAYS : activeDisplayCount;

    for (uint32_t di = 0; di < info->displayCount; di++) {
        info->displayIDs[di] = activeDisplays[di];

        // Convert CGDirectDisplayID to UUID string to match against display data
        CFUUIDRef displayUUID = CGDisplayCreateUUIDFromDisplayID(activeDisplays[di]);
        if (!displayUUID) {
            continue;
        }
        CFStringRef displayIDStr = CFUUIDCreateString(NULL, displayUUID);
        CFRelease(displayUUID);
        if (!displayIDStr) {
            continue;
        }

        // Find matching display entry by "Display Identifier"
        const CFIndex entryCount = CFArrayGetCount(allDisplayData);
        for (CFIndex ei = 0; ei < entryCount; ei++) {
            const void *entryValue = CFArrayGetValueAtIndex(allDisplayData, ei);
            if (!entryValue || CFGetTypeID(entryValue) != CFDictionaryGetTypeID()) {
                continue;
            }

            CFDictionaryRef entryDict = (CFDictionaryRef)entryValue;
            CFStringRef identifier = (CFStringRef)CFDictionaryGetValue(entryDict, CFSTR("Display Identifier"));
            if (!identifier || CFGetTypeID(identifier) != CFStringGetTypeID()) {
                continue;
            }

            if (!CFEqual(identifier, displayIDStr)) {
                continue;
            }

            // Found matching display — count its spaces
            const void *spacesValue = CFDictionaryGetValue(entryDict, CFSTR("Spaces"));
            if (spacesValue && CFGetTypeID(spacesValue) == CFArrayGetTypeID()) {
                info->spaceCounts[di] = (unsigned int)CFArrayGetCount((CFArrayRef)spacesValue);
            }
            break;
        }

        CFRelease(displayIDStr);
    }

    CFRelease(allDisplayData);
    return true;
}

uint32_t iss_get_cursor_display_id(void) {
    CGEventRef tempEvent = CGEventCreate(NULL);
    if (!tempEvent) {
        return 0;
    }
    CGPoint cursorLocation = CGEventGetLocation(tempEvent);
    CFRelease(tempEvent);

    CGDirectDisplayID cursorDisplay = 0;
    uint32_t displayCount = 0;

    if (CGGetDisplaysWithPoint(cursorLocation, 1, &cursorDisplay, &displayCount) == kCGErrorSuccess
        && displayCount > 0) {
        return cursorDisplay;
    }

    return 0;
}

bool iss_switch_to_index(unsigned int targetIndex) {
    ISSSpaceInfo info;
    if (!iss_get_space_info(&info)) {
        return false;
    }

    if (info.spaceCount == 0) {
        return false;
    }

    bool outOfBounds = targetIndex >= info.spaceCount;
    if (outOfBounds) {
        targetIndex = info.spaceCount - 1;
    }

    if (info.currentIndex == targetIndex) {
        return !outOfBounds;
    }

    ISSDirection direction = info.currentIndex < targetIndex ? ISSDirectionRight : ISSDirectionLeft;
    unsigned int steps = direction == ISSDirectionRight ? (targetIndex - info.currentIndex) : (info.currentIndex - targetIndex);

    for (unsigned int i = 0; i < steps; i++) {
        if (!iss_post_switch_gesture(direction)) {
            return false;
        }
    }

    return !outOfBounds;
}
