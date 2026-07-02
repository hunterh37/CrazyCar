import RealityKit
import simd

// MARK: - DriveSystem
//
// Real RealityKit System. Each frame it:
//  1. Reads throttle/steering inputs (written by the UI and wheel gesture).
//  2. Integrates a simple kinematic bicycle model into CarStateComponent.
//  3. Moves the kinematic chassis collider to the car's world pose so physics
//     resolves real contacts against dynamic obstacles.
//  4. Sets worldRoot's transform to the inverse car pose so the environment
//     streams past the seated user.
//
// The pure math lives in step(state:dt:) so tests can drive it directly.

struct DriveSystem: System {

    /// Inputs, written on the main thread by the control UI and wheel gesture.
    @MainActor static var throttleInput: Float = 0
    @MainActor static var steeringInput: Float = 0
    /// Speedometer readout for the HUD.
    @MainActor static var currentSpeed: Float = 0

    static let maxSpeed: Float = 14
    static let acceleration: Float = 7
    static let drag: Float = 1.6
    static let turnRate: Float = 1.4

    private static let carQuery = EntityQuery(where: .has(CarStateComponent.self))
    private static let chassisQuery = EntityQuery(where: .has(CarChassisComponent.self))

    init(scene: RealityKit.Scene) {}

    func update(context: SceneUpdateContext) {
        let dt = Float(context.deltaTime)
        guard dt > 0 else { return }

        for worldRoot in context.scene.performQuery(Self.carQuery) {
            guard var state = worldRoot.components[CarStateComponent.self] else { continue }
            state.throttle = Self.throttleInput
            state.steering = Self.steeringInput

            state = Self.step(state: state, dt: dt)
            worldRoot.components.set(state)
            Self.currentSpeed = state.speed

            let carRotation = simd_quatf(angle: state.heading, axis: [0, 1, 0])

            // Chassis collider follows the car pose inside the world.
            for chassis in context.scene.performQuery(Self.chassisQuery)
            where chassis.parent == worldRoot {
                chassis.position = state.position + SIMD3<Float>(0, 0.55, 0)
                chassis.orientation = carRotation
            }

            // World root gets the inverse pose: the user stays at the origin.
            let inverseRotation = carRotation.inverse
            worldRoot.orientation = inverseRotation
            worldRoot.position = inverseRotation.act(-state.position)
        }
    }

    /// Pure kinematic bicycle step. No scene access, directly testable.
    static func step(state: CarStateComponent, dt: Float) -> CarStateComponent {
        var s = state

        // Speed: throttle accelerates, drag bleeds off.
        s.speed += s.throttle * acceleration * dt
        s.speed -= s.speed * drag * dt * (s.throttle == 0 ? 1.6 : 0.35)
        s.speed = max(-maxSpeed * 0.4, min(maxSpeed, s.speed))
        if abs(s.speed) < 0.02 && s.throttle == 0 { s.speed = 0 }

        // Heading: steering authority scales with speed, flips in reverse.
        let speedFactor = min(1, abs(s.speed) / 4)
        s.heading += s.steering * turnRate * speedFactor * dt * (s.speed >= 0 ? 1 : -1)

        // Position: forward is -Z rotated by heading.
        let forward = SIMD3<Float>(-sin(s.heading), 0, -cos(s.heading))
        s.position += forward * s.speed * dt

        return s
    }
}

// MARK: - WobbleSystem
//
// Gentle idle sway on obstacles that have not been knocked over yet, so the
// arena feels alive. Skips anything moving under physics.

struct WobbleSystem: System {

    private static let query = EntityQuery(where: .has(WobbleComponent.self))
    @MainActor private static var time: Float = 0

    init(scene: RealityKit.Scene) {}

    func update(context: SceneUpdateContext) {
        Self.time += Float(context.deltaTime)
        for entity in context.scene.performQuery(Self.query) {
            guard let wobble = entity.components[WobbleComponent.self] else { continue }
            let velocity = entity.components[PhysicsMotionComponent.self]?.linearVelocity ?? .zero
            if simd_length(velocity) > 0.5 {
                // Once physics has flung it, the wobble is done.
                entity.components.remove(WobbleComponent.self)
                continue
            }
            let sway = sin(Self.time * 2.2 + wobble.phase) * wobble.amplitude
            entity.orientation = simd_quatf(angle: sway, axis: [0, 0, 1])
        }
    }
}
