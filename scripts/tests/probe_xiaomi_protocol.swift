import Foundation

@main
struct XiaomiProtocolProbeRunner {
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
            exit(0)
        } catch {
            print("probe failed: \(error.localizedDescription)")
            exit(1)
        }
    }
}
