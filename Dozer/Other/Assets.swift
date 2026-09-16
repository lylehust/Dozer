import AppKit

/// Asset catalog accessors.
///
/// This file replaces the output that SwiftGen used to generate into the
/// gitignored `Dozer/Other/Generated/` directory. Committing it keeps the
/// build self-contained: only XcodeGen is required, no SwiftGen install.
enum Assets {
    enum helperStatusItemIcon {
        static let name = "HelperStatusItemIcon"
    }
}
