import SwiftUI

/// The status-item icon: dim and neutral when nothing is listening, tinted with the system
/// accent color and a count badge when ports are active.
struct MenuBarLabel: View {
    let count: Int

    var body: some View {
        if count == 0 {
            // A template image lets the system tint it for the current menu bar appearance,
            // which is what makes the idle state read as "dim" in both light and dark modes.
            Image(systemName: "powerplug")
                .accessibilityLabel("Ports: none active")
        } else {
            Image(nsImage: MenuBarIconRenderer.activeIcon(count: count))
                .accessibilityLabel("Ports: \(count) active")
        }
    }
}

/// Renders the active icon to a non-template `NSImage`.
///
/// The menu bar force-tints template images to the system foreground color, so a colored icon
/// has to be a rendered, non-template bitmap. Results are cached per (count, scale, accent)
/// because the label re-evaluates on every refresh tick.
@MainActor
enum MenuBarIconRenderer {
    private static var cache: [String: NSImage] = [:]

    static func activeIcon(count: Int) -> NSImage {
        let scale = NSScreen.main?.backingScaleFactor ?? 2

        // The accent is part of the cache key: changing it in System Settings must not keep
        // serving a bitmap rendered in the old color.
        let accent = NSColor.controlAccentColor
        let key = "\(count)@\(scale)#\(accentFingerprint(accent))"
        if let cached = cache[key] { return cached }

        let badge = HStack(spacing: 3) {
            Image(systemName: "powerplug.fill")
                .font(.system(size: 13, weight: .medium))
            Text(verbatim: String(count))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
        // controlAccentColor, not Color.accentColor — this is specifically the shade set in
        // System Settings › Appearance, independent of any app-level accent override.
        .foregroundStyle(Color(nsColor: accent))
        .padding(.horizontal, 1)

        let renderer = ImageRenderer(content: badge)
        renderer.scale = scale

        guard let image = renderer.nsImage else {
            // Fall back to the template symbol rather than showing nothing at all.
            let fallback = NSImage(
                systemSymbolName: "powerplug.fill",
                accessibilityDescription: "Ports: \(count) active"
            ) ?? NSImage()
            fallback.isTemplate = true
            return fallback
        }

        image.isTemplate = false
        cache[key] = image
        return image
    }

    /// A stable string for the accent's resolved sRGB components, used only as a cache key.
    /// The "multicolor" accent setting resolves to whatever the system picks, so comparing
    /// resolved components is more reliable than comparing NSColor identity.
    private static func accentFingerprint(_ color: NSColor) -> String {
        guard let srgb = color.usingColorSpace(.sRGB) else { return "accent" }
        return String(
            format: "%.3f,%.3f,%.3f",
            srgb.redComponent, srgb.greenComponent, srgb.blueComponent
        )
    }
}
