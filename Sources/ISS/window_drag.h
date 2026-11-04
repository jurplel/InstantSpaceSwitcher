#ifndef WINDOW_DRAG_H
#define WINDOW_DRAG_H

#include <ApplicationServices/ApplicationServices.h>
#include <stdbool.h>
#include <stdint.h>

#include "include/ISSWindowCarry.h"

/**
 * @brief Starts a listen-only tap on left mouse down/up that remembers which normal
 * window was under the cursor when the button went down.
 * @return true on success
 */
bool iss_drag_tracker_start(void);

/** @brief Stops the tracker started by iss_drag_tracker_start(). */
void iss_drag_tracker_stop(void);

/**
 * @brief Returns the window currently being dragged by the left mouse button.
 *
 * A window counts as dragged only while the button is held and the window has moved
 * together with the cursor since the button went down (see iss_window_follows_cursor()).
 * Text selection, resizing and plain held clicks do not count.
 * @param outWindowID Receives the window ID
 * @return true if a window is being dragged
 */
bool iss_drag_current_window(uint32_t *outWindowID);

/** @brief Logs to stderr when ISS_DEBUG_CARRY=1 (diagnostics for carrying dragged windows). */
void iss_carry_log(const char *format, ...) __attribute__((format(printf, 1, 2)));

#endif /* WINDOW_DRAG_H */
