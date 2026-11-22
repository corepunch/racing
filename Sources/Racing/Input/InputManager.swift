import GameController

/// Reads both the system touch controller and paired extended gamepads.
final class RaceControls {
    private static let elements: Set<String> = [GCInputLeftThumbstick, GCInputButtonA, GCInputButtonB]
    private let touchController: GCVirtualController
    private var touchRequested = false
    private var connecting = false
    private var failed = false

    init() {
        let config = GCVirtualController.Configuration()
        config.elements = Self.elements
        touchController = GCVirtualController(configuration: config)
    }

    private var hardware: GCExtendedGamepad? {
        GCController.controllers().first { $0 !== touchController.controller && $0.extendedGamepad != nil }?.extendedGamepad
    }

    func setActive(_ active: Bool) {
        if !active { failed = false }
        let wantsTouch = active && hardware == nil
        touchRequested = wantsTouch
        if !wantsTouch {
            if !connecting, touchController.controller != nil { touchController.disconnect() }
        } else if !connecting, !failed, touchController.controller == nil {
            connecting = true
            touchController.connect { [weak self, touchController] error in
                DispatchQueue.main.async {
                    guard let self else {
                        touchController.disconnect()
                        return
                    }
                    self.connecting = false
                    self.failed = error != nil && self.touchRequested
                    if !self.touchRequested || self.hardware != nil { touchController.disconnect() }
                }
            }
        }
    }

    var instruction: String {
        if hardware != nil { return "LEFT STICK STEER   ·   RT ACCELERATE   ·   LT BRAKE / REVERSE" }
        if failed { return "← / → STEER   ·   ↑ ACCELERATE   ·   ↓ BRAKE / REVERSE" }
        return "LEFT STICK STEER   ·   A ACCELERATE   ·   B BRAKE / REVERSE"
    }

    var menuPressed: Bool { hardware?.buttonMenu.isPressed ?? false }

    var input: CarInput {
        let keyboard = GCKeyboard.coalesced?.keyboardInput
        let left = keyboard?.button(forKeyCode: .leftArrow)?.value ?? 0
        let right = keyboard?.button(forKeyCode: .rightArrow)?.value ?? 0
        let brake = keyboard?.button(forKeyCode: .downArrow)?.value ?? 0
        let throttle = keyboard?.button(forKeyCode: .upArrow)?.value ?? 0
        if left > 0 || right > 0 || brake > 0 || throttle > 0 {
            return CarInput(steer: right - left, brake: brake, throttle: throttle)
        }
        if let pad = hardware ?? touchController.controller?.extendedGamepad {
            let axis = pad.leftThumbstick.xAxis.value
            let magnitude = min(1, max(0, (abs(axis) - 0.08) / 0.92))
            let steering = (axis < 0 ? -1 : 1) * pow(magnitude, 1.75)
            return CarInput(steer: steering, brake: max(pad.buttonB.value, pad.leftTrigger.value),
                            throttle: max(pad.buttonA.value, pad.rightTrigger.value))
        }
        return CarInput(throttle: 0)
    }
}
