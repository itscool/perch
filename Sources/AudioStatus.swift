import Foundation
import CoreAudio
import AudioToolbox

// Read the current default output on every query, so changing output devices or
// muting elsewhere is reflected without caching a preference as the truth.
enum AudioStatus {
    static func heading(volume: Int?, muted: Bool?) -> String {
        let level = volume.map { "\($0)%" } ?? "Volume unavailable"
        return "Audio · " + level + (muted == true ? " · Muted" : "")
    }
    static func percentage(_ scalar: Float32) -> Int? {
        guard scalar.isFinite, (0...1).contains(scalar) else { return nil }
        return Int((scalar * 100).rounded())
    }
    /// Query the output's virtual main control, preserving channel balance.
    /// Called on existing open-menu refreshes only; no process or timer added.
    static func volume() -> Int? {
        var device = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(mSelector:kAudioHardwarePropertyDefaultOutputDevice,mScope:kAudioObjectPropertyScopeGlobal,mElement:kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),&address,0,nil,&size,&device) == noErr, device != kAudioObjectUnknown else { return nil }
        address = AudioObjectPropertyAddress(mSelector:kAudioHardwareServiceDeviceProperty_VirtualMainVolume,mScope:kAudioDevicePropertyScopeOutput,mElement:kAudioObjectPropertyElementMain)
        var scalar: Float32 = 0
        size = UInt32(MemoryLayout<Float32>.size)
        guard AudioHardwareServiceHasProperty(device,&address), AudioHardwareServiceGetPropertyData(device,&address,0,nil,&size,&scalar) == noErr else { return nil }
        return percentage(scalar)
    }
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
