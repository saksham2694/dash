//
//  RouteStatusView.swift
//  Dash
//
//  A small, transient status pill for M3 routing — shown under the search card
//  while a route is being fetched or after it failed. Nothing while the route is
//  idle or successfully drawn (the route itself is the success indicator, on the
//  map).
//
//  Deliberately NOT a navigation bottom sheet and NOT an ETA / turn-by-turn
//  surface — those are later milestones. No distance / duration text here even
//  though `Route` carries it.
//

import SwiftUI

struct RouteStatusView: View {

    @ObservedObject var viewModel: RouteViewModel

    /// Re-request the route with a fresh origin (owned by the composing view).
    var onRetry: () -> Void

    var body: some View {
        switch viewModel.state {
        case .idle, .loaded:
            EmptyView()

        case .loading:
            pill {
                ProgressView()
                    .controlSize(.small)
                Text("Finding route…")
            }

        case .noCurrentLocation:
            pill {
                Image(systemName: "location.slash")
                Text("Waiting for GPS to find a route")
            }

        case .failed:
            pill {
                Image(systemName: "exclamationmark.triangle")
                Text("Route unavailable")
                Button("Retry", action: onRetry)
                    .buttonStyle(.borderless)
                    .font(.subheadline.weight(.semibold))
            }
        }
    }

    private func pill<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 8) {
            content()
        }
        .font(.subheadline)
        // Explicit opaque colour, matching the search rows — the hierarchical
        // styles wash out against `.regularMaterial` over the bright map.
        .foregroundStyle(Color(uiColor: .label))
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08)))
        .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        // Own gap from the search card above — so the composing `VStack` can use
        // `spacing: 0` and reserve nothing when this view is `EmptyView`.
        .padding(.top, 8)
    }
}

#if DEBUG
#Preview("Route status") {
    let vm = RouteViewModel(service: PreviewRouteService())
    // No origin → lands in `.noCurrentLocation`, so the pill renders.
    vm.requestRoutes(
        to: Destination(placeID: "x", name: "X", address: nil,
                        coordinate: MapCoordinate(latitude: 1, longitude: 1)),
        from: nil
    )
    return RouteStatusView(viewModel: vm, onRetry: {})
        .padding()
        .frame(maxWidth: 560)
        .background(Color(white: 0.15))
}

private struct PreviewRouteService: RouteService {
    func routes(from origin: MapCoordinate, to destination: MapCoordinate) async throws -> [Route] {
        [Route(polyline: [MapCoordinate(latitude: 0, longitude: 0),
                          MapCoordinate(latitude: 1, longitude: 1)],
               distanceMeters: 0, duration: .zero)]
    }
}
#endif
