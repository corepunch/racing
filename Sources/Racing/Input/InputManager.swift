import UIKit

/// One-thumb control. Touch anywhere and slide: sideways steers, pulling down slows the car.
/// The pull is progressive: first the throttle eases off, then the brakes come on gently,
/// and only a pull of half the screen's width brakes hard (and reverses from a standstill).
/// The car accelerates on its own, so lifting the thumb just drives straight.
/// Arrow keys do the same on a keyboard.
final class InputView: UIView {
    /// Sideways travel for full lock, in points.
    private var steeringDistance: CGFloat { max(70, min(bounds.width * 0.3, 130)) }
    /// Downward travel ignored so steering does not lift the throttle, and the travel for hard braking.
    private let pullDeadZone: CGFloat = 18
    private var hardBrakeDistance: CGFloat { max(120, bounds.width * 0.5) }
    /// Share of the pull that only eases the throttle off, and the strongest soft braking.
    private let liftShare: Float = 0.3
    private let softBrake: Float = 0.4
    private var touchThrottle: Float = 1
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
        origin.y = max(origin.y, current.y - hardBrakeDistance)
        origin.y = min(origin.y, current.y)
        let horizontal = (current.x - origin.x) / reach
        // Slightly soft round the centre for small corrections.
        touchSteer = Float((horizontal < 0 ? -1 : 1) * pow(abs(horizontal), 1.25))
        let pull = Float(max(0, min(1, (current.y - origin.y - pullDeadZone) / (hardBrakeDistance - pullDeadZone))))
        touchThrottle = 1 - min(1, pull / liftShare)
        if pull >= 1 {
            touchBrake = 1
        } else {
            let soft = max(0, (pull - liftShare) / (1 - liftShare))
            touchBrake = softBrake * soft * soft.squareRoot()
        }
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

        // Brake rail: runs down to the hard-braking mark.
        let down = UIBezierPath()
        down.move(to: CGPoint(x: origin.x, y: origin.y + pullDeadZone))
        down.addLine(to: CGPoint(x: origin.x, y: origin.y + hardBrakeDistance))
        down.lineWidth = 3
        down.lineCapStyle = .round
        UIColor(white: 1, alpha: touchThrottle < 1 ? 0.22 : 0.08).setStroke()
        down.stroke()
        UI.magenta.withAlphaComponent(touchThrottle < 1 ? 0.8 : 0.25).setFill()
        UIBezierPath(rect: CGRect(x: origin.x - 9, y: origin.y + hardBrakeDistance - 1.5, width: 18, height: 3)).fill()

        // The knob sits under the thumb: cyan driving, amber slowing, magenta braking hard.
        let knob = CGPoint(x: current.x, y: max(origin.y, current.y))
        let color = touchBrake >= 1 ? UI.magenta : (touchThrottle < 1 ? UI.amber : UI.cyan)
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
    var brake: Float { max(keys.contains(.keyboardDownArrow) ? 1 : 0, touchBrake) }
    var throttle: Float { keys.contains(.keyboardDownArrow) ? 0 : touchThrottle }
}
