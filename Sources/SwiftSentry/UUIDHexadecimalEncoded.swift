//
//  UUIDHexadecimalEncoded.swift
//  
//
//  Created by Patrick Zippenfenig on 17.11.21.
//

import Foundation

@propertyWrapper
struct UUIDHexadecimalEncoded {
    let wrappedValue: UUID
}

extension UUIDHexadecimalEncoded: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        guard let id = UUID(fromHexadecimalEncodedString: try container.decode(String.self)) else {
            throw DecodingError.typeMismatch(UUIDHexadecimalEncoded.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected UUID in hexdeciaml format"))
        }
        self.wrappedValue = id
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(self.wrappedValue.hexdecimalEncoded)
    }
}

extension UUID {
    /// Hexadecimal encoded 32-characters encoded uuid without dashes. E.g. `ecce513737d441b78b66c84ace35a281`
    var hexdecimalEncoded: String {
        uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }
    
    init?(fromHexadecimalEncodedString string: String) {
        fatalError()
    }
}
