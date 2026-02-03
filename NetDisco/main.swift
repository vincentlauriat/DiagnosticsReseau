// main.swift
// Point d'entrée de l'application macOS utilisant AppKit.
// Ce fichier configure l'application, assigne un délégué, puis lance la boucle d'exécution.

import Cocoa

// AppKit pour macOS. `Cocoa` regroupe AppKit, Foundation et d'autres utilitaires nécessaires aux apps macOS.

// Récupère l'instance partagée de l'application (singleton) qui gère le cycle de vie et les événements.
let app = NSApplication.shared

// Crée le délégué d'application. `AppDelegate` doit implémenter `NSApplicationDelegate` pour réagir aux événements de l'app.
let delegate = AppDelegate()

// Associe le délégué à l'application afin de recevoir les callbacks du système (démarrage, fermeture, etc.).
app.delegate = delegate

// Démarre la boucle d'exécution (run loop) et affiche l'interface. Bloque jusqu'à la fermeture de l'app.
app.run()
