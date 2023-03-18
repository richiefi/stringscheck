import Foundation
@testable import StringsCheck
import XCTest

final class StringsCheckTests: XCTestCase {
    func testEmpty() throws {
        XCTAssertTrue(findErrors(in: []).isEmpty)
    }

    func testTwoGood() throws {
        let lproj1 = LanguageProject(URL(filePath: "/l1", directoryHint: .isDirectory))
        let l1sf1 = StringsFile(languageProject: lproj1, name: "sf1")
        let l1sf2 = StringsFile(languageProject: lproj1, name: "sf2")
        let lproj2 = LanguageProject(URL(filePath: "/l2", directoryHint: .isDirectory))
        let l2sf1 = StringsFile(languageProject: lproj2, name: "sf1")
        let l2sf2 = StringsFile(languageProject: lproj2, name: "sf2")

        let strings1 = [
            "key1": "value1",
            "key2": "value2",
        ]

        let strings2 = [
            "key3": "value3",
            "key4": "value4",
        ]

        let plp1 = ParsedLanguageProject(
            languageProject: lproj1,
            content: [
                l1sf1: strings1,
                l1sf2: strings2,
            ]
        )

        let plp2 = ParsedLanguageProject(
            languageProject: lproj2,
            content: [
                l2sf1: strings1,
                l2sf2: strings2,
            ]
        )

        XCTAssertTrue(findErrors(in: [plp1, plp2]).isEmpty)
    }

    func testThreeGood() throws {
        let lproj1 = LanguageProject(URL(filePath: "/l1", directoryHint: .isDirectory))
        let l1sf1 = StringsFile(languageProject: lproj1, name: "sf1")
        let l1sf2 = StringsFile(languageProject: lproj1, name: "sf2")
        let lproj2 = LanguageProject(URL(filePath: "/l2", directoryHint: .isDirectory))
        let l2sf1 = StringsFile(languageProject: lproj2, name: "sf1")
        let l2sf2 = StringsFile(languageProject: lproj2, name: "sf2")
        let lproj3 = LanguageProject(URL(filePath: "/l2", directoryHint: .isDirectory))
        let l3sf1 = StringsFile(languageProject: lproj3, name: "sf1")
        let l3sf2 = StringsFile(languageProject: lproj3, name: "sf2")

        let strings1 = [
            "key1": "value1",
            "key2": "value2",
        ]

        let strings2 = [
            "key3": "value3",
            "key4": "value4",
        ]

        let plp1 = ParsedLanguageProject(
            languageProject: lproj1,
            content: [
                l1sf1: strings1,
                l1sf2: strings2,
            ]
        )

        let plp2 = ParsedLanguageProject(
            languageProject: lproj2,
            content: [
                l2sf1: strings1,
                l2sf2: strings2,
            ]
        )

        let plp3 = ParsedLanguageProject(
            languageProject: lproj3,
            content: [
                l3sf1: strings1,
                l3sf2: strings2,
            ]
        )

        XCTAssertTrue(findErrors(in: [plp1, plp2, plp3]).isEmpty)
    }

    func testExtraStringsFile() throws {
        let lproj1 = LanguageProject(URL(filePath: "/l1", directoryHint: .isDirectory))
        let l1sf1 = StringsFile(languageProject: lproj1, name: "sf1")
        let l1sf2 = StringsFile(languageProject: lproj1, name: "sf2")
        let lproj2 = LanguageProject(URL(filePath: "/l2", directoryHint: .isDirectory))
        let l2sf1 = StringsFile(languageProject: lproj2, name: "sf1")
        let l2sf2 = StringsFile(languageProject: lproj2, name: "sf2")
        let lproj3 = LanguageProject(URL(filePath: "/l2", directoryHint: .isDirectory))
        let l3sf1 = StringsFile(languageProject: lproj3, name: "sf1")
        let l3sf2 = StringsFile(languageProject: lproj3, name: "sf2")
        let l3sf3 = StringsFile(languageProject: lproj3, name: "sf3")

        let strings1 = [
            "key1": "value1",
            "key2": "value2",
        ]

        let strings2 = [
            "key3": "value3",
            "key4": "value4",
        ]

        let plp1 = ParsedLanguageProject(
            languageProject: lproj1,
            content: [
                l1sf1: strings1,
                l1sf2: strings2,
            ]
        )

        let plp2 = ParsedLanguageProject(
            languageProject: lproj2,
            content: [
                l2sf1: strings1,
                l2sf2: strings2,
            ]
        )

        let plp3 = ParsedLanguageProject(
            languageProject: lproj3,
            content: [
                l3sf1: strings1,
                l3sf2: strings2,
                l3sf3: [:],
            ]
        )

        XCTAssertEqual(
            Set(findErrors(in: [plp1, plp2, plp3])),
            [
                .missingFile(MissingStringsFileError(languageProject: lproj1, name: l3sf3.name)),
                .missingFile(MissingStringsFileError(languageProject: lproj2, name: l3sf3.name)),
            ]
        )
    }

    func testExtraString() throws {
        let lproj1 = LanguageProject(URL(filePath: "/l1", directoryHint: .isDirectory))
        let l1sf1 = StringsFile(languageProject: lproj1, name: "sf1")
        let l1sf2 = StringsFile(languageProject: lproj1, name: "sf2")
        let lproj2 = LanguageProject(URL(filePath: "/l2", directoryHint: .isDirectory))
        let l2sf1 = StringsFile(languageProject: lproj2, name: "sf1")
        let l2sf2 = StringsFile(languageProject: lproj2, name: "sf2")
        let lproj3 = LanguageProject(URL(filePath: "/l2", directoryHint: .isDirectory))
        let l3sf1 = StringsFile(languageProject: lproj3, name: "sf1")
        let l3sf2 = StringsFile(languageProject: lproj3, name: "sf2")

        let strings1_1 = [
            "key1": "value1",
            "key2": "value2",
        ]

        let strings1_2 = [
            "key1": "value1",
            "key2": "value2",
            "key10": "value10",
        ]

        let strings2_1 = [
            "key3": "value3",
            "key4": "value4",
        ]

        let strings2_2 = [
            "key3": "value3",
            "key4": "value4",
            "key11": "value11",
        ]

        let plp1 = ParsedLanguageProject(
            languageProject: lproj1,
            content: [
                l1sf1: strings1_2,
                l1sf2: strings2_1,
            ]
        )

        let plp2 = ParsedLanguageProject(
            languageProject: lproj2,
            content: [
                l2sf1: strings1_1,
                l2sf2: strings2_1,
            ]
        )

        let plp3 = ParsedLanguageProject(
            languageProject: lproj3,
            content: [
                l3sf1: strings1_1,
                l3sf2: strings2_2,
            ]
        )

        XCTAssertEqual(
            Set(findErrors(in: [plp1, plp2, plp3])),
            [
                .missingKey(MissingKeyError(key: MissingLanguageKey(key: "key10", stringsFile: l2sf1), foundIn: l1sf1)),
                .missingKey(MissingKeyError(key: MissingLanguageKey(key: "key10", stringsFile: l3sf1), foundIn: l1sf1)),
                .missingKey(MissingKeyError(key: MissingLanguageKey(key: "key11", stringsFile: l1sf2), foundIn: l3sf2)),
                .missingKey(MissingKeyError(key: MissingLanguageKey(key: "key11", stringsFile: l2sf2), foundIn: l3sf2)),
            ]
        )
    }
}
