import SwiftUI
import RealityKit

// MARK: - GameViewModel
//
// Session state shared between the menu window, the control panel, and the
// immersive scene. Inputs flow into DriveSystem's statics; stats flow back
// for the HUD.

@Observable
@MainActor
final class GameViewModel {

    var isDriving = false
    var smashCount = 0
    var throttle: Float = 0 {
        didSet { DriveSystem.throttleInput = throttle }
    }

    /// Speedometer, refreshed by the HUD timer.
    var speed: Float { DriveSystem.currentSpeed }

    func reset() {
        smashCount = 0
        throttle = 0
        DriveSystem.throttleInput = 0
        DriveSystem.steeringInput = 0
    }
}
