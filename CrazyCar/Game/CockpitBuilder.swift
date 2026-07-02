import RealityKit
import UIKit
import simd

// MARK: - CockpitBuilder
//
// The car interior the user sits in, built entirely from primitives and fixed
// at the app origin. The steering wheel pivot carries SteeringWheelComponent,
// an InputTargetComponent, and a collision shape so a drag gesture can spin it.

enum CockpitBuilder {

    @MainActor
    static func build() -> Entity {
        let cockpit = Entity()
        cockpit.name = "cockpit"

        let bodyMat  = SimpleMaterial(color: UIColor(red: 0.85, green: 0.10, blue: 0.15, alpha: 1), isMetallic: true)
        let darkMat  = SimpleMaterial(color: UIColor(white: 0.12, alpha: 1), isMetallic: false)
        let seatMat  = SimpleMaterial(color: UIColor(red: 0.15, green: 0.15, blue: 0.35, alpha: 1), isMetallic: false)
        let chromeMat = SimpleMaterial(color: UIColor(white: 0.8, alpha: 1), isMetallic: true)

        // Floor pan.
        let floor = ModelEntity(mesh: .generateBox(width: 1.5, height: 0.06, depth: 2.6), materials: [darkMat])
        floor.position = [0, 0.03, -0.2]
        cockpit.addChild(floor)

        // Seat: base + backrest under and behind the user.
        let seatBase = ModelEntity(mesh: .generateBox(width: 0.55, height: 0.12, depth: 0.55, cornerRadius: 0.04), materials: [seatMat])
        seatBase.position = [0, 0.45, 0.1]
        cockpit.addChild(seatBase)
        let seatBack = ModelEntity(mesh: .generateBox(width: 0.55, height: 0.7, depth: 0.12, cornerRadius: 0.04), materials: [seatMat])
        seatBack.position = [0, 0.85, 0.38]
        cockpit.addChild(seatBack)

        // Dashboard.
        let dash = ModelEntity(mesh: .generateBox(width: 1.4, height: 0.28, depth: 0.35, cornerRadius: 0.05), materials: [darkMat])
        dash.name = "dashboard"
        dash.position = [0, 0.92, -0.75]
        cockpit.addChild(dash)

        // Hood sloping away in front.
        let hood = ModelEntity(mesh: .generateBox(width: 1.45, height: 0.08, depth: 1.1), materials: [bodyMat])
        hood.position = [0, 0.82, -1.5]
        hood.orientation = simd_quatf(angle: 0.12, axis: [1, 0, 0])
        cockpit.addChild(hood)

        // Doors left and right.
        for x in [Float(-0.78), 0.78] {
            let door = ModelEntity(mesh: .generateBox(width: 0.08, height: 0.75, depth: 2.2, cornerRadius: 0.04), materials: [bodyMat])
            door.position = [x, 0.6, -0.2]
            cockpit.addChild(door)
        }

        // Windshield frame: two A-pillars and a top bar.
        for x in [Float(-0.72), 0.72] {
            let pillar = ModelEntity(mesh: .generateBox(width: 0.06, height: 0.85, depth: 0.06), materials: [chromeMat])
            pillar.position = [x, 1.4, -0.85]
            pillar.orientation = simd_quatf(angle: 0.28, axis: [1, 0, 0])
            cockpit.addChild(pillar)
        }
        let topBar = ModelEntity(mesh: .generateBox(width: 1.5, height: 0.06, depth: 0.06), materials: [chromeMat])
        topBar.position = [0, 1.8, -0.97]
        cockpit.addChild(topBar)

        // Steering column + wheel.
        let column = ModelEntity(mesh: .generateCylinder(height: 0.35, radius: 0.03), materials: [chromeMat])
        column.position = [0, 0.98, -0.62]
        column.orientation = simd_quatf(angle: .pi / 2 - 0.45, axis: [1, 0, 0])
        cockpit.addChild(column)
        cockpit.addChild(buildWheel())
        cockpit.addChild(buildGasPedal())

        return cockpit
    }

    /// Wheel pivot at the driver's hands, tilted like a real column.
    /// The disc, hub, and spokes are children so the whole assembly spins on
    /// the pivot's local Z.
    @MainActor
    static func buildWheel() -> Entity {
        let pivot = Entity()
        pivot.name = "wheelPivot"
        pivot.position = [0, 1.05, -0.5]
        pivot.orientation = simd_quatf(angle: -0.45, axis: [1, 0, 0])
        pivot.components.set(SteeringWheelComponent())
        pivot.components.set(InputTargetComponent())
        pivot.components.set(CollisionComponent(
            shapes: [.generateBox(width: 0.42, height: 0.42, depth: 0.1)],
            mode: .trigger
        ))

        let rimMat = SimpleMaterial(color: UIColor(white: 0.08, alpha: 1), isMetallic: false)
        let hubMat = SimpleMaterial(color: .systemRed, isMetallic: true)

        // Rim: custom-drawn circle primitive, a single procedural torus mesh.
        let radius: Float = 0.18
        let rim = ModelEntity(
            mesh: torusMesh(ringRadius: radius, tubeRadius: 0.022, ringSegments: 48, tubeSegments: 16),
            materials: [rimMat]
        )
        rim.name = "wheelRim"
        pivot.addChild(rim)

        // Hub.
        let hub = ModelEntity(mesh: .generateCylinder(height: 0.05, radius: 0.05), materials: [hubMat])
        hub.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
        pivot.addChild(hub)

        // Three spokes.
        for a in [Float(0), 2.1, 4.2] {
            let spoke = ModelEntity(mesh: .generateBox(width: 0.03, height: radius, depth: 0.02), materials: [rimMat])
            spoke.position = [cos(a + .pi / 2) * radius / 2, sin(a + .pi / 2) * radius / 2, 0]
            spoke.orientation = simd_quatf(angle: a, axis: [0, 0, 1])
            pivot.addChild(spoke)
        }

        return pivot
    }

    /// Gas pedal pivot to the right of the steering wheel. The pedal plate
    /// hangs from a hinge at its top edge so a press rotates it forward.
    @MainActor
    static func buildGasPedal() -> Entity {
        let pivot = Entity()
        pivot.name = "gasPedalPivot"
        pivot.position = [0.28, 0.95, -0.55]
        pivot.orientation = simd_quatf(angle: -0.35, axis: [1, 0, 0])
        pivot.components.set(GasPedalComponent())
        pivot.components.set(InputTargetComponent())
        pivot.components.set(CollisionComponent(
            shapes: [.generateBox(width: 0.14, height: 0.2, depth: 0.1)],
            mode: .trigger
        ))

        let pedalMat = SimpleMaterial(color: UIColor(white: 0.1, alpha: 1), isMetallic: true)
        let gripMat  = SimpleMaterial(color: UIColor(white: 0.3, alpha: 1), isMetallic: false)
        let armMat   = SimpleMaterial(color: UIColor(white: 0.7, alpha: 1), isMetallic: true)

        // Pedal plate, hanging below the hinge.
        let plate = ModelEntity(mesh: .generateBox(width: 0.11, height: 0.17, depth: 0.02, cornerRadius: 0.015), materials: [pedalMat])
        plate.name = "gasPedalPlate"
        plate.position = [0, -0.085, 0]
        pivot.addChild(plate)

        // Grip ridges on the plate face.
        for i in 0..<4 {
            let ridge = ModelEntity(mesh: .generateBox(width: 0.09, height: 0.012, depth: 0.006), materials: [gripMat])
            ridge.position = [0, -0.03 - Float(i) * 0.036, 0.013]
            pivot.addChild(ridge)
        }

        // Arm connecting the hinge back toward the firewall.
        let arm = ModelEntity(mesh: .generateCylinder(height: 0.16, radius: 0.012), materials: [armMat])
        arm.position = [0, 0.02, -0.07]
        arm.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
        pivot.addChild(arm)

        return pivot
    }

    /// Procedural torus mesh: a circle of `ringSegments` around local Z, tube
    /// of `tubeSegments`, with smooth normals.
    static func torusMesh(ringRadius: Float, tubeRadius: Float, ringSegments: Int, tubeSegments: Int) -> MeshResource {
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        positions.reserveCapacity(ringSegments * tubeSegments)
        normals.reserveCapacity(ringSegments * tubeSegments)
        indices.reserveCapacity(ringSegments * tubeSegments * 6)

        for i in 0..<ringSegments {
            let u = Float(i) / Float(ringSegments) * 2 * .pi
            let ringCenter = SIMD3<Float>(cos(u) * ringRadius, sin(u) * ringRadius, 0)
            let outward = SIMD3<Float>(cos(u), sin(u), 0)
            for j in 0..<tubeSegments {
                let v = Float(j) / Float(tubeSegments) * 2 * .pi
                let normal = outward * cos(v) + SIMD3<Float>(0, 0, 1) * sin(v)
                positions.append(ringCenter + normal * tubeRadius)
                normals.append(normal)

                let iNext = (i + 1) % ringSegments
                let jNext = (j + 1) % tubeSegments
                let a = UInt32(i * tubeSegments + j)
                let b = UInt32(iNext * tubeSegments + j)
                let c = UInt32(iNext * tubeSegments + jNext)
                let d = UInt32(i * tubeSegments + jNext)
                indices.append(contentsOf: [a, b, c, a, c, d])
            }
        }

        var descriptor = MeshDescriptor(name: "torus")
        descriptor.positions = MeshBuffer(positions)
        descriptor.normals = MeshBuffer(normals)
        descriptor.primitives = .triangles(indices)
        // swiftlint:disable:next force_try
        return try! MeshResource.generate(from: [descriptor])
    }
}
