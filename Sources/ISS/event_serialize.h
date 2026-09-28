#ifndef EVENT_SERIALIZE_H
#define EVENT_SERIALIZE_H

#include <ApplicationServices/ApplicationServices.h>
#include <stdbool.h>
#include <stdint.h>

// Internal helpers shared with the construction layer and regression tests.
// Nonfinite values fail. Finite values saturate to signed 16.16 limits.
bool iss_double_to_fixed1616(double value, int32_t *result);
CFDataRef iss_copy_dock_swipe_data(CGEventRef event, CFDataRef serialized);
void iss_mark_synthetic_event(CGEventRef event);
bool iss_is_synthetic_event(CGEventRef event);

/**
 * @brief Augments a synthetic dock-swipe CGEvent with the raw IOHID payload
 * that macOS 27 requires to recognize synthetic trackpad swipe gestures.
 *
 * The returned event is retained and the caller is responsible for releasing it.
 *
 * @param event A synthetic dock-swipe CGEvent with the public gesture fields set.
 * @return A retained, augmented CGEventRef, or NULL on failure.
 */
CGEventRef iss_augment_dock_swipe_event(CGEventRef event);

/**
 * @brief Returns true when the running OS is macOS 27 or later.
 *
 * On these versions, synthetic dock-swipe events must carry the raw IOHID
 * payload created by iss_augment_dock_swipe_event() in order to be honored.
 *
 * For testing, set the environment variable ISS_FORCE_EVENT_AUGMENTATION=1
 * to enable augmentation on any version, or =0 to disable it.
 */
bool iss_requires_event_augmentation(void);

#endif /* EVENT_SERIALIZE_H */
