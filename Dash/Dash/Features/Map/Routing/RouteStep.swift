//
//  RouteStep.swift
//  Dash
//
//  The SDK-neutral maneuver model for turn-by-turn guidance (M4.3). A `Route`
//  (M3) gained a `steps` array of these; `GoogleRouteService` translates the
//  Routes API's `legs[].steps[]` into them at the boundary, exactly as it already
//  translates the overview polyline. No GoogleMaps / Routes-API types appear
//  here.
//
//  One `RouteStep` is one leg-of-the-journey the driver performs: a maneuver
//  (turn / merge / continue) at `maneuverPoint`, then travel `distanceMeters`
//  along `polyline` to the next step's maneuver point.
//

import Foundation

/// A coarse, SDK-neutral maneuver classification — enough for the guidance UI to
/// pick an arrow and a phrase, and for the progress engine to decide which
/// maneuvers matter for camera framing. Providers map their own richer enums
/// down to this.
nonisolated enum ManeuverType: Equatable, Sendable {
    case depart
    case turnLeft
    case turnRight
    case turnSlightLeft
    case turnSlightRight
    case turnSharpLeft
    case turnSharpRight
    case uTurn
    case straight
    case rampLeft
    case rampRight
    case merge
    case forkLeft
    case forkRight
    case roundabout
    case nameChange
    case arrive
    /// The provider gave a maneuver we don't model — fall back to its own
    /// instruction text.
    case unknown

    /// A short imperative for the maneuver card ("Turn right"). `nil` when the
    /// type carries no natural phrase and the raw instruction text should show
    /// instead.
    var phrase: String? {
        switch self {
        case .depart:          return "Start out"
        case .turnLeft:        return "Turn left"
        case .turnRight:       return "Turn right"
        case .turnSlightLeft:  return "Slight left"
        case .turnSlightRight: return "Slight right"
        case .turnSharpLeft:   return "Sharp left"
        case .turnSharpRight:  return "Sharp right"
        case .uTurn:           return "Make a U-turn"
        case .straight:        return "Continue straight"
        case .rampLeft, .rampRight: return "Take the ramp"
        case .forkLeft:        return "Keep left"
        case .forkRight:       return "Keep right"
        case .merge:           return "Merge"
        case .roundabout:      return "Enter the roundabout"
        case .arrive:          return "Arrive at destination"
        case .nameChange, .unknown: return nil
        }
    }

    /// SF Symbol for the maneuver arrow.
    var symbolName: String {
        switch self {
        case .depart:          return "location.north.line.fill"
        case .turnLeft:        return "arrow.turn.up.left"
        case .turnRight:       return "arrow.turn.up.right"
        case .turnSlightLeft:  return "arrow.up.left"
        case .turnSlightRight: return "arrow.up.right"
        case .turnSharpLeft:   return "arrow.uturn.left"
        case .turnSharpRight:  return "arrow.uturn.right"
        case .uTurn:           return "arrow.uturn.down"
        case .straight, .nameChange, .merge: return "arrow.up"
        case .rampLeft:        return "arrow.up.left"
        case .rampRight:       return "arrow.up.right"
        case .forkLeft:        return "arrow.branch"
        case .forkRight:       return "arrow.branch"
        case .roundabout:      return "arrow.triangle.turn.up.right.circle"
        case .arrive:          return "mappin.and.ellipse"
        case .unknown:         return "arrow.up"
        }
    }

    /// Whether the camera should zoom in for this maneuver as the driver nears
    /// it (M4.3 dynamic zoom). A genuine change of road warrants a closer look;
    /// continuing straight or a lane merge does not.
    var warrantsCloserView: Bool {
        switch self {
        case .turnLeft, .turnRight, .turnSlightLeft, .turnSlightRight,
             .turnSharpLeft, .turnSharpRight, .uTurn,
             .rampLeft, .rampRight, .forkLeft, .forkRight, .roundabout:
            return true
        case .depart, .straight, .merge, .nameChange, .arrive, .unknown:
            return false
        }
    }
}

/// One maneuver of a route plus the geometry that follows it.
nonisolated struct RouteStep: Equatable, Sendable {

    /// What the driver does at `maneuverPoint`.
    var maneuver: ManeuverType

    /// The provider's full instruction text, e.g. "Turn right onto MG Road".
    /// Shown when `maneuver.phrase` is `nil`; always available for accessibility.
    var instruction: String

    /// The road being joined / followed after the maneuver, when the provider
    /// gives one ("MG Road"). Derived at the provider boundary.
    var roadName: String?

    /// Where the maneuver happens — the start of this step.
    var maneuverPoint: MapCoordinate

    /// This step's path, in travel order, from `maneuverPoint` onward. Falls back
    /// to `[maneuverPoint, endPoint]` when the provider omits step geometry.
    var polyline: [MapCoordinate]

    /// Driving distance along `polyline`, in metres.
    var distanceMeters: Double

    init(
        maneuver: ManeuverType,
        instruction: String,
        roadName: String? = nil,
        maneuverPoint: MapCoordinate,
        polyline: [MapCoordinate],
        distanceMeters: Double
    ) {
        self.maneuver = maneuver
        self.instruction = instruction
        self.roadName = roadName
        self.maneuverPoint = maneuverPoint
        self.polyline = polyline
        self.distanceMeters = distanceMeters
    }

    /// The primary line for the maneuver card: the maneuver phrase, or the raw
    /// instruction when there is no natural phrase.
    var primaryText: String {
        maneuver.phrase ?? instruction
    }
}
