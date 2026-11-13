import Foundation

/// The desk worked out from what each Mac sees: which Mac each screen shows,
/// and which preset that is. Scott's own desk is the fixture: a MacBook and a
/// Studio sharing an UltraFine and an HDR 4K, with a PC on a third input.
func runDeskObservedDeskTests() throws {
    func check(_ value: Bool, _ message: String) throws { if !value { throw AppError(message: message) } }
    let macBook = UUID(), studio = UUID(), pc = UUID()
    let perch: Set<UUID> = [macBook, studio], both: Set<UUID> = [macBook, studio]

    // What one screen shows.
    try check(DeskObservedDesk.state(seenBy: [macBook], cabled: both, reporting: both) == .showing(macBook),
              "A screen only the MacBook sees was not counted as showing the MacBook")
    try check(DeskObservedDesk.state(seenBy: [], cabled: both, reporting: both) == .elsewhere,
              "A screen neither Mac sees, with both reporting, was not counted as on another source")
    try check(DeskObservedDesk.state(seenBy: [], cabled: both, reporting: [macBook]) == .unknown,
              "A screen was put on another source before every Mac cabled to it had reported")
    try check(DeskObservedDesk.state(seenBy: both, cabled: both, reporting: both) == .unknown,
              "Two Macs seeing one screen was taken as proof of either")
    try check(DeskObservedDesk.state(seenBy: [], cabled: [], reporting: both) == .unknown,
              "A screen cabled only to PCs was settled without any evidence")

    // Whether a preset's choice agrees. The screens decide when they can.
    try check(DeskObservedDesk.agrees(.showing(macBook), computer: macBook, perch: perch, input: 17, fallback: 15) &&
              !DeskObservedDesk.agrees(.showing(macBook), computer: studio, perch: perch, input: 15, fallback: 15) &&
              !DeskObservedDesk.agrees(.showing(macBook), computer: pc, perch: perch, input: 18, fallback: nil),
              "A screen a Mac is seen on agreed with a preset that puts something else there, or the last command outvoted the screens")
    try check(DeskObservedDesk.agrees(.elsewhere, computer: pc, perch: perch, input: 18, fallback: nil) &&
              DeskObservedDesk.agrees(.elsewhere, computer: nil, perch: perch, input: 18, fallback: nil) &&
              !DeskObservedDesk.agrees(.elsewhere, computer: studio, perch: perch, input: 15, fallback: 15),
              "A screen no Mac sees did not agree with the PC, or agreed with a Mac")
    try check(DeskObservedDesk.agrees(.unknown, computer: studio, perch: perch, input: 15, fallback: 15) &&
              !DeskObservedDesk.agrees(.unknown, computer: studio, perch: perch, input: 15, fallback: nil) &&
              !DeskObservedDesk.agrees(.unknown, computer: studio, perch: perch, input: 15, fallback: 17),
              "With the screens unable to say, the monitor's report or last command was not what decided")

    // The whole desk: each preset against what the two Macs see.
    struct Choice { let computer: UUID; let input: UInt16 }
    let presets: [(String, [Choice])] = [
        ("Work", [.init(computer: macBook, input: 17), .init(computer: studio, input: 15)]),
        ("PC", [.init(computer: pc, input: 18), .init(computer: studio, input: 15)]),
        ("Swapped", [.init(computer: studio, input: 16), .init(computer: macBook, input: 19)]),
    ]
    func active(_ seen: [Set<UUID>]) -> [String] {
        let screens = seen.map { DeskObservedDesk.state(seenBy: $0, cabled: both, reporting: both) }
        return presets.filter { _, choices in
            zip(screens, choices).allSatisfy { DeskObservedDesk.agrees($0, computer: $1.computer, perch: perch, input: $1.input, fallback: nil) }
        }.map(\.0)
    }
    try check(active([[macBook], [studio]]) == ["Work"], "The MacBook on the UltraFine and the Studio on the HDR 4K did not read as Work: \(active([[macBook], [studio]]))")
    try check(active([[], [studio]]) == ["PC"], "The UltraFine on the PC did not read as the PC preset: \(active([[], [studio]]))")
    try check(active([[studio], [macBook]]) == ["Swapped"], "Swapped screens did not read as Swapped: \(active([[studio], [macBook]]))")
    try check(active([[macBook, studio], [studio]]).isEmpty, "A screen both Macs see picked a preset with nothing to go on")

    let line = DeskObservedDesk.summary([("UltraFine", .showing(macBook)), ("HDR 4K", .elsewhere)],
                                        name: { $0 == macBook ? "MacBook" : "Studio" }, preset: "PC")
    try check(line == "UltraFine shows MacBook (only MacBook sees it); HDR 4K shows another source (no Mac sees it) → preset PC",
              "The desk log line changed: \(line)")

    // A version is answered only when it is news, or the two Macs bounce it
    // back and forth forever and fill the link.
    try check(KVMInputSession.answersVersion(known: nil, heard: 2) && KVMInputSession.answersVersion(known: 1, heard: 2) &&
              !KVMInputSession.answersVersion(known: 2, heard: 2), "A sharing version already known was answered again, which bounces forever")

    print("PASS: the desk from what the Macs see: one Mac seeing a screen is showing it, none seeing it means another source once all have reported, two seeing it proves nothing; the screens outvote the last command; Work, PC and Swapped read correctly; a known sharing version is never answered again")
}
