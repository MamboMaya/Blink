import Foundation

enum Shell {
    static func run(
        _ path: String,
        arguments: [String] = [],
        mergingErrors: Bool = false
    ) async -> String? {
        await runChecked(path, arguments: arguments, mergingErrors: mergingErrors).output
    }

    static func runChecked(
        _ path: String,
        arguments: [String] = [],
        mergingErrors: Bool = false
    ) async -> (status: Int32, output: String?) {
        await withCheckedContinuation { continuation in
            let process = Process()
            let pipe = Pipe()

            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = arguments
            process.standardOutput = pipe
            process.standardError = mergingErrors ? pipe : FileHandle.nullDevice
            process.standardInput = FileHandle.nullDevice

            var env = ProcessInfo.processInfo.environment
            if let xcodePath = [
                "/Applications/Xcode.app/Contents/Developer",
                "/Applications/Xcode-beta.app/Contents/Developer"
            ].first(where: { FileManager.default.fileExists(atPath: $0) }) {
                env["DEVELOPER_DIR"] = xcodePath
            }
            // GUI-launched apps get a bare PATH without Homebrew, and colima
            // needs to find limactl on PATH regardless of how we were opened.
            env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + (env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin")
            process.environment = env

            do {
                try process.run()
            } catch {
                continuation.resume(returning: (-1, nil))
                return
            }

            // The pipe must be drained concurrently with waitUntilExit(): a
            // child that writes more than the pipe's buffer (~64KB) before
            // exiting would otherwise deadlock, blocked on a write nobody is
            // reading while we're blocked waiting for it to exit.
            let outputHandle = pipe.fileHandleForReading
            let readGroup = DispatchGroup()
            var data = Data()
            readGroup.enter()
            DispatchQueue.global(qos: .utility).async {
                data = outputHandle.readDataToEndOfFile()
                readGroup.leave()
            }

            process.waitUntilExit()
            readGroup.wait()

            continuation.resume(returning: (process.terminationStatus, String(data: data, encoding: .utf8)))
        }
    }
}
