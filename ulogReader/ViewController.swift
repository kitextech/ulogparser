//
//  ViewController.swift
//  ulogReader
//
//  Created by Andreas Okholm on 28/07/2017.
//  Copyright © 2017 Andreas Okholm. All rights reserved.
//

import Cocoa

// ULog message types

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

class ViewController: NSViewController {
    override func viewDidLoad() {
        super.viewDidLoad()

//        let path = "/Users/aokholm/src/kitex/PX4/Firmware/build_posix_sitl_default_replay/tmp/rootfs/fs/microsd/log/2017-08-04/15_19_22_replayed.ulg"

        let path = "~/Dropbox/10. KITEX/PrototypeDesign/10_32_17.ulg"
        let location = NSString(string: path).expandingTildeInPath
        
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: location)) else {
            print("failed to load data")
            return
        }

        testParser(data: data)
        //        testUlog(data: data)
//                testInfo(data: data)
    }

    func testParser(data: Data) {
        guard let parser = ULogParser(data) else {
            return
        }

        func time(_ heading: String, closure: () -> ()) {
            print(heading + " ------------------------------------------")
            let before = Date()
            closure()
            print("That took \(Date().timeIntervalSince(before))")
        }

        print(parser.format(of: "vehicle_attitude")?.description ?? "--")

        time("q0 simple style") {
            let q0: [Float] = parser.read("vehicle_attitude", primitive: "q[0]")
            q0[0..<10].forEach { print($0) }
        }

        time("q simple style") {
            let q: [[Float]] = parser.read("vehicle_attitude", primitiveArray: "q")
            q[0..<10].forEach { print($0) }
        }

        time("q0 fancy style") {
            let qq0 = parser.read("vehicle_attitude") { $0.value("q[0]") as Float }
            qq0[0..<10].forEach { print($0) }
        }

        time("q fancy style A") {
            let qqA = parser.read("vehicle_attitude") { read in
                Quaternion(x: read.value("q[1]"), y: read.value("q[2]"), z: read.value("q[3]"), w: read.value("q[0]"))
            }
            qqA[0..<10].forEach { print($0) }
        }

        time("q fancy style B") {
            let qq = parser.read("vehicle_attitude", range: 0..<10) { read -> Quaternion in
                let qs: [Float] = read.values("q")
                return Quaternion(x: qs[1], y: qs[2], z: qs[3], w: read.index % 2 == 0 ? qs[0] : -1)
            }
            qq.forEach { print($0) }
        }
    }

    func testInfo(data: Data) {
        let parser = ULogParser(data)!

        let vas = ULogFormat("vehicle_attitude_t:uint64_t timestamp;float rollspeed;float pitchspeed;my_special_t[4] special;super_special_t super;float yawspeed;float[4] q;uint8_t[4] _padding0;")
        let mss = ULogFormat("my_special_t:float yaw;float roll;super_special_t super;")
        let sss = ULogFormat("super_special_t:float x;float y;")

        parser.debugAdd(vas)
        parser.debugAdd(mss)
        parser.debugAdd(sss)

        func off(type: String, path: String) {
            print("\(type): \(path)")

            if let property = parser.property(of: type, at: path) {
                print("    Size   > \(property.byteCount)")
                //                print("    Prop > \(property)")
            }
            else {
                print("    Prop   > Not found")
            }

            if let offset = parser.byteOffset(of: type, at: path) {
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

    func testUlog(data: Data) {
        guard let ulog = ULogOld(data: data) else {
            print("ulog error")
            return
        }

        let vehicleLocalPositions = ulog.data["vehicle_local_position"]!
        let VLPf = ulog.formats["vehicle_local_position"]!

        print("FORMAT---------------")
        print(VLPf)
        print("---------------")

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
