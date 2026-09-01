//
//  DashMapView.swift
//  Dash
//
//  The embeddable map component. The dashboard hands it a `MapViewModel` and the
//  latest `LocationPacket` from `LocationStore`; everything SDK-specific lives
//  behind `viewModel.provider`. Styling is intentionally minimal for now.
//
//  Usage (later, from DashboardView):
//      DashMapView(viewModel: mapViewModel, location: locationStore.latestPacket)
//
//  Note: call `GoogleMapsConfiguration.bootstrap()` once at launch before this
//  view is shown, so the Google Maps SDK has its API key.
//

import DashShared
import SwiftUI

struct DashMapView: View {

    @ObservedObject var viewModel: MapViewModel

    /// Latest location, owned by `LocationStore` and passed down. `nil` until a
    /// fix arrives.
    var location: LocationPacket?

    var body: some View {
        viewModel.provider
            .makeMapView(content: viewModel.content) { event in
                viewModel.handle(event)
            }
            .onAppear { viewModel.update(with: location) }
            .onChange(of: location) { _, newLocation in
                viewModel.update(with: newLocation)
            }
    }
}
