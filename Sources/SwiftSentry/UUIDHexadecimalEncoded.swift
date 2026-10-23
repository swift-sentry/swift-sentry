import Foundation

extension UUID {
    /// Hexadecimal encoded 32-characters encoded uuid without dashes. E.g. `ecce513737d441b78b66c84ace35a281`
    var hexadecimalEncoded: String {
        uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }

    init?(fromHexadecimalEncodedString string: String) {
        var a = string.uppercased()
        a.insert("-", at: a.index(a.startIndex, offsetBy: 20))
        a.insert("-", at: a.index(a.startIndex, offsetBy: 16))
        a.insert("-", at: a.index(a.startIndex, offsetBy: 12))
        a.insert("-", at: a.index(a.startIndex, offsetBy: 8))
        self.init(uuidString: a)
    }
}
