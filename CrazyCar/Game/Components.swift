import RealityKit
import simd

// MARK: - Car state
//
// Lives on the world root. The user sits at the app origin inside the cockpit.
// The car "moves" by sliding and rotating the world root inversely, while a
// kinematic chassis collider (child of the world root) tracks the car's pose
// in world space so RealityKit physics resolves real contacts against the
// dynamic obstacles.

struct CarStateComponent: Component {
    /// Car position in world (worldRoot local) space.
    var position: SIMD3<Float> = .zero
    /// Heading in radians. 0 faces -Z.
    var heading: Float = 0
    /// Current signed speed, m/s. Positive is forward.
    var speed: Float = 0
    /// Steering input, -1 (full left) ... 1 (full right).
    var steering: Float = 0
    /// Throttle input, -1 (reverse) ... 1 (full gas).
    var throttle: Float = 0
}

/// Marks the kinematic chassis collider entity.
struct CarChassisComponent: Component {}

/// Marks the steering wheel pivot; stores the current wheel angle in radians.
struct SteeringWheelComponent: Component {
    var angle: Float = 0
    /// Max physical wheel rotation each way, radians.
    static let maxAngle: Float = 2.4
}

/// Marks the gas pedal; stores press state for animation.
struct GasPedalComponent: Component {
    var isPressed: Bool = false
    /// Pedal rotation when fully pressed, radians.
    static let pressedAngle: Float = 0.35
}

/// Marks a smashable dynamic obstacle.
struct ObstacleComponent: Component {
    /// Cooldown so one hit does not spam explosions every contact frame.
    var lastHitTime: Double = -10
}

/// Popup explosion text and flash, animated by ExplosionPopSystem.
struct ExplosionPopComponent: Component {
    var age: Float = 0
    var lifetime: Float = 1.4
    var riseSpeed: Float = 0.55
    var spinSpeed: Float = 0
}

/// Marks an intact cute humanoid pedestrian.
struct CharacterComponent: Component {
    /// Facing direction, radians.
    var baseYaw: Float = 0
    /// Bob animation phase offset.
    var phase: Float = 0
}

/// Marks an exploded body part awaiting cleanup.
struct BodyPartComponent: Component {
    var age: Float = 0
    var lifetime: Float = 2.5
}

/// Idle wobble on cones and barrels for extra life.
struct WobbleComponent: Component {
    var phase: Float = 0
    var amplitude: Float = 0.05
}

@MainActor
func registerCrazyCarECS() {
    CarStateComponent.registerComponent()
    CarChassisComponent.registerComponent()
    SteeringWheelComponent.registerComponent()
    GasPedalComponent.registerComponent()
    ObstacleComponent.registerComponent()
    ExplosionPopComponent.registerComponent()
    WobbleComponent.registerComponent()
    CharacterComponent.registerComponent()
    BodyPartComponent.registerComponent()
    DriveSystem.registerSystem()
    ExplosionPopSystem.registerSystem()
    WobbleSystem.registerSystem()
    CharacterBobSystem.registerSystem()
    BodyPartSystem.registerSystem()
}
