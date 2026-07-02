import RealityKit
import UIKit
import simd

// MARK: - CharacterBuilder
//
// Cute low poly humanoid pedestrians built from primitives. They stand near
// the road bobbing gently. Drive into one and it bursts apart: every body
// part becomes its own dynamic physics body flung outward, plus the classic
// arcade popup ("BAM!") from ExplosionBuilder.
//
// ECS notes:
//  - All meshes and materials are generated once in SharedAssets and reused,
//    so RealityKit batches draw calls across every character.
//  - An intact character is a single kinematic-free dynamic body with one
//    capsule-ish box collider on the root. Body parts are plain ModelEntity
//    children with zero physics until the explosion.
//  - Exploded parts get BodyPartComponent and are cleaned up by
//    BodyPartSystem after a short lifetime, so the scene never accumulates.

enum CharacterBuilder {

    static let crashWords = ["BAM!", "BONK!", "OOF!", "YOWCH!", "SPLAT!", "WHAM!"]

    @MainActor
    struct SharedAssets {
        // Cute pastel outfit palettes: shirt, pants pairs.
        let shirts: [SimpleMaterial] = [
            SimpleMaterial(color: UIColor(red: 1.00, green: 0.55, blue: 0.60, alpha: 1), roughness: 1, isMetallic: false),
            SimpleMaterial(color: UIColor(red: 0.45, green: 0.70, blue: 0.95, alpha: 1), roughness: 1, isMetallic: false),
            SimpleMaterial(color: UIColor(red: 0.55, green: 0.85, blue: 0.55, alpha: 1), roughness: 1, isMetallic: false),
            SimpleMaterial(color: UIColor(red: 0.95, green: 0.80, blue: 0.35, alpha: 1), roughness: 1, isMetallic: false),
            SimpleMaterial(color: UIColor(red: 0.75, green: 0.60, blue: 0.95, alpha: 1), roughness: 1, isMetallic: false),
        ]
        let pants: [SimpleMaterial] = [
            SimpleMaterial(color: UIColor(red: 0.30, green: 0.35, blue: 0.55, alpha: 1), roughness: 1, isMetallic: false),
            SimpleMaterial(color: UIColor(red: 0.45, green: 0.30, blue: 0.25, alpha: 1), roughness: 1, isMetallic: false),
            SimpleMaterial(color: UIColor(red: 0.35, green: 0.55, blue: 0.45, alpha: 1), roughness: 1, isMetallic: false),
        ]
        let skins: [SimpleMaterial] = [
            SimpleMaterial(color: UIColor(red: 1.00, green: 0.85, blue: 0.70, alpha: 1), roughness: 1, isMetallic: false),
            SimpleMaterial(color: UIColor(red: 0.90, green: 0.70, blue: 0.55, alpha: 1), roughness: 1, isMetallic: false),
            SimpleMaterial(color: UIColor(red: 0.60, green: 0.42, blue: 0.30, alpha: 1), roughness: 1, isMetallic: false),
        ]
        let hairs: [SimpleMaterial] = [
            SimpleMaterial(color: UIColor(red: 0.20, green: 0.15, blue: 0.12, alpha: 1), roughness: 1, isMetallic: false),
            SimpleMaterial(color: UIColor(red: 0.85, green: 0.65, blue: 0.30, alpha: 1), roughness: 1, isMetallic: false),
            SimpleMaterial(color: UIColor(red: 0.55, green: 0.30, blue: 0.18, alpha: 1), roughness: 1, isMetallic: false),
            SimpleMaterial(color: UIColor(red: 0.90, green: 0.45, blue: 0.55, alpha: 1), roughness: 1, isMetallic: false),
        ]
        let eye = UnlitMaterial(color: UIColor(red: 0.10, green: 0.10, blue: 0.14, alpha: 1))
        let cheek = SimpleMaterial(color: UIColor(red: 1.0, green: 0.60, blue: 0.60, alpha: 1), roughness: 1, isMetallic: false)

        // Meshes, one of each, shared by all characters.
        let head = MeshResource.generateSphere(radius: 0.16)
        let torso = MeshResource.generateBox(size: [0.26, 0.30, 0.16], cornerRadius: 0.06)
        let arm = MeshResource.generateBox(size: [0.08, 0.26, 0.08], cornerRadius: 0.035)
        let leg = MeshResource.generateBox(size: [0.09, 0.26, 0.09], cornerRadius: 0.035)
        let eyeMesh = MeshResource.generateSphere(radius: 0.022)
        let cheekMesh = MeshResource.generateSphere(radius: 0.03)
        let hairMesh = MeshResource.generateSphere(radius: 0.165)

        // Collider shapes for exploded parts, matched to the part meshes.
        let headShape = ShapeResource.generateSphere(radius: 0.16)
        let torsoShape = ShapeResource.generateBox(size: [0.26, 0.30, 0.16])
        let armShape = ShapeResource.generateBox(size: [0.08, 0.26, 0.08])
        let legShape = ShapeResource.generateBox(size: [0.09, 0.26, 0.09])
        // Whole character collider.
        let bodyShape = ShapeResource.generateBox(size: [0.34, 0.95, 0.22])
    }

    @MainActor static let assets = SharedAssets()

    // MARK: Build one character

    @MainActor
    static func make(seed: Float) -> Entity {
        let a = assets
        func pick<T>(_ items: [T], _ salt: Float) -> T {
            items[Int((seed * 977 + salt * 131).truncatingRemainder(dividingBy: Float(items.count)))]
        }
        let shirt = pick(a.shirts, 1)
        let pant = pick(a.pants, 2)
        let skin = pick(a.skins, 3)
        let hair = pick(a.hairs, 4)

        let character = Entity()
        character.name = "character"

        // Legs
        let legL = ModelEntity(mesh: a.leg, materials: [pant])
        legL.name = "part_legL"
        legL.position = [-0.075, 0.13, 0]
        let legR = ModelEntity(mesh: a.leg, materials: [pant])
        legR.name = "part_legR"
        legR.position = [0.075, 0.13, 0]

        // Torso
        let torso = ModelEntity(mesh: a.torso, materials: [shirt])
        torso.name = "part_torso"
        torso.position = [0, 0.41, 0]

        // Arms
        let armL = ModelEntity(mesh: a.arm, materials: [shirt])
        armL.name = "part_armL"
        armL.position = [-0.18, 0.42, 0]
        armL.orientation = simd_quatf(angle: 0.15, axis: [0, 0, 1])
        let armR = ModelEntity(mesh: a.arm, materials: [shirt])
        armR.name = "part_armR"
        armR.position = [0.18, 0.42, 0]
        armR.orientation = simd_quatf(angle: -0.15, axis: [0, 0, 1])

        // Head with face and hair. Face details are children of the head so
        // they fly together when it pops off.
        let head = ModelEntity(mesh: a.head, materials: [skin])
        head.name = "part_head"
        head.position = [0, 0.70, 0]
        let hairCap = ModelEntity(mesh: a.hairMesh, materials: [hair])
        hairCap.scale = [1, 0.72, 1]
        hairCap.position = [0, 0.055, -0.025]
        head.addChild(hairCap)
        for x in [Float(-0.06), 0.06] {
            let eye = ModelEntity(mesh: a.eyeMesh, materials: [a.eye])
            eye.position = [x, 0.02, 0.145]
            head.addChild(eye)
            let blush = ModelEntity(mesh: a.cheekMesh, materials: [a.cheek])
            blush.scale = [1, 0.6, 0.4]
            blush.position = [x * 1.9, -0.05, 0.125]
            head.addChild(blush)
        }

        for part in [legL, legR, torso, armL, armR, head] {
            character.addChild(part)
        }

        character.components.set(CharacterComponent())
        character.components.set(ObstacleComponent())
        character.components.set(CollisionComponent(shapes: [a.bodyShape.offsetBy(translation: [0, 0.48, 0])]))
        var body = PhysicsBodyComponent(
            shapes: [a.bodyShape.offsetBy(translation: [0, 0.48, 0])],
            mass: 30, mode: .dynamic)
        body.material = .generate(friction: 0.6, restitution: 0.2)
        character.components.set(body)
        return character
    }

    // MARK: Explode

    /// Bursts the character into its body parts: each part is reparented into
    /// worldRoot at its current world pose, given a dynamic body, and flung.
    @MainActor
    static func explode(_ character: Entity, in worldRoot: Entity, intensity: Float) {
        let a = assets
        let origin = character.position(relativeTo: worldRoot)

        let parts = character.children.filter { $0.name.hasPrefix("part_") }
        for part in parts {
            guard let model = part as? ModelEntity else { continue }
            let worldTransform = model.transformMatrix(relativeTo: worldRoot)
            model.removeFromParent()
            model.setTransformMatrix(worldTransform, relativeTo: worldRoot)
            worldRoot.addChild(model)

            let shape: ShapeResource
            let mass: Float
            switch model.name {
            case "part_head": shape = a.headShape; mass = 3
            case "part_torso": shape = a.torsoShape; mass = 6
            case "part_armL", "part_armR": shape = a.armShape; mass = 1.5
            default: shape = a.legShape; mass = 2
            }
            model.components.set(CollisionComponent(shapes: [shape]))
            var body = PhysicsBodyComponent(shapes: [shape], mass: mass, mode: .dynamic)
            body.material = .generate(friction: 0.5, restitution: 0.5)
            model.components.set(body)
            model.components.set(BodyPartComponent(lifetime: 2.2 + Float.random(in: 0...0.8)))

            var away = model.position(relativeTo: worldRoot) - origin
            away.y = 0
            if simd_length(away) < 0.01 { away = [Float.random(in: -1...1), 0, Float.random(in: -1...1)] }
            away = simd_normalize(away)
            away.y = 1.2 + Float.random(in: 0...0.6)
            model.addForce(simd_normalize(away) * (mass * (14 + intensity * 30)), relativeTo: nil)
            model.addTorque(SIMD3<Float>(
                Float.random(in: -4...4), Float.random(in: -4...4), Float.random(in: -4...4)),
                relativeTo: nil)
        }

        character.removeFromParent()
    }
}

// MARK: - CharacterBobSystem
//
// Cute idle: intact characters bob and sway in place until physics moves
// them, mirroring WobbleSystem for props.

struct CharacterBobSystem: System {

    private static let query = EntityQuery(where: .has(CharacterComponent.self))
    @MainActor private static var time: Float = 0

    init(scene: RealityKit.Scene) {}

    func update(context: SceneUpdateContext) {
        Self.time += Float(context.deltaTime)
        for entity in context.scene.performQuery(Self.query) {
            guard let comp = entity.components[CharacterComponent.self] else { continue }
            let bob = sin(Self.time * 2.6 + comp.phase)
            entity.orientation =
                simd_quatf(angle: comp.baseYaw, axis: [0, 1, 0]) *
                simd_quatf(angle: bob * 0.06, axis: [0, 0, 1])
        }
    }
}

// MARK: - BodyPartSystem
//
// Shrinks and removes exploded body parts after their lifetime, so the world
// never fills with limbs.

struct BodyPartSystem: System {

    private static let query = EntityQuery(where: .has(BodyPartComponent.self))

    init(scene: RealityKit.Scene) {}

    func update(context: SceneUpdateContext) {
        let dt = Float(context.deltaTime)
        for entity in context.scene.performQuery(Self.query) {
            guard var part = entity.components[BodyPartComponent.self] else { continue }
            part.age += dt
            entity.components.set(part)

            if part.age >= part.lifetime {
                entity.removeFromParent()
                continue
            }
            // Shrink out over the last 20 percent.
            let t = part.age / part.lifetime
            if t > 0.8 {
                let s = max(0.001, 1 - (t - 0.8) / 0.2)
                entity.scale = SIMD3<Float>(repeating: s)
            }
        }
    }
}
