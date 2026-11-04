#ifndef WINDOW_FOCUS_H
#define WINDOW_FOCUS_H

#include <ApplicationServices/ApplicationServices.h>
#include <stdbool.h>
#include <stdint.h>

/**
 * @brief Brings a window to the front and focuses its app, via Accessibility.
 *
 * Activating a space directly makes that space's own frontmost app active, so a window
 * carried onto it would otherwise end up behind the space's windows and unfocused.
 * Runs shortly after the call, once the space switch has applied.
 */
void iss_focus_window_soon(uint32_t windowID);

/**
 * @brief Whether the point is on a part of the given window that drags it (title bar,
 * toolbar background, title text), by Accessibility hit test.
 */
bool iss_point_is_window_drag_area(CGPoint point, uint32_t windowID);

#endif /* WINDOW_FOCUS_H */
