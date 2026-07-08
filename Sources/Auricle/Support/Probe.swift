import CoreAudio
import Foundation

// AGENT-TODO(core): implement. Headless diagnostics mode (`Auricle --probe`):
// print JSON to stdout with: all devices (id, uid, name, transport fourcc, in/out, volume),
// default output/input, and all audio process objects (pid, bundleID, isRunningOutput).
// Must not create taps or aggregates (no TCC prompt) and must exit(0) when done.

enum Probe {
    static func run() {
        print(#"{"error": "probe not implemented yet"}"#)
    }
}
