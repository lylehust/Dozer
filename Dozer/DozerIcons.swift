/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import Cocoa
import Defaults

public final class DozerIcons {
    static var shared = DozerIcons()
    private var dozerIcons: [HelperstatusIcon] = []
    private var timerToCheckUserInteraction: Timer?
    private var timerToHideDozerIcons: Timer?
    private var previousApp = NSRunningApplication()

    /// Process name as it appears in `kCGWindowOwnerName`.
    private static let ownerName = ProcessInfo.processInfo.processName

    private init() {
        dozerIcons.append(NormalStatusIcon())

        if !hideBothDozerIcons  || !Defaults[.isShortcutSet] {
            dozerIcons.append(NormalStatusIcon())
        }

        if enableRemoveDozerIcon {
            dozerIcons.append(RemoveStatusIcon())
        }

        if hideStatusBarIconsAfterDelay {
            startTimer()
        }

        Defaults.observe(.isShortcutSet) { change in
            self.triggerHideBothDozerIcons()
        }
        .tieToLifetime(of: self)
    }

    private func startUserInteractionTimer() {
        // Always invalidate the previous timer first. `Timer.scheduledTimer`
        // makes the run loop retain the timer, so merely overwriting the stored
        // reference would orphan it: it would keep firing every 0.5s for the
        // lifetime of the process and could never be invalidated. Since each
        // tick enumerates every on-screen window, leaked timers compound into
        // steadily rising CPU and memory use.
        stopUserInteractionTimer()

        guard Defaults[.hideAfterDelayEnabled] else {
            return
        }

        timerToCheckUserInteraction = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            if self.isUserInteractingWithStatusBar() {
                self.resetTimer()
            }
        }
    }

    private func stopUserInteractionTimer() {
        timerToCheckUserInteraction?.invalidate()
        timerToCheckUserInteraction = nil
    }

    // MARK: Observe changes to settings
    public var hideStatusBarIconsAtLaunch: Bool = Defaults[.hideAtLaunchEnabled] {
        didSet {
            Defaults[.hideAtLaunchEnabled] = self.hideStatusBarIconsAtLaunch
        }
    }

    public var hideStatusBarIconsAfterDelay: Bool = Defaults[.hideAfterDelayEnabled] {
        didSet {
            Defaults[.hideAfterDelayEnabled] = self.hideStatusBarIconsAfterDelay
            if hideStatusBarIconsAfterDelay {
                startTimer()
            } else {
                stopTimer()
            }
        }
    }

    public var hideBothDozerIcons: Bool = Defaults[.noIconMode] {
        didSet {
            Defaults[.noIconMode] = self.hideBothDozerIcons
            triggerHideBothDozerIcons()
        }
    }

    public func triggerHideBothDozerIcons() {
        let normalStatusIconsCount = dozerIcons.filter { $0.type == .normal}.count
        if hideBothDozerIcons && Defaults[.isShortcutSet] {
            if normalStatusIconsCount == 2 {
                // Remove by identity. Comparing on-screen x positions was
                // unreliable: an icon whose window is not on screen used to
                // report 0, so the wrong icon could be removed.
                if let rightDozerIcon = get(dozerIcon: .normalRight) {
                    dozerIcons.removeAll { $0 === rightDozerIcon }
                }
            }
        } else if !hideBothDozerIcons && Defaults[.isShortcutSet] || !Defaults[.isShortcutSet] {
            if normalStatusIconsCount == 1 {
                show()
                dozerIcons.append(NormalStatusIcon())
            }
        }
        show()
    }

    public var enableRemoveDozerIcon: Bool = Defaults[.removeDozerIconEnabled] {
        didSet {
            Defaults[.removeDozerIconEnabled] = self.enableRemoveDozerIcon
            if enableRemoveDozerIcon {
                dozerIcons.append(RemoveStatusIcon())
            } else {
                dozerIcons.removeAll { $0.type == .remove }
            }
            showAll()
        }
    }

    public var enableIconAndMenu: Bool = Defaults[.showIconAndMenuEnabled] {
        didSet {
            Defaults[.showIconAndMenuEnabled] = self.enableIconAndMenu
            if self.enableIconAndMenu == false {
                _ = DozerIcons.toggleDockIcon(showIcon: false)
                AppDelegate.shared.preferencesWindowController.show(preferencePane: .general)
            }
        }
    }

    public var iconFontSize: Int = Defaults[.iconSize] {
        didSet {
            Defaults[.iconSize] = self.iconFontSize
            for icon in dozerIcons {
                icon.setSize()
            }
        }
    }

    public var buttonPadding: CGFloat = Defaults[.buttonPadding] {
        didSet {
            Defaults[.buttonPadding] = self.buttonPadding
            for icon in dozerIcons {
                icon.setSize()
            }
        }
    }

    // MARK: Public methods
    public func hide() {
        perform(action: .hide, statusIcon: .remove)
        perform(action: .hide, statusIcon: .normalLeft)
        if Defaults[.noIconMode] && Defaults[.isShortcutSet] {
            perform(action: .hide, statusIcon: .normalRight)
        }
        didHideStatusBarIcons()
        hideIconAndMenu()
    }

    public func hideAtLaunch() {
        if hideStatusBarIconsAtLaunch {
            if #available(macOS 11.0, *) {
                Timer.scheduledTimer(withTimeInterval: 0.15, repeats: false) { _ in
                   self.hide()
                }
            } else {
                self.hide()
            }
        }
    }

    public func show() {
        resetTimer()
        perform(action: .hide, statusIcon: .remove)
        perform(action: .show, statusIcon: .normalLeft)
        if Defaults[.noIconMode] {
            perform(action: .show, statusIcon: .normalRight)
        }
        didShowStatusBarIcons()
        showIconAndMenu()
    }

    public func toggle() {
        if get(dozerIcon: .normalLeft)?.isShown == true {
            hide()
        } else {
            show()
        }
    }

    public func toggleRemove() {
        if get(dozerIcon: .remove)?.isShown == true {
            perform(action: .hide, statusIcon: .remove)
        } else {
            perform(action: .show, statusIcon: .remove)
        }
    }

    public func showIconAndMenu() {
        if let frontmostApp = NSWorkspace.shared.frontmostApplication,
           frontmostApp.bundleIdentifier != AppInfo.bundleIdentifier {
            previousApp = frontmostApp
        }
        if Defaults[.showIconAndMenuEnabled] {
            _ = DozerIcons.toggleDockIcon(showIcon: true)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    public func hideIconAndMenu() {
        if Defaults[.showIconAndMenuEnabled] {
            _ = DozerIcons.toggleDockIcon(showIcon: false)
            if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == AppInfo.bundleIdentifier {
                previousApp.activate()
            }
        }
    }

    /// Force show all Dozer icons
    public func showAll() {
        perform(action: .show, statusIcon: .remove)
        perform(action: .show, statusIcon: .normalLeft)
        perform(action: .show, statusIcon: .normalRight)
        didShowStatusBarIcons()
    }

    public func handleOptionClick() {
        showIconAndMenu()
        if get(dozerIcon: .normalLeft)?.isShown == true {
            DozerIcons.shared.perform(
                action: .toggle,
                statusIcon: .remove
            )
        } else {
            DozerIcons.shared.perform(
                action: .show,
                statusIcon: .normalLeft
            )
            DozerIcons.shared.perform(
                action: .show,
                statusIcon: .remove
            )
        }
        stopUserInteractionTimer()
        startUserInteractionTimer()
        resetTimer()
    }

    // MARK: Show/hide lifecycle
    private func didShowStatusBarIcons() {
        //startTimer()
        startUserInteractionTimer()
    }

    private func didHideStatusBarIcons() {
        stopTimer()
        stopUserInteractionTimer()
    }

    private func willHideStatusBarIcons() {
        guard Defaults[.hideAfterDelayEnabled] else {
            return
        }

        // don't hide on user interaction with menu bar
        guard !isUserInteractingWithStatusBar() else {
            resetTimer()
            return
        }

        DozerIcons.shared.hide()
    }

    // MARK: timerToHideDozerIcons methods
    private func startTimer() {
        stopTimer()

        guard Defaults[.hideAfterDelayEnabled] else {
            return
        }

        timerToHideDozerIcons = Timer.scheduledTimer(withTimeInterval: Defaults[.hideAfterDelay], repeats: false) { [weak self] (_: Timer) -> Void in
            self?.willHideStatusBarIcons()
        }
    }

    private func stopTimer() {
        timerToHideDozerIcons?.invalidate()
        timerToHideDozerIcons = nil
    }

    func resetTimer() {
        self.stopTimer()
        self.startTimer()
    }

    // MARK: Private methods
    /// Will fail silently if statusIcon does not exist
    private func perform(action: StatusIconAction, statusIcon: DozerIcon) {
        if statusIcon == .remove {
            guard Defaults[.removeDozerIconEnabled] else {
                return
            }
        }
        guard let theStatusIcon = get(dozerIcon: statusIcon) else {
            return
        }
        switch action {
        case .show:
            theStatusIcon.show()
        case .hide:
            theStatusIcon.hide()
        case .toggle:
            theStatusIcon.toggle()
        }
    }

    /// Normal icons whose on-screen position is currently known.
    ///
    /// `xPositionOnScreen` is `nil` when a status item has no window, which
    /// happens while an icon is hidden or during a display/menu-bar change.
    /// Excluding those keeps left/right selection deterministic instead of
    /// matching whichever icons happen to report 0.
    private var positionedNormalIcons: [HelperstatusIcon] {
        dozerIcons.filter { $0.type == .normal && $0.xPositionOnScreen != nil }
    }

    /// Returns the requested status icon, or `nil` when it is not currently in
    /// the menu bar. Callers tolerate `nil` so that a transient missing status
    /// item is a no-op rather than a crash.
    private func get(dozerIcon: DozerIcon) -> HelperstatusIcon? {
        switch dozerIcon {
        case .remove:
            return dozerIcons.first { $0.type == .remove }
        case .normalLeft:
            return positionedNormalIcons.min { ($0.xPositionOnScreen ?? 0) < ($1.xPositionOnScreen ?? 0) }
        case .normalRight:
            return positionedNormalIcons.max { ($0.xPositionOnScreen ?? 0) < ($1.xPositionOnScreen ?? 0) }
        }
    }

    /// hide and show dock icon and thus its menu bar: to free up space to show more menu bar icons
    public class func toggleDockIcon(showIcon state: Bool) -> Bool {
        if state {
            return NSApp.setActivationPolicy(NSApplication.ActivationPolicy.regular)
        } else {
            return NSApp.setActivationPolicy(NSApplication.ActivationPolicy.accessory)
        }
    }

    /// Determines if the user is interacting with the menu bar based on level, owner and y-coordinate
    ///
    /// - Returns: Returns whether the user is interacting with the menu bar or not
    private func isUserInteractingWithStatusBar() -> Bool {
        let windowListType = CGWindowListOption.optionOnScreenOnly
        guard let windowInfoList = CGWindowListCopyWindowInfo(windowListType, kCGNullWindowID) as NSArray? as? [[String: AnyObject]] else {
            return false
        }
        var statusBarAppsWindowInfo: [Window] = []

        for windowInfo in windowInfoList {
            guard let window = Window(windowInfo),
                // If the preferences window are close to the menu bar it won't auto hide
                window.owner != DozerIcons.ownerName else {
                    continue
            }

            if window.isStatusIcon {
                statusBarAppsWindowInfo.append(window)
            }
        }

        for windowInfo in windowInfoList {
            guard let window = Window(windowInfo) else { continue }
            guard window.isStatusIcon == false else { continue }

            for statusBarApp in statusBarAppsWindowInfo {
                guard statusBarApp.owner == window.owner else { continue }
                guard (statusBarApp.y + statusBarApp.height...statusBarApp.y + statusBarApp.height + 15).contains(window.y) else { continue }

                return true
            }
        }

        return false
    }

    /// Wrapper class for CGWindowList
    private class Window {
        var x: Int = 0
        var y: Int = 0
        var width: Int = 0
        var height: Int = 0

        var level: Int
        var owner: String

        init?(_ windowInfo: [String: AnyObject]) {
            guard let level = windowInfo[kCGWindowLayer as String] as? Int else {
                return nil
            }
            guard let owner = windowInfo[kCGWindowOwnerName as String] as? String else {
                return nil
            }

            self.level = level
            self.owner = owner

            let bounds: [String: Int] = windowInfo[kCGWindowBounds as String] as! [String: Int]
            for item in bounds {
                switch item.key {
                case "X":
                    x = item.value
                case "Y":
                    y = item.value
                case "Width":
                    width = item.value
                case "Height":
                    height = item.value
                default:
                    continue
                }
            }
        }

        /// Status item windows live at window level 25 inside the menu bar.
        ///
        /// Their height tracks the menu bar height, which Apple has grown over
        /// time: it was 22pt historically, and macOS 26 "Tahoe" draws a taller
        /// bar. Hardcoding `height == 22` (as Dozer 4.x did) makes this
        /// detection fail on modern systems, which in turn breaks auto-hide
        /// (the app can no longer tell that the user is interacting with a
        /// status item). Accept a range instead, whose upper bound is derived
        /// from the live menu bar thickness so future releases keep working.
        var isStatusIcon: Bool {
            guard level == 25 else {
                return false
            }
            return (Window.minStatusIconHeight...Window.maxStatusIconHeight).contains(height)
        }

        /// A status item is at least as tall as the classic 22pt menu bar.
        static let minStatusIconHeight = 22

        /// Upper bound. 37 is the value verified against macOS 26 (Tahoe);
        /// anything taller is derived from the current menu bar thickness.
        ///
        /// Computed rather than cached: the menu bar can change height when the
        /// user moves to a different display, and a `static let` would freeze
        /// the first value read for the lifetime of the process.
        static var maxStatusIconHeight: Int {
            let menuBarThickness = Int(NSStatusBar.system.thickness.rounded(.up))
            return max(37, menuBarThickness + 16)
        }
    }
}
