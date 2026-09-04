# Built-in wallpapers

Image files here (`.png`, `.jpg`, `.jpeg`, `.heic`) ship with the app as
built-in wallpapers — bundled and non-deletable, alongside the default
("Ember") in Settings ▸ Wallpaper.

Adding one is explicit, two steps, no automatic scanning:

1. Drop the image file in this folder.
2. Add one entry for it in `WallpaperCatalog.all`, in
   `Core/DashWallpaper.swift` — a `builtInWallpaper(fileName:extension:id:displayName:)`
   call, matching the file name exactly.

This folder is committed to the repo — unlike `Dash/Dash/LocalAssets/`
(git-ignored, for private/non-redistributable dev assets), anything placed
here ships in the built app and is fine to commit.
