/// On-screen virtual controls: left thumbstick for steering, right-side gas/brake buttons.
/// Also handles hardware keyboard (arrow keys) for Simulator testing.

import UIKit

final class InputView: UIView {

    var onSteer:    ((Float) -> Void)?
    var onThrottle: ((Float) -> Void)?
    var onBrake:    ((Float) -> Void)?

    // State
    private var steerTouchID:   UITouch?
    private var stickOrigin:    CGPoint = .zero
    private var throttleTouchID: UITouch?
    private var brakeTouchID:   UITouch?

    // Layout constants
    private let stickRadius: CGFloat    = 55
    private let buttonRadius: CGFloat   = 44
    private let stickMaxOffset: CGFloat = 50

    // Steer stick visual
    private let stickBG  = UIView()
    private let stickKnob = UIView()
    private let gasButton  = UIButton(type: .custom)
    private let brakeButton = UIButton(type: .custom)

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        backgroundColor = .clear
        buildControls()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func buildControls() {
        // Left stick background
        stickBG.frame               = CGRect(origin: .zero, size: CGSize(width: stickRadius * 2, height: stickRadius * 2))
        stickBG.layer.cornerRadius  = stickRadius
        stickBG.backgroundColor     = UIColor(white: 1, alpha: 0.12)
        stickBG.layer.borderColor   = UIColor(white: 1, alpha: 0.3).cgColor
        stickBG.layer.borderWidth   = 1.5
        stickBG.isUserInteractionEnabled = false
        addSubview(stickBG)

        stickKnob.frame             = CGRect(origin: .zero, size: CGSize(width: 44, height: 44))
        stickKnob.layer.cornerRadius = 22
        stickKnob.backgroundColor   = UIColor(white: 1, alpha: 0.5)
        stickKnob.isUserInteractionEnabled = false
        addSubview(stickKnob)

        styleButton(gasButton,   title: "GAS",   color: UIColor(red: 0.2, green: 0.8, blue: 0.3, alpha: 0.75))
        styleButton(brakeButton, title: "BRAKE",  color: UIColor(red: 0.9, green: 0.2, blue: 0.2, alpha: 0.75))
    }

    private func styleButton(_ b: UIButton, title: String, color: UIColor) {
        b.setTitle(title, for: .normal)
        b.titleLabel?.font = UIFont.systemFont(ofSize: 13, weight: .bold)
        b.backgroundColor  = color
        b.layer.cornerRadius = buttonRadius
        b.isUserInteractionEnabled = false
        b.frame = CGRect(origin: .zero, size: CGSize(width: buttonRadius * 2, height: buttonRadius * 2))
        addSubview(b)
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        // Left side: stick centred at ~20% from left, ~40% from bottom
        let stickCentre = CGPoint(x: bounds.width * 0.18, y: bounds.height * 0.55)
        stickBG.center  = stickCentre
        stickKnob.center = stickCentre

        // Right side: gas bottom-right, brake above it
        let gasCenter   = CGPoint(x: bounds.width - 70, y: bounds.height * 0.65)
        let brakeCenter = CGPoint(x: bounds.width - 70, y: bounds.height * 0.30)
        gasButton.center   = gasCenter
        brakeButton.center = brakeCenter

        stickOrigin = stickCentre
    }

    // MARK: - Touch handling

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches {
            let p = t.location(in: self)
            if steerTouchID == nil && p.x < bounds.width * 0.4 {
                steerTouchID = t
                stickOrigin  = p
                stickBG.center = p
                stickKnob.center = p
            } else if throttleTouchID == nil && p.x > bounds.width * 0.6 && p.y > bounds.height * 0.5 {
                throttleTouchID = t
                gasButton.backgroundColor = gasButton.backgroundColor?.withAlphaComponent(1)
                onThrottle?(1)
            } else if brakeTouchID == nil && p.x > bounds.width * 0.6 && p.y < bounds.height * 0.5 {
                brakeTouchID = t
                brakeButton.backgroundColor = brakeButton.backgroundColor?.withAlphaComponent(1)
                onBrake?(1)
            }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches where t === steerTouchID {
            let p      = t.location(in: self)
            let dx     = p.x - stickOrigin.x
            let clamped = max(-stickMaxOffset, min(stickMaxOffset, dx))
            stickKnob.center = CGPoint(x: stickOrigin.x + clamped, y: stickOrigin.y)
            onSteer?(Float(clamped / stickMaxOffset))
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches {
            if t === steerTouchID {
                steerTouchID = nil
                stickKnob.center = stickOrigin
                stickBG.center   = CGPoint(x: bounds.width * 0.18, y: bounds.height * 0.55)
                stickKnob.center = stickBG.center
                stickOrigin      = stickBG.center
                onSteer?(0)
            } else if t === throttleTouchID {
                throttleTouchID = nil
                gasButton.backgroundColor = gasButton.backgroundColor?.withAlphaComponent(0.75)
                onThrottle?(0)
            } else if t === brakeTouchID {
                brakeTouchID = nil
                brakeButton.backgroundColor = brakeButton.backgroundColor?.withAlphaComponent(0.75)
                onBrake?(0)
            }
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchesEnded(touches, with: event)
    }

    // MARK: - Hardware keyboard (Simulator / paired keyboard)

    override var canBecomeFirstResponder: Bool { true }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        for p in presses {
            switch p.key?.keyCode {
            case .keyboardUpArrow:    onThrottle?(1)
            case .keyboardDownArrow:  onBrake?(1)
            case .keyboardLeftArrow:  onSteer?(-1)
            case .keyboardRightArrow: onSteer?(1)
            default: super.pressesBegan(presses, with: event)
            }
        }
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        for p in presses {
            switch p.key?.keyCode {
            case .keyboardUpArrow:    onThrottle?(0)
            case .keyboardDownArrow:  onBrake?(0)
            case .keyboardLeftArrow, .keyboardRightArrow: onSteer?(0)
            default: super.pressesEnded(presses, with: event)
            }
        }
    }
}
