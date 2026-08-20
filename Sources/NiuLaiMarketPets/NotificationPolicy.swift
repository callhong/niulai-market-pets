import Foundation

/// Decides whether a settled automatic pet transition is notification-worthy.
/// The state engine owns debounce/cooldown; this policy owns notification
/// semantics and suppresses repeated boundary events.
public struct NotificationPolicy: Sendable {
    private var lastNotifiedTransition: String?

    public init() {}

    public static func title(for pet: PetID) -> String {
        switch pet {
        case .muamua: return "妈妈——"
        case .baola: return "豹拉！"
        case .niulai: return "牛来了"
        }
    }

    public static func body(for pet: PetID, target: MarketTarget, quote: Quote?) -> String {
        "\(pet.displayName) · \(target.name) · \(MarketRules.price(quote?.lastPrice)) · \(MarketRules.signedPercent(quote?.percent))"
    }

    public mutating func reset() {
        lastNotifiedTransition = nil
    }

    public mutating func shouldNotify(
        previousPercent: Double?,
        currentPercent: Double,
        switchedTo: PetID,
        mode: ControlMode,
        isInitialSample: Bool,
        isTargetRotation: Bool,
        isStale: Bool
    ) -> Bool {
        guard mode == .auto,
              !isInitialSample,
              !isTargetRotation,
              !isStale,
              currentPercent.isFinite,
              let previousPercent,
              previousPercent.isFinite,
              let currentBucket = MarketRules.bucket(for: currentPercent),
              currentBucket == switchedTo,
              let previousBucket = MarketRules.bucket(for: previousPercent),
              previousBucket != currentBucket
        else { return false }

        let transition = "\(previousBucket.rawValue)->\(currentBucket.rawValue)"
        guard transition != lastNotifiedTransition else { return false }
        lastNotifiedTransition = transition
        return true
    }
}
