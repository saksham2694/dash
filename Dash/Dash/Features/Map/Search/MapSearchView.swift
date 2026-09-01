//
//  MapSearchView.swift
//  Dash
//
//  The destination-search UI: a search field with a live suggestions list, and —
//  once a destination is chosen — a compact chip with a clear button. Purely
//  presentational + a `PlaceSearchViewModel`; it never touches the map renderer,
//  the Places SDK, or `DestinationStore` (the composing view wires those).
//
//  Result rows follow the Apple Maps hierarchy: a category glyph, a prominent
//  name, a secondary line of location context, and a trailing distance — so
//  several same-named places (three "Starbucks") read apart at a glance.
//

import SwiftUI

struct MapSearchView: View {

    @ObservedObject var viewModel: PlaceSearchViewModel

    /// The current destination, if one is chosen. Owned by `DestinationStore`.
    var destination: Destination?

    /// Clear the chosen destination and return to search.
    var onClear: () -> Void

    /// Horizontal inset that aligns row separators with the row text (past the
    /// leading glyph): card padding + glyph width + glyph-to-text spacing.
    private static let textLeadingInset: CGFloat = 16 + 28 + 14

    @FocusState private var queryFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            if let destination {
                chip(for: destination)
            } else {
                searchField
                if showsResults {
                    Divider().overlay(Color.primary.opacity(0.12))
                    results
                }
            }
        }
        // Fill the width the parent offers (ContentView caps this at 560) rather
        // than shrinking to the intrinsic width of the content.
        .frame(maxWidth: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08))
        )
        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
        .animation(.easeInOut(duration: 0.15), value: destination)
        .animation(.easeInOut(duration: 0.15), value: viewModel.suggestions)
    }

    // MARK: - Search field

    private var searchField: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.title3)
                .foregroundStyle(.secondary)

            TextField("Search for a place", text: $viewModel.query)
                .font(.title3)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($queryFieldFocused)

            if viewModel.isSearching {
                ProgressView()
            } else if !viewModel.query.isEmpty {
                Button {
                    viewModel.reset()
                    queryFieldFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 52)
    }

    private var showsResults: Bool {
        !viewModel.suggestions.isEmpty || viewModel.errorText != nil
    }

    private var results: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if let errorText = viewModel.errorText {
                    Text(errorText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 48)
                }

                ForEach(viewModel.suggestions) { suggestion in
                    // A plain tappable row, NOT `Button { } label: { … }`: a
                    // `Button` label is laid out as single-line control content,
                    // which clipped the row's second (`secondaryText`) line away.
                    // Button semantics are re-added explicitly below.
                    let select = {
                        queryFieldFocused = false
                        viewModel.choose(suggestion)
                    }
                    suggestionRow(suggestion)
                        .onTapGesture(perform: select)
                        .accessibilityElement(children: .combine)
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction(.default, select)

                    if suggestion.id != viewModel.suggestions.last?.id {
                        Divider()
                            .overlay(Color.primary.opacity(0.08))
                            .padding(.leading, Self.textLeadingInset)
                    }
                }
            }
        }
        .frame(maxHeight: 320)
    }

    private func suggestionRow(_ suggestion: PlaceSuggestion) -> some View {
        HStack(spacing: 14) {
            Image(systemName: Self.glyph(for: suggestion.category))
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Self.tint(for: suggestion.category))
                .frame(width: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(suggestion.primaryText)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                if let secondary = suggestion.secondaryText {
                    Text(secondary)
                        .font(.subheadline)
                        // Explicit opaque grey rather than `.foregroundStyle(.secondary)`:
                        // the hierarchical secondary style is translucent and washes out
                        // to near-invisible against `.regularMaterial` layered over the
                        // bright map. `.systemGray` stays readable in light and dark and
                        // still reads as clearly weaker than the primary line.
                        .foregroundStyle(Color(uiColor: .systemGray))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            // Claim the row's free width so the secondary line has room and the
            // trailing distance sits at the edge.
            .frame(maxWidth: .infinity, alignment: .leading)

            if let distance = Self.formattedDistance(suggestion.distanceMeters) {
                Text(distance)
                    .font(.footnote)
                    .monospacedDigit()
                    // Explicit opaque grey, matching the secondary line: the
                    // hierarchical `.tertiary` style is translucent and washes out
                    // to invisible against `.regularMaterial` over the bright map.
                    .foregroundStyle(Color(uiColor: .systemGray))
                    .layoutPriority(1)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .frame(minHeight: 58)
        .contentShape(Rectangle())
    }

    // MARK: - Chosen destination

    private func chip(for destination: Destination) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "mappin.circle.fill")
                .font(.title2)
                .foregroundStyle(.red)

            VStack(alignment: .leading, spacing: 2) {
                Text(destination.name.isEmpty ? "Destination" : destination.name)
                    .font(.headline)
                    .lineLimit(1)
                if let address = destination.address, !address.isEmpty {
                    Text(address)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            Button(role: .destructive, action: onClear) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Clear destination")
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 60)
    }

    // MARK: - Presentation helpers

    private static func glyph(for category: PlaceCategory) -> String {
        switch category {
        case .food: return "fork.knife"
        case .cafe: return "cup.and.saucer.fill"
        case .shopping: return "bag.fill"
        case .fuel: return "fuelpump.fill"
        case .lodging: return "bed.double.fill"
        case .transit: return "tram.fill"
        case .landmark: return "building.columns.fill"
        case .geographic: return "mappin.and.ellipse"
        case .place: return "mappin.circle.fill"
        }
    }

    private static func tint(for category: PlaceCategory) -> Color {
        switch category {
        case .food: return .orange
        case .cafe: return .brown
        case .shopping: return .pink
        case .fuel: return .blue
        case .lodging: return .indigo
        case .transit: return .blue
        case .landmark: return .purple
        case .geographic: return .gray
        case .place: return .red
        }
    }

    /// Locale-aware short distance, e.g. "850 m" / "1.2 km" (or "0.5 mi").
    private static func formattedDistance(_ meters: Double?) -> String? {
        guard let meters, meters.isFinite, meters >= 0 else { return nil }
        let formatter = MeasurementFormatter()
        formatter.unitOptions = .naturalScale
        formatter.unitStyle = .medium
        formatter.numberFormatter.maximumFractionDigits = meters < 10_000 ? 1 : 0
        return formatter.string(from: Measurement(value: meters, unit: UnitLength.meters))
    }
}

// MARK: - Preview

#if DEBUG
/// Canned results with long secondary lines — the layout regression to guard
/// against is exactly this: the secondary location line failing to render.
private struct PreviewPlaceSearchService: PlaceSearchService {
    func suggestions(matching query: String, near origin: MapCoordinate?) async throws -> [PlaceSuggestion] {
        [
            PlaceSuggestion(placeID: "1", primaryText: "Starbucks - Sector 7",
                            secondaryText: "Madhya Marg, Sector 7-C, Sector 7, Chandigarh, India",
                            distanceMeters: 9783, category: .cafe),
            PlaceSuggestion(placeID: "2", primaryText: "Starbucks - Elante Mall",
                            secondaryText: "Industrial Area Phase I, Chandigarh, India",
                            distanceMeters: 4210, category: .cafe),
            PlaceSuggestion(placeID: "3", primaryText: "Starbucks",
                            secondaryText: "VR Punjab, Kharar, Punjab, India",
                            distanceMeters: 15340, category: .cafe),
        ]
    }
    func details(for placeID: String) async throws -> Destination {
        Destination(placeID: placeID, name: "Starbucks", address: nil,
                    coordinate: MapCoordinate(latitude: 30.7, longitude: 76.8))
    }
}

#Preview("Search results") {
    let viewModel = PlaceSearchViewModel(service: PreviewPlaceSearchService(), debounce: .zero)
    viewModel.query = "starbucks"
    return MapSearchView(viewModel: viewModel, destination: nil, onClear: {})
        .frame(maxWidth: 560)
        .padding()
        .background(Color(white: 0.15))
}
#endif
