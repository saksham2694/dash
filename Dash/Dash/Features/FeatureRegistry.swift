//
//  FeatureRegistry.swift
//  Dash
//
//  The list of features the shell can show, plus lookup by `FeatureID`. Built
//  once in `DashApp` and injected into the view tree; the shell reads it to
//  render the sidebar / Home / (later) the dashboard grid.
//
//  `makeDefault()` is the single place the app's feature set is declared — add a
//  new `DashFeature` there and nothing in `Shell/` changes (M5 proposal §11).
//
//  It is an `ObservableObject` only so it can travel as an `@EnvironmentObject`
//  like the app's other stores; its contents are fixed after `init` in M5.0.
//

import Combine
import Foundation

@MainActor
final class FeatureRegistry: ObservableObject {

    /// Registered features, in declaration order (drives sidebar / Home order).
    let features: [any DashFeature]

    private let byID: [FeatureID: any DashFeature]

    init(_ features: [any DashFeature]) {
        let duplicates = Self.duplicateIDs(in: features)
        precondition(
            duplicates.isEmpty,
            "FeatureRegistry: duplicate feature id(s) \(duplicates)"
        )
        self.features = features
        self.byID = Dictionary(uniqueKeysWithValues: features.map { ($0.manifest.id, $0) })
    }

    /// The feature with this id, or `nil` if none is registered.
    func feature(_ id: FeatureID) -> (any DashFeature)? { byID[id] }

    /// The manifests of every registered feature, in order.
    var manifests: [FeatureManifest] { features.map(\.manifest) }

    // MARK: - Validation

    /// Ids that appear more than once, each reported once, in first-seen order.
    /// Pure — used by `init` and by tests (a `precondition` crash isn't
    /// observable from a test).
    static func duplicateIDs(in features: [any DashFeature]) -> [FeatureID] {
        var seen = Set<FeatureID>()
        var reported = Set<FeatureID>()
        var duplicates: [FeatureID] = []
        for feature in features {
            let id = feature.manifest.id
            if seen.contains(id), reported.insert(id).inserted {
                duplicates.append(id)
            }
            seen.insert(id)
        }
        return duplicates
    }
}

extension FeatureRegistry {

    /// The features Dash ships with. **This is the only place the feature set is
    /// declared** — add a new `DashFeature` here; the shell does not change.
    static func makeDefault() -> FeatureRegistry {
        FeatureRegistry([
            MapFeature(),
        ])
    }
}
