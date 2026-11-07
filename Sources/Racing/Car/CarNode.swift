import SceneKit
import simd

final class CarNode: SCNNode {

    // Wheel nodes used for rolling and steering animation.
    // For loaded models with merged left+right meshes, leftFront == rightFront.
    let leftFrontWheel:  SCNNode
    let rightFrontWheel: SCNNode
    let leftRearWheel:   SCNNode
    let rightRearWheel:  SCNNode

    private let style: CarStyle

    // MARK: - Init

    init(style: CarStyle = .truckGreen) {
        self.style = style

        if style.isAssetBased, let loaded = CarNode.loadAsset(style: style) {
            leftFrontWheel  = loaded.fl
            rightFrontWheel = loaded.fr
            leftRearWheel   = loaded.rl
            rightRearWheel  = loaded.rr
            super.init()
            addChildNode(loaded.root)
        } else {
            // Procedural fallback (also used for .sport and .rally)
            let wheels = CarNode.buildProceduralWheels()
            leftFrontWheel  = wheels.fl
            rightFrontWheel = wheels.fr
            leftRearWheel   = wheels.rl
            rightRearWheel  = wheels.rr
            super.init()
            switch style {
            case .rally: buildRallyGeometry()
            default:     buildSportGeometry()
            }
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Asset loading

    private struct LoadedCar {
        let root: SCNNode
        let fl: SCNNode
        let fr: SCNNode
        let rl: SCNNode
        let rr: SCNNode
    }

    private static func loadAsset(style: CarStyle) -> LoadedCar? {
        guard let url = Bundle.main.url(forResource: style.rawValue,
                                        withExtension: "usdz",
                                        subdirectory: "Cars") else {
            return nil
        }
        guard let scene = try? SCNScene(url: url, options: nil) else { return nil }

        let wrapper = SCNNode()
        for child in scene.rootNode.childNodes {
            wrapper.addChildNode(child)
        }
        wrapper.eulerAngles = SCNVector3(0, style.modelYRotation, 0)
        let s = style.modelScale
        wrapper.scale       = SCNVector3(s, s, s)
        wrapper.position    = SCNVector3(0, style.modelYOffset, 0)

        let wn = style.wheelNodes
        let fl = wrapper.childNode(withName: wn.frontLeft  ?? "", recursively: true) ?? Self.makeWheel()
        let fr = wrapper.childNode(withName: wn.frontRight ?? "", recursively: true) ?? Self.makeWheel()
        let rl = wrapper.childNode(withName: wn.rearLeft   ?? "", recursively: true) ?? Self.makeWheel()
        let rr = wrapper.childNode(withName: wn.rearRight  ?? "", recursively: true) ?? Self.makeWheel()

        return LoadedCar(root: wrapper, fl: fl, fr: fr, rl: rl, rr: rr)
    }

    // MARK: - Procedural wheels (shared by fallback + procedural variants)

    private static func buildProceduralWheels() -> (fl: SCNNode, fr: SCNNode, rl: SCNNode, rr: SCNNode) {
        let make = { Self.makeWheel() }
        return (make(), make(), make(), make())
    }

    private func placeProceduralWheels(lateral: Float = 1.0,
                                       frontZ: Float = -1.1,
                                       rearZ:  Float =  1.1) {
        let positions: [(node: SCNNode, x: Float, z: Float)] = [
            (leftFrontWheel,  -lateral,  frontZ),
            (rightFrontWheel,  lateral,  frontZ),
            (leftRearWheel,   -lateral,  rearZ),
            (rightRearWheel,   lateral,  rearZ),
        ]
        for (wn, x, z) in positions {
            wn.position = SCNVector3(x, 0, z)
            addChildNode(wn)
        }
    }

    private static func makeWheel(radius: CGFloat = 0.33, width: CGFloat = 0.22,
                                   color: UIColor = UIColor(white: 0.12, alpha: 1)) -> SCNNode {
        let cyl     = SCNCylinder(radius: radius, height: width)
        let mat     = SCNMaterial()
        mat.diffuse.contents   = color
        mat.roughness.contents = 0.9
        cyl.firstMaterial      = mat

        let hub    = SCNCylinder(radius: radius * 0.42, height: width + 0.01)
        let hubMat = SCNMaterial()
        hubMat.diffuse.contents   = UIColor(white: 0.65, alpha: 1)
        hubMat.metalness.contents = 0.6
        hub.firstMaterial         = hubMat

        let node       = SCNNode(geometry: cyl)
        node.eulerAngles = SCNVector3(0, 0, Float.pi * 0.5)
        let hubNode    = SCNNode(geometry: hub)
        hubNode.eulerAngles = node.eulerAngles
        node.addChildNode(hubNode)
        return node
    }

    // MARK: - Sport (original) geometry

    private func buildSportGeometry() {
        let bodyGeo           = SCNBox(width: 1.85, height: 0.85, length: 3.6, chamferRadius: 0.12)
        bodyGeo.firstMaterial = carPaint(UIColor(red: 0.9, green: 0.15, blue: 0.1, alpha: 1))
        let body              = SCNNode(geometry: bodyGeo)
        body.position         = SCNVector3(0, 0.42, 0)
        addChildNode(body)

        let cabinGeo           = SCNBox(width: 1.55, height: 0.6, length: 1.8, chamferRadius: 0.15)
        cabinGeo.firstMaterial = carPaint(UIColor(white: 0.18, alpha: 1))
        let cabin              = SCNNode(geometry: cabinGeo)
        cabin.position         = SCNVector3(0, 1.08, 0.1)
        addChildNode(cabin)

        let screenGeo           = SCNBox(width: 1.4, height: 0.5, length: 0.05, chamferRadius: 0.05)
        screenGeo.firstMaterial = glassMaterial()
        let screen              = SCNNode(geometry: screenGeo)
        screen.position         = SCNVector3(0, 1.0, -0.9)
        addChildNode(screen)

        for zSign: Float in [-1, 1] {
            let bumperGeo           = SCNBox(width: 1.7, height: 0.32, length: 0.14, chamferRadius: 0.05)
            bumperGeo.firstMaterial = carPaint(UIColor(white: 0.18, alpha: 1))
            let bumper              = SCNNode(geometry: bumperGeo)
            bumper.position         = SCNVector3(0, 0.22, zSign * 1.86)
            addChildNode(bumper)
        }

        placeProceduralWheels()
    }

    // MARK: - Rally (90s WRC) geometry

    private func buildRallyGeometry() {
        let bodyColor = UIColor(red: 0.05, green: 0.15, blue: 0.55, alpha: 1)   // Subaru blue
        let accentColor = UIColor(red: 0.85, green: 0.65, blue: 0.0, alpha: 1)  // gold

        // Body — wide, flat, long
        let bodyGeo           = SCNBox(width: 2.1, height: 0.72, length: 4.1, chamferRadius: 0.08)
        bodyGeo.firstMaterial = carPaint(bodyColor)
        let body              = SCNNode(geometry: bodyGeo)
        body.position         = SCNVector3(0, 0.36, 0)
        addChildNode(body)

        // Cabin — squatter, further forward
        let cabinGeo           = SCNBox(width: 1.65, height: 0.52, length: 1.55, chamferRadius: 0.1)
        cabinGeo.firstMaterial = carPaint(UIColor(white: 0.15, alpha: 1))
        let cabin              = SCNNode(geometry: cabinGeo)
        cabin.position         = SCNVector3(0, 0.96, 0.18)
        addChildNode(cabin)

        // Windscreen — raked
        let screenGeo           = SCNBox(width: 1.5, height: 0.44, length: 0.05, chamferRadius: 0.04)
        screenGeo.firstMaterial = glassMaterial()
        let screen              = SCNNode(geometry: screenGeo)
        screen.position         = SCNVector3(0, 0.92, -0.76)
        screen.eulerAngles      = SCNVector3(-0.22, 0, 0)
        addChildNode(screen)

        // Roof scoop
        let scoopGeo           = SCNBox(width: 0.28, height: 0.14, length: 0.65, chamferRadius: 0.04)
        scoopGeo.firstMaterial = carPaint(UIColor(white: 0.12, alpha: 1))
        let scoop              = SCNNode(geometry: scoopGeo)
        scoop.position         = SCNVector3(0, 1.26, 0.28)
        addChildNode(scoop)

        // Rear spoiler
        let spoilerGeo           = SCNBox(width: 1.8, height: 0.12, length: 0.08, chamferRadius: 0.02)
        spoilerGeo.firstMaterial = carPaint(accentColor)
        let spoiler              = SCNNode(geometry: spoilerGeo)
        spoiler.position         = SCNVector3(0, 1.1, 2.08)
        addChildNode(spoiler)

        // Front splitter
        let splitterGeo           = SCNBox(width: 2.0, height: 0.06, length: 0.3, chamferRadius: 0.02)
        splitterGeo.firstMaterial = carPaint(accentColor)
        let splitter              = SCNNode(geometry: splitterGeo)
        splitter.position         = SCNVector3(0, 0.1, -2.2)
        addChildNode(splitter)

        // Front bumper
        let bumperGeo           = SCNBox(width: 2.0, height: 0.3, length: 0.16, chamferRadius: 0.05)
        bumperGeo.firstMaterial = carPaint(UIColor(white: 0.14, alpha: 1))
        let bumper              = SCNNode(geometry: bumperGeo)
        bumper.position         = SCNVector3(0, 0.26, -2.14)
        addChildNode(bumper)

        // Rear bumper
        let rBumperGeo           = SCNBox(width: 2.0, height: 0.3, length: 0.16, chamferRadius: 0.05)
        rBumperGeo.firstMaterial = carPaint(UIColor(white: 0.14, alpha: 1))
        let rBumper              = SCNNode(geometry: rBumperGeo)
        rBumper.position         = SCNVector3(0, 0.26, 2.14)
        addChildNode(rBumper)

        // Flared front wheel arches (simple box overlay)
        for xSign: Float in [-1, 1] {
            let archGeo           = SCNBox(width: 0.32, height: 0.52, length: 1.0, chamferRadius: 0.12)
            archGeo.firstMaterial = carPaint(bodyColor)
            let arch              = SCNNode(geometry: archGeo)
            arch.position         = SCNVector3(xSign * 1.17, 0.28, -1.08)
            addChildNode(arch)

            let rArchGeo          = SCNBox(width: 0.32, height: 0.52, length: 1.0, chamferRadius: 0.12)
            rArchGeo.firstMaterial = carPaint(bodyColor)
            let rArch             = SCNNode(geometry: rArchGeo)
            rArch.position        = SCNVector3(xSign * 1.17, 0.28, 1.08)
            addChildNode(rArch)
        }

        // Rally cars use wider track and bigger tyres
        placeProceduralWheels(lateral: 1.15, frontZ: -1.08, rearZ: 1.08)
        // Replace procedural wheel params with gold rims
        for w in [leftFrontWheel, rightFrontWheel, leftRearWheel, rightRearWheel] {
            if let cyl = w.geometry as? SCNCylinder {
                cyl.radius = 0.35
                cyl.height = 0.28
            }
            if let hub = w.childNodes.first, let hCyl = hub.geometry as? SCNCylinder {
                hCyl.firstMaterial?.diffuse.contents = accentColor
            }
        }
    }

    // MARK: - Wheel animation

    func animateWheels(speed: Float, steer: Float, dt: Float) {
        // Rolling — rotate around local X (the spin axis for all variants).
        // For asset-based models the wheel mesh's natural orientation determines roll axis;
        // X gives correct forward-roll for both Kenney and OGA meshes.
        let rotPerSec: Float = -speed / (2 * Float.pi * 0.33)
        for w in uniqueWheelNodes {
            w.eulerAngles.x += rotPerSec * dt
        }

        // Steering — apply only to front wheels
        let steerAngle: Float = steer * 0.42
        leftFrontWheel.eulerAngles.y  = steerAngle
        // avoid double-applying when both sides share the same node
        if rightFrontWheel !== leftFrontWheel {
            rightFrontWheel.eulerAngles.y = steerAngle
        }
    }

    private var uniqueWheelNodes: [SCNNode] {
        var seen  = Set<ObjectIdentifier>()
        var nodes = [SCNNode]()
        for w in [leftFrontWheel, rightFrontWheel, leftRearWheel, rightRearWheel] {
            let id = ObjectIdentifier(w)
            if seen.insert(id).inserted { nodes.append(w) }
        }
        return nodes
    }

    // MARK: - Materials

    private func carPaint(_ colour: UIColor) -> SCNMaterial {
        let m = SCNMaterial()
        m.diffuse.contents    = colour
        m.specular.contents   = UIColor(white: 0.9, alpha: 1)
        m.roughness.contents  = 0.25
        m.metalness.contents  = 0.4
        return m
    }

    private func glassMaterial() -> SCNMaterial {
        let m = SCNMaterial()
        m.diffuse.contents    = UIColor(red: 0.6, green: 0.8, blue: 0.9, alpha: 0.4)
        m.isDoubleSided       = true
        m.transparencyMode    = .dualLayer
        m.roughness.contents  = 0.1
        return m
    }
}
