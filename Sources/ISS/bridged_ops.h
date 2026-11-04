#ifndef BRIDGED_OPS_H
#define BRIDGED_OPS_H

#include <CoreFoundation/CoreFoundation.h>
#include <stdbool.h>
#include <stdint.h>

#include "include/ISSWindowCarry.h"

/**
 * @brief Returns true when the private SkyLight window-management operations used
 * to carry a dragged window across spaces exist with the expected method signatures.
 *
 * The check runs once and is cached. Set ISS_DISABLE_BRIDGED_OPS=1 to force false.
 */
bool iss_bridged_available(void);

/**
 * @brief Moves a window to a managed space without activating it.
 * @return true if the operation was created and dispatched (it applies asynchronously)
 */
bool iss_bridged_move_window(uint32_t windowID, uint64_t spaceID);

/**
 * @brief Makes a space current on its display: shows it, hides the display's other
 * spaces, then sets it as the display's current space. No animation is played.
 * @param displayID Display identifier from CGSCopyManagedDisplaySpaces
 * @param spaceID The space to activate
 * @param displaySpaceIDs Every space on that display (CFNumber, 64-bit)
 * @return true if all three operations were created and dispatched
 */
bool iss_bridged_activate_space(CFStringRef displayID, uint64_t spaceID, CFArrayRef displaySpaceIDs);

#endif /* BRIDGED_OPS_H */
