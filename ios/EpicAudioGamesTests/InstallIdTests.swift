// analytics/InstallIdTest.kt: the random ID usage data is sent under, made once, kept, and forgotten for good.

import Foundation
import Testing
@testable import EpicAudioGames

/**
 * The random ID usage data is sent under (Analytics/InstallId.swift): made once and kept in a file out of backups, a
 * UUID and nothing else, and forgotten for good when usage data is turned off or deleted (the next one is another).
 * Android: InstallIdTest.kt.
 */
@MainActor
@Suite(.serialized)
final class InstallIdTests {
    private let folder: URL
    private let file: URL

    init() {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("InstallIdTests-\(UUID().uuidString)")
        file = folder.appendingPathComponent("analytics/install_id")
    }

    deinit {
        try? FileManager.default.removeItem(at: folder)
    }

    private func text() throws -> String { try String(contentsOf: file, encoding: .utf8) }

    @Test func itsMadeTheFirstTimeItsNeededAndKept() throws {
        let id = InstallId(file: file)
        #expect(id.peek() == nil)
        #expect(!FileManager.default.fileExists(atPath: file.path))
        let made = id.get()
        #expect(Events.fits("uuid", made), "\(made)")
        #expect(made == made.lowercased())
        #expect(id.get() == made)
        #expect(try text() == made)
        // The next run reads the same.
        #expect(InstallId(file: file).peek() == made)
        #expect(InstallId(file: file).get() == made)
    }

    @Test func forgottenItsGoneAndTheNextIsAnother() throws {
        let id = InstallId(file: file)
        let first = id.get()
        id.forget()
        #expect(id.peek() == nil)
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(InstallId(file: file).peek() == nil)
        let second = id.get()
        #expect(first != second)
        #expect(InstallId(file: file).peek() == second)
    }

    @Test func aDamagedFileIsNoID() throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not an id".utf8).write(to: file)
        let id = InstallId(file: file)
        #expect(id.peek() == nil)
        let made = id.get()
        #expect(Events.fits("uuid", made))
        #expect(try text() == made)
        // One written in capitals (by hand) is read, in the server's lower case.
        try Data("4B0C8A8E-4F3D-4C6E-9A51-3B8A7F0F2D10\n".utf8).write(to: file)
        #expect(InstallId(file: file).peek() == "4b0c8a8e-4f3d-4c6e-9a51-3b8a7f0f2d10")
    }

    @Test func itsFolderAndFileAreOutOfBackups() throws {
        _ = InstallId(file: file).get()
        for url in [file, file.deletingLastPathComponent()] {
            #expect(try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true, "\(url)")
        }
    }
}
