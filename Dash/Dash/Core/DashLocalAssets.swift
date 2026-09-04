//
//  DashLocalAssets.swift
//  Dash
//
//  A tiny lookup for *optional*, local-only development assets — proprietary or
//  third-party artwork the developer drops into `Dash/LocalAssets/` for their
//  private device build (that folder is git-ignored). The committed app never
//  needs them: every call has an original, procedurally-drawn fallback.
//
//  Drop-in names the shell looks for (any of .png / .jpg / .jpeg / .heic):
//    • `shell-wallpaper`         — the full-screen shell background
//    • `app-icon-maps`           — the Maps launcher / rail icon
//    • `app-icon-music`          — the Music icon
//    • `app-icon-speedometer`    — the Speedometer icon
//
//  Files placed loose in `Dash/LocalAssets/` are bundled automatically by the
//  file-system-synchronised project; this just resolves them by name.
//
//  Lives in `Core/` (M8.3) — a plain name→image lookup, not shell-specific —
//  since `Core/DashWallpaperArtwork.swift` needs it too (a feature may not
//  import `Shell/`, so the shared wallpaper-preview renderer sits alongside
//  this rather than reaching into `Shell/`).
//

import SwiftUI

enum DashLocalAssets {

    private static let extensions = ["png", "jpg", "jpeg", "heic"]
    private static let subdirectory = "LocalAssets"

    /// A `UIImage` for `name` if the developer has provided a matching local
    /// file, otherwise `nil` (callers fall back to procedural art).
    static func uiImage(named name: String) -> UIImage? {
        for ext in extensions {
            if let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: subdirectory),
               let image = UIImage(contentsOfFile: url.path) {
                return image
            }
            // Also honour a plain bundle resource / asset-catalog entry.
            if let url = Bundle.main.url(forResource: name, withExtension: ext),
               let image = UIImage(contentsOfFile: url.path) {
                return image
            }
        }
        return UIImage(named: name)
    }

    /// A SwiftUI `Image` for `name`, or `nil`.
    static func image(named name: String) -> Image? {
        uiImage(named: name).map { Image(uiImage: $0) }
    }

    static func hasImage(named name: String) -> Bool {
        uiImage(named: name) != nil
    }
}
