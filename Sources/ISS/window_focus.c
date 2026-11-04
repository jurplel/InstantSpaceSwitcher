#include "window_focus.h"

#include <ApplicationServices/ApplicationServices.h>
#include <dispatch/dispatch.h>
#include <dlfcn.h>
#include <string.h>

#include "include/ISSWindowCarry.h"
#include "window_drag.h"

// The bridged space operations apply asynchronously (measured: within ~16 ms); raising before
// the switch lands would reorder the window on the old space. Raise soon after, then once
// more as a safety net in case the switch landed late.
static const CFTimeInterval kFocusDelay = 0.02;
static const CFTimeInterval kFocusRetryDelay = 0.12;
static const float kMessagingTimeout = 0.25f;
// The hit test runs while the user waits for the switch, so keep it short
static const float kHitTestTimeout = 0.1f;
// Title bar plus tab strip in Chromium-based windows
static const double kTitleBandHeight = 52.0;

// Maps an Accessibility window to its window server ID. Private but long-standing
// (used by most window managers); resolved at runtime so a removal only disables focusing.
typedef AXError (*AXGetWindowFn)(AXUIElementRef element, uint32_t *outWindowID);

static AXGetWindowFn axGetWindow = NULL;

static void load_ax_get_window(void *context) {
    (void)context;
    axGetWindow = (AXGetWindowFn)dlsym(RTLD_DEFAULT, "_AXUIElementGetWindow");
}

// Also called from the background title-bar check, so resolve exactly once
static AXGetWindowFn resolve_ax_get_window(void) {
    static dispatch_once_t once;
    dispatch_once_f(&once, NULL, load_ax_get_window);
    return axGetWindow;
}

static pid_t window_owner_pid(uint32_t windowID) {
    pid_t pid = 0;
    CFArrayRef info = CGWindowListCopyWindowInfo(kCGWindowListOptionIncludingWindow, windowID);
    if (info && CFArrayGetCount(info) > 0) {
        CFDictionaryRef window = (CFDictionaryRef)CFArrayGetValueAtIndex(info, 0);
        CFNumberRef owner = (CFNumberRef)CFDictionaryGetValue(window, kCGWindowOwnerPID);
        if (owner) {
            CFNumberGetValue(owner, kCFNumberIntType, &pid);
        }
    }
    if (info) {
        CFRelease(info);
    }
    return pid;
}

static void focus_window(uint32_t windowID) {
    AXGetWindowFn getWindow = resolve_ax_get_window();
    pid_t pid = window_owner_pid(windowID);
    if (!getWindow || pid <= 0) {
        return;
    }
    const CFAbsoluteTime started = CFAbsoluteTimeGetCurrent();

    AXUIElementRef app = AXUIElementCreateApplication(pid);
    if (!app) {
        return;
    }
    AXUIElementSetMessagingTimeout(app, kMessagingTimeout);

    CFArrayRef windows = NULL;
    if (AXUIElementCopyAttributeValue(app, kAXWindowsAttribute, (CFTypeRef *)&windows) == kAXErrorSuccess &&
        windows && CFGetTypeID(windows) == CFArrayGetTypeID()) {
        for (CFIndex i = 0; i < CFArrayGetCount(windows); i++) {
            AXUIElementRef window = (AXUIElementRef)CFArrayGetValueAtIndex(windows, i);
            uint32_t candidate = 0;
            if (getWindow(window, &candidate) != kAXErrorSuccess || candidate != windowID) {
                continue;
            }
            AXUIElementPerformAction(window, kAXRaiseAction);
            AXUIElementSetAttributeValue(window, kAXMainAttribute, kCFBooleanTrue);
            AXUIElementSetAttributeValue(app, kAXFrontmostAttribute, kCFBooleanTrue);
            break;
        }
    }
    if (windows) {
        CFRelease(windows);
    }
    CFRelease(app);
    iss_carry_log("raised and focused window %u in %.1f ms", windowID, (CFAbsoluteTimeGetCurrent() - started) * 1000.0);
}

bool iss_ax_role_is_drag_area(const char *role, const char *parentRole, double offsetFromTop) {
    if (!role) {
        return false;
    }
    if (strcmp(role, "AXWindow") == 0 || strcmp(role, "AXToolbar") == 0) {
        return true;
    }
    // The title text in the title bar
    if (strcmp(role, "AXStaticText") == 0 && parentRole && strcmp(parentRole, "AXWindow") == 0) {
        return true;
    }
    // Chromium's self-drawn title bar and tab strip background
    bool inPageContent = parentRole && (strcmp(parentRole, "AXScrollArea") == 0 || strcmp(parentRole, "AXWebArea") == 0);
    return strcmp(role, "AXGroup") == 0 && !inPageContent && offsetFromTop >= 0.0 &&
           offsetFromTop <= kTitleBandHeight;
}

static bool copy_role(AXUIElementRef element, char *buffer, size_t size) {
    CFStringRef role = NULL;
    if (AXUIElementCopyAttributeValue(element, kAXRoleAttribute, (CFTypeRef *)&role) != kAXErrorSuccess || !role) {
        return false;
    }
    bool ok = CFGetTypeID(role) == CFStringGetTypeID() &&
              CFStringGetCString(role, buffer, (CFIndex)size, kCFStringEncodingUTF8);
    CFRelease(role);
    return ok;
}

bool iss_point_is_window_drag_area(CGPoint point, uint32_t windowID, double windowTop) {
    AXGetWindowFn getWindow = resolve_ax_get_window();
    if (!getWindow) {
        return false;
    }
    const CFAbsoluteTime started = CFAbsoluteTimeGetCurrent();
    AXUIElementRef systemWide = AXUIElementCreateSystemWide();
    if (!systemWide) {
        return false;
    }
    AXUIElementSetMessagingTimeout(systemWide, kHitTestTimeout);
    AXUIElementRef element = NULL;
    AXError error = AXUIElementCopyElementAtPosition(systemWide, (float)point.x, (float)point.y, &element);
    CFRelease(systemWide);
    if (error != kAXErrorSuccess || !element) {
        iss_carry_log("hit test at (%.0f, %.0f) failed (AXError %d)", point.x, point.y, (int)error);
        return false;
    }

    char role[64] = {0};
    char parentRole[64] = {0};
    copy_role(element, role, sizeof(role));
    AXUIElementRef parent = NULL;
    if (AXUIElementCopyAttributeValue(element, kAXParentAttribute, (CFTypeRef *)&parent) == kAXErrorSuccess && parent) {
        copy_role(parent, parentRole, sizeof(parentRole));
        CFRelease(parent);
    }

    // The element must belong to the window being held
    uint32_t elementWindow = 0;
    if (strcmp(role, "AXWindow") == 0) {
        getWindow(element, &elementWindow);
    } else {
        AXUIElementRef window = NULL;
        if (AXUIElementCopyAttributeValue(element, kAXWindowAttribute, (CFTypeRef *)&window) == kAXErrorSuccess &&
            window) {
            getWindow(window, &elementWindow);
            CFRelease(window);
        }
    }
    CFRelease(element);

    double offsetFromTop = point.y - windowTop;
    bool dragArea = elementWindow == windowID &&
                    iss_ax_role_is_drag_area(role, parentRole[0] ? parentRole : NULL, offsetFromTop);
    iss_carry_log("press on %s (parent %s) of window %u, %.0f pt below its top: %s (hit test %.1f ms)",
                  role[0] ? role : "?", parentRole[0] ? parentRole : "?", elementWindow, offsetFromTop,
                  dragArea ? "grabs the window" : "does not grab the window",
                  (CFAbsoluteTimeGetCurrent() - started) * 1000.0);
    return dragArea;
}

static void focus_timer_fired(CFRunLoopTimerRef timer, void *info) {
    focus_window((uint32_t)(uintptr_t)info);
    CFRunLoopTimerInvalidate(timer);
    CFRelease(timer);
}

static void schedule_focus(uint32_t windowID, CFTimeInterval delay) {
    CFRunLoopTimerContext context = {0, (void *)(uintptr_t)windowID, NULL, NULL, NULL};
    CFRunLoopTimerRef timer = CFRunLoopTimerCreate(NULL, CFAbsoluteTimeGetCurrent() + delay, 0, 0, 0,
                                                   focus_timer_fired, &context);
    if (timer) {
        CFRunLoopAddTimer(CFRunLoopGetMain(), timer, kCFRunLoopCommonModes);
    }
}

void iss_focus_window_soon(uint32_t windowID) {
    schedule_focus(windowID, kFocusDelay);
    schedule_focus(windowID, kFocusRetryDelay);
}
