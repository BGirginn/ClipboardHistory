import Foundation
import Security

protocol KeychainSecurityClient {
    func copyMatching(_ query: [String: Any]) -> (status: OSStatus, data: Data?)
    func add(_ query: [String: Any]) -> OSStatus
    func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus
    func randomData(count: Int) -> (status: OSStatus, data: Data)
}
