#include "../ISS/include/ISS.h"
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <ApplicationServices/ApplicationServices.h>
#include <CoreFoundation/CoreFoundation.h>
#include <string.h>
#include <unistd.h>

static void print_usage(const char *progName) {
    fprintf(stderr, "Usage: %s [left|right|index <n>|focus <app name>]\n", progName);
}

/** @brief Finds the space index of the frontmost app window that lives on one space of this display. */
static bool find_app_space_index(const char *appName, unsigned int *outIndex) {
    CFArrayRef windows = CGWindowListCopyWindowInfo(
        kCGWindowListOptionAll | kCGWindowListExcludeDesktopElements, kCGNullWindowID);
    CFStringRef name = CFStringCreateWithCString(NULL, appName, kCFStringEncodingUTF8);
    bool found = false;

    for (CFIndex i = 0; windows && name && i < CFArrayGetCount(windows) && !found; i++) {
        CFDictionaryRef window = (CFDictionaryRef)CFArrayGetValueAtIndex(windows, i);
        CFStringRef owner = (CFStringRef)CFDictionaryGetValue(window, kCGWindowOwnerName);
        if (!owner || CFStringCompare(owner, name, kCFCompareCaseInsensitive) != kCFCompareEqualTo) {
            continue;
        }

        int layer = -1;
        CFNumberRef layerNumber = (CFNumberRef)CFDictionaryGetValue(window, kCGWindowLayer);
        if (!layerNumber || !CFNumberGetValue(layerNumber, kCFNumberIntType, &layer) || layer != 0) {
            continue;
        }

        // Apps keep tiny helper windows around; a real window is bigger than this
        CGRect bounds = CGRectZero;
        CFDictionaryRef boundsDict = (CFDictionaryRef)CFDictionaryGetValue(window, kCGWindowBounds);
        if (!boundsDict || !CGRectMakeWithDictionaryRepresentation(boundsDict, &bounds) ||
            bounds.size.width < 100 || bounds.size.height < 100) {
            continue;
        }

        // Hidden helper windows (e.g. Electron's) belong to no space, so they are skipped here
        uint32_t windowID = 0;
        CFNumberRef windowNumber = (CFNumberRef)CFDictionaryGetValue(window, kCGWindowNumber);
        found = windowNumber && CFNumberGetValue(windowNumber, kCFNumberSInt32Type, &windowID) &&
                iss_get_window_space_index(windowID, outIndex);
    }

    if (name) CFRelease(name);
    if (windows) CFRelease(windows);
    return found;
}

/** @brief Switches instantly to the space of the app's front window, then activates the app.
 * macOS has nothing left to animate because the window is already on screen.
 */
static int focus_app(const char *appName) {
    unsigned int index = 0;
    if (find_app_space_index(appName, &index)) {
        // On failure the app still activates, just with the normal animation
        iss_switch_to_index(index);
    }
    iss_destroy();

    execl("/usr/bin/open", "open", "-a", appName, (char *)NULL);
    perror("open");
    return 1;
}

int main(int argc, char **argv) {
    if (!iss_init()) {
        fprintf(stderr, "Failed to initialize ISS (event tap). Check accessibility and input monitoring permissions.\n");
        return 1;
    }

    ISSDirection direction = ISSDirectionLeft;
    bool useIndex = false;
    unsigned int targetIndex = 0;

    if (argc > 1) {
        if (!strcmp(argv[1], "right") || !strcmp(argv[1], "r") || !strcmp(argv[1], "1")) {
            direction = ISSDirectionRight;
        } else if (!strcmp(argv[1], "left") || !strcmp(argv[1], "l") || !strcmp(argv[1], "0")) {
            direction = ISSDirectionLeft;
        } else if (!strcmp(argv[1], "index") || !strcmp(argv[1], "i")) {
            if (argc < 3) {
                print_usage(argv[0]);
                iss_destroy();
                return 1;
            }
            char *endPtr = NULL;
            long parsed = strtol(argv[2], &endPtr, 10);
            if (endPtr == argv[2] || parsed < 1) {
                fprintf(stderr, "Index must be a positive integer.\n");
                iss_destroy();
                return 1;
            }
            useIndex = true;
            targetIndex = (unsigned int)(parsed - 1); // convert to zero-based
        } else if (!strcmp(argv[1], "focus") || !strcmp(argv[1], "f")) {
            if (argc < 3) {
                print_usage(argv[0]);
                iss_destroy();
                return 1;
            }
            return focus_app(argv[2]);
        } else {
            print_usage(argv[0]);
            iss_destroy();
            return 1;
        }
    }

    bool success = false;
    if (useIndex) {
        success = iss_switch_to_index(targetIndex);
    } else {
        success = iss_switch(direction);
    }

    if (!success) {
        fprintf(stderr, "Switch request failed. Check space bounds or permissions.\n");
        iss_destroy();
        return 1;
    }

    CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.3, false);
    iss_destroy();
    return 0;
}
