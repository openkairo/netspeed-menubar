// NetSpeed – zeigt Up-/Download der WLAN-Verbindung in der Menüleiste.
import Cocoa
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    var timer: Timer?
    var iface = "en0"
    var last: (rx: UInt64, tx: UInt64, t: TimeInterval)?
    // 32-Bit-Zähler der Schnittstelle laufen bei 4 GB über – hier hochgezählt.
    var raw: (rx: UInt32, tx: UInt32)?
    var total: (rx: UInt64, tx: UInt64) = (0, 0)
    let ifaceItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    let loginItem = NSMenuItem(title: "Bei Anmeldung starten", action: #selector(toggleLogin), keyEquivalent: "")
    let layoutItem = NSMenuItem(title: "Zweizeilig anzeigen", action: #selector(toggleLayout), keyEquivalent: "")
    let menu = NSMenu()
    var shown: (down: Double?, up: Double?) = (0, 0)
    var twoLines: Bool {
        get { UserDefaults.standard.bool(forKey: "zweizeilig") }
        set { UserDefaults.standard.set(newValue, forKey: "zweizeilig") }
    }

    // Rechtsklick: zwischen ein- und zweizeilig umschalten. Linksklick: Menü.
    @objc func clicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            toggleLayout()
        } else {
            item.popUpMenu(menu)   // veraltet, setzt das Menü aber als einziges sauber unter den Eintrag
        }
    }

    @objc func toggleLayout() {
        twoLines.toggle()
        layoutItem.state = twoLines ? .on : .off
        render(down: shown.down, up: shown.up)
    }

    @objc func toggleLogin() {
        let svc = SMAppService.mainApp
        do {
            if svc.status == .enabled { try svc.unregister() } else { try svc.register() }
        } catch {
            let a = NSAlert()
            a.messageText = "Autostart ließ sich nicht ändern"
            a.informativeText = "\(error.localizedDescription)\n\nTipp: NetSpeed erst in den Ordner „Programme“ ziehen."
            a.runModal()
        }
        loginItem.state = svc.status == .enabled ? .on : .off
    }

    func applicationDidFinishLaunching(_ n: Notification) {
        item.autosaveName = "NetSpeed"
        iface = wifiInterface() ?? "en0"
        ifaceItem.title = "Schnittstelle: \(iface) (WLAN)"
        menu.addItem(ifaceItem)
        menu.addItem(.separator())
        layoutItem.target = self
        layoutItem.state = twoLines ? .on : .off
        menu.addItem(layoutItem)
        loginItem.target = self
        // Erster Start: Autostart gleich einschalten (abschaltbar im Menü).
        if !UserDefaults.standard.bool(forKey: "autostartEingerichtet") {
            UserDefaults.standard.set(true, forKey: "autostartEingerichtet")
            try? SMAppService.mainApp.register()
        }
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(loginItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Beenden", action: #selector(NSApp.terminate(_:)), keyEquivalent: "q"))
        item.button?.target = self
        item.button?.action = #selector(clicked)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        item.button?.toolTip = "Rechtsklick: ein-/zweizeilig umschalten"
        render(down: 0, up: 0)
        tick()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func wifiInterface() -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        p.arguments = ["-listallhardwareports"]
        let pipe = Pipe(); p.standardOutput = pipe
        guard (try? p.run()) != nil else { return nil }
        p.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let lines = out.components(separatedBy: "\n")
        for (i, l) in lines.enumerated() where l.contains("Wi-Fi") || l.contains("AirPort") {
            if i + 1 < lines.count, lines[i + 1].hasPrefix("Device: ") {
                return String(lines[i + 1].dropFirst("Device: ".count))
            }
        }
        return nil
    }

    func readCounters() -> (rx: UInt32, tx: UInt32)? {
        var ptr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ptr) == 0, let first = ptr else { return nil }
        defer { freeifaddrs(ptr) }
        for p in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let a = p.pointee
            guard let addr = a.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK),
                  String(cString: a.ifa_name) == iface, let d = a.ifa_data else { continue }
            let data = d.assumingMemoryBound(to: if_data.self).pointee
            return (data.ifi_ibytes, data.ifi_obytes)
        }
        return nil
    }

    func tick() {
        guard let c = readCounters() else { render(down: nil, up: nil); return }
        if let r = raw {
            total.rx &+= UInt64(c.rx &- r.rx)   // Überlauf-sicher
            total.tx &+= UInt64(c.tx &- r.tx)
        }
        raw = c
        let now = ProcessInfo.processInfo.systemUptime
        if let l = last, now > l.t {
            let dt = now - l.t
            render(down: Double(total.rx - l.rx) / dt, up: Double(total.tx - l.tx) / dt)
        }
        last = (total.rx, total.tx, now)
    }

    func fmt(_ bps: Double?) -> String {
        guard let b = bps else { return "–" }
        let bits = b * 8
        if bits >= 1_000_000_000 { return String(format: "%.2f Gb/s", bits / 1e9) }
        if bits >= 100_000_000 { return String(format: "%.0f Mb/s", bits / 1e6) }
        if bits >= 1_000_000 { return String(format: "%.1f Mb/s", bits / 1e6) }
        return String(format: "%.0f kb/s", bits / 1e3)
    }

    func render(down: Double?, up: Double?) {
        // Selbst gezeichnet auf einer dezenten Kapsel; Pfeile farbig (↓ grün, ↑ blau – wie das
        // App-Symbol), Zahlen in Textfarbe. Einzeilig: [↓ 172 kb/s  ↑ 16 kb/s], der Download
        // rechts-, der Upload linksbündig – so bleibt der Abstand klein und die Leiste springt nicht.
        // Zweizeilig: Upload oben, Download unten, kleiner und rechtsbündig.
        shown = (down, up)
        let two = twoLines
        let font = NSFont.monospacedDigitSystemFont(ofSize: two ? 10.5 : 13, weight: two ? .bold : .semibold)
        let arrowFont = NSFont.systemFont(ofSize: two ? 10 : 12, weight: .heavy)
        func size(_ t: String, _ f: NSFont) -> CGFloat { ceil((t as NSString).size(withAttributes: [.font: f]).width) }
        let arrowW = size("↓", arrowFont) + (two ? 2 : 3)
        let valW = size("888 Mb/s", font)
        let gap: CGFloat = 9, pad: CGFloat = two ? 6 : 7
        let h = NSStatusBar.system.thickness
        let pillH = h - (two ? 1 : 4)
        let w = two ? pad + arrowW + valW + pad : pad + 2 * (arrowW + valW) + gap + pad
        let dText = fmt(down), uText = fmt(up)
        let button = item.button
        let img = NSImage(size: NSSize(width: w, height: h), flipped: true) { _ in
            let dark = (button?.effectiveAppearance ?? NSApp.effectiveAppearance)
                .bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            // Kapsel: hebt die Werte vom Hintergrundbild ab
            let r = two ? 6 : pillH / 2
            let pill = NSBezierPath(roundedRect: NSRect(x: 0, y: (h - pillH) / 2, width: w, height: pillH),
                                    xRadius: r, yRadius: r)
            (dark ? NSColor(white: 0, alpha: 0.28) : NSColor(white: 1, alpha: 0.45)).setFill()
            pill.fill()
            let text = dark ? NSColor.white : NSColor(white: 0.08, alpha: 1)
            let green = dark ? NSColor(srgbRed: 0.35, green: 0.92, blue: 0.52, alpha: 1)
                             : NSColor(srgbRed: 0.05, green: 0.60, blue: 0.25, alpha: 1)
            let blue  = dark ? NSColor(srgbRed: 0.45, green: 0.74, blue: 1.00, alpha: 1)
                             : NSColor(srgbRed: 0.05, green: 0.42, blue: 0.90, alpha: 1)
            // cy = senkrechte Mitte der Zeile
            func draw(_ t: String, _ f: NSFont, _ c: NSColor, x: CGFloat, cy: CGFloat) {
                let a: [NSAttributedString.Key: Any] = [.font: f, .foregroundColor: c]
                let sz = (t as NSString).size(withAttributes: a)
                (t as NSString).draw(at: NSPoint(x: x, y: cy - sz.height / 2), withAttributes: a)
            }
            if two {
                let right = w - pad
                for (arrow, val, col, cy) in [("↑", uText, blue, h * 0.27), ("↓", dText, green, h * 0.73)] {
                    let vW = size(val, font)
                    draw(arrow, arrowFont, col, x: right - vW - arrowW, cy: cy)
                    draw(val, font, text, x: right - vW, cy: cy)
                }
            } else {
                let mid = pad + arrowW + valW
                let dW = size(dText, font)
                draw("↓", arrowFont, green, x: mid - dW - arrowW, cy: h / 2)
                draw(dText, font, text, x: mid - dW, cy: h / 2)
                let ux = mid + gap
                draw("↑", arrowFont, blue, x: ux, cy: h / 2)
                draw(uText, font, text, x: ux + arrowW, cy: h / 2)
            }
            return true
        }
        button?.title = ""
        button?.image = img
        button?.imagePosition = .imageOnly
        item.length = w + 4
    }
}

// Läuft schon eine NetSpeed-Instanz? Dann nicht doppelt starten.
let me = ProcessInfo.processInfo.processIdentifier
if NSRunningApplication.runningApplications(withBundleIdentifier: "de.openkairo.netspeed")
    .contains(where: { $0.processIdentifier != me }) { exit(0) }

// Erster Start: Platz direkt links neben Kontrollzentrum/Uhr statt ganz links (dort verschwindet
// der Eintrag auf Notch-Macs). Danach gilt, wohin man ihn per ⌘-Ziehen schiebt.
let posKey = "NSStatusItem Preferred Position NetSpeed"
if UserDefaults.standard.object(forKey: posKey) == nil {
    UserDefaults.standard.set(181.0, forKey: posKey)
    UserDefaults.standard.set(true, forKey: "NSStatusItem Visible NetSpeed")
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
