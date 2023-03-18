import Algorithms
import Foundation

public struct LanguageProject: Hashable {
    public var url: URL

    public var path: String {
        self.url.path(percentEncoded: false)
    }
}

extension LanguageProject {
    public init(_ url: URL) {
        self.url = url
    }
}

extension LanguageProject: CustomStringConvertible {
    public var description: String { self.path }
}

public struct LanguageProjectDatas {
    public var lproj: LanguageProject
    public var datas: [StringsFile: Data]
}

public struct StringsFile: Hashable {
    public var languageProject: LanguageProject
    public var name: String

    public var url: URL {
        URL(filePath: self.name, directoryHint: .notDirectory, relativeTo: self.languageProject.url).absoluteURL
    }

    public var path: String {
        self.url.path(percentEncoded: false)
    }
}

extension StringsFile: CustomStringConvertible {
    public var description: String {
        self.path
    }
}

public struct ParsedLanguageProject {
    public var languageProject: LanguageProject
    public var content: [StringsFile: [String: String]]

    public init(
        languageProject: LanguageProject,
        content: [StringsFile: [String: String]]
    ) {
        self.languageProject = languageProject
        self.content = content
    }
}

private func ensureExtension(language: String) -> String {
    language.hasSuffix(".lproj") ? language : "\(language).lproj"
}

public func readStringsContents(directory: String, languages: [String]) throws -> [LanguageProjectDatas] {
    let languageLprojs = Set(languages.map(ensureExtension(language:)))
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

public func readLanguageProjectDatas(_ lproj: LanguageProject) throws -> LanguageProjectDatas {
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

public func findErrors(in projects: [ParsedLanguageProject]) -> [LanguageComparisonError] {
    var missingKeys = Set<MissingLanguageKey>()
    var accumulatedErrors = [LanguageComparisonError]()

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
                accumulatedErrors.append(
                    .missingFile(
                        MissingStringsFileError(languageProject: project.languageProject, name: table)
                    )
                )
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
            accumulatedErrors.append(
                .missingKey(MissingKeyError(key: missingLanguageKey, foundIn: sourceFile))
            )
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

public enum FileOrDirectory {
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

public struct DataTypeError: Error {}

public enum LanguageComparisonError: Error, Hashable {
    case missingFile(MissingStringsFileError)
    case missingKey(MissingKeyError)
}

extension LanguageComparisonError: CustomStringConvertible {
    public var description: String {
        switch self {
        case let .missingFile(e): return String(describing: e)
        case let .missingKey(e): return String(describing: e)
        }
    }
}

public struct MissingStringsFileError: Error, Hashable {
    public let languageProject: LanguageProject
    public let name: String
}

extension MissingStringsFileError: CustomStringConvertible {
    public var description: String {
        "Missing strings file in \(self.languageProject.path.debugDescription): \(self.name.debugDescription)"
    }
}

public struct MissingLanguageKey: Hashable {
    public let key: String
    public let stringsFile: StringsFile
}

public struct MissingKeyError: Error, Hashable {
    public let key: MissingLanguageKey
    public let foundIn: StringsFile
}

extension MissingKeyError: CustomStringConvertible {
    public var description: String {
        "Missing key \(self.key.key.debugDescription) in \(self.key.stringsFile) (found in \(self.foundIn))"
    }
}

public func parseStrings(_ data: Data) throws -> [String: String] {
    let value = try PropertyListSerialization.propertyList(from: data, format: nil)
    guard let dict = value as? [String: String] else {
        throw DataTypeError()
    }
    return dict
}
