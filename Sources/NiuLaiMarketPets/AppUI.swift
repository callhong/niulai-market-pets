import AppKit
import Combine
import CoreGraphics
import Foundation
import ImageIO
import SwiftUI

struct ControllerView: View {
    @ObservedObject var model: ControllerModel
    let onHide: () -> Void

    private let accent = Color(red: 0.98, green: 0.42, blue: 0.12)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("上证指数").font(.headline)
                Text(MarketRules.signedPercent(model.quote?.percent)).font(.system(.headline, design: .rounded).weight(.semibold))
                    .foregroundStyle(model.quote?.percent ?? 0 < 0 ? .blue : .red)
                Spacer()
                Circle().fill(model.isOnline ? .green : .gray).frame(width: 8, height: 8)
                Text(model.session.rawValue).font(.caption).foregroundStyle(.secondary)
                Button(action: onHide) { Image(systemName: "minus") }
                    .buttonStyle(.plain)
                    .help("隐藏面板")
            }

            HStack(spacing: 6) {
                modeButton("自动", isSelected: model.mode == .auto) { model.selectAuto() }
                ForEach(PetID.allCases, id: \.self) { pet in
                    modeButton(pet.displayName, isSelected: model.mode == .manual && model.activePet == pet) {
                        model.selectManual(pet)
                    }
                }
            }

            HStack(spacing: 8) {
                ForEach(PetID.allCases, id: \.self) { pet in
                    VStack(spacing: 2) {
                        SpriteThumbnailView(pet: pet)
                            .frame(width: 42, height: 48)
                        Text(pet.displayName).font(.caption2)
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            HStack {
                Text(model.mode == .auto ? "自动：\(model.activePet.displayName) · \(model.activePet.shortSemantic)" : "已暂停自动切换")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if let last = model.lastRefreshAt {
                    Text(last, style: .time).font(.caption2).foregroundStyle(.secondary)
                }
            }
            if let error = model.lastError, !error.isEmpty {
                Text(error).font(.caption2).lineLimit(1).foregroundStyle(.orange)
            }
        }
        .padding(12)
        .frame(width: 320, height: 180)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(accent.opacity(0.32), lineWidth: 1))
    }

    @ViewBuilder
    private func modeButton(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.caption.weight(.medium)).frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(isSelected ? accent : Color.gray.opacity(0.42))
        .controlSize(.small)
    }
}

struct SpriteThumbnailView: View {
    let pet: PetID

    var body: some View {
        Group {
            if let image = thumbnailImage {
                Image(nsImage: image).resizable().scaledToFit()
            } else {
                Image(systemName: "pawprint.fill").resizable().scaledToFit().padding(9).foregroundStyle(.secondary)
            }
        }
        .accessibilityLabel(pet.displayName)
    }

    private var thumbnailImage: NSImage? {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/pets/\(pet.rawValue)/spritesheet.webp")
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let cell = image.cropping(to: CGRect(x: 0, y: 0, width: 192, height: 208)) ?? image
        return NSImage(cgImage: cell, size: NSSize(width: 48, height: 52))
    }
}

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
        hasShadow = true
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        animationBehavior = .utilityWindow
    }
}
