import SpriteKit
import simd

/// SpriteKit HUD scene overlaid on the SCNView.
/// Displays speed, lap time, surface type, drift warning, and minimap.
final class HUDScene: SKScene {

    // Nodes
    private var speedLabel: SKLabelNode!
    private var speedUnit: SKLabelNode!
    private var lapLabel: SKLabelNode!
    private var lapTimeLabel: SKLabelNode!
    private var surfaceLabel: SKLabelNode!
    private var driftLabel: SKLabelNode!
    private var minimapBG: SKShapeNode!
    private var minimapTrackPath: SKShapeNode!
    private var minimapCar: SKShapeNode!

    // Minimap data
    private var trackPoints: [CGPoint] = []
    private var minimapFrame: CGRect = .zero

    // Reference to game scene for polling
    weak var gameScene: GameScene?

    // MARK: - Init

    override init(size: CGSize) {
        super.init(size: size)
        isUserInteractionEnabled = false
        buildHUD(size: size)
    }

    required init?(coder aDecoder: NSCoder) { fatalError() }

    // MARK: - Build

    private func buildHUD(size: CGSize) {
        let s = size

        // ── Speedometer ───────────────────────────────────────────────────────
        let speedo = SKNode()
        speedo.position = CGPoint(x: 90, y: 70)
        addChild(speedo)

        // Background arc
        let arcBG = arcNode(radius: 72, start: -.pi * 0.78, end: .pi * (-0.22), color: UIColor(white: 0, alpha: 0.4), width: 8)
        speedo.addChild(arcBG)

        speedLabel = label("0", size: 46, weight: .bold)
        speedLabel.verticalAlignmentMode = .center
        speedLabel.horizontalAlignmentMode = .center
        speedo.addChild(speedLabel)

        speedUnit = label("km/h", size: 14, weight: .regular)
        speedUnit.verticalAlignmentMode = .center
        speedUnit.position.y = -32
        speedo.addChild(speedUnit)

        // ── Lap info (bottom centre) ──────────────────────────────────────────
        lapLabel = label("LAP 1", size: 20, weight: .bold)
        lapLabel.position = CGPoint(x: s.width * 0.5, y: 44)
        lapLabel.horizontalAlignmentMode = .center
        addChild(lapLabel)

        lapTimeLabel = label("00:00.000", size: 14, weight: .regular)
        lapTimeLabel.position = CGPoint(x: s.width * 0.5, y: 20)
        lapTimeLabel.horizontalAlignmentMode = .center
        addChild(lapTimeLabel)

        // ── Surface / drift (top left) ────────────────────────────────────────
        surfaceLabel = label("TARMAC", size: 16, weight: .medium)
        surfaceLabel.position = CGPoint(x: 20, y: s.height - 36)
        surfaceLabel.horizontalAlignmentMode = .left
        surfaceLabel.fontColor = SKColor(white: 0.9, alpha: 0.85)
        addChild(surfaceLabel)

        driftLabel = label("DRIFT!", size: 22, weight: .heavy)
        driftLabel.position = CGPoint(x: s.width * 0.5, y: s.height - 60)
        driftLabel.horizontalAlignmentMode = .center
        driftLabel.fontColor = SKColor(red: 1, green: 0.6, blue: 0.1, alpha: 1)
        driftLabel.isHidden = true
        addChild(driftLabel)

        // ── Minimap (bottom right) ────────────────────────────────────────────
        let mapSize: CGFloat = 130
        minimapFrame = CGRect(x: s.width - mapSize - 16, y: 16, width: mapSize, height: mapSize)

        minimapBG = SKShapeNode(rect: minimapFrame, cornerRadius: 6)
        minimapBG.fillColor   = SKColor(white: 0, alpha: 0.45)
        minimapBG.strokeColor = SKColor(white: 1, alpha: 0.25)
        minimapBG.lineWidth   = 1
        minimapBG.zPosition   = 10
        addChild(minimapBG)

        minimapCar = SKShapeNode(circleOfRadius: 4)
        minimapCar.fillColor   = SKColor(red: 1, green: 0.2, blue: 0.1, alpha: 1)
        minimapCar.strokeColor = .white
        minimapCar.lineWidth   = 1
        minimapCar.zPosition   = 12   // above track path (11)
        addChild(minimapCar)
    }

    // MARK: - Track path drawing (call once after track is available)

    func buildMinimapPath(trackPath: TrackPath) {
        let samples = trackPath.samples
        let bMin    = trackPath.boundsMin
        let bMax    = trackPath.boundsMax

        func project(_ s: PathSample) -> CGPoint {
            let nx = CGFloat((s.position.x - bMin.x) / (bMax.x - bMin.x))
            let nz = CGFloat((s.position.z - bMin.y) / (bMax.y - bMin.y))
            return CGPoint(
                x: minimapFrame.minX + nx * minimapFrame.width,
                y: minimapFrame.minY + (1 - nz) * minimapFrame.height
            )
        }

        trackPoints = samples.map(project)

        let path  = CGMutablePath()
        if let first = trackPoints.first {
            path.move(to: first)
            for pt in trackPoints.dropFirst() { path.addLine(to: pt) }
            path.closeSubpath()
        }
        minimapTrackPath = SKShapeNode(path: path)
        minimapTrackPath.strokeColor = SKColor(white: 1, alpha: 0.6)
        minimapTrackPath.lineWidth   = 1.5
        minimapTrackPath.fillColor   = .clear
        minimapTrackPath.zPosition   = 11
        addChild(minimapTrackPath)
    }

    // MARK: - Per-frame update

    func updateHUD(speed: Float, lap: Int, lapTime: TimeInterval,
                   surface: SurfaceType, isDrifting: Bool, carPos: SIMD3<Float>,
                   trackPath: TrackPath) {
        // Speed
        speedLabel.text = "\(Int(speed))"

        // Lap
        lapLabel.text = "LAP \(max(lap, 1))"
        lapTimeLabel.text = formatTime(lapTime)

        // Surface
        surfaceLabel.text = surface.name
        surfaceLabel.fontColor = SKColor(cgColor: surface.color.cgColor)

        // Drift flash
        if isDrifting {
            driftLabel.isHidden = false
            let scale = 1.0 + 0.08 * sin(CACurrentMediaTime() * 20)
            driftLabel.setScale(scale)
        } else {
            driftLabel.isHidden = true
        }

        // Minimap car dot
        let mm = trackPath.minimapPosition(for: carPos)
        minimapCar.position = CGPoint(
            x: minimapFrame.minX + CGFloat(mm.x) * minimapFrame.width,
            y: minimapFrame.minY + CGFloat(1 - mm.y) * minimapFrame.height
        )
    }

    // MARK: - Helpers

    private func label(_ text: String, size: CGFloat, weight: UIFont.Weight) -> SKLabelNode {
        let n           = SKLabelNode()
        n.text          = text
        n.fontName      = UIFont.systemFont(ofSize: size, weight: weight).fontName
        n.fontSize      = size
        n.fontColor     = .white
        n.position      = .zero
        return n
    }

    private func arcNode(radius: CGFloat, start: CGFloat, end: CGFloat,
                         color: UIColor, width: CGFloat) -> SKShapeNode {
        let path = CGMutablePath()
        path.addArc(center: .zero, radius: radius, startAngle: start, endAngle: end, clockwise: false)
        let n           = SKShapeNode(path: path)
        n.strokeColor   = SKColor(cgColor: color.cgColor)
        n.lineWidth     = width
        n.fillColor     = .clear
        return n
    }

    private func formatTime(_ t: TimeInterval) -> String {
        let total  = max(0, t)
        let mins   = Int(total / 60)
        let secs   = Int(total) % 60
        let millis = Int((total.truncatingRemainder(dividingBy: 1)) * 1000)
        return String(format: "%02d:%02d.%03d", mins, secs, millis)
    }
}
