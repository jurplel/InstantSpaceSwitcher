import Foundation
import ISS

/// Keep preference migration, the settings preview, and the C driver in sync.
struct AnimationSettings {
  static let speedNames = ["Normal", "Fast", "Faster", "Fastest", "Instant", "Custom"]
  static let speeds = [40.0, ISS_DEFAULT_GESTURE_SPEED, 60.0, 80.0, 2000.0]
  static let curveNames = ["Gentle", "Linear", "Ease In", "Ease Out", "Smooth", "Custom"]
  static let curves: [(Double, Double)] = [(0.1, 0.1), (0, 0), (0.5, 0), (0, 0.5), (0.5, 0.5)]

  var speed = ISS_DEFAULT_GESTURE_SPEED
  var customDuration = 0.0
  var easeIn = 0.1
  var easeOut = 0.1

  var isInstant: Bool { speed >= 2000 }
  var duration: Double { customDuration > 0 ? customDuration : max(0.08, min(0.35, 11 / speed)) }
  var speedIndex: Int { isInstant ? 4 : customDuration > 0 ? 5 : Self.speeds.firstIndex(of: speed) ?? 1 }
  var curveIndex: Int {
    Self.curves.firstIndex { abs($0.0 - easeIn) < 0.001 && abs($0.1 - easeOut) < 0.001 } ?? 5
  }

  static func load(from defaults: UserDefaults = .standard) -> Self {
    var settings = Self()
    let speed = defaults.double(forKey: "gestureSpeed")
    if speed.isFinite && speed > 0 { settings.speed = speed }
    let duration = defaults.double(forKey: "animationDurationMs") / 1000
    if duration.isFinite && duration > 0 { settings.customDuration = max(0.08, min(1, duration)) }
    for (key, path) in [("animationEaseIn", \.easeIn), ("animationEaseOut", \.easeOut)] as [(String, WritableKeyPath<Self, Double>)] {
      if let value = defaults.object(forKey: key) as? Double, value.isFinite {
        settings[keyPath: path] = max(0, min(0.5, value))
      }
    }
    return settings
  }

  func apply() {
    iss_set_gesture_speed(speed)
    iss_set_animation_duration(customDuration)
    iss_set_animation_curve(easeIn, easeOut)
  }

  func save(to defaults: UserDefaults = .standard) {
    defaults.set(speed, forKey: "gestureSpeed")
    defaults.set(customDuration * 1000, forKey: "animationDurationMs")
    defaults.set(easeIn, forKey: "animationEaseIn")
    defaults.set(easeOut, forKey: "animationEaseOut")
    apply()
  }
}
