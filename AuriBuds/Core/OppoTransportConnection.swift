import Foundation

protocol OppoTransportConnection: AnyObject {
    var responseCount: Int { get }
    var isOpen: Bool { get }

    func write(_ command: OppoCommand) throws
    func write(_ bytes: [UInt8]) throws
    func waitForMatchingResponses(
        since baseline: Int,
        timeout: TimeInterval,
        matcher: OppoResponseMatcher
    ) -> [Data]
    func waitForResponses(since baseline: Int, timeout: TimeInterval) -> [Data]
    func close()
}
