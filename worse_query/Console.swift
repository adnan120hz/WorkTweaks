import Foundation
import Combine
import Darwin

class Console: ObservableObject {
    @Published var output = ""

    private var pipe: Pipe?
    private var originalOut: Int32 = 0
    private var started = false

    // Performance (fix for app-wide lag): stdout chunks are buffered
    // and flushed to the published string at most ~10x per second, and
    // the stored output is capped. Previously every chunk appended
    // straight to one unbounded String that the Log and Sandbox tabs
    // render as a single Text — as it grew, each new line re-laid out
    // the whole transcript on the main thread, lagging the whole app.
    private var pending = ""
    private var flushScheduled = false
    private let maxCharacters = 60_000

    func start() {
        guard !started else { return }
        started = true

        let newPipe = Pipe()
        pipe = newPipe

        originalOut = dup(STDOUT_FILENO)
        dup2(newPipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)
        setvbuf(stdout, nil, _IONBF, 0)

        newPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if let self = self {
                data.withUnsafeBytes { rawBuffer in
                    _ = write(self.originalOut, rawBuffer.baseAddress, data.count)
                }
            }
            if let string = String(data: data, encoding: .utf8), !string.isEmpty {
                DispatchQueue.main.async {
                    self?.buffer(string)
                }
            }
        }

        print("WorkTweaks console ready.")
    }

    private func buffer(_ string: String) {
        pending += string
        guard !flushScheduled else { return }
        flushScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self else { return }
            self.flushScheduled = false
            guard !self.pending.isEmpty else { return }
            self.output += self.pending
            self.pending = ""
            if self.output.count > self.maxCharacters {
                // Drop the oldest half, cutting at a line boundary.
                let target = self.output.index(self.output.startIndex, offsetBy: self.output.count - self.maxCharacters / 2)
                if let newline = self.output.range(of: "\n", range: target..<self.output.endIndex)?.upperBound {
                    self.output = String(self.output[newline...])
                } else {
                    self.output = String(self.output[target...])
                }
            }
        }
    }
}
