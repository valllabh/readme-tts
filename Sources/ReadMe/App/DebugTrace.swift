import Foundation

// Development visibility: when Debug Mode is on, every stage of the pipeline
// appends here and lands in the daily log as DEBUG entries, readable live in
// the Logs panel of the app window. Nothing is captured when disabled, so
// spoken content stays out of the log in normal use.
enum DebugTrace {
    static func append(_ tag: String, _ text: String) {
        Log.debug("\(tag): \(text)")
    }
}
