//
//  ViewController.swift
//  ulogReader
//
//  Created by Andreas Okholm on 28/07/2017.
//  Copyright © 2017 Andreas Okholm. All rights reserved.
//

import Cocoa

extension Data {
    func hexEncodedString() -> String {
        return map { String(format: "x%02hhx", $0) }.joined()
    }
    
    func asString() -> String {
        return String(map { Character(UnicodeScalar($0)) })
    }

    func value<T>() -> T {
        return withUnsafeBytes { $0.pointee }
    }
}

// ULog message types

enum MessageType: Character {
    case format = "F"
    case data = "D"
    case info = "I"
    case infoMultiple = "M"
    case parameter = "P"
    case addLoggedMessage = "A"
    case removeLoggedMessage = "R"
    case sync = "S"
    case dropout = "O"
    case logging = "L"
    case flagBits = "B"
}

struct ULogFormat: CustomStringConvertible {
    let typeName: String
    let properties: [(String, ULogProperty)]

    init(_ typeName: String, _ properties: [(String, ULogProperty)]) {
        self.typeName = typeName
        self.properties = properties
    }

    init(_ formatString: String) {
        let nameAndContents = formatString.components(separatedBy: ":")
        self.typeName = nameAndContents[0]

        self.properties = nameAndContents[1].components(separatedBy: ";").filter { $0 != "" }.map { string in
            let formatAndName = string.components(separatedBy: " ")
            return (formatAndName[1], ULogProperty(formatAndName[0]))
        }
    }

    // MARK: - Expanding

    func expanded(with customType: ULogFormat) -> ULogFormat {
        if customType.typeName == typeName {
            return customType
        }

        return ULogFormat(typeName, properties.map { ($0, $1.expanded(with: customType)) })
    }

    // MARK: - Information on properties

    func property(at path: [String]) -> ULogProperty? {
        let (name, index) = nameAndNumber(path[0])

        guard let property = properties.first(where: { $0.0 == name })?.1 else {
            return nil
        }

        let propertyToRecurse: ULogProperty?

        switch (index, path.count, property) {
        case let (i?, _, .builtins(type, n)) where i < n: propertyToRecurse = .builtin(type)
        case let (i?, _, .customs(type, n)) where i < n: propertyToRecurse = .custom(type)
        case (nil, _, .builtin), (nil, _, .custom): propertyToRecurse = property
        case (nil, 1, .builtins), (nil, 1, .customs): propertyToRecurse = property
        default: propertyToRecurse = nil
        }

        return propertyToRecurse?.property(at: Array(path.dropFirst()))
    }

    func byteOffset(to path: [String]) -> UInt? {
        var offsetToProperty: UInt = 0
        for property in properties {
            let (name, index) = nameAndNumber(path[0])

            if property.0 == name {
                guard let offsetInsideProperty = property.1.byteOffset(to: Array(path.dropFirst())) else {
                    return nil
                }

                let offset: UInt?

                switch (index, path.count, property.1) {
                case let (i?, _, .builtins(type, n)) where i < n: offset = offsetToProperty + i*type.byteCount + offsetInsideProperty
                case let (i?, _, .customs(type, n)) where i < n: offset = offsetToProperty + i*type.byteCount + offsetInsideProperty
                case (nil, _, .builtin), (nil, _, .custom): offset = offsetToProperty + offsetInsideProperty
                case (nil, 1, .builtins), (nil, 1, .customs): offset = offsetToProperty + offsetInsideProperty
                default: return nil
                }

                return offset

            }
            else {
                offsetToProperty += property.1.byteCount
            }
        }

        return nil
    }

    var byteCount: UInt {
        return properties.reduce(0) { $0 + $1.1.byteCount }
    }

    // MARK: - Printing

    var description: String {
        return ([typeName] + indent(formatDescription)).joined(separator: "\n")
    }

    var formatDescription: [String] {
        return properties.flatMap { name, property in ["\(name): \(property.typeName)"] + indent(property.formatDescription) }
    }

    // MARK: - Helper methods

    private func indent(_ list: [String]) -> [String] {
        return list.map { "    " + $0 }
    }
}

enum ULogProperty {
    case builtin(ULogPrimitive)
    case custom(ULogFormat)
    case builtins(ULogPrimitive, UInt)
    case customs(ULogFormat, UInt)

    var isArray: Bool {
        switch self {
        case .customs, .builtins: return true
        default: return false
        }
    }

    var isBuiltin: Bool {
        switch self {
        case .builtin, .builtins: return true
        default: return false
        }
    }

    init(_ formatString: String) {
        let (name, arraySize) = nameAndNumber(formatString)

        if let arraySize = arraySize {
            if let builtin = ULogPrimitive(rawValue: name) {
                self = .builtins(builtin, arraySize)
            }
            else {
                self = .customs(.init(name, []), arraySize)
            }
        }
        else {
            if let builtin = ULogPrimitive(rawValue: name) {
                self = .builtin(builtin)
            }
            else {
                self = .custom(.init(name, []))
            }
        }
    }

    // MARK: - Expanding

    func expanded(with customType: ULogFormat) -> ULogProperty {
        switch self {
        case .custom(let format): return .custom(format.expanded(with: customType))
        case .customs(let format, let n): return .customs(format.expanded(with: customType), n)
        default: return self
        }
    }

    // MARK: - Information on properties

    func property(at path: [String]) -> ULogProperty? {
        switch (path.count, self) {
        case (0, _): return self
        case (_, .customs(let format, _)), (_, .custom(let format)): return format.property(at: path)
        default: return nil
        }
    }

    func byteOffset(to path: [String]) -> UInt? {
        switch (path.count, self) {
        case (0, _): return 0
        case (_, .customs(let format, _)), (_, .custom(let format)): return format.byteOffset(to: path)
        default: return nil
        }
    }

    var byteCount: UInt {
        switch self {
        case .builtin(let primitiveType): return primitiveType.byteCount
        case .builtins(let primitiveType, let n): return n*primitiveType.byteCount
        case .custom(let customType): return customType.byteCount
        case .customs(let customType, let n): return n*customType.byteCount
        }
    }

    // MARK: - Printing

    var typeName: String {
        switch self {
        case .builtin(let builtin): return builtin.typeName
        case .custom(let format): return format.typeName
        case .builtins(let builtin, let n): return builtin.typeName + "[\(n)]"
        case .customs(let format, let n): return format.typeName + "[\(n)]"
        }
    }

    var formatDescription: [String] {
        switch self {
        case .builtin, .builtins: return []
        case .custom(let format), .customs(let format, _): return format.formatDescription
        }
    }
}

func nameAndNumber(_ formatString: String) -> (name: String, number: UInt?) {
    let parts = formatString.components(separatedBy: ["[", "]"])
    guard parts.count == 3, let count = UInt(parts[1]) else {
        return (parts[0], nil)
    }

    return (parts[0], count)
}

enum ULogPrimitive: String {
    case uint8 = "uint8_t"
    case uint16 = "uint16_t"
    case uint32 = "uint32_t"
    case uint64 = "uint64_t"
    case int8 = "int8_t"
    case int16 = "int16_t"
    case int32 = "int32_t"
    case int64 = "int64_t"
    case float = "float"
    case double = "double"
    case bool = "bool"
    case char = "char"

    // MARK: - Information

    var byteCount: UInt {
        switch self {
        case .uint8: return 1
        case .uint16: return 2
        case .uint32: return 4
        case .uint64: return 8
        case .int8: return 1
        case .int16: return 2
        case .int32: return 4
        case .int64: return 8
        case .float: return 4
        case .double: return 8
        case .bool: return 1
        case .char: return 1
        }
    }

    // MARK: - Printing

    var typeName: String {
        return rawValue
    }
}

enum UlogType {
    case uint8
    case uint16
    case uint32
    case uint64
    case int8
    case int16
    case int32
    case int64
    case float
    case double
    case bool
    case string
    case array([UlogType])

    init?(typeName: String) {
        let (name, count) = nameAndNumber(typeName)

        if let count = count {
            self = name == "char" ? .string : .array(Array(repeating: UlogType(typeName: name)!, count: Int(count)))
        }
        else {
            switch typeName {
            case "uint8_t": self = .uint8
            case "uint16_t": self = .uint16
            case "uint32_t": self = .uint32
            case "uint64_t": self = .uint64
            case "int8_t": self = .int8
            case "int16_t": self = .int16
            case "int32_t": self = .int32
            case "int64_t": self = .int64
            case "float": self = .float
            case "double": self = .double
            case "bool": self = .bool
            default: self = .bool
            }
        }
    }

    var byteCount: Int {
        switch self {
        case .int8: return 1
        case .uint8: return 1
        case .int16: return 2
        case .uint16: return 2
        case .int32: return 4
        case .uint32: return 4
        case .int64: return 8
        case .uint64: return 8
        case .float: return 4
        case .double: return 8
        case .bool: return 1
        case .string: return 0 // Should not be ussed
        case .array(let array): return array.reduce(0) { $0 + $1.byteCount } // Should not be ussed
        }
    }
}

enum UlogValue: CustomStringConvertible {
    case uint8(UInt8)
    case uint16(UInt16)
    case uint32(UInt32)
    case uint64(UInt64)
    case int8(Int8)
    case int16(Int16)
    case int32(Int32)
    case int64(Int64)
    case float(Float)
    case double(Double)
    case bool(Bool)
    case string(String)
    case array([UlogValue])

    init(type: UlogType, data: Data) {
//        print("Type name :\(type)")
        switch type {
        case .int8: self = .int8(data.value())
        case .uint8: self = .uint8(data.value())
        case .int16: self = .int16(data.value())
        case .uint16: self = .uint16(data.value())
        case .int32: self = .int32(data.value())
        case .uint32: self = .uint32(data.value())
        case .int64: self = .int64(data.value())
        case .uint64: self = .uint64(data.value())
        case .float: self = .float(data.value())
        case .double: self = .double(data.value())
        case .bool: self = .bool(data.value())
        case .string: self = .string(data.asString())
        case .array(let array):

            self = .array(array.enumerated().map { (offset, type) in
                return UlogValue(type: type, data: data.advanced(by: offset*type.byteCount))
                }
            )
        }
    }
    
    var typeName: String {
        switch self {
        case .uint8: return "uint8_t"
        case .uint16: return "uint16_t"
        case .uint32: return "uint32_t"
        case .uint64: return "uint64_t"
        case .int8: return "int8_t"
        case .int16: return "int16_t"
        case .int32: return "int32_t"
        case .int64: return "int64_t"
        case .float: return "float_t"
        case .double: return "double_t"
        case .bool: return "bool_t"
        case .string: return "char_t"
        case .array(let val): return val[0].description
        }
    }

    func getValue<T>() -> T {
        switch self {
        case .int8(let val): return val as! T
        case .uint8(let val): return val as! T
        case .int16(let val): return val as! T
        case .uint16(let val): return val as! T
        case .int32(let val): return val as! T
        case .uint32(let val): return val as! T
        case .int64(let val): return val as! T
        case .uint64(let val): return val as! T
        case .float(let val): return val as! T
        case .double(let val): return val as! T
        case .bool(let val): return val as! T
        case .string(let val): return val as! T
        case .array(let val): return val as! T
        }
    }

    var description: String {
        switch self {
        case .int8(let val): return String(val)
        case .uint8(let val): return String(val)
        case .int16(let val): return String(val)
        case .uint16(let val): return String(val)
        case .int32(let val): return String(val)
        case .uint32(let val): return String(val)
        case .int64(let val): return String(val)
        case .uint64(let val): return String(val)
        case .float(let val): return String(val)
        case .double(let val): return String(val)
        case .bool(let val): return String(val)
        case .string(let val): return val
        case .array(let val): return String(describing: val)
        }
    }
}

/*
 All the data
 HEADER:
 16 bytes - magic + timestamp
 DEFINITIONS:
 {
    3 bytes - header (type = format, size)
    n bytes - data
 }
 {
    3 bytes - header (type = info, size)

    n bytes - data
 }
 DATA:
 {
     3 bytes - header (type = addLoggedMessage, size)
     n bytes - data
 }
 {
     3 bytes - header (type = data, size)
     2 bytes - id
     n bytes - data
 }
 */

struct MessageHeader: CustomStringConvertible {
    let size: UInt16
    let type: MessageType
    
    var description: String {
        return "MessageHeader(size \(size), type: \(type))"
    }
    
    init?(ptr: UnsafeRawPointer) {
        size = ptr.assumingMemoryBound(to: UInt16.self).pointee // size = ptr.load(as: UInt16.self) works the first time, but not the second !

        guard let mt = MessageType(rawValue: ptr.load(fromByteOffset: 2, as: UInt8.self).character) else {
            print("Header error: \(Character(UnicodeScalar(ptr.load(fromByteOffset: 2, as: UInt8.self))))")
                return nil
        }
        type = mt
    }
}

extension UInt8 {
    var character: Character {
        return Character(UnicodeScalar(self))
    }
}

struct MessageInfo: CustomStringConvertible {
    let header: MessageHeader
    let keyLength: UInt8
    let key: String
    let value: UlogValue

    var description: String {
        return "MessageInfo(keyLength: \(keyLength), key \(key), typeName: \(value.typeName)):\nValue:\n\(value)"
    }

    init?(data: Data, header: MessageHeader) {
        self.header = header
        keyLength = data.value()
        let typeAndName = data.subdata(in: 1..<Int(1 + keyLength)).asString().components(separatedBy: " ")

        let dataValue = data.subdata(in: 1 + Int(keyLength)..<Int(header.size))
        value = UlogValue(type: UlogType(typeName: typeAndName[0])!, data: dataValue)

        key = typeAndName[1]
    }
}

struct MessageParameter {
    let header: MessageHeader
    let keyLength: UInt8
    let key: String
    let value: UlogValue
    
    init(data: Data, header: MessageHeader) {
        self.header = header
        keyLength = data.value()
        let typeAndName = data.subdata(in: 1..<(1+Int(keyLength))).asString()
        let typeNName = typeAndName.components(separatedBy: " ")
        
        let dataValue = data.subdata(in: 1 + Int(keyLength)..<Int(header.size))
        
        value = UlogValue(type: UlogType(typeName: typeNName.first!)!, data: dataValue)
        
        key = typeNName[1]
    }
}

struct MessageFormat {
    let header: MessageHeader
    let format: String
    
    init?(data: Data, header: MessageHeader) {
        self.header = header
        format = data.subdata(in: 0..<Int(header.size)).asString()
    }
    
    var messageName: String {
        return format.substring(to: format.range(of: ":")!.lowerBound)
    }
    
    var formatsProcessed: [(String, UlogType)] {
        return format
            .substring(from: format.range(of: ":")!.upperBound)
            .components(separatedBy: ";")
            .filter { $0.characters.count > 0 }
            .map { split(s: $0) }
            .filter { $0.0 != "_padding0" }
    }
    
    func split(s: String) -> (String, UlogType) {
        let x = s.components(separatedBy: " ")
        let typeString = x.first!
        let variableName = x[1]
        let ulogtype = UlogType(typeName: typeString)!
        
        return (variableName, ulogtype)
    }
}

struct MessageAddLoggedMessage {
    let header: MessageHeader
    let multi_id: UInt8
    let id: UInt16
    let messageName: String
    
    init(data: Data, header: MessageHeader) {
        self.header = header
        multi_id = data[0]
        id = data.advanced(by: 1).value()
        messageName = data.subdata(in: 3..<Int(header.size) ).asString()
    }
}

struct MessageData {
    let header: MessageHeader
    let id: UInt16
    let data: Data
    
    init(data: Data, header: MessageHeader) {
        self.header = header
        id = data.value()
        self.data = data.advanced(by: 2)
    }
}

struct MessageLog {
    let header: MessageHeader
    let level: UInt8
    let timestamp: UInt64
    let message: String
    
    init(data: Data, header: MessageHeader) {
        self.header = header
        level = data[0]
        timestamp = data.advanced(by: 1).value()
        message = data.subdata(in: 7..<Int(header.size)).asString()
    }
}

struct MessageDropout {
    let header: MessageHeader
    let duration: UInt16
    
    init(data: Data, header: MessageHeader) {
        self.header = header
        duration = data.value()
    }
}

// HELPER structures

struct Format {
    let name: String
    let lookup: Dictionary<String, Int>
    let types: [UlogType]
}

class ULogParser: CustomStringConvertible {
    private let data: Data

    private var formats: [String : ULogFormat] = [:]
    private var dataMessages: [String : [MessageData]] = [:]
    private var messageNames: [UInt16 : String] = [:]

    init?(_ data: Data) {
        self.data = data

        guard checkMagicHeader(data: data), checkVersionHeader(data: data) else {
            return nil
        }

        readFileDefinitions(data: data.subdata(in: 16..<data.endIndex))
    }

    func readFileDefinitions(data: Data) {
        var iteration = 0
        let iterationMax = 50000

        let startTime = Date()

        let numberOfBytes = data.count


        data.withUnsafeBytes { (u8Ptr: UnsafePointer<UInt8>) in
            var ptr = UnsafeMutableRawPointer(mutating: u8Ptr)
            let initialPointer = ptr

            while iteration < iterationMax {
                iteration += 1

                guard let messageHeader = MessageHeader(ptr: ptr) else {
                    break // complete when the header is nil
                }

//                print(messageHeader)
                ptr += 3

                if ptr - initialPointer + Int(messageHeader.size) > numberOfBytes { return }
                let data = Data(bytes: ptr, count: Int(messageHeader.size))

                switch messageHeader.type {
                case .info:
                    guard let message = MessageInfo(data: data, header: messageHeader) else { return }
                    //                    infos.append(message)

//                    print(message)
                case .format:
                    add(ULogFormat(data.subdata(in: 0..<Int(messageHeader.size)).asString()))
//                case .parameter:
//                    let message = MessageParameter(data: data, header: messageHeader)
//                    parameters.append(message)
                case .addLoggedMessage:
                    let message = MessageAddLoggedMessage(data: data, header: messageHeader)
                    messageNames[message.id] = message.messageName
                    dataMessages[message.messageName] = dataMessages[message.messageName] ?? []
//                    addLoggedMessages.append(message)
//                    formatsByLoggedId.insert(formats[message.messageName]!, at: Int(message.id))

                case .data:
                    if let messageName = messageNames[data.value() as UInt16] {
                        dataMessages[messageName]?.append(MessageData(data: data, header: messageHeader))
                    }

//                    var index = 0
//                    let format = formatsByLoggedId[Int(message.id)]
//                    var content = [UlogValue]()
//
//                    for type in format.types {
//                        content.append(UlogValue(type: type, data: message.data.advanced(by: index)))
//                        index += type.byteCount
//                    }
//
//                    if self.data[format.name] == nil {
//                        self.data[format.name] = [[UlogValue]]()
//                    }
//
//                    self.data[format.name]!.append(content)

//                case .logging:
//                    let message = MessageLog(data: data, header: messageHeader)
//                    print("logging \(message.message)")
//                    break
//
//                case .dropout:
//                    let message = MessageDropout(data: data, header: messageHeader)
//                    print("dropout \(message.duration) ms")
//                    break

                default:
                    break
                }

                ptr += Int(messageHeader.size)
            }
        }

        print("Complete: \(Date().timeIntervalSince(startTime))")

        print(dataMessages["vehicle_attitude"]?.count ?? -1)
        print(formats["vehicle_attitude"]?.description ?? "--")

        let q0 = extractPrimitives("vehicle_attitude:q") as [[Float]]
        print(q0[0..<10])


//        print(description)

    }

    func add(_ format: ULogFormat) {
        let expanded = expandedWithExisting(format)
        expandExisting(with: expanded)
        formats[format.typeName] = expanded
    }

    func extract<T>(_ keyPath: String, closure: () -> T ) -> [T]? {


        fatalError()
    }

    func extractPrimitives<T>(_ keyPath: String) -> [[T]] {
        guard let offsetInMessage = byteOffset(to: keyPath), let prop = property(at: keyPath), case let .builtins(prim, n) = prop else {
            return []
        }

        return dataMessages[keyPath.typeName]?.map { dataMessage in
            return (0..<n).map { i in dataMessage.data.advanced(by: Int(offsetInMessage + i*prim.byteCount)).value() }
        } ?? []
    }

    func extractPrimitive<T>(_ keyPath: String) -> [T] {
        guard let offsetInMessage = byteOffset(to: keyPath), let prop = property(at: keyPath), prop.isBuiltin, !prop.isArray else {
            return []
        }

        return dataMessages[keyPath.typeName]?.map { $0.data.advanced(by: Int(offsetInMessage)).value() } ?? []
    }

    func extract<T>(_ typeName: String, keyPath: String) -> [T]? {

//        guard let offsetsToMessages = messageOffsets[typeName],
//            let offsetInMessage = byteOffset(in: typeName, to: keyPath),
//            let prop = property(in: typeName, at: keyPath),
//            prop.isBuiltin else {
//                return nil
//        }
//
//        return offsetsToMessages
//            .map { Range(uncheckedBounds: (Int($0 + offsetInMessage), Int($0 + offsetInMessage + prop.byteCount))) }
//            .map { data.subdata(in: $0).value() as T }
        fatalError()
    }

    func property(at keyPath: String) -> ULogProperty? {
        return formats[keyPath.typeName]?.property(at: keyPath.path)
    }

    func byteOffset(to keyPath: String) -> UInt? {
        return formats[keyPath.typeName]?.byteOffset(to: keyPath.path)
    }

    // MARK: - Helper methods

    private func expandedWithExisting(_ format: ULogFormat) -> ULogFormat {
        var expandedFormat = format
        for existingFormat in formats.values {
            expandedFormat = expandedFormat.expanded(with: existingFormat)
        }

        return expandedFormat
    }

    private func expandExisting(with newFormat: ULogFormat) {
        for (key, format) in formats {
            formats[key] = format.expanded(with: newFormat)
        }
    }

    private func checkMagicHeader(data: Data) -> Bool {
        let ulog = "ULog".unicodeScalars.map(UInt8.init(ascii:))
        return Array(data[0..<7]) == ulog + ["01", "12", "35"].map { UInt8($0, radix: 16)! }
    }

    private func checkVersionHeader(data: Data) -> Bool {
        return data[7] == 0 || data[7] == 1
    }

    // MARK: - Printing

    var description: String {
        return formats.values.map { $0.description }.joined(separator: "\n\n")
    }
}

private extension String {
    var typeName: String {
        return components(separatedBy: ":").first!
    }

    var path: [String] {
        return components(separatedBy: ":")[1].components(separatedBy: ".")
    }
}

class ULog {
    
//    let data: Data
    
    var infos = [MessageInfo]()
    var messageFormats = [MessageFormat]()
    var formats = [String : Format]()
    var formatsByLoggedId = [Format]()
    var parameters = [MessageParameter]()
    var addLoggedMessages = [MessageAddLoggedMessage]()
    
    var data = [String : [[UlogValue]]]()

    init?(data: Data) {
        guard checkMagicHeader(data: data) else {
            return nil
        }

        guard checkVersionHeader(data: data) else {
            return nil
        }

        print(getLoggingStartMicros(data: data))
        
        readFileDefinitions(data: data.subdata(in: 16..<data.endIndex))
    }
    
    private func checkMagicHeader(data: Data) -> Bool {
        let ulog = "ULog".unicodeScalars.map(UInt8.init(ascii:))
        return Array(data[0..<7]) == ulog + ["01", "12", "35"].map { UInt8($0, radix: 16)! }
    }

    private func checkVersionHeader(data: Data) -> Bool {
        return data[7] == 0 || data[7] == 1
    }
    
    func getLoggingStartMicros(data: Data) -> UInt64 {
        // logging start in micro
        return data.subdata(in: 8..<16).value()
    }

    func readFileDefinitions(data: Data) {
        var iteration = 0
        let iterationMax = 50000
        
        let startTime = Date()
        
        let numberOfBytes = data.count

        data.withUnsafeBytes { (u8Ptr: UnsafePointer<UInt8>) in
            var ptr = UnsafeMutableRawPointer(mutating: u8Ptr)
            let initialPointer = ptr
            
            while iteration < iterationMax {
                iteration += 1
                let newTime = Date()
                
                if iteration % (iterationMax/100) == 0 {
                    print( "complete\(Int(100*iteration/iterationMax)) time: \(newTime.timeIntervalSince(startTime))" )
                }
                
                guard let messageHeader = MessageHeader(ptr: ptr) else {
                    return // complete when the header is nil
                }

                print(messageHeader)
                ptr += 3
                
                if ptr - initialPointer + Int(messageHeader.size) > numberOfBytes { return }
                let data = Data(bytes: ptr, count: Int(messageHeader.size))

                switch messageHeader.type {
                case .info:
                    guard let message = MessageInfo(data: data, header: messageHeader) else { return }
//                    infos.append(message)

                    print(message)
                    break
                case .format:
                    guard let message = MessageFormat(data: data, header: messageHeader) else { return }
                    messageFormats.append(message)
                    
                    let name = message.messageName
                    
                    var types = [UlogType]()
                    var lookup = [String : Int]()
                    
                    message.formatsProcessed.enumerated().forEach { (offset, element) in
                        lookup[element.0] = offset
                        types.append(element.1)
                    }

                    let f = Format(name: name, lookup: lookup, types: types)
                    formats[name] = f

                    break
                case .parameter:
                    let message = MessageParameter(data: data, header: messageHeader)
                    parameters.append(message)
                case .addLoggedMessage:
                    let message = MessageAddLoggedMessage(data: data, header: messageHeader)
                    addLoggedMessages.append(message)
                    
                    formatsByLoggedId.insert(formats[message.messageName]!, at: Int(message.id))
                    break
                    
                case .data:
                    let message = MessageData(data: data, header: messageHeader)
                    
                    var index = 0
                    let format = formatsByLoggedId[Int(message.id)]
                    var content = [UlogValue]()
                    
                    for type in format.types {
                        content.append(UlogValue(type: type, data: message.data.advanced(by: index)))
                        index += type.byteCount
                    }
                    
                    if self.data[format.name] == nil {
                        self.data[format.name] = [[UlogValue]]()
                    }
                    
                    self.data[format.name]!.append(content)
                    break
                    
                case .logging:
                    let message = MessageLog(data: data, header: messageHeader)
                    print("logging \(message.message)")
                    break
                    
                case .dropout:
                    let message = MessageDropout(data: data, header: messageHeader)
                    print("dropout \(message.duration) ms")
                    break

                default:
                    print("default, messageHeader.type \(messageHeader.type)")

                    return
                }
                
                ptr += Int(messageHeader.size)
            }
        }
    }
}

class ViewController: NSViewController {
    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
        
//        let path = "/Users/aokholm/src/kitex/PX4/Firmware/build_posix_sitl_default_replay/tmp/rootfs/fs/microsd/log/2017-08-04/15_19_22_replayed.ulg"

        let path = "~/Dropbox/10. KITEX/PrototypeDesign/10_32_17.ulg"
        
        let location = NSString(string: path).expandingTildeInPath
        
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: location)) else {
            print("failed to load data")
            return
        }

        testParser(data: data)

//        test(data: data)
    }

    func testParser(data: Data) {
        guard let parser = ULogParser(data) else {
            return
        }
    }

    func testUlog(data: Data) {
        guard let ulog = ULog(data: data) else {
            print("ulog error")
            return
        }

        let vehicleLocalPositions = ulog.data["vehicle_local_position"]!
        let VLPf = ulog.formats["vehicle_local_position"]!

        print("FORMAT---------------")
        print(VLPf)
        print("---------------")

        struct Vector {
            let x: Float
            let y: Float
            let z: Float
        }

        struct TimedLocation {
            let time: Double
            let pos: Vector
            let vel: Vector
        }

        func toTimedLocation(value: [UlogValue]) -> TimedLocation {
            let time = value[VLPf.lookup["timestamp"]!].getValue() as UInt64

            let x = value[VLPf.lookup["x"]!].getValue() as Float
            let y = value[VLPf.lookup["y"]!].getValue() as Float
            let z = value[VLPf.lookup["z"]!].getValue() as Float
            let vx = value[VLPf.lookup["vx"]!].getValue() as Float
            let vy = value[VLPf.lookup["vy"]!].getValue() as Float
            let vz = value[VLPf.lookup["vz"]!].getValue() as Float
            let pos = Vector(x: x, y: y, z: z)
            let vel = Vector(x: vx, y: vy, z: vz)

            return TimedLocation(time: Double(time)/1000000, pos: pos, vel: vel)
        }

        struct Quaternion {
            let x: Float
            let y: Float
            let z: Float
            let w: Float
        }

        struct TimedOrientation {
            let time: Double
            let orientation: Quaternion
        }

        let VAf = ulog.formats["vehicle_attitude"]!

        func toTimedOrientation(value: [UlogValue] ) -> TimedOrientation {

            let time = value[VAf.lookup["timestamp"]!].getValue() as UInt64
            let qarray = value[VAf.lookup["q"]!].getValue() as [UlogValue]

            let w = qarray[0].getValue() as Float
            let x = qarray[1].getValue() as Float
            let y = qarray[2].getValue() as Float
            let z = qarray[3].getValue() as Float

            return TimedOrientation(time: Double(time)/1000000, orientation: Quaternion(x: x, y: y, z: z, w: w))
        }

        let timedLocations = vehicleLocalPositions.map(toTimedLocation)
        let timedOrientations = ulog.data["vehicle_attitude"]!.map(toTimedOrientation)

        print()
        print("------")
        print()

        print(timedLocations[0].pos)
        print(timedLocations[0].vel)
        print(timedLocations[0].time)

        print()
        print("------")
        print()
        
        print(timedOrientations[0].orientation)
        
        print()
        print("------")
        print()
    }

    func test(data: Data) {
        let parser = ULogParser(data)!

        let vas = ULogFormat("vehicle_attitude_t:uint64_t timestamp;float rollspeed;float pitchspeed;my_special_t[4] special;super_special_t super;float yawspeed;float[4] q;uint8_t[4] _padding0;")
        let mss = ULogFormat("my_special_t:float yaw;float roll;super_special_t super;")
        let sss = ULogFormat("super_special_t:float x;float y;")

        parser.add(vas)
        parser.add(mss)
        parser.add(sss)

        func off(type: String, path: String) {
            let keyPath = "\(type):\(path)"
            print(keyPath)

            if let property = parser.property( at: keyPath) {
                print("    Size   > \(property.byteCount)")
//                print("    Prop > \(property)")
            }
            else {
                print("    Prop   > Not found")
            }

            if let offset = parser.byteOffset(to: keyPath) {
                print("    Offset > \(offset)")
            }
            else {
                print("    Offset > Not found")
            }

        }

        print(parser)

        // Case 1: specifies index,        index ok,     _                       is array     - OK   - return dearrayed type

        // Case 2: does not specify index, _             -                       is not array - OK   - return self

        // Case 3: does not specify index, _             path ends here,         is array     - OK   - return self

        // Case 4: does not specify index, _             path does not end here, is array     - FAIL - return nil

        // Case 5: specifies index,        index not ok, _                       is array     - FAIL - return nil

        // Case 6: specifies index,        _             _                       is not array - FAIL - return nil


        print()
        print("Case 1: specifies index,        index ok,     _                       is array ")
        off(type: "vehicle_attitude_t", path: "q[3]")
        off(type: "vehicle_attitude_t", path: "special[2]")
        off(type: "vehicle_attitude_t", path: "special[2].yaw")
        off(type: "vehicle_attitude_t", path: "special[2].roll")

        print()
        print("Case 2: does not specify index, _             -                       is not array ")
        off(type: "my_special_t", path: "super.x")
        off(type: "my_special_t", path: "yaw")
        off(type: "my_special_t", path: "super")

        print()
        print("Case 3: does not specify index, _             path ends here,         is array ")
        off(type: "vehicle_attitude_t", path: "special")
        off(type: "vehicle_attitude_t", path: "q")

        print()
        print("Case 4: does not specify index, _             path does not end here ")
        off(type: "vehicle_attitude_t", path: "special.super.x")
        off(type: "vehicle_attitude_t", path: "q.wrong")

        print()
        print("Case 5: specifies index,        index not ok, _                       is array ")
        off(type: "vehicle_attitude_t", path: "q[4]")
        off(type: "vehicle_attitude_t", path: "special[8]")
        off(type: "vehicle_attitude_t", path: "special[8].yaw")

        print()
        print("Case 6: specifies index,        _             _                       is not array ")
        off(type: "my_special_t", path: "yaw[1]")
        off(type: "my_special_t", path: "yaw[1].x")
        off(type: "my_special_t", path: "super[1]")
        off(type: "my_special_t", path: "super[1].x")


        off(type: "vehicle_attitude_t", path: "special[2]")
        off(type: "vehicle_attitude_t", path: "special[2]")
        off(type: "vehicle_attitude_t", path: "special[2]")
        off(type: "vehicle_attitude_t", path: "special[2]")

        off(type: "vehicle_attitude_t", path: "special")
        off(type: "vehicle_attitude_t", path: "special[2]")
        off(type: "vehicle_attitude_t", path: "special[2].yaw")
        off(type: "vehicle_attitude_t", path: "special[2].super")
        off(type: "vehicle_attitude_t", path: "special[2].super.x")
        off(type: "vehicle_attitude_t", path: "special[3].super.x")
        off(type: "vehicle_attitude_t", path: "special[5]")
        off(type: "vehicle_attitude_t", path: "special[5].super.x")
        off(type: "vehicle_attitude_t", path: "special.super.x")

        off(type: "vehicle_attitude_t", path: "q")
        off(type: "vehicle_attitude_t", path: "q[0]")
        off(type: "vehicle_attitude_t", path: "q[1]")
        off(type: "vehicle_attitude_t", path: "q[2]")
        off(type: "vehicle_attitude_t", path: "q[3]")
        off(type: "vehicle_attitude_t", path: "q[4]")

        off(type: "my_special_t", path: "yaw")
        off(type: "my_special_t", path: "super")
        off(type: "my_special_t", path: "super.x")
        off(type: "my_special_t", path: "super.y")
    }

}


// my_type_t
//     my_float: float_t[2]
//         0: float_t = 4.55
//         1: float_t = 3.41
//     my_pos: my_pos_type_t =
//         x: float_t = 3
//         y: float_t = 5
//     my_path: my_pos_type_t[2] =
//         0: my_pos_type_t
//             x: float_t = 3
//             y: float_t = 5
//         1: my_pos_type_t
//             x: float_t = 3
//             y: float_t = 5
//     time: double_t = 45

// my_type_t
//     my_float: float_t[2]
//     my_pos: my_pos_type_t
//         x: float_t
//         y: float_t
//     my_path: my_pos_type_t[2]
//         x: float_t
//         y: float_t
//     time: double_t = 45

// my_type_t = {
//     my_float: float_t[2] = [
//         0: 4.55
//         1: 3.41
//     ]
//
//     my_pos: my_pos_type_t = {
//         x: float_t = 3
//         y: float_t = 5
//     }
//
//     my_path: my_pos_type_t[2] = [
//         0: my_pos_type_t = {
//             x: float_t = 3
//             y: float_t = 5
//         }
//         1: my_pos_type_t = {
//             x: float_t = 3
//             y: float_t = 5
//         }
//     ]
//
//     time: double_t = 45
// }
