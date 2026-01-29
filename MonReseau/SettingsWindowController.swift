// SettingsWindowController.swift
// Mon Réseau
//
// Fenêtre de réglages proposant deux options :
//   1. Afficher/masquer l'icône dans le Dock (via NSApp.setActivationPolicy)
//   2. Lancer l'app au démarrage de session (via SMAppService.mainApp)
// Les préférences sont persistées dans UserDefaults (ShowInDock) et le système (Login Item).

import Cocoa
import ServiceManagement

class SettingsWindowController: NSWindowController {

    private var dockCheckbox: NSButton!
    private var loginCheckbox: NSButton!

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 200),
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

        let showInDock = UserDefaults.standard.bool(forKey: "ShowInDock")

        // --- Afficher dans le Dock ---
        dockCheckbox = NSButton(checkboxWithTitle: "Afficher dans le Dock", target: self, action: #selector(dockCheckboxChanged))
        dockCheckbox.translatesAutoresizingMaskIntoConstraints = false
        dockCheckbox.state = showInDock ? .on : .off
        dockCheckbox.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        contentView.addSubview(dockCheckbox)

        let dockDesc = NSTextField(wrappingLabelWithString: "L'application apparait dans le Dock comme une app classique en plus de la barre de menus.")
        dockDesc.translatesAutoresizingMaskIntoConstraints = false
        dockDesc.font = NSFont.systemFont(ofSize: 11)
        dockDesc.textColor = .secondaryLabelColor
        dockDesc.isSelectable = false
        contentView.addSubview(dockDesc)

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
            dockCheckbox.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 24),
            dockCheckbox.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            dockCheckbox.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -24),

            dockDesc.topAnchor.constraint(equalTo: dockCheckbox.bottomAnchor, constant: 4),
            dockDesc.leadingAnchor.constraint(equalTo: dockCheckbox.leadingAnchor, constant: 18),
            dockDesc.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),

            separator.topAnchor.constraint(equalTo: dockDesc.bottomAnchor, constant: 16),
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

    /// Bascule la politique d'activation de l'app entre .regular (Dock visible) et .accessory (barre de menus seule).
    @objc private func dockCheckboxChanged(_ sender: NSButton) {
        let showInDock = sender.state == .on
        UserDefaults.standard.set(showInDock, forKey: "ShowInDock")

        if showInDock {
            NSApp.setActivationPolicy(.regular)
        } else {
            NSApp.setActivationPolicy(.accessory)
            // Reactiver l'app pour garder le focus sur la fenetre reglages
            DispatchQueue.main.async {
                NSApp.activate(ignoringOtherApps: true)
            }
        }
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
