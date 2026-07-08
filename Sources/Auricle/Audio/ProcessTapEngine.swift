import Accelerate
import CoreAudio
import Foundation
import os

// Per-engine chain: CATapDescription -> process tap -> private aggregate (target device +
// tap with drift compensation) -> IOProc on the HAL RT thread that replays the tapped audio
// processed (ramped gain, GraphicEQ, hard clip) into the aggregate's output buffers.
//
// systemWide feedback avoidance: the global tap always excludes Auricle's own process object;
// when that object cannot be resolved yet, the aggregate + IOProc start first (silence) and
// the tap is attached post-hoc via kAudioAggregateDevicePropertyTapList. The global tap also
// excludes every process currently captured by a per-app engine (fed in via updateSource),
// because .mutedWhenTapped only silences the device mix — other taps still hear the process,
// and without the exclusion those apps would be replayed twice.

final class ProcessTapEngine {
    enum Source {
        /// Tap a set of process objects belonging to one app.
        case app(objectIDs: [AudioObjectID])
        /// Tap everything except Auricle itself (master chain).
        case systemWide
    }

    let source: Source

    /// Called on the main queue when the engine fails. Messages starting with "permission:"
    /// indicate missing System Audio Recording consent.
    var onFailure: ((String) -> Void)?

    private(set) var isRunning: Bool = false

    private let controlQueue: DispatchQueue
    private let levels: UnsafeMutablePointer<Float>
    private var tappedObjectIDs: [AudioObjectID]
    private var lastConfig: AppAudioConfig?
    private var lastRequestedUID: String?
    private var chain: Chain?
    /// Bumped at the start of every buildChain so stale failure deliveries can be dropped.
    private let buildGeneration = OSAllocatedUnfairLock(initialState: 0)

    init(source: Source) {
        self.source = source
        controlQueue = DispatchQueue(label: "io.github.cleoanka.Auricle.tap-engine")
        switch source {
        case .app(let objectIDs):
            tappedObjectIDs = objectIDs
        case .systemWide:
            tappedObjectIDs = []
        }
        levels = .allocate(capacity: 2)
        levels.initialize(repeating: 0, count: 2)
    }

    deinit {
        // deinit can run on controlQueue itself (a queued block holding the last strong
        // reference), so a sync here would self-deadlock. Move the chain out and destroy
        // it without capturing self; levels must outlive any in-flight render.
        let chain = chain
        let levels = levels
        controlQueue.async {
            if let chain { ProcessTapEngine.destroy(chain: chain) }
            levels.deallocate()
        }
    }

    /// Start / reconfigure / retarget as needed. Diffs internally:
    /// cheap path for gain/EQ/mute changes, full rebuild for device changes.
    /// `targetDeviceUID` nil = follow the current system default output device.
    func apply(config: AppAudioConfig, targetDeviceUID: String?) {
        controlQueue.async { [weak self] in
            guard let self else { return }
            self.lastConfig = config
            self.lastRequestedUID = targetDeviceUID
            guard let chain = self.chain else {
                self.buildChain()
                return
            }
            if let target = self.resolveTarget(requestedUID: self.explicitRequestedUID),
               target.uid != chain.targetUID {
                self.buildChain()
            } else {
                self.pushParameters(config, into: chain)
            }
        }
    }

    /// App engines: update the set of tapped process objects (app gained/lost helpers).
    /// Master engine: update the set of process objects excluded from the global tap
    /// (apps owned by per-app engines, so their audio is not captured twice).
    func updateSource(objectIDs: [AudioObjectID]) {
        controlQueue.async { [weak self] in
            guard let self else { return }
            guard objectIDs != self.tappedObjectIDs else { return }
            self.tappedObjectIDs = objectIDs
            guard let chain = self.chain else { return }
            // Swap the process list on the live tap; keep the UUID so the aggregate's
            // tap-list reference stays valid. Any failure falls back to a full rebuild.
            let description: CATapDescription
            switch self.source {
            case .app:
                description = self.makeAppTapDescription(objectIDs: objectIDs)
            case .systemWide:
                let own = translatePIDToProcessObject(getpid())
                guard own.isValid else {
                    self.buildChain()
                    return
                }
                description = self.makeSystemTapDescription(excluding: self.systemExclusions(own: own))
            }
            description.uuid = chain.tapUUID
            var address = AudioObjectPropertyAddress(kAudioTapPropertyDescription)
            var value = description
            let status = withUnsafeMutablePointer(to: &value) { pointer in
                AudioObjectSetPropertyData(chain.tapID, &address, 0, nil,
                                           UInt32(MemoryLayout<CATapDescription>.size),
                                           UnsafeRawPointer(pointer))
            }
            if status != noErr {
                self.buildChain()
            }
        }
    }

    func stop() {
        // Strong capture on purpose: the engine stays alive until teardown completes,
        // so releasing the last external reference right after stop() is always safe.
        controlQueue.async { self.tearDownChain() }
    }

    /// coreaudiod restarted: every HAL object ID in the chain is dead. Drop them without
    /// destroying (the IDs no longer refer to our objects) and rebuild from the last config.
    func handleServiceRestart() {
        controlQueue.async { [weak self] in
            guard let self, self.chain != nil else { return }
            self.chain = nil
            self.isRunning = false
            self.levels.update(repeating: 0, count: 2)
            self.buildChain()
        }
    }

    /// Thread-safe RMS levels (0...1) for UI meters.
    var currentLevels: (left: Float, right: Float) {
        (min(1, max(0, levels[0])), min(1, max(0, levels[1])))
    }

    // MARK: - Control plane (everything below runs on controlQueue)

    private var explicitRequestedUID: String? {
        if case .systemWide = source { return nil }
        return lastRequestedUID
    }

    private func pushParameters(_ config: AppAudioConfig, into chain: Chain) {
        chain.rtState.setParameters(RTState.Parameters(config: config))
        chain.rtState.eq.setParameters(gainsDB: config.eq.gains, preampDB: config.eq.preampDB)
    }

    private func resolveTarget(requestedUID: String?) -> (id: AudioObjectID, uid: String)? {
        if let requestedUID, let deviceID = translateUIDToDevice(requestedUID) {
            return (deviceID, requestedUID)
        }
        guard let defaultID = readDefaultOutputDevice(),
              let uid = readDeviceUID(defaultID) else { return nil }
        return (defaultID, uid)
    }

    private func makeAppTapDescription(objectIDs: [AudioObjectID]) -> CATapDescription {
        let description = CATapDescription(stereoMixdownOfProcesses: objectIDs)
        description.name = "Auricle App Tap"
        description.muteBehavior = .mutedWhenTapped
        description.isPrivate = true
        return description
    }

    private func makeSystemTapDescription(excluding processObjects: [AudioObjectID]) -> CATapDescription {
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: processObjects)
        description.name = "Auricle Master Tap"
        description.muteBehavior = .mutedWhenTapped
        description.isPrivate = true
        return description
    }

    /// Own process first, then the per-app-tapped objects; invalid and duplicate IDs dropped.
    private func systemExclusions(own: AudioObjectID) -> [AudioObjectID] {
        var seen = Set<AudioObjectID>()
        var list: [AudioObjectID] = []
        for id in [own] + tappedObjectIDs where id.isValid && seen.insert(id).inserted {
            list.append(id)
        }
        return list
    }

    private func reportFailure(_ message: String) {
        isRunning = false
        let generation = buildGeneration.withLock { $0 }
        guard let handler = onFailure else { return }
        DispatchQueue.main.async { [weak self] in
            // Drop failures from superseded builds: a newer build may already have recovered.
            guard let self, self.buildGeneration.withLock({ $0 }) == generation else { return }
            handler(message)
        }
    }

    /// Only a permission-shaped OSStatus earns the "permission:" prefix; anything else
    /// (e.g. the tapped process quit mid-build) stays a per-engine error.
    private static func tapFailureMessage(_ status: OSStatus, what: String) -> String {
        let permissionStatuses: [OSStatus] = [
            OSStatus(kAudioHardwareIllegalOperationError),
            OSStatus(kAudioDevicePermissionsError),
        ]
        let text = "could not create the \(what) (OSStatus \(status))"
        return permissionStatuses.contains(status) ? "permission: \(text)" : text
    }

    private func tearDownChain() {
        isRunning = false
        guard let chain else { return }
        self.chain = nil
        Self.destroy(chain: chain)
        levels.update(repeating: 0, count: 2)
    }

    private static func destroy(chain: Chain) {
        for listener in chain.listeners {
            listener.remove()
        }
        if let procID = chain.procID {
            AudioDeviceStop(chain.aggregateID, procID)
            AudioDeviceDestroyIOProcID(chain.aggregateID, procID)
        }
        AudioHardwareDestroyAggregateDevice(chain.aggregateID)
        AudioHardwareDestroyProcessTap(chain.tapID)
    }

    private func buildChain() {
        buildGeneration.withLock { $0 += 1 }
        tearDownChain()
        guard let config = lastConfig else { return }
        guard let target = resolveTarget(requestedUID: explicitRequestedUID) else {
            reportFailure("no usable output device is available")
            return
        }

        var tapID = AudioObjectID.unknown
        var tapUUID: UUID?
        var aggregateID = AudioObjectID.unknown
        var procID: AudioDeviceIOProcID?

        func unwind() {
            if aggregateID.isValid {
                if let procID {
                    AudioDeviceStop(aggregateID, procID)
                    AudioDeviceDestroyIOProcID(aggregateID, procID)
                }
                AudioHardwareDestroyAggregateDevice(aggregateID)
            }
            if tapID.isValid {
                AudioHardwareDestroyProcessTap(tapID)
            }
        }

        var deferredSystemTap = false
        switch source {
        case .app:
            let description = makeAppTapDescription(objectIDs: tappedObjectIDs)
            let status = AudioHardwareCreateProcessTap(description, &tapID)
            guard status == noErr, tapID.isValid else {
                reportFailure(Self.tapFailureMessage(status, what: "process tap"))
                return
            }
            tapUUID = description.uuid
        case .systemWide:
            let own = translatePIDToProcessObject(getpid())
            if own.isValid {
                let description = makeSystemTapDescription(excluding: systemExclusions(own: own))
                let status = AudioHardwareCreateProcessTap(description, &tapID)
                guard status == noErr, tapID.isValid else {
                    reportFailure(Self.tapFailureMessage(status, what: "system tap"))
                    return
                }
                tapUUID = description.uuid
            } else {
                deferredSystemTap = true
            }
        }

        let aggregateSuffix = UUID().uuidString
        var aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Auricle: \(aggregateSuffix.suffix(8))",
            kAudioAggregateDeviceUIDKey: "\(AudioDeviceManager.auricleAggregatePrefix).\(aggregateSuffix)",
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceMainSubDeviceKey: target.uid,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [
                [kAudioSubDeviceUIDKey: target.uid,
                 kAudioSubDeviceDriftCompensationKey: 0],
            ],
        ]
        if let tapUUID {
            aggregateDescription[kAudioAggregateDeviceTapListKey] = [
                [kAudioSubTapUIDKey: tapUUID.uuidString,
                 kAudioSubTapDriftCompensationKey: 1],
            ]
        } else {
            aggregateDescription[kAudioAggregateDeviceTapListKey] = [[String: Any]]()
        }
        let aggregateStatus = AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary,
                                                                 &aggregateID)
        guard aggregateStatus == noErr, aggregateID.isValid else {
            unwind()
            reportFailure("could not create the replay device (OSStatus \(aggregateStatus))")
            return
        }

        var frameSize: UInt32 = 512
        var frameSizeAddress = AudioObjectPropertyAddress(kAudioDevicePropertyBufferFrameSize)
        AudioObjectSetPropertyData(aggregateID, &frameSizeAddress, 0, nil,
                                   UInt32(MemoryLayout<UInt32>.size), &frameSize)
        if getProperty(aggregateID, frameSizeAddress, &frameSize) != noErr || frameSize == 0 {
            frameSize = 512
        }

        var sampleRate = readSampleRate(aggregateID) ?? 0
        if sampleRate <= 0, tapID.isValid {
            var tapFormat = AudioStreamBasicDescription()
            if getProperty(tapID, AudioObjectPropertyAddress(kAudioTapPropertyFormat), &tapFormat) == noErr {
                sampleRate = tapFormat.mSampleRate
            }
        }
        if sampleRate <= 0 {
            sampleRate = 48_000
        }

        if let format = firstOutputStreamFormat(aggregateID), !isFloat32(format) {
            unwind()
            reportFailure("the target device exposes an unsupported stream format")
            return
        }

        let eq = GraphicEQ(sampleRate: sampleRate, channelCount: 2)
        eq.setParameters(gainsDB: config.eq.gains, preampDB: config.eq.preampDB)
        eq.reset()
        let rtState = RTState(capacity: max(4096, Int(frameSize) * 4),
                              sampleRate: sampleRate,
                              eq: eq,
                              levels: levels,
                              parameters: RTState.Parameters(config: config))
        let ioBlock: AudioDeviceIOBlock = { _, inputData, _, outputData, _ in
            rtState.render(input: inputData, output: outputData)
        }
        let procStatus = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, nil, ioBlock)
        guard procStatus == noErr, procID != nil else {
            unwind()
            reportFailure("could not install the replay IO proc (OSStatus \(procStatus))")
            return
        }
        let startStatus = AudioDeviceStart(aggregateID, procID)
        guard startStatus == noErr else {
            unwind()
            reportFailure("could not start the replay device (OSStatus \(startStatus))")
            return
        }

        if deferredSystemTap {
            var own = AudioObjectID.unknown
            for _ in 0..<10 {
                own = translatePIDToProcessObject(getpid())
                if own.isValid { break }
                usleep(20_000)
            }
            guard own.isValid else {
                unwind()
                reportFailure("could not resolve Auricle's own audio process for the master tap")
                return
            }
            let description = makeSystemTapDescription(excluding: systemExclusions(own: own))
            let status = AudioHardwareCreateProcessTap(description, &tapID)
            guard status == noErr, tapID.isValid else {
                unwind()
                reportFailure(Self.tapFailureMessage(status, what: "system tap"))
                return
            }
            tapUUID = description.uuid
            var listAddress = AudioObjectPropertyAddress(kAudioAggregateDevicePropertyTapList)
            var list = [description.uuid.uuidString] as CFArray
            let attachStatus = withUnsafeMutablePointer(to: &list) { pointer in
                AudioObjectSetPropertyData(aggregateID, &listAddress, 0, nil,
                                           UInt32(MemoryLayout<CFArray>.size),
                                           UnsafeRawPointer(pointer))
            }
            guard attachStatus == noErr else {
                unwind()
                reportFailure("could not attach the system tap (OSStatus \(attachStatus))")
                return
            }
        }

        var listeners: [PropertyListener] = []
        let aggregate = aggregateID
        if let listener = PropertyListener(objectID: aggregate,
                                           selector: kAudioDevicePropertyNominalSampleRate,
                                           queue: controlQueue,
                                           handler: { [weak self] in
            guard let self, let chain = self.chain, chain.aggregateID == aggregate else { return }
            if let rate = readSampleRate(aggregate), abs(rate - chain.sampleRate) > 0.5 {
                self.buildChain()
            }
        }) {
            listeners.append(listener)
        }
        let targetID = target.id
        if let listener = PropertyListener(objectID: targetID,
                                           selector: kAudioDevicePropertyDeviceIsAlive,
                                           queue: controlQueue,
                                           handler: { [weak self] in
            guard let self, let chain = self.chain, chain.targetDeviceID == targetID else { return }
            var alive: UInt32 = 1
            let status = getProperty(targetID, AudioObjectPropertyAddress(kAudioDevicePropertyDeviceIsAlive), &alive)
            if status != noErr || alive == 0 {
                // The target vanished: rebuild, which re-resolves to the default output.
                self.buildChain()
            }
        }) {
            listeners.append(listener)
        }

        guard let finalTapUUID = tapUUID else {
            unwind()
            reportFailure("internal error: tap identity was lost during build")
            return
        }
        chain = Chain(tapID: tapID,
                      tapUUID: finalTapUUID,
                      aggregateID: aggregateID,
                      procID: procID,
                      targetDeviceID: target.id,
                      targetUID: target.uid,
                      sampleRate: sampleRate,
                      rtState: rtState,
                      listeners: listeners)
        isRunning = true
    }

    // MARK: - Chain state

    private struct Chain {
        let tapID: AudioObjectID
        let tapUUID: UUID
        let aggregateID: AudioObjectID
        let procID: AudioDeviceIOProcID?
        let targetDeviceID: AudioObjectID
        let targetUID: String
        let sampleRate: Double
        let rtState: RTState
        let listeners: [PropertyListener]
    }

    private final class PropertyListener {
        private let objectID: AudioObjectID
        private var address: AudioObjectPropertyAddress
        private let queue: DispatchQueue
        private let block: AudioObjectPropertyListenerBlock
        private var installed: Bool

        init?(objectID: AudioObjectID,
              selector: AudioObjectPropertySelector,
              queue: DispatchQueue,
              handler: @escaping () -> Void) {
            self.objectID = objectID
            self.address = AudioObjectPropertyAddress(selector)
            self.queue = queue
            self.block = { _, _ in handler() }
            installed = false
            guard AudioObjectAddPropertyListenerBlock(objectID, &address, queue, block) == noErr else {
                return nil
            }
            installed = true
        }

        func remove() {
            guard installed else { return }
            installed = false
            AudioObjectRemovePropertyListenerBlock(objectID, &address, queue, block)
        }

        deinit { remove() }
    }

    // MARK: - Realtime state

    private final class RTState {
        struct Parameters {
            var targetGain: Float
            var eqEnabled: Bool

            init(config: AppAudioConfig) {
                targetGain = config.isMuted ? 0 : max(0, config.volume) * powf(10, config.boostDB / 20)
                eqEnabled = config.eq.enabled
            }
        }

        let eq: GraphicEQ

        private let capacity: Int
        private let sampleRate: Float
        private let levels: UnsafeMutablePointer<Float>
        private let workL: UnsafeMutablePointer<Float>
        private let workR: UnsafeMutablePointer<Float>
        private let outL: UnsafeMutablePointer<Float>
        private let outR: UnsafeMutablePointer<Float>
        private let eqChannels: [UnsafeMutablePointer<Float>]
        private let lock: UnsafeMutablePointer<os_unfair_lock>
        private var pending: Parameters
        private var active: Parameters
        private var currentGain: Float = 0

        init(capacity: Int,
             sampleRate: Double,
             eq: GraphicEQ,
             levels: UnsafeMutablePointer<Float>,
             parameters: Parameters) {
            self.capacity = capacity
            self.sampleRate = Float(sampleRate)
            self.eq = eq
            self.levels = levels
            workL = .allocate(capacity: capacity)
            workL.initialize(repeating: 0, count: capacity)
            workR = .allocate(capacity: capacity)
            workR.initialize(repeating: 0, count: capacity)
            outL = .allocate(capacity: capacity)
            outL.initialize(repeating: 0, count: capacity)
            outR = .allocate(capacity: capacity)
            outR.initialize(repeating: 0, count: capacity)
            eqChannels = [outL, outR]
            lock = .allocate(capacity: 1)
            lock.initialize(to: os_unfair_lock())
            pending = parameters
            active = parameters
        }

        deinit {
            workL.deallocate()
            workR.deallocate()
            outL.deallocate()
            outR.deallocate()
            lock.deallocate()
        }

        func setParameters(_ parameters: Parameters) {
            os_unfair_lock_lock(lock)
            pending = parameters
            os_unfair_lock_unlock(lock)
        }

        func render(input: UnsafePointer<AudioBufferList>, output: UnsafeMutablePointer<AudioBufferList>) {
            if os_unfair_lock_trylock(lock) {
                active = pending
                os_unfair_lock_unlock(lock)
            }

            let outputBuffers = UnsafeMutableAudioBufferListPointer(output)
            var frames = 0
            for buffer in outputBuffers where buffer.mNumberChannels > 0 {
                frames = max(frames, Int(buffer.mDataByteSize) / (Int(buffer.mNumberChannels) * MemoryLayout<Float>.size))
            }
            for buffer in outputBuffers {
                if let data = buffer.mData, buffer.mDataByteSize > 0 {
                    memset(data, 0, Int(buffer.mDataByteSize))
                }
            }
            frames = min(frames, capacity)
            guard frames > 0 else { return }
            let decay = expf(-Float(frames) / (sampleRate * 0.3))

            let inputBuffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
            var gathered = 0
            for buffer in inputBuffers {
                if gathered >= 2 { break }
                let channelCount = Int(buffer.mNumberChannels)
                guard channelCount > 0, let data = buffer.mData, buffer.mDataByteSize > 0 else { continue }
                let available = min(frames, Int(buffer.mDataByteSize) / (channelCount * MemoryLayout<Float>.size))
                let samples = data.assumingMemoryBound(to: Float.self)
                var channel = 0
                while channel < channelCount && gathered < 2 {
                    let destination = gathered == 0 ? workL : workR
                    if channelCount == 1 {
                        memcpy(destination, samples, available * MemoryLayout<Float>.size)
                    } else {
                        for frame in 0..<available {
                            destination[frame] = samples[frame * channelCount + channel]
                        }
                    }
                    if available < frames {
                        memset(destination + available, 0, (frames - available) * MemoryLayout<Float>.size)
                    }
                    channel += 1
                    gathered += 1
                }
            }
            guard gathered > 0 else {
                levels[0] *= decay
                levels[1] *= decay
                return
            }
            if gathered == 1 {
                memcpy(workR, workL, frames * MemoryLayout<Float>.size)
            }

            var gain = currentGain
            var step = (active.targetGain - currentGain) / Float(frames)
            vDSP_vrampmul2(workL, workR, 1, &gain, &step, outL, outR, 1, vDSP_Length(frames))
            currentGain = active.targetGain

            if active.eqEnabled {
                eq.process(channels: eqChannels, stride: 1, frameCount: frames)
            }

            var lowerBound: Float = -1
            var upperBound: Float = 1
            vDSP_vclip(outL, 1, &lowerBound, &upperBound, outL, 1, vDSP_Length(frames))
            vDSP_vclip(outR, 1, &lowerBound, &upperBound, outR, 1, vDSP_Length(frames))

            var rms: Float = 0
            vDSP_rmsqv(outL, 1, &rms, vDSP_Length(frames))
            levels[0] = max(rms, levels[0] * decay)
            vDSP_rmsqv(outR, 1, &rms, vDSP_Length(frames))
            levels[1] = max(rms, levels[1] * decay)

            var written = 0
            for buffer in outputBuffers {
                if written >= 2 { break }
                let channelCount = Int(buffer.mNumberChannels)
                guard channelCount > 0, let data = buffer.mData, buffer.mDataByteSize > 0 else { continue }
                let available = min(frames, Int(buffer.mDataByteSize) / (channelCount * MemoryLayout<Float>.size))
                let samples = data.assumingMemoryBound(to: Float.self)
                var channel = 0
                while channel < channelCount && written < 2 {
                    let source = written == 0 ? outL : outR
                    if channelCount == 1 {
                        memcpy(samples, source, available * MemoryLayout<Float>.size)
                    } else {
                        for frame in 0..<available {
                            samples[frame * channelCount + channel] = source[frame]
                        }
                    }
                    channel += 1
                    written += 1
                }
            }
        }
    }
}

// MARK: - Raw property helpers (control plane only)

private func getProperty<T>(_ objectID: AudioObjectID,
                            _ address: AudioObjectPropertyAddress,
                            _ value: inout T) -> OSStatus {
    var address = address
    var size = UInt32(MemoryLayout<T>.size)
    return withUnsafeMutablePointer(to: &value) { pointer in
        AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, UnsafeMutableRawPointer(pointer))
    }
}

private func readDefaultOutputDevice() -> AudioObjectID? {
    var deviceID = AudioObjectID.unknown
    let status = getProperty(.system, AudioObjectPropertyAddress(kAudioHardwarePropertyDefaultOutputDevice), &deviceID)
    guard status == noErr, deviceID.isValid else { return nil }
    return deviceID
}

private func readDeviceUID(_ deviceID: AudioObjectID) -> String? {
    var uid = "" as CFString
    guard getProperty(deviceID, AudioObjectPropertyAddress(kAudioDevicePropertyDeviceUID), &uid) == noErr else {
        return nil
    }
    return uid as String
}

private func readSampleRate(_ deviceID: AudioObjectID) -> Double? {
    var rate: Float64 = 0
    guard getProperty(deviceID, AudioObjectPropertyAddress(kAudioDevicePropertyNominalSampleRate), &rate) == noErr,
          rate > 0 else { return nil }
    return rate
}

private func translateUIDToDevice(_ uid: String) -> AudioObjectID? {
    var address = AudioObjectPropertyAddress(kAudioHardwarePropertyTranslateUIDToDevice)
    var qualifier = uid as CFString
    var deviceID = AudioObjectID.unknown
    var size = UInt32(MemoryLayout<AudioObjectID>.size)
    let status = withUnsafeMutablePointer(to: &qualifier) { pointer in
        AudioObjectGetPropertyData(.system, &address,
                                   UInt32(MemoryLayout<CFString>.size), UnsafeRawPointer(pointer),
                                   &size, &deviceID)
    }
    guard status == noErr, deviceID.isValid else { return nil }
    return deviceID
}

private func translatePIDToProcessObject(_ pid: pid_t) -> AudioObjectID {
    var address = AudioObjectPropertyAddress(kAudioHardwarePropertyTranslatePIDToProcessObject)
    var qualifier = pid
    var object = AudioObjectID.unknown
    var size = UInt32(MemoryLayout<AudioObjectID>.size)
    let status = AudioObjectGetPropertyData(.system, &address,
                                            UInt32(MemoryLayout<pid_t>.size), &qualifier,
                                            &size, &object)
    return status == noErr ? object : .unknown
}

private func firstOutputStreamFormat(_ deviceID: AudioObjectID) -> AudioStreamBasicDescription? {
    var address = AudioObjectPropertyAddress(kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeOutput)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr,
          size >= UInt32(MemoryLayout<AudioObjectID>.size) else { return nil }
    var streams = [AudioObjectID](repeating: .unknown, count: Int(size) / MemoryLayout<AudioObjectID>.size)
    guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &streams) == noErr,
          let stream = streams.first, stream.isValid else { return nil }
    var format = AudioStreamBasicDescription()
    guard getProperty(stream, AudioObjectPropertyAddress(kAudioStreamPropertyVirtualFormat), &format) == noErr else {
        return nil
    }
    return format
}

private func isFloat32(_ format: AudioStreamBasicDescription) -> Bool {
    format.mFormatID == kAudioFormatLinearPCM
        && format.mFormatFlags & kAudioFormatFlagIsFloat != 0
        && format.mBitsPerChannel == 32
}
