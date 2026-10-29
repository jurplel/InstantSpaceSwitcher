import Foundation
import ISS

enum SpaceTransitionSettings {
    static func duration(forGestureSpeed speed: Double) -> TimeInterval {
        switch speed {
        case 40.0:
            return 0.35
        case 50.0:
            return 0.25
        case 60.0:
            return 0.18
        case 80.0:
            return 0.10
        case 2000.0:
            return 0.0
        default:
            return 0.0
        }
    }

    static func outgoingOffset(for direction: ISSDirection, height: CGFloat) -> CGFloat {
        direction == ISSDirectionLeft ? height : -height
    }
}
