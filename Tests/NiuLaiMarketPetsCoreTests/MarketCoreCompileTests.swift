import Foundation
@testable import NiuLaiMarketPets

/// SwiftPM's CommandLineTools-only toolchain on this Mac does not ship
/// XCTest.framework. The executable harness in NiuLaiMarketPetsTests runs the
/// assertions; this target keeps `swift test` as a real SwiftPM test build and
/// type-checks the same public test surface without importing unavailable SDK
/// modules. Xcode/CI can add XCTest execution without changing the model.
enum MarketCoreCompileTests {
    static let thresholds: [PetID?] = [
        MarketRules.bucket(for: -0.01),
        MarketRules.bucket(for: 0),
        MarketRules.bucket(for: 1.00),
        MarketRules.bucket(for: 1.01),
    ]
    static let tone = MarketTone.resolve(percent: -0.0001)
    static let formatted = MarketRules.signedPercent(-0.004)
    static let policy = NotificationPolicy()
    static let snapshot = MarketSnapshot(targetID: MarketTarget.sse.id)
    static let persisted = PersistedState(showMarketPill: false)
}
