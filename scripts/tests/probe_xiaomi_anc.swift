import Foundation

@main
struct XiaomiANCProbeRunner {
    static func main() async {
        let target = CommandLine.arguments.dropFirst().first ?? "Redmi Buds 4"
        let protocolClient = XiaomiProtocol()
        protocolClient.onEvent = { event in
            print(event)
        }

        do {
            print("probe target: \(target)")
            let battery = try await protocolClient.connect(deviceName: target)
            print("battery left=\(battery.text(for: .left)) right=\(battery.text(for: .right)) case=\(battery.text(for: .batteryCase))")

            let originalMode = try await protocolClient.refreshANC(deviceName: target)
            print("anc current=\(originalMode.rawValue)")

            let modes: [ANCMode] = [.noiseCancellation, .transparency, .off]
            for mode in modes {
                print("--- test set anc \(mode.rawValue) ---")
                do {
                    try await protocolClient.setANC(mode, deviceName: target)
                    try await Task.sleep(nanoseconds: 500_000_000)
                    let readBack = try await protocolClient.refreshANC(deviceName: target)
                    let success = readBack == mode
                    print("set ack OK, readback=\(readBack.rawValue), match=\(success ? "PASS" : "MISMATCH")")
                } catch let error as XiaomiProtocolError {
                    if case .commandRejected(let name, let status) = error {
                        print("set REJECTED: \(name) status=0x\(String(format: "%02X", status))")
                    } else {
                        print("set FAILED: \(error.localizedDescription)")
                    }
                } catch {
                    print("set FAILED: \(error.localizedDescription)")
                }
            }

            print("--- restore anc \(originalMode.rawValue) ---")
            do {
                try await protocolClient.setANC(originalMode, deviceName: target)
                print("restore OK")
            } catch {
                print("restore FAILED: \(error.localizedDescription)")
            }

            exit(0)
        } catch {
            print("probe failed: \(error.localizedDescription)")
            exit(1)
        }
    }
}
