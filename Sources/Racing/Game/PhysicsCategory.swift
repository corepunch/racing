import SceneKit

enum PhysicsCategory {
    static let none:  Int = 0
    static let car:   Int = 1 << 0
    static let track: Int = 1 << 1
    static let terrain: Int = 1 << 2
    static let obstacle: Int = 1 << 3

    /// SceneKit query geometry for the static scenery; the car uses swept tests.
    static func addStaticMesh(to node: SCNNode, category: Int) {
        guard let geometry = node.geometry else { return }
        let shape = SCNPhysicsShape(geometry: geometry, options: [.type: SCNPhysicsShape.ShapeType.concavePolyhedron])
        let body = SCNPhysicsBody(type: .static, shape: shape)
        body.categoryBitMask = category
        body.collisionBitMask = car
        node.physicsBody = body
    }
}
