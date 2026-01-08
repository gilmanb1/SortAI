// MARK: - File Hasher Utility
// SHA-256 checksum generation for file deduplication

import Foundation
import CryptoKit

/// Utility for generating file checksums
enum FileHasher {
    
    /// Generates a SHA-256 hash of the file at the given URL
    /// - Parameter url: The file URL to hash
    /// - Returns: Hexadecimal string representation of the hash
    static func sha256(url: URL) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let hash = try computeSHA256(url: url)
                    continuation.resume(returning: hash)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    /// Synchronous SHA-256 computation (for smaller files)
    static func sha256Sync(url: URL) throws -> String {
        try computeSHA256(url: url)
    }
    
    /// Computes SHA-256 using streaming for memory efficiency
    private static func computeSHA256(url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        
        var hasher = SHA256()
        let bufferSize = 64 * 1024  // 64KB chunks
        
        while autoreleasepool(invoking: {
            guard let data = try? handle.read(upToCount: bufferSize), !data.isEmpty else {
                return false
            }
            hasher.update(data: data)
            return true
        }) {}
        
        let digest = hasher.finalize()
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    /// Generates a quick hash from file metadata (size + name + modification date)
    /// Useful for quick comparisons before full hash
    static func quickHash(url: URL) throws -> String {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = attributes[.size] as? Int64 ?? 0
        let modDate = attributes[.modificationDate] as? Date ?? Date()
        let name = url.lastPathComponent
        
        let combined = "\(name)|\(size)|\(modDate.timeIntervalSince1970)"
        let data = Data(combined.utf8)
        let digest = SHA256.hash(data: data)
        
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }
}

