<div align="center">

# Tabby

**A fast, good-looking ⌥Tab window switcher for macOS.**

Hold ⌥, tap Tab, see every window as a live picture, let go to switch. That's the whole app.

[![CI](https://github.com/ChristiantangCC/tabby/actions/workflows/ci.yml/badge.svg)](https://github.com/ChristiantangCC/tabby/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
![macOS 14+](https://img.shields.io/badge/platform-macOS%2014%2B-lightgrey)

</div>

## Why

macOS's own ⌘Tab switches between apps, not windows. Tools like AltTab fix that, but grow a settings screen for every edge case. Tabby does one thing: switch windows, quickly, and look nice doing it.

## Layouts

| Layout | What it looks like |
| --- | --- |
| **Thumbnails** | A grid of live window pictures, each tile in its window's real shape |
| **Cover Flow** | A 3D shelf with reflections that flips past as you tab |
| **Deck** | Your windows fanned out like a hand of cards; the selected one lifts up |
| **Orbit** | Windows circle a large preview of the selected one |
| **Spotlight** | One huge preview with a small strip of the rest |
| **Time Machine** | Windows stacked into the distance over a starfield |

## Settings

- **Layout:** one of the six above, plus size, animation speed and window titles
- **Appearance:** light, dark or system; glass, solid or frameless surface; accent colour; dim the screen behind
- **Shortcut:** ⌥Tab by default. Click it in Settings and press a new one.

While the switcher is open: ⇧ goes backwards, arrow keys move, esc cancels, and releasing the modifier switches.

## Install

Tabby isn't notarized yet, so build it yourself. You need Xcode or the Swift toolchain (Swift 5.10+).

```sh
git clone https://github.com/ChristiantangCC/tabby.git
cd tabby
./scripts/build.sh
```

This builds `build/Tabby.app`, signs it (with your Apple Development certificate if you have one, otherwise ad-hoc) and copies it to `/Applications`. Pass `INSTALL=0` to skip the copy.

On first launch Tabby asks for two permissions:

- **Accessibility:** to catch the shortcut and focus windows
- **Screen Recording:** to draw window thumbnails

Settings → General has a **Grant…** button for each. With an ad-hoc signature, macOS forgets both after every rebuild.

## How it works

- Windows are listed through the Accessibility API, in parallel per app, starting the moment you press ⌥ so the list is usually ready before Tab lands.
- Thumbnails come from ScreenCaptureKit, captured only as large as the layout draws them.
- A window is focused with the same window-server calls AltTab and yabai use, so the exact window comes forward, not just its app.

Tabby only sees windows on the current Space.

## License

[MIT](LICENSE)
