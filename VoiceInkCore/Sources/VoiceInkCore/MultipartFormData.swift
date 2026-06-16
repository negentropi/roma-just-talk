import Foundation

struct VoiceInkMultipartFormData {
    let boundary: String
    private var body = Data()

    init(boundary: String = "Boundary-\(UUID().uuidString)") {
        self.boundary = boundary
    }

    var contentType: String {
        "multipart/form-data; boundary=\(boundary)"
    }

    var data: Data {
        var result = body
        append("--\(boundary)--\r\n", to: &result)
        return result
    }

    mutating func addField(name: String, value: String) {
        append("--\(boundary)\r\n", to: &body)
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n", to: &body)
        append(value, to: &body)
        append("\r\n", to: &body)
    }

    mutating func addFile(name: String, fileName: String, mimeType: String, fileData: Data) {
        append("--\(boundary)\r\n", to: &body)
        append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(fileName)\"\r\n", to: &body)
        append("Content-Type: \(mimeType)\r\n\r\n", to: &body)
        body.append(fileData)
        append("\r\n", to: &body)
    }

    private func append(_ string: String, to data: inout Data) {
        data.append(Data(string.utf8))
    }
}
