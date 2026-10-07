import Foundation

struct Multipart: Sendable {
    struct Part: Sendable {
        let name: String
        let filename: String?
        let mimeType: String?
        let data: Data
    }

    var parts: [Part] = []
    let boundary: String

    init(boundary: String = "Marker-\(UUID().uuidString)") {
        self.boundary = boundary
    }

    mutating func add(_ name: String, _ value: String) {
        parts.append(Part(name: name, filename: nil, mimeType: nil, data: Data(value.utf8)))
    }

    mutating func addFile(_ name: String, filename: String, mimeType: String, data: Data) {
        parts.append(Part(name: name, filename: filename, mimeType: mimeType, data: data))
    }

    var contentType: String { "multipart/form-data; boundary=\(boundary)" }

    func encoded() -> Data {
        var body = Data()
        for p in parts {
            body.append("--\(boundary)\r\n")
            if let filename = p.filename {
                let safe = filename.replacingOccurrences(of: "\"", with: "")
                body.append("Content-Disposition: form-data; name=\"\(p.name)\"; filename=\"\(safe)\"\r\n")
                body.append("Content-Type: \(p.mimeType ?? "application/octet-stream")\r\n\r\n")
            } else {
                body.append("Content-Disposition: form-data; name=\"\(p.name)\"\r\n\r\n")
            }
            body.append(p.data)
            body.append("\r\n")
        }
        body.append("--\(boundary)--\r\n")
        return body
    }
}

private extension Data {
    mutating func append(_ s: String) { append(Data(s.utf8)) }
}
