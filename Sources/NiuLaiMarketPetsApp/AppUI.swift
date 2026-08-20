import AppKit
import CoreGraphics
import ImageIO
import NiuLaiMarketPets
import SwiftUI

@MainActor
private enum SpriteImageCache {
    private static var images: [String: NSImage] = [:]

    static func image(pet: PetID, row: Int, frame: Int, size: CGSize) -> NSImage? {
        let safeRow = max(0, min(row, 10))
        let maxFrame = safeRow == 0 ? 6 : (safeRow == 3 || safeRow == 4 || safeRow == 7 || safeRow == 8 ? 6 : 8)
        let safeFrame = max(0, min(frame, maxFrame - 1))
        let key = "\(pet.rawValue)-\(safeRow)-\(safeFrame)-\(Int(size.width))x\(Int(size.height))"
        if let cached = images[key] { return cached }

        guard let url = Bundle.main.url(
            forResource: "spritesheet",
            withExtension: "webp",
            subdirectory: "Pets/\(pet.rawValue)"
        ) else { return nil }
        guard
            let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let atlas = CGImageSourceCreateImageAtIndex(source, 0, nil),
            let cell = atlas.cropping(to: CGRect(x: safeFrame * 192, y: safeRow * 208, width: 192, height: 208))
        else { return nil }

        let image = NSImage(cgImage: cell, size: size)
        images[key] = image
        return image
    }
}

private struct MotionFrame {
    let row: Int
    let frame: Int
    let verticalOffset: CGFloat
    let isStumbling: Bool
    let showsObstacle: Bool
}

enum FloatingLayout {
    static let baseWidth: CGFloat = 360
    static let baseHeight: CGFloat = 480
    // The sprite is centered inside the 320x340 hit frame. The visible feet
    // end at the sprite cell's lower edge, not at the hit frame's lower edge.
    static let petVisualHalfHeight: CGFloat = 273 / 2
    static let badgeGapMinimum: CGFloat = 16
    static let badgeGapMaximum: CGFloat = 24
    static let estimatedBadgeHeight: CGFloat = 28

    static func size(for percent: Double) -> CGSize {
        let scale = CGFloat(PetScaleRange.clamped(percent) / 100.0)
        // Extra margins keep bubbles, glow, tears, quote badge and the
        // transparent hit area inside the panel at the 160% maximum.
        return CGSize(
            width: max(baseWidth, 252 * scale + 180),
            height: max(baseHeight, 330 * scale + 230)
        )
    }

    static func quoteBadgeCenterY(
        stageHeight: CGFloat,
        petScalePercent: Double,
        motionOffset: CGFloat = 0,
        badgeHeight: CGFloat = estimatedBadgeHeight
    ) -> CGFloat {
        let scale = CGFloat(PetScaleRange.clamped(petScalePercent) / 100.0)
        let petFootY = stageHeight / 2 + (petVisualHalfHeight + motionOffset) * scale
        let gap = min(badgeGapMaximum, max(badgeGapMinimum, 18 * scale))
        return petFootY + gap + badgeHeight / 2
    }
}

struct ControllerView: View {
    @ObservedObject var model: ControllerModel
    let onToggleVisibility: () -> Void
    @State private var burstStartedAt: Date?

    private let spriteSize = CGSize(width: 252, height: 273)

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.12)) { timeline in
            let stageSize = FloatingLayout.size(for: model.petScalePercent)
            let motion = motionFrame(at: timeline.date)
            let bubbles = SpeechPlanner.bubbles(
                for: model.activePet,
                at: timeline.date,
                burstStartedAt: burstStartedAt,
                textScalePercent: model.speechTextScalePercent
            )
            ZStack {
                visualLayer(motion: motion, bubbles: bubbles, date: timeline.date)
                    .zIndex(1)

                if model.showMarketPill {
                    GeometryReader { proxy in
                        quoteBadge
                            .position(
                                x: proxy.size.width / 2,
                                y: FloatingLayout.quoteBadgeCenterY(
                                    stageHeight: proxy.size.height,
                                    petScalePercent: model.petScalePercent,
                                    motionOffset: motion.verticalOffset
                                )
                            )
                            .zIndex(3)
                    }
                }
            }
            .frame(width: stageSize.width, height: stageSize.height)
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(model.activePet.displayName)桌面宠物，目标\(model.target.name)，\(bubbles.map(\.text).joined(separator: "、"))")
            .help("右键打开形态和指数菜单，左键触发台词连击")
            .onChange(of: model.activePet) { _ in
                burstStartedAt = nil
            }
        }
        .frame(
            width: FloatingLayout.size(for: model.petScalePercent).width,
            height: FloatingLayout.size(for: model.petScalePercent).height
        )
    }

    private func visualLayer(motion: MotionFrame, bubbles: [SpeechBubble], date: Date) -> some View {
        let scale = CGFloat(model.petScalePercent / 100.0)
        return ZStack {
            ZStack {
                headGlow(isBurst: bubbles.contains(where: { $0.isBurst }))
                    .frame(width: 104, height: 104)
                    .offset(y: -126 + motion.verticalOffset * 0.35)

                petLayer(motion: motion)
                    .offset(y: motion.verticalOffset)
            }
            .scaleEffect(scale)

            ForEach(Array(bubbles.enumerated()), id: \.element.id) { index, bubble in
                speechBubble(bubble, date: date, scale: scale)
                    .zIndex(bubble.isBurst ? Double(index + 2) : 1)
            }
        }
    }

    private func petLayer(motion: MotionFrame) -> some View {
        ZStack {
            if let image = SpriteImageCache.image(pet: model.activePet, row: motion.row, frame: motion.frame, size: spriteSize) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: spriteSize.width, height: spriteSize.height)
            } else {
                Image(systemName: "pawprint.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(.secondary)
            }

            if model.activePet == .niulai && motion.showsObstacle {
                semiconductorMarker
                    .offset(x: 104, y: 108)
            }
        }
        .frame(width: 320, height: 340)
        .contentShape(Rectangle())
        .onTapGesture {
            model.playClickAudio(for: model.activePet)
            let now = Date()
            if let burstStartedAt,
               now.timeIntervalSince(burstStartedAt) < SpeechPlanner.burstDuration {
                return
            }
            burstStartedAt = now
        }
    }

    private func speechBubble(_ bubble: SpeechBubble, date: Date, scale: CGFloat) -> some View {
        let progress = bubble.progress(at: date)
        let fadeIn = min(1, progress / 0.12)
        let fadeOut = progress > 0.68 ? max(0, (1 - progress) / 0.32) : 1
        let opacity = fadeIn * fadeOut
        let drift = CGFloat(progress)
        let pulse = bubble.isBurst ? 1 + CGFloat(sin(progress * .pi)) * 0.08 : 1

        return Text(bubble.text)
            .font(.custom(bubble.fontName, size: CGFloat(bubble.fontSize)))
            .fontWeight(bubble.isBurst ? .semibold : .medium)
            .foregroundStyle(speechColor)
            .padding(.horizontal, bubble.isBurst ? 10 : 8)
            .padding(.vertical, bubble.isBurst ? 5 : 4)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.black.opacity(bubble.isBurst ? 0.20 : 0.13))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(speechColor.opacity(bubble.isBurst ? 0.62 : 0.36), lineWidth: 0.8)
            )
            .shadow(color: .black.opacity(0.42), radius: 1.5, x: 1, y: 1)
            .shadow(color: speechColor.opacity(bubble.isBurst ? 0.38 : 0.22), radius: bubble.isBurst ? 9 : 6)
            .scaleEffect(pulse)
            .rotationEffect(.degrees(bubble.rotationDegrees * (1 - progress * 0.35)))
            .offset(
                x: CGFloat(bubble.originX) * scale + CGFloat(bubble.driftX) * drift,
                y: CGFloat(bubble.originY) * scale + CGFloat(bubble.driftY) * drift
            )
            .opacity(opacity)
            .allowsHitTesting(false)
    }

    private var semiconductorMarker: some View {
        HStack(spacing: 0) {
            pinColumn
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.20, green: 0.19, blue: 0.48), Color(red: 0.08, green: 0.08, blue: 0.24)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color(red: 0.46, green: 0.42, blue: 0.90).opacity(0.92), lineWidth: 1.2)
                    }
                    .overlay(alignment: .bottom) {
                        NotchShape()
                            .fill(Color(red: 0.12, green: 0.10, blue: 0.32))
                            .frame(width: 12, height: 7)
                            .offset(y: 1)
                    }

                Path { path in
                    path.move(to: CGPoint(x: 10, y: 11))
                    path.addLine(to: CGPoint(x: 20, y: 11))
                    path.addLine(to: CGPoint(x: 24, y: 17))
                    path.addLine(to: CGPoint(x: 35, y: 17))
                }
                .stroke(Color.cyan.opacity(0.94), style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))

                Circle()
                    .fill(Color.cyan)
                    .frame(width: 4, height: 4)
                    .offset(x: -14, y: -4)
                Circle()
                    .fill(Color.cyan.opacity(0.9))
                    .frame(width: 4, height: 4)
                    .offset(x: 15, y: 4)
            }
            .frame(width: 42, height: 28)
            pinColumn
        }
        .frame(width: 56, height: 32)
        .rotationEffect(.degrees(-8))
        .shadow(color: .black.opacity(0.28), radius: 2, y: 1)
        .allowsHitTesting(false)
    }

    private var pinColumn: some View {
        VStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { _ in
                Capsule(style: .continuous)
                    .fill(Color(red: 0.56, green: 0.62, blue: 0.82))
                    .frame(width: 7, height: 3)
            }
        }
        .frame(width: 7, height: 24)
    }

    private var quoteBadge: some View {
        HStack(spacing: 6) {
            Text(model.target.name)
                .foregroundStyle(.primary.opacity(0.82))
            if let quote = model.quote, quote.lastPrice.isFinite, quote.percent.isFinite {
                Text(String(format: "%.2f", quote.lastPrice))
                    .foregroundStyle(marketColor.opacity(model.currentQuoteIsStale ? 0.55 : 0.82))
                Text(MarketRules.signedPercent(quote.percent))
                    .foregroundStyle(marketColor)
            } else {
                Text("--")
                    .foregroundStyle(.secondary)
                Text("--")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 12, weight: .medium, design: .rounded))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.ultraThinMaterial.opacity(0.72), in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.26), lineWidth: 0.6))
        .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
        .allowsHitTesting(false)
    }

    private func headGlow(isBurst: Bool) -> some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [marketColor.opacity(0.96), marketColor.opacity(0.38), .clear],
                    center: .center,
                    startRadius: 1,
                    endRadius: 50
                )
            )
            .blur(radius: 1.4)
            .shadow(color: marketColor.opacity(0.78), radius: 16)
            .scaleEffect(isBurst ? 1.08 : 1)
            .allowsHitTesting(false)
    }

    private var marketColor: Color {
        Color(hex: MarketTone.resolve(percent: model.quote?.percent, isStale: model.currentQuoteIsStale).colorHex)
    }

    private var speechColor: Color {
        switch model.activePet {
        case .niulai: return Color(red: 0.98, green: 0.72, blue: 0.24)
        case .baola: return Color(red: 1.0, green: 0.82, blue: 0.25)
        case .muamua: return Color(red: 0.98, green: 0.58, blue: 0.26)
        }
    }

    private func motionFrame(at date: Date) -> MotionFrame {
        let time = date.timeIntervalSinceReferenceDate / 1.35
        switch model.activePet {
        case .niulai:
            let phase = time.truncatingRemainder(dividingBy: 3.1)
            if phase < 1.15 {
                let frame = Int((phase / 1.15) * 8).positiveModulo(8)
                return MotionFrame(row: 1, frame: frame, verticalOffset: 0, isStumbling: false, showsObstacle: true)
            }
            if phase < 2.25 {
                let frame = Int(((phase - 1.15) / 1.1) * 8).positiveModulo(8)
                return MotionFrame(row: 5, frame: frame, verticalOffset: 8, isStumbling: true, showsObstacle: true)
            }
            return MotionFrame(row: 0, frame: 0, verticalOffset: 0, isStumbling: false, showsObstacle: false)
        case .baola:
            let phase = time.truncatingRemainder(dividingBy: 1.28) / 1.28
            let frame = min(4, Int(phase * 5))
            let lift = -28 * sin(.pi * phase)
            return MotionFrame(row: 4, frame: frame, verticalOffset: lift, isStumbling: false, showsObstacle: false)
        case .muamua:
            let phase = time.truncatingRemainder(dividingBy: 1.85)
            let frame = Int((phase / 1.85) * 8).positiveModulo(8)
            return MotionFrame(row: 5, frame: frame, verticalOffset: 4, isStumbling: false, showsObstacle: false)
        }
    }
}

private extension Color {
    init(hex: String) {
        let value = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let number = UInt64(value, radix: 16) ?? 0x8A8F98
        self.init(
            red: Double((number >> 16) & 0xff) / 255,
            green: Double((number >> 8) & 0xff) / 255,
            blue: Double(number & 0xff) / 255
        )
    }
}

struct ScaleEditorView: View {
    @ObservedObject var model: ControllerModel
    let onDone: () -> Void
    @State private var draftPercent: Double

    init(model: ControllerModel, onDone: @escaping () -> Void) {
        self.model = model
        self.onDone = onDone
        _draftPercent = State(initialValue: model.petScalePercent)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("宠物大小")
                    .font(.headline)
                Spacer()
                Text("\(Int(draftPercent.rounded()))%")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(value: $draftPercent, in: PetScaleRange.minPercent...PetScaleRange.maxPercent, step: 1)
                .onChange(of: draftPercent) { value in
                    model.setPetScalePercent(value)
                }
            HStack {
                Text("\(Int(PetScaleRange.minPercent))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(PetScaleRange.maxPercent))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("完成", action: onDone)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 250)
    }
}

struct SpeechScaleEditorView: View {
    @ObservedObject var model: ControllerModel
    let onDone: () -> Void
    @State private var draftPercent: Double

    init(model: ControllerModel, onDone: @escaping () -> Void) {
        self.model = model
        self.onDone = onDone
        _draftPercent = State(initialValue: model.speechTextScalePercent)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("台词字号")
                    .font(.headline)
                Spacer()
                Text("\(Int(draftPercent.rounded()))%")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(value: $draftPercent, in: SpeechTextScaleRange.minPercent...SpeechTextScaleRange.maxPercent, step: 1)
                .onChange(of: draftPercent) { value in
                    model.setSpeechTextScalePercent(value)
                }
            HStack {
                Text("\(Int(SpeechTextScaleRange.minPercent))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(SpeechTextScaleRange.maxPercent))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("完成", action: onDone)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 250)
    }
}

private struct NotchShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private extension Int {
    func positiveModulo(_ divisor: Int) -> Int {
        let result = self % divisor
        return result >= 0 ? result : result + divisor
    }
}

@MainActor
final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init(frame: NSRect) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovableByWindowBackground = true
        ignoresMouseEvents = false
        hidesOnDeactivate = false
        animationBehavior = .utilityWindow
    }
}
