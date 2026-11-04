#ifndef _ISS_WINDOW_CARRY_H
#define _ISS_WINDOW_CARRY_H

// Pure helpers behind carrying a dragged window to another space.
// Exposed for unit tests; they do not touch the window server.

#include <ApplicationServices/ApplicationServices.h>
#include <stdbool.h>
#include <stdint.h>

#include "ISS.h"

/** @brief How a space switch is carried out. */
typedef enum {
    ISSSwitchRouteSwipe = 0, /**< Synthetic Dock swipe (the default path) */
    ISSSwitchRouteCarry = 1, /**< Move the dragged window, then activate the target space */
} ISSSwitchRoute;

/**
 * @brief Picks the switch route: carry only when the window-management operations are
 * available and a window is being dragged that may be carried.
 */
ISSSwitchRoute iss_choose_switch_route(bool bridgedAvailable, bool windowDragged, bool windowCarriable);

/**
 * @brief A window can be carried only from the current user space to another user space.
 * Windows on several spaces (sticky) or on a fullscreen or system space are left alone.
 * @param windowSpaceCount Number of spaces the window belongs to
 * @param windowSpace The window's space (first one when there are several)
 * @param currentSpace The display's current space
 * @param currentSpaceType CGS type of the current space (0 = user)
 * @param targetSpaceType CGS type of the target space (0 = user)
 */
bool iss_window_can_be_carried(unsigned int windowSpaceCount, uint64_t windowSpace, uint64_t currentSpace,
                               int currentSpaceType, int targetSpaceType);

/**
 * @brief Neighboring space index in the given direction.
 * @return false at the first or last space
 */
bool iss_target_index_for_direction(unsigned int currentIndex, unsigned int spaceCount,
                                    ISSDirection direction, unsigned int *outTarget);

/** @brief Clamps a requested index to the last space, as iss_switch_to_index does. */
unsigned int iss_clamp_space_index(unsigned int requestedIndex, unsigned int spaceCount);

/**
 * @brief Whether a window moved together with the cursor since the button went down.
 *
 * True when the window kept its size, moved by at least one point, and its
 * displacement matches the cursor's within tolerance on both axes.
 */
bool iss_window_follows_cursor(CGRect downFrame, CGPoint downCursor,
                               CGRect frame, CGPoint cursor, double tolerance);

/**
 * @brief Whether a window is held still: the button went down on it but neither the window
 * nor (beyond the slop) the cursor has moved since. Combined with an Accessibility check
 * that the press was on the window's title bar or toolbar, this counts as grabbing it.
 */
bool iss_window_is_held(CGRect downFrame, CGPoint downCursor,
                        CGRect frame, CGPoint cursor, double slop);

/**
 * @brief Whether an Accessibility hit-test result is a part of a window that drags it:
 * the window frame itself (title bar), its toolbar background, or its title text.
 * @param role Role of the element under the cursor (e.g. "AXWindow")
 * @param parentRole Role of its parent, or NULL
 */
bool iss_ax_role_is_drag_area(const char *role, const char *parentRole);

/**
 * @brief Compares an Objective-C method type encoding with a compact signature.
 *
 * Offsets are ignored, so "@32@0:8@16Q24" matches "@@:@Q". Anything beyond plain
 * one-character types (qualifiers, structs, pointers) never matches.
 */
bool iss_objc_encoding_matches(const char *encoding, const char *expected);

#endif /* _ISS_WINDOW_CARRY_H */
