enum SleepPreferences {
    static let lidPreferenceKey = "sleep.includeLid"
    /// Off by default. When on, Perch declares presence every 30 seconds so an
    /// idle screen saver or idle lock does not start (see IdleLockPreventer).
    static let preventIdleLockKey = "sleep.preventIdleLock"
}
