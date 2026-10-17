//
//  Array+RawRepresentable.swift
//  Browserino
//
//  Created by Aleksandr Strizhnev on 06.06.2024.
//

import Foundation

/// Decodes one element of a stored array without failing the others.
private struct Lenient<Element: Decodable>: Decodable {
    let value: Element?

    init(from decoder: Decoder) throws {
        value = try? Element(from: decoder)
    }
}

extension Array: @retroactive RawRepresentable where Element: Codable {
    /// One element this build can't read, from a newer build or a bad import,
    /// is skipped rather than failing the whole array. A failed array makes
    /// @AppStorage fall back to its empty default, and the next save would
    /// write that over every rule, browser or app the user had.
    public init?(rawValue: String) {
        guard let data = rawValue.data(using: .utf8),
              let result = try? JSONDecoder().decode([Lenient<Element>].self, from: data)
        else {
            return nil
        }
        self = result.compactMap(\.value)
    }

    public var rawValue: String {
        guard let data = try? JSONEncoder().encode(self),
              let result = String(data: data, encoding: .utf8)
        else {
            return "[]"
        }
        return result
    }
}

extension Dictionary: @retroactive RawRepresentable where Key == String, Value: Codable {
    public init?(rawValue: String) {
        guard let data = rawValue.data(using: .utf8),
              let result = try? JSONDecoder().decode(Self.self, from: data)
        else {
            return nil
        }
        self = result
    }

    public var rawValue: String {
        guard let data = try? JSONEncoder().encode(self),
              let result = String(data: data, encoding: .utf8)
        else {
            return "{}"
        }
        return result
    }
}

/// @AppStorage for code outside SwiftUI views, such as the link router.
/// AppStorage only promises to follow writes made through other AppStorage
/// properties while it lives in a view, and a link has to be routed by the
/// rules as Settings saved them a moment ago. This reads UserDefaults on
/// every access instead.
@propertyWrapper
struct StoredDefault<Value: RawRepresentable> where Value.RawValue == String {
    let key: String
    let defaultValue: Value

    init(wrappedValue: Value, _ key: String) {
        self.key = key
        self.defaultValue = wrappedValue
    }

    var wrappedValue: Value {
        get {
            UserDefaults.standard.string(forKey: key).flatMap(Value.init(rawValue:)) ?? defaultValue
        }
        nonmutating set {
            UserDefaults.standard.set(newValue.rawValue, forKey: key)
        }
    }
}

/// StoredDefault for a Bool, which UserDefaults stores natively.
@propertyWrapper
struct StoredFlag {
    let key: String
    let defaultValue: Bool

    init(wrappedValue: Bool, _ key: String) {
        self.key = key
        self.defaultValue = wrappedValue
    }

    var wrappedValue: Bool {
        get {
            UserDefaults.standard.object(forKey: key) as? Bool ?? defaultValue
        }
        nonmutating set {
            UserDefaults.standard.set(newValue, forKey: key)
        }
    }
}
