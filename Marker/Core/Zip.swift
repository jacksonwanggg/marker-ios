import Foundation

struct ZipEntry: Sendable, Hashable, Identifiable {
    let path: String
    let data: Data

    var id: String { path }
    var name: String { (path as NSString).lastPathComponent }
    var ext: String { (name as NSString).pathExtension.lowercased() }
    var size: Int { data.count }

    var badge: String {
        if name == "Makefile" { return "MK" }
        let e = ext.uppercased()
        return e.isEmpty ? "TXT" : String(e.prefix(4))
    }

    private static let textExts: Set<String> = [
        "tex", "txt", "md", "py", "c", "h", "cc", "cpp", "hpp", "java", "js", "ts", "swift", "json",
        "csv", "sty", "cls", "bib", "yml", "yaml", "sh", "hs", "rs", "go", "kt", "rb", "pl", "sql", "xml", "html", "css",
    ]

    var isText: Bool {
        if Self.textExts.contains(ext) || name == "Makefile" { return true }
        if !ext.isEmpty { return false }
        let head = data.prefix(4096)
        return !head.contains(0) && String(data: head, encoding: .utf8) != nil
    }

    var isLatex: Bool { ["tex", "sty", "cls", "bib"].contains(ext) }
}

struct FileBundle: Sendable {
    let name: String
    let entries: [ZipEntry]
    var totalSize: Int { entries.reduce(0) { $0 + $1.size } }
}

enum ZipError: LocalizedError {
    case notZip
    var errorDescription: String? { "That file isn't a zip archive." }
}

/// Small zip reader (stored and deflate only) so we don't need a library.
enum Zip {
    static func entries(_ data: Data) throws -> [ZipEntry] {
        let b = [UInt8](data)
        guard b.count >= 22, b[0] == 0x50, b[1] == 0x4b else { throw ZipError.notZip }
        func u16(_ o: Int) -> Int { Int(b[o]) | Int(b[o + 1]) << 8 }
        func u32(_ o: Int) -> Int { u16(o) | u16(o + 2) << 16 }

        var eocd = -1
        var i = b.count - 22
        let stop = max(0, b.count - 22 - 65_535)
        while i >= stop {
            if b[i] == 0x50, b[i + 1] == 0x4b, b[i + 2] == 0x05, b[i + 3] == 0x06 { eocd = i; break }
            i -= 1
        }
        guard eocd >= 0 else { throw ZipError.notZip }

        let count = u16(eocd + 10)
        var p = u32(eocd + 16)
        var out: [ZipEntry] = []
        for _ in 0..<count {
            guard p + 46 <= b.count, u32(p) == 0x02014b50 else { break }
            let method = u16(p + 10)
            let csize = u32(p + 20)
            let nlen = u16(p + 28), xlen = u16(p + 30), clen = u16(p + 32)
            let local = u32(p + 42)
            guard p + 46 + nlen <= b.count else { break }
            let name = String(decoding: b[(p + 46)..<(p + 46 + nlen)], as: UTF8.self)
            p += 46 + nlen + xlen + clen

            let last = (name as NSString).lastPathComponent
            if name.hasSuffix("/") || name.hasPrefix("__MACOSX") || last.hasPrefix(".") { continue }
            guard local + 30 <= b.count, u32(local) == 0x04034b50 else { continue }
            let start = local + 30 + u16(local + 26) + u16(local + 28)
            guard start + csize <= b.count else { continue }
            let raw = Data(b[start..<(start + csize)])
            let content: Data?
            switch method {
            case 0: content = raw
            case 8: content = try? (raw as NSData).decompressed(using: .zlib) as Data
            default: content = nil
            }
            if let content { out.append(ZipEntry(path: name, data: content)) }
        }
        return out
    }

    static func isZip(_ data: Data) -> Bool { data.starts(with: [0x50, 0x4b]) }
    static func isPDF(_ data: Data) -> Bool { data.starts(with: Array("%PDF".utf8)) }
}
