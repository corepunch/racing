import UIKit

/// A floating touch control, with arrow keys available on keyboards.
final class InputView: UIView {
    private let controlDiameter: CGFloat = 100
    /// Finger travel for full lock: the whole screen width, so a given drag steers gently.
    private var steeringDistance: CGFloat { max(bounds.width, 1) }
    /// Downward finger travel for a full stop.
    private var brakeDistance: CGFloat { max(max(bounds.width, bounds.height) * 0.38, 1) }
    private var keys = Set<UIKeyboardHIDUsage>()
    private var activeTouch: UITouch?
    private var origin = CGPoint.zero
    private var current = CGPoint.zero
    private var touchSteer: Float = 0
    private var touchBrake: Float = 0
    private var touchThrottle: Float = 1

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isMultipleTouchEnabled = true
    }

    required init?(coder: NSCoder) { fatalError() }
    override var canBecomeFirstResponder: Bool { true }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard activeTouch == nil,
              let touch = touches.first(where: { $0.location(in: self).y >= bounds.midY }) else { return }
        activeTouch = touch
        origin = touch.location(in: self)
        current = origin
        setNeedsDisplay()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = activeTouch, touches.contains(touch) else { return }
        current = touch.location(in: self)
        let horizontal = (current.x - origin.x) / steeringDistance
        touchSteer = Float((horizontal < 0 ? -1 : 1) * logarithmicResponse(abs(horizontal)))
        let downward = max(0, (current.y - origin.y) / brakeDistance)
        // Ease off the accelerator over the first quarter, then build braking gently:
        // cubic, so most of the drag only trims speed and full stop needs the whole distance.
        touchThrottle = Float(max(0, 1 - downward / 0.25))
        let brakeProgress = max(0, min(1, (downward - 0.25) / 0.75))
        touchBrake = Float(brakeProgress * brakeProgress * brakeProgress)
        setNeedsDisplay()
    }

    /// Maps a normalized gesture to a gentle logarithmic response, preserving endpoints.
    private func logarithmicResponse(_ input: CGFloat) -> CGFloat {
        let normalized = max(0, min(1, input))
        return log1p(3 * normalized) / log1p(3)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let touch = activeTouch, touches.contains(touch) { resetTouch() }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let touch = activeTouch, touches.contains(touch) { resetTouch() }
    }

    override func draw(_ rect: CGRect) {
        guard activeTouch != nil else { return }
        let circle = CGRect(x: origin.x - controlDiameter / 2, y: origin.y - controlDiameter / 2,
                            width: controlDiameter, height: controlDiameter)
        UIColor(white: 0, alpha: 0.3).setFill()
        UIColor(white: 1, alpha: 0.7).setStroke()
        let ring = UIBezierPath(ovalIn: circle)
        ring.lineWidth = 2
        ring.fill()
        ring.stroke()

        let dx = max(-steeringDistance, min(steeringDistance, current.x - origin.x))
        let dy = max(0, min(brakeDistance, current.y - origin.y))
        UIColor(white: 1, alpha: 0.8).setFill()
        UIBezierPath(ovalIn: CGRect(x: origin.x + dx - 10, y: origin.y + dy - 10,
                                    width: 20, height: 20)).fill()
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        for press in presses { if let key = press.key { keys.insert(key.keyCode) } }
        super.pressesBegan(presses, with: event)
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        for press in presses { if let key = press.key { keys.remove(key.keyCode) } }
        super.pressesEnded(presses, with: event)
    }

    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        for press in presses { if let key = press.key { keys.remove(key.keyCode) } }
        super.pressesCancelled(presses, with: event)
    }

    private func resetTouch() {
        activeTouch = nil
        touchSteer = 0
        touchBrake = 0
        touchThrottle = 1
        setNeedsDisplay()
    }

    func reset() {
        keys.removeAll()
        resetTouch()
    }

    var steer: Float {
        let keyboard: Float = (keys.contains(.keyboardRightArrow) ? 1 : 0) - (keys.contains(.keyboardLeftArrow) ? 1 : 0)
        return keyboard != 0 ? keyboard : touchSteer
    }
    var throttle: Float { keys.contains(.keyboardDownArrow) ? 0 : touchThrottle }
    var brake: Float { max(keys.contains(.keyboardDownArrow) ? 1 : 0, touchBrake) }
}
