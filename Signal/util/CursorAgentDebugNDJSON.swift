//
// Temporary Cursor debug session instrumentation — remove after investigation.
//

import Foundation
import SignalServiceKit
import UIKit

// #region agent log
enum CursorAgentDebugNDJSON {
    private static let sessionId = "78ca08"
    private static let logPath = "/Users/ben/Sites/hcp/.cursor/debug-78ca08.log"
    private static let endpoint = URL(string: "http://127.0.0.1:7532/ingest/a3e21906-305f-4b8f-993d-47a049b3f6c4")!

    static func log(
        hypothesisId: String,
        location: String,
        message: String,
        data: [String: String] = [:],
        runId: String = "pre-fix",
    ) {
        let ts = Int(Date().timeIntervalSince1970 * 1000)
        let obj: [String: Any] = [
            "sessionId": sessionId,
            "hypothesisId": hypothesisId,
            "location": location,
            "message": message,
            "timestamp": ts,
            "runId": runId,
            "data": data,
        ]
        guard JSONSerialization.isValidJSONObject(obj),
              let json = try? JSONSerialization.data(withJSONObject: obj),
              let line = String(data: json, encoding: .utf8) else { return }

        Logger.info("CURSOR_AGENT_DEBUG \(line)")

        let payload = (line + "\n").data(using: .utf8) ?? Data()
        if FileManager.default.fileExists(atPath: logPath) {
            if let h = try? FileHandle(forWritingTo: URL(fileURLWithPath: logPath)) {
                _ = try? h.seekToEnd()
                _ = try? h.write(contentsOf: payload)
                _ = try? h.close()
            }
        } else {
            _ = try? payload.write(to: URL(fileURLWithPath: logPath), options: .atomic)
        }

        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(sessionId, forHTTPHeaderField: "X-Debug-Session-Id")
        req.httpBody = json
        URLSession.shared.dataTask(with: req).resume()
    }
}
// #endregion
