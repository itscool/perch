/// Required instructions stay open. Readiness changes reset an optional review;
/// polling the same state preserves the user's disclosure choice.
struct SetupDisclosure {
    private(set) var ready = false
    private var observed = false
    private var reviewing = false
    var expanded: Bool { !ready || reviewing }
    var title: String { expanded ? "Hide permission instructions" : "Show permission instructions" }
    mutating func update(ready: Bool) {
        if !observed || self.ready != ready { reviewing = false }
        self.ready = ready; observed = true
    }
    mutating func toggle() { if ready { reviewing.toggle() } }
}
