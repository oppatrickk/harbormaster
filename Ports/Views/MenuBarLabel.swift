import SwiftUI

/// The status-item icon: an outline plug when nothing is listening, a filled plug plus a
/// count when ports are active.
///
/// Both states are template images, so macOS tints them to match the menu bar — black on a
/// light menu bar, white on a dark one — and inverts them while the menu is open, the same
/// as every built-in status item.
struct MenuBarLabel: View {
    let count: Int

    var body: some View {
        if count == 0 {
            Image(systemName: "powerplug")
                .accessibilityLabel("Ports: none active")
        } else {
            Image(nsImage: MenuBarIconRenderer.activeIcon(count: count))
                .accessibilityLabel("Ports: \(count) active")
        }
    }
}

/// Renders the plug-plus-count badge to a template `NSImage`.
///
/// The count has to be drawn into the image rather than passed as a separate `Text`, because
/// a MenuBarExtra label renders a single status item. Marking the result as a template means
/// only its alpha channel is used, so the system supplies the color and the icon stays
/// legible against either menu bar appearance.
///
/// Results are cached per (count, scale) because the label re-evaluates on every refresh tick.
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
            Text(verbatim: String(count))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
        // Drawn opaque black purely to produce a clean alpha mask; the color is discarded
        // once the image is marked as a template.
        .foregroundStyle(.black)
        .padding(.horizontal, 1)

        let renderer = ImageRenderer(content: badge)
        renderer.scale = scale

        guard let image = renderer.nsImage else {
            // Fall back to the plain symbol rather than showing nothing at all.
            let fallback = NSImage(
                systemSymbolName: "powerplug.fill",
                accessibilityDescription: "Ports: \(count) active"
            ) ?? NSImage()
            fallback.isTemplate = true
            return fallback
        }

        image.isTemplate = true
        cache[key] = image
        return image
    }
}
