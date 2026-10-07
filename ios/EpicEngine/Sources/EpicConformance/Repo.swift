// build.gradle.kts's games.dir, fixtures.dir and engine.src for GoldenTest.kt: where the repo's folders are.

import Foundation

/// The repository: the folder with games/catalog.json, found from EPIC_REPO_ROOT or by walking up from a source file.
public enum Repo {
    /**
     * EPIC_REPO_ROOT when set; else the first folder with games/catalog.json above [file] (pass #filePath), above
     * this source file, or above the current directory.
     */
    public static func root(from file: String = #filePath) throws -> URL {
        if let env = ProcessInfo.processInfo.environment["EPIC_REPO_ROOT"], !env.isEmpty {
            let url = URL(fileURLWithPath: env)
            guard isFile(url.appendingPathComponent("games/catalog.json")) else {
                throw ConformanceError("EPIC_REPO_ROOT=\(env) has no games/catalog.json")
            }
            return url
        }
        for start in [file, #filePath, FileManager.default.currentDirectoryPath] {
            // Symlinks resolved, so a package that links to these sources still finds the repo.
            var dir = URL(fileURLWithPath: start).resolvingSymlinksInPath()
            while dir.path != "/" && !dir.path.isEmpty {
                if isFile(dir.appendingPathComponent("games/catalog.json")) { return dir }
                dir.deleteLastPathComponent()
            }
        }
        throw ConformanceError("can't find the repo (a folder with games/catalog.json): set EPIC_REPO_ROOT")
    }

    static func isFile(_ url: URL) -> Bool {
        var dir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &dir) && !dir.boolValue
    }

    static func isDirectory(_ url: URL) -> Bool {
        var dir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &dir) && dir.boolValue
    }

    /// The names in a folder (hidden ones too, as Java's File.listFiles gives them); none when it isn't there.
    static func list(_ dir: URL) -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
    }
}
