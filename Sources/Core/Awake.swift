import Foundation
import IOKit.pwr_mgt

/// Holds a "prevent idle system sleep" assertion while enabled. Used by the
/// menu app's Keep awake, the lid helper and the guardian.
final class Awake {
    private var ids: [IOPMAssertionID] = []
    var enabled: Bool { !ids.isEmpty }
    func set(_ enabled: Bool) throws {
        if !enabled { ids.forEach { IOPMAssertionRelease($0) }; ids.removeAll(); return }
        guard ids.isEmpty else { return }
        for type in [kIOPMAssertionTypePreventUserIdleSystemSleep] {
            var id: IOPMAssertionID = 0
            let result = IOPMAssertionCreateWithName(type as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), "Perch: keep Mac awake" as CFString, &id)
            guard result == kIOReturnSuccess else {
                try? set(false)
                throw PerchError("Could not keep the Mac awake (\(result)).")
            }
            ids.append(id)
        }
    }
    deinit { ids.forEach { IOPMAssertionRelease($0) } }
}
