import Foundation

/// Security type declared in a `WIFI:` QR code.
public enum WifiSecurity: Hashable, Sendable {
    case wpa
    case wep
    case open
    case other(String)

    init(code: String?) {
        switch code?.uppercased() {
        case nil, "", "NOPASS", "NONE": self = .open
        case "WPA", "WPA2", "WPA3", "SAE", "WPA2-EAP": self = .wpa
        case "WEP": self = .wep
        case let value?: self = .other(value)
        }
    }

    public var displayName: String {
        switch self {
        case .wpa: "WPA/WPA2/WPA3"
        case .wep: "WEP"
        case .open: String(localized: "None", comment: "Wi-Fi security of a network without a password")
        case .other(let value): value
        }
    }
}

/// Credentials parsed from a `WIFI:` QR code.
public struct WifiCredentials: Hashable, Sendable {
    public var ssid: String
    public var password: String?
    public var security: WifiSecurity
    public var hidden: Bool

    public init(ssid: String, password: String?, security: WifiSecurity, hidden: Bool) {
        self.ssid = ssid
        self.password = password
        self.security = security
        self.hidden = hidden
    }
}

/// Semantic interpretation of a decoded QR string.
public enum QRPayload: Hashable, Sendable {
    case wifi(WifiCredentials)
    case url(URL)
    case contact(String)
    case text(String)

    public static func parse(_ raw: String) -> QRPayload {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.uppercased().hasPrefix("WIFI:"), let wifi = parseWifi(trimmed) {
            return .wifi(wifi)
        }
        if trimmed.uppercased().hasPrefix("BEGIN:VCARD") {
            return .contact(raw)
        }
        if let url = parseURL(trimmed) {
            return .url(url)
        }
        return .text(raw)
    }

    /// Short one-line description, used in history menus.
    public var summary: String {
        switch self {
        case .wifi(let wifi): return "Wi-Fi: \(wifi.ssid)"
        case .url(let url): return url.absoluteString.truncated(to: 50)
        case .contact(let vcard): return String(localized: "Contact: \(Self.vcardName(vcard) ?? String(localized: "no name"))")
        case .text(let text): return text.replacingOccurrences(of: "\n", with: " ").truncated(to: 50)
        }
    }

    // MARK: - Wi-Fi

    /// Parses `WIFI:T:WPA;S:ssid;P:pass;H:true;;`. Fields may appear in any order and
    /// values may escape `\ ; , : "` with a backslash.
    static func parseWifi(_ raw: String) -> WifiCredentials? {
        var fields: [String: String] = [:]
        var current = ""
        var escaping = false
        for char in raw.dropFirst("WIFI:".count) {
            if escaping {
                current.append(char)
                escaping = false
            } else if char == "\\" {
                escaping = true
            } else if char == ";" {
                addField(current, to: &fields)
                current = ""
            } else {
                current.append(char)
            }
        }
        addField(current, to: &fields)

        guard let ssid = fields["S"], !ssid.isEmpty else { return nil }
        let security = WifiSecurity(code: fields["T"])
        let password = (security == .open) ? nil : fields["P"].flatMap { $0.isEmpty ? nil : $0 }
        let hidden = fields["H"]?.lowercased() == "true"
        return WifiCredentials(ssid: ssid, password: password, security: security, hidden: hidden)
    }

    private static func addField(_ field: String, to fields: inout [String: String]) {
        guard let colon = field.firstIndex(of: ":") else { return }
        let key = field[..<colon].uppercased()
        var value = String(field[field.index(after: colon)...])
        if value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") {
            value = String(value.dropFirst().dropLast())
        }
        fields[key] = value
    }

    // MARK: - URL

    private static let urlSchemes: Set<String> = ["http", "https", "mailto", "tel", "sms", "facetime"]

    static func parseURL(_ text: String) -> URL? {
        guard !text.contains(where: \.isWhitespace) else { return nil }
        let candidate = text.lowercased().hasPrefix("www.") ? "https://" + text : text
        guard let url = URL(string: candidate), let scheme = url.scheme?.lowercased(),
              urlSchemes.contains(scheme)
        else { return nil }
        if scheme.hasPrefix("http"), (url.host ?? "").isEmpty { return nil }
        return url
    }

    // MARK: - vCard

    static func vcardName(_ vcard: String) -> String? {
        for line in vcard.components(separatedBy: .newlines) {
            let upper = line.uppercased()
            if upper.hasPrefix("FN:") || upper.hasPrefix("FN;") {
                guard let colon = line.firstIndex(of: ":") else { continue }
                let name = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                return name.isEmpty ? nil : name
            }
        }
        return nil
    }
}

extension String {
    func truncated(to length: Int) -> String {
        count > length ? prefix(length - 1) + "…" : self
    }
}
