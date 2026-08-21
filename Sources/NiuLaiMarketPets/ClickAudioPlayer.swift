import AVFoundation
import Foundation

/// The audio files intentionally live outside the SwiftPM target and are
/// copied into the finished app bundle by build-app.sh. Keeping the mapping
/// here makes the click behavior testable without requiring an audio device.
public enum ClickAudioCatalog {
    public static let resourceNames: [PetID: [String]] = [
        .niulai: ["niulai"],
        .baola: ["baola"],
        .muamua: ["muamua-mama-long", "muamua-mama-rescue"],
    ]

    public static func names(for pet: PetID) -> [String] {
        resourceNames[pet] ?? []
    }

    public static func randomName(for pet: PetID) -> String? {
        names(for: pet).randomElement()
    }
}

@MainActor
public final class ClickAudioPlayer {
    /// All four cues use the same application-level gain. The WAV files are
    /// intentionally played at the same AVAudioPlayer volume on macOS.
    public static let normalizedVolume: Float = 1.0
    private let bundle: Bundle
    private var player: AVAudioPlayer?

    public init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    public func play(for pet: PetID) {
        guard let resourceName = ClickAudioCatalog.randomName(for: pet),
              let url = bundle.url(forResource: resourceName, withExtension: "wav", subdirectory: "Audio")
                ?? bundle.url(forResource: resourceName, withExtension: "wav")
        else {
            NSLog("NiuLaiMarketPets: click audio resource missing for %@", pet.rawValue)
            return
        }

        do {
            player = try AVAudioPlayer(contentsOf: url)
            player?.volume = Self.normalizedVolume
            player?.prepareToPlay()
            player?.play()
        } catch {
            NSLog("NiuLaiMarketPets: click audio failed for %@: %@", pet.rawValue, error.localizedDescription)
        }
    }
}
