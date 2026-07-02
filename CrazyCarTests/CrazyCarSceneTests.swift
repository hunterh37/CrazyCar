import XCTest
import RealityKit
import simd
import ImmersiveTesting
@testable import CrazyCar

@MainActor
final class CrazyCarSceneTests: XCTestCase {

    override func setUp() {
        super.setUp()
        registerCrazyCarECS()
    }

    // MARK: Scene graph

    func testSceneGraphSpec() {
        let root = CarSceneBuilder.build()
        SceneStateSpec("driveScene") {
            Requires(entityNamed: "worldRoot")
            Requires(entityNamed: "carChassis")
            Requires(entityNamed: "cockpit")
            Requires(entityNamed: "wheelPivot")
            Requires(entityNamed: "ground")
            Requires(atLeast: 1, matching: .hasComponent(CarStateComponent.self))
            Requires(atLeast: 10, matching: .hasComponent(ObstacleComponent.self))
        }.assert(against: root)
    }

    func testChassisIsKinematicWithCollision() throws {
        let root = CarSceneBuilder.build()
        let chassis = try XCTUnwrap(root.findEntity(named: "carChassis"))
        let body = try XCTUnwrap(chassis.components[PhysicsBodyComponent.self])
        XCTAssertEqual(body.mode, .kinematic)
        XCTAssertNotNil(chassis.components[CollisionComponent.self])
    }

    func testObstaclesAreDynamicBodies() throws {
        let root = CarSceneBuilder.build()
        let worldRoot = try XCTUnwrap(root.findEntity(named: "worldRoot"))
        var dynamicCount = 0
        for child in worldRoot.children {
            guard child.components.has(ObstacleComponent.self) else { continue }
            let body = try XCTUnwrap(child.components[PhysicsBodyComponent.self])
            XCTAssertEqual(body.mode, .dynamic)
            dynamicCount += 1
        }
        XCTAssertGreaterThanOrEqual(dynamicCount, 10)
    }

    func testWheelIsInteractive() throws {
        let root = CarSceneBuilder.build()
        let wheel = try XCTUnwrap(root.findEntity(named: "wheelPivot"))
        XCTAssertNotNil(wheel.components[InputTargetComponent.self])
        XCTAssertNotNil(wheel.components[CollisionComponent.self])
        XCTAssertNotNil(wheel.components[SteeringWheelComponent.self])
    }

    // MARK: Drive model

    func testThrottleAcceleratesForward() {
        var state = CarStateComponent()
        state.throttle = 1
        for _ in 0..<120 { state = DriveSystem.step(state: state, dt: 1.0 / 60.0) }
        XCTAssertGreaterThan(state.speed, 4)
        XCTAssertLessThan(state.position.z, -2)
        XCTAssertLessThanOrEqual(state.speed, DriveSystem.maxSpeed)
    }

    func testDragStopsTheCar() {
        var state = CarStateComponent(speed: 10)
        for _ in 0..<600 { state = DriveSystem.step(state: state, dt: 1.0 / 60.0) }
        XCTAssertEqual(state.speed, 0)
    }

    func testSteeringTurnsHeadingOnlyWhenMoving() {
        var parked = CarStateComponent()
        parked.steering = 1
        for _ in 0..<60 { parked = DriveSystem.step(state: parked, dt: 1.0 / 60.0) }
        XCTAssertEqual(parked.heading, 0, accuracy: 0.001)

        var moving = CarStateComponent(speed: 8)
        moving.throttle = 1
        moving.steering = 1
        for _ in 0..<60 { moving = DriveSystem.step(state: moving, dt: 1.0 / 60.0) }
        XCTAssertGreaterThan(moving.heading, 0.3)
    }

    func testExplosionPopSpawnsWordFlashAndBurst() throws {
        let root = Entity()
        ExplosionBuilder.spawn(at: [0, 1, -2], in: root, word: "BOOM!", color: .systemYellow, intensity: 1)
        let explosion = try XCTUnwrap(root.findEntity(named: "explosion"))
        XCTAssertNotNil(explosion.components[ExplosionPopComponent.self])
        XCTAssertNotNil(explosion.findEntity(named: "word"))
        XCTAssertNotNil(explosion.findEntity(named: "flash"))
        XCTAssertNotNil(explosion.findEntity(named: "burst"))
    }
}
