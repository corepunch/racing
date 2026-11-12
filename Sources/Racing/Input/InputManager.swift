import UIKit
import GameController

/// Keyboard input remains available on Mac, Simulator, and paired keyboards.
final class InputView: UIView {
    private var keys = Set<UIKeyboardHIDUsage>()

    override var canBecomeFirstResponder: Bool { true }

    // Let the system virtual controller receive touches.
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool { false }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        for press in presses {
            if let key = press.key { keys.insert(key.keyCode) }
        }
        super.pressesBegan(presses, with: event)
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        for press in presses {
            if let key = press.key { keys.remove(key.keyCode) }
        }
        super.pressesEnded(presses, with: event)
    }

    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        for press in presses {
            if let key = press.key { keys.remove(key.keyCode) }
        }
        super.pressesCancelled(presses, with: event)
    }

    func reset() { keys.removeAll() }
    var steer: Float { (keys.contains(.keyboardRightArrow) ? 1 : 0) - (keys.contains(.keyboardLeftArrow) ? 1 : 0) }
    var throttle: Float { keys.contains(.keyboardUpArrow) ? 1 : 0 }
    var brake: Float { keys.contains(.keyboardDownArrow) ? 1 : 0 }
}

/// Reads physical and system virtual gamepads through the same extended profile.
final class InputManager {
    struct State {
        var steer: Float = 0
        var throttle: Float = 0
        var brake: Float = 0
    }

    private var observers: [NSObjectProtocol] = []
    #if !targetEnvironment(macCatalyst)
    private let virtualController: GCVirtualController
    private var connecting = false
    #endif

    init() {
        #if !targetEnvironment(macCatalyst)
        let configuration = GCVirtualController.Configuration()
        configuration.elements = [GCInputLeftThumbstick, GCInputButtonA, GCInputButtonB]
        virtualController = GCVirtualController(configuration: configuration)
        #endif
        let center = NotificationCenter.default
        for name in [NSNotification.Name.GCControllerDidConnect, .GCControllerDidDisconnect] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.updateControllers()
            })
        }
        updateControllers()
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        #if !targetEnvironment(macCatalyst)
        virtualController.disconnect()
        #endif
    }

    private func updateControllers() {
        #if !targetEnvironment(macCatalyst)
        let physical = GCController.controllers().contains { $0 !== virtualController.controller && $0.extendedGamepad != nil }
        if physical {
            if virtualController.controller != nil { virtualController.disconnect() }
        } else if virtualController.controller == nil && !connecting {
            connecting = true
            virtualController.connect { [weak self] error in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    self.connecting = false
                    if let error = error {
                        NSLog("Could not connect virtual controller: %@", error.localizedDescription)
                    } else {
                        self.updateControllers()
                    }
                }
            }
        }
        #endif
    }

    func state() -> State {
        let controllers = GCController.controllers().filter { $0.extendedGamepad != nil }
        #if !targetEnvironment(macCatalyst)
        let controller = controllers.first { $0 !== virtualController.controller } ?? virtualController.controller
        #else
        let controller = controllers.first
        #endif
        guard let gamepad = controller?.extendedGamepad else { return State() }
        let stick = gamepad.leftThumbstick.xAxis.value
        let steer = abs(stick) > 0.12 ? stick : gamepad.dpad.xAxis.value
        return State(steer: steer,
                     throttle: max(gamepad.rightTrigger.value, gamepad.buttonA.value),
                     brake: max(gamepad.leftTrigger.value, gamepad.buttonB.value))
    }
}
