import RealityKit
import UIKit
import simd

// MARK: - CarSceneBuilder
//
// Builds a cute low poly outdoor world from primitives, headless-friendly:
//
//   root
//   ├── cockpit          fixed at the app origin, the user sits inside
//   │   └── wheelPivot   steering wheel, drag to steer
//   └── worldRoot        CarStateComponent + PhysicsSimulationComponent
//       ├── ground       static physics, grass
//       ├── road         curved road ribbon built from flat segments
//       ├── carChassis   kinematic collider tracking the car pose
//       ├── obstacles    dynamic cones, crates, barrels along the road
//       └── scenery      trees, rocks, bushes, flowers, mushrooms, clouds
//
// Performance notes (ECS friendly):
//  - Every mesh and material is generated exactly once in SharedAssets and
//    reused by all instances, so RealityKit batches draw calls.
//  - Scenery is purely visual (no physics) except trees and rocks, which get
//    cheap static convex colliders.
//  - Road segments and decor have no CollisionComponent at all.

enum CarSceneBuilder {

    struct Config {
        var roadObstacles: Int = 26
        var characterCount: Int = 16
        var treeCount: Int = 60
        var bushCount: Int = 40
        var flowerCount: Int = 80
        var rockCount: Int = 18
        var mushroomCount: Int = 24
        var cloudCount: Int = 10
        var worldRadius: Float = 55
    }

    // MARK: Road path
    //
    // A closed wobbly loop: radius swells and shrinks around the circle so the
    // road curves left and right. point(t) with t in 0..<1.

    enum RoadPath {
        static let baseRadius: Float = 22
        static let wobble: Float = 7
        static let width: Float = 5

        static func point(_ t: Float) -> SIMD3<Float> {
            let a = t * .pi * 2
            let r = baseRadius + wobble * sin(a * 3)
            return [cos(a) * r, 0, sin(a) * r - 6]
        }

        static func tangent(_ t: Float) -> SIMD3<Float> {
            let ahead = point(t + 0.002)
            let here = point(t)
            return simd_normalize(ahead - here)
        }

        static func distanceToRoad(_ p: SIMD3<Float>, samples: Int = 96) -> Float {
            var best = Float.greatestFiniteMagnitude
            for i in 0..<samples {
                let q = point(Float(i) / Float(samples))
                best = min(best, simd_length(SIMD3<Float>(p.x - q.x, 0, p.z - q.z)))
            }
            return best
        }
    }

    // MARK: Shared assets

    @MainActor
    struct SharedAssets {
        // Materials
        let grass = SimpleMaterial(color: UIColor(red: 0.55, green: 0.82, blue: 0.45, alpha: 1), roughness: 1, isMetallic: false)
        let asphalt = SimpleMaterial(color: UIColor(red: 0.38, green: 0.39, blue: 0.46, alpha: 1), roughness: 1, isMetallic: false)
        let dash = SimpleMaterial(color: UIColor(red: 0.98, green: 0.96, blue: 0.86, alpha: 1), roughness: 1, isMetallic: false)
        let trunk = SimpleMaterial(color: UIColor(red: 0.55, green: 0.38, blue: 0.24, alpha: 1), roughness: 1, isMetallic: false)
        let leafA = SimpleMaterial(color: UIColor(red: 0.28, green: 0.65, blue: 0.35, alpha: 1), roughness: 1, isMetallic: false)
        let leafB = SimpleMaterial(color: UIColor(red: 0.40, green: 0.75, blue: 0.38, alpha: 1), roughness: 1, isMetallic: false)
        let leafC = SimpleMaterial(color: UIColor(red: 0.20, green: 0.55, blue: 0.42, alpha: 1), roughness: 1, isMetallic: false)
        let rock = SimpleMaterial(color: UIColor(red: 0.68, green: 0.70, blue: 0.74, alpha: 1), roughness: 1, isMetallic: false)
        let cloud = SimpleMaterial(color: UIColor(red: 0.99, green: 0.99, blue: 1.0, alpha: 1), roughness: 1, isMetallic: false)
        let mushroomCap = SimpleMaterial(color: UIColor(red: 0.95, green: 0.35, blue: 0.35, alpha: 1), roughness: 1, isMetallic: false)
        let mushroomStem = SimpleMaterial(color: UIColor(red: 0.98, green: 0.94, blue: 0.86, alpha: 1), roughness: 1, isMetallic: false)
        let petals: [SimpleMaterial] = [
            SimpleMaterial(color: UIColor(red: 1.0, green: 0.62, blue: 0.75, alpha: 1), roughness: 1, isMetallic: false),
            SimpleMaterial(color: UIColor(red: 1.0, green: 0.85, blue: 0.40, alpha: 1), roughness: 1, isMetallic: false),
            SimpleMaterial(color: UIColor(red: 0.70, green: 0.60, blue: 0.95, alpha: 1), roughness: 1, isMetallic: false),
            SimpleMaterial(color: UIColor(red: 0.55, green: 0.85, blue: 0.95, alpha: 1), roughness: 1, isMetallic: false)
        ]
        let cone = SimpleMaterial(color: UIColor(red: 1.0, green: 0.58, blue: 0.25, alpha: 1), roughness: 1, isMetallic: false)
        let crate = SimpleMaterial(color: UIColor(red: 0.78, green: 0.58, blue: 0.34, alpha: 1), roughness: 1, isMetallic: false)
        let barrel = SimpleMaterial(color: UIColor(red: 0.90, green: 0.30, blue: 0.40, alpha: 1), roughness: 0.8, isMetallic: false)

        // Meshes
        let unitBox = MeshResource.generateBox(size: 1)
        let roundedBox = MeshResource.generateBox(size: 1, cornerRadius: 0.08)
        let sphere = MeshResource.generateSphere(radius: 0.5)
        let coneTall = MeshResource.generateCone(height: 1, radius: 0.5)
        let cylinder = MeshResource.generateCylinder(height: 1, radius: 0.5)

        // Obstacle meshes at native size so colliders match
        let coneMesh = MeshResource.generateCone(height: 0.7, radius: 0.28)
        let crateMesh = MeshResource.generateBox(size: 0.6, cornerRadius: 0.03)
        let barrelMesh = MeshResource.generateCylinder(height: 0.85, radius: 0.3)
        let coneShape = ShapeResource.generateConvex(from: MeshResource.generateCone(height: 0.7, radius: 0.28))
        let crateShape = ShapeResource.generateBox(size: [0.6, 0.6, 0.6])
        let barrelShape = ShapeResource.generateConvex(from: MeshResource.generateCylinder(height: 0.85, radius: 0.3))
    }

    @MainActor static let assets = SharedAssets()

    // MARK: Build

    @MainActor
    static func build(config: Config = Config()) -> Entity {
        let root = Entity()
        root.name = "root"

        addLighting(to: root)

        let cockpit = CockpitBuilder.build()
        root.addChild(cockpit)

        let worldRoot = Entity()
        worldRoot.name = "worldRoot"
        worldRoot.components.set(CarStateComponent())
        worldRoot.components.set(PhysicsSimulationComponent())
        root.addChild(worldRoot)

        worldRoot.addChild(buildGround(config: config))
        worldRoot.addChild(buildRoad())
        worldRoot.addChild(buildChassis())
        addObstacles(to: worldRoot, config: config)
        addCharacters(to: worldRoot, config: config)
        addScenery(to: worldRoot, config: config)

        return root
    }

    // MARK: Lighting
    //
    // A full immersive space provides no environment lighting, so PBR/Simple
    // materials render black. Generate a bright warm IBL from a solid color
    // for ambient fill, plus a key directional light for shape and shadows.

    @MainActor
    private static func addLighting(to root: Entity) {
        let ibl = Entity()
        ibl.name = "ibl"
        if let resource = try? EnvironmentResource.generate(
            fromEquirectangular: solidColorCGImage(
                UIColor(red: 0.82, green: 0.88, blue: 0.98, alpha: 1))) {
            var iblComp = ImageBasedLightComponent(source: .single(resource))
            iblComp.intensityExponent = 1.25
            ibl.components.set(iblComp)
            ibl.components.set(ImageBasedLightReceiverComponent(imageBasedLight: ibl))
        }
        root.addChild(ibl)

        let key = DirectionalLight()
        key.name = "keyLight"
        key.light.intensity = 6500
        key.light.color = UIColor(red: 1.0, green: 0.96, blue: 0.88, alpha: 1)
        key.shadow = DirectionalLightComponent.Shadow(maximumDistance: 50, depthBias: 2)
        key.orientation =
            simd_quatf(angle: -.pi / 3, axis: [1, 0, 0]) *
            simd_quatf(angle: .pi / 5, axis: [0, 1, 0])
        root.addChild(key)
    }

    private static func solidColorCGImage(_ color: UIColor) -> CGImage {
        let width = 4, height = 2
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(color.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()!
    }

    // MARK: Ground

    @MainActor
    private static func buildGround(config: Config) -> Entity {
        let size: Float = config.worldRadius * 2 + 40
        let ground = ModelEntity(mesh: assets.unitBox, materials: [assets.grass])
        ground.name = "ground"
        ground.scale = [size, 0.1, size]
        ground.position = [0, -0.05, 0]
        let shape = ShapeResource.generateBox(width: size, height: 0.1, depth: size)
        ground.components.set(CollisionComponent(shapes: [shape]))
        ground.components.set(PhysicsBodyComponent(shapes: [shape], mass: 0, mode: .static))

        // Soft low poly hills around the rim, half buried spheres.
        var seed: UInt64 = 0xB0BA
        func rnd() -> Float {
            seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17
            return Float(seed % 10_000) / 10_000
        }
        let hillHolder = Entity()
        hillHolder.name = "hills"
        for i in 0..<14 {
            let angle = Float(i) / 14 * .pi * 2 + rnd() * 0.4
            let r = config.worldRadius + 6 + rnd() * 10
            let hill = ModelEntity(mesh: assets.sphere, materials: [rnd() > 0.5 ? assets.leafB : assets.grass])
            let s = 10 + rnd() * 16
            hill.scale = [s, s * 0.45, s]
            // Ground is 1x0.1x1 scaled, so children live in its local space.
            hill.position = [cos(angle) * r / size, 0.5, sin(angle) * r / size]
            hill.scale /= size
            hillHolder.addChild(hill)
        }
        ground.addChild(hillHolder)
        return ground
    }

    // MARK: Road
    //
    // Flat overlapping segments follow the loop, each yawed to the local
    // tangent, so the ribbon reads as one smooth curved road. Dashes ride a
    // touch higher down the center line. Visual only, zero physics.

    @MainActor
    private static func buildRoad() -> Entity {
        let road = Entity()
        road.name = "road"
        let segments = 140
        for i in 0..<segments {
            let t = Float(i) / Float(segments)
            let p = RoadPath.point(t)
            let tan = RoadPath.tangent(t)
            let yaw = atan2(-tan.x, -tan.z)
            let next = RoadPath.point(Float(i + 1) / Float(segments))
            let length = simd_length(next - p) * 1.35

            let slab = ModelEntity(mesh: assets.unitBox, materials: [assets.asphalt])
            slab.scale = [RoadPath.width, 0.04, length]
            slab.position = [p.x, 0.03, p.z]
            slab.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0])
            road.addChild(slab)

            if i % 3 == 0 {
                let dashEntity = ModelEntity(mesh: assets.unitBox, materials: [assets.dash])
                dashEntity.scale = [0.22, 0.045, 0.9]
                dashEntity.position = [p.x, 0.055, p.z]
                dashEntity.orientation = slab.orientation
                road.addChild(dashEntity)
            }
        }
        return road
    }

    // MARK: Chassis collider

    @MainActor
    private static func buildChassis() -> Entity {
        let chassis = Entity()
        chassis.name = "carChassis"
        chassis.components.set(CarChassisComponent())
        let shape = ShapeResource.generateBox(width: 1.7, height: 1.1, depth: 3.4)
        chassis.components.set(CollisionComponent(shapes: [shape]))
        var body = PhysicsBodyComponent(shapes: [shape], mass: 900, mode: .kinematic)
        body.material = .generate(friction: 0.4, restitution: 0.6)
        chassis.components.set(body)
        chassis.position = [0, 0.55, 0]
        return chassis
    }

    // MARK: Obstacles
    //
    // Smashable props scattered along the road edges so driving the loop is
    // a slalom. All dynamic bodies, direct children of worldRoot.

    @MainActor
    private static func addObstacles(to worldRoot: Entity, config: Config) {
        var seed: UInt64 = 0xC0FFEE
        func rnd() -> Float {
            seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17
            return Float(seed % 10_000) / 10_000
        }

        for i in 0..<config.roadObstacles {
            let t = Float(i) / Float(config.roadObstacles) + rnd() * 0.02
            let p = RoadPath.point(t)
            let tan = RoadPath.tangent(t)
            let side = SIMD3<Float>(-tan.z, 0, tan.x)
            let offset = (rnd() - 0.5) * RoadPath.width * 1.6
            let pos = p + side * offset

            let obstacle: ModelEntity
            switch Int(rnd() * 3) {
            case 0: obstacle = makeCone()
            case 1: obstacle = makeCrate()
            default: obstacle = makeBarrel()
            }
            obstacle.position = [pos.x, obstacle.position.y, pos.z]
            obstacle.components.set(WobbleComponent(phase: rnd() * .pi * 2, amplitude: 0.03 + rnd() * 0.04))
            worldRoot.addChild(obstacle)
        }
    }

    // MARK: Characters
    //
    // Cute humanoids loitering along the road edges, facing the road so the
    // driver sees their faces. Dynamic bodies, direct children of worldRoot.

    @MainActor
    private static func addCharacters(to worldRoot: Entity, config: Config) {
        var seed: UInt64 = 0xD00D
        func rnd() -> Float {
            seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17
            return Float(seed % 10_000) / 10_000
        }

        for i in 0..<config.characterCount {
            let t = Float(i) / Float(config.characterCount) + 0.02 + rnd() * 0.03
            let p = RoadPath.point(t)
            let tan = RoadPath.tangent(t)
            let side = SIMD3<Float>(-tan.z, 0, tan.x)
            // Half stand on the shoulder, half wander onto the road.
            let onRoad = rnd() > 0.5
            let offset = onRoad
                ? (rnd() - 0.5) * RoadPath.width * 0.9
                : (RoadPath.width * 0.75 + rnd() * 1.5) * (rnd() > 0.5 ? 1 : -1)
            let pos = p + side * offset

            let character = CharacterBuilder.make(seed: rnd())
            character.position = [pos.x, 0, pos.z]
            let yawToRoad = atan2(p.x - pos.x, p.z - pos.z) + .pi
            if var comp = character.components[CharacterComponent.self] {
                comp.baseYaw = onRoad ? rnd() * .pi * 2 : yawToRoad
                comp.phase = rnd() * .pi * 2
                character.components.set(comp)
                character.orientation = simd_quatf(angle: comp.baseYaw, axis: [0, 1, 0])
            }
            worldRoot.addChild(character)
        }
    }

    @MainActor
    static func makeCone() -> ModelEntity {
        let cone = ModelEntity(mesh: assets.coneMesh, materials: [assets.cone])
        cone.name = "cone"
        cone.position.y = 0.35
        finishObstacle(cone, shape: assets.coneShape, mass: 3)
        return cone
    }

    @MainActor
    static func makeCrate() -> ModelEntity {
        let crate = ModelEntity(mesh: assets.crateMesh, materials: [assets.crate])
        crate.name = "crate"
        crate.position.y = 0.3
        finishObstacle(crate, shape: assets.crateShape, mass: 8)
        return crate
    }

    @MainActor
    static func makeBarrel() -> ModelEntity {
        let barrel = ModelEntity(mesh: assets.barrelMesh, materials: [assets.barrel])
        barrel.name = "barrel"
        barrel.position.y = 0.425
        finishObstacle(barrel, shape: assets.barrelShape, mass: 12)
        return barrel
    }

    @MainActor
    private static func finishObstacle(_ entity: ModelEntity, shape: ShapeResource, mass: Float) {
        entity.components.set(ObstacleComponent())
        entity.components.set(CollisionComponent(shapes: [shape]))
        var body = PhysicsBodyComponent(shapes: [shape], mass: mass, mode: .dynamic)
        body.material = .generate(friction: 0.5, restitution: 0.55)
        entity.components.set(body)
    }

    // MARK: Scenery
    //
    // Trees, rocks, bushes, flowers, mushrooms on the grass (kept off the
    // road), plus drifting clouds overhead. One holder entity keeps the
    // worldRoot child list tidy for physics queries.

    @MainActor
    private static func addScenery(to worldRoot: Entity, config: Config) {
        var seed: UInt64 = 0xFAB1E5
        func rnd() -> Float {
            seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17
            return Float(seed % 10_000) / 10_000
        }
        func groundSpot(minRoadDistance: Float) -> SIMD3<Float>? {
            for _ in 0..<12 {
                let a = rnd() * .pi * 2
                let r = 4 + rnd() * config.worldRadius
                let p = SIMD3<Float>(cos(a) * r, 0, sin(a) * r - 6)
                if RoadPath.distanceToRoad(p) > minRoadDistance { return p }
            }
            return nil
        }

        let scenery = Entity()
        scenery.name = "scenery"
        worldRoot.addChild(scenery)

        for _ in 0..<config.treeCount {
            guard let p = groundSpot(minRoadDistance: RoadPath.width) else { continue }
            let tree = makeTree(variant: rnd(), scale: 0.8 + rnd() * 1.1)
            tree.position = p
            tree.orientation = simd_quatf(angle: rnd() * .pi * 2, axis: [0, 1, 0])
            scenery.addChild(tree)
        }
        for _ in 0..<config.rockCount {
            guard let p = groundSpot(minRoadDistance: RoadPath.width * 0.9) else { continue }
            let rock = makeRock(scale: 0.5 + rnd() * 1.2, squash: 0.5 + rnd() * 0.4)
            rock.position = p
            rock.orientation = simd_quatf(angle: rnd() * .pi * 2, axis: [0, 1, 0])
            scenery.addChild(rock)
        }
        for _ in 0..<config.bushCount {
            guard let p = groundSpot(minRoadDistance: RoadPath.width * 0.8) else { continue }
            let bush = makeBush(scale: 0.4 + rnd() * 0.7, variant: rnd())
            bush.position = p
            scenery.addChild(bush)
        }
        for _ in 0..<config.flowerCount {
            guard let p = groundSpot(minRoadDistance: RoadPath.width * 0.7) else { continue }
            let flower = makeFlower(colorIndex: Int(rnd() * 4))
            flower.position = p
            scenery.addChild(flower)
        }
        for _ in 0..<config.mushroomCount {
            guard let p = groundSpot(minRoadDistance: RoadPath.width * 0.8) else { continue }
            let mushroom = makeMushroom(scale: 0.5 + rnd() * 0.9)
            mushroom.position = p
            scenery.addChild(mushroom)
        }
        for _ in 0..<config.cloudCount {
            let cloudEntity = makeCloud(rnd: rnd)
            let a = rnd() * .pi * 2
            let r = 10 + rnd() * config.worldRadius
            cloudEntity.position = [cos(a) * r, 9 + rnd() * 6, sin(a) * r - 6]
            scenery.addChild(cloudEntity)
        }
    }

    /// Layered cone canopy on a cylinder trunk. Static collider on the trunk
    /// only, so the car bonks trees but the canopy costs nothing.
    @MainActor
    private static func makeTree(variant: Float, scale: Float) -> Entity {
        let tree = Entity()
        tree.name = "tree"

        let trunkHeight: Float = 1.0 * scale
        let trunkEntity = ModelEntity(mesh: assets.cylinder, materials: [assets.trunk])
        trunkEntity.scale = [0.3 * scale, trunkHeight, 0.3 * scale]
        trunkEntity.position.y = trunkHeight / 2
        tree.addChild(trunkEntity)

        let leaf = variant < 0.33 ? assets.leafA : (variant < 0.66 ? assets.leafB : assets.leafC)
        if variant < 0.5 {
            // Pine: three stacked cones.
            for (i, s) in [Float(1.5), 1.15, 0.8].enumerated() {
                let layer = ModelEntity(mesh: assets.coneTall, materials: [leaf])
                layer.scale = [s * scale, 1.0 * scale, s * scale]
                layer.position.y = trunkHeight + (0.45 + Float(i) * 0.6) * scale
                tree.addChild(layer)
            }
        } else {
            // Puff: two offset spheres.
            let puff = ModelEntity(mesh: assets.sphere, materials: [leaf])
            puff.scale = SIMD3<Float>(repeating: 1.7 * scale)
            puff.position.y = trunkHeight + 0.7 * scale
            tree.addChild(puff)
            let puff2 = ModelEntity(mesh: assets.sphere, materials: [leaf])
            puff2.scale = SIMD3<Float>(repeating: 1.1 * scale)
            puff2.position = [0.5 * scale, trunkHeight + 1.1 * scale, 0.2 * scale]
            tree.addChild(puff2)
        }

        let shape = ShapeResource.generateBox(width: 0.35 * scale, height: trunkHeight * 2, depth: 0.35 * scale)
        tree.components.set(CollisionComponent(shapes: [shape]))
        tree.components.set(PhysicsBodyComponent(shapes: [shape], mass: 0, mode: .static))
        return tree
    }

    @MainActor
    private static func makeRock(scale: Float, squash: Float) -> Entity {
        let rock = ModelEntity(mesh: assets.roundedBox, materials: [assets.rock])
        rock.name = "rock"
        rock.scale = [scale, scale * squash, scale * 0.85]
        rock.position.y = scale * squash * 0.35
        let shape = ShapeResource.generateBox(size: [scale, scale * squash, scale * 0.85])
        rock.components.set(CollisionComponent(shapes: [shape]))
        rock.components.set(PhysicsBodyComponent(shapes: [shape], mass: 0, mode: .static))
        return rock
    }

    @MainActor
    private static func makeBush(scale: Float, variant: Float) -> Entity {
        let bush = ModelEntity(
            mesh: assets.sphere,
            materials: [variant > 0.5 ? assets.leafB : assets.leafC])
        bush.name = "bush"
        bush.scale = [scale, scale * 0.75, scale]
        bush.position.y = scale * 0.25
        return bush
    }

    @MainActor
    private static func makeFlower(colorIndex: Int) -> Entity {
        let flower = Entity()
        flower.name = "flower"
        let stem = ModelEntity(mesh: assets.cylinder, materials: [assets.leafB])
        stem.scale = [0.03, 0.25, 0.03]
        stem.position.y = 0.125
        flower.addChild(stem)
        let head = ModelEntity(mesh: assets.sphere, materials: [assets.petals[colorIndex % assets.petals.count]])
        head.scale = SIMD3<Float>(repeating: 0.14)
        head.position.y = 0.28
        flower.addChild(head)
        return flower
    }

    @MainActor
    private static func makeMushroom(scale: Float) -> Entity {
        let mushroom = Entity()
        mushroom.name = "mushroom"
        let stem = ModelEntity(mesh: assets.cylinder, materials: [assets.mushroomStem])
        stem.scale = [0.14 * scale, 0.3 * scale, 0.14 * scale]
        stem.position.y = 0.15 * scale
        mushroom.addChild(stem)
        let cap = ModelEntity(mesh: assets.sphere, materials: [assets.mushroomCap])
        cap.scale = [0.42 * scale, 0.26 * scale, 0.42 * scale]
        cap.position.y = 0.32 * scale
        mushroom.addChild(cap)
        return mushroom
    }

    @MainActor
    private static func makeCloud(rnd: () -> Float) -> Entity {
        let cloud = Entity()
        cloud.name = "cloud"
        let blobs = 3 + Int(rnd() * 3)
        for _ in 0..<blobs {
            let blob = ModelEntity(mesh: assets.sphere, materials: [assets.cloud])
            let s = 1.6 + rnd() * 2.4
            blob.scale = [s, s * 0.6, s * 0.8]
            blob.position = [(rnd() - 0.5) * 4.5, (rnd() - 0.5) * 0.8, (rnd() - 0.5) * 2]
            cloud.addChild(blob)
        }
        return cloud
    }
}
