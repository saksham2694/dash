//
//  WallpaperStore.swift
//  Dash
//
//  App-scoped owner of the *persisted* shell wallpaper selection AND (M8.5)
//  the user's custom (imported) wallpapers. Loads on init, exposes both as
//  observable state, and writes back through `UserDefaults` (+ the sandbox
//  filesystem for custom image files) when they change.
//
//  Mirrors the project's other small single-purpose stores (`DashboardLayoutStore`,
//  `HomeLayoutStore`, `KnownDeviceStore`): storage only, no networking, no
//  feature knowledge, no UI. `Shell/DashShellBackground.swift` reads `selected`
//  to draw the live background; the Settings ▸ Wallpaper screen (self-contained
//  under `Features/Settings/`) calls `select(_:)` / `addCustomWallpaper(...)` /
//  `deleteCustomWallpaper(id:)`. Living in `Core/` — not `Shell/` — is what
//  makes that legal: a feature may never import `Shell/`, and this store is
//  the one thing both sides need.
//
//  Selection persistence is a single `WallpaperID.rawValue` string under a
//  namespaced key; an unrecognised value falls back to `WallpaperCatalog.default`.
//  Custom wallpapers persist as a small JSON array of lightweight records
//  (id/displayName/file name) under a second key; the actual image bytes live
//  as JPEG files in `Application Support/CustomWallpapers/` — the app's own
//  sandbox, never the user-visible Files app / Photos library.
//

import Combine
import Foundation
import UIKit

@MainActor
final class WallpaperStore: ObservableObject {

    /// Namespaced key. A breaking change to the wallpaper model bumps the `.vN`
    /// suffix; old values are then simply ignored (→ default).
    static let storageKey = "shell.wallpaper.v1"

    /// Namespaced key for the persisted custom-wallpaper record list.
    static let customStorageKey = "shell.wallpaper.custom.v1"

    /// The selected wallpaper's id. Read + persisted; never invalid.
    @Published private(set) var selectedID: WallpaperID

    /// The user's imported wallpapers, in the order they were added.
    @Published private(set) var customWallpapers: [DashWallpaper] = []

    /// The resolved catalogue entry for the current selection — checks custom
    /// wallpapers first (a built-in id can never collide with a generated
    /// UUID), then the built-in catalog.
    var selected: DashWallpaper {
        customWallpapers.first { $0.id == selectedID } ?? WallpaperCatalog.wallpaper(selectedID)
    }

    /// Every wallpaper the Settings ▸ Wallpaper screen should list: built-ins
    /// first, then custom ones in import order.
    var allWallpapers: [DashWallpaper] { WallpaperCatalog.all + customWallpapers }

    private let defaults: UserDefaults
    private let fileManager: FileManager

    init(defaults: UserDefaults = .standard, fileManager: FileManager = .default) {
        self.defaults = defaults
        self.fileManager = fileManager

        // Only list a custom record whose image file is actually still
        // present — a record surviving an external deletion of the file
        // (e.g. an app-data reset) shouldn't offer a wallpaper that can't
        // render.
        let directory = Self.customWallpapersDirectory(fileManager: fileManager)
        let resolvedCustomWallpapers = Self.loadCustomRecords(from: defaults).compactMap { record -> DashWallpaper? in
            let wallpaper = record.asDashWallpaper(directory: directory)
            guard let url = wallpaper.customFileURL, fileManager.fileExists(atPath: url.path) else { return nil }
            return wallpaper
        }
        self.customWallpapers = resolvedCustomWallpapers

        self.selectedID = Self.loadValid(from: defaults, knownCustomIDs: resolvedCustomWallpapers.map(\.id.rawValue))
            ?? WallpaperCatalog.default.id
    }

    // MARK: - Selection

    /// Choose a wallpaper and persist it. Persisting is idempotent; the
    /// `@Published` selection only churns on an actual change.
    func select(_ id: WallpaperID) {
        if id != selectedID { selectedID = id }
        defaults.set(id.rawValue, forKey: Self.storageKey)
    }

    /// Restore and persist the default wallpaper.
    func resetToDefault() {
        select(WallpaperCatalog.default.id)
    }

    // MARK: - Custom wallpapers (M8.5)

    enum ImportError: Error {
        case invalidImage
        case encodingFailed
        case writeFailed
    }

    /// Copy `imageData` into the app's sandbox as a new custom wallpaper,
    /// add it to the catalog, and return it. Downscales large photos (a
    /// Photos-library image can be tens of megapixels — a wallpaper never
    /// needs to be that large) before re-encoding as JPEG.
    @discardableResult
    func addCustomWallpaper(imageData: Data, displayName: String) throws -> DashWallpaper {
        guard let original = UIImage(data: imageData) else { throw ImportError.invalidImage }
        let resized = Self.downscaled(original, maxDimension: 2048)
        guard let jpegData = resized.jpegData(compressionQuality: 0.85) else { throw ImportError.encodingFailed }

        let directory = Self.customWallpapersDirectory(fileManager: fileManager)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let id = UUID().uuidString
        let fileName = "\(id).jpg"
        let url = directory.appendingPathComponent(fileName)
        do {
            try jpegData.write(to: url, options: .atomic)
        } catch {
            throw ImportError.writeFailed
        }

        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let record = CustomWallpaperRecord(
            id: id,
            displayName: trimmedName.isEmpty ? "Custom" : trimmedName,
            fileName: fileName
        )
        var records = Self.loadCustomRecords(from: defaults)
        records.append(record)
        persistCustomRecords(records)

        let wallpaper = record.asDashWallpaper(directory: directory)
        customWallpapers.append(wallpaper)
        return wallpaper
    }

    /// Delete a custom wallpaper: removes its stored file and catalog entry.
    /// If it was the current selection, falls back to the default built-in
    /// (M8.5 §1: "gracefully fall back to an available built-in wallpaper").
    /// A no-op for a built-in id (never deletable) or an unknown id.
    func deleteCustomWallpaper(id: WallpaperID) {
        guard let index = customWallpapers.firstIndex(where: { $0.id == id }) else { return }
        let wallpaper = customWallpapers[index]

        if let url = wallpaper.customFileURL {
            try? fileManager.removeItem(at: url)
        }

        customWallpapers.remove(at: index)
        var records = Self.loadCustomRecords(from: defaults)
        records.removeAll { $0.id == id.rawValue }
        persistCustomRecords(records)

        if selectedID == id {
            select(WallpaperCatalog.default.id)
        }
    }

    /// Longest-side-capped, aspect-preserving resize — a wallpaper never
    /// needs to exceed this, and it keeps imported files small.
    private static func downscaled(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let longestSide = max(size.width, size.height)
        guard longestSide > maxDimension, longestSide > 0 else { return image }

        let scale = maxDimension / longestSide
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: target)
        return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: target)) }
    }

    // MARK: - Persistence

    /// The persisted selection, or `nil` (→ caller uses the default) if it's
    /// missing, or a string that names neither a built-in NOR a currently
    /// resolvable custom wallpaper. `WallpaperID` itself accepts any string
    /// (custom ids are arbitrary UUIDs), so — unlike the old closed-`enum`
    /// version — "valid" has to be checked against the known sets here rather
    /// than by the type alone.
    private static func loadValid(from defaults: UserDefaults, knownCustomIDs: [String]) -> WallpaperID? {
        guard let raw = defaults.string(forKey: storageKey) else { return nil }
        guard WallpaperCatalog.all.contains(where: { $0.id.rawValue == raw }) || knownCustomIDs.contains(raw) else {
            return nil
        }
        return WallpaperID(rawValue: raw)
    }

    /// Where custom wallpaper image files are copied — the app's own
    /// sandbox (`Application Support`), never a user-visible location.
    private static func customWallpapersDirectory(fileManager: FileManager) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return base.appendingPathComponent("CustomWallpapers", isDirectory: true)
    }

    private static func loadCustomRecords(from defaults: UserDefaults) -> [CustomWallpaperRecord] {
        guard let data = defaults.data(forKey: customStorageKey) else { return [] }
        return (try? JSONDecoder().decode([CustomWallpaperRecord].self, from: data)) ?? []
    }

    private func persistCustomRecords(_ records: [CustomWallpaperRecord]) {
        guard let data = try? JSONEncoder().encode(records) else { return }
        defaults.set(data, forKey: Self.customStorageKey)
    }
}

/// The on-disk shape of one custom wallpaper's metadata. The image bytes
/// themselves live in a separate file (`fileName`, resolved against
/// `WallpaperStore`'s sandbox directory) — this record is just enough to
/// find it again and show a name.
private struct CustomWallpaperRecord: Codable, Equatable {
    var id: String
    var displayName: String
    var fileName: String

    func asDashWallpaper(directory: URL) -> DashWallpaper {
        DashWallpaper(
            customID: WallpaperID(rawValue: id),
            displayName: displayName,
            fileURL: directory.appendingPathComponent(fileName)
        )
    }
}
