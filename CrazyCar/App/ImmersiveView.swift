import SwiftUI
import RealityKit
import simd

// MARK: - ImmersiveView
//
// Thin shell: builds the scene with CarSceneBuilder, subscribes to chassis
// collisions to spawn popup explosions, and forwards the steering wheel drag
// into DriveSystem. No game logic lives here.

struct ImmersiveView: View {

    @Environment(GameViewModel.self) private var viewModel

    @State private var root: Entity?
    @State private var collisionSubscription: EventSubscription?
    @State private var dragStartAngle: Float?

    var body: some View {
        RealityView { content in
            let scene = CarSceneBuilder.build()
            content.add(scene)
            root = scene

            if let chassis = scene.findEntity(named: "carChassis") {
                collisionSubscription = content.subscribe(to: CollisionEvents.Began.self, on: chassis) { event in
                    handleCrash(event: event)
                }
            }
        }
        .gesture(steeringGesture)
        .simultaneousGesture(gasPedalGesture)
    }

    // MARK: Gas pedal

    private var gasPedalGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .targetedToEntity(where: .has(GasPedalComponent.self))
            .onChanged { value in
                let pedal = value.entity
                guard var comp = pedal.components[GasPedalComponent.self], !comp.isPressed else { return }
                comp.isPressed = true
                pedal.components.set(comp)
                setPedal(pedal, pressed: true)
                DriveSystem.throttleInput = 1
            }
            .onEnded { value in
                let pedal = value.entity
                if var comp = pedal.components[GasPedalComponent.self] {
                    comp.isPressed = false
                    pedal.components.set(comp)
                }
                setPedal(pedal, pressed: false)
                DriveSystem.throttleInput = 0
            }
    }

    private func setPedal(_ pedal: Entity, pressed: Bool) {
        let press: Float = pressed ? GasPedalComponent.pressedAngle : 0
        var transform = pedal.transform
        transform.rotation = simd_quatf(angle: -0.35 - press, axis: [1, 0, 0])
        pedal.move(to: transform, relativeTo: pedal.parent, duration: 0.1, timingFunction: .easeOut)
    }

    // MARK: Steering

    private var steeringGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .targetedToEntity(where: .has(SteeringWheelComponent.self))
            .onChanged { value in
                let wheel = value.entity
                guard var comp = wheel.components[SteeringWheelComponent.self] else { return }
                if dragStartAngle == nil { dragStartAngle = comp.angle }

                // Horizontal drag spins the wheel, one full sweep per ~40cm.
                let delta = Float(value.translation.width) * 0.012
                let angle = max(-SteeringWheelComponent.maxAngle,
                                min(SteeringWheelComponent.maxAngle, (dragStartAngle ?? 0) - delta))
                comp.angle = angle
                wheel.components.set(comp)
                spinWheel(wheel, to: angle)
                DriveSystem.steeringInput = angle / SteeringWheelComponent.maxAngle
            }
            .onEnded { value in
                dragStartAngle = nil
                // Wheel self-centers.
                let wheel = value.entity
                if var comp = wheel.components[SteeringWheelComponent.self] {
                    comp.angle = 0
                    wheel.components.set(comp)
                }
                spinWheel(value.entity, to: 0)
                DriveSystem.steeringInput = 0
            }
    }

    private func spinWheel(_ wheel: Entity, to angle: Float) {
        wheel.orientation =
            simd_quatf(angle: -0.45, axis: [1, 0, 0]) *
            simd_quatf(angle: angle, axis: [0, 0, 1])
    }

    // MARK: Crash handling

    private func handleCrash(event: CollisionEvents.Began) {
        let other = event.entityA.components.has(CarChassisComponent.self) ? event.entityB : event.entityA
        guard var obstacle = other.components[ObstacleComponent.self] else { return }

        let now = Date.timeIntervalSinceReferenceDate
        guard now - obstacle.lastHitTime > 0.6 else { return }
        obstacle.lastHitTime = now
        other.components.set(obstacle)

        let speed = abs(DriveSystem.currentSpeed)
        guard speed > 0.8, let root else { return }

        // Popup lives in app space so it hangs where the hit happened.
        var hitPosition = other.position(relativeTo: root)
        hitPosition.y = max(hitPosition.y, 0.6) + 0.5

        let intensity = min(1, speed / DriveSystem.maxSpeed)
        let isCharacter = other.components.has(CharacterComponent.self)
        ExplosionBuilder.spawn(
            at: hitPosition,
            in: root,
            word: isCharacter
                ? (CharacterBuilder.crashWords.randomElement() ?? "BAM!")
                : (ExplosionBuilder.words.randomElement() ?? "BOOM!"),
            color: ExplosionBuilder.wordColors.randomElement() ?? .systemYellow,
            intensity: intensity
        )

        // Characters burst into flying body parts.
        if isCharacter, let worldRoot = root.findEntity(named: "worldRoot") {
            CharacterBuilder.explode(other, in: worldRoot, intensity: intensity)
            viewModel.smashCount += 1
            return
        }

        // Extra fun physics: an upward kick scaled by impact speed.
        if let model = other as? ModelEntity {
            let away = simd_normalize(SIMD3<Float>(
                Float.random(in: -0.4...0.4), 1, Float.random(in: -0.4...0.4)))
            model.addForce(away * (18 + intensity * 55), relativeTo: nil)
            model.addTorque(SIMD3<Float>(
                Float.random(in: -6...6), Float.random(in: -6...6), Float.random(in: -6...6)),
                relativeTo: nil)
        }

        viewModel.smashCount += 1
    }
}
