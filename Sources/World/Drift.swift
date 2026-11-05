import Foundation

/// Little things that drift by over the pool with the season (v1.2): petals
/// in spring, dandelion fluff in summer, leaves in autumn. Nothing in winter
/// or while it rains, storms or snows (the weather has the sky then).
public enum Drift {
    public static func item(for context: WorldContext) -> String? {
        switch context.weather {
        case .rain, .storm, .snow: return nil
        default: break
        }
        switch context.season {
        case .spring: return "spring"
        case .summer: return "summer"
        case .autumn: return "autumn"
        case .winter: return nil
        }
    }
}
