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
        let fileContents = try readStringsContents(directory: self.directory, languages: self.languages)
        let parsedProjects = try fileContents.map { lprojDatas in
            try ParsedLanguageProject(
                languageProject: lprojDatas.lproj,
                content: lprojDatas.datas.mapValues { try parseStrings($0) }
            )
        }

        let errors = findErrors(in: parsedProjects)

        guard !errors.isEmpty else { return }

        for error in errors {
            print(error, to: &stderr)
        }

        throw ExitCode(1)
    }
}

struct LanguageProject: Hashable {
    var url: URL

    var path: String {
        self.url.path(percentEncoded: false)
    }
}

extension LanguageProject {
    init(_ url: URL) {
        self.url = url
    }
}

extension LanguageProject: CustomStringConvertible {
    var description: String { self.path }
}

struct LanguageProjectDatas {
    var lproj: LanguageProject
    var datas: [StringsFile: Data]
}

struct StringsFile: Hashable {
    var languageProject: LanguageProject
    var name: String

    var url: URL {
        URL(filePath: self.name, directoryHint: .notDirectory, relativeTo: self.languageProject.url).absoluteURL
    }

    var path: String {
        self.url.path(percentEncoded: false)
    }
}

extension StringsFile: CustomStringConvertible {
    var description: String {
        self.path
    }
}

struct ParsedLanguageProject {
    var languageProject: LanguageProject
    var content: [StringsFile: [String: String]]
}

func readStringsContents(directory: String, languages: [String]) throws -> [LanguageProjectDatas] {
    let languageLprojs = Set(languages.map { "\($0).lproj" })
    let rootURL = URL(filePath: directory, directoryHint: .isDirectory)
    let lprojDatas: [LanguageProjectDatas] = try FileManager.default.contentsOfDirectory(atPath: directory)
        .filter { (f: String) -> Bool in languageLprojs.contains(f) }
        .map { (f: String) -> LanguageProject in
            LanguageProject(URL(filePath: f, directoryHint: .isDirectory, relativeTo: rootURL).absoluteURL)
        }
        .filter { (lproj: LanguageProject) -> Bool in
            FileManager.default.fileOrDirectoryExists(atPath: lproj.path) == .directory
        }
        .map(readLanguageProjectDatas(_:))

    return lprojDatas
}

func readLanguageProjectDatas(_ lproj: LanguageProject) throws -> LanguageProjectDatas {
    let stringsFiles: [StringsFile] = try FileManager.default.contentsOfDirectory(atPath: lproj.path)
        .filter { $0.hasSuffix(".strings") }
        .map { StringsFile(languageProject: lproj, name: $0) }
        .filter { FileManager.default.fileOrDirectoryExists(atPath: $0.path) == .file }

    let lprojDatas: LanguageProjectDatas = try LanguageProjectDatas(
        lproj: lproj,
        datas: Dictionary(
            uniqueKeysWithValues: stringsFiles.map { ($0, try Data(contentsOf: URL(fileURLWithPath: $0.path))) }
        )
    )
    return lprojDatas
}

func findErrors(in projects: [ParsedLanguageProject]) -> [any Error] {
    let langStrings = projects.map { project in
        combineLanguageDicts(lproj: project.languageProject, dicts: project.content)
    }

    var missingKeys = Set<MissingLanguageKey>()
    var accumulatedErrors = langStrings.flatMap(\.errors)
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

    return accumulatedErrors
}

struct LanguageCombinationResult {
    var lproj: LanguageProject
    var translations: [String: String]
    var errors: [any Error]
}

func combineLanguageDicts(lproj: LanguageProject, dicts: [StringsFile: [String: String]]) -> LanguageCombinationResult {
    var errors = [any Error]()
    var combinedStrings = [String: String]()
    var stringLocation = [String: StringsFile]()
    for stringsFileContents in dicts {
        for (key, value) in stringsFileContents.value {
            if let earlierLocation = stringLocation[key] {
                errors.append(
                    DuplicateKey(key: key, lproj: lproj, file1: earlierLocation, file2: stringsFileContents.key)
                )
                continue
            }
            stringLocation[key] = stringsFileContents.key
            combinedStrings[key] = value
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
    let key: String
    let lproj: LanguageProject
    let file1: StringsFile
    let file2: StringsFile
}

extension DuplicateKey: CustomStringConvertible {
    var description: String {
        let key = self.key.debugDescription
        let file1 = self.file1.name.debugDescription
        let file2 = self.file2.name.debugDescription
        return "Duplicate key \(key) in \(self.lproj). Files: \(file1), \(file2)"
    }
}

struct MissingLanguageKey: Hashable {
    let key: String
    let lproj: LanguageProject
}
struct MissingKeyError: Error {
    let key: MissingLanguageKey
    let foundInLproj: LanguageProject
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
