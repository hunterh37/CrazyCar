import RealityKit
import UIKit
import simd

// MARK: - ExplosionBuilder
//
// Popup explosion on collision: a particle burst, an expanding flash sphere,
// and extruded 3D text with a fun word. Spawned in app space (under root, not
// worldRoot) so popups hang where the hit happened relative to the user.
// ExplosionPopSystem animates and despawns them.

enum ExplosionBuilder {

    static let words = [
        "BOOM!", "KAPOW!", "WHAM!", "SMASH!", "CRUNCH!",
        "BONK!", "POW!", "YEET!", "WRECKED!", "SPLAT!",
        "KABOOM!", "OOF!", "ZOINK!", "THWACK!",
    ]

    static let wordColors: [UIColor] = [
        .systemYellow, .systemOrange, .systemRed, .systemPink, .systemTeal,
    ]

    @MainActor
    static func spawn(at position: SIMD3<Float>, in parent: Entity, word: String, color: UIColor, intensity: Float) {
        let explosion = Entity()
        explosion.name = "explosion"
        explosion.position = position
        explosion.components.set(ExplosionPopComponent(
            lifetime: 1.2 + intensity * 0.5,
            riseSpeed: 0.4 + intensity * 0.4,
            spinSpeed: Float.random(in: -1.5...1.5)
        ))
        parent.addChild(explosion)

        explosion.addChild(makeFlash(intensity: intensity))
        explosion.addChild(makeBurst(intensity: intensity))
        explosion.addChild(makeWord(word, color: color))
    }

    /// Expanding emissive flash sphere, scaled up by ExplosionPopSystem.
    @MainActor
    private static func makeFlash(intensity: Float) -> ModelEntity {
        var mat = UnlitMaterial(color: UIColor(red: 1, green: 0.75, blue: 0.2, alpha: 0.85))
        mat.blending = .transparent(opacity: 0.85)
        let flash = ModelEntity(
            mesh: .generateSphere(radius: 0.12 + intensity * 0.1),
            materials: [mat]
        )
        flash.name = "flash"
        return flash
    }

    /// One-shot spark burst.
    @MainActor
    private static func makeBurst(intensity: Float) -> Entity {
        let emitter = Entity()
        emitter.name = "burst"
        var p = ParticleEmitterComponent()
        p.emitterShape     = .sphere
        p.emitterShapeSize = [0.1, 0.1, 0.1]
        p.speed            = 1.8 + intensity * 1.6
        p.speedVariation   = 1.2
        p.mainEmitter.birthRate    = 1400
        p.mainEmitter.lifeSpan     = 0.7
        p.mainEmitter.size         = 0.025
        p.mainEmitter.opacityCurve = .linearFadeOut
        p.mainEmitter.color = .evolving(
            start: .single(UIColor(red: 1.0, green: 0.65, blue: 0.1, alpha: 1.0)),
            end:   .single(UIColor(red: 0.85, green: 0.1, blue: 0.05, alpha: 0.0)))
        p.timing = .once(warmUp: 0, emit: .init(duration: 0.18, variation: 0.05))
        emitter.components.set(p)
        return emitter
    }

    /// Extruded 3D word, centered, facing the driver.
    @MainActor
    private static func makeWord(_ word: String, color: UIColor) -> ModelEntity {
        let mesh = MeshResource.generateText(
            word,
            extrusionDepth: 0.035,
            font: .systemFont(ofSize: 0.22, weight: .black),
            containerFrame: .zero,
            alignment: .center,
            lineBreakMode: .byWordWrapping
        )
        let text = ModelEntity(
            mesh: mesh,
            materials: [SimpleMaterial(color: color, isMetallic: true)]
        )
        text.name = "word"
        // generateText origins at the bottom-left; center the word on the blast.
        let bounds = mesh.bounds
        text.position = [-bounds.center.x, 0.15, 0]
        return text
    }
}

// MARK: - ExplosionPopSystem
//
// Pops the word in with an overshoot, inflates and fades the flash, floats
// the whole popup upward, billboards it at the user, then removes it.

struct ExplosionPopSystem: System {

    private static let query = EntityQuery(where: .has(ExplosionPopComponent.self))

    init(scene: RealityKit.Scene) {}

    func update(context: SceneUpdateContext) {
        let dt = Float(context.deltaTime)
        for entity in context.scene.performQuery(Self.query) {
            guard var pop = entity.components[ExplosionPopComponent.self] else { continue }
            pop.age += dt
            entity.components.set(pop)

            if pop.age >= pop.lifetime {
                entity.removeFromParent()
                continue
            }

            let t = pop.age / pop.lifetime

            // Rise and lazy spin.
            entity.position.y += pop.riseSpeed * dt

            // Word: overshoot pop in the first 25 percent, then shrink out.
            if let word = entity.findEntity(named: "word") {
                let popIn = min(1, t / 0.25)
                let overshoot = 1 + 0.45 * sin(popIn * .pi)
                let fadeOut: Float = t > 0.75 ? max(0.001, 1 - (t - 0.75) / 0.25) : 1
                word.scale = SIMD3<Float>(repeating: popIn * overshoot * fadeOut)
                word.orientation = simd_quatf(angle: pop.spinSpeed * pop.age * 0.4, axis: [0, 1, 0])
            }

            // Flash: fast inflate, quick fade by scale.
            if let flash = entity.findEntity(named: "flash") {
                let flashT = min(1, t / 0.3)
                flash.scale = SIMD3<Float>(repeating: 1 + flashT * 3)
                if t > 0.3 { flash.scale = .init(repeating: 0.001) }
            }

            // Face the user (seated at the app origin).
            let worldPos = entity.position(relativeTo: nil)
            let toUser = SIMD3<Float>(0, worldPos.y, 0) - worldPos
            if simd_length(toUser) > 0.01 {
                entity.look(at: worldPos + toUser, from: worldPos, relativeTo: nil)
                // look(at:) points -Z at the target; text faces +Z, so flip.
                entity.orientation = entity.orientation * simd_quatf(angle: .pi, axis: [0, 1, 0])
            }
        }
    }
}
