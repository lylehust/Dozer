/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import Cocoa
import Preferences
import KeyboardShortcuts
import LaunchAtLogin
import Sparkle
import Defaults

final class General: NSViewController, PreferencePane {
    let preferencePaneIdentifier = Preferences.PaneIdentifier.general
    let preferencePaneTitle: String = "General"
    let toolbarItemIcon = NSImage(named: NSImage.preferencesGeneralName)!

    override var nibName: NSNib.Name? { "General" }

    /// The single updater owned by `AppDelegate`. Do not create a second
    /// `SPUStandardUpdaterController` here, Sparkle expects one per process.
    private var updaterController: SPUStandardUpdaterController {
        AppDelegate.shared.sparkleUpdaterController
    }

    private var defaultsObserver: NSObjectProtocol?

    @IBOutlet private var LaunchAtLoginCheckbox: NSButton!
    @IBOutlet private var CheckForUpdatesCheckbox: NSButton!
    @IBOutlet private var HideStatusBarIconsAtLaunchCheckbox: NSButton!
    @IBOutlet private var HideStatusBarIconsAfterDelayCheckbox: NSButton!
    @IBOutlet private var HideStatusBarIconsSecondsPopUpButton: NSPopUpButton!
    @IBOutlet private var HideBothDozerIconsCheckbox: NSButton!
    @IBOutlet private var EnableRemoveDozerIconCheckbox: NSButton!
    @IBOutlet private var ShowIconAndMenuCheckbox: NSButton!
    @IBOutlet private var FontSizePopUpButton: NSPopUpButton!
    @IBOutlet private var ButtonPaddingPopUpButton: NSPopUpButton!

    override func viewDidLoad() {
        super.viewDidLoad()

        LaunchAtLoginCheckbox.focusRingType = .none

        LaunchAtLoginCheckbox.isChecked = LaunchAtLogin.isEnabled
        CheckForUpdatesCheckbox.isChecked = updaterController.updater.automaticallyChecksForUpdates

        HideStatusBarIconsAtLaunchCheckbox.isChecked = Defaults[.hideAtLaunchEnabled]
        HideStatusBarIconsAfterDelayCheckbox.isChecked = Defaults[.hideAfterDelayEnabled]
        HideBothDozerIconsCheckbox.isChecked = Defaults[.noIconMode]
        EnableRemoveDozerIconCheckbox.isChecked = Defaults[.removeDozerIconEnabled]
        ShowIconAndMenuCheckbox.isChecked = Defaults[.showIconAndMenuEnabled]
        HideStatusBarIconsSecondsPopUpButton.selectItem(withTitle: "\(Int(Defaults[.hideAfterDelay])) seconds")
        FontSizePopUpButton.selectItem(withTitle: "\(Int(Defaults[.iconSize])) px")
        ButtonPaddingPopUpButton.selectItem(withTitle: "\(Int(Defaults[.buttonPadding])) px")

        addKeyboardShortcutRecorder()
        configureEnabledNoIconCheckbox()

        // KeyboardShortcuts persists into UserDefaults, so observe that store to
        // keep the "hide both icons" checkbox in sync. The guard inside
        // `configureEnabledNoIconCheckbox` stops this from re-entering itself,
        // which is what used to crash on modern macOS.
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.configureEnabledNoIconCheckbox()
        }
    }

    deinit {
        if let defaultsObserver {
            NotificationCenter.default.removeObserver(defaultsObserver)
        }
    }

    /// Installs the shortcut recorder into the slot that the old
    /// `MASShortcutView` occupied in General.xib.
    private func addKeyboardShortcutRecorder() {
        let recorder = KeyboardShortcuts.RecorderCocoa(for: .toggleMenuItems)
        recorder.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(recorder)

        NSLayoutConstraint.activate([
            recorder.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            recorder.widthAnchor.constraint(equalToConstant: 105),
            // Vertically centred on the "Show/hide menu bar icons" label,
            // which sits at y = 17...34 in the nib.
            recorder.centerYAnchor.constraint(equalTo: view.bottomAnchor, constant: -25)
        ])
    }

    @IBAction private func launchAtLoginClicked(_ sender: NSButton) {
        LaunchAtLogin.isEnabled = (sender.state == .on)
    }

    @IBAction private func automaticallyCheckForUpdatesClicked(_ sender: NSButton) {
        updaterController.updater.automaticallyChecksForUpdates = (sender.state == .on)
        CheckForUpdatesCheckbox.isChecked = updaterController.updater.automaticallyChecksForUpdates
    }

    @IBAction private func hideStatusBarIconsAtLaunchClicked(_ sender: NSButton) {
        DozerIcons.shared.hideStatusBarIconsAtLaunch = HideStatusBarIconsAtLaunchCheckbox.isChecked
    }

    @IBAction private func hideStatusBarIconsAfterDelayClicked(_ sender: NSButton) {
        DozerIcons.shared.hideStatusBarIconsAfterDelay = HideStatusBarIconsAfterDelayCheckbox.isChecked
    }

    @IBAction private func hideStatusBarIconsSecondsUpdated(_ sender: NSPopUpButton) {
        Defaults[.hideAfterDelay] = TimeInterval(HideStatusBarIconsSecondsPopUpButton.selectedTag())
        DozerIcons.shared.resetTimer()
    }

    @IBAction private func hideBothDozerIconsClicked(_ sender: NSButton) {
        DozerIcons.shared.hideBothDozerIcons = HideBothDozerIconsCheckbox.isChecked
    }

    @IBAction private func showIconAndMenuClicked(_ sender: NSButton) {
        DozerIcons.shared.enableIconAndMenu = ShowIconAndMenuCheckbox.isChecked
    }

    @IBAction private func fontSizeChanged(_ sender: NSPopUpButton) {
        DozerIcons.shared.iconFontSize = FontSizePopUpButton.selectedTag()
    }

    @IBAction private func buttonPaddingChanged(_ sender: NSPopUpButton) {
        DozerIcons.shared.buttonPadding = CGFloat(ButtonPaddingPopUpButton.selectedTag())
    }

    @IBAction private func enableRemoveDozerIconClicked(_ sender: NSButton) {
        DozerIcons.shared.enableRemoveDozerIcon = EnableRemoveDozerIconCheckbox.isChecked
    }

    /// Disables the noIcon-checkbox if no shortcut is set and keeps track whether a shortcut is set.
    private func configureEnabledNoIconCheckbox() {
        let hasShortcut = KeyboardShortcuts.getShortcut(for: .toggleMenuItems) != nil
        HideBothDozerIconsCheckbox.isEnabled = hasShortcut
        // Only write when the value actually changes, otherwise this observer
        // would retrigger itself through UserDefaults.didChangeNotification.
        if Defaults[.isShortcutSet] != hasShortcut {
            Defaults[.isShortcutSet] = hasShortcut
        }
    }
}
