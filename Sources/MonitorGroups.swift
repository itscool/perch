import AppKit
import Carbon

struct MonitorGroupMember: Codable, Equatable {
    var display: String
    var name: String
}
struct MonitorDestination: Codable, Equatable {
    var id = UUID().uuidString
    var name: String
    var inputs: [String: UInt16]
}
struct MonitorGroup: Codable, Equatable {
    var id = UUID().uuidString
    var name = "Desk displays"
    var members: [MonitorGroupMember] = []
    var destinations: [MonitorDestination] = []
    var shortcut = PanicShortcut(key: UInt32(kVK_F8), modifiers: UInt32(controlKey | optionKey), enabled: false)
    var valid: Bool {
        let ids = Set(members.map(\.display))
        func named(_ text: String) -> Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && text.utf8.count <= 120 && !text.unicodeScalars.contains { $0.value < 32 } }
        return UUID(uuidString: id) != nil && named(name) && (1...16).contains(members.count) && ids.count == members.count &&
            members.allSatisfy { UUID(uuidString: $0.display) != nil && named($0.name) } &&
            (1...8).contains(destinations.count) && Set(destinations.map(\.id)).count == destinations.count &&
            Set(destinations.map { $0.name.lowercased() }).count == destinations.count &&
            Set(destinations.map { destination in destination.inputs.keys.sorted().map { "\($0)=\(destination.inputs[$0]!)" }.joined(separator: ",") }).count == destinations.count &&
            destinations.allSatisfy { UUID(uuidString: $0.id) != nil && named($0.name) && Set($0.inputs.keys) == ids && $0.inputs.values.allSatisfy { $0 > 0 } } &&
            (!shortcut.enabled || (destinations.count >= 2 && shortcut.modifiers.nonzeroBitCount >= 2 && PanicShortcut.keys.contains { $0.1 == shortcut.key }))
    }
    func next(observed: [String: UInt16]) throws -> MonitorDestination {
        guard destinations.count >= 2, Set(observed.keys) == Set(members.map(\.display)),
              let index = destinations.firstIndex(where: { $0.inputs == observed }) else {
            throw AppError(message: "The displays are on different or unknown inputs. Choose a named destination in Switching groups; Perch will not guess or cycle each display separately.")
        }
        return destinations[(index + 1) % destinations.count]
    }
}
struct MonitorGroupSettings: Codable, Equatable {
    var groups: [MonitorGroup] = []
    var activeID: String?
    var valid: Bool { groups.count <= 16 && groups.allSatisfy(\.valid) && Set(groups.map(\.id)).count == groups.count && (activeID == nil || groups.contains { $0.id == activeID }) }
}
struct MonitorGroupRequest: Equatable {
    let member: MonitorGroupMember
    let plan: MonitorInputPlan?
    let input: UInt16
    let readable: Bool
    let unavailable: String?
}
struct MonitorGroupResult: Equatable {
    enum State: String { case confirmed = "Confirmed", unverified = "Unverified", failed = "Failed" }
    let display: String
    let name: String
    let input: UInt16
    let state: State
    let detail: String
    let checkedAt: Date
}

enum MonitorGroupEngine {
    static func read(_ request: MonitorGroupRequest, backend: MonitorCommandBackend) throws -> UInt16 {
        guard request.readable, request.unavailable == nil, let plan = request.plan else { throw AppError(message: request.unavailable ?? "Current input cannot be read reliably.") }
        let result = try JSONDecoder().decode(MonitorInspection.self, from: backend.run(["read", plan.display, plan.commandMode]))
        guard let input = result.current, input > 0 else { throw AppError(message: "Current input is unknown.") }
        return input
    }
    /// Destination is fixed for the entire operation, even if a member fails or
    /// video disappears after the first switch. Never substitute another display.
    static func execute(_ requests: [MonitorGroupRequest], backend: MonitorCommandBackend, pause: () -> Void = { Thread.sleep(forTimeInterval: 0.2) }, progress: (MonitorGroupResult) -> Void) -> [MonitorGroupResult] {
        requests.map { request in
            let result: MonitorGroupResult
            do {
                if let error = request.unavailable { throw AppError(message: error) }
                guard let plan = request.plan else { throw AppError(message: "The saved setup is missing. Configure this display before switching it.") }
                if (try? read(request, backend: backend)) == request.input {
                    result = .init(display: request.member.display, name: request.member.name, input: request.input, state: .confirmed, detail: "Already showing this destination; confirmed by a fresh monitor read.", checkedAt: Date())
                } else {
                    let data = try backend.run(["switch", plan.display, plan.commandMode, String(request.input)])
                    guard let reply = try JSONSerialization.jsonObject(with: data) as? [String: Any], reply["sent"] as? Bool == true else { throw AppError(message: "The monitor did not accept the input command.") }
                    pause()
                    let current = try? read(request, backend: backend)
                    result = .init(display: request.member.display, name: request.member.name, input: request.input, state: current == request.input ? .confirmed : .unverified,
                        detail: current == request.input ? "Monitor reports the requested input." : current.map { "Command sent, but the monitor reports input \($0). Check the display before retrying." } ?? "Command sent; the current input cannot be verified. Check the display before retrying.", checkedAt: Date())
                }
            } catch {
                result = .init(display: request.member.display, name: request.member.name, input: request.input, state: .failed, detail: error.localizedDescription, checkedAt: Date())
            }
            progress(result); return result
        }
    }
}

final class MonitorGroupController {
    static let preferenceKey = "monitor.groups.v1"
    private(set) var settings = MonitorGroupSettings()
    private(set) var loadError: String?
    private(set) var results: [MonitorGroupResult] = []
    private(set) var message = "Choose the displays that belong together and name their destinations."
    private(set) var busy = false
    var onChange: (() -> Void)?
    var onNeedsDestination: (() -> Void)?
    private(set) var cycleNeedsChoice = false
    private unowned let monitor: MonitorInputController
    private let defaults: UserDefaults
    private let hotKey = PanicHotKey(signature: 0x50475250)
    private var lastGroup: MonitorGroup?
    private var lastDestination: MonitorDestination?
    private var lastRequests: [MonitorGroupRequest] = []
    var resultGroupID: String? { lastGroup?.id }
    var active: MonitorGroup? { settings.groups.first { $0.id == settings.activeID } }
    var canCycle: Bool {
        guard !busy, !monitor.busy, !monitor.checkingDisplays, let group = active, group.destinations.count >= 2 else { return false }
        let plans = (try? monitor.savedPlans()) ?? [:]
        return group.destinations.allSatisfy { requests(group, destination: $0, savedPlans: plans).allSatisfy { $0.unavailable == nil } }
    }
    var shortcutActive: Bool { hotKey.active }
    var hasAttention: Bool { cycleNeedsChoice || loadError != nil || !results.isEmpty && results.contains { $0.state != .confirmed } || active?.shortcut.enabled == true && !shortcutActive }
    var canRetry: Bool { !busy && !monitor.busy && lastGroup != nil && results.contains { $0.state != .confirmed } }
    init(monitor: MonitorInputController, defaults: UserDefaults) {
        self.monitor = monitor; self.defaults = defaults
        if let object = defaults.object(forKey: Self.preferenceKey) {
            if let data = object as? Data, data.count <= 1_048_576, let value = try? JSONDecoder().decode(MonitorGroupSettings.self, from: data), value.valid { settings = value }
            else { loadError = "Saved switching groups could not be read. They have not been replaced."; message = loadError! }
        }
        hotKey.action = { [weak self] in self?.cycle() }
    }
    func start() {
        do { try hotKey.register(active?.shortcut ?? PanicShortcut(enabled: false)) }
        catch { message = error.localizedDescription }
    }
    func save(_ value: MonitorGroupSettings) throws {
        guard loadError == nil else { throw AppError(message: loadError!) }
        guard !busy && !monitor.busy else { throw AppError(message: "Wait for the current display operation to finish before changing groups.") }
        guard value.valid else { throw AppError(message: "Choose at least one display and map every selected display to each uniquely named destination.") }
        let shortcut = value.groups.first { $0.id == value.activeID }?.shortcut ?? PanicShortcut(enabled: false)
        let panic = SafetyConfiguration.load().shortcut
        guard !shortcut.enabled || !panic.enabled || shortcut.key != panic.key || shortcut.modifiers != panic.modifiers else { throw AppError(message: "Choose a different shortcut from Immediate Kill.") }
        guard !shortcut.enabled || !monitor.plan.shortcut.enabled || shortcut.key != monitor.plan.shortcut.key || shortcut.modifiers != monitor.plan.shortcut.modifiers else { throw AppError(message: "Choose a different shortcut from the individual monitor shortcut, or turn that shortcut off first.") }
        let data = try JSONEncoder().encode(value)
        guard data.count <= 1_048_576 else { throw AppError(message: "The saved groups are too large.") }
        do { try hotKey.register(shortcut) }
        catch { try? hotKey.register(active?.shortcut ?? PanicShortcut(enabled: false)); throw error }
        defaults.set(data, forKey: Self.preferenceKey); settings = value
        results = []; lastGroup = nil; lastDestination = nil; lastRequests = []
        cycleNeedsChoice = false
        message = "Switching groups saved. Saving does not switch any display."
        onChange?(); monitor.notifyGroupChanged()
    }
    func requests(_ group: MonitorGroup, destination: MonitorDestination, savedPlans: [String: MonitorInputPlan]? = nil) -> [MonitorGroupRequest] {
        let plans = savedPlans ?? (try? monitor.savedPlans()) ?? [:]
        return group.members.map { member in
            let plan = monitor.plan.display == member.display ? monitor.plan : plans[member.display]
            let display = monitor.displays.first { $0.id == member.display }
            let input = destination.inputs[member.display] ?? 0
            let unavailable: String?
            if plan == nil || plan?.valid != true { unavailable = "Saved display setup is missing or invalid. Review this display’s setup." }
            else if !(plan!.availableInputs ?? plan!.inputs).contains(where: { $0.code == input }) { unavailable = "The destination’s mapped input is no longer in this display’s saved setup." }
            else if plan?.controlConnection == nil && display?.ddcAvailable != true { unavailable = "Display disconnected or monitor control unavailable. It remains part of this group." }
            else { unavailable = nil }
            let profile = display.flatMap { display in MonitorProfiles.entries.first { $0.name == plan?.profileName && $0.vendor == display.vendor } ?? MonitorProfiles.match(display) }
            return .init(member: member, plan: plan, input: input, readable: plan?.controlConnection != nil || profile?.readbackUnavailable != true, unavailable: unavailable)
        }
    }
    func choose(_ group: MonitorGroup, destination: MonitorDestination, retry: Bool = false) {
        guard !busy && !monitor.busy else { return }
        guard settings.groups.contains(group), group.destinations.contains(destination) else { message = "This group changed. Choose a destination again."; onChange?(); return }
        var requests = self.requests(group, destination: destination)
        if retry {
            guard lastGroup == group, lastDestination == destination, requests.count == lastRequests.count,
                  zip(requests, lastRequests).allSatisfy({ $0.member == $1.member && $0.plan == $1.plan && $0.input == $1.input }) else { message = "Display setup changed. Review it and choose the destination again."; onChange?(); return }
            let incomplete = Set(results.filter { $0.state != .confirmed }.map(\.display))
            requests = requests.filter { incomplete.contains($0.member.display) }
        } else { results = []; lastGroup = group; lastDestination = destination; lastRequests = requests }
        busy = true; message = "Switching \(group.name) to \(destination.name)…"; onChange?()
        cycleNeedsChoice = false
        monitor.performGroup(requests, progress: { [weak self] result in self?.record(result) }) { [weak self] in
            guard let self else { return }
            self.busy = false
            let count = self.results.filter { $0.state == .confirmed }.count
            self.message = "\(group.name) → \(destination.name): \(count) of \(group.members.count) displays confirmed." + (count == group.members.count ? "" : " Review each result; retry only the unconfirmed displays.")
            self.onChange?(); self.monitor.notifyGroupChanged()
        }
    }
    private func record(_ result: MonitorGroupResult) { results.removeAll { $0.display == result.display }; results.append(result); onChange?() }
    func retry() { if let group = lastGroup, let destination = lastDestination { choose(group, destination: destination, retry: true) } }
    func checkInputs(_ group: MonitorGroup) {
        guard !busy && !monitor.busy, let first = group.destinations.first else { return }
        busy = true; message = "Reading the selected displays’ current inputs…"; onChange?()
        monitor.readGroup(requests(group, destination: first)) { [weak self] result in
            guard let self else { return }; self.busy = false
            do {
                let inputs = try result.get()
                if let destination = group.destinations.first(where: { $0.inputs == inputs }) { self.message = "\(group.name) reports \(destination.name), checked just now."; self.cycleNeedsChoice = false }
                else { self.message = "The selected displays report different destinations or unmapped inputs. Choose a destination to bring them together."; self.cycleNeedsChoice = true }
            } catch { self.message = "Current inputs could not all be confirmed. " + error.localizedDescription; self.cycleNeedsChoice = true }
            self.onChange?(); self.monitor.notifyGroupChanged()
        }
    }
    func cycle() {
        guard let group = active, !busy && !monitor.busy && !monitor.checkingDisplays else { return }
        guard let first = group.destinations.first else { return }
        busy = true; message = "Checking every display before choosing the next destination…"; onChange?()
        monitor.readGroup(requests(group, destination: first)) { [weak self] result in
            guard let self else { return }; self.busy = false
            do { self.choose(group, destination: try group.next(observed: result.get())) }
            catch { self.cycleNeedsChoice = true; self.message = error.localizedDescription; self.onChange?(); self.monitor.notifyGroupChanged(); self.onNeedsDestination?() }
        }
    }
}
