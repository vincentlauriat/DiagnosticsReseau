// SettingsWindowController.swift
// Mon Réseau
//
// Fenêtre de réglages proposant deux options :
//   1. Mode d'affichage : barre de menus ou application normale
//   2. Lancer l'app au démarrage de session (via SMAppService.mainApp)
// Les préférences sont persistées dans UserDefaults (AppMode) et le système (Login Item).

import Cocoa
import ServiceManagement

class SettingsWindowController: NSWindowController {

    private var modePopup: NSPopUpButton!
    private var loginCheckbox: NSButton!

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 220),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Mon Réseau — Réglages"
        window.center()
        window.isReleasedWhenClosed = false
        self.init(window: window)
        setupUI()
    }

    private func setupUI() {
        guard let contentView = window?.contentView else { return }

        let appDelegate = NSApp.delegate as? AppDelegate
        let currentMode = appDelegate?.currentMode ?? .menubar

        // --- Mode d'affichage ---
        let modeLabel = NSTextField(labelWithString: "Mode d'affichage :")
        modeLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        modeLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(modeLabel)

        modePopup = NSPopUpButton()
        modePopup.addItems(withTitles: ["Barre de menus", "Application"])
        modePopup.translatesAutoresizingMaskIntoConstraints = false
        modePopup.target = self
        modePopup.action = #selector(modeChanged)
        modePopup.selectItem(at: currentMode == .menubar ? 0 : 1)
        contentView.addSubview(modePopup)

        let modeDesc = NSTextField(wrappingLabelWithString: "Barre de menus : l'app vit dans la barre de menus avec une icône d'état.\nApplication : l'app apparaît dans le Dock avec une fenêtre d'accueil et une barre de menus classique.")
        modeDesc.translatesAutoresizingMaskIntoConstraints = false
        modeDesc.font = NSFont.systemFont(ofSize: 11)
        modeDesc.textColor = .secondaryLabelColor
        modeDesc.isSelectable = false
        contentView.addSubview(modeDesc)

        // --- Separator ---
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(separator)

        // --- Lancer au demarrage ---
        loginCheckbox = NSButton(checkboxWithTitle: "Lancer au démarrage", target: self, action: #selector(loginCheckboxChanged))
        loginCheckbox.translatesAutoresizingMaskIntoConstraints = false
        loginCheckbox.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        contentView.addSubview(loginCheckbox)

        // Lire l'etat actuel du Login Item
        let loginStatus = SMAppService.mainApp.status
        loginCheckbox.state = (loginStatus == .enabled) ? .on : .off

        let loginDesc = NSTextField(wrappingLabelWithString: "L'application se lance automatiquement à l'ouverture de session.")
        loginDesc.translatesAutoresizingMaskIntoConstraints = false
        loginDesc.font = NSFont.systemFont(ofSize: 11)
        loginDesc.textColor = .secondaryLabelColor
        loginDesc.isSelectable = false
        contentView.addSubview(loginDesc)

        NSLayoutConstraint.activate([
            modeLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 24),
            modeLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),

            modePopup.centerYAnchor.constraint(equalTo: modeLabel.centerYAnchor),
            modePopup.leadingAnchor.constraint(equalTo: modeLabel.trailingAnchor, constant: 8),
            modePopup.widthAnchor.constraint(equalToConstant: 160),

            modeDesc.topAnchor.constraint(equalTo: modeLabel.bottomAnchor, constant: 8),
            modeDesc.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            modeDesc.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),

            separator.topAnchor.constraint(equalTo: modeDesc.bottomAnchor, constant: 16),
            separator.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            separator.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),

            loginCheckbox.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 16),
            loginCheckbox.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            loginCheckbox.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -24),

            loginDesc.topAnchor.constraint(equalTo: loginCheckbox.bottomAnchor, constant: 4),
            loginDesc.leadingAnchor.constraint(equalTo: loginCheckbox.leadingAnchor, constant: 18),
            loginDesc.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            loginDesc.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -20),
        ])
    }

    /// Bascule le mode d'affichage de l'application.
    @objc private func modeChanged(_ sender: NSPopUpButton) {
        guard let appDelegate = NSApp.delegate as? AppDelegate else { return }
        let mode: AppDelegate.AppMode = sender.indexOfSelectedItem == 0 ? .menubar : .app
        appDelegate.applyMode(mode)
    }

    /// Enregistre ou désenregistre l'app comme Login Item via SMAppService (macOS 13+).
    @objc private func loginCheckboxChanged(_ sender: NSButton) {
        let enable = sender.state == .on
        do {
            if enable {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // En cas d'erreur, remettre la checkbox a l'etat precedent
            sender.state = enable ? .off : .on
            let alert = NSAlert()
            alert.messageText = "Impossible de modifier le lancement au démarrage"
            alert.informativeText = "L'application doit être dans le dossier Applications pour activer cette option.\n\nErreur : \(error.localizedDescription)"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            if let w = self.window { alert.beginSheetModal(for: w) }
        }
    }
}
