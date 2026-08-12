import Foundation

enum StorageOperation: Equatable, Sendable {
    case executeSQL(String)
    case prepareSQL(String)
    case storeAsset(String)
    case removeAsset(String)
}
