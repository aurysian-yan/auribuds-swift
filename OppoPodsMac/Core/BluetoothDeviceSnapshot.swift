import Foundation

struct BluetoothDeviceSnapshot: Equatable, Identifiable {
    let name: String
    let address: String
    let isConnected: Bool
    let timestamp: Date
    let majorDeviceClass: UInt32
    let minorDeviceClass: UInt32

    var id: String {
        if !address.isEmpty {
            return address
        }

        return name
    }

    var fallbackSystemName: String {
        switch majorDeviceClass {
        case 1:
            return "desktopcomputer"
        case 2:
            return "iphone"
        case 4:
            return audioSystemName
        case 5:
            return peripheralSystemName
        case 6:
            return "camera"
        case 7:
            return "applewatch"
        case 8:
            return "gamecontroller"
        case 9:
            return "cross.case"
        default:
            return "antenna.radiowaves.left.and.right"
        }
    }

    private var audioSystemName: String {
        switch minorDeviceClass {
        case 1, 2, 6:
            return "headphones"
        case 4, 5:
            return "speaker.wave.2"
        case 10:
            return "car"
        default:
            return "headphones"
        }
    }

    private var peripheralSystemName: String {
        switch minorDeviceClass {
        case 16:
            return "keyboard"
        case 32:
            return "computermouse"
        case 48:
            return "keyboard"
        default:
            return "keyboard"
        }
    }
}
