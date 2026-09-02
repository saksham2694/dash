//
//  RouteGeometry.swift
//  Dash
//
//  Pure, SDK-neutral geodesic helpers for the navigation progress engine (M4.3):
//  great-circle distance, polyline length, and projecting a point onto a
//  polyline. No GoogleMaps / CoreLocation / MapKit — just arithmetic on
//  `MapCoordinate`, so it is unit-testable in isolation (same spirit as
//  `GooglePolyline`).
//
//  Accuracy is "good enough for turn-by-turn": metres over a few kilometres.
//  Segment projection works in a local equirectangular frame around the query
//  point, which is fine at these scales.
//

import Foundation

nonisolated enum RouteGeometry {

    /// Mean Earth radius, metres.
    static let earthRadiusMeters = 6_371_000.0

    /// Great-circle distance between two coordinates, in metres (haversine).
    static func distance(_ a: MapCoordinate, _ b: MapCoordinate) -> Double {
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let dLat = (b.latitude - a.latitude) * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * earthRadiusMeters * asin(min(1, h.squareRoot()))
    }

    /// Total length of a polyline in metres. `0` for fewer than two points.
    static func length(_ polyline: [MapCoordinate]) -> Double {
        guard polyline.count > 1 else { return 0 }
        var total = 0.0
        for i in 1..<polyline.count {
            total += distance(polyline[i - 1], polyline[i])
        }
        return total
    }

    /// The result of snapping a point onto a polyline.
    struct Projection: Equatable {
        /// Index of the segment `[i, i+1]` the closest point lies on.
        var segmentIndex: Int
        /// The closest point on the polyline.
        var point: MapCoordinate
        /// Straight-line distance from the query point to `point`, metres.
        var distanceFromInput: Double
        /// Distance from the polyline's start to `point`, along the polyline,
        /// metres.
        var distanceAlong: Double
    }

    /// Project `p` onto `polyline`, returning the closest point, which segment it
    /// falls on, how far the input is from it, and how far along the polyline it
    /// sits. `nil` for an empty polyline; a single-point polyline projects onto
    /// that point.
    static func project(_ p: MapCoordinate, onto polyline: [MapCoordinate]) -> Projection? {
        guard let first = polyline.first else { return nil }
        guard polyline.count >= 2 else {
            return Projection(
                segmentIndex: 0,
                point: first,
                distanceFromInput: distance(p, first),
                distanceAlong: 0
            )
        }

        // Local equirectangular frame centred on `p`, in metres.
        let metersPerDegLat = 111_320.0
        let metersPerDegLon = 111_320.0 * cos(p.latitude * .pi / 180)
        func planar(_ c: MapCoordinate) -> (x: Double, y: Double) {
            ((c.longitude - p.longitude) * metersPerDegLon,
             (c.latitude - p.latitude) * metersPerDegLat)
        }

        var best = Projection(segmentIndex: 0, point: first,
                              distanceFromInput: .greatestFiniteMagnitude, distanceAlong: 0)
        var lengthBeforeSegment = 0.0

        for i in 0..<(polyline.count - 1) {
            let a = polyline[i]
            let b = polyline[i + 1]
            let segLength = distance(a, b)

            let pa = planar(a)
            let pb = planar(b)
            let dx = pb.x - pa.x
            let dy = pb.y - pa.y
            let segSq = dx * dx + dy * dy

            // Parametric position of the foot of the perpendicular, clamped to
            // the segment.
            let t: Double
            if segSq <= .ulpOfOne {
                t = 0
            } else {
                t = max(0, min(1, ((0 - pa.x) * dx + (0 - pa.y) * dy) / segSq))
            }

            let footLat = a.latitude + (b.latitude - a.latitude) * t
            let footLon = a.longitude + (b.longitude - a.longitude) * t
            let foot = MapCoordinate(latitude: footLat, longitude: footLon)
            let d = distance(p, foot)

            if d < best.distanceFromInput {
                best = Projection(
                    segmentIndex: i,
                    point: foot,
                    distanceFromInput: d,
                    distanceAlong: lengthBeforeSegment + segLength * t
                )
            }
            lengthBeforeSegment += segLength
        }
        return best
    }
}
