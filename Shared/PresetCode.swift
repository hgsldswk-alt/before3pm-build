import Foundation

struct PresetCode: Codable, Equatable {
    static let maxBytes = 512
    static let prefix = "BG1:"
    var v = 1
    var prepMin: Int
    var travelMin: Int
    var taskID: String?

    var isValid: Bool {
        v == 1 && TimePlan.validMinutes(prepMin) && TimePlan.validMinutes(travelMin)
            && (taskID.map { id in TaskPreset.builtIns.contains { $0.id == id } } ?? true)
    }

    func encode() throws -> String {
        guard isValid else { throw CodeError.invalid }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let body = try encoder.encode(self).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let code = Self.prefix + body
        guard code.utf8.count <= Self.maxBytes else { throw CodeError.invalid }
        return code
    }

    static func decode(_ input: String) throws -> Self {
        guard input.utf8.count <= maxBytes else { throw CodeError.invalid }
        let code = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard code.hasPrefix(prefix) else { throw CodeError.invalid }
        let body = code.dropFirst(prefix.count)
        let alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
        guard !body.isEmpty, body.utf8.count % 4 != 1, body.utf8.allSatisfy({ alphabet.utf8.contains($0) })
        else { throw CodeError.invalid }
        let padded = body.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
            + String(repeating: "=", count: (4 - body.utf8.count % 4) % 4)
        guard let data = Data(base64Encoded: padded),
              let fields = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(fields.keys).isSubset(of: ["v", "prepMin", "travelMin", "taskID"]) else {
            throw CodeError.invalid
        }
        let result = try JSONDecoder().decode(Self.self, from: data)
        guard result.isValid else { throw CodeError.invalid }
        return result
    }

    enum CodeError: Error { case invalid }
}
