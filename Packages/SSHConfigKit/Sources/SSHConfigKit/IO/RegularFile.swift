import Foundation

/// Reads only regular files, and never blocks on a FIFO or device (spec §8.1).
enum RegularFile {
    /// O_NONBLOCK: opening a FIFO or device can never block; fstat on the descriptor (no check/use race).
    /// - Parameter limit: the most bytes to read; nil reads the whole file.
    static func read(_ url: URL, limit: Int?) throws -> Data {
        let fd = open(url.path, O_RDONLY | O_NONBLOCK)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        var info = stat()
        guard fstat(fd, &info) == 0 else {
            let code = POSIXErrorCode(rawValue: errno) ?? .EIO
            close(fd)
            throw POSIXError(code)
        }
        guard info.st_mode & S_IFMT == S_IFREG else {
            close(fd)
            throw KeyFileError.notARegularFile(url.path)
        }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        if let limit { return try handle.read(upToCount: limit) ?? Data() }
        return try handle.readToEnd() ?? Data()
    }
}
