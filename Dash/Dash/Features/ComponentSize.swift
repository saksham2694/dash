//
//  ComponentSize.swift
//  Dash
//
//  The size a feature is asked to render at. The shell picks a size and hands it
//  to a feature; the feature decides what that size *means* for its content
//  (M5 architecture proposal §4). SDK-neutral — no map / music types here.
//
//    • .full                 — the full-screen app experience.
//    • .large / .medium / .compact — dashboard-widget footprints (M5.2+).
//
//  M5.0 establishes the type only; the dashboard widget grid is a later
//  milestone, so nothing renders `.large` / `.medium` / `.compact` yet.
//

import Foundation

nonisolated enum ComponentSize: String, CaseIterable, Sendable, Codable {

    case compact
    case medium
    case large
    case full

    /// The dashboard-widget sizes — everything except the full-screen experience.
    static var widgetSizes: [ComponentSize] { [.compact, .medium, .large] }

    /// Whether this size is a dashboard widget rather than the full-screen app.
    var isWidget: Bool { self != .full }
}
