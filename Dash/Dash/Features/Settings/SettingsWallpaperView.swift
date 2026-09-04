//
//  SettingsWallpaperView.swift
//  Dash — Settings feature
//
//  A plain Apple-style UI over the EXISTING `Core/WallpaperStore` /
//  `Core/WallpaperCatalog` — no second wallpaper persistence system. One
//  unified list — built-ins first, then the user's custom (imported)
//  wallpapers (`WallpaperStore.allWallpapers`) — with a native `PhotosPicker`
//  "Add Wallpaper" action and swipe-to-delete for custom entries only (a
//  built-in is never deletable — `DashWallpaper.isDeletable`).
//
//  Selecting a row calls straight through to `WallpaperStore.select(_:)`,
//  which `Shell/DashShellBackground.swift` already observes, so the shell's
//  background updates immediately — this view is simply the UI, not a
//  parallel source of truth. Each row previews the wallpaper's real artwork
//  via `Core/DashWallpaperArtwork` — the same renderer the shell itself uses.
//

import PhotosUI
import SwiftUI

struct SettingsWallpaperView: View {

    @EnvironmentObject private var wallpaperStore: WallpaperStore

    @State private var photosPickerItem: PhotosPickerItem?
    @State private var importErrorMessage: String?

    var body: some View {
        List {
            Section {
                ForEach(wallpaperStore.allWallpapers) { wallpaper in
                    Button {
                        wallpaperStore.select(wallpaper.id)
                    } label: {
                        row(for: wallpaper)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        if wallpaper.isDeletable {
                            Button(role: .destructive) {
                                wallpaperStore.deleteCustomWallpaper(id: wallpaper.id)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            } footer: {
                if wallpaperStore.allWallpapers.count == 1 {
                    Text("Import your own photo below, or more built-in wallpapers will be added in a future update.")
                }
            }

            Section {
                PhotosPicker(selection: $photosPickerItem, matching: .images) {
                    Label("Add Wallpaper", systemImage: "plus.circle.fill")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Wallpaper")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: photosPickerItem) { _, newItem in
            Task { await importSelection(newItem) }
        }
        .alert(
            "Couldn’t Add Wallpaper",
            isPresented: Binding(
                get: { importErrorMessage != nil },
                set: { if !$0 { importErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importErrorMessage ?? "")
        }
    }

    private func row(for wallpaper: DashWallpaper) -> some View {
        let selected = wallpaper.id == wallpaperStore.selectedID
        return HStack(spacing: 14) {
            DashWallpaperArtwork(wallpaper: wallpaper)
                .frame(width: 60, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
                )

            Text(wallpaper.displayName)
                .foregroundStyle(.primary)

            Spacer()

            if selected {
                Image(systemName: "checkmark")
                    .fontWeight(.semibold)
                    .foregroundStyle(.tint)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    /// Load the picked photo's data, copy it into the app's sandbox via
    /// `WallpaperStore`, and select it. Any failure surfaces as a plain
    /// alert — never a silent no-op, never a crash.
    private func importSelection(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        photosPickerItem = nil

        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                importErrorMessage = "The selected photo couldn’t be loaded."
                return
            }
            let name = "Wallpaper \(wallpaperStore.customWallpapers.count + 1)"
            let added = try wallpaperStore.addCustomWallpaper(imageData: data, displayName: name)
            wallpaperStore.select(added.id)
        } catch {
            importErrorMessage = "The selected photo couldn’t be added."
        }
    }
}

#if DEBUG
#Preview {
    NavigationStack { SettingsWallpaperView() }
        .environmentObject(WallpaperStore())
}
#endif
