import Foundation
import Testing
@testable import QRCore

@Suite struct WifiParsingTests {
    @Test func wpaNetwork() {
        let payload = QRPayload.parse("WIFI:T:WPA;S:CasaMia;P:segreta123;;")
        #expect(payload == .wifi(WifiCredentials(ssid: "CasaMia", password: "segreta123", security: .wpa, hidden: false)))
    }

    @Test func fieldsInAnyOrderAndHidden() {
        let payload = QRPayload.parse("WIFI:S:Ufficio;H:true;P:pwd;T:WPA2;;")
        #expect(payload == .wifi(WifiCredentials(ssid: "Ufficio", password: "pwd", security: .wpa, hidden: true)))
    }

    @Test func escapedCharacters() {
        let payload = QRPayload.parse(#"WIFI:T:WPA;S:My\;Net\,x;P:pa\:ss\\;;"#)
        #expect(payload == .wifi(WifiCredentials(ssid: "My;Net,x", password: #"pa:ss\"#, security: .wpa, hidden: false)))
    }

    @Test func openNetworkIgnoresPassword() {
        let payload = QRPayload.parse("WIFI:T:nopass;S:Guest;P:;;")
        #expect(payload == .wifi(WifiCredentials(ssid: "Guest", password: nil, security: .open, hidden: false)))
    }

    @Test func missingTypeMeansOpen() {
        let payload = QRPayload.parse("WIFI:S:Bar;;")
        #expect(payload == .wifi(WifiCredentials(ssid: "Bar", password: nil, security: .open, hidden: false)))
    }

    @Test func wepAndQuotedSSID() {
        let payload = QRPayload.parse(#"WIFI:T:WEP;S:"0123456789";P:abcde;;"#)
        #expect(payload == .wifi(WifiCredentials(ssid: "0123456789", password: "abcde", security: .wep, hidden: false)))
    }

    @Test func lowercasePrefix() {
        guard case .wifi(let wifi) = QRPayload.parse("wifi:T:WPA;S:x;P:y;;") else {
            Issue.record("expected wifi")
            return
        }
        #expect(wifi.ssid == "x")
    }

    @Test func missingSSIDFallsBackToText() {
        #expect(QRPayload.parse("WIFI:T:WPA;P:x;;") == .text("WIFI:T:WPA;P:x;;"))
    }
}

@Suite struct OtherPayloadTests {
    @Test func httpsURL() {
        #expect(QRPayload.parse("https://sibill.com/path?q=1") == .url(URL(string: "https://sibill.com/path?q=1")!))
    }

    @Test func wwwGetsHttps() {
        #expect(QRPayload.parse("www.example.com") == .url(URL(string: "https://www.example.com")!))
    }

    @Test func mailtoAndTel() {
        #expect(QRPayload.parse("mailto:a@b.it") == .url(URL(string: "mailto:a@b.it")!))
        #expect(QRPayload.parse("tel:+390212345") == .url(URL(string: "tel:+390212345")!))
    }

    @Test func plainTextIsNotURL() {
        #expect(QRPayload.parse("hello world") == .text("hello world"))
        #expect(QRPayload.parse("ftp://x.y") == .text("ftp://x.y"))
        #expect(QRPayload.parse("https://") == .text("https://"))
    }

    @Test func vcard() {
        let vcard = "BEGIN:VCARD\nVERSION:3.0\nFN:Mario Rossi\nTEL:123\nEND:VCARD"
        let payload = QRPayload.parse(vcard)
        #expect(payload == .contact(vcard))
        #expect(payload.summary == "Contact: Mario Rossi")
    }

    @Test func summaries() {
        #expect(QRPayload.parse("WIFI:S:Casa;;").summary == "Wi-Fi: Casa")
        #expect(QRPayload.parse(String(repeating: "a", count: 80)).summary.count == 50)
    }
}
