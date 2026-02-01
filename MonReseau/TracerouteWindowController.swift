// TracerouteWindowController.swift
// Interface de traceroute visuel avec carte interactive.
// Utilise ICMP natif (SOCK_DGRAM + IPPROTO_ICMP) avec TTL incrementiel pour tracer le chemin reseau.
// Geolocalise chaque hop en temps reel via ipwho.is et affiche le trajet sur une carte MapKit.
// Contient: modele `TracerouteHop`, service `TracerouteService`, annotation `HopAnnotation`,
// et fenetre `TracerouteWindowController`.

import Cocoa
import MapKit
import CoreLocation

// MapKit pour la carte, CoreLocation pour les coordonnees et geocodage

// MARK: - Data Model

/// Modèle représentant un hop de traceroute (numéro, IP, latence, localisation).
// Modele representant un hop de traceroute (numero, IP, latence, localisation)
class TracerouteHop {
    let hopNumber: Int
    var ipAddress: String
    var hostname: String?
    var latencyMs: Double?
    var coordinate: CLLocationCoordinate2D?
    var city: String?
    var region: String?
    var country: String?
    var countryCode: String?
    var asn: Int?
    var isp: String?
    var org: String?
    var isTimeout: Bool

    init(hopNumber: Int, ipAddress: String, latencyMs: Double?) {
        self.hopNumber = hopNumber
        self.ipAddress = ipAddress
        self.latencyMs = latencyMs
        self.isTimeout = ipAddress == "*"
    }

    var locationString: String {
        if isTimeout { return "—" }
        if isPrivateIP { return "Réseau local" }
        if let city = city, let country = country {
            return "\(city), \(country)"
        }
        return "..."
    }

    var asnString: String {
        if let asn = asn { return "AS\(asn)" }
        return ""
    }

    var isPrivateIP: Bool {
        if ipAddress.hasPrefix("192.168.") || ipAddress.hasPrefix("10.") {
            return true
        }
        if ipAddress.hasPrefix("172.") {
            let parts = ipAddress.split(separator: ".")
            if parts.count >= 2, let second = Int(parts[1]), second >= 16 && second <= 31 {
                return true
            }
        }
        // IPv6 private ranges
        let lower = ipAddress.lowercased()
        if lower.hasPrefix("fe80:") || lower.hasPrefix("fc") || lower.hasPrefix("fd") || lower == "::1" {
            return true
        }
        return false
    }
}

// MARK: - Traceroute Service

/// Service de traceroute natif via ICMP avec geolocalisation en temps reel.
class TracerouteService {

    /// Lance le traceroute en arrière-plan, publie les hops puis géolocalise.
    // Execute le traceroute en arriere-plan, publie les hops au fil de l'eau, puis geolocalise et renvoie le resultat
    func run(host: String, progressHandler: @escaping (TracerouteHop) -> Void, geoHandler: @escaping (TracerouteHop) -> Void, completion: @escaping ([TracerouteHop]) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            // Run local traceroute with inline geolocation
            let hops = self.runLocalTraceroute(host: host, progressHandler: progressHandler, geoHandler: geoHandler)

            DispatchQueue.main.async {
                completion(hops)
            }
        }
    }

    /// Traceroute natif via ICMP/ICMPv6 non-privilegie (SOCK_DGRAM).
    /// Supporte IPv4 et IPv6 automatiquement selon la résolution DNS.
    private func runLocalTraceroute(host: String, progressHandler: @escaping (TracerouteHop) -> Void, geoHandler: @escaping (TracerouteHop) -> Void) -> [TracerouteHop] {
        var hops: [TracerouteHop] = []

        // Resoudre l'adresse destination (IPv4 d'abord, IPv6 en fallback)
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_DGRAM
        var infoPtr: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &infoPtr) == 0, let info = infoPtr else {
            NSLog("TracerouteService: Resolution echouee pour \(host)")
            return hops
        }
        defer { freeaddrinfo(infoPtr) }

        let family = info.pointee.ai_family
        let destAddr = info.pointee.ai_addr
        let destLen = info.pointee.ai_addrlen
        let isIPv6 = family == AF_INET6

        // Obtenir l'IP de destination pour detecter l'arrivee
        var destHostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        getnameinfo(destAddr, socklen_t(destLen), &destHostname, socklen_t(destHostname.count), nil, 0, NI_NUMERICHOST)
        let destIP = String(cString: destHostname)

        // Creer le socket ICMP/ICMPv6 non-privilegie
        let proto = isIPv6 ? IPPROTO_ICMPV6 : IPPROTO_ICMP
        let sock = Darwin.socket(family, SOCK_DGRAM, proto)
        guard sock >= 0 else {
            NSLog("TracerouteService: Impossible de creer le socket ICMP")
            return hops
        }
        defer { Darwin.close(sock) }

        // Timeout de reception
        var timeout = timeval(tv_sec: 3, tv_usec: 0)
        setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        let maxHops = 30
        let queriesPerHop = 2
        let pid = UInt16(ProcessInfo.processInfo.processIdentifier & 0xFFFF)

        // Options TTL/hop limit selon le protocole
        let ttlProto = isIPv6 ? IPPROTO_IPV6 : IPPROTO_IP
        let ttlOption = isIPv6 ? IPV6_UNICAST_HOPS : IP_TTL

        for ttl in 1...maxHops {
            var ttlValue = Int32(ttl)
            setsockopt(sock, ttlProto, ttlOption, &ttlValue, socklen_t(MemoryLayout<Int32>.size))

            var latencies: [Double] = []
            var hopIP: String?

            for q in 0..<queriesPerHop {
                // Construire le paquet ICMP/ICMPv6 Echo Request
                let seq = UInt16(ttl * queriesPerHop + q)
                var packet = [UInt8](repeating: 0, count: 64)
                packet[0] = isIPv6 ? 128 : 8  // ICMPv6_ECHO_REQUEST : ICMP_ECHO
                packet[1] = 0  // Code
                packet[4] = UInt8(pid >> 8)
                packet[5] = UInt8(pid & 0xFF)
                packet[6] = UInt8(seq >> 8)
                packet[7] = UInt8(seq & 0xFF)

                // Checksum (IPv4 seulement ; ICMPv6 checksum calculé par le kernel)
                if !isIPv6 {
                    var sum: UInt32 = 0
                    for i in stride(from: 0, to: packet.count - 1, by: 2) {
                        sum += UInt32(packet[i]) << 8 | UInt32(packet[i + 1])
                    }
                    while sum >> 16 != 0 { sum = (sum & 0xFFFF) + (sum >> 16) }
                    let checksum = ~UInt16(sum)
                    packet[2] = UInt8(checksum >> 8)
                    packet[3] = UInt8(checksum & 0xFF)
                }

                // Envoyer
                let startTime = CFAbsoluteTimeGetCurrent()
                let sent = packet.withUnsafeBytes { bufPtr in
                    sendto(sock, bufPtr.baseAddress, bufPtr.count, 0, destAddr!, socklen_t(destLen))
                }
                guard sent > 0 else { continue }

                // Recevoir (ICMP Time Exceeded ou Echo Reply)
                var recvBuf = [UInt8](repeating: 0, count: 1024)
                var srcStorage = sockaddr_storage()
                var srcLen = socklen_t(MemoryLayout<sockaddr_storage>.size)

                let recvLen = withUnsafeMutablePointer(to: &srcStorage) { storagePtr in
                    storagePtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                        recvfrom(sock, &recvBuf, recvBuf.count, 0, sockaddrPtr, &srcLen)
                    }
                }

                if recvLen > 0 {
                    let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
                    // Extract source IP from sockaddr_storage
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    withUnsafePointer(to: &srcStorage) { storagePtr in
                        storagePtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                            getnameinfo(sockaddrPtr, srcLen, &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST)
                        }
                    }
                    let ip = String(cString: hostname)
                    hopIP = ip
                    latencies.append(elapsed)
                }
            }

            let hop: TracerouteHop
            if let ip = hopIP {
                let avgLatency = latencies.isEmpty ? nil : latencies.reduce(0, +) / Double(latencies.count)
                hop = TracerouteHop(hopNumber: ttl, ipAddress: ip, latencyMs: avgLatency)
            } else {
                hop = TracerouteHop(hopNumber: ttl, ipAddress: "*", latencyMs: nil)
            }

            // Reverse DNS
            if !hop.isTimeout {
                hop.hostname = self.reverseDNS(ip: hop.ipAddress)
            }

            hops.append(hop)
            DispatchQueue.main.async { progressHandler(hop) }

            // Geolocaliser ce hop en temps reel si IP publique
            if !hop.isTimeout && !hop.isPrivateIP {
                let sem = DispatchSemaphore(value: 0)
                self.geolocateHop(hop) {
                    DispatchQueue.main.async { geoHandler(hop) }
                    sem.signal()
                }
                sem.wait()
            }

            // Verifier si on a atteint la destination
            if hopIP == destIP {
                break
            }
        }

        NSLog("TracerouteService: \(hops.count) hops (\(isIPv6 ? "IPv6" : "IPv4"))")
        return hops
    }

    /// Reverse DNS lookup pour obtenir le hostname a partir de l'IP.
    private func reverseDNS(ip: String) -> String? {
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_DGRAM
        var infoPtr: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(ip, nil, &hints, &infoPtr) == 0, let info = infoPtr else { return nil }
        defer { freeaddrinfo(infoPtr) }

        var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let result = getnameinfo(info.pointee.ai_addr, info.pointee.ai_addrlen,
                                 &hostname, socklen_t(hostname.count),
                                 nil, 0, NI_NAMEREQD)
        guard result == 0 else { return nil }
        let name = String(cString: hostname)
        // Si le reverse DNS renvoie juste l'IP, ignorer
        if name == ip { return nil }
        return name
    }

    /// Geolocalise un seul hop via ipwho.is (HTTPS, sans rate limit strict).
    private func geolocateHop(_ hop: TracerouteHop, completion: @escaping () -> Void) {
        guard let url = URL(string: "https://ipwho.is/\(hop.ipAddress)") else {
            completion()
            return
        }

        let request = URLRequest(url: url, timeoutInterval: 5)

        URLSession.shared.dataTask(with: request) { data, _, _ in
            defer { completion() }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  json["success"] as? Bool == true,
                  let lat = json["latitude"] as? Double,
                  let lon = json["longitude"] as? Double else { return }

            hop.coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            hop.city = json["city"] as? String ?? ""
            hop.region = json["region"] as? String
            hop.country = json["country"] as? String ?? ""
            hop.countryCode = json["country_code"] as? String

            if let connection = json["connection"] as? [String: Any] {
                hop.asn = connection["asn"] as? Int
                hop.isp = connection["isp"] as? String
                hop.org = connection["org"] as? String
            }
        }.resume()
    }

}

// MARK: - Custom Annotation

/// Annotation MapKit pour afficher un hop sur la carte.
// Annotation MapKit pour afficher un hop sur la carte
class HopAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    let title: String?
    let subtitle: String?
    let hopNumber: Int
    let latencyMs: Double?
    let hop: TracerouteHop

    init(hop: TracerouteHop) {
        self.hop = hop
        self.coordinate = hop.coordinate ?? CLLocationCoordinate2D()
        self.hopNumber = hop.hopNumber
        self.latencyMs = hop.latencyMs

        // Titre: hop + hostname ou IP
        if let hostname = hop.hostname {
            self.title = "Hop \(hop.hopNumber) — \(hostname)"
        } else {
            self.title = "Hop \(hop.hopNumber) — \(hop.ipAddress)"
        }

        // Sous-titre: localisation + ISP/ASN + latence
        var parts: [String] = []
        parts.append(hop.locationString)
        if let isp = hop.isp, !isp.isEmpty {
            if let asn = hop.asn {
                parts.append("\(isp) (AS\(asn))")
            } else {
                parts.append(isp)
            }
        }
        if let latency = hop.latencyMs {
            parts.append(String(format: "%.1f ms", latency))
        }
        self.subtitle = parts.joined(separator: " · ")
    }
}

// MARK: - Window Controller

/// Controleur de fenetre: UI, lancement du traceroute, affichage table + carte avec mise a jour en temps reel.
class TracerouteWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, MKMapViewDelegate {

    private var targetTextField: NSTextField!
    private var startButton: NSButton!
    private var statusLabel: NSTextField!
    private var mapView: MKMapView!
    private var hopsTableView: NSTableView!
    private var progressIndicator: NSProgressIndicator!

    private let tracerouteService = TracerouteService()
    private var hops: [TracerouteHop] = []
    private var isRunning = false

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 650),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = NSLocalizedString("traceroute.title", comment: "")
        window.center()
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 700, height: 500)

        self.init(window: window)
        setupUI()
        window.initialFirstResponder = targetTextField
    }

    private func setupUI() {
        guard let contentView = window?.contentView else { return }
        contentView.wantsLayer = true

        // Title
        let titleLabel = NSTextField(labelWithString: NSLocalizedString("traceroute.heading", comment: ""))
        titleLabel.font = NSFont.systemFont(ofSize: 18, weight: .semibold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(titleLabel)

        // Input row
        let inputStack = NSStackView()
        inputStack.orientation = .horizontal
        inputStack.spacing = 10
        inputStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(inputStack)

        targetTextField = NSTextField()
        targetTextField.placeholderString = "google.com"
        targetTextField.target = self
        targetTextField.action = #selector(startTracerouteFromButton)
        targetTextField.translatesAutoresizingMaskIntoConstraints = false
        targetTextField.widthAnchor.constraint(greaterThanOrEqualToConstant: 250).isActive = true
        inputStack.addArrangedSubview(targetTextField)

        startButton = NSButton(title: NSLocalizedString("traceroute.button.trace", comment: ""), target: self, action: #selector(startTracerouteFromButton))
        startButton.bezelStyle = .rounded
        inputStack.addArrangedSubview(startButton)

        progressIndicator = NSProgressIndicator()
        progressIndicator.style = .spinning
        progressIndicator.controlSize = .small
        progressIndicator.isHidden = true
        inputStack.addArrangedSubview(progressIndicator)

        let copyButton = NSButton(title: NSLocalizedString("Copier", comment: "Copy button"), target: self, action: #selector(copyTraceroute))
        copyButton.bezelStyle = .rounded
        inputStack.addArrangedSubview(copyButton)

        let shareButton = NSButton(title: NSLocalizedString("Partager", comment: "Share button"), target: self, action: #selector(shareTraceroute(_:)))
        shareButton.bezelStyle = .rounded
        inputStack.addArrangedSubview(shareButton)

        // Status
        statusLabel = NSTextField(labelWithString: NSLocalizedString("traceroute.status.ready", comment: ""))
        statusLabel.font = NSFont.systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(statusLabel)

        // Map
        mapView = MKMapView()
        mapView.delegate = self
        mapView.translatesAutoresizingMaskIntoConstraints = false
        mapView.wantsLayer = true
        mapView.layer?.cornerRadius = 8
        mapView.layer?.masksToBounds = true
        contentView.addSubview(mapView)

        // Table in scroll view
        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        contentView.addSubview(scrollView)

        hopsTableView = NSTableView()
        hopsTableView.dataSource = self
        hopsTableView.delegate = self
        hopsTableView.rowHeight = 20
        hopsTableView.usesAlternatingRowBackgroundColors = true

        let hopColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("hop"))
        hopColumn.title = "#"
        hopColumn.width = 30
        hopColumn.minWidth = 28
        hopsTableView.addTableColumn(hopColumn)

        let ipColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("ip"))
        ipColumn.title = "IP"
        ipColumn.width = 120
        ipColumn.minWidth = 90
        hopsTableView.addTableColumn(ipColumn)

        let hostnameColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("hostname"))
        hostnameColumn.title = "Nom d'hôte"
        hostnameColumn.width = 180
        hostnameColumn.minWidth = 80
        hopsTableView.addTableColumn(hostnameColumn)

        let locationColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("location"))
        locationColumn.title = "Lieu"
        locationColumn.width = 130
        locationColumn.minWidth = 60
        hopsTableView.addTableColumn(locationColumn)

        let ispColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("isp"))
        ispColumn.title = "ISP / ASN"
        ispColumn.width = 160
        ispColumn.minWidth = 60
        hopsTableView.addTableColumn(ispColumn)

        let latencyColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("latency"))
        latencyColumn.title = "Latence"
        latencyColumn.width = 70
        latencyColumn.minWidth = 50
        hopsTableView.addTableColumn(latencyColumn)

        scrollView.documentView = hopsTableView

        // Contraintes Auto Layout
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            titleLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),

            inputStack.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 16),
            inputStack.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),

            statusLabel.topAnchor.constraint(equalTo: inputStack.bottomAnchor, constant: 8),
            statusLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),

            mapView.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 12),
            mapView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            mapView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            mapView.heightAnchor.constraint(equalToConstant: 280),

            scrollView.topAnchor.constraint(equalTo: mapView.bottomAnchor, constant: 12),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            scrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
        ])
    }

    @objc func startTracerouteFromButton() {
        let target = targetTextField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !target.isEmpty, !isRunning else { return }
        runTraceroute(for: target)
    }

    func startTraceroute(host: String) {
        targetTextField.stringValue = host
        guard !isRunning else { return }
        runTraceroute(for: host)
    }

    // Prepare l'UI, vide l'etat precedent, puis lance le service
    private func runTraceroute(for target: String) {

        isRunning = true
        hops.removeAll()
        hopsTableView.reloadData()
        mapView.removeAnnotations(mapView.annotations)
        mapView.removeOverlays(mapView.overlays)

        startButton.isEnabled = false
        progressIndicator.isHidden = false
        progressIndicator.startAnimation(nil)
        statusLabel.stringValue = NSLocalizedString("traceroute.status.running", comment: "")

        tracerouteService.run(host: target, progressHandler: { [weak self] hop in
            guard let self = self else { return }
            self.hops.append(hop)
            self.hopsTableView.reloadData()
            self.hopsTableView.scrollRowToVisible(self.hops.count - 1)
            self.statusLabel.stringValue = "Hop \(hop.hopNumber): \(hop.ipAddress)"
        }, geoHandler: { [weak self] hop in
            guard let self = self else { return }
            self.hopsTableView.reloadData()
            self.addHopToMap(hop)
        }, completion: { [weak self] finalHops in
            guard let self = self else { return }
            self.hops = finalHops
            self.hopsTableView.reloadData()
            self.finishTraceroute()
        })
    }

    private func finishTraceroute() {
        isRunning = false
        startButton.isEnabled = true
        progressIndicator.stopAnimation(nil)
        progressIndicator.isHidden = true
        statusLabel.stringValue = String(format: NSLocalizedString("traceroute.status.done", comment: ""), hops.count)
    }

    // Ajoute un hop sur la carte, met a jour la polyline et autozoom
    private func addHopToMap(_ hop: TracerouteHop) {
        guard let coord = hop.coordinate else { return }

        let annotation = HopAnnotation(hop: hop)
        mapView.addAnnotation(annotation)

        // Redessiner la polyline avec tous les hops geolocalises
        mapView.removeOverlays(mapView.overlays)
        let coordinates = hops.compactMap { $0.coordinate }
        if coordinates.count >= 2 {
            let polyline = MKPolyline(coordinates: coordinates, count: coordinates.count)
            mapView.addOverlay(polyline)
        }

        // Autozoom sur tous les points visibles
        let allAnnotations = mapView.annotations.filter { $0 is HopAnnotation }
        if !allAnnotations.isEmpty {
            mapView.showAnnotations(allAnnotations, animated: true)
        }
    }

    // MARK: - MKMapViewDelegate

    // Fournit une vue pour chaque annotation, colorie en fonction de la latence
    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        guard let hopAnnotation = annotation as? HopAnnotation else { return nil }

        let identifier = "HopPin"
        var annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView

        if annotationView == nil {
            annotationView = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
            annotationView?.canShowCallout = true
        } else {
            annotationView?.annotation = annotation
        }

        // Callout detail view
        let detailLabel = NSTextField(wrappingLabelWithString: calloutText(for: hopAnnotation.hop))
        detailLabel.font = NSFont.systemFont(ofSize: 11)
        detailLabel.preferredMaxLayoutWidth = 220
        annotationView?.detailCalloutAccessoryView = detailLabel

        // Couleur en fonction de la latence
        if let latency = hopAnnotation.latencyMs {
            if latency < 30 {
                annotationView?.markerTintColor = .systemGreen
            } else if latency < 100 {
                annotationView?.markerTintColor = .systemOrange
            } else {
                annotationView?.markerTintColor = .systemRed
            }
        } else {
            annotationView?.markerTintColor = .systemGray
        }

        annotationView?.glyphText = "\(hopAnnotation.hopNumber)"

        return annotationView
    }

    private func calloutText(for hop: TracerouteHop) -> String {
        var lines: [String] = []
        lines.append("IP : \(hop.ipAddress)")
        if let hostname = hop.hostname {
            lines.append("Hôte : \(hostname)")
        }
        if let city = hop.city, let region = hop.region, let country = hop.country {
            lines.append("Lieu : \(city), \(region), \(country)")
        }
        if let isp = hop.isp {
            lines.append("ISP : \(isp)")
        }
        if let org = hop.org, org != hop.isp {
            lines.append("Org : \(org)")
        }
        if let asn = hop.asn {
            lines.append("ASN : AS\(asn)")
        }
        if let latency = hop.latencyMs {
            lines.append(String(format: "Latence : %.1f ms", latency))
        }
        return lines.joined(separator: "\n")
    }

    // Render l'overlay polyline en bleu semi-transparent
    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        if let polyline = overlay as? MKPolyline {
            let renderer = MKPolylineRenderer(polyline: polyline)
            renderer.strokeColor = NSColor.systemBlue.withAlphaComponent(0.7)
            renderer.lineWidth = 3
            return renderer
        }
        return MKOverlayRenderer(overlay: overlay)
    }

    // MARK: - Selection tableau -> carte

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = hopsTableView.selectedRow
        guard row >= 0, row < hops.count else { return }
        let hop = hops[row]
        guard let coord = hop.coordinate else { return }

        // Centrer la carte sur le hop selectionne
        let region = MKCoordinateRegion(center: coord, latitudinalMeters: 500_000, longitudinalMeters: 500_000)
        mapView.setRegion(region, animated: true)

        // Ouvrir le callout de l'annotation correspondante
        for annotation in mapView.annotations {
            if let hopAnn = annotation as? HopAnnotation, hopAnn.hopNumber == hop.hopNumber {
                mapView.selectAnnotation(hopAnn, animated: true)
                break
            }
        }
    }

    // MARK: - Copier / Partager

    private func formatTracerouteText() -> String {
        guard !hops.isEmpty else { return "" }
        let target = targetTextField.stringValue
        var text = "Mon Réseau — Traceroute vers \(target)\n"
        text += String(repeating: "═", count: 60) + "\n"
        text += String(format: "%-4s  %-16s  %-30s  %-8s  %@\n", "#", "IP", "Nom d'hôte", "Latence", "Lieu")
        text += String(repeating: "─", count: 80) + "\n"

        for hop in hops {
            let num = String(format: "%-4d", hop.hopNumber)
            let ip = hop.isTimeout ? "* * *" : hop.ipAddress
            let hostname = hop.hostname ?? "—"
            let latency = hop.latencyMs.map { String(format: "%.1f ms", $0) } ?? "—"
            let location = hop.locationString
            text += "\(num)  \(ip.padding(toLength: 16, withPad: " ", startingAt: 0))  \(hostname.padding(toLength: 30, withPad: " ", startingAt: 0))  \(latency.padding(toLength: 8, withPad: " ", startingAt: 0))  \(location)\n"
        }
        return text
    }

    @objc private func copyTraceroute() {
        let text = formatTracerouteText()
        guard !text.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    @objc private func shareTraceroute(_ sender: NSButton) {
        let text = formatTracerouteText()
        guard !text.isEmpty else { return }
        let picker = NSSharingServicePicker(items: [text])
        picker.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
    }

    // MARK: - NSTableViewDataSource

    // Nombre de lignes = nombre de hops
    func numberOfRows(in tableView: NSTableView) -> Int {
        return hops.count
    }

    // MARK: - NSTableViewDelegate

    // Configure la cellule pour chaque colonne et ligne
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < hops.count else { return nil }
        let hop = hops[row]

        let identifier = tableColumn?.identifier ?? NSUserInterfaceItemIdentifier("")
        let cellIdentifier = NSUserInterfaceItemIdentifier("Cell_\(identifier.rawValue)")

        let textField: NSTextField
        if let existing = tableView.makeView(withIdentifier: cellIdentifier, owner: nil) as? NSTextField {
            textField = existing
        } else {
            textField = NSTextField(labelWithString: "")
            textField.identifier = cellIdentifier
            textField.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        }

        switch identifier.rawValue {
        case "hop":
            textField.stringValue = "\(hop.hopNumber)"
        case "ip":
            textField.stringValue = hop.isTimeout ? "* * *" : hop.ipAddress
            textField.textColor = hop.isTimeout ? .tertiaryLabelColor : .labelColor
        case "hostname":
            textField.stringValue = hop.hostname ?? (hop.isTimeout ? "—" : "")
            textField.textColor = hop.hostname != nil ? .labelColor : .tertiaryLabelColor
        case "location":
            textField.stringValue = hop.locationString
        case "isp":
            if hop.isTimeout || hop.isPrivateIP {
                textField.stringValue = hop.isPrivateIP ? "—" : ""
            } else if let isp = hop.isp {
                textField.stringValue = hop.asn != nil ? "\(isp) (AS\(hop.asn!))" : isp
            } else {
                textField.stringValue = hop.asnString.isEmpty ? "..." : hop.asnString
            }
        case "latency":
            if let latency = hop.latencyMs {
                textField.stringValue = String(format: "%.1f ms", latency)
                if latency < 30 {
                    textField.textColor = .systemGreen
                } else if latency < 100 {
                    textField.textColor = .systemOrange
                } else {
                    textField.textColor = .systemRed
                }
            } else {
                textField.stringValue = "—"
                textField.textColor = .tertiaryLabelColor
            }
        default:
            textField.stringValue = ""
        }

        return textField
    }
}

