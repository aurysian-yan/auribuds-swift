import Foundation

@main
struct XiaomiBLEProbeRunner {
    static func main() async {
        let target = CommandLine.arguments.dropFirst().first ?? "Redmi Buds 4"
        let transport = XiaomiBLETransport()

        do {
            print("probe target: \(target)")
            let connection = try await transport.connect(deviceName: target, timeout: 12) { event in
                print(event)
            }
            let command = XiaomiCommands.getTargetInfo(sequence: 0x31)
            let baseline = connection.responseCount
            try connection.write(command.bytes)
            let deadline = Date().addingTimeInterval(command.timeout)
            var responses: [Data] = []
            while Date() < deadline {
                responses = connection.responsesSince(baseline)
                if responses.contains(where: { command.expectedResponse.matches($0) }) {
                    break
                }
                RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
            }

            print("responses: \(responses.map(\.hexString))")
            if let battery = responses.compactMap({ XiaomiFrameParser.decodeBattery(from: $0) }).first {
                print("battery left=\(battery.text(for: .left)) right=\(battery.text(for: .right)) case=\(battery.text(for: .batteryCase))")
                exit(0)
            }

            print("battery decode failed")
            exit(2)
        } catch {
            print("probe failed: \(error.localizedDescription)")
            exit(1)
        }
    }
}
