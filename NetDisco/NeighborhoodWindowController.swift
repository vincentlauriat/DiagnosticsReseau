// NeighborhoodWindowController.swift
// Scan du voisinage reseau local en 3 phases :
//   1. Sollicitation ARP (UDP sweep) pour peupler la table ARP du systeme
//   2. Ping sweep ICMP pour mesurer la latence des machines qui repondent
//   3. Lecture de la table ARP (sysctl) pour recuperer les machines silencieuses (firewall, IoT)
// Enrichissement : resolution DNS inverse (getnameinfo), decouverte Bonjour/mDNS (NWBrowser),
// lookup fabricant OUI depuis l'adresse MAC.
// Double-clic sur une machine ouvre une fiche detaillee avec ping x10, scan de ports TCP, et type d'appareil.
// Compatible App Store — aucun appel shell.

import Cocoa
import Network

// MARK: - Data Model

/// Machine detectee sur le reseau local.
class NetworkDevice {
    let ipAddress: String
    var hostname: String?
    var latencyMs: Double?
    var macAddress: String?
    var vendor: String?
    var services: [String] = []

    init(ipAddress: String) {
        self.ipAddress = ipAddress
    }

    /// Nom affiche : hostname ou IP.
    var displayName: String {
        hostname ?? ipAddress
    }

    /// Services en texte.
    var servicesString: String {
        services.isEmpty ? "—" : services.joined(separator: ", ")
    }
}

// MARK: - OUI Vendor Lookup

/// Table simplifiee des prefixes MAC (OUI) les plus courants.
private let ouiTable: [String: String] = [
    "00:03:93": "Apple", "00:05:02": "Apple", "00:0A:27": "Apple", "00:0A:95": "Apple",
    "00:0D:93": "Apple", "00:10:FA": "Apple", "00:11:24": "Apple", "00:14:51": "Apple",
    "00:16:CB": "Apple", "00:17:F2": "Apple", "00:19:E3": "Apple", "00:1B:63": "Apple",
    "00:1C:B3": "Apple", "00:1D:4F": "Apple", "00:1E:52": "Apple", "00:1E:C2": "Apple",
    "00:1F:5B": "Apple", "00:1F:F3": "Apple", "00:21:E9": "Apple", "00:22:41": "Apple",
    "00:23:12": "Apple", "00:23:32": "Apple", "00:23:6C": "Apple", "00:23:DF": "Apple",
    "00:24:36": "Apple", "00:25:00": "Apple", "00:25:4B": "Apple", "00:25:BC": "Apple",
    "00:26:08": "Apple", "00:26:4A": "Apple", "00:26:B0": "Apple", "00:26:BB": "Apple",
    "00:30:65": "Apple", "00:3E:E1": "Apple", "00:50:E4": "Apple", "00:56:CD": "Apple",
    "04:0C:CE": "Apple", "04:15:52": "Apple", "04:1E:64": "Apple", "04:26:65": "Apple",
    "04:F1:28": "Apple", "08:00:27": "Oracle VM", "08:66:98": "Apple",
    "0C:74:C2": "Apple", "10:40:F3": "Apple", "10:DD:B1": "Apple",
    "14:10:9F": "Apple", "18:AF:61": "Apple", "1C:36:BB": "Apple",
    "20:78:F0": "Apple", "24:A0:74": "Apple", "28:6A:BA": "Apple",
    "2C:F0:A2": "Apple", "30:63:6B": "Apple", "34:36:3B": "Apple",
    "38:C9:86": "Apple", "3C:15:C2": "Apple", "3C:22:FB": "Apple",
    "40:33:1A": "Apple", "44:2A:60": "Apple", "48:60:BC": "Apple",
    "4C:32:75": "Apple", "4C:57:CA": "Apple", "50:BC:96": "Apple",
    "54:26:96": "Apple", "58:55:CA": "Apple", "5C:F9:38": "Apple",
    "60:03:08": "Apple", "64:A3:CB": "Apple", "68:5B:35": "Apple",
    "6C:40:08": "Apple", "6C:94:66": "Apple", "70:DE:E2": "Apple",
    "74:E1:B6": "Apple", "78:31:C1": "Apple", "7C:6D:62": "Apple",
    "80:E6:50": "Apple", "84:38:35": "Apple", "84:FC:FE": "Apple",
    "88:66:A5": "Apple", "8C:85:90": "Apple", "8C:FA:BA": "Apple",
    "90:27:E4": "Apple", "90:8D:6C": "Apple", "98:01:A7": "Apple",
    "98:D6:BB": "Apple", "9C:20:7B": "Apple", "9C:35:EB": "Apple",
    "A0:99:9B": "Apple", "A4:5E:60": "Apple", "A4:67:06": "Apple",
    "A4:D1:D2": "Apple", "A8:20:66": "Apple", "A8:5C:2C": "Apple",
    "A8:88:08": "Apple", "A8:BE:27": "Apple", "AC:29:3A": "Apple",
    "AC:BC:32": "Apple", "B0:34:95": "Apple", "B0:65:BD": "Apple",
    "B4:18:D1": "Apple", "B8:17:C2": "Apple", "B8:41:A4": "Apple",
    "B8:C1:11": "Apple", "B8:E8:56": "Apple", "BC:3A:EA": "Apple",
    "BC:52:B7": "Apple", "C0:63:94": "Apple", "C0:84:7A": "Apple",
    "C4:2C:03": "Apple", "C8:2A:14": "Apple", "C8:69:CD": "Apple",
    "CC:08:8D": "Apple", "CC:29:F5": "Apple", "D0:25:98": "Apple",
    "D0:33:11": "Apple", "D4:61:9D": "Apple", "D4:F4:6F": "Apple",
    "D8:00:4D": "Apple", "D8:1D:72": "Apple", "D8:30:62": "Apple",
    "DC:2B:2A": "Apple", "DC:56:E7": "Apple", "E0:5F:45": "Apple",
    "E0:B5:2D": "Apple", "E4:25:E7": "Apple", "E4:C6:3D": "Apple",
    "E8:06:88": "Apple", "E8:80:2E": "Apple", "EC:35:86": "Apple",
    "F0:18:98": "Apple", "F0:99:BF": "Apple", "F0:B4:79": "Apple",
    "F0:CB:A1": "Apple", "F0:D1:A9": "Apple", "F4:5C:89": "Apple",
    "F8:1E:DF": "Apple", "FC:25:3F": "Apple",
    // Samsung
    "00:07:AB": "Samsung", "00:12:FB": "Samsung", "00:15:99": "Samsung",
    "00:16:32": "Samsung", "00:17:D5": "Samsung", "00:18:AF": "Samsung",
    "00:1A:8A": "Samsung", "00:1C:43": "Samsung", "00:1D:25": "Samsung",
    "00:1E:E1": "Samsung", "00:1E:E2": "Samsung", "00:21:19": "Samsung",
    "00:23:39": "Samsung", "00:23:D6": "Samsung", "00:23:D7": "Samsung",
    "00:24:54": "Samsung", "00:24:90": "Samsung", "00:24:91": "Samsung",
    "00:26:37": "Samsung", "00:E0:64": "Samsung",
    "08:37:3D": "Samsung", "08:D4:2B": "Samsung",
    "10:1D:C0": "Samsung", "14:49:E0": "Samsung", "18:67:B0": "Samsung",
    "1C:62:B8": "Samsung", "24:4B:81": "Samsung", "28:98:7B": "Samsung",
    "30:CD:A7": "Samsung", "34:23:BA": "Samsung", "38:01:97": "Samsung",
    "40:0E:85": "Samsung", "44:4E:1A": "Samsung", "4C:BC:A5": "Samsung",
    "50:01:BB": "Samsung", "50:A4:C8": "Samsung", "54:40:AD": "Samsung",
    "5C:49:7D": "Samsung", "5C:E8:EB": "Samsung", "60:AF:6D": "Samsung",
    "6C:F3:73": "Samsung", "78:52:1A": "Samsung", "84:25:DB": "Samsung",
    "8C:77:12": "Samsung", "90:18:7C": "Samsung", "94:01:C2": "Samsung",
    "98:52:B1": "Samsung", "A0:82:1F": "Samsung", "A8:06:00": "Samsung",
    "AC:5F:3E": "Samsung", "B4:07:F9": "Samsung", "BC:44:86": "Samsung",
    "C0:BD:D1": "Samsung", "C4:73:1E": "Samsung", "CC:07:AB": "Samsung",
    "D0:22:BE": "Samsung", "D0:66:7B": "Samsung", "D8:90:E8": "Samsung",
    "E4:7C:F9": "Samsung", "E8:50:8B": "Samsung", "EC:1F:72": "Samsung",
    "F0:25:B7": "Samsung", "F4:42:8F": "Samsung", "FC:A1:3E": "Samsung",
    // Google
    "08:9E:08": "Google", "18:D6:C7": "Google", "30:FD:38": "Google",
    "3C:5A:B4": "Google", "54:60:09": "Google", "58:CB:52": "Google",
    "94:EB:2C": "Google", "A4:77:33": "Google", "F4:F5:D8": "Google",
    "F4:F5:E8": "Google",
    // Intel
    "00:02:B3": "Intel", "00:03:47": "Intel", "00:04:23": "Intel",
    "00:07:E9": "Intel", "00:0E:0C": "Intel", "00:0E:35": "Intel",
    "00:11:11": "Intel", "00:12:F0": "Intel", "00:13:02": "Intel",
    "00:13:20": "Intel", "00:13:CE": "Intel", "00:13:E8": "Intel",
    "00:15:00": "Intel", "00:15:17": "Intel", "00:16:6F": "Intel",
    "00:16:76": "Intel", "00:16:EA": "Intel", "00:16:EB": "Intel",
    "00:18:DE": "Intel", "00:19:D1": "Intel", "00:19:D2": "Intel",
    "00:1B:21": "Intel", "00:1B:77": "Intel", "00:1C:BF": "Intel",
    "00:1C:C0": "Intel", "00:1D:E0": "Intel", "00:1D:E1": "Intel",
    "00:1E:64": "Intel", "00:1E:65": "Intel", "00:1F:3B": "Intel",
    "00:1F:3C": "Intel", "00:20:7B": "Intel", "00:21:5C": "Intel",
    "00:21:5D": "Intel", "00:21:6A": "Intel", "00:21:6B": "Intel",
    "00:22:FA": "Intel", "00:22:FB": "Intel", "00:24:D6": "Intel",
    "00:24:D7": "Intel", "00:27:10": "Intel",
    // Huawei
    "00:18:82": "Huawei", "00:1E:10": "Huawei", "00:22:A1": "Huawei",
    "00:25:68": "Huawei", "00:25:9E": "Huawei", "00:34:FE": "Huawei",
    "00:46:4B": "Huawei", "00:E0:FC": "Huawei", "04:02:1F": "Huawei",
    "04:25:C5": "Huawei", "04:33:89": "Huawei", "04:B0:E7": "Huawei",
    "04:C0:6F": "Huawei", "04:F9:38": "Huawei",
    // TP-Link
    "00:23:CD": "TP-Link", "00:27:19": "TP-Link",
    "14:CC:20": "TP-Link", "18:A6:F7": "TP-Link",
    "1C:3B:F3": "TP-Link", "30:B5:C2": "TP-Link",
    "50:C7:BF": "TP-Link", "54:C8:0F": "TP-Link",
    "60:E3:27": "TP-Link", "64:56:01": "TP-Link",
    "6C:5A:B0": "TP-Link", "74:DA:88": "TP-Link",
    "84:16:F9": "TP-Link", "90:F6:52": "TP-Link",
    "A4:2B:B0": "TP-Link", "B0:4E:26": "TP-Link",
    "B0:95:75": "TP-Link", "B0:BE:76": "TP-Link",
    "C0:25:E9": "TP-Link", "C4:E9:84": "TP-Link",
    "D8:07:B6": "TP-Link", "E8:DE:27": "TP-Link",
    "F4:EC:38": "TP-Link", "F8:D1:11": "TP-Link",
    // Netgear
    "00:09:5B": "Netgear", "00:0F:B5": "Netgear",
    "00:14:6C": "Netgear", "00:18:4D": "Netgear",
    "00:1B:2F": "Netgear", "00:1E:2A": "Netgear",
    "00:1F:33": "Netgear", "00:22:3F": "Netgear",
    "00:24:B2": "Netgear", "00:26:F2": "Netgear",
    "20:0C:C8": "Netgear", "28:80:88": "Netgear",
    "2C:B0:5D": "Netgear", "30:46:9A": "Netgear",
    "44:94:FC": "Netgear", "4C:60:DE": "Netgear",
    "6C:B0:CE": "Netgear", "84:1B:5E": "Netgear",
    "8C:3B:AD": "Netgear", "A0:04:60": "Netgear",
    "A4:2B:8C": "Netgear", "B0:7F:B9": "Netgear",
    "C0:3F:0E": "Netgear", "C4:04:15": "Netgear",
    "E0:46:9A": "Netgear", "E0:91:F5": "Netgear",
    // Raspberry Pi
    "28:CD:C1": "Raspberry Pi", "B8:27:EB": "Raspberry Pi",
    "D8:3A:DD": "Raspberry Pi", "DC:A6:32": "Raspberry Pi",
    "E4:5F:01": "Raspberry Pi",
    // Amazon (Echo, Fire, etc.)
    "00:FC:8B": "Amazon", "0C:47:C9": "Amazon",
    "10:CE:A9": "Amazon", "18:74:2E": "Amazon",
    "34:D2:70": "Amazon", "38:F7:3D": "Amazon",
    "40:A2:DB": "Amazon", "44:65:0D": "Amazon",
    "4C:EF:C0": "Amazon", "50:DC:E7": "Amazon",
    "5C:41:5A": "Amazon", "68:37:E9": "Amazon",
    "68:54:FD": "Amazon", "74:C2:46": "Amazon",
    "84:D6:D0": "Amazon", "A0:02:DC": "Amazon",
    "AC:63:BE": "Amazon", "B4:7C:9C": "Amazon",
    "F0:F0:A4": "Amazon", "FC:65:DE": "Amazon",
    // Sonos
    "00:0E:58": "Sonos", "34:7E:5C": "Sonos",
    "48:A6:B8": "Sonos", "54:2A:1B": "Sonos",
    "5C:AA:FD": "Sonos", "78:28:CA": "Sonos",
    "94:9F:3E": "Sonos", "B8:E9:37": "Sonos",
    // Microsoft (Xbox, Surface)
    "00:15:5D": "Microsoft", "00:17:FA": "Microsoft",
    "00:1D:D8": "Microsoft", "00:22:48": "Microsoft",
    "00:25:AE": "Microsoft", "00:50:F2": "Microsoft",
    "28:18:78": "Microsoft", "7C:1E:52": "Microsoft",
    // Sony (PlayStation)
    "00:04:1F": "Sony", "00:13:A9": "Sony",
    "00:15:C1": "Sony", "00:19:63": "Sony",
    "00:1A:80": "Sony", "00:1D:0D": "Sony",
    "00:1F:A7": "Sony", "00:24:8D": "Sony",
    "28:0D:FC": "Sony", "2C:CC:44": "Sony",
    "70:9E:29": "Sony", "78:C8:81": "Sony",
    "A8:E3:EE": "Sony", "AC:B3:13": "Sony",
    "BC:60:A7": "Sony", "F8:D0:AC": "Sony",
    // Synology
    "00:11:32": "Synology",
    // QNAP
    "00:08:9B": "QNAP", "24:5E:BE": "QNAP",
    // HP
    "00:01:E6": "HP", "00:01:E7": "HP", "00:02:A5": "HP",
    "00:04:EA": "HP", "00:08:02": "HP", "00:0A:57": "HP",
    "00:0B:CD": "HP", "00:0D:9D": "HP", "00:0E:7F": "HP",
    "00:0F:20": "HP", "00:0F:61": "HP", "00:10:83": "HP",
    "00:11:0A": "HP", "00:11:85": "HP", "00:12:79": "HP",
    "00:13:21": "HP", "00:14:38": "HP", "00:14:C2": "HP",
    "00:15:60": "HP", "00:17:A4": "HP", "00:18:FE": "HP",
    "00:19:BB": "HP", "00:1A:4B": "HP", "00:1B:78": "HP",
    "00:1C:C4": "HP", "00:1E:0B": "HP", "00:1F:29": "HP",
    "00:21:5A": "HP", "00:22:64": "HP", "00:23:7D": "HP",
    "00:24:81": "HP", "00:25:B3": "HP", "00:26:55": "HP",
    "00:30:6E": "HP", "00:30:C1": "HP",
    // Freebox
    "00:07:CB": "Freebox", "00:24:D4": "Freebox",
    "14:0C:76": "Freebox", "24:95:04": "Freebox",
    "34:27:92": "Freebox", "40:CA:63": "Freebox",
    "54:64:D9": "Freebox", "68:A3:78": "Freebox",
    "78:94:B4": "Freebox", "8C:97:EA": "Freebox",
    "BC:30:7E": "Freebox", "E4:9E:12": "Freebox",
    "F4:CA:E5": "Freebox",
    // Livebox (Orange)
    "00:1E:74": "Livebox", "28:FA:A0": "Livebox",
    "34:8A:AE": "Livebox", "58:11:22": "Livebox",
    "64:7C:34": "Livebox", "7C:03:4C": "Livebox",
    "84:A1:D1": "Livebox", "E8:AD:A6": "Livebox",
    // Bbox (Bouygues)
    "00:1A:2B": "Bbox", "E8:F1:B0": "Bbox",
    // SFR Box
    "00:1F:9F": "SFR Box", "30:D3:2D": "SFR Box",
    "68:A3:C4": "SFR Box", "9C:C8:FC": "SFR Box",
]

/// Recherche le fabricant a partir d'une adresse MAC.
private func lookupVendor(mac: String) -> String? {
    let prefix = mac.uppercased().components(separatedBy: ":").prefix(3).joined(separator: ":")
    return ouiTable[prefix]
}

// MARK: - Network Scanner

/// Service de scan reseau: ping sweep, ARP, DNS inverse, Bonjour.
class NetworkScanner {

    /// Recupere l'IP locale et le masque du sous-reseau de l'interface active.
    func getLocalSubnet() -> (ip: String, mask: String, prefix: Int)? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let flags = Int32(ptr.pointee.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0 else { continue }
            guard ptr.pointee.ifa_addr.pointee.sa_family == UInt8(AF_INET) else { continue }

            let name = String(cString: ptr.pointee.ifa_name)
            guard name.hasPrefix("en") else { continue }

            var ip = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            var mask = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))

            let addr = ptr.pointee.ifa_addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
            var addrCopy = addr.sin_addr
            inet_ntop(AF_INET, &addrCopy, &ip, socklen_t(INET_ADDRSTRLEN))

            let netmask = ptr.pointee.ifa_netmask.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
            var maskCopy = netmask.sin_addr
            inet_ntop(AF_INET, &maskCopy, &mask, socklen_t(INET_ADDRSTRLEN))

            let maskInt = UInt32(bigEndian: netmask.sin_addr.s_addr)
            var prefix = 0
            var m = maskInt
            while m & 0x80000000 != 0 { prefix += 1; m <<= 1 }

            return (String(cString: ip), String(cString: mask), prefix)
        }
        return nil
    }

    /// Genere toutes les IPs hotes d'un sous-reseau.
    func generateIPRange(ip: String, mask: String) -> [String] {
        let ipParts = ip.split(separator: ".").compactMap { UInt32($0) }
        let maskParts = mask.split(separator: ".").compactMap { UInt32($0) }
        guard ipParts.count == 4, maskParts.count == 4 else { return [] }

        let ipInt = (ipParts[0] << 24) | (ipParts[1] << 16) | (ipParts[2] << 8) | ipParts[3]
        let maskInt = (maskParts[0] << 24) | (maskParts[1] << 16) | (maskParts[2] << 8) | maskParts[3]

        let network = ipInt & maskInt
        let broadcast = network | ~maskInt
        let hostCount = broadcast - network

        // Limiter a /22 max (1022 hotes) pour eviter des scans trop longs
        guard hostCount > 1, hostCount <= 1022 else { return [] }

        var ips: [String] = []
        for i in (network + 1)..<broadcast {
            ips.append("\(i >> 24 & 0xFF).\(i >> 16 & 0xFF).\(i >> 8 & 0xFF).\(i & 0xFF)")
        }
        return ips
    }

    /// Ping ICMP une seule IP. Retourne la latence ou nil si timeout.
    func ping(ip: String, timeout: TimeInterval = 0.5) -> Double? {
        var hints = addrinfo()
        hints.ai_family = AF_INET
        hints.ai_socktype = SOCK_DGRAM
        var infoPtr: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(ip, nil, &hints, &infoPtr) == 0, let info = infoPtr else { return nil }
        defer { freeaddrinfo(infoPtr) }

        let sock = Darwin.socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP)
        guard sock >= 0 else { return nil }
        defer { Darwin.close(sock) }

        var tv = timeval(tv_sec: 0, tv_usec: Int32(timeout * 1_000_000))
        setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        let pid = UInt16(ProcessInfo.processInfo.processIdentifier & 0xFFFF)
        let seq = UInt16.random(in: 0...UInt16.max)
        var packet = [UInt8](repeating: 0, count: 64)
        packet[0] = 8 // Echo Request
        packet[4] = UInt8(pid >> 8); packet[5] = UInt8(pid & 0xFF)
        packet[6] = UInt8(seq >> 8); packet[7] = UInt8(seq & 0xFF)

        var sum: UInt32 = 0
        for i in stride(from: 0, to: packet.count - 1, by: 2) {
            sum += UInt32(packet[i]) << 8 | UInt32(packet[i + 1])
        }
        while sum >> 16 != 0 { sum = (sum & 0xFFFF) + (sum >> 16) }
        let checksum = ~UInt16(sum)
        packet[2] = UInt8(checksum >> 8); packet[3] = UInt8(checksum & 0xFF)

        let startTime = CFAbsoluteTimeGetCurrent()
        let sent = packet.withUnsafeBytes { buf in
            sendto(sock, buf.baseAddress, buf.count, 0, info.pointee.ai_addr, socklen_t(info.pointee.ai_addrlen))
        }
        guard sent > 0 else { return nil }

        var recvBuf = [UInt8](repeating: 0, count: 1024)
        var srcAddr = sockaddr_in()
        var srcLen = socklen_t(MemoryLayout<sockaddr_in>.size)
        let recvLen = withUnsafeMutablePointer(to: &srcAddr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                recvfrom(sock, &recvBuf, recvBuf.count, 0, sa, &srcLen)
            }
        }
        guard recvLen > 0 else { return nil }

        // Verifier que la reponse vient bien de l'IP ciblee (inet_ntop est thread-safe)
        var respBuf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        var addrCopy = srcAddr.sin_addr
        inet_ntop(AF_INET, &addrCopy, &respBuf, socklen_t(INET_ADDRSTRLEN))
        let respIP = String(cString: respBuf)
        guard respIP == ip else { return nil }

        // Verifier que c'est un Echo Reply (type 0) — le header IP (20 octets) precede le payload ICMP
        let ipHeaderLen: Int
        if recvLen > 20 && (recvBuf[0] & 0xF0) == 0x40 {
            ipHeaderLen = Int(recvBuf[0] & 0x0F) * 4
        } else {
            ipHeaderLen = 0
        }
        if ipHeaderLen + 1 < recvLen {
            let icmpType = recvBuf[ipHeaderLen]
            guard icmpType == 0 else { return nil } // 0 = Echo Reply
        }

        return (CFAbsoluteTimeGetCurrent() - startTime) * 1000
    }

    /// Resolution DNS inverse.
    func reverseDNS(ip: String) -> String? {
        var hints = addrinfo()
        hints.ai_family = AF_INET
        var infoPtr: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(ip, nil, &hints, &infoPtr) == 0, let info = infoPtr else { return nil }
        defer { freeaddrinfo(infoPtr) }

        var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let result = getnameinfo(info.pointee.ai_addr, info.pointee.ai_addrlen,
                                 &hostname, socklen_t(NI_MAXHOST), nil, 0, 0)
        guard result == 0 else { return nil }
        let name = String(cString: hostname)
        // Ne pas retourner l'IP elle-meme
        if name == ip { return nil }
        return name
    }

    /// Lit la table ARP du systeme via sysctl.
    func readARPTable() -> [String: String] {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, AF_INET, NET_RT_FLAGS, RTF_LLINFO]
        var size: Int = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &size, nil, 0) == 0, size > 0 else { return [:] }

        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, UInt32(mib.count), &buffer, &size, nil, 0) == 0 else { return [:] }

        var result: [String: String] = [:]
        var offset = 0

        while offset < size {
            let rtm = buffer.withUnsafeBytes { ptr -> rt_msghdr in
                ptr.load(fromByteOffset: offset, as: rt_msghdr.self)
            }

            let msgLen = Int(rtm.rtm_msglen)
            guard msgLen > 0 else { break }

            // sockaddr_inarp suit rt_msghdr
            let saOffset = offset + MemoryLayout<rt_msghdr>.size
            if saOffset + MemoryLayout<sockaddr_in>.size <= offset + msgLen {
                let sin = buffer.withUnsafeBytes { ptr -> sockaddr_in in
                    ptr.load(fromByteOffset: saOffset, as: sockaddr_in.self)
                }

                if sin.sin_family == UInt8(AF_INET) {
                    var addrCopy = sin.sin_addr
                    var ipBuf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                    inet_ntop(AF_INET, &addrCopy, &ipBuf, socklen_t(INET_ADDRSTRLEN))
                    let ip = String(cString: ipBuf)

                    // sockaddr_dl suit sockaddr_in (aligne)
                    let sdlOffset = saOffset + Int(sin.sin_len)
                    if sdlOffset + 20 <= offset + msgLen {
                        let sdl = buffer.withUnsafeBytes { ptr -> sockaddr_dl in
                            ptr.load(fromByteOffset: sdlOffset, as: sockaddr_dl.self)
                        }

                        let alen = Int(sdl.sdl_alen)
                        if alen == 6 {
                            let macOffset = sdlOffset + 8 + Int(sdl.sdl_nlen)
                            if macOffset + 6 <= offset + msgLen {
                                let mac = (0..<6).map { String(format: "%02X", buffer[macOffset + $0]) }.joined(separator: ":")
                                if mac != "00:00:00:00:00:00" {
                                    result[ip] = mac
                                }
                            }
                        }
                    }
                }
            }

            offset += msgLen
        }

        return result
    }
}

// MARK: - Window Controller

class NeighborhoodWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {

    private var tableView: NSTableView!
    private var scanButton: NSButton!
    private var subnetLabel: NSTextField!
    private var statusLabel: NSTextField!
    private var progressIndicator: NSProgressIndicator!

    private let scanner = NetworkScanner()
    private let devicesLock = NSLock()
    private var devices: [NetworkDevice] = []
    private var isScanning = false
    private var bonjourBrowsers: [NWBrowser] = [] // liste des browsers Bonjour actifs
    private var bonjourServices: [String: Set<String>] = [:] // ip -> set of service names

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 750, height: 500),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = NSLocalizedString("neighborhood.window.title", comment: "")
        window.center()
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 600, height: 350)

        self.init(window: window)
        setupUI()
        updateSubnetInfo()
    }

    private func setupUI() {
        guard let contentView = window?.contentView else { return }
        contentView.wantsLayer = true

        // Titre
        let titleLabel = NSTextField(labelWithString: NSLocalizedString("neighborhood.title", comment: ""))
        titleLabel.font = NSFont.systemFont(ofSize: 18, weight: .semibold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(titleLabel)

        // Sous-reseau
        subnetLabel = NSTextField(labelWithString: NSLocalizedString("neighborhood.subnet.loading", comment: ""))
        subnetLabel.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        subnetLabel.textColor = .secondaryLabelColor
        subnetLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(subnetLabel)

        // Status
        statusLabel = NSTextField(labelWithString: NSLocalizedString("neighborhood.status.ready", comment: ""))
        statusLabel.font = NSFont.systemFont(ofSize: 11)
        statusLabel.textColor = .tertiaryLabelColor
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(statusLabel)

        // Progress
        progressIndicator = NSProgressIndicator()
        progressIndicator.style = .bar
        progressIndicator.minValue = 0
        progressIndicator.maxValue = 100
        progressIndicator.isHidden = true
        progressIndicator.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(progressIndicator)

        // Tableau
        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        contentView.addSubview(scrollView)

        tableView = NSTableView()
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 22
        tableView.usesAlternatingRowBackgroundColors = true

        let ipCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("ip"))
        ipCol.title = NSLocalizedString("neighborhood.column.ip", comment: "")
        ipCol.width = 120
        tableView.addTableColumn(ipCol)

        let nameCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        nameCol.title = NSLocalizedString("neighborhood.column.name", comment: "")
        nameCol.width = 160
        tableView.addTableColumn(nameCol)

        let latencyCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("latency"))
        latencyCol.title = NSLocalizedString("neighborhood.column.latency", comment: "")
        latencyCol.width = 70
        tableView.addTableColumn(latencyCol)

        let macCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("mac"))
        macCol.title = NSLocalizedString("neighborhood.column.mac", comment: "")
        macCol.width = 140
        tableView.addTableColumn(macCol)

        let vendorCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("vendor"))
        vendorCol.title = NSLocalizedString("neighborhood.column.vendor", comment: "")
        vendorCol.width = 100
        tableView.addTableColumn(vendorCol)

        let servicesCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("services"))
        servicesCol.title = NSLocalizedString("neighborhood.column.services", comment: "")
        servicesCol.width = 120
        tableView.addTableColumn(servicesCol)

        tableView.doubleAction = #selector(tableDoubleClick)
        tableView.target = self
        scrollView.documentView = tableView

        // Bouton scanner en bas
        let bottomBar = NSStackView()
        bottomBar.orientation = .horizontal
        bottomBar.spacing = 12
        bottomBar.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(bottomBar)

        scanButton = NSButton(title: NSLocalizedString("neighborhood.button.scan", comment: ""), target: self, action: #selector(startScan))
        scanButton.bezelStyle = .rounded
        bottomBar.addArrangedSubview(scanButton)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        bottomBar.addArrangedSubview(spacer)

        let countLabel = NSTextField(labelWithString: "")
        countLabel.font = NSFont.systemFont(ofSize: 11)
        countLabel.textColor = .secondaryLabelColor
        countLabel.tag = 999
        bottomBar.addArrangedSubview(countLabel)

        // Contraintes
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            titleLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),

            subnetLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            subnetLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),

            statusLabel.topAnchor.constraint(equalTo: subnetLabel.bottomAnchor, constant: 4),
            statusLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),

            progressIndicator.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 8),
            progressIndicator.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            progressIndicator.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),

            scrollView.topAnchor.constraint(equalTo: progressIndicator.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            scrollView.bottomAnchor.constraint(equalTo: bottomBar.topAnchor, constant: -8),

            bottomBar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            bottomBar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            bottomBar.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),
            bottomBar.heightAnchor.constraint(equalToConstant: 28),
        ])
    }

    private func updateSubnetInfo() {
        if let subnet = scanner.getLocalSubnet() {
            subnetLabel.stringValue = String(format: NSLocalizedString("neighborhood.subnet.detected", comment: ""), subnet.ip, subnet.prefix)
        } else {
            subnetLabel.stringValue = NSLocalizedString("neighborhood.subnet.notfound", comment: "")
        }
    }

    // MARK: - Scan

    @objc private func startScan() {
        guard !isScanning else { return }
        guard let subnet = scanner.getLocalSubnet() else {
            statusLabel.stringValue = NSLocalizedString("neighborhood.error.nosubnet", comment: "")
            return
        }

        let ips = scanner.generateIPRange(ip: subnet.ip, mask: subnet.mask)
        guard !ips.isEmpty else {
            statusLabel.stringValue = NSLocalizedString("neighborhood.error.iprange", comment: "")
            return
        }

        isScanning = true
        devicesLock.lock()
        devices.removeAll()
        devicesLock.unlock()
        tableView.reloadData()
        scanButton.isEnabled = false
        progressIndicator.isHidden = false
        progressIndicator.doubleValue = 0
        statusLabel.stringValue = NSLocalizedString("neighborhood.status.phase1", comment: "")

        // Lancer le scan Bonjour en parallele
        startBonjourDiscovery()

        let totalCount = ips.count

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            // === Phase 1 : UDP sweep pour peupler la table ARP ===
            // Envoyer un paquet UDP a chaque IP pour forcer la resolution ARP
            // meme si la machine ne repond pas en ICMP, l'ARP se fait au niveau Ethernet
            let udpQueue = DispatchQueue(label: "udp-sweep", attributes: .concurrent)
            let udpGroup = DispatchGroup()
            let udpSemaphore = DispatchSemaphore(value: 40)

            for ip in ips {
                udpGroup.enter()
                udpQueue.async {
                    udpSemaphore.wait()
                    // Envoyer un paquet UDP sur un port improbable pour declencher l'ARP
                    let sock = Darwin.socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
                    if sock >= 0 {
                        var addr = sockaddr_in()
                        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
                        addr.sin_family = sa_family_t(AF_INET)
                        addr.sin_port = UInt16(39_127).bigEndian
                        inet_pton(AF_INET, ip, &addr.sin_addr)

                        let data: [UInt8] = [0]
                        withUnsafePointer(to: &addr) { ptr in
                            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                                _ = data.withUnsafeBytes { buf in
                                    sendto(sock, buf.baseAddress, buf.count, 0, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
                                }
                            }
                        }
                        Darwin.close(sock)
                    }
                    udpSemaphore.signal()
                    udpGroup.leave()
                }
            }
            udpGroup.wait()

            // Laisser le temps aux reponses ARP d'arriver
            usleep(500_000) // 500ms

            DispatchQueue.main.async {
                self.statusLabel.stringValue = NSLocalizedString("neighborhood.status.phase2", comment: "")
            }

            // === Phase 2 : Ping ICMP sweep ===
            let pingQueue = DispatchQueue(label: "ping-sweep", qos: .userInitiated, attributes: .concurrent)
            let pingGroup = DispatchGroup()
            let pingSemaphore = DispatchSemaphore(value: 20)
            var scannedCount = 0
            var foundIPs = Set<String>()

            // Lire la table ARP (apres le sweep UDP)
            let arpTable = self.scanner.readARPTable()

            for ip in ips {
                pingGroup.enter()
                pingQueue.async { [weak self] in
                    guard let self = self else { pingGroup.leave(); return }

                    // Avoid indefinite blocking to prevent QoS inversions
                    if pingSemaphore.wait(timeout: .now() + 1.0) == .timedOut {
                        // Skip this IP if we couldn't acquire a permit promptly
                        pingGroup.leave()
                        return
                    }

                    let latency = self.scanner.ping(ip: ip, timeout: 0.8)
                    pingSemaphore.signal()

                    if let latency = latency {
                        let device = NetworkDevice(ipAddress: ip)
                        device.latencyMs = latency

                        if let mac = arpTable[ip] {
                            device.macAddress = mac
                            device.vendor = lookupVendor(mac: mac)
                        }

                        device.hostname = self.scanner.reverseDNS(ip: ip)

                        devicesLock.lock()
                        self.devices.append(device)
                        foundIPs.insert(ip)
                        devicesLock.unlock()
                    }

                    devicesLock.lock()
                    scannedCount += 1
                    let progress = Double(scannedCount) / Double(totalCount) * 100
                    let deviceCount = self.devices.count
                    devicesLock.unlock()

                    DispatchQueue.main.async {
                        self.progressIndicator.doubleValue = progress
                        self.statusLabel.stringValue = String(format: NSLocalizedString("neighborhood.status.phase2.progress", comment: ""), scannedCount, totalCount, deviceCount)
                        self.devicesLock.lock()
                        let snapshot = self.devices.sorted { self.ipToInt($0.ipAddress) < self.ipToInt($1.ipAddress) }
                        self.devices = snapshot
                        self.devicesLock.unlock()
                        self.tableView.reloadData()
                    }

                    pingGroup.leave()
                }
            }
            pingGroup.wait()

            // === Phase 3 : Recuperer les machines ARP non trouvees par ICMP ===
            DispatchQueue.main.async {
                self.statusLabel.stringValue = NSLocalizedString("neighborhood.status.phase3", comment: "")
            }

            // Relire la table ARP (elle peut avoir ete enrichie)
            let finalArpTable = self.scanner.readARPTable()
            let dnsQueue = DispatchQueue(label: "dns-resolve", attributes: .concurrent)
            let dnsGroup = DispatchGroup()
            let dnsSemaphore = DispatchSemaphore(value: 10)

            for (ip, mac) in finalArpTable {
                // Ignorer les machines deja trouvees par ping
                devicesLock.lock()
                let alreadyFound = foundIPs.contains(ip)
                devicesLock.unlock()
                if alreadyFound { continue }

                // Ignorer les MAC broadcast/multicast
                if mac == "FF:FF:FF:FF:FF:FF" { continue }

                // Verifier que l'IP est dans notre sous-reseau
                guard ips.contains(ip) else { continue }

                dnsGroup.enter()
                dnsQueue.async { [weak self] in
                    guard let self = self else { dnsGroup.leave(); return }

                    dnsSemaphore.wait()
                    let device = NetworkDevice(ipAddress: ip)
                    device.macAddress = mac
                    device.vendor = lookupVendor(mac: mac)
                    device.hostname = self.scanner.reverseDNS(ip: ip)
                    // Pas de latence car n'a pas repondu au ping
                    dnsSemaphore.signal()

                    devicesLock.lock()
                    self.devices.append(device)
                    devicesLock.unlock()

                    dnsGroup.leave()
                }
            }
            dnsGroup.wait()

            // Mise a jour finale sur le main thread
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.enrichWithBonjour()

                self.devicesLock.lock()
                // Aussi enrichir les MAC pour les devices trouves par ping qui n'avaient pas de MAC
                for device in self.devices {
                    if device.macAddress == nil, let mac = finalArpTable[device.ipAddress] {
                        device.macAddress = mac
                        device.vendor = lookupVendor(mac: mac)
                    }
                }

                self.devices.sort { self.ipToInt($0.ipAddress) < self.ipToInt($1.ipAddress) }
                let finalCount = self.devices.count
                self.devicesLock.unlock()

                self.tableView.reloadData()

                self.isScanning = false
                self.scanButton.isEnabled = true
                self.progressIndicator.isHidden = true
                self.statusLabel.stringValue = String(format: NSLocalizedString("neighborhood.status.done", comment: ""), finalCount)

                for b in self.bonjourBrowsers { b.cancel() }
                self.bonjourBrowsers.removeAll()
            }
        }
    }

    private func ipToInt(_ ip: String) -> UInt32 {
        let parts = ip.split(separator: ".").compactMap { UInt32($0) }
        guard parts.count == 4 else { return 0 }
        return (parts[0] << 24) | (parts[1] << 16) | (parts[2] << 8) | parts[3]
    }

    // MARK: - Bonjour Discovery

    private func startBonjourDiscovery() {
        bonjourServices.removeAll()
        bonjourBrowsers.removeAll()

        // Decouvrir les services courants
        let serviceTypes = [
            "_http._tcp", "_https._tcp", "_ssh._tcp", "_sftp-ssh._tcp",
            "_smb._tcp", "_afpovertcp._tcp", "_nfs._tcp",
            "_airplay._tcp", "_raop._tcp", "_airplay._tcp",
            "_ipp._tcp", "_ipps._tcp", "_printer._tcp", "_pdl-datastream._tcp",
            "_companion-link._tcp", "_homekit._tcp",
            "_googlecast._tcp", "_spotify-connect._tcp",
        ]

        for serviceType in serviceTypes {
            let params = NWParameters()
            params.includePeerToPeer = true
            let browser = NWBrowser(for: .bonjour(type: serviceType, domain: "local."), using: params)
            bonjourBrowsers.append(browser)

            browser.browseResultsChangedHandler = { [weak self] results, _ in
                for result in results {
                    if case .bonjour(let txtRecord) = result.metadata {
                        _ = txtRecord // on pourrait extraire des infos
                    }
                    if case .service(let name, let type, let domain, _) = result.endpoint {
                        // Resoudre l'endpoint pour obtenir l'IP
                        self?.resolveBonjourService(name: name, type: type, domain: domain, serviceType: serviceType)
                    }
                }
            }

            browser.stateUpdateHandler = { _ in }
            browser.start(queue: .global(qos: .utility))

            // On laisse tourner pendant le scan, on arretera a la fin
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
                browser.cancel()
            }
        }
    }

    private func resolveBonjourService(name: String, type: String, domain: String, serviceType: String) {
        // Utiliser getaddrinfo pour resoudre le nom Bonjour
        let fullName = "\(name).\(type)\(domain)"
        var hints = addrinfo()
        hints.ai_family = AF_INET
        var infoPtr: UnsafeMutablePointer<addrinfo>?

        // Essayer de resoudre le hostname via DNS
        let hostname = "\(name).local"
        if getaddrinfo(hostname, nil, &hints, &infoPtr) == 0, let info = infoPtr {
            defer { freeaddrinfo(infoPtr) }
            let addr = info.pointee.ai_addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
            var addrCopy = addr.sin_addr
            var ipBuf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            inet_ntop(AF_INET, &addrCopy, &ipBuf, socklen_t(INET_ADDRSTRLEN))
            let ip = String(cString: ipBuf)

            // Extraire un nom de service lisible
            let friendlyName = friendlyServiceName(serviceType)

            DispatchQueue.main.async { [weak self] in
                if self?.bonjourServices[ip] == nil {
                    self?.bonjourServices[ip] = Set<String>()
                }
                self?.bonjourServices[ip]?.insert(friendlyName)
            }
        }
    }

    private func friendlyServiceName(_ type: String) -> String {
        switch type {
        case "_http._tcp": return "HTTP"
        case "_https._tcp": return "HTTPS"
        case "_ssh._tcp": return "SSH"
        case "_sftp-ssh._tcp": return "SFTP"
        case "_smb._tcp": return "SMB"
        case "_afpovertcp._tcp": return "AFP"
        case "_nfs._tcp": return "NFS"
        case "_airplay._tcp": return "AirPlay"
        case "_raop._tcp": return "AirPlay"
        case "_ipp._tcp", "_ipps._tcp": return NSLocalizedString("neighborhood.service.printer", comment: "")
        case "_printer._tcp", "_pdl-datastream._tcp": return NSLocalizedString("neighborhood.service.printer", comment: "")
        case "_companion-link._tcp": return "Companion"
        case "_homekit._tcp": return "HomeKit"
        case "_googlecast._tcp": return "Chromecast"
        case "_spotify-connect._tcp": return "Spotify"
        default: return type
        }
    }

    private func enrichWithBonjour() {
        for device in devices {
            if let services = bonjourServices[device.ipAddress], !services.isEmpty {
                device.services = Array(services).sorted()
            }
        }
    }

    // MARK: - NSTableViewDataSource

    func numberOfRows(in tableView: NSTableView) -> Int {
        devicesLock.lock()
        let count = devices.count
        devicesLock.unlock()
        return count
    }

    // MARK: - NSTableViewDelegate

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        devicesLock.lock()
        guard row < devices.count else {
            devicesLock.unlock()
            return nil
        }
        let device = devices[row]
        devicesLock.unlock()

        let identifier = tableColumn?.identifier ?? NSUserInterfaceItemIdentifier("")
        let cellId = NSUserInterfaceItemIdentifier("Cell_\(identifier.rawValue)")

        let textField: NSTextField
        if let existing = tableView.makeView(withIdentifier: cellId, owner: nil) as? NSTextField {
            textField = existing
        } else {
            textField = NSTextField(labelWithString: "")
            textField.identifier = cellId
            textField.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        }

        switch identifier.rawValue {
        case "ip":
            textField.stringValue = device.ipAddress
        case "name":
            textField.stringValue = device.displayName
            textField.font = NSFont.systemFont(ofSize: 11)
        case "latency":
            if let latency = device.latencyMs {
                textField.stringValue = String(format: "%.1f ms", latency)
            } else {
                textField.stringValue = "—"
            }
        case "mac":
            textField.stringValue = device.macAddress ?? "—"
        case "vendor":
            textField.stringValue = device.vendor ?? "—"
            textField.font = NSFont.systemFont(ofSize: 11)
        case "services":
            textField.stringValue = device.servicesString
            textField.font = NSFont.systemFont(ofSize: 11)
        default:
            textField.stringValue = ""
        }

        return textField
    }

    @objc private func tableDoubleClick() {
        let row = tableView.clickedRow
        devicesLock.lock()
        guard row >= 0, row < devices.count else {
            devicesLock.unlock()
            return
        }
        let device = devices[row]
        devicesLock.unlock()
        let detailCtrl = DeviceDetailWindowController(device: device, scanner: scanner, bonjourServices: bonjourServices)
        detailCtrl.showWindow(nil)
        detailCtrl.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        // Retenir la fenetre
        deviceDetailWindows.append(detailCtrl)
    }

    private var deviceDetailWindows: [DeviceDetailWindowController] = []

    override func close() {
        for b in bonjourBrowsers { b.cancel() }
        bonjourBrowsers.removeAll()
        super.close()
    }
}

// MARK: - Device Detail Window

class DeviceDetailWindowController: NSWindowController {

    private let device: NetworkDevice
    private let scanner: NetworkScanner
    private let bonjourServices: [String: Set<String>]
    private var textView: NSTextView!

    init(device: NetworkDevice, scanner: NetworkScanner, bonjourServices: [String: Set<String>]) {
        self.device = device
        self.scanner = scanner
        self.bonjourServices = bonjourServices

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 520),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = String(format: NSLocalizedString("neighborhood.detail.window.title", comment: ""), device.displayName)
        window.center()
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 400, height: 300)

        super.init(window: window)
        setupUI()
        runDetailScan()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupUI() {
        guard let contentView = window?.contentView else { return }

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        contentView.addSubview(scrollView)

        textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textContainerInset = NSSize(width: 16, height: 16)
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        scrollView.documentView = textView

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: contentView.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
    }

    private func runDetailScan() {
        let ip = device.ipAddress

        // Afficher les infos connues immediatement
        var text = ""
        text += sectionTitle(NSLocalizedString("neighborhood.detail.section.id", comment: ""))
        text += line(NSLocalizedString("neighborhood.detail.ip", comment: ""), ip)
        text += line(NSLocalizedString("neighborhood.detail.hostname", comment: ""), device.hostname ?? NSLocalizedString("neighborhood.detail.unknown", comment: ""))
        if let mac = device.macAddress {
            text += line(NSLocalizedString("neighborhood.detail.mac", comment: ""), mac)
        } else {
            text += line(NSLocalizedString("neighborhood.detail.mac", comment: ""), NSLocalizedString("neighborhood.detail.unavailable", comment: ""))
        }
        text += line(NSLocalizedString("neighborhood.detail.vendor", comment: ""), device.vendor ?? NSLocalizedString("neighborhood.detail.unknown", comment: ""))
        if let latency = device.latencyMs {
            text += line(NSLocalizedString("neighborhood.detail.initial.latency", comment: ""), String(format: "%.1f ms", latency))
        }

        // Services Bonjour
        text += "\n"
        text += sectionTitle(NSLocalizedString("neighborhood.detail.section.bonjour", comment: ""))
        if let services = bonjourServices[ip], !services.isEmpty {
            for svc in services.sorted() {
                text += "  \u{2022} \(svc)\n"
            }
        } else {
            text += "  \(NSLocalizedString("neighborhood.detail.noservices", comment: ""))\n"
        }

        text += "\n"
        text += sectionTitle(NSLocalizedString("neighborhood.detail.section.analyzing", comment: ""))
        text += "  \(NSLocalizedString("neighborhood.detail.analyzing.desc", comment: ""))\n"

        setTextViewContent(text)

        // Lancer les analyses en arriere-plan
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            // 1. Ping x10
            var pings: [Double] = []
            for _ in 0..<10 {
                if let latency = self.scanner.ping(ip: ip, timeout: 1.0) {
                    pings.append(latency)
                }
                usleep(100_000) // 100ms entre chaque
            }

            // 2. Scan de ports courants
            let commonPorts: [(Int, String)] = [
                (21, "FTP"), (22, "SSH"), (23, "Telnet"), (53, "DNS"),
                (80, "HTTP"), (443, "HTTPS"), (445, "SMB"),
                (548, "AFP"), (631, "IPP"), (3389, "RDP"),
                (5000, "UPnP"), (5353, "mDNS"), (8080, "HTTP-Alt"),
                (8443, "HTTPS-Alt"), (9090, "Web Admin"), (62078, "iPhone Sync"),
            ]
            var openPorts: [(Int, String)] = []
            for (port, name) in commonPorts {
                if self.isPortOpen(ip: ip, port: port, timeout: 0.3) {
                    openPorts.append((port, name))
                }
            }

            // 3. DNS inverse complet (deja fait mais on le refait pour afficher)
            let hostname = self.scanner.reverseDNS(ip: ip)

            // 4. Determiner le type d'appareil
            let deviceType = self.guessDeviceType(device: self.device, services: self.bonjourServices[ip], openPorts: openPorts)

            // Construire le resultat final
            DispatchQueue.main.async {
                var result = ""
                result += self.sectionTitle(NSLocalizedString("neighborhood.detail.section.id", comment: ""))
                result += self.line(NSLocalizedString("neighborhood.detail.ip", comment: ""), ip)
                result += self.line(NSLocalizedString("neighborhood.detail.hostname", comment: ""), hostname ?? self.device.hostname ?? NSLocalizedString("neighborhood.detail.unknown", comment: ""))
                if let mac = self.device.macAddress {
                    result += self.line(NSLocalizedString("neighborhood.detail.mac", comment: ""), mac)
                } else {
                    result += self.line(NSLocalizedString("neighborhood.detail.mac", comment: ""), NSLocalizedString("neighborhood.detail.unavailable", comment: ""))
                }
                result += self.line(NSLocalizedString("neighborhood.detail.vendor", comment: ""), self.device.vendor ?? NSLocalizedString("neighborhood.detail.unknown", comment: ""))
                result += self.line(NSLocalizedString("neighborhood.detail.type", comment: ""), deviceType)

                // Ping
                result += "\n"
                result += self.sectionTitle(NSLocalizedString("neighborhood.detail.section.latency", comment: ""))
                if pings.isEmpty {
                    result += "  \(NSLocalizedString("neighborhood.detail.noreply", comment: ""))\n"
                } else {
                    let minP = pings.min()!
                    let maxP = pings.max()!
                    let avg = pings.reduce(0, +) / Double(pings.count)
                    let sortedPings = pings.sorted()
                    let median = sortedPings.count % 2 == 0
                        ? (sortedPings[sortedPings.count/2 - 1] + sortedPings[sortedPings.count/2]) / 2
                        : sortedPings[sortedPings.count/2]
                    // Jitter
                    var jitterSum = 0.0
                    for i in 1..<pings.count {
                        jitterSum += abs(pings[i] - pings[i-1])
                    }
                    let jitter = pings.count > 1 ? jitterSum / Double(pings.count - 1) : 0

                    result += self.line(NSLocalizedString("neighborhood.detail.replies", comment: ""), "\(pings.count)/10")
                    result += self.line(NSLocalizedString("neighborhood.detail.minimum", comment: ""), String(format: "%.2f ms", minP))
                    result += self.line(NSLocalizedString("neighborhood.detail.maximum", comment: ""), String(format: "%.2f ms", maxP))
                    result += self.line(NSLocalizedString("neighborhood.detail.average", comment: ""), String(format: "%.2f ms", avg))
                    result += self.line(NSLocalizedString("neighborhood.detail.median", comment: ""), String(format: "%.2f ms", median))
                    result += self.line(NSLocalizedString("neighborhood.detail.jitter", comment: ""), String(format: "%.2f ms", jitter))
                    result += self.line(NSLocalizedString("neighborhood.detail.loss", comment: ""), String(format: "%.0f%%", (1.0 - Double(pings.count) / 10.0) * 100))
                }

                // Ports
                result += "\n"
                result += self.sectionTitle(NSLocalizedString("neighborhood.detail.section.ports", comment: ""))
                if openPorts.isEmpty {
                    result += "  \(NSLocalizedString("neighborhood.detail.noports", comment: ""))\n"
                } else {
                    for (port, name) in openPorts.sorted(by: { $0.0 < $1.0 }) {
                        result += "  \(String(format: "%5d", port))  \(name)\n"
                    }
                }

                // Services Bonjour
                result += "\n"
                result += self.sectionTitle(NSLocalizedString("neighborhood.detail.section.bonjour", comment: ""))
                if let services = self.bonjourServices[ip], !services.isEmpty {
                    for svc in services.sorted() {
                        result += "  \u{2022} \(svc)\n"
                    }
                } else {
                    result += "  \(NSLocalizedString("neighborhood.detail.noservices", comment: ""))\n"
                }

                self.setTextViewContent(result)
            }
        }
    }

    private func isPortOpen(ip: String, port: Int, timeout: TimeInterval) -> Bool {
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = UInt16(port).bigEndian
        inet_pton(AF_INET, ip, &addr.sin_addr)

        let sock = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else { return false }
        defer { Darwin.close(sock) }

        // Non-blocking
        var flags = fcntl(sock, F_GETFL, 0)
        flags |= O_NONBLOCK
        fcntl(sock, F_SETFL, flags)

        let result = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                Darwin.connect(sock, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        if result == 0 { return true }
        guard errno == EINPROGRESS else { return false }

        // Attendre avec poll
        var pfd = pollfd(fd: sock, events: Int16(POLLOUT), revents: 0)
        let pollResult = poll(&pfd, 1, Int32(timeout * 1000))
        guard pollResult > 0 else { return false }

        var error: Int32 = 0
        var errorLen = socklen_t(MemoryLayout<Int32>.size)
        getsockopt(sock, SOL_SOCKET, SO_ERROR, &error, &errorLen)
        return error == 0
    }

    private func guessDeviceType(device: NetworkDevice, services: Set<String>?, openPorts: [(Int, String)]) -> String {
        let vendor = device.vendor ?? ""
        let hostname = (device.hostname ?? "").lowercased()
        let svcSet = services ?? Set<String>()
        let ports = Set(openPorts.map { $0.0 })

        // Par vendor
        if vendor == "Apple" {
            if hostname.contains("iphone") || hostname.contains("ipad") { return "iPhone/iPad" }
            if hostname.contains("macbook") || hostname.contains("mbp") || hostname.contains("mba") { return "MacBook" }
            if hostname.contains("imac") { return "iMac" }
            if hostname.contains("mac-mini") || hostname.contains("macmini") { return "Mac mini" }
            if hostname.contains("mac-pro") || hostname.contains("macpro") { return "Mac Pro" }
            if hostname.contains("appletv") || hostname.contains("apple-tv") { return "Apple TV" }
            if svcSet.contains("AirPlay") && !ports.contains(22) && !ports.contains(445) { return NSLocalizedString("neighborhood.device.appletv.homepod", comment: "") }
            if ports.contains(62078) { return "iPhone/iPad" }
            return NSLocalizedString("neighborhood.device.apple", comment: "")
        }
        if vendor == "Samsung" { return NSLocalizedString("neighborhood.device.samsung", comment: "") }
        if vendor == "Google" {
            if svcSet.contains("Chromecast") { return "Chromecast" }
            return NSLocalizedString("neighborhood.device.google", comment: "")
        }
        if vendor == "Amazon" { return "Amazon Echo / Fire" }
        if vendor == "Sonos" { return NSLocalizedString("neighborhood.device.sonos", comment: "") }
        if vendor == "Sony" { return "PlayStation / Sony" }
        if vendor == "Raspberry Pi" { return "Raspberry Pi" }
        if vendor == "Synology" { return NSLocalizedString("neighborhood.device.synology", comment: "") }
        if vendor == "QNAP" { return NSLocalizedString("neighborhood.device.qnap", comment: "") }

        // Par services/ports
        if vendor.contains("box") || vendor.contains("Box") ||
           ["Freebox", "Livebox", "Bbox", "SFR Box"].contains(vendor) { return NSLocalizedString("neighborhood.device.router.isp", comment: "") }
        if ["Netgear", "TP-Link"].contains(vendor) { return NSLocalizedString("neighborhood.device.router.wifi", comment: "") }
        if svcSet.contains(NSLocalizedString("neighborhood.service.printer", comment: "")) || ports.contains(631) { return NSLocalizedString("neighborhood.device.printer", comment: "") }
        if ports.contains(445) || ports.contains(548) || svcSet.contains("SMB") || svcSet.contains("AFP") {
            return NSLocalizedString("neighborhood.device.server.nas", comment: "")
        }
        if ports.contains(80) || ports.contains(443) { return NSLocalizedString("neighborhood.device.server.web", comment: "") }
        if ports.contains(22) { return NSLocalizedString("neighborhood.device.server.unix", comment: "") }

        // Par hostname
        if hostname.contains("printer") || hostname.contains("imprimante") { return NSLocalizedString("neighborhood.device.printer", comment: "") }
        if hostname.contains("nas") || hostname.contains("diskstation") { return "NAS" }
        if hostname.contains("router") || hostname.contains("gateway") { return NSLocalizedString("neighborhood.device.router", comment: "") }
        if hostname.contains("switch") { return NSLocalizedString("neighborhood.device.switch", comment: "") }
        if hostname.contains("cam") || hostname.contains("camera") { return NSLocalizedString("neighborhood.device.camera", comment: "") }

        return NSLocalizedString("neighborhood.detail.unknown", comment: "")
    }

    private func sectionTitle(_ title: String) -> String {
        return "━━ \(title) ━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
    }

    private func line(_ label: String, _ value: String) -> String {
        let padding = max(1, 20 - label.count)
        return "  \(label)\(String(repeating: " ", count: padding))\(value)\n"
    }

    private func setTextViewContent(_ text: String) {
        let attrStr = NSMutableAttributedString(string: text, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: NSColor.labelColor,
        ])

        // Colorer les titres de section
        let lines = text.components(separatedBy: "\n")
        var pos = 0
        for l in lines {
            if l.hasPrefix("━━") {
                attrStr.addAttributes([
                    .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .bold),
                    .foregroundColor: NSColor.systemBlue,
                ], range: NSRange(location: pos, length: l.count))
            }
            pos += l.count + 1
        }

        textView.textStorage?.setAttributedString(attrStr)
    }
}

