import Darwin
import Foundation

/// Process-scoped lock equivalent to the Windows Mutex used by the WPF app.
/// BSD flock releases the lock automatically if the app crashes, so an old
/// lock file never prevents the next launch.
final class SingleInstanceLock {
    private let fileDescriptor: Int32

    init?() {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("NiuLaiMarketPets-\(getuid()).lock")
            .path
        let descriptor = open(path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { return nil }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            return nil
        }
        fileDescriptor = descriptor
    }

    deinit {
        flock(fileDescriptor, LOCK_UN)
        close(fileDescriptor)
    }
}
