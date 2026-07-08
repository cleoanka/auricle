import Foundation
import CoreAudio
import AudioToolbox
import Accelerate

// ---------------------------------------------------------------------------
// STEP 2: compile-time proof for Core Audio process-tap + aggregate + vDSP EQ
// Target: arm64-apple-macos14.4
// ---------------------------------------------------------------------------

func buildTapDescriptions() {
    let pids: [AudioObjectID] = [1234, 5678]

    // (a) per-process stereo mixdown tap
    // NOTE: the Swift-refined initializer takes [AudioObjectID], NOT [NSNumber].
    let perProcess = CATapDescription(stereoMixdownOfProcesses: pids)
    perProcess.name = "Auricle Process Tap"
    perProcess.muteBehavior = .mutedWhenTapped
    perProcess.isPrivate = true
    perProcess.isExclusive = false
    let _: UUID = perProcess.uuid

    // (b) system-wide (global) tap excluding our own process
    let global = CATapDescription(stereoGlobalTapButExcludeProcesses: pids)
    global.name = "Auricle Global Tap"
    global.muteBehavior = .mutedWhenTapped
    global.isPrivate = true
    let _: UUID = global.uuid

    // create / destroy tap
    var tapID = AudioObjectID(kAudioObjectUnknown)
    var status: OSStatus = AudioHardwareCreateProcessTap(perProcess, &tapID)
    status = AudioHardwareDestroyProcessTap(tapID)
    _ = status
}

func readTapFormat(_ tapID: AudioObjectID) -> AudioStreamBasicDescription {
    var addr = AudioObjectPropertyAddress(
        mSelector: kAudioTapPropertyFormat,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    var asbd = AudioStreamBasicDescription()
    var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
    let st = AudioObjectGetPropertyData(tapID, &addr, 0, nil, &size, &asbd)
    _ = st
    // also referencing UID + Description selectors
    _ = kAudioTapPropertyUID
    _ = kAudioTapPropertyDescription
    return asbd
}

func buildAggregate(tapUUID: String, outputDeviceUID: String) {
    let subDevice: [String: Any] = [
        kAudioSubDeviceUIDKey: outputDeviceUID,
        kAudioSubDeviceDriftCompensationKey: 0
    ]
    let subTap: [String: Any] = [
        kAudioSubTapUIDKey: tapUUID,
        kAudioSubTapDriftCompensationKey: 1
    ]
    let description: [String: Any] = [
        kAudioAggregateDeviceNameKey: "Auricle Aggregate",
        kAudioAggregateDeviceUIDKey: "com.auricle.aggregate.\(UUID().uuidString)",
        kAudioAggregateDeviceIsPrivateKey: true,
        kAudioAggregateDeviceIsStackedKey: false,
        kAudioAggregateDeviceMainSubDeviceKey: outputDeviceUID,
        kAudioAggregateDeviceTapAutoStartKey: true,
        kAudioAggregateDeviceSubDeviceListKey: [subDevice],
        kAudioAggregateDeviceTapListKey: [subTap]
    ]

    var aggID = AudioObjectID(kAudioObjectUnknown)
    var st = AudioHardwareCreateAggregateDevice(description as CFDictionary, &aggID)

    // settable post-creation tap list property (CFArray of tap UUID CFStrings)
    var tapListAddr = AudioObjectPropertyAddress(
        mSelector: kAudioAggregateDevicePropertyTapList,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    var tapList: CFArray = [tapUUID] as CFArray
    let tlSize = UInt32(MemoryLayout<CFArray>.size)
    st = AudioObjectSetPropertyData(aggID, &tapListAddr, 0, nil, tlSize, &tapList)

    st = AudioHardwareDestroyAggregateDevice(aggID)
    _ = st
}

func installIOProc(_ aggID: AudioObjectID) {
    // AudioDeviceIOBlock: exact param types
    let ioBlock: AudioDeviceIOBlock = {
        (inNow: UnsafePointer<AudioTimeStamp>,
         inInputData: UnsafePointer<AudioBufferList>,
         inInputTime: UnsafePointer<AudioTimeStamp>,
         outOutputData: UnsafeMutablePointer<AudioBufferList>,
         inOutputTime: UnsafePointer<AudioTimeStamp>) in
        _ = inNow
        _ = inInputData
        _ = inInputTime
        _ = outOutputData
        _ = inOutputTime
    }

    var procID: AudioDeviceIOProcID? = nil
    var st = AudioDeviceCreateIOProcIDWithBlock(&procID, aggID, nil, ioBlock)
    st = AudioDeviceStart(aggID, procID)
    st = AudioDeviceStop(aggID, procID)
    if let procID = procID {
        st = AudioDeviceDestroyIOProcID(aggID, procID)
    }
    _ = st
}

func processObjectProbeTypes() {
    _ = kAudioHardwarePropertyProcessObjectList
    _ = kAudioHardwarePropertyTranslatePIDToProcessObject
    _ = kAudioProcessPropertyPID
    _ = kAudioProcessPropertyBundleID
    _ = kAudioProcessPropertyIsRunning
    _ = kAudioProcessPropertyIsRunningInput
    _ = kAudioProcessPropertyIsRunningOutput
}

func biquadEQ() {
    let sections = 10   // 10-band EQ
    let channels = 2    // stereo
    // biquadm coefficient layout: 5 coeffs (b0,b1,b2,a1,a2) per section per channel
    var coeffs = [Double](repeating: 0, count: 5 * sections * channels)
    for i in stride(from: 0, to: coeffs.count, by: 5) {
        coeffs[i] = 1.0 // b0 = 1 (identity passthrough)
    }
    guard let setup = vDSP_biquadm_CreateSetup(&coeffs,
                                               vDSP_Length(sections),
                                               vDSP_Length(channels)) else { return }

    var targets = coeffs
    vDSP_biquadm_SetTargetsDouble(setup,
                                  &targets,
                                  0.995,   // interp_rate
                                  0.0001,  // interp_threshold
                                  0,       // start_sec
                                  0,       // start_chn
                                  vDSP_Length(sections),
                                  vDSP_Length(channels))

    // apply filter (float, multi-channel)
    let n = 512
    var l = [Float](repeating: 0, count: n)
    var r = [Float](repeating: 0, count: n)
    var outL = [Float](repeating: 0, count: n)
    var outR = [Float](repeating: 0, count: n)
    l.withUnsafeMutableBufferPointer { lp in
    r.withUnsafeMutableBufferPointer { rp in
    outL.withUnsafeMutableBufferPointer { olp in
    outR.withUnsafeMutableBufferPointer { orp in
        var xs: [UnsafePointer<Float>] = [UnsafePointer(lp.baseAddress!), UnsafePointer(rp.baseAddress!)]
        var ys: [UnsafeMutablePointer<Float>] = [olp.baseAddress!, orp.baseAddress!]
        xs.withUnsafeMutableBufferPointer { xptr in
        ys.withUnsafeMutableBufferPointer { yptr in
            vDSP_biquadm(setup,
                         xptr.baseAddress!, vDSP_Stride(1),
                         yptr.baseAddress!, vDSP_Stride(1),
                         vDSP_Length(n))
        }}
    }}}}

    // vDSP_vrampmul2: stereo interleaved gain ramp
    var start: Float = 0.5
    var step: Float = 0.001
    vDSP_vrampmul2(&l, &r, vDSP_Stride(1),
                   &start, &step,
                   &outL, &outR, vDSP_Stride(1),
                   vDSP_Length(n))

    vDSP_biquadm_DestroySetup(setup)
}

// keep the compiler from stripping everything
func main() {
    buildTapDescriptions()
    _ = readTapFormat(AudioObjectID(kAudioObjectUnknown))
    buildAggregate(tapUUID: UUID().uuidString, outputDeviceUID: "BuiltInSpeakerDevice")
    installIOProc(AudioObjectID(kAudioObjectUnknown))
    processObjectProbeTypes()
    biquadEQ()
}
