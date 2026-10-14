import Cocoa

/// Bundle.module.image(forResource:) does not resolve subpath-qualified
/// names like "Keycaps/k01" (confirmed empirically: it returns nil for
/// all 55 keycap/annunciator images, since .copy("Resources/Keycaps")
/// preserves the Keycaps/ subdirectory inside the built bundle). The
/// URL-based lookup with an explicit `subdirectory:` does resolve it.
enum KeycapImages {
    static func load(_ name: String) -> NSImage? {
        guard let url = Bundle.module.url(forResource: name, withExtension: "png", subdirectory: "Keycaps") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }
}
