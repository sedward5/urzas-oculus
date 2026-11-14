import Foundation
import CZlib

public enum SeventeenLandsCSVError: Error, Equatable {
    case invalidGzipStream(Int32)
    case truncatedGzipStream
    case malformedCSV
    case invalidUTF8
    case missingHeader
    case inconsistentColumnCount(expected: Int, actual: Int)
    case duplicateColumn(String)
}

/// Header metadata for one set-specific 17Lands CSV. Card-facet columns vary
/// by expansion, so callers must resolve names dynamically rather than rely
/// on fixed column positions.
public struct SeventeenLandsCSVHeader: Equatable, Sendable {
    public let columns: [String]
    private let indices: [String: Int]

    public init(columns: [String]) throws {
        var indices: [String: Int] = [:]
        for (index, column) in columns.enumerated() {
            guard indices[column] == nil else {
                throw SeventeenLandsCSVError.duplicateColumn(column)
            }
            indices[column] = index
        }
        self.columns = columns
        self.indices = indices
    }

    public func index(of column: String) -> Int? {
        indices[column]
    }

    public func value(for column: String, in row: [String]) -> String? {
        guard let index = indices[column], row.indices.contains(index) else { return nil }
        return row[index]
    }
}

/// Incrementally decompresses a gzip CSV and emits one parsed row at a time.
/// Neither the compressed archive nor the decompressed dataset is loaded in
/// memory as a whole.
public enum SeventeenLandsCSVReader {
    /// Reads the first row as the dynamic header and streams subsequent rows.
    /// The returned count excludes the header.
    @discardableResult
    public static func readTable(
        from url: URL,
        chunkSize: Int = 64 * 1024,
        onHeader: @escaping (SeventeenLandsCSVHeader) throws -> Void,
        onRow: @escaping ([String]) throws -> Void
    ) throws -> Int {
        var header: SeventeenLandsCSVHeader?
        var rowCount = 0
        try readRows(from: url, chunkSize: chunkSize) { values in
            if header == nil {
                let parsedHeader = try SeventeenLandsCSVHeader(columns: values)
                header = parsedHeader
                try onHeader(parsedHeader)
            } else {
                guard values.count == header?.columns.count else {
                    throw SeventeenLandsCSVError.inconsistentColumnCount(
                        expected: header?.columns.count ?? 0,
                        actual: values.count
                    )
                }
                try onRow(values)
                rowCount += 1
            }
        }
        guard header != nil else { throw SeventeenLandsCSVError.missingHeader }
        return rowCount
    }

    /// Low-level row reader. The first emitted row is the CSV header.
    @discardableResult
    public static func readRows(
        from url: URL,
        chunkSize: Int = 64 * 1024,
        onRow: @escaping ([String]) throws -> Void
    ) throws -> Int {
        guard chunkSize > 0 else { throw SeventeenLandsCSVError.malformedCSV }
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }

        var stream = z_stream()
        let initialized = inflateInit2_(
            &stream,
            MAX_WBITS + 16,
            ZLIB_VERSION,
            Int32(MemoryLayout<z_stream>.size)
        )
        guard initialized == Z_OK else {
            throw SeventeenLandsCSVError.invalidGzipStream(initialized)
        }
        defer { inflateEnd(&stream) }

        let parser = CSVRowParser(onRow: onRow)
        var finished = false

        while !finished {
            let input = try file.read(upToCount: chunkSize) ?? Data()
            if input.isEmpty {
                throw SeventeenLandsCSVError.truncatedGzipStream
            }

            try input.withUnsafeBytes { rawBuffer in
                guard let inputBase = rawBuffer.bindMemory(to: Bytef.self).baseAddress else {
                    return
                }
                stream.next_in = UnsafeMutablePointer(mutating: inputBase)
                stream.avail_in = uInt(input.count)

                var lastOutputCount = chunkSize
                while stream.avail_in > 0 || lastOutputCount == chunkSize {
                    var output = [UInt8](repeating: 0, count: chunkSize)
                    var status: Int32 = Z_OK
                    var outputCount = 0

                    status = output.withUnsafeMutableBufferPointer { outputBuffer in
                        stream.next_out = outputBuffer.baseAddress
                        stream.avail_out = uInt(outputBuffer.count)
                        let result = inflate(&stream, Z_NO_FLUSH)
                        outputCount = outputBuffer.count - Int(stream.avail_out)
                        return result
                    }

                    if outputCount > 0 {
                        try parser.consume(output.prefix(outputCount))
                    }
                    lastOutputCount = outputCount

                    if status == Z_STREAM_END {
                        finished = true
                        break
                    }
                    guard status == Z_OK || status == Z_BUF_ERROR else {
                        throw SeventeenLandsCSVError.invalidGzipStream(status)
                    }
                    if status == Z_BUF_ERROR && outputCount == 0 {
                        break
                    }
                }
            }
        }

        try parser.finish()
        return parser.emittedRowCount
    }
}

private final class CSVRowParser {
    private enum State {
        case fieldStart
        case unquoted
        case quoted
        case afterQuote
    }

    private let onRow: ([String]) throws -> Void
    private var state: State = .fieldStart
    private var field: [UInt8] = []
    private var row: [String] = []
    private var skipNextLineFeed = false
    private(set) var emittedRowCount = 0

    init(onRow: @escaping ([String]) throws -> Void) {
        self.onRow = onRow
    }

    func consume<S: Sequence>(_ bytes: S) throws where S.Element == UInt8 {
        for byte in bytes {
            if skipNextLineFeed {
                skipNextLineFeed = false
                if byte == 10 { continue }
            }

            switch state {
            case .fieldStart:
                switch byte {
                case 34: state = .quoted
                case 44: try finishField()
                case 10: try finishRow()
                case 13:
                    try finishRow()
                    skipNextLineFeed = true
                default:
                    field.append(byte)
                    state = .unquoted
                }
            case .unquoted:
                switch byte {
                case 34: throw SeventeenLandsCSVError.malformedCSV
                case 44: try finishField()
                case 10: try finishRow()
                case 13:
                    try finishRow()
                    skipNextLineFeed = true
                default: field.append(byte)
                }
            case .quoted:
                if byte == 34 {
                    state = .afterQuote
                } else {
                    field.append(byte)
                }
            case .afterQuote:
                switch byte {
                case 34:
                    field.append(34)
                    state = .quoted
                case 44: try finishField()
                case 10: try finishRow()
                case 13:
                    try finishRow()
                    skipNextLineFeed = true
                default: throw SeventeenLandsCSVError.malformedCSV
                }
            }
        }
    }

    func finish() throws {
        if case .quoted = state { throw SeventeenLandsCSVError.malformedCSV }
        switch state {
        case .fieldStart:
            if !field.isEmpty || !row.isEmpty { try finishRow() }
        case .unquoted, .afterQuote:
            try finishRow()
        case .quoted:
            throw SeventeenLandsCSVError.malformedCSV
        }
    }

    private func finishField() throws {
        guard let value = String(bytes: field, encoding: .utf8) else {
            throw SeventeenLandsCSVError.invalidUTF8
        }
        row.append(value)
        field.removeAll(keepingCapacity: true)
        state = .fieldStart
    }

    private func finishRow() throws {
        try finishField()
        try onRow(row)
        emittedRowCount += 1
        row.removeAll(keepingCapacity: true)
    }
}
