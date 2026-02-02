//
// Created by Mateus Polonini Cardoso on 01/02/26.
//
import Foundation
import CoreBluetooth

struct BLETransportConfig {
    let serviceUUID: CBUUID
    let writeCharUUID: CBUUID

    let chunkSize: Int
    let chunkDelayUs: useconds_t

    static let zebraDefault = BLETransportConfig(
        serviceUUID: CBUUID(string: "38EB4A80-C570-11E3-9507-0002A5D5C51B"),
        writeCharUUID: CBUUID(string: "38EB4A82-C570-11E3-9507-0002A5D5C51B"),
        chunkSize: 100,
        chunkDelayUs: 10_000
    )
}
