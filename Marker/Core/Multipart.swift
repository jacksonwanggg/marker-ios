import Foundation

struct Multipart: Sendable {
    let boundary: String
    private var parts: [(header: String, data: Data)] = []

    init(boundary: String = "Marker-\(UUID().uuidString)") {
        self.boundary = boundary
    }

    var contentType: String { "multipart/form-data; boundary=\(boundary)" }

    mutating func add(_ name: String, _ value: String) {
        parts.append(("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n", Data(value.utf8)))
    }

    mutating func addFile(_ name: String, filename: String, mimeType: String, data: Data) {
        let safe = filename.replacingOccurrences(of: "\"", with: "")
        let header = "Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(safe)\"\r\nContent-Type: \(mimeType)\r\n\r\n"
        parts.append((header, data))
    }

    func encoded() -> Data {
        var body = Data()
        for part in parts {
            body.append("--\(boundary)\r\n" + part.header)
            body.append(part.data)
            body.append("\r\n")
        }
        body.append("--\(boundary)--\r\n")
        return body
    }
}

private extension Data {
    mutating func append(_ s: String) { append(Data(s.utf8)) }
}
