import Foundation

public struct SpeechCue: Equatable, Sendable {
    public let text: String
    public let isBurst: Bool
    public let burstProgress: Double

    public init(text: String, isBurst: Bool, burstProgress: Double = 0) {
        self.text = text
        self.isBurst = isBurst
        self.burstProgress = burstProgress
    }
}

public struct SpeechBubble: Identifiable, Equatable, Sendable {
    public let id: String
    public let text: String
    public let isBurst: Bool
    public let startedAt: Date
    public let duration: TimeInterval
    public let originX: Double
    public let originY: Double
    public let driftX: Double
    public let driftY: Double
    public let rotationDegrees: Double
    public let fontName: String
    public let fontSize: Double

    public init(
        id: String,
        text: String,
        isBurst: Bool,
        startedAt: Date,
        duration: TimeInterval,
        originX: Double,
        originY: Double,
        driftX: Double,
        driftY: Double,
        rotationDegrees: Double,
        fontName: String,
        fontSize: Double
    ) {
        self.id = id
        self.text = text
        self.isBurst = isBurst
        self.startedAt = startedAt
        self.duration = duration
        self.originX = originX
        self.originY = originY
        self.driftX = driftX
        self.driftY = driftY
        self.rotationDegrees = rotationDegrees
        self.fontName = fontName
        self.fontSize = fontSize
    }

    public func progress(at date: Date) -> Double {
        guard duration > 0 else { return 1 }
        return min(1, max(0, date.timeIntervalSince(startedAt) / duration))
    }

    public func isVisible(at date: Date) -> Bool {
        let elapsed = date.timeIntervalSince(startedAt)
        return elapsed >= 0 && elapsed < duration
    }
}

/// Pure timing and copy rules for the visual speech layer. Keeping this out
/// of SwiftUI makes intermittent speech and click bursts deterministic in
/// tests and prevents duplicate timer tasks after repeated clicks.
public enum SpeechPlanner {
    public static let defaultInterval: TimeInterval = 5.0
    public static let defaultVisibleDuration: TimeInterval = 2.2
    public static let burstStep: TimeInterval = 0.42
    public static let burstBubbleDuration: TimeInterval = 2.0
    public static let burstDuration: TimeInterval = burstStep * 2 + burstBubbleDuration

    public static func cue(for pet: PetID, at date: Date, burstStartedAt: Date?) -> SpeechCue? {
        if let burstStartedAt {
            let elapsed = date.timeIntervalSince(burstStartedAt)
            if let burst = burstCue(for: pet, elapsed: elapsed) { return burst }
        }
        return defaultCue(for: pet, at: date)
    }

    public static func defaultCue(for pet: PetID, at date: Date) -> SpeechCue? {
        let elapsed = positiveRemainder(date.timeIntervalSinceReferenceDate, defaultInterval)
        guard elapsed < defaultVisibleDuration else { return nil }
        let phrases = defaultPhrases(for: pet)
        let cycle = Int(floor(date.timeIntervalSinceReferenceDate / defaultInterval))
        let index = positiveModulo(cycle, phrases.count)
        return SpeechCue(text: phrases[index], isBurst: false)
    }

    public static func burstCue(for pet: PetID, elapsed: TimeInterval) -> SpeechCue? {
        guard elapsed >= 0, elapsed < burstDuration else { return nil }
        let phrases = burstPhrases(for: pet)
        let index = min(phrases.count - 1, max(0, Int(floor(elapsed / burstStep))))
        let progress = min(1, max(0, (elapsed - Double(index) * burstStep) / burstStep))
        return SpeechCue(text: phrases[index], isBurst: true, burstProgress: progress)
    }

    public static func bubbles(
        for pet: PetID,
        at date: Date,
        burstStartedAt: Date?,
        textScalePercent: Double = SpeechTextScaleRange.defaultPercent
    ) -> [SpeechBubble] {
        let textScale = SpeechTextScaleRange.clamped(textScalePercent) / 100.0
        if let burstStartedAt {
            let burstBubbles = makeBurstBubbles(for: pet, startedAt: burstStartedAt, at: date, textScale: textScale)
            if !burstBubbles.isEmpty { return burstBubbles }
        }
        return defaultBubbles(for: pet, at: date, textScale: textScale)
    }

    public static func defaultBubbles(for pet: PetID, at date: Date, textScale: Double = 1) -> [SpeechBubble] {
        let cycle = Int(floor(date.timeIntervalSinceReferenceDate / defaultInterval))
        let cycleStart = Date(timeIntervalSinceReferenceDate: Double(cycle) * defaultInterval)
        let phrases = defaultPhrases(for: pet)
        let index = positiveModulo(cycle, phrases.count)
        var bubbles = [makeBubble(
            id: "idle-\(pet.rawValue)-\(cycle)-0",
            text: phrases[index],
            pet: pet,
            index: cycle,
            startedAt: cycleStart,
            isBurst: false,
            fontSize: 25 * textScale
        )]

        // Every third idle line gets a quieter echo, giving the scene some
        // breathing variation without leaving text permanently on screen.
        if positiveModulo(cycle, 3) == 1 {
            let echoStart = cycleStart.addingTimeInterval(0.34)
            if date >= echoStart {
                bubbles.append(makeBubble(
                    id: "idle-\(pet.rawValue)-\(cycle)-echo",
                    text: "…",
                    pet: pet,
                    index: cycle + 7,
                    startedAt: echoStart,
                    isBurst: false,
                    fontSize: 19 * textScale
                ))
            }
        }
        return bubbles.filter { $0.isVisible(at: date) }
    }

    public static func burstBubbles(
        for pet: PetID,
        startedAt: Date,
        at date: Date,
        textScale: Double = 1
    ) -> [SpeechBubble] {
        makeBurstBubbles(for: pet, startedAt: startedAt, at: date, textScale: textScale)
    }

    public static func defaultPhrases(for pet: PetID) -> [String] {
        switch pet {
        case .niulai: return ["牛来", "牛来！", "冲呀"]
        case .baola: return ["豹拉", "起飞", "再冲一段"]
        case .muamua: return ["妈妈", "呜呜", "妈妈救我"]
        }
    }

    public static func burstPhrases(for pet: PetID) -> [String] {
        switch pet {
        case .niulai: return ["牛来速归", "牛来！", "冲冲冲"]
        case .baola: return ["豹拉 All in", "豹拉起飞", "再来一根"]
        case .muamua: return ["妈妈救我！", "妈——", "妈妈"]
        }
    }

    private static func makeBurstBubbles(
        for pet: PetID,
        startedAt: Date,
        at date: Date,
        textScale: Double
    ) -> [SpeechBubble] {
        let phrases = burstPhrases(for: pet)
        return phrases.enumerated().compactMap { index, phrase in
            let bubbleStart = startedAt.addingTimeInterval(Double(index) * burstStep)
            let bubble = makeBubble(
                id: "burst-\(pet.rawValue)-\(Int(startedAt.timeIntervalSinceReferenceDate * 10))-\(index)",
                text: phrase,
                pet: pet,
                index: index,
                startedAt: bubbleStart,
                isBurst: true,
                fontSize: (index == 0 ? 29 : 24) * textScale
            )
            return bubble.isVisible(at: date) ? bubble : nil
        }
    }

    private static func makeBubble(
        id: String,
        text: String,
        pet: PetID,
        index: Int,
        startedAt: Date,
        isBurst: Bool,
        fontSize: Double
    ) -> SpeechBubble {
        let styles = isBurst ? burstStyle(index: index) : style(for: pet, index: index)
        return SpeechBubble(
            id: id,
            text: text,
            isBurst: isBurst,
            startedAt: startedAt,
            duration: isBurst ? burstBubbleDuration : defaultVisibleDuration,
            originX: styles.originX,
            originY: styles.originY,
            driftX: styles.driftX,
            driftY: styles.driftY,
            rotationDegrees: styles.rotationDegrees,
            fontName: styles.fontName,
            fontSize: fontSize
        )
    }

    private static func style(for pet: PetID, index: Int) -> (originX: Double, originY: Double, driftX: Double, driftY: Double, rotationDegrees: Double, fontName: String) {
        let fonts = ["STKaiti", "Kaiti SC", "Songti SC", "Heiti SC"]
        let slots: [(Double, Double, Double, Double, Double)] = [
            (92, -118, 10, -34, -4),
            (-82, -98, -12, -28, 3),
            (76, -42, 14, -24, 5),
            (-64, -54, -10, -30, -5),
            (108, -76, 6, -38, 2),
        ]
        let petOffset: Int
        switch pet {
        case .niulai: petOffset = 0
        case .baola: petOffset = 1
        case .muamua: petOffset = 2
        }
        let slot = slots[positiveModulo(index + petOffset, slots.count)]
        return (slot.0, slot.1, slot.2, slot.3, slot.4, fonts[positiveModulo(index + petOffset, fonts.count)])
    }

    private static func burstStyle(index: Int) -> (originX: Double, originY: Double, driftX: Double, driftY: Double, rotationDegrees: Double, fontName: String) {
        let fonts = ["STKaiti", "Kaiti SC", "Songti SC"]
        // Keep the three click lines visually independent: upper-left,
        // upper-right, then a lower side cue. These slots leave room for the
        // pet and the quote badge even at 160%.
        let slots: [(Double, Double, Double, Double, Double)] = [
            (-112, -104, -12, -30, -4),
            (112, -104, 14, -32, 4),
            (0, -174, 0, -28, 0),
        ]
        let slot = slots[positiveModulo(index, slots.count)]
        return (slot.0, slot.1, slot.2, slot.3, slot.4, fonts[positiveModulo(index, fonts.count)])
    }

    private static func positiveRemainder(_ value: TimeInterval, _ divisor: TimeInterval) -> TimeInterval {
        let remainder = value.truncatingRemainder(dividingBy: divisor)
        return remainder >= 0 ? remainder : remainder + divisor
    }

    private static func positiveModulo(_ value: Int, _ divisor: Int) -> Int {
        let remainder = value % divisor
        return remainder >= 0 ? remainder : remainder + divisor
    }
}
