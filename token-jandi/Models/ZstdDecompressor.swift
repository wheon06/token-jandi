import Foundation
import libzstd

/// Streaming zstd decoding for Codex's archived session logs (`*.jsonl.zst`).
nonisolated enum ZstdDecompressor {
    struct DecodeError: Error, CustomStringConvertible {
        let description: String
    }

    /// Decompresses `url` and hands each decoded chunk to `consume` in order,
    /// so large archives never have to be held in memory at once.
    static func decompress(fileAt url: URL, consume: (Data) throws -> Void) throws {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        guard let context = ZSTD_createDCtx() else {
            throw DecodeError(description: "ZSTD_createDCtx failed")
        }
        defer { ZSTD_freeDCtx(context) }

        let inputCapacity = ZSTD_DStreamInSize()
        let outputCapacity = ZSTD_DStreamOutSize()
        var output = [UInt8](repeating: 0, count: outputCapacity)

        while true {
            let input = handle.readData(ofLength: inputCapacity)
            if input.isEmpty { break }

            try input.withUnsafeBytes { (inputPointer: UnsafeRawBufferPointer) in
                var inputBuffer = ZSTD_inBuffer(src: inputPointer.baseAddress, size: input.count, pos: 0)

                while inputBuffer.pos < inputBuffer.size {
                    try output.withUnsafeMutableBytes { (outputPointer: UnsafeMutableRawBufferPointer) in
                        var outputBuffer = ZSTD_outBuffer(dst: outputPointer.baseAddress, size: outputCapacity, pos: 0)
                        let status = ZSTD_decompressStream(context, &outputBuffer, &inputBuffer)
                        if ZSTD_isError(status) != 0 {
                            throw DecodeError(description: String(cString: ZSTD_getErrorName(status)))
                        }
                        if outputBuffer.pos > 0, let base = outputPointer.baseAddress {
                            try consume(Data(bytes: base, count: outputBuffer.pos))
                        }
                    }
                }
            }
        }
    }

    /// One-shot compression. Only used to build fixtures in tests.
    static func compress(_ data: Data, level: Int32 = 3) throws -> Data {
        let capacity = ZSTD_compressBound(data.count)
        var destination = [UInt8](repeating: 0, count: capacity)

        let written = data.withUnsafeBytes { (source: UnsafeRawBufferPointer) in
            destination.withUnsafeMutableBytes { (target: UnsafeMutableRawBufferPointer) in
                ZSTD_compress(target.baseAddress, capacity, source.baseAddress, data.count, level)
            }
        }
        if ZSTD_isError(written) != 0 {
            throw DecodeError(description: String(cString: ZSTD_getErrorName(written)))
        }
        return Data(destination[0..<written])
    }
}

/// Splits a byte stream into newline-delimited JSON objects, tolerating lines
/// that straddle chunk boundaries.
nonisolated struct JSONLineReader {
    private var pending = Data()

    mutating func feed(_ chunk: Data, _ body: ([String: Any]) -> Void) {
        pending.append(chunk)

        var lineStart = pending.startIndex
        while let newline = pending[lineStart...].firstIndex(of: UInt8(ascii: "\n")) {
            Self.emit(pending[lineStart..<newline], body)
            lineStart = pending.index(after: newline)
        }

        if lineStart == pending.endIndex {
            pending.removeAll(keepingCapacity: true)
        } else if lineStart > pending.startIndex {
            pending = Data(pending[lineStart...])
        }
    }

    mutating func finish(_ body: ([String: Any]) -> Void) {
        if !pending.isEmpty {
            Self.emit(pending, body)
            pending.removeAll()
        }
    }

    private static func emit(_ line: Data, _ body: ([String: Any]) -> Void) {
        guard !line.isEmpty,
              let json = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { return }
        body(json)
    }
}
