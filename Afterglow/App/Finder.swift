import Foundation

/// Finds each light's address on Wi-Fi: scan the /24 for Tuya's port 6668, then try each light's
/// key against each open address. A 3.4/3.5 handshake or a 3.3 status reply only succeeds with the
/// right key, so a match is certain. Addresses are probed in parallel, lights one at a time per
/// address (bulbs usually allow a single connection).
extension AppStore {
    func findOnWiFi(quiet: Bool = false) async {
        guard finding == nil else { return }
        guard LocalScan.wifiAddress() != nil else {
            if !quiet { error = "Connect to your home Wi-Fi first." }
            return
        }
        let candidates = lights.filter { $0.localKey?.isEmpty == false }
        guard !candidates.isEmpty else {
            if !quiet { error = "Tuya didn't send local keys for these lights. Sign in again and retry." }
            return
        }
        finding = "Scanning Wi-Fi…"
        defer { finding = nil }
        await LightControl.shared.dropAll()

        // Known addresses first: most lights keep theirs (DHCP reservations, long leases).
        var unmatched = candidates
        var results: [String: (String, Double)] = [:]
        for l in candidates {
            guard let host = l.host else { continue }
            if let v = await Self.probe(l, host: host, versions: l.version.map { [$0] } ?? [3.3, 3.4, 3.5]) {
                results[l.id] = (host, v)
                unmatched.removeAll { $0.id == l.id }
            }
        }

        if !unmatched.isEmpty {
            let hosts = await LocalScan.openHosts { done in
                Task { @MainActor in AppStore.shared.finding = "Scanning Wi-Fi… \(Int(Double(done) / 253 * 100))%" }
            }
            let taken = Set(results.values.map(\.0))
            let open = hosts.filter { !taken.contains($0) }
            finding = "Matching \(unmatched.count) light\(unmatched.count == 1 ? "" : "s") to \(open.count) device\(open.count == 1 ? "" : "s")…"
            let pool = MatchPool(unmatched)
            await withTaskGroup(of: Void.self) { group in
                for host in open {
                    group.addTask {
                        // Fast versions first; 3.3 with the wrong key is the slow case.
                        for versions in [[3.4, 3.5], [3.3]] {
                            for l in await pool.remaining() {
                                if let v = await Self.probe(l, host: host, versions: versions) {
                                    await pool.matched(l.id, host: host, version: v)
                                    return
                                }
                            }
                        }
                    }
                }
            }
            for (id, hit) in await pool.hits { results[id] = hit }
        }

        var list = LightStore.load()
        for i in list.indices {
            if let hit = results[list[i].id] {
                list[i].host = hit.0
                list[i].version = hit.1
            }
        }
        LightStore.save(list)
        lights = LightStore.load()
        let found = results.count, total = candidates.count
        if !quiet || found > 0 {
            show(found == total ? "Found all \(total) on Wi-Fi. Controls are local now."
                 : "Found \(found) of \(total) on Wi-Fi. The rest go through the cloud.")
        }
    }

    /// The protocol version that worked, or nil.
    nonisolated static func probe(_ l: Light, host: String, versions: [Double]) async -> Double? {
        guard let key = l.localKey else { return nil }
        guard let r = try? await LocalLink.detect(devId: l.id, host: host, localKey: key,
                                                            knownDPs: Array(l.codeMap().keys), timeout: 1.6, versions: versions,
                                                            onDPS: { _ in }, onClose: { _ in }) else { return nil }
        let v = r.0.version, dps = r.1
        await r.0.close()
        // 3.4+ proved the key in the handshake. For 3.3 only real data proves it.
        if v >= 3.4 || !dps.isEmpty { return v }
        return nil
    }
}

private actor MatchPool {
    private var left: [Light]
    private(set) var hits: [String: (String, Double)] = [:]
    init(_ l: [Light]) { left = l }
    func remaining() -> [Light] { left }
    func matched(_ id: String, host: String, version: Double) {
        left.removeAll { $0.id == id }
        hits[id] = (host, version)
    }
}
