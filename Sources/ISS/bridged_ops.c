#include "bridged_ops.h"

#include <objc/message.h>
#include <objc/runtime.h>
#include <stdlib.h>
#include <string.h>

// SkyLight exposes window-management operations as Objective-C classes that are
// initialized with plain values and dispatched with -performWithWMBridgeDelegate.
// Signatures verified on macOS 27.0.1 (26A434). Every class and selector is checked
// against these encodings before first use; on any mismatch the feature stays off.
typedef struct {
    const char *className;
    const char *initSelector;
    const char *initSignature;
    Class cls;
} ISSBridgedOperation;

static ISSBridgedOperation moveWindowsOp = {
    "SLSBridgedMoveWindowsToManagedSpaceOperation", "initWithWindows:spaceID:", "@@:@Q", Nil};
static ISSBridgedOperation showSpacesOp = {
    "SLSBridgedShowSpacesOperation", "initWithSpaces:", "@@:@", Nil};
static ISSBridgedOperation hideSpacesOp = {
    "SLSBridgedHideSpacesOperation", "initWithSpaces:", "@@:@", Nil};
static ISSBridgedOperation setCurrentSpaceOp = {
    "SLSBridgedManagedDisplaySetCurrentSpaceOperation", "initWithDisplayIdentifier:spaceID:", "@@:@Q", Nil};

static const char *kPerformSelector = "performWithWMBridgeDelegate";
static const char *kPerformSignature = "v@:";

// Exported by libobjc; lets C callers without an autorelease pool (ISSCli) avoid leaks.
extern void *objc_autoreleasePoolPush(void);
extern void objc_autoreleasePoolPop(void *pool);

bool iss_objc_encoding_matches(const char *encoding, const char *expected) {
    if (!encoding || !expected) {
        return false;
    }
    size_t matched = 0;
    for (const char *c = encoding; *c; c++) {
        if (*c >= '0' && *c <= '9') {
            continue;
        }
        if (expected[matched] != *c) {
            return false;
        }
        matched++;
    }
    return expected[matched] == '\0';
}

static bool method_matches(Class cls, const char *selector, const char *signature) {
    Method method = class_getInstanceMethod(cls, sel_registerName(selector));
    return method && iss_objc_encoding_matches(method_getTypeEncoding(method), signature);
}

static bool resolve_operation(ISSBridgedOperation *op) {
    Class cls = objc_getClass(op->className);
    if (!cls || !method_matches(cls, op->initSelector, op->initSignature) ||
        !method_matches(cls, kPerformSelector, kPerformSignature)) {
        return false;
    }
    op->cls = cls;
    return true;
}

bool iss_bridged_available(void) {
    static int cached = -1;
    if (cached != -1) {
        return cached == 1;
    }
    const char *disable = getenv("ISS_DISABLE_BRIDGED_OPS");
    if (disable && strcmp(disable, "1") == 0) {
        cached = 0;
        return false;
    }
    bool available = resolve_operation(&moveWindowsOp) && resolve_operation(&showSpacesOp) &&
                     resolve_operation(&hideSpacesOp) && resolve_operation(&setCurrentSpaceOp);
    cached = available ? 1 : 0;
    return available;
}

// Returns a +1 operation, or nil. init consumes the allocated object.
static id create_with_array(const ISSBridgedOperation *op, CFArrayRef array) {
    id allocated = ((id (*)(Class, SEL))objc_msgSend)(op->cls, sel_registerName("alloc"));
    return ((id (*)(id, SEL, CFArrayRef))objc_msgSend)(allocated, sel_registerName(op->initSelector), array);
}

static id create_with_object_and_space(const ISSBridgedOperation *op, CFTypeRef object, uint64_t spaceID) {
    id allocated = ((id (*)(Class, SEL))objc_msgSend)(op->cls, sel_registerName("alloc"));
    return ((id (*)(id, SEL, CFTypeRef, uint64_t))objc_msgSend)(
        allocated, sel_registerName(op->initSelector), object, spaceID);
}

static void perform_and_release(id operation) {
    ((void (*)(id, SEL))objc_msgSend)(operation, sel_registerName(kPerformSelector));
    ((void (*)(id, SEL))objc_msgSend)(operation, sel_registerName("release"));
}

static void release_operation(id operation) {
    if (operation) {
        ((void (*)(id, SEL))objc_msgSend)(operation, sel_registerName("release"));
    }
}

bool iss_bridged_move_window(uint32_t windowID, uint64_t spaceID) {
    if (!iss_bridged_available()) {
        return false;
    }
    void *pool = objc_autoreleasePoolPush();
    CFNumberRef number = CFNumberCreate(NULL, kCFNumberSInt32Type, &windowID);
    CFArrayRef windows = CFArrayCreate(NULL, (const void **)&number, 1, &kCFTypeArrayCallBacks);
    CFRelease(number);

    id operation = create_with_object_and_space(&moveWindowsOp, windows, spaceID);
    CFRelease(windows);
    if (operation) {
        perform_and_release(operation);
    }
    objc_autoreleasePoolPop(pool);
    return operation != nil;
}

bool iss_bridged_activate_space(CFStringRef displayID, uint64_t spaceID, CFArrayRef displaySpaceIDs) {
    if (!iss_bridged_available() || !displayID || !displaySpaceIDs) {
        return false;
    }
    void *pool = objc_autoreleasePoolPush();

    CFNumberRef target = CFNumberCreate(NULL, kCFNumberSInt64Type, &spaceID);
    CFArrayRef shown = CFArrayCreate(NULL, (const void **)&target, 1, &kCFTypeArrayCallBacks);
    CFMutableArrayRef hidden = CFArrayCreateMutable(NULL, 0, &kCFTypeArrayCallBacks);
    for (CFIndex i = 0; i < CFArrayGetCount(displaySpaceIDs); i++) {
        CFNumberRef value = (CFNumberRef)CFArrayGetValueAtIndex(displaySpaceIDs, i);
        if (!CFEqual(value, target)) {
            CFArrayAppendValue(hidden, value);
        }
    }
    CFRelease(target);

    // Create all three before dispatching any, so a failure leaves nothing half-applied
    id show = create_with_array(&showSpacesOp, shown);
    id hide = create_with_array(&hideSpacesOp, hidden);
    id setCurrent = create_with_object_and_space(&setCurrentSpaceOp, displayID, spaceID);
    CFRelease(shown);
    CFRelease(hidden);

    bool created = show && hide && setCurrent;
    if (created) {
        // Order verified on macOS 27: show the target, hide its siblings, then make it current
        perform_and_release(show);
        perform_and_release(hide);
        perform_and_release(setCurrent);
    } else {
        release_operation(show);
        release_operation(hide);
        release_operation(setCurrent);
    }
    objc_autoreleasePoolPop(pool);
    return created;
}
