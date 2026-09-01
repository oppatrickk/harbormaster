import SwiftUI

/// The status-item icon: dim and neutral when nothing is listening, amber with a count badge
/// when ports are active.
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
/// The menu bar force-tints template images to the system foreground color, so an amber icon
/// has to be a rendered, non-template bitmap. Results are cached per (count, scale) because
/// the label re-evaluates on every refresh tick.
@MainActor
enum MenuBarIconRenderer {
    private static var cache: [String: NSImage] = [:]

    static func activeIcon(count: Int) -> NSImage {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let key = "\(count)@\(scale)"
        if let cached = cache[key] { return cached }

        let badge = HStack(spacing: 3) {
            Image(systemName: "powerplug.fill")
                .font(.system(size: 13, weight: .medium))
            Text("\(count)")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
        .foregroundStyle(Color(nsColor: .systemOrange))
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
}
