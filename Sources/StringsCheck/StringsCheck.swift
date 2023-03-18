import ArgumentParser
import Foundation
import StringsCheckCore

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

var stderr = StandardErrorOutputStream()

final class StandardErrorOutputStream: TextOutputStream {
    func write(_ string: String) {
        FileHandle.standardError.write(Data(string.utf8))
    }
}
