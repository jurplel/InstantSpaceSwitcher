#ifndef ISS_h
#define ISS_h

#include <stdbool.h>
#include <stdint.h>

/** @brief Initialize resources
 * @return true on success, false on failure
 */
bool iss_init(void);

/** @brief Clean up resources */
void iss_destroy(void);

/** @brief The direction to switch spaces towards */
typedef enum {
    ISSDirectionLeft = 0,
    ISSDirectionRight = 1
} ISSDirection;

/**
 * @brief Describes the current space state for the active display.
 */
typedef struct {
    unsigned int currentIndex; /**< Zero-based index of the active space */
    unsigned int spaceCount;   /**< Total number of user-visible spaces */
} ISSSpaceInfo;

/**
 * @brief Performs the space switch if the requested move is within bounds.
 * @param direction The direction to switch spaces towards
 * @return true if the switch was posted, false if blocked by bounds or errors
 */
bool iss_switch(ISSDirection direction);

/**
 * @brief Retrieves the current space info for the display where the cursor is located.
 * @param info Output pointer that receives the info struct.
 * @return true on success, false if unavailable (e.g. API failure)
 */
bool iss_get_space_info(ISSSpaceInfo *info);

/**
 * @brief Retrieves the current space info for the active menu-bar display.
 * @param info Output pointer that receives the info struct.
 * @return true on success, false if unavailable (e.g. API failure)
 */
bool iss_get_menubar_space_info(ISSSpaceInfo *info);

/**
 * @brief Determines if a move in the given direction is allowed for the info.
 * @param info Space info snapshot.
 * @param direction Desired direction to move.
 * @return true if the move is permissible.
 */
bool iss_can_move(ISSSpaceInfo info, ISSDirection direction);

/**
 * @brief Attempts to switch directly to the provided space index.
 * @param targetIndex Zero-based index for the desired space.
 * @return true if the request succeeded (already on target or switches posted)
 */
bool iss_switch_to_index(unsigned int targetIndex);

/**
 * @brief Retrieves the current space info for a specific display.
 * @param info Output pointer that receives the info struct.
 * @param displayID The CGDirectDisplayID for the target display.
 * @return true on success, false if unavailable
 */
bool iss_get_space_info_for_display(ISSSpaceInfo *info, uint32_t displayID);

/**
 * @brief Attempts to switch to a space on a specific display, moving cursor if needed.
 * @param targetIndex Zero-based index for the desired space on that display.
 * @param displayID The CGDirectDisplayID for the target display.
 * @return true if the request succeeded
 */
bool iss_switch_to_index_on_display(unsigned int targetIndex, uint32_t displayID);

#endif /* ISS_h */
