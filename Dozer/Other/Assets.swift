/// Asset catalog accessors.
///
/// This file replaces the output that SwiftGen used to generate. Committing it
/// keeps the build self-contained: only XcodeGen is required, no SwiftGen
/// install and no generated-file step.
enum Assets {
    enum helperStatusItemIcon {
        static let name = "HelperStatusItemIcon"
    }
}
