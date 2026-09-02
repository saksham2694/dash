//
//  DashboardLayoutValidator.swift
//  Dash
//
//  Pure validation for a `DashboardLayout`. Kept out of `DashboardLayoutStore`
//  so the rules are trivially unit-testable and reusable (load-time sanity gate
//  now; an editor's live feedback later).
//
//  Two entry points:
//    • `validate(_:grid:)` — structural only (no registry needed): duplicate
//      ids, non-widget sizes, out-of-bounds, overlaps.
//    • `validate(_:grid:registry:)` — the above plus feature-aware checks:
//      the feature exists and supports the requested size.
//

import Foundation

/// A single problem found in a layout. `Equatable` so tests can assert exact sets.
nonisolated enum DashboardLayoutIssue: Equatable, Sendable {
    case duplicatePlacementID(UUID)
    case notAWidgetSize(placementID: UUID, size: ComponentSize)
    case outOfBounds(placementID: UUID)
    case overlap(UUID, UUID)
    case unknownFeature(placementID: UUID, featureID: FeatureID)
    case unsupportedSize(placementID: UUID, featureID: FeatureID, size: ComponentSize)
}

nonisolated enum DashboardLayoutValidator {

    /// Structural checks that need only the grid. Pure.
    static func validate(_ layout: DashboardLayout, grid: DashboardGrid) -> [DashboardLayoutIssue] {
        var issues: [DashboardLayoutIssue] = []
        var seenIDs = Set<UUID>()

        for placement in layout.allPlacements {
            if !seenIDs.insert(placement.id).inserted {
                issues.append(.duplicatePlacementID(placement.id))
            }
            if !placement.size.isWidget {
                issues.append(.notAWidgetSize(placementID: placement.id, size: placement.size))
            }
            if !grid.contains(grid.rect(for: placement)) {
                issues.append(.outOfBounds(placementID: placement.id))
            }
        }

        // Overlap is checked per page — widgets on different pages can't collide.
        for page in layout.pages {
            let placements = page.placements
            for i in placements.indices {
                for j in placements.indices where j > i {
                    if grid.rect(for: placements[i]).intersects(grid.rect(for: placements[j])) {
                        issues.append(.overlap(placements[i].id, placements[j].id))
                    }
                }
            }
        }

        return issues
    }

    /// Structural checks plus feature-aware ones. Needs the registry, so it is
    /// `@MainActor` like `FeatureRegistry` itself.
    @MainActor
    static func validate(
        _ layout: DashboardLayout,
        grid: DashboardGrid,
        registry: FeatureRegistry
    ) -> [DashboardLayoutIssue] {
        var issues = validate(layout, grid: grid)

        for placement in layout.allPlacements {
            guard let feature = registry.feature(placement.featureID) else {
                issues.append(.unknownFeature(placementID: placement.id, featureID: placement.featureID))
                continue
            }
            if !feature.manifest.supportedSizes.contains(placement.size) {
                issues.append(.unsupportedSize(
                    placementID: placement.id,
                    featureID: placement.featureID,
                    size: placement.size
                ))
            }
        }

        return issues
    }

    /// Convenience: whether the layout is free of structural problems.
    static func isStructurallyValid(_ layout: DashboardLayout, grid: DashboardGrid) -> Bool {
        validate(layout, grid: grid).isEmpty
    }
}
