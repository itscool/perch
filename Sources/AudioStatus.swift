import Foundation
import CoreAudio

// Read the current default output on every query, so changing output devices or
// muting elsewhere is reflected without caching a preference as the truth.
enum AudioStatus {
    static func muted() throws -> Bool {
        if let value = nativeMuted() { return value }
        // Preserve support for outputs exposing mute through scripting only.
        return try script("output muted of (get volume settings)").booleanValue
    }
    static func nativeMuted() -> Bool? {
        var device = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                mScope: kAudioObjectPropertyScopeGlobal,
                                                mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr,
              device != kAudioObjectUnknown else { return nil }
        address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute,
                                             mScope: kAudioDevicePropertyScopeOutput,
                                             mElement: kAudioObjectPropertyElementMain)
        var muted: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        if AudioObjectHasProperty(device, &address),
           AudioObjectGetPropertyData(device, &address, 0, nil, &size, &muted) == noErr {
            return muted != 0
        }
        return nil
    }
}
