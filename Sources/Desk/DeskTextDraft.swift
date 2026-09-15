import Foundation

/// Keeps an unfinished edit separate from both the saved value and incoming peer edits.
struct DeskTextDraft {
    var text: String
    var baseline: String
    var conflict = false
    var dirty: Bool { text != baseline }
    init(_ value: String) { text = value; baseline = value }
    mutating func receive(_ value: String) {
        guard value != baseline else { return }
        if !dirty || text == value { text = value; baseline = value; conflict = false }
        else { baseline = value; conflict = true }
    }
    mutating func accept(_ value: String) { text = value; baseline = value; conflict = false }
}

