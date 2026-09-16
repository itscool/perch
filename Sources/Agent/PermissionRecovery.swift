import Foundation

/// Removes the permission entries an earlier, differently signed Perch left
/// behind. It names only Perch's own bundle id and only the services that fail
/// now, so a working Local Network, Screen Recording or Full Disk Access grant
/// is never touched. No administrator rights are involved.
enum PermissionRecovery {
    static let tccutil = "/usr/bin/tccutil"
    typealias Run = ([String]) throws -> Subprocess.Output

    /// One service, one bundle id. Never "All" and never a global reset.
    static func arguments(_ service: PermissionService, bundleID: String = PanicPlan.perchID) -> [String] {
        ["reset", service.rawValue, bundleID]
    }

    struct Outcome: Equatable {
        var cleared: [PermissionService] = []
        var failure: String?
    }

    /// Decide and act once. A clear that fails leaves the stored publisher
    /// alone, so the next launch tries again instead of reporting success.
    @discardableResult
    static func perform(current: String?, failing: [PermissionService], defaults: UserDefaults,
                        now: Date = Date(), run: Run) -> Outcome {
        guard let current else { return .init() }
        let stored = defaults.codable(PublisherRecord.self, forKey: PublisherChange.key)
        func remember(cleared: String?, services: [PermissionService]) {
            let record = PublisherRecord(publisher: current, seen: now,
                                         cleared: cleared ?? (stored?.cleared == current ? current : nil),
                                         clearedServices: services.isEmpty ? (stored?.cleared == current ? stored?.clearedServices ?? [] : []) : services)
            try? defaults.setCodable(record, forKey: PublisherChange.key)
        }
        switch PublisherChange.decide(current: current, stored: stored, failing: failing) {
        case .record:
            remember(cleared: nil, services: [])
            return .init()
        case .clear(let services):
            var cleared: [PermissionService] = []
            for service in services {
                do {
                    let output = try run(arguments(service))
                    guard output.succeeded else {
                        return .init(cleared: cleared, failure: "macOS did not remove Perch’s old \(service.title) entry (exit \(output.status)). Review Privacy & Security, then remove the Perch entry and add it again.")
                    }
                    cleared.append(service)
                } catch {
                    return .init(cleared: cleared, failure: "macOS did not remove Perch’s old \(service.title) entry. \(error.localizedDescription)")
                }
            }
            remember(cleared: current, services: cleared)
            return .init(cleared: cleared)
        }
    }

    /// The permissions this copy cannot use right now.
    static func failing(accessibility: Bool = AccessCheck.accessibility,
                        inputMonitoring: Bool = AccessCheck.inputMonitoring) -> [PermissionService] {
        (accessibility ? [] : [PermissionService.accessibility]) + (inputMonitoring ? [] : [.inputMonitoring])
    }

    /// Run once per launch off the main thread; `refresh` runs on the main thread.
    static func startAtLaunch(refresh: @escaping () -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let outcome = perform(current: CodeIdentity.designatedRequirement, failing: failing(),
                                  defaults: .standard) { try Subprocess.run(tccutil, $0, timeout: 20) }
            DispatchQueue.main.async {
                if !outcome.cleared.isEmpty || outcome.failure != nil { refresh() }
            }
        }
    }

    /// What Setup should explain while removed permissions are still missing.
    static func restoreNeeded(defaults: UserDefaults = .standard) -> [PermissionService] {
        PublisherChange.restoreNeeded(current: CodeIdentity.designatedRequirement,
                                      stored: defaults.codable(PublisherRecord.self, forKey: PublisherChange.key),
                                      failing: failing())
    }
}
