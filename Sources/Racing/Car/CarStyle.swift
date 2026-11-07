import Foundation

/// All selectable car visual styles.
/// Loaded styles resolve to a USDZ in Resources/Cars/.
/// Procedural styles are built entirely in code.
enum CarStyle: String, CaseIterable {

    // MARK: - Kenney Starter Kit (CC0) — cartoon trucks

    case truckGreen    = "vehicle-truck-green"
    case truckPurple   = "vehicle-truck-purple"
    case truckRed      = "vehicle-truck-red"
    case truckYellow   = "vehicle-truck-yellow"
    case motorcycle    = "vehicle-motorcycle"

    // MARK: - OpenGameArt LowPoly Cars Pack 1 (CC0) — semi-realistic

    case ogaBasicCar       = "oga_BasicCar"
    case ogaCopCar         = "oga_CopCar"
    case ogaRaceCar        = "oga_RaceCar"
    case ogaSimpleCarHigh  = "oga_SimpleCarHigh"
    case ogaSimpleCarShort = "oga_SimpleCarShort"
    case ogaTaxi           = "oga_Taxi"

    // MARK: - OpenGameArt LowPoly Cars Pack 2 (CC0) — minimalist blocky

    case oga2RaceCar  = "oga2_RaceCar"
    case oga2SimpleCar = "oga2_SimpleCar"
    case oga2Truck    = "oga2_Truck"

    // MARK: - Procedural

    case sport   // red boxy sport car
    case rally   // blue 90s rally car

    // MARK: - Metadata

    var displayName: String {
        switch self {
        case .truckGreen:       return "Truck (Green)"
        case .truckPurple:      return "Truck (Purple)"
        case .truckRed:         return "Truck (Red)"
        case .truckYellow:      return "Truck (Yellow)"
        case .motorcycle:       return "Motorcycle"
        case .ogaBasicCar:      return "Basic Car"
        case .ogaCopCar:        return "Police Car"
        case .ogaRaceCar:       return "Race Car"
        case .ogaSimpleCarHigh: return "Coupe"
        case .ogaSimpleCarShort: return "Hatchback"
        case .ogaTaxi:          return "Taxi"
        case .oga2RaceCar:      return "Race Car (Retro)"
        case .oga2SimpleCar:    return "Simple Car (Retro)"
        case .oga2Truck:        return "Truck (Retro)"
        case .sport:            return "Sport (Procedural)"
        case .rally:            return "Rally (Procedural)"
        }
    }

    /// Whether this style loads a USDZ from the bundle.
    var isAssetBased: Bool {
        switch self {
        case .sport, .rally: return false
        default:             return true
        }
    }

    // MARK: - Wheel node names

    struct WheelNodes {
        /// nil means share the same merged node with the other side
        let frontLeft:  String?
        let frontRight: String?
        let rearLeft:   String?
        let rearRight:  String?
    }

    var wheelNodes: WheelNodes {
        switch self {
        case .truckGreen, .truckPurple, .truckRed, .truckYellow:
            return WheelNodes(frontLeft:  "wheel_front_left",
                              frontRight: "wheel_front_right",
                              rearLeft:   "wheel_back_left",
                              rearRight:  "wheel_back_right")

        case .motorcycle:
            return WheelNodes(frontLeft:  "wheel_front",
                              frontRight: "wheel_front",
                              rearLeft:   "wheel_back",
                              rearRight:  "wheel_back")

        case .ogaBasicCar:
            return WheelNodes(frontLeft:  "FrontWheels_Cylinder_003",
                              frontRight: "FrontWheels_Cylinder_003",
                              rearLeft:   "BackWheels_Cylinder_006",
                              rearRight:  "BackWheels_Cylinder_006")

        case .ogaCopCar:
            return WheelNodes(frontLeft:  "FrontWheels_Cylinder_001",
                              frontRight: "FrontWheels_Cylinder_001",
                              rearLeft:   "BackWheels_Cylinder_004",
                              rearRight:  "BackWheels_Cylinder_004")

        case .ogaRaceCar:
            return WheelNodes(frontLeft:  "FrontWheels_Cylinder_003",
                              frontRight: "FrontWheels_Cylinder_003",
                              rearLeft:   "FrontWheels_001_Cylinder_002",
                              rearRight:  "FrontWheels_001_Cylinder_002")

        case .ogaSimpleCarHigh, .ogaSimpleCarShort:
            return WheelNodes(frontLeft:  "FrontWheels_000_Cylinder_000",
                              frontRight: "FrontWheels_000_Cylinder_000",
                              rearLeft:   "FrontWheels_001_Cylinder_001",
                              rearRight:  "FrontWheels_001_Cylinder_001")

        case .ogaTaxi:
            return WheelNodes(frontLeft:  "Front_Wheels_Cylinder_001",
                              frontRight: "Front_Wheels_Cylinder_001",
                              rearLeft:   "BackWheels_Cylinder_003",
                              rearRight:  "BackWheels_Cylinder_003")

        case .oga2RaceCar:
            return WheelNodes(frontLeft:  "Cylinder",
                              frontRight: "Cylinder",
                              rearLeft:   "Cylinder_001_Cylinder_005",
                              rearRight:  "Cylinder_001_Cylinder_005")

        case .oga2SimpleCar:
            return WheelNodes(frontLeft:  "Cylinder_000_Cylinder_015",
                              frontRight: "Cylinder_000_Cylinder_015",
                              rearLeft:   "Cylinder_001_Cylinder_017",
                              rearRight:  "Cylinder_001_Cylinder_017")

        case .oga2Truck:
            return WheelNodes(frontLeft:  "Cylinder_000_Cylinder_007",
                              frontRight: "Cylinder_000_Cylinder_007",
                              rearLeft:   "Cylinder_001_Cylinder_002",
                              rearRight:  "Cylinder_001_Cylinder_002")

        case .sport, .rally:
            return WheelNodes(frontLeft: nil, frontRight: nil, rearLeft: nil, rearRight: nil)
        }
    }

    // MARK: - Visual scale & orientation

    /// Scale to apply to the loaded model.
    /// Kenney trucks are 1.5 m wide and 2.9 m long natively; use 2.1 m width in game.
    var modelScale: Float {
        switch self {
        case .truckGreen, .truckPurple, .truckRed, .truckYellow:
            return 1.4
        case .motorcycle:
            return 2.0
        case .ogaBasicCar, .ogaCopCar, .ogaRaceCar,
             .ogaSimpleCarHigh, .ogaSimpleCarShort, .ogaTaxi:
            return 1.0
        case .oga2RaceCar, .oga2SimpleCar, .oga2Truck:
            return 1.0
        case .sport, .rally:
            return 1.0
        }
    }

    /// Kenney trucks face +Z; SceneKit game expects −Z. Rotate π around Y.
    var modelYRotation: Float {
        switch self {
        case .truckGreen, .truckPurple, .truckRed, .truckYellow,
             .motorcycle:
            return .pi
        default:
            return 0
        }
    }

    /// Y-offset to lower loaded models so wheels sit on the ground plane.
    var modelYOffset: Float {
        switch self {
        case .truckGreen, .truckPurple, .truckRed, .truckYellow:
            return -0.3 * modelScale   // wheel centre at Y≈0.3 × scale
        case .motorcycle:
            return -0.3 * 2.0
        default:
            return 0
        }
    }
}
