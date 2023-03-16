import Algorithms
import ArgumentParser
import Foundation

@main
struct Check: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "stringscheck",
        abstract: "Checks that .strings localization files for different languages match",
        discussion: """
            Looks for lproj directories inside a directory and ensures they contain localizations for the same strings.

            Example: stringscheck /path/with/lprojs en fi sv
            """
    )

    @Argument(help: "The directory to look in for lproj folders")
    var directory: String

    @Argument(help: "Languages to include")
    var languages: [String]

    func run() throws {
        let languageLprojs = Set(self.languages.map { "\($0).lproj" })

        let lprojs = try FileManager.default.contentsOfDirectory(atPath: self.directory)
            .filter { languageLprojs.contains($0) }
            .map { "\(self.directory)/\($0)" }
            .filter { FileManager.default.fileOrDirectoryExists(atPath: $0) == .directory }
            .map { lproj in
                let stringsFiles = try FileManager.default.contentsOfDirectory(atPath: lproj)
                    .filter { $0.hasSuffix(".strings") }
                    .map { "\(lproj)/\($0)" }
                    .filter { FileManager.default.fileOrDirectoryExists(atPath: $0) == .file }
                return (lproj, stringsFiles)
            }

        let stringsDicts = try lprojs.map { lproj, stringsFiles in
            try (path: lproj, content: stringsFiles.map { try parseStrings(Data(contentsOf: URL(fileURLWithPath: $0))) })
        }

        let langStrings = stringsDicts.map { lproj, dicts in
            combineLanguageDicts(lproj: lproj, dicts: dicts)
        }

        var missingKeys = Set<MissingLanguageKey>()
        var accumulatedErrors = [any Error]()
        for langs in langStrings.combinations(ofCount: 2) {
            guard let l1 = langs.first, let l2 = langs.dropFirst().first, langs.count == 2 else {
                fatalError("Invalid combination")
            }

            for key1 in l1.translations.keys {
                guard l2.translations[key1] == nil else { continue }
                let missingLanguageKey = MissingLanguageKey(key: key1, lproj: l2.lproj)
                guard !missingKeys.contains(missingLanguageKey) else { continue }
                missingKeys.insert(missingLanguageKey)
                accumulatedErrors.append(MissingKeyError(key: missingLanguageKey, foundInLproj: l1.lproj))
                continue
            }

            for key2 in l2.translations.keys {
                guard l1.translations[key2] == nil else { continue }
                let missingLanguageKey = MissingLanguageKey(key: key2, lproj: l1.lproj)
                guard !missingKeys.contains(missingLanguageKey) else { continue }
                missingKeys.insert(missingLanguageKey)
                accumulatedErrors.append(MissingKeyError(key: missingLanguageKey, foundInLproj: l2.lproj))
                continue
            }
        }

        guard !accumulatedErrors.isEmpty else { return }

        for accumulatedError in accumulatedErrors {
            print(accumulatedError, to: &stderr)
        }

        throw ExitCode(1)
    }
}

struct LanguageCombinationResult {
    var lproj: String
    var translations: [String: String]
    var errors: [any Error]
}

func combineLanguageDicts(lproj: String, dicts: [[String: String]]) -> LanguageCombinationResult {
    var errors = [any Error]()
    let combinedStrings: [String: String] = dicts.reduce(into: [String: String]()) { acc, dict in
        for (key, value) in dict {
            if acc[key] != nil {
                errors.append(DuplicateKey(file: lproj, key: key))
                continue
            }
            acc[key] = value
        }
    }
    return LanguageCombinationResult(
        lproj: lproj,
        translations: combinedStrings,
        errors: errors
    )
}

var stderr = StandardErrorOutputStream()

final class StandardErrorOutputStream: TextOutputStream {
    func write(_ string: String) {
        FileHandle.standardError.write(Data(string.utf8))
    }
}

enum FileOrDirectory {
    case notExist
    case file
    case directory
}

extension FileManager {
    func fileOrDirectoryExists(atPath path: String) -> FileOrDirectory {
        var isDirectory: ObjCBool = false
        let exists = self.fileExists(atPath: path, isDirectory: &isDirectory)
        switch (exists, isDirectory.boolValue) {
        case (false, _): return .notExist
        case (true, false): return .file
        case (true, true): return .directory
        }
    }
}

struct DataTypeError: Error {}
struct DuplicateKey: Error {
    let file: String
    let key: String
}
struct MissingLanguageKey: Hashable {
    let key: String
    let lproj: String
}
struct MissingKeyError: Error {
    let key: MissingLanguageKey
    let foundInLproj: String
}

extension MissingKeyError: CustomStringConvertible {
    var description: String {
        "Missing key \(self.key.key.debugDescription) in \(self.key.lproj) (found in \(self.foundInLproj))"
    }
}

func parseStrings(_ data: Data) throws -> [String: String] {
    let value = try PropertyListSerialization.propertyList(from: data, format: nil)
    guard let dict = value as? [String: String] else {
        throw DataTypeError()
    }
    return dict
}
