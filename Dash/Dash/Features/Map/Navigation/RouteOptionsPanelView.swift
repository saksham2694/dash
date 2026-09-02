//
//  RouteOptionsPanelView.swift
//  Dash
//
//  The compact route-option selector (M4.5). Presentational: it renders one chip
//  per `RouteOptionSummary` (duration, distance, a relative label) and reports
//  taps. `RouteOptions` in `RouteViewModel` / `MapViewModel` decides the
//  content and which chip is selected.
//
//  Deliberately small and horizontal — never a full-screen list. Used both in
//  the destination preview and, with `onDismiss` set, for a mid-navigation
//  refresh result.
//

import SwiftUI

struct RouteOptionsPanelView: View {

    let summaries: [RouteOptionSummary]

    /// The driver picked a route (its `id`).
    var onSelect: (String) -> Void

    /// Shown as a small "keep current" ✕ when set (the navigation refresh case).
    var onDismiss: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(summaries) { summary in
                        chip(summary)
                            .onTapGesture { onSelect(summary.id) }
                    }
                }
                .padding(.vertical, 2)
            }

            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color(uiColor: .label))
                        .frame(width: 32, height: 32)
                        .background(Color.primary.opacity(0.1), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Keep current route")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08))
        )
        .shadow(color: .black.opacity(0.15), radius: 10, y: 3)
    }

    private func chip(_ summary: RouteOptionSummary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(summary.durationText)
                .font(.headline)
                .monospacedDigit()
                .foregroundStyle(Color(uiColor: .label))
            Text(summary.distanceText)
                .font(.caption)
                .foregroundStyle(Color(uiColor: .secondaryLabel))
            Text(summary.label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(summary.isSelected
                                 ? Color(uiColor: .systemBlue)
                                 : Color(uiColor: .secondaryLabel))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minWidth: 96, alignment: .leading)
        .background(
            summary.isSelected
                ? Color(uiColor: .systemBlue).opacity(0.15)
                : Color.primary.opacity(0.06),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(summary.isSelected ? Color(uiColor: .systemBlue) : .clear, lineWidth: 1.5)
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(summary.isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityLabel("\(summary.durationText), \(summary.distanceText), \(summary.label)")
    }
}

#if DEBUG
#Preview("Route options") {
    let summaries = [
        RouteOptionSummary(id: "route-0", isSelected: true, isRecommended: true,
                           distanceText: "12 km", durationText: "18 min", label: "Recommended"),
        RouteOptionSummary(id: "route-1", isSelected: false, isRecommended: false,
                           distanceText: "14 km", durationText: "16 min", label: "2 min faster"),
        RouteOptionSummary(id: "route-2", isSelected: false, isRecommended: false,
                           distanceText: "11 km", durationText: "22 min", label: "4 min longer"),
    ]
    return VStack(spacing: 14) {
        RouteOptionsPanelView(summaries: summaries, onSelect: { _ in })
        RouteOptionsPanelView(summaries: summaries, onSelect: { _ in }, onDismiss: {})
    }
    .padding()
    .frame(maxWidth: 600)
    .background(Color(white: 0.15))
}
#endif
