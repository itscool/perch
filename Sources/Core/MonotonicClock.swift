import Foundation

/// Seconds on a clock that keeps counting through sleep and cannot be moved
/// by editing the wall clock. Deadlines, leases and battery countdowns use it.
enum MonotonicClock {
    private static let scale: Double = { var timebase = mach_timebase_info_data_t(); mach_timebase_info(&timebase); return Double(timebase.numer) / Double(timebase.denom) / 1_000_000_000 }()
    static var now: Double { Double(mach_continuous_time()) * scale }
}
/// The lid helper's original name for the same clock; its headless policy
/// suite compiles against it.
typealias LidGuardClock = MonotonicClock
