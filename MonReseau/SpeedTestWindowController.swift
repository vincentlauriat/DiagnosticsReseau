// SpeedTestWindowController.swift
// Fenetre de test de debit via HTTP (Cloudflare). Mesure download, upload et latence.
// Comprend: modeles de resultat/historique, stockage UserDefaults (max 50 entrees),
// service de localisation (CoreLocation + fallback IP via ipapi.co), et vue d'animation (CVDisplayLink).
// Aucun appel shell — entierement compatible App Store.

import Cocoa
import CoreLocation
import UniformTypeIdentifiers

// CoreLocation pour obtenir une localisation (ville/pays) a associer aux mesures

// MARK: - Speed Test Result Model

/// Résultat d'un test de débit (Mbps down/up, latence, RPM).
struct SpeedTestResult {
    let downloadMbps: Double
    let uploadMbps: Double
    let latencyMs: Double
    let rpm: Int  // Responsiveness Per Minute
}

// MARK: - History Model

/// Entrée d'historique persistée (Codable).
struct SpeedTestHistoryEntry: Codable {
    let id: UUID
    let date: Date
    let downloadMbps: Double
    let uploadMbps: Double
    let latencyMs: Double
    let rpm: Int
    let location: String
    let isFallback: Bool

    init(result: SpeedTestResult, location: String, isFallback: Bool) {
        self.id = UUID()
        self.date = Date()
        self.downloadMbps = result.downloadMbps
        self.uploadMbps = result.uploadMbps
        self.latencyMs = result.latencyMs
        self.rpm = result.rpm
        self.location = location
        self.isFallback = isFallback
    }
}

// MARK: - History Storage (UserDefaults - sandbox compatible)

/// Persistance simple de l'historique dans UserDefaults (max 50 entrées).
class SpeedTestHistoryStorage {
    private static let key = "SpeedTestHistory"
    private static let maxEntries = 50

    static func setup() {
        // No special setup needed
    }

    static func load() -> [SpeedTestHistoryEntry] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let entries = try? JSONDecoder().decode([SpeedTestHistoryEntry].self, from: data) else {
            return []
        }
        return entries
    }

    static func save(_ entries: [SpeedTestHistoryEntry]) {
        let trimmed = Array(entries.prefix(maxEntries))
        if let data = try? JSONEncoder().encode(trimmed) {
            UserDefaults.standard.set(data, forKey: key)
            // Notifier les observateurs que l'historique a changé
            NotificationCenter.default.post(name: .speedTestHistoryDidChange, object: nil)
        }
    }

    static func add(_ entry: SpeedTestHistoryEntry) {
        var entries = load()
        entries.insert(entry, at: 0)
        save(entries)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
        // Notifier les observateurs que l'historique a été effacé
        NotificationCenter.default.post(name: .speedTestHistoryDidChange, object: nil)
    }
}

// Notification interne pour synchroniser l'historique entre vues/fenetres
extension Notification.Name {
    static let speedTestHistoryDidChange = Notification.Name("speedTestHistoryDidChange")
}

// MARK: - Location Service

/// Service de localisation: GPS si autorisé, sinon géolocalisation IP (ip-api.com).
class LocationService: NSObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    private var completion: ((String) -> Void)?
    private var hasResult = false
    private var requestID = 0

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    // Demande la localisation: si autorisation pas encore donnee, la demande est faite
    // si autorisation ok, on demande la localisation GPS
    // sinon on fait fallback sur geolocalisation IP
    // timeout a 5s pour ne pas bloquer indefiniment
    func getLocation(completion: @escaping (String) -> Void) {
        requestID += 1
        let currentRequestID = requestID
        self.completion = completion
        self.hasResult = false

        // Check authorization
        let status = locationManager.authorizationStatus
        if status == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        } else if status == .authorized || status == .authorizedAlways {
            locationManager.requestLocation()
        } else {
            // Fallback to IP geolocation
            getIPLocation()
        }

        // Timeout after 5 seconds - fallback to IP if no GPS result
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self = self, !self.hasResult, self.requestID == currentRequestID else { return }
            self.hasResult = true
            self.getIPLocation()
        }
    }

    // Delegate called when authorization changes; request location if authorized,
    // else fallback to IP geolocation
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        if status == .authorized || status == .authorizedAlways {
            manager.requestLocation()
        } else if status == .denied || status == .restricted {
            getIPLocation()
        }
    }

    // Delegate called with location updates; reverse geocode to city,country string
    // Only first location used, then completion called.
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard !hasResult, let location = locations.first else { return }
        hasResult = true

        let geocoder = CLGeocoder()
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, error in
            guard let self = self else { return }

            if let placemark = placemarks?.first {
                let city = placemark.locality ?? ""
                let country = placemark.country ?? ""
                let locationStr = [city, country].filter { !$0.isEmpty }.joined(separator: ", ")
                self.completion?(locationStr.isEmpty ? "Position inconnue" : locationStr)
            } else {
                self.completion?("Position inconnue")
            }
        }
    }

    // Delegate called on failure to get location; fallback to IP geolocation once.
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard !hasResult else { return }
        hasResult = true
        getIPLocation()
    }

    // Fallback: geolocalisation IP via ipapi.co (HTTPS)
    private func getIPLocation() {
        guard let url = URL(string: "https://ipapi.co/json/") else {
            completion?("Lieu inconnu")
            return
        }

        var request = URLRequest(url: url, timeoutInterval: 5)
        request.setValue("MonReseau/1.0", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            DispatchQueue.main.async {
                guard let self = self else { return }

                if let data = data,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    let city = json["city"] as? String ?? ""
                    let country = json["country_name"] as? String ?? ""
                    let locationStr = [city, country].filter { !$0.isEmpty }.joined(separator: ", ")
                    self.completion?(locationStr.isEmpty ? "Lieu inconnu" : locationStr)
                } else {
                    self.completion?("Lieu inconnu")
                }
            }
        }.resume()
    }
}

// MARK: - Animation View

/// Vue d'animation décorative pendant le test (ondes + particules).
class SpeedTestAnimationView: NSView {

    private var displayLink: CVDisplayLink?
    private var phase: CGFloat = 0
    private var waveAmplitudes: [CGFloat] = [1.0, 0.7, 0.5]
    private var isAnimating = false
    private var particles: [(x: CGFloat, y: CGFloat, speed: CGFloat, size: CGFloat)] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupParticles()
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupParticles()
    }

    private func setupParticles() {
        for _ in 0..<20 {
            particles.append((
                x: CGFloat.random(in: 0...1),
                y: CGFloat.random(in: 0...1),
                speed: CGFloat.random(in: 0.005...0.015),
                size: CGFloat.random(in: 2...6)
            ))
        }
    }

    // Demarre la boucle d'animation a l'aide d'un CVDisplayLink
    func startAnimating() {
        isAnimating = true
        createDisplayLink()
    }

    // Arrete la boucle d'animation et invalide le displayLink
    func stopAnimating() {
        isAnimating = false
        if let displayLink = displayLink {
            CVDisplayLinkStop(displayLink)
            self.displayLink = nil
        }
    }

    // Cree un CVDisplayLink pour appeler updateAnimation a chaque rafraichissement ecran (~60Hz)
    private func createDisplayLink() {
        CVDisplayLinkCreateWithActiveCGDisplays(&displayLink)
        guard let displayLink = displayLink else { return }

        let callback: CVDisplayLinkOutputCallback = { _, _, _, _, _, userInfo in
            let view = Unmanaged<SpeedTestAnimationView>.fromOpaque(userInfo!).takeUnretainedValue()
            DispatchQueue.main.async {
                view.updateAnimation()
            }
            return kCVReturnSuccess
        }

        CVDisplayLinkSetOutputCallback(displayLink, callback, Unmanaged.passUnretained(self).toOpaque())
        CVDisplayLinkStart(displayLink)
    }

    // Met a jour les positions des particules et phase d'onde, puis demande redraw
    private func updateAnimation() {
        guard isAnimating else { return }
        phase += 0.05

        for i in 0..<particles.count {
            particles[i].x += particles[i].speed
            if particles[i].x > 1.2 {
                particles[i].x = -0.2
                particles[i].y = CGFloat.random(in: 0.2...0.8)
            }
        }

        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let rect = bounds

        // Background gradient (adaptatif clair/sombre)
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let colors = isDark ? [
            NSColor(calibratedRed: 0.1, green: 0.1, blue: 0.2, alpha: 1.0).cgColor,
            NSColor(calibratedRed: 0.05, green: 0.1, blue: 0.15, alpha: 1.0).cgColor
        ] : [
            NSColor(calibratedRed: 0.85, green: 0.9, blue: 0.98, alpha: 1.0).cgColor,
            NSColor(calibratedRed: 0.92, green: 0.95, blue: 1.0, alpha: 1.0).cgColor
        ]
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 1])!
        context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: rect.height), end: CGPoint(x: 0, y: 0), options: [])

        // Waves
        let waveColors: [NSColor] = [.systemCyan, .systemBlue, .systemTeal]
        for (i, amplitude) in waveAmplitudes.enumerated() {
            drawWave(in: rect, context: context, amplitude: amplitude * 15, frequency: 0.02 + CGFloat(i) * 0.01, phaseOffset: phase + CGFloat(i) * 0.5, color: waveColors[i].withAlphaComponent(0.4))
        }

        // Particles floating over waves
        for particle in particles {
            let x = particle.x * rect.width
            let y = particle.y * rect.height + sin(phase * 2 + particle.x * 10) * 10
            let alpha = min(1.0, particle.x * 2) * min(1.0, (1.2 - particle.x) * 2)

            context.setFillColor(NSColor.systemCyan.withAlphaComponent(alpha * 0.8).cgColor)
            context.fillEllipse(in: CGRect(x: x - particle.size/2, y: y - particle.size/2, width: particle.size, height: particle.size))

            context.setFillColor(NSColor.systemCyan.withAlphaComponent(alpha * 0.2).cgColor)
            context.fillEllipse(in: CGRect(x: x - particle.size, y: y - particle.size, width: particle.size * 2, height: particle.size * 2))
        }

        // Animated speed arrows
        drawSpeedArrows(in: rect, context: context)
    }

    // Dessine une onde sinusoïdale avec une amplitude, frequence, phase et couleur données
    private func drawWave(in rect: NSRect, context: CGContext, amplitude: CGFloat, frequency: CGFloat, phaseOffset: CGFloat, color: NSColor) {
        let path = CGMutablePath()
        let centerY = rect.height / 2

        path.move(to: CGPoint(x: 0, y: centerY))

        for x in stride(from: 0, to: rect.width, by: 2) {
            let y = centerY + sin(x * frequency + phaseOffset) * amplitude
            path.addLine(to: CGPoint(x: x, y: y))
        }

        path.addLine(to: CGPoint(x: rect.width, y: 0))
        path.addLine(to: CGPoint(x: 0, y: 0))
        path.closeSubpath()

        context.setFillColor(color.cgColor)
        context.addPath(path)
        context.fillPath()
    }

    // Dessine plusieurs fleches animées pour simuler le debit descendant
    private func drawSpeedArrows(in rect: NSRect, context: CGContext) {
        let arrowCount = 5
        let spacing = rect.width / CGFloat(arrowCount + 1)

        for i in 1...arrowCount {
            let baseX = spacing * CGFloat(i)
            let offset = (phase * 20).truncatingRemainder(dividingBy: spacing)
            let x = baseX + offset - spacing
            let y = rect.height / 2

            let alpha = sin((x / rect.width) * .pi)
            if alpha > 0 {
                drawArrow(at: CGPoint(x: x, y: y), context: context, alpha: alpha)
            }
        }
    }

    // Dessine une fleche simple orientee vers la droite avec alpha pour la transparence
    private func drawArrow(at point: CGPoint, context: CGContext, alpha: CGFloat) {
        let size: CGFloat = 12

        context.saveGState()
        context.translateBy(x: point.x, y: point.y)

        let path = CGMutablePath()
        path.move(to: CGPoint(x: -size, y: -size/2))
        path.addLine(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: -size, y: size/2))

        let arrowColor: NSColor = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .white : .black
        context.setStrokeColor(arrowColor.withAlphaComponent(alpha * 0.6).cgColor)
        context.setLineWidth(2)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.addPath(path)
        context.strokePath()

        context.restoreGState()
    }

    deinit {
        stopAnimating()
    }
}

// MARK: - Window Controller

/// Contrôleur de fenêtre du test de débit: UI, lancement de test, résultats et historique.
class SpeedTestWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {

    private var startButton: NSButton!
    private var historyButton: NSButton!
    private var progressIndicator: NSProgressIndicator!
    private var statusLabel: NSTextField!
    private var locationLabel: NSTextField!
    private var animationView: SpeedTestAnimationView!
    private var downloadLabel: NSTextField!
    private var uploadLabel: NSTextField!
    private var latencyLabel: NSTextField!
    private var rpmLabel: NSTextField!
    private var qualityLabel: NSTextField!
    private var resultsBox: NSBox!
    private var historyBox: NSBox!
    private var historyTableView: NSTableView!
    private var clearHistoryButton: NSButton!
    private var isRunning = false

    private let locationService = LocationService()
    private var currentLocation = "Localisation..."
    private var history: [SpeedTestHistoryEntry] = []

    private let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .short
        df.timeStyle = .short
        return df
    }()

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Mon Réseau — Test de débit"
        window.center()
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 450, height: 500)

        self.init(window: window)
        setupUI()
        setupiCloudSync()
        loadHistory()
    }

    private func setupiCloudSync() {
        SpeedTestHistoryStorage.setup()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(historyDidChangeExternally),
            name: .speedTestHistoryDidChange,
            object: nil
        )
    }

    @objc private func historyDidChangeExternally() {
        loadHistory()
    }

    private func setupUI() {
        guard let contentView = window?.contentView else { return }
        contentView.wantsLayer = true

        // Title
        let titleLabel = NSTextField(labelWithString: "Test de débit")
        titleLabel.font = NSFont.systemFont(ofSize: 18, weight: .semibold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(titleLabel)

        // Location label
        locationLabel = NSTextField(labelWithString: "Localisation...")
        locationLabel.font = NSFont.systemFont(ofSize: 11)
        locationLabel.textColor = .tertiaryLabelColor
        locationLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(locationLabel)

        // Animation view (sous la localisation)
        animationView = SpeedTestAnimationView()
        animationView.translatesAutoresizingMaskIntoConstraints = false
        animationView.wantsLayer = true
        animationView.layer?.cornerRadius = 8
        animationView.layer?.masksToBounds = true
        animationView.isHidden = true
        contentView.addSubview(animationView)

        // Status label
        statusLabel = NSTextField(labelWithString: "Cliquez sur le bouton pour lancer le test")
        statusLabel.font = NSFont.systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(statusLabel)

        progressIndicator = NSProgressIndicator()
        progressIndicator.style = .spinning
        progressIndicator.controlSize = .small
        progressIndicator.isHidden = true
        progressIndicator.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(progressIndicator)

        // Results container
        resultsBox = NSBox()
        resultsBox.title = "Résultats"
        resultsBox.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(resultsBox)

        let resultsStack = NSStackView()
        resultsStack.orientation = .vertical
        resultsStack.alignment = .leading
        resultsStack.spacing = 6
        resultsStack.translatesAutoresizingMaskIntoConstraints = false
        resultsBox.contentView?.addSubview(resultsStack)

        downloadLabel = createResultLabel("Download: —")
        uploadLabel = createResultLabel("Upload: —")
        latencyLabel = createResultLabel("Latence: —")
        rpmLabel = createResultLabel("RPM: —")
        qualityLabel = createResultLabel("Qualité: —")
        qualityLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)

        resultsStack.addArrangedSubview(downloadLabel)
        resultsStack.addArrangedSubview(uploadLabel)
        resultsStack.addArrangedSubview(latencyLabel)
        resultsStack.addArrangedSubview(rpmLabel)
        resultsStack.addArrangedSubview(qualityLabel)

        // History table (directement dans contentView, pas dans une NSBox)
        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        contentView.addSubview(scrollView)

        historyTableView = NSTableView()
        historyTableView.dataSource = self
        historyTableView.delegate = self
        historyTableView.rowHeight = 22
        historyTableView.usesAlternatingRowBackgroundColors = true

        let dateColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("date"))
        dateColumn.title = "Date"
        dateColumn.width = 120
        historyTableView.addTableColumn(dateColumn)

        let downloadColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("download"))
        downloadColumn.title = "Down (Mbps)"
        downloadColumn.width = 80
        historyTableView.addTableColumn(downloadColumn)

        let uploadColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("upload"))
        uploadColumn.title = "Up (Mbps)"
        uploadColumn.width = 80
        historyTableView.addTableColumn(uploadColumn)

        let locationColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("location"))
        locationColumn.title = "Lieu"
        locationColumn.width = 150
        historyTableView.addTableColumn(locationColumn)

        scrollView.documentView = historyTableView

        // Barre de boutons en bas
        let bottomBar = NSStackView()
        bottomBar.orientation = .horizontal
        bottomBar.spacing = 12
        bottomBar.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(bottomBar)

        startButton = NSButton(title: "Lancer le test", target: self, action: #selector(startTest))
        startButton.bezelStyle = .rounded
        bottomBar.addArrangedSubview(startButton)

        // Spacer pour pousser Effacer a droite
        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        bottomBar.addArrangedSubview(spacer)

        let exportButton = NSButton(title: "Exporter CSV", target: self, action: #selector(exportCSV))
        exportButton.bezelStyle = .rounded
        exportButton.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.addArrangedSubview(exportButton)

        clearHistoryButton = NSButton(title: "Effacer l'historique", target: self, action: #selector(clearHistory))
        clearHistoryButton.bezelStyle = .rounded
        clearHistoryButton.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.addArrangedSubview(clearHistoryButton)

        // On n'utilise plus historyBox, on le garde nil-safe
        historyBox = NSBox()
        historyBox.isHidden = true

        // Mise en page Auto Layout
        NSLayoutConstraint.activate([
            // Titre
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            titleLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),

            // Localisation
            locationLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            locationLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),

            // Animation (sous localisation)
            animationView.topAnchor.constraint(equalTo: locationLabel.bottomAnchor, constant: 8),
            animationView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            animationView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            animationView.heightAnchor.constraint(equalToConstant: 80),

            // Status + spinner (sous animation)
            statusLabel.topAnchor.constraint(equalTo: animationView.bottomAnchor, constant: 8),
            statusLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            progressIndicator.centerYAnchor.constraint(equalTo: statusLabel.centerYAnchor),
            progressIndicator.trailingAnchor.constraint(equalTo: statusLabel.leadingAnchor, constant: -6),

            // Resultats
            resultsBox.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 8),
            resultsBox.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            resultsBox.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),

            resultsStack.topAnchor.constraint(equalTo: resultsBox.contentView!.topAnchor, constant: 6),
            resultsStack.leadingAnchor.constraint(equalTo: resultsBox.contentView!.leadingAnchor, constant: 10),
            resultsStack.trailingAnchor.constraint(equalTo: resultsBox.contentView!.trailingAnchor, constant: -10),
            resultsStack.bottomAnchor.constraint(equalTo: resultsBox.contentView!.bottomAnchor, constant: -6),

            // Tableau (prend tout l'espace restant)
            scrollView.topAnchor.constraint(equalTo: resultsBox.bottomAnchor, constant: 12),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            scrollView.bottomAnchor.constraint(equalTo: bottomBar.topAnchor, constant: -8),

            // Barre de boutons en bas
            bottomBar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            bottomBar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            bottomBar.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),
            bottomBar.heightAnchor.constraint(equalToConstant: 28),
        ])

        // Get initial location
        updateLocation()
    }

    private func createResultLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        return label
    }

    /// Charge l'historique depuis UserDefaults et rafraîchit la table.
    private func loadHistory() {
        history = SpeedTestHistoryStorage.load()
        DispatchQueue.main.async { [weak self] in
            self?.historyTableView?.reloadData()
        }
    }

    /// Demande/actualise la localisation courante.
    private func updateLocation() {
        locationService.getLocation { [weak self] location in
            self?.currentLocation = location
            self?.locationLabel.stringValue = "📍 \(location)"
        }
    }

    /// Lance un test de debit via HTTP (download, upload, latence).
    @objc func startTest() {
        guard !isRunning else { return }
        isRunning = true

        startButton.isEnabled = false
        progressIndicator.isHidden = false
        progressIndicator.startAnimation(nil)
        statusLabel.stringValue = "Test en cours..."
        resetResults()

        animationView.isHidden = false
        animationView.startAnimating()

        // Refresh location before test
        updateLocation()

        runHTTPSpeedTest()
    }

    /// Efface l'historique après confirmation utilisateur.
    @objc private func exportCSV() {
        let entries = SpeedTestHistoryStorage.load()
        guard !entries.isEmpty else {
            let alert = NSAlert()
            alert.messageText = "Aucun historique"
            alert.informativeText = "Il n'y a pas de données à exporter."
            alert.runModal()
            return
        }

        let panel = NSSavePanel()
        panel.nameFieldStringValue = "MonReseau_SpeedTest.csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let df = DateFormatter()
        df.dateStyle = .short
        df.timeStyle = .medium

        var csv = "Date;Download (Mbps);Upload (Mbps);Latence (ms);Localisation\n"
        for entry in entries {
            csv += "\(df.string(from: entry.date));\(String(format: "%.1f", entry.downloadMbps));\(String(format: "%.1f", entry.uploadMbps));\(String(format: "%.0f", entry.latencyMs));\(entry.location)\n"
        }

        do {
            try csv.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Erreur d'export"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    @objc private func clearHistory() {
        let alert = NSAlert()
        alert.messageText = "Effacer l'historique ?"
        alert.informativeText = "Cette action est irréversible."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Effacer")
        alert.addButton(withTitle: "Annuler")

        if alert.runModal() == .alertFirstButtonReturn {
            SpeedTestHistoryStorage.clear()
            loadHistory()
        }
    }

    /// Réinitialise l'affichage des résultats.
    private func resetResults() {
        downloadLabel.stringValue = "Download: —"
        uploadLabel.stringValue = "Upload: —"
        latencyLabel.stringValue = "Latence: —"
        rpmLabel.stringValue = "RPM: —"
        qualityLabel.stringValue = "Qualité: —"
        qualityLabel.textColor = .labelColor
    }

    /// Termine le test et réactive l'UI.
    private func finishTest() {
        isRunning = false
        startButton.isEnabled = true
        progressIndicator.stopAnimation(nil)
        progressIndicator.isHidden = true
        animationView.stopAnimating()
    }

    /// Sauvegarde le résultat courant dans l'historique.
    private func saveToHistory(_ result: SpeedTestResult, isFallback: Bool) {
        let entry = SpeedTestHistoryEntry(result: result, location: currentLocation, isFallback: isFallback)
        SpeedTestHistoryStorage.add(entry)
        loadHistory()
    }

    // MARK: - Test HTTP (download, upload, latence)

    /// Lance les 3 phases du test de debit via HTTP.
    private func runHTTPSpeedTest() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            // Phase 1: Latence (5 requetes HEAD)
            DispatchQueue.main.async { self.statusLabel.stringValue = "Mesure de la latence..." }
            let latency = self.measureHTTPLatency()

            // Phase 2: Download
            DispatchQueue.main.async { self.statusLabel.stringValue = "Test de download..." }
            let downloadMbps = self.measureDownload()

            // Phase 3: Upload
            DispatchQueue.main.async { self.statusLabel.stringValue = "Test d'upload..." }
            let uploadMbps = self.measureUpload()

            // Estimation RPM a partir de la latence
            let rpm = latency > 0 ? max(0, Int(60000.0 / max(latency, 5))) : 0

            let result = SpeedTestResult(
                downloadMbps: downloadMbps,
                uploadMbps: uploadMbps,
                latencyMs: latency,
                rpm: rpm
            )

            DispatchQueue.main.async {
                self.displayResult(result, isFallback: false)
                self.saveToHistory(result, isFallback: false)
                self.finishTest()
            }
        }
    }

    /// Mesure la latence HTTP via des requetes HEAD repetees.
    private func measureHTTPLatency() -> Double {
        let url = URL(string: "https://one.one.one.one")!
        var latencies: [Double] = []
        let session = URLSession(configuration: .ephemeral)

        for _ in 0..<5 {
            var request = URLRequest(url: url, timeoutInterval: 5)
            request.httpMethod = "HEAD"
            request.cachePolicy = .reloadIgnoringLocalCacheData

            let semaphore = DispatchSemaphore(value: 0)
            let start = CFAbsoluteTimeGetCurrent()
            session.dataTask(with: request) { _, _, error in
                if error == nil {
                    let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
                    latencies.append(elapsed)
                }
                semaphore.signal()
            }.resume()
            _ = semaphore.wait(timeout: .now() + 5)
        }

        session.invalidateAndCancel()
        guard !latencies.isEmpty else { return 0 }
        // Prendre la mediane pour eviter les outliers
        let sorted = latencies.sorted()
        return sorted[sorted.count / 2]
    }

    /// Mesure le debit descendant en telechargeant depuis Cloudflare.
    private func measureDownload() -> Double {
        let url = URL(string: "https://speed.cloudflare.com/__down?bytes=25000000")!
        let semaphore = DispatchSemaphore(value: 0)
        var downloadMbps = 0.0
        let startTime = CFAbsoluteTimeGetCurrent()

        let session = URLSession(configuration: .ephemeral)
        session.dataTask(with: url) { data, _, error in
            if let data = data, error == nil {
                let elapsed = CFAbsoluteTimeGetCurrent() - startTime
                downloadMbps = (Double(data.count) * 8) / (elapsed * 1_000_000)
            }
            semaphore.signal()
        }.resume()
        _ = semaphore.wait(timeout: .now() + 30)
        session.invalidateAndCancel()
        return downloadMbps
    }

    /// Mesure le debit montant en envoyant des donnees vers Cloudflare.
    private func measureUpload() -> Double {
        guard let url = URL(string: "https://speed.cloudflare.com/__up") else { return 0 }
        let uploadSize = 10_000_000 // 10 Mo
        let uploadData = Data(repeating: 0, count: uploadSize)

        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")

        let semaphore = DispatchSemaphore(value: 0)
        var uploadMbps = 0.0
        let startTime = CFAbsoluteTimeGetCurrent()

        let session = URLSession(configuration: .ephemeral)
        session.uploadTask(with: request, from: uploadData) { _, _, error in
            if error == nil {
                let elapsed = CFAbsoluteTimeGetCurrent() - startTime
                uploadMbps = (Double(uploadSize) * 8) / (elapsed * 1_000_000)
            }
            semaphore.signal()
        }.resume()
        _ = semaphore.wait(timeout: .now() + 30)
        session.invalidateAndCancel()
        return uploadMbps
    }

    /// Met à jour l'UI avec les résultats et calcule une étiquette de qualité simple.
    private func displayResult(_ result: SpeedTestResult, isFallback: Bool) {
        downloadLabel.stringValue = String(format: "Download: %.1f Mbps", result.downloadMbps)
        uploadLabel.stringValue = String(format: "Upload: %.1f Mbps", result.uploadMbps)
        latencyLabel.stringValue = String(format: "Latence: %.0f ms", result.latencyMs)
        rpmLabel.stringValue = String(format: "RPM: %d", result.rpm)
        statusLabel.stringValue = "Test termine"

        let quality: String
        let color: NSColor
        if result.downloadMbps >= 100 {
            quality = "Excellente"
            color = .systemGreen
        } else if result.downloadMbps >= 25 {
            quality = "Bonne"
            color = .systemBlue
        } else if result.downloadMbps >= 5 {
            quality = "Moyenne"
            color = .systemOrange
        } else {
            quality = "Mauvaise"
            color = .systemRed
        }

        qualityLabel.stringValue = "Qualité: \(quality)"
        qualityLabel.textColor = color
    }

    // MARK: - NSTableViewDataSource

    // Nombre de lignes dans la table (taille de l'historique)
    func numberOfRows(in tableView: NSTableView) -> Int {
        return history.count
    }

    // MARK: - NSTableViewDelegate

    // Retourne une vue pour chaque cellule selon la colonne et la ligne, formatte les donnees
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < history.count else { return nil }
        let entry = history[row]

        let identifier = tableColumn?.identifier ?? NSUserInterfaceItemIdentifier("")
        let cellIdentifier = NSUserInterfaceItemIdentifier("Cell_\(identifier.rawValue)")

        let textField: NSTextField
        if let existing = tableView.makeView(withIdentifier: cellIdentifier, owner: nil) as? NSTextField {
            textField = existing
        } else {
            textField = NSTextField(labelWithString: "")
            textField.identifier = cellIdentifier
            textField.font = NSFont.systemFont(ofSize: 11)
        }

        switch identifier.rawValue {
        case "date":
            textField.stringValue = dateFormatter.string(from: entry.date)
        case "download":
            textField.stringValue = String(format: "%.1f", entry.downloadMbps)
        case "upload":
            textField.stringValue = entry.uploadMbps > 0 ? String(format: "%.1f", entry.uploadMbps) : "—"
        case "location":
            textField.stringValue = entry.location
        default:
            textField.stringValue = ""
        }

        return textField
    }

    // Arrete l'animation avant la fermeture
    override func close() {
        animationView.stopAnimating()
        super.close()
    }

    // Arrete l'animation si le controleur est deinitalise
    deinit {
        animationView?.stopAnimating()
        NotificationCenter.default.removeObserver(self, name: .speedTestHistoryDidChange, object: nil)
    }
}

