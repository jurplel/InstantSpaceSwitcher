#ifndef _ISS_H
#define _ISS_H

#include <stdbool.h>
#include <CoreFoundation/CoreFoundation.h>

// Match the Fast preset: retain a visible slide instead of skipping it.
#define ISS_DEFAULT_GESTURE_SPEED 50.0

/** @brief Initialize resources
 * @return true on success, false on failure
 */
bool iss_init(void);

/** @brief Finish any active gesture and clean up resources. Call on the main thread. */
void iss_destroy(void);

/** @brief Pump the main run loop until the pending slide finishes (for CLI use).
 * Call on the main thread. The app's normal run loop handles this automatically.
 */
void iss_wait_for_pending_switch(void);

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
    char displayID[128];       /**< UUID string of the display */
} ISSSpaceInfo;

/**
 * @brief Starts the space switch if the requested move is within bounds.
 * Call on the main thread. Animated switches advance on its run loop.
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

/** Switch to the Space containing a window, using that window's display. */
bool iss_switch_to_window(unsigned int windowID);
bool iss_window_is_on_active_space(unsigned int windowID);
bool iss_has_pending_switch(void);

typedef enum {
    ISSUserInputCommandTab,
    ISSUserInputMouseClick,
    ISSUserInputSpaceNavigation
} ISSUserInput;
/** Observe input on the main run loop without consuming or changing it. */
typedef void (*ISSUserInputCallback)(ISSUserInput input);
void iss_set_user_input_callback(ISSUserInputCallback callback);

/**
 * @brief Enables or disables interception of trackpad horizontal swipe gestures.
 *
 * When enabled, native horizontal dock-swipe gestures are suppressed and
 * replaced with space switches using the selected animation speed.
 * @param enabled true to intercept, false to pass gestures through normally.
 */
void iss_set_swipe_override(bool enabled);

/**
 * @brief Callback invoked after any successful space switch.
 * @param newSpaceIndex Zero-based index of the space that was switched to.
 */
typedef void (*ISSSwitchCallback)(unsigned int newSpaceIndex);

/**
 * @brief Registers a callback invoked after each successful space switch.
 * @param callback Function pointer, or NULL to clear.
 */
void iss_set_switch_callback(ISSSwitchCallback callback);

/**
 * @brief Resets the predicted space indices so the next bounds check falls back
 * to live CGS data. Call this whenever the active space changes externally
 * (e.g. from activeSpaceDidChangeNotification).
 */
void iss_reset_predictions(void);

// MARK: - Public API

/**
 * @brief Returns true when App Exposé is currently active.
 * Detects a Dock layer-18 overlay combined with 1-2 layer-20 windows.
 */
bool iss_is_expose_active(void);

/**
 * @brief Returns true when Mission Control is currently active.
 * Detects a Dock layer-18 overlay combined with 3+ layer-20 windows.
 */
bool iss_is_mission_control_active(void);

/**
 * @brief Enables or disables experimental overlay detection.
 * When disabled, iss_is_expose_active() and iss_is_mission_control_active() always return false.
 * @param enabled true to enable detection, false to disable.
 */
void iss_set_overlay_detection_enabled(bool enabled);

/**
 * @brief Sets animation speed for shortcuts, CLI, and swipe override.
 * @param speed Legacy speed value: 50 targets a 220ms slide; 2000 is instant.
 * Positive finite values only. Native Dock rendering may add latency.
 */
void iss_set_gesture_speed(double speed);

/** @brief Override slide duration in seconds (0 restores speed presets).
 * Positive values are clamped to 0.08–1.0 seconds. Instant still takes priority.
 */
void iss_set_animation_duration(double seconds);

/** @brief Set the fraction of time spent accelerating and decelerating.
 * Each value is clamped to 0–0.5. Defaults are 0.1 and 0.1.
 * Settings apply to the next gesture, not a slide already in progress.
 */
void iss_set_animation_curve(double easeIn, double easeOut);

/** @brief Evaluate normalized slide progress for a time in 0–1.
 * Shared by the gesture driver and the settings preview.
 */
double iss_animation_progress(double time, double easeIn, double easeOut);

#endif /* _ISS_H */
