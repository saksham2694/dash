//
//  ManeuverCardView.swift
//  Dash
//
//  The top-of-map turn-by-turn card (M4.3). Presentational: it renders a
//  `ManeuverCard` and offers an "End" action. All state — which maneuver, how
//  far, arrival — is decided by `NavigationViewModel`.
//
//  CarPlay-like: a big maneuver arrow, a large distance, and the instruction /
//  road beneath. Deliberately NOT a full nav sheet (no ETA, lane guidance, or
//  step list — later milestones).
//

import SwiftUI

struct ManeuverCardView: View {

    let card: ManeuverCard

    /// Leave navigation and return to cruising.
    var onEnd: () -> Void

    /// Manually recalculate routes from the current location (M4.5). Hidden when
    /// `nil`. Shows a spinner while `isRefreshing`.
    var onRefresh: (() -> Void)?
    var isRefreshing: Bool = false

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: card.iconSystemName)
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(Color(uiColor: .label))
                .frame(width: 52)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                if let distanceText = card.distanceText {
                    Text(distanceText)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color(uiColor: .label))
                }
                Text(card.primaryText)
                    .font(.headline)
                    .foregroundStyle(Color(uiColor: .label))
                if let detailText = card.detailText, !detailText.isEmpty {
                    Text(detailText)
                        .font(.subheadline)
                        .foregroundStyle(Color(uiColor: .secondaryLabel))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                if let onRefresh {
                    Button(action: onRefresh) {
                        Group {
                            if isRefreshing {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.system(size: 15, weight: .bold))
                            }
                        }
                        .foregroundStyle(Color(uiColor: .label))
                        .frame(width: 36, height: 36)
                        .background(Color.primary.opacity(0.1), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(isRefreshing)
                    .accessibilityLabel("Refresh route")
                }

                Button(action: onEnd) {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color(uiColor: .label))
                        .frame(width: 36, height: 36)
                        .background(Color.primary.opacity(0.1), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("End navigation")
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08))
        )
        .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        [card.distanceText, card.primaryText, card.detailText]
            .compactMap { $0 }
            .joined(separator: ", ")
    }
}

#if DEBUG
#Preview("Maneuver") {
    VStack(spacing: 16) {
        ManeuverCardView(
            card: ManeuverCard(
                iconSystemName: "arrow.turn.up.right",
                primaryText: "Turn right",
                detailText: "Mahatma Gandhi Road",
                distanceText: "200 m",
                isArrival: false
            ),
            onEnd: {}
        )
        ManeuverCardView(card: .arrived, onEnd: {})
    }
    .padding()
    .frame(maxWidth: 560)
    .background(Color(white: 0.15))
}
#endif
