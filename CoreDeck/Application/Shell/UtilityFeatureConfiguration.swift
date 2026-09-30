import Foundation

struct UtilityFeatureConfiguration: Codable, Equatable, Identifiable, Sendable {
    let id: UtilityFeatureID
    var placement: FeaturePlacement
    var clickAction: FeatureClickAction
}
