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

    @Argument(help: "Languages to include (two or more)")
    var languages: [String]

    func validate() throws {
        guard self.languages.count > 1 else {
            throw ValidationError("You must specify at least two languages")
        }
    }

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
    var missingKeys = Set<MissingLanguageKey>()
    var accumulatedErrors = [any Error]()

    guard let firstProject = projects.first else { return [] }
    let initialCommonTables = firstProject.content.keys.map(\.name)

    let tables = projects
        .map { project in project.content.keys }
        .reduce(into: (all: Set<String>(), common: Set(initialCommonTables))) { tables, stringsFiles in
            tables.all.formUnion(stringsFiles.map(\.name))
            tables.common.formIntersection(stringsFiles.map(\.name))
        }

    for project in projects {
        for table in tables.all {
            if !project.content.contains(where: { $0.key.name == table }) {
                accumulatedErrors.append(MissingStringsFileError(languageProject: project.languageProject, name: table))
            }
        }
    }

    for projectPair in projects.permutations(ofCount: 2) {
        guard projectPair.count == 2 else { fatalError("Invalid combination \(projectPair)") }
        let proj1 = projectPair[0]
        let proj2 = projectPair[1]

        func require(
            key: String,
            sourceFile: StringsFile,
            targetFile: StringsFile,
            targetContent: [String: String]
        ) {
            guard targetContent[key] == nil else { return }
            let missingLanguageKey = MissingLanguageKey(key: key, stringsFile: targetFile)
            guard !missingKeys.contains(missingLanguageKey) else { return }
            missingKeys.insert(missingLanguageKey)
            accumulatedErrors.append(MissingKeyError(key: missingLanguageKey, foundIn: sourceFile))
        }

        for table in tables.common {
            let (sf1, strings1) = proj1.content.first(where: { $0.key.name == table })!
            let (sf2, strings2) = proj2.content.first(where: { $0.key.name == table })!

            for key1 in strings1.keys {
                require(key: key1, sourceFile: sf1, targetFile: sf2, targetContent: strings2)
            }

            for key2 in strings2.keys {
                require(key: key2, sourceFile: sf2, targetFile: sf1, targetContent: strings1)
            }
        }
    }

    return accumulatedErrors
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

struct MissingStringsFileError: Error {
    let languageProject: LanguageProject
    let name: String
}

extension MissingStringsFileError: CustomStringConvertible {
    var description: String {
        "Missing strings file in \(self.languageProject.path.debugDescription): \(self.name.debugDescription)"
    }
}

struct MissingLanguageKey: Hashable {
    let key: String
    let stringsFile: StringsFile
}

struct MissingKeyError: Error {
    let key: MissingLanguageKey
    let foundIn: StringsFile
}

extension MissingKeyError: CustomStringConvertible {
    var description: String {
        "Missing key \(self.key.key.debugDescription) in \(self.key.stringsFile) (found in \(self.foundIn))"
    }
}

func parseStrings(_ data: Data) throws -> [String: String] {
    let value = try PropertyListSerialization.propertyList(from: data, format: nil)
    guard let dict = value as? [String: String] else {
        throw DataTypeError()
    }
    return dict
}
