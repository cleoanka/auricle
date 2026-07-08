import AppKit
import CoreAudio
import Foundation

// AGENT-TODO(proc): implement this class fully.
// - Enumerate kAudioHardwarePropertyProcessObjectList on the system object; listen for list changes.
// - For each process object read pid (kAudioProcessPropertyPID), bundleID (kAudioProcessPropertyBundleID),
//   isRunningOutput (kAudioProcessPropertyIsRunningOutput) and listen for IsRunningOutput changes.
// - Fold helper processes into their top-level app via responsibility_get_pid_responsible_for_pid
//   (dlsym; fall back to the process's own pid if unavailable). Exclude Auricle's own pid.
// - Name/icon via NSRunningApplication(processIdentifier:); skip processes with no resolvable app
//   unless they are audible (then use the process name from sysctl/proc_name).
// - Track lastHeard timestamps; expose apps that are playing now, OR played within `recentWindow`,
//   OR whose configKey is in keepAliveKeys (configured apps stay visible while running).
// - Sort: playing first (alphabetical), then recent, then configured-silent.
// - All @Published mutations on the main actor.

@MainActor
final class AudioProcessMonitor: ObservableObject {
    @Published private(set) var apps: [AudioApp] = []

    /// Config keys AudioController wants kept visible even when silent (apps with saved configs).
    var keepAliveKeys: Set<String> = []

    /// Seconds an app stays listed after it stops playing.
    var recentWindow: TimeInterval = 300

    /// Fired (on main) after `apps` changes — AudioController reconciles engines here.
    var onChange: (() -> Void)?

    func start() {
        // AGENT-TODO(proc)
    }

    func refresh() {
        // AGENT-TODO(proc)
    }
}
