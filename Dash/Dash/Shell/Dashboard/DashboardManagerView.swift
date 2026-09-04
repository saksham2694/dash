//
//  DashboardManagerView.swift
//  Dash
//
//  The dashboard switcher / manager (M5.6) — a small sheet opened from the
//  dashboard-name pill. Lists every dashboard (tap to switch), and offers add,
//  rename and remove. Deliberately unobtrusive: it is a modal sheet, not a
//  permanent sidebar control, and the entry-point pill only appears once there
//  is more than one dashboard (or while editing).
//
//  All state lives in `DashboardCollectionStore`; this view only sends it
//  intents. Styled to the shell's dark glass language, like the widget picker.
//

import SwiftUI

struct DashboardManagerView: View {

    @ObservedObject var dashboards: DashboardCollectionStore

    @Environment(\.dismiss) private var dismiss

    /// A rename in progress, if any.
    @State private var renaming: DashboardRecord?
    @State private var renameText: String = ""

    var body: some View {
        NavigationStack {
            ZStack {
                DashWallpaperView(wallpaper: WallpaperCatalog.default)
                    .ignoresSafeArea()

                List {
                    Section {
                        ForEach(dashboards.collection.dashboards) { record in
                            row(record)
                        }
                    }

                    Section {
                        Button {
                            dashboards.addDashboard()
                            dismiss()
                        } label: {
                            Label("Add Dashboard", systemImage: "plus")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(Color.dashAccent)
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Dashboards")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .alert("Rename Dashboard", isPresented: renamingBinding, presenting: renaming) { record in
            TextField("Name", text: $renameText)
            Button("Save") {
                dashboards.renameDashboard(id: record.id, to: renameText)
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Give this dashboard a name you'll recognise.")
        }
    }

    // MARK: - Row

    @ViewBuilder
    private func row(_ record: DashboardRecord) -> some View {
        let isActive = record.id == dashboards.activeID

        HStack(spacing: 12) {
            Image(systemName: isActive ? "checkmark.circle.fill" : "rectangle.grid.1x2")
                .foregroundStyle(isActive ? Color.dashAccent : Color.dashTextSecondary)

            Text(record.name)
                .font(.body.weight(isActive ? .semibold : .regular))
                .foregroundStyle(Color.dashTextPrimary)
                .lineLimit(1)

            Spacer()

            Text(widgetCountText(record))
                .font(.dashCaption)
                .foregroundStyle(Color.dashTextTertiary)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            dashboards.select(id: record.id)
            dismiss()
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if dashboards.dashboardCount > 1 {
                Button(role: .destructive) {
                    dashboards.removeDashboard(id: record.id)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
            Button {
                renameText = record.name
                renaming = record
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            .tint(.gray)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isActive ? "\(record.name), current dashboard" : record.name)
        .accessibilityHint("Switch to this dashboard")
    }

    private func widgetCountText(_ record: DashboardRecord) -> String {
        let count = record.layout.allPlacements.count
        return count == 1 ? "1 widget" : "\(count) widgets"
    }

    private var renamingBinding: Binding<Bool> {
        Binding(
            get: { renaming != nil },
            set: { if !$0 { renaming = nil } }
        )
    }
}
