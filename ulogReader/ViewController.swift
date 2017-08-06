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
    
    func toString() -> String {
        return String( self.map { Character(UnicodeScalar($0)) } )
    }
    
    func to<T>(type: T.Type) -> T {
        return withUnsafeBytes { pointer in return pointer.pointee }
    }
    
    func toValueType<T>() -> T {
        return withUnsafeBytes { pointer in return pointer.pointee }
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

// Ulog Datatypes

//            let regExp: NSRegularExpression = ""

//            if typeName.contains("[") {
//                if typeName.contains("char") {
//                    self = .string
//                }
//                else {
//                    let g = typeName.range(of: "[")
//                    let gg = g!.lowerBound
//                    let ggg = typeName.substring(to: gg)
//                    let type = UlogType(typeName: ggg)!
//
//                    //                    let type = UlogType(typeName: typeName.substring(to: typeName.range(of: "[")!.lowerBound))!
//
//                    let x = typeName.range(of: "[")!.upperBound
//                    let y = typeName.range(of: "]")!.lowerBound
//
//                    let count = Int(typeName.substring(with: x..<y))!
//
//                    self = .array(Array(repeatElement(type, count: count)))
//                }
//            }
//            else {
//                return nil
//            }
            //        }

protocol ULogType {}

struct UlogFormat: ULogType {
    let name: String
    let properties: [String : ULogType]
}

struct ULogList: ULogType {
    let n: Int
    let type: UlogPrimitive
}

enum UlogPrimitive: ULogType {
    case uint8, uint16, uint32, uint64, int8, int16, int32, int64, float, double, bool, char
    case uint8s(Int), uint16s(Int), uint32s(Int), uint64s(Int), int8s(Int), int16s(Int), int32s(Int), int64s(Int), floats(Int), doubles(Int), bools(Int), chars(Int)

    var count: Int {
        switch self {
        case uint8s(let n): return n
        }
    }

//    case uint8 = "uint8_t"
//    case uint16 = "uint16_t"
//    case uint32 = "uint32_t"
//    case uint64 = "uint64_t"
//    case int8 = "int8_t"
//    case int16 = "int16_t"
//    case int32 = "int32_t"
//    case int64 = "int64_t"
//    case float = "float_t"
//    case double = "double_t"
//    case bool = "bool_t"
//    case char = "char_t"
//
//    case uint8s = "uint8_t[]"
//    case uint16s = "uint16_t[]"
//    case uint32s = "uint32_t[]"
//    case uint64s = "uint64_t[]"
//    case int8s = "int8_t[]"
//    case int16s = "int16_t[]"
//    case int32s = "int32_t[]"
//    case int64s = "int64_t[]"
//    case floats = "float_t[]"
//    case doubles = "double_t[]"
//    case bools = "bool_t[]"
//    case chars = "char_t[]"

    init?(typeName: String) {

    }

//    private static let pairs: [UlogPrimitive : String] = [.uint8 : "uint8_t", .uint16 : "uint16_t", .uint32 : "uint32_t", .uint64 : "uint64_t", .int8 : "int8_t", .int16 : "int16_t", .int32 : "int32_t", .int64 : "int64_t", .float : "float_t", .double : "double_t", .bool : "bool_t", .char : "char_t", .uint8s : "uint8_t[<n>]", .uint16s : "uint16_t[<n>]", .uint32s : "uint32_t[<n>]", .uint64s : "uint64_t[<n>]", .int8s : "int8_t[<n>]", .int16s : "int16_t[<n>]", .int32s : "int32_t[<n>]", .int64s : "int64_t[<n>]", .floats : "float_t[<n>]", .doubles : "double_t[<n>]", .bools : "bool_t[<n>]", .chars : "char_t[<n>]"]

}

        //        print("TypeName:\(typeName)")
//        switch typeName {
//        case "int8_t": self = .int8
//        case "uint8_t": self = .uint8
//        case "int16_t": self = .int16
//        case "uint16_t": self = .uint16
//        case "int32_t": self = .int32
//        case "uint32_t": self = .uint32
//        case "int64_t": self = .int64
//        case "uint64_t": self = .uint64
//        case "float": self = .float
//        case "double": self = .double
//        case "bool": self = .bool
//        case "char": self = .char
//
//        default:
//
//        }
//    }

enum UlogValue {
    case uint8(UInt8)
    case int8(Int8)
    case uint16(UInt16)
    case int16(Int16)
    case uint32(UInt32)
    case int32(Int32)
    case uint64(UInt64)
    case int64(Int64)
    case float(Float)
    case double(Double)
    case bool(Bool)
    case char(Character)
    case custom(UlogFormat)

    case uint8s([UInt8])
    case int8s([Int8])
    case uint16s([UInt16])
    case int16s([Int16])
    case uint32s([UInt32])
    case int32s([Int32])
    case uint64s([UInt64])
    case int64s([Int64])
    case floats([Float])
    case doubles([Double])
    case bools([Bool])
    case chars(String)
    case customs([UlogFormat])
}

//    init?(typeName: String) {
//        print("TypeName:\(typeName)")
//        switch typeName {
//        case "int8_t": self = .int8
//        case "uint8_t": self = .uint8
//        case "int16_t": self = .int16
//        case "uint16_t": self = .uint16
//        case "int32_t": self = .int32
//        case "uint32_t": self = .uint32
//        case "int64_t": self = .int64
//        case "uint64_t": self = .uint64
//        case "float": self = .float
//        case "double": self = .double
//        case "bool": self = .bool
//        case "char": self = .char
//
//        default:
//
//        }
//    }


    //
    // Messages
//

struct MessageHeader: CustomStringConvertible {
    let size: UInt16
    let type: MessageType
    
    var description: String {
        return "type: \(type), size \(size)"
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

struct MessageInfo {
    let header: MessageHeader
    let keyLength: UInt8
    let key: String
    let value: UlogValue
    
    init?(data: Data, header: MessageHeader) {
        self.header = header
        keyLength = data.toValueType()
        let typeAndName = data.subdata(in: 1..<(1+Int(keyLength))).toString()
        let typeNName = typeAndName.components(separatedBy: " ")
        
        let dataValue = data.subdata(in: 1+Int(keyLength)..<Int(header.size))
        
        value = UlogValue(type: UlogType(typeName: typeNName.first!)!, value: dataValue)!
        
        key = typeNName[1]
    }
}

struct MessageParameter {
    let header: MessageHeader
    let keyLength: UInt8
    let key: String
    let value: UlogValue
    
    init(data: Data, header: MessageHeader) {
        self.header = header
        keyLength = data.toValueType()
        let typeAndName = data.subdata(in: 1..<(1+Int(keyLength))).toString()
        let typeNName = typeAndName.components(separatedBy: " ")
        
        let dataValue = data.subdata(in: 1 + Int(keyLength)..<Int(header.size))
        
        value = UlogValue(type: UlogType(typeName: typeNName.first!)!, value: dataValue)!
        
        key = typeNName[1]
    }
}

struct MessageFormat {
    let header: MessageHeader
    let format: String
    
    init?(data: Data, header: MessageHeader) {
        self.header = header
        format = data.subdata(in: 0..<Int(header.size) ).toString()
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
        id = data.advanced(by: 1).toValueType()
        messageName = data.subdata(in: 3..<Int(header.size) ).toString()
    }
}

struct MessageData {
    let header: MessageHeader
    let id: UInt16
    let data: Data
    
    init(data: Data, header: MessageHeader) {
        self.header = header
        id = data.toValueType()
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
        timestamp = data.advanced(by: 1).toValueType()
        message = data.subdata(in: 7..<Int(header.size) ).toString()
    }
}

struct MessageDropout {
    let header: MessageHeader
    let duration: UInt16
    
    init(data: Data, header: MessageHeader) {
        self.header = header
        duration = data.toValueType()
    }
}

// HELPER structures

struct Format {
    let name: String
    let lookup: Dictionary<String, Int>
    let types: [UlogType]
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
        if !checkMagicHeader(data: data) {
            print("bad header magic")
            return nil
        }
        
        if !checkVersionHeader(data: data) {
            print("bad version")
            return nil
        }
        
        print(getLoggingStartMicros(data: data))
        
        readFileDefinitions(data: data.subdata(in: 16..<data.endIndex))
    }
    
    func checkMagicHeader(data: Data) -> Bool {
        
        let magic = Data(bytes: [UInt8](
            [UInt8(ascii: "U"),
             UInt8(ascii: "L"),
             UInt8(ascii: "o"),
             UInt8(ascii: "g"),
             UInt8("01", radix: 16)!,
             UInt8("12", radix: 16)!,
             UInt8("35", radix: 16)!]))
        return data.subdata(in: Range(uncheckedBounds: (lower: 0, upper: 7))) == magic
    }
    
    func checkVersionHeader(data: Data) -> Bool {
        return data[7] == UInt8(0) || data[7] == UInt8(1)
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
                
                guard let messageHeader = MessageHeader(ptr: ptr ) else {
                    return // complete when the header is nil
                }
                ptr += 3
                
                if (ptr-initialPointer + Int(messageHeader.size) > numberOfBytes) { return }
                let data = Data(bytes: ptr, count: Int(messageHeader.size))
                
                
                switch messageHeader.type {
                case .Info:
                    guard let message = MessageInfo(data: data, header: messageHeader) else { return }
                    infos.append(message)
                    break
                case .Format:
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
                case .Parameter:
                    let message = MessageParameter(data: data, header: messageHeader)
                    parameters.append(message)
                case .AddLoggedMessage:
                    let message = MessageAddLoggedMessage(data: data, header: messageHeader)
                    addLoggedMessages.append(message)
                    
                    formatsByLoggedId.insert(formats[message.messageName]!, at: Int(message.id))
                    break
                    
                case .Data:
                    let message = MessageData(data: data, header: messageHeader)
                    
                    var index = 0
                    let format = formatsByLoggedId[Int(message.id)]
                    var content = [UlogValue]()
                    
                    for type in format.types {
                        content.append( UlogValue(type: type, value: message.data.advanced(by: index))! )
                        index += type.byteCount
                    }
                    
                    if self.data[format.name] == nil {
                        self.data[format.name] = [[UlogValue]]()
                    }
                    
                    self.data[format.name]!.append(content)
                    break
                    
                case .Logging:
                    let message = MessageLog(data: data, header: messageHeader)
                    print(message.message)
                    break
                    
                case .Dropout:
                    let message = MessageDropout(data: data, header: messageHeader)
                    print("dropout \(message.duration) ms")
                    break
                    
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
        
        
        let messageName = "fw_turning"
        let variableKey = "arc_radius"
        
        let f = ulog.formats[messageName]!
        let sensorCombinedData = ulog.data[messageName]!
        
        let variableIndex = f.lookup[variableKey]!
        
        let variableArray = sensorCombinedData.map { $0[variableIndex] }
        
        print(variableArray)
    }
}



