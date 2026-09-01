//
//  GooglePolyline.swift
//  Dash
//
//  Decoder for Google's "encoded polyline" string format, as returned by the
//  Routes API in `routes[].polyline.encodedPolyline`. Pure (no SDK, no
//  Foundation networking) and `internal` so it can be unit-tested directly, in
//  the same spirit as `GooglePlaceSearchService`'s static mapping helpers.
//
//  Algorithm: https://developers.google.com/maps/documentation/utilities/polylinealgorithm
//

import Foundation

nonisolated enum GooglePolyline {

    /// Decode an encoded-polyline string into ordered coordinates. Returns `[]`
    /// for an empty or truncated string rather than throwing.
    static func decode(_ encoded: String) -> [MapCoordinate] {
        let bytes = Array(encoded.utf8)
        var coordinates: [MapCoordinate] = []
        var index = 0
        var lat = 0
        var lon = 0

        // Reads one zig-zag-encoded varint delta starting at `index`; advances
        // `index` past it. Returns `nil` if the string ends mid-value.
        func nextDelta() -> Int? {
            var shift = 0
            var result = 0
            while index < bytes.count {
                let chunk = Int(bytes[index]) - 63
                index += 1
                result |= (chunk & 0x1F) << shift
                if chunk < 0x20 {
                    return (result & 1) != 0 ? ~(result >> 1) : (result >> 1)
                }
                shift += 5
            }
            return nil
        }

        while index < bytes.count {
            guard let deltaLat = nextDelta(), let deltaLon = nextDelta() else { break }
            lat += deltaLat
            lon += deltaLon
            coordinates.append(
                MapCoordinate(latitude: Double(lat) / 1e5, longitude: Double(lon) / 1e5)
            )
        }
        return coordinates
    }
}
