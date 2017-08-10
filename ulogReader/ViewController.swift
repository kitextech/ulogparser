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

    func asValue<T>() -> T {
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

class ULogFormatParser: CustomStringConvertible {
    private var formats: [ULogFormat] = []

    func add(_ format: ULogFormat) {
        let expanded = expandedWithExisting(format)
        expandExisting(with: expanded)
        formats.append(expanded)
    }

    func property(at path: String) -> ULogProperty? {
        let pathComponents = path.components(separatedBy: ".")
        guard let typeName = pathComponents.first, let format = formats.first(where: { $0.typeName == typeName }) else {
            return nil
        }

        return format.property(at: Array(pathComponents.dropFirst()))
    }

    func size(at path: String) -> UInt? {
        let pathComponents = path.components(separatedBy: ".")
        guard let typeName = pathComponents.first, let format = formats.first(where: { $0.typeName == typeName }) else {
            return nil
        }

        return format.size(at: Array(pathComponents.dropFirst()))
    }

    func byteOffset(to path: String) -> UInt? {
        let pathComponents = path.components(separatedBy: ".")
        guard let typeName = pathComponents.first, let format = formats.first(where: { $0.typeName == typeName }) else {
            return nil
        }

        return format.byteOffset(to: Array(pathComponents.dropFirst()))
    }

    private func expandedWithExisting(_ format: ULogFormat) -> ULogFormat {
        var expandedFormat = format
        for existingFormat in formats {
            expandedFormat = expandedFormat.expanded(with: existingFormat)
        }

        return expandedFormat
    }

    private func expandExisting(with format: ULogFormat) {
        formats = formats.map { $0.expanded(with: format) }
    }

    var description: String {
        return formats.map { $0.description }.joined(separator: "\n\n")
    }
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

    func expanded(with customType: ULogFormat) -> ULogFormat {
        if customType.typeName == typeName {
            return customType
        }

        return ULogFormat(typeName, properties.map { ($0, $1.expanded(with: customType)) })
    }

    // specifies index,        index ok,     _                       is array     - OK   - return dearrayed type
    // does not specify index, _             -                       is not array - OK   - return self
    // does not specify index, _             path ends here,         is array     - OK   - return self
    // does not specify index, _             path does not end here, is array     - FAIL - return nil
    // specifies index,        index not ok, _                       is array     - FAIL - return nil
    // specifies index,        _             _                       is not array - FAIL - return nil

    func property(at path: [String]) -> ULogProperty? {
        let nameAndIndex = nameAndNumber(path[0])

        guard let property = properties.first(where: { $0.0 == nameAndIndex.name })?.1 else {
            return nil
        }

        let propertyToRecurse: ULogProperty?

        switch (nameAndIndex.number, path.count, property) {
        case let (i?, _, .builtins(type, n)) where i < n: propertyToRecurse = .builtin(type)
        case let (i?, _, .customs(type, n)) where i < n: propertyToRecurse = .custom(type)
        case (nil, _, .builtin), (nil, _, .custom): propertyToRecurse = property
        case (nil, 1, .builtins), (nil, 1, .customs): propertyToRecurse = property
        default: propertyToRecurse = nil
        }

        return propertyToRecurse?.property(at: Array(path.dropFirst()))
    }

    func size(at path: [String]) -> UInt? {
        let nameAndIndex = nameAndNumber(path[0])

        guard let property = properties.first(where: { $0.0 == nameAndIndex.name })?.1 else {
            return nil
        }

        return properties.reduce(0) { $0 + $1.1.byteCount }


        let propertyToRecurse: ULogProperty?

        switch (nameAndIndex.number, path.count, property) {
        case let (i?, _, .builtins(type, n)) where i < n: propertyToRecurse = .builtin(type)
        case let (i?, _, .customs(type, n)) where i < n: propertyToRecurse = .custom(type)
        case (nil, _, .builtin), (nil, _, .custom): propertyToRecurse = property
        case (nil, 1, .builtins), (nil, 1, .customs): propertyToRecurse = property
        default: propertyToRecurse = nil
        }

        return propertyToRecurse?.size(at: Array(path.dropFirst()))
    }

    func byteOffset(to path: [String]) -> UInt? {
        var offsetToProperty: UInt = 0
        for property in properties {
            let nameAndIndex = nameAndNumber(path[0])

            if property.0 == nameAndIndex.name {
                guard let offsetInsideProperty = property.1.byteOffset(to: Array(path.dropFirst())) else {
                    return nil
                }

                let offset: UInt?

                switch (nameAndIndex.number, path.count, property.1) {
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

    var description: String {
        return ([typeName] + indent(format)).joined(separator: "\n")
    }

    var format: [String] {
        return properties.flatMap { name, property in ["\(name): \(property.typeName)"] + indent(property.format) }
    }

    static func test() {
        let parser = ULogFormatParser()

        let vas = ULogFormat("vehicle_attitude_t:uint64_t timestamp;float rollspeed;float pitchspeed;my_special_t[4] special;super_special_t super;float yawspeed;float[4] q;uint8_t[4] _padding0;")
        let mss = ULogFormat("my_special_t:float yaw;float roll;super_special_t super;")
        let sss = ULogFormat("super_special_t:float x;float y;")

        parser.add(vas)
        parser.add(mss)
        parser.add(sss)

        func off(path: String) {
            print("\(path)")

            if let offset = parser.byteOffset(to: path) {
                print("    Offset >\(offset)")
            }
            else {
                print("    >Not found")
            }

//            if let prop = parser.property(at: path) {
//                print("    Info   >\(prop)")
//            }
//            else {
//                print("    >Not found")
//            }
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
        off(path: "vehicle_attitude_t.q[3]")
        off(path: "vehicle_attitude_t.special[2]")
        off(path: "vehicle_attitude_t.special[2].yaw")
        off(path: "vehicle_attitude_t.special[2].roll")

        print()
        print("Case 2: does not specify index, _             -                       is not array ")
        off(path: "my_special_t.super.x")
        off(path: "my_special_t.yaw")
        off(path: "my_special_t.super")

        print()
        print("Case 3: does not specify index, _             path ends here,         is array ")
        off(path: "vehicle_attitude_t.special")
        off(path: "vehicle_attitude_t.q")

        print()
        print("Case 4: does not specify index, _             path does not end here ")
        off(path: "vehicle_attitude_t.special.super.x")
        off(path: "vehicle_attitude_t.q.wrong")

        print()
        print("Case 5: specifies index,        index not ok, _                       is array ")
        off(path: "vehicle_attitude_t.q[4]")
        off(path: "vehicle_attitude_t.special[8]")
        off(path: "vehicle_attitude_t.special[8].yaw")

        print()
        print("Case 6: specifies index,        _             _                       is not array ")
        off(path: "my_special_t.yaw[1]")
        off(path: "my_special_t.yaw[1].x")
        off(path: "my_special_t.super[1]")
        off(path: "my_special_t.super[1].x")


//        off(path: "vehicle_attitude_t.special[2]")
//        off(path: "vehicle_attitude_t.special[2]")
//        off(path: "vehicle_attitude_t.special[2]")
//        off(path: "vehicle_attitude_t.special[2]")
//
//        off(path: "vehicle_attitude_t.special")
//        off(path: "vehicle_attitude_t.special[2]")
//        off(path: "vehicle_attitude_t.special[2].yaw")
//        off(path: "vehicle_attitude_t.special[2].super")
//        off(path: "vehicle_attitude_t.special[2].super.x")
//        off(path: "vehicle_attitude_t.special[3].super.x")
//        off(path: "vehicle_attitude_t.special[5]")
//        off(path: "vehicle_attitude_t.special[5].super.x")
//        off(path: "vehicle_attitude_t.special.super.x")
//
//        off(path: "vehicle_attitude_t.q")
//        off(path: "vehicle_attitude_t.q[0]")
//        off(path: "vehicle_attitude_t.q[1]")
//        off(path: "vehicle_attitude_t.q[2]")
//        off(path: "vehicle_attitude_t.q[3]")
//        off(path: "vehicle_attitude_t.q[4]")
//
//        off(path: "my_special_t.yaw")
//        off(path: "my_special_t.super")
//        off(path: "my_special_t.super.x")
//        off(path: "my_special_t.super.y")
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

    init(_ formatString: String) {
        let components = nameAndNumber(formatString)
        if let arraySize = components.number {
            if let builtin = ULogPrimitive(rawValue: components.name) {
                self = .builtins(builtin, arraySize)
            }
            else {
                self = .customs(.init(components.name, []), arraySize)
            }
        }
        else {
            if let builtin = ULogPrimitive(rawValue: components.name) {
                self = .builtin(builtin)
            }
            else {
                self = .custom(.init(components.name, []))
            }
        }
    }

    func expanded(with customType: ULogFormat) -> ULogProperty {
        switch self {
        case .custom(let format): return .custom(format.expanded(with: customType))
        case .customs(let format, let n): return .customs(format.expanded(with: customType), n)
        default: return self
        }
    }

    func property(at path: [String]) -> ULogProperty? {
        switch (path.count, self) {
        case (0, _): return self
        case (_, .customs(let format, _)), (_, .custom(let format)): return format.property(at: path)
        default: return nil
        }
    }

    func size(at path: [String]) -> UInt? {
        fatalError()
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

    var typeName: String {
        switch self {
        case .builtin(let builtin): return builtin.typeName
        case .custom(let format): return format.typeName
        case .builtins(let builtin, let n): return builtin.typeName + "[\(n)]"
        case .customs(let format, let n): return format.typeName + "[\(n)]"
        }
    }

    var format: [String] {
        switch self {
        case .builtin, .builtins: return []
        case .custom(let format), .customs(let format, _): return format.format
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

    var typeName: String {
        return rawValue
    }

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
}

enum ULogValue {
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
    case char(Character)

    init(type: ULogPrimitive, data: Data) {
        print("Type name :\(type.typeName)")
        switch type {
        case .int8: self = .int8(data.asValue())
        case .uint8: self = .uint8(data.asValue())
        case .int16: self = .int16(data.asValue())
        case .uint16: self = .uint16(data.asValue())
        case .int32: self = .int32(data.asValue())
        case .uint32: self = .uint32(data.asValue())
        case .int64: self = .int64(data.asValue())
        case .uint64: self = .uint64(data.asValue())
        case .float: self = .float(data.asValue())
        case .double: self = .double(data.asValue())
        case .bool: self = .bool(data.asValue())
        case .char: self = .char(data.asValue())
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
        case .char: return "char_t"
        }
    }
}


private func indent(_ list: [String]) -> [String] {
    return list.map { "    " + $0 }
}

//class ViewController: NSViewController {
//    override func viewDidLoad() {
//        super.viewDidLoad()
//
//        let pos = ULogFormat("vehicle_position_t", ["x" : .builtin(.float), "y" : .builtin(.float), "z" : .builtin(.float)])
//        let loc = ULogFormat("vehicle_location_t", ["timestamp" : .builtin(.double), "position" : .custom(pos)])
//
//        print(pos)
//        print("---")
//        print(loc)
//
//    }
//}

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
        return "MessageHeader(type: \(type), size \(size))"
    }
    
    init?(ptr: UnsafeRawPointer) {
        size = ptr.assumingMemoryBound(to: UInt16.self).pointee // size = ptr.load(as: UInt16.self) works the first time, but not the second !

        guard let mt = MessageType(rawValue: Character(UnicodeScalar(ptr.load(fromByteOffset: 2, as: UInt8.self)))) else {
                print(Character(UnicodeScalar(ptr.load(fromByteOffset: 2, as: UInt8.self))))
                return nil
        }
        type = mt
    }
}

struct MessageInfo: CustomStringConvertible {
    let header: MessageHeader
    let keyLength: UInt8
    let key: String
//    let value: UlogValue

    let typeName: String // temp

    var description: String {
        return "MessageInfo(keyLength: \(keyLength), key \(key), typeName: \(typeName))"
    }

    init?(data: Data, header: MessageHeader) {
        self.header = header
        keyLength = data.asValue()
        let typeAndName = data.subdata(in: 1..<Int(1 + keyLength)).asString().components(separatedBy: " ")

//        let dataValue = data.subdata(in: 1 + Int(keyLength)..<Int(header.size))
//        value = UlogValue(type: UlogType(typeName: typeAndName[0])!, value: dataValue)!

        typeName = typeAndName[0]
        key = typeAndName[1]
    }
}

//struct MessageParameter {
//    let header: MessageHeader
//    let keyLength: UInt8
//    let key: String
//    let value: UlogValue
//    
//    init(data: Data, header: MessageHeader) {
//        self.header = header
//        keyLength = data.toValueType()
//        let typeAndName = data.subdata(in: 1..<(1+Int(keyLength))).toString()
//        let typeNName = typeAndName.components(separatedBy: " ")
//        
//        let dataValue = data.subdata(in: 1 + Int(keyLength)..<Int(header.size))
//        
//        value = UlogValue(type: UlogType(typeName: typeNName.first!)!, value: dataValue)!
//        
//        key = typeNName[1]
//    }
//}
//
//struct MessageFormat {
//    let header: MessageHeader
//    let format: String
//    
//    init?(data: Data, header: MessageHeader) {
//        self.header = header
//        format = data.subdata(in: 0..<Int(header.size) ).toString()
//    }
//    
//    var messageName: String {
//        return format.substring(to: format.range(of: ":")!.lowerBound)
//    }
//    
//    var formatsProcessed: [(String, UlogType)] {
//        return format
//            .substring(from: format.range(of: ":")!.upperBound)
//            .components(separatedBy: ";")
//            .filter { $0.characters.count > 0 }
//            .map { split(s: $0) }
//            .filter { $0.0 != "_padding0" }
//    }
//    
//    func split(s: String) -> (String, UlogType) {
//        let x = s.components(separatedBy: " ")
//        let typeString = x.first!
//        let variableName = x[1]
//        let ulogtype = UlogType(typeName: typeString)!
//        
//        return (variableName, ulogtype)
//    }
//}
//
//struct MessageAddLoggedMessage {
//    let header: MessageHeader
//    let multi_id: UInt8
//    let id: UInt16
//    let messageName: String
//    
//    init(data: Data, header: MessageHeader) {
//        self.header = header
//        multi_id = data[0]
//        id = data.advanced(by: 1).toValueType()
//        messageName = data.subdata(in: 3..<Int(header.size) ).toString()
//    }
//}

struct MessageData {
    let header: MessageHeader
    let id: UInt16
    let data: Data
    
    init(data: Data, header: MessageHeader) {
        self.header = header
        id = data.asValue()
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
        timestamp = data.advanced(by: 1).asValue()
        message = data.subdata(in: 7..<Int(header.size)).asString()
    }
}

struct MessageDropout {
    let header: MessageHeader
    let duration: UInt16
    
    init(data: Data, header: MessageHeader) {
        self.header = header
        duration = data.asValue()
    }
}

// HELPER structures

//struct Format {
//    let name: String
//    let lookup: Dictionary<String, Int>
//    let types: [UlogType]
//}

class ULog {
    
//    let data: Data
    
//    var infos = [MessageInfo]()
//    var messageFormats = [MessageFormat]()
//    var formats = [String : Format]()
//    var formatsByLoggedId = [Format]()
//    var parameters = [MessageParameter]()
//    var addLoggedMessages = [MessageAddLoggedMessage]()
//    
//    var data = [String : [[UlogValue]]]()

    init?(data: Data) {
        guard checkMagicHeader(data: data) else {
            print("Bad header magic")
            return nil
        }
        
        guard checkVersionHeader(data: data) else {
            print("Bad version")
            return nil
        }
        
        print(getLoggingStartMicros(data: data))
        
        readFileDefinitions(data: data.subdata(in: 16..<data.endIndex))
    }
    
    private func checkMagicHeader(data: Data) -> Bool {
        return Array(data[0..<7]) == [UInt8(ascii: "U"),
                                      UInt8(ascii: "L"),
                                      UInt8(ascii: "o"),
                                      UInt8(ascii: "g"),
                                      UInt8("01", radix: 16)!,
                                      UInt8("12", radix: 16)!,
                                      UInt8("35", radix: 16)!]
    }
    
    private func checkVersionHeader(data: Data) -> Bool {
        return data[7] == 0 || data[7] == 1
    }
    
    func getLoggingStartMicros(data: Data) -> UInt64 {
        // logging start in micro
        return data.subdata(in: 8..<16).withUnsafeBytes { $0.pointee }
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
//                case .format:
//                    guard let message = MessageFormat(data: data, header: messageHeader) else { return }
//                    messageFormats.append(message)
//                    
//                    let name = message.messageName
//                    
//                    var types = [UlogType]()
//                    var lookup = [String : Int]()
//                    
//                    message.formatsProcessed.enumerated().forEach { (offset, element) in
//                        lookup[element.0] = offset
//                        types.append(element.1)
//                    }

//                    let f = Format(name: name, lookup: lookup, types: types)
//                    formats[name] = f

//                    break
//                case .parameter:
//                    let message = MessageParameter(data: data, header: messageHeader)
//                    parameters.append(message)
//                case .addLoggedMessage:
//                    let message = MessageAddLoggedMessage(data: data, header: messageHeader)
//                    addLoggedMessages.append(message)
//                    
//                    formatsByLoggedId.insert(formats[message.messageName]!, at: Int(message.id))
//                    break
//                    
//                case .data:
//                    let message = MessageData(data: data, header: messageHeader)
//                    
//                    var index = 0
//                    let format = formatsByLoggedId[Int(message.id)]
//                    var content = [UlogValue]()
//                    
//                    for type in format.types {
//                        content.append( UlogValue(type: type, value: message.data.advanced(by: index))! )
//                        index += type.byteCount
//                    }
//                    
//                    if self.data[format.name] == nil {
//                        self.data[format.name] = [[UlogValue]]()
//                    }
//                    
//                    self.data[format.name]!.append(content)
//                    break
//                    
//                case .logging:
//                    let message = MessageLog(data: data, header: messageHeader)
//                    print(message.message)
//                    break
//                    
//                case .dropout:
//                    let message = MessageDropout(data: data, header: messageHeader)
//                    print("dropout \(message.duration) ms")
//                    break

                default:
                    print(messageHeader.type)
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
        
        guard let ulog = ULog(data: data) else {
            print("error")
            return
        }
        
        
        //        print("--------")
        //        infos.forEach { print($0) }
        //        print("--------")
        ////        messageFormats.forEach {
        //            print("-xxxxxxx-")
        //            print($0.messageName)
        //            print($0)
        //            print($0.formatsProcessed)
        //        }
        //        print("--------")
        //        parameters.forEach { print($0) }
        
        //        print("_-_-_-_-_-_-_")
        //
        //        print(formats)
        
        //        print("--------")
        //        addLoggedMessages.forEach { print($0) }
        
        //        print("_-_-_-_-_-_-_")
        //        
        //        print(formatsByLoggedId)
        //        
        
        // print format
        
//        print(sen)
//        name	String	"sensor_combined"
//        key	String	"timestamp"
//        key	String	"accelerometer_m_s2"
        
//        let messageName = "sensor_combined"
//        let variableKey = "accelerometer_m_s2"

//        let messageName = "vehicle_local_position"
//        let variableKey = "timestamp"
        
        
//        let messageName = "fw_turning"
//        let variableKey = "arc_radius"

//        let f = ulog.formats[messageName]!
//        let sensorCombinedData = ulog.data[messageName]!

//        let variableIndex = f.lookup[variableKey]!

//        let variableArray = sensorCombinedData.map { $0[variableIndex] }

//        print(variableArray)

        ULogFormat.test()
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
