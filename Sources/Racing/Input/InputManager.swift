import UIKit

/// One-thumb control. Touch anywhere and slide: sideways steers, pulling down airbrakes.
/// The ship accelerates on its own, so lifting the thumb just flies straight.
/// Arrow keys do the same on a keyboard.
final class InputView: UIView {
    /// Sideways travel for full lock, in points.
    private var steeringDistance: CGFloat { max(70, min(bounds.width * 0.3, 130)) }
    /// Downward travel before the airbrake starts, and from there to full.
    private let brakeDeadZone: CGFloat = 34
    private let brakeDistance: CGFloat = 90
    private var keys = Set<UIKeyboardHIDUsage>()
    private var activeTouch: UITouch?
    private var origin = CGPoint.zero
    private var current = CGPoint.zero
    private var touchSteer: Float = 0
    private var touchBrake: Float = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        contentMode = .redraw
    }

    required init?(coder: NSCoder) { fatalError() }
    override var canBecomeFirstResponder: Bool { true }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard activeTouch == nil, let touch = touches.first else { return }
        activeTouch = touch
        origin = touch.location(in: self)
        current = origin
        setNeedsDisplay()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = activeTouch, touches.contains(touch) else { return }
        current = touch.location(in: self)
        // The anchor follows a thumb that overshoots, so reversing answers at once.
        let reach = steeringDistance
        origin.x = max(current.x - reach, min(current.x + reach, origin.x))
        origin.y = max(origin.y, current.y - brakeDeadZone - brakeDistance)
        origin.y = min(origin.y, current.y)
        let horizontal = (current.x - origin.x) / reach
        // Slightly soft round the centre for small corrections.
        touchSteer = Float((horizontal < 0 ? -1 : 1) * pow(abs(horizontal), 1.25))
        touchBrake = Float(max(0, min(1, (current.y - origin.y - brakeDeadZone) / brakeDistance)))
        setNeedsDisplay()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let touch = activeTouch, touches.contains(touch) { resetTouch() }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let touch = activeTouch, touches.contains(touch) { resetTouch() }
    }

    override func draw(_ rect: CGRect) {
        guard activeTouch != nil else { return }
        let reach = steeringDistance
        // Steering rail with a knob under the thumb.
        let rail = UIBezierPath()
        rail.move(to: CGPoint(x: origin.x - reach, y: origin.y))
        rail.addLine(to: CGPoint(x: origin.x + reach, y: origin.y))
        rail.lineWidth = 3
        rail.lineCapStyle = .round
        UIColor(white: 1, alpha: 0.22).setStroke()
        rail.stroke()
        let tick = UIBezierPath(rect: CGRect(x: origin.x - 1, y: origin.y - 7, width: 2, height: 14))
        UIColor(white: 1, alpha: 0.35).setFill()
        tick.fill()

        let braking = touchBrake > 0
        let knob = CGPoint(x: current.x, y: origin.y + (braking ? CGFloat(touchBrake) * 26 : 0))
        let color = braking ? UI.magenta : UI.cyan
        color.withAlphaComponent(0.25).setFill()
        UIBezierPath(ovalIn: CGRect(x: knob.x - 26, y: knob.y - 26, width: 52, height: 52)).fill()
        color.withAlphaComponent(0.9).setStroke()
        let ring = UIBezierPath(ovalIn: CGRect(x: knob.x - 17, y: knob.y - 17, width: 34, height: 34))
        ring.lineWidth = 2.5
        ring.stroke()
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
    var brake: Float { max(keys.contains(.keyboardDownArrow) ? 1 : 0, touchBrake) }
}
