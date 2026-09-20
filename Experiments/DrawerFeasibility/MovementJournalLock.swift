import Darwin
import Foundation

final class MovementJournalLock {
    private var descriptor: Int32

    init(lockURL: URL = FileManager.default.temporaryDirectory
        .appendingPathComponent("CoreDeckDrawerMovement.lock")) throws {
        let descriptor = open(lockURL.path, O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw LockError.unavailable }
        var status = stat()
        guard fstat(descriptor, &status) == 0,
              status.st_mode & S_IFMT == S_IFREG, status.st_uid == getuid(),
              status.st_nlink == 1, flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            throw LockError.unavailable
        }
        self.descriptor = descriptor
    }

    func release() {
        guard descriptor >= 0 else { return }
        flock(descriptor, LOCK_UN)
        close(descriptor)
        descriptor = -1
        // Keep the inode: unlinking it would let two processes lock different files.
    }

    deinit { release() }

    enum LockError: LocalizedError {
        case unavailable
        var errorDescription: String? {
            "Movement probe lock is unavailable or another movement/recovery probe is running."
        }
    }
}
