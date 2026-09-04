//
//  WeatherStatusContent.swift
//  Dash — Weather feature
//
//  The shared "nothing to show yet" body for `.unavailable` / `.loading` /
//  `.failed` (M8.4 §2: "handle loading, unavailable location, request
//  failure... cleanly"). One small view instead of three near-duplicate
//  bodies scattered across the compact/medium/full-screen views.
//

import SwiftUI

struct WeatherStatusContent: View {

    let presentation: WeatherPresentation
    /// Bigger glyph/type on the full-screen presentation, same idea as the
    /// data views (M8.4 §7: "essentially the medium widget... larger").
    var isFullScreen: Bool = false

    var body: some View {
        VStack(spacing: isFullScreen ? 12 : 6) {
            if case .loading = presentation {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(isFullScreen ? 1.2 : 1)
            } else {
                Image(systemName: symbolName)
                    .font(.system(size: isFullScreen ? 40 : 22, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
            }
            Text(title)
                .font(isFullScreen ? .title3.weight(.semibold) : .subheadline.weight(.medium))
                .foregroundStyle(.white)
            if isFullScreen, let subtitle {
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var symbolName: String {
        switch presentation {
        case .unavailable: return "location.slash"
        case .loading:      return "arrow.triangle.2.circlepath"
        case .failed:       return "exclamationmark.triangle"
        case .loaded:       return "cloud"   // unreached — loaded states render their own content
        }
    }

    private var title: String {
        switch presentation {
        case .unavailable: return "Waiting for Location"
        case .loading:      return "Getting Weather…"
        case .failed:       return "Weather Unavailable"
        case .loaded:       return ""
        }
    }

    private var subtitle: String? {
        switch presentation {
        case .unavailable: return "Weather will appear once a GPS fix is available."
        case .failed:       return "Couldn't reach the weather service. It'll try again shortly."
        default:            return nil
        }
    }
}
