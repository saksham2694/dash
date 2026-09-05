//
//  MusicKitFavoritesService.swift
//  Dash — Apple Music feature
//
//  The production `MusicFavoritesService` — the Apple Music `ratings`
//  endpoint via `MusicDataRequest` (MusicKit's authenticated raw-request
//  type for endpoints without a dedicated Swift API). A rating `value` of
//  `1` is "loved" (the heart); no rating record means unfavorited. Setting
//  `isFavorite: false` deletes the rating rather than setting a negative
//  value, matching what un-hearting a song in Apple Music actually does.
//
//  Network calls here are best-effort: `MusicFavoritesStore` (the feature's
//  local, persisted cache) is what the UI actually reads for "is this
//  favorited", so a transient failure here never makes the heart icon look
//  broken — it just means Apple's server copy didn't update this time.
//

import Foundation
import MusicKit

struct MusicKitFavoritesService: MusicFavoritesService {

    func isFavorite(songID: MusicItemID) async -> Bool {
        guard let url = Self.ratingsURL(for: songID) else { return false }
        do {
            let request = MusicDataRequest(urlRequest: URLRequest(url: url))
            let response = try await request.response()
            let decoded = try JSONDecoder().decode(RatingsDocument.self, from: response.data)
            return decoded.data.first?.attributes.value == 1
        } catch {
            return false
        }
    }

    func setFavorite(songID: MusicItemID, isFavorite: Bool) async throws {
        guard let url = Self.ratingsURL(for: songID) else { return }
        var urlRequest = URLRequest(url: url)

        if isFavorite {
            urlRequest.httpMethod = "PUT"
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            urlRequest.httpBody = try JSONEncoder().encode(RatingPutBody(attributes: .init(value: 1)))
        } else {
            urlRequest.httpMethod = "DELETE"
        }

        let request = MusicDataRequest(urlRequest: urlRequest)
        _ = try await request.response()
    }

    private static func ratingsURL(for songID: MusicItemID) -> URL? {
        URL(string: "https://api.music.apple.com/v1/me/ratings/songs/\(songID.rawValue)")
    }

    // MARK: - Wire types (JSON:API-shaped, per Apple Music API's ratings resource)

    private struct RatingsDocument: Decodable {
        var data: [RatingResource]
    }

    private struct RatingResource: Decodable {
        var attributes: RatingAttributes
    }

    private struct RatingAttributes: Codable {
        var value: Int
    }

    private struct RatingPutBody: Encodable {
        var attributes: RatingAttributes
    }
}
