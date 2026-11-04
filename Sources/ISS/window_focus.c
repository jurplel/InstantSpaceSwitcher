#include "window_focus.h"

#include <ApplicationServices/ApplicationServices.h>
#include <dlfcn.h>
#include <string.h>

#include "include/ISSWindowCarry.h"
#include "window_drag.h"

// The bridged space operations apply asynchronously; raising before the switch lands
// would reorder the window on the old space
static const CFTimeInterval kFocusDelay = 0.05;
static const float kMessagingTimeout = 0.25f;
// The hit test runs while the user waits for the switch, so keep it short
static const float kHitTestTimeout = 0.1f;

// Maps an Accessibility window to its window server ID. Private but long-standing
// (used by most window managers); resolved at runtime so a removal only disables focusing.
typedef AXError (*AXGetWindowFn)(AXUIElementRef element, uint32_t *outWindowID);

static AXGetWindowFn resolve_ax_get_window(void) {
    static bool resolved = false;
    static AXGetWindowFn fn = NULL;
    if (!resolved) {
        resolved = true;
        fn = (AXGetWindowFn)dlsym(RTLD_DEFAULT, "_AXUIElementGetWindow");
    }
    return fn;
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
}

bool iss_ax_role_is_drag_area(const char *role, const char *parentRole) {
    if (!role) {
        return false;
    }
    if (strcmp(role, "AXWindow") == 0 || strcmp(role, "AXToolbar") == 0) {
        return true;
    }
    // The title text in the title bar
    return strcmp(role, "AXStaticText") == 0 && parentRole && strcmp(parentRole, "AXWindow") == 0;
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

bool iss_point_is_window_drag_area(CGPoint point, uint32_t windowID) {
    AXGetWindowFn getWindow = resolve_ax_get_window();
    if (!getWindow) {
        return false;
    }
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

    bool dragArea = elementWindow == windowID && iss_ax_role_is_drag_area(role, parentRole[0] ? parentRole : NULL);
    iss_carry_log("press on %s (parent %s) of window %u: %s", role[0] ? role : "?", parentRole[0] ? parentRole : "?",
                  elementWindow, dragArea ? "grabs the window" : "does not grab the window");
    return dragArea;
}

static void focus_timer_fired(CFRunLoopTimerRef timer, void *info) {
    focus_window((uint32_t)(uintptr_t)info);
    CFRunLoopTimerInvalidate(timer);
    CFRelease(timer);
}

void iss_focus_window_soon(uint32_t windowID) {
    CFRunLoopTimerContext context = {0, (void *)(uintptr_t)windowID, NULL, NULL, NULL};
    CFRunLoopTimerRef timer = CFRunLoopTimerCreate(NULL, CFAbsoluteTimeGetCurrent() + kFocusDelay, 0, 0, 0,
                                                   focus_timer_fired, &context);
    if (timer) {
        CFRunLoopAddTimer(CFRunLoopGetMain(), timer, kCFRunLoopCommonModes);
    }
}
