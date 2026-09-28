#ifndef ISS_GESTURE_EVENT_H
#define ISS_GESTURE_EVENT_H

#include <ApplicationServices/ApplicationServices.h>
#include <stdbool.h>
#include <stdint.h>

// Internal construction API. Returned events are retained; nothing is posted.
CGEventRef iss_create_dock_swipe_event(uint8_t phase, double progress,
                                      double velocity, bool augment);

#endif
