// Shared by the EpicAppCore tests: the repo's games folder, scratch folders, and small turns to play.

import EpicConformance
import Foundation
import Testing

@testable import EpicAppCore

enum AppTestRepo {
    /// games/ in the repo (EPIC_REPO_ROOT, or up from this file).
    static func games() throws -> URL { try Repo.root(from: #filePath).appendingPathComponent("games") }

    static func catalog() throws -> [GameInfo] { try Catalog.load(games().appendingPathComponent("catalog.json")) }

    static func game(_ id: String) throws -> GameInfo {
        try #require(catalog().first { $0.id == id }, "no \(id) in the catalog")
    }
}

/// A folder under the temporary directory, removed with it.
final class Scratch {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("EpicAppCoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: url) }

    /// Writes a file at [path] under the folder (making its folders), and returns it.
    @discardableResult
    func write(_ path: String, _ contents: String = "x") throws -> URL {
        let file = url.appendingPathComponent(path, isDirectory: false)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: file)
        return file
    }

    func folder(_ path: String) -> URL { url.appendingPathComponent(path, isDirectory: true) }
}

/// A clip step with its lines.
func clip(_ path: String, _ lines: [Line] = []) -> Step { .play(Clip(path: path, dur: 1.0, lines: lines)) }

func line(_ at: Double, _ len: Double, _ who: String, _ text: String, more: Bool = false) -> Line {
    Line(at: at, len: len, who: who, text: text, more: more)
}

func bed(_ path: String?, _ volume: Double = 0.5) -> Step { .bed(path: path, volume: volume, dur: 10.0) }
