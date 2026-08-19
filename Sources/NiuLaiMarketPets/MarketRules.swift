import Foundation

public enum MarketRules {
    public static func bucket(for percent: Double) -> PetID? {
        guard percent.isFinite else { return nil }
        if percent < 0 { return .muamua }
        if percent <= 1 { return .niulai }
        return .baola
    }

    public static func signedPercent(_ percent: Double?) -> String {
        guard let percent, percent.isFinite else { return "--" }
        return String(format: "%+.2f%%", percent)
    }

    public static func session(for date: Date, calendar: Calendar = MarketRules.shanghaiCalendar) -> MarketSession {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        guard let hour = components.hour, let minute = components.minute else { return .closed }
        let minutes = hour * 60 + minute
        switch minutes {
        case 9 * 60 + 15 ..< 9 * 60 + 25: return .preOpen
        case 9 * 60 + 25 ..< 11 * 60 + 30: return .trading
        case 11 * 60 + 30 ..< 13 * 60: return .lunch
        case 13 * 60 ..< 15 * 60: return .trading
        default: return .closed
        }
    }

    public static var shanghaiCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }
}

public struct MarketStateEngine: Sendable {
    public private(set) var activePet: PetID
    public private(set) var candidatePet: PetID?
    public private(set) var candidateSince: Date?
    public private(set) var cooldownUntil: Date?
    public private(set) var hasValidSample: Bool

    public let debounceInterval: TimeInterval
    public let cooldownInterval: TimeInterval

    public init(
        activePet: PetID = .niulai,
        hasHistory: Bool = false,
        debounceInterval: TimeInterval = 20,
        cooldownInterval: TimeInterval = 120
    ) {
        self.activePet = activePet
        self.hasValidSample = hasHistory
        self.debounceInterval = debounceInterval
        self.cooldownInterval = cooldownInterval
    }

    public mutating func resetForManual(pet: PetID) {
        activePet = pet
        candidatePet = nil
        candidateSince = nil
        cooldownUntil = nil
        hasValidSample = true
    }

    public mutating func clearPendingCandidate() {
        candidatePet = nil
        candidateSince = nil
    }

    /// Returns the new pet only when an automatic switch should actually be performed.
    public mutating func accept(
        percent: Double,
        at date: Date,
        tradingAllowed: Bool,
        isStale: Bool
    ) -> PetID? {
        guard tradingAllowed, !isStale, let proposed = MarketRules.bucket(for: percent) else {
            clearPendingCandidate()
            return nil
        }
        if !hasValidSample {
            hasValidSample = true
            activePet = proposed
            clearPendingCandidate()
            cooldownUntil = date.addingTimeInterval(cooldownInterval)
            return proposed
        }
        if proposed == activePet {
            clearPendingCandidate()
            return nil
        }
        if let cooldownUntil, date < cooldownUntil {
            clearPendingCandidate()
            return nil
        }
        if candidatePet != proposed {
            candidatePet = proposed
            candidateSince = date
            return nil
        }
        guard let candidateSince, date.timeIntervalSince(candidateSince) >= debounceInterval else {
            return nil
        }
        activePet = proposed
        clearPendingCandidate()
        cooldownUntil = date.addingTimeInterval(cooldownInterval)
        return proposed
    }
}
