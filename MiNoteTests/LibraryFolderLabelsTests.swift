import XCTest
import MiNoteCore
@testable import MiNote

final class LibraryFolderLabelsTests: XCTestCase {
    func testSameNameSiblingsHaveStableDistinctPaths() {
        let a = LibraryFolder(name: "Work"), b = LibraryFolder(name: "Work")
        let labels = LibraryFolderLabels(folders: [a, b]), reordered = LibraryFolderLabels(folders: [b, a])
        XCTAssertNotEqual(labels.label(for: a.id), labels.label(for: b.id))
        XCTAssertEqual(labels.label(for: a.id), reordered.label(for: a.id))
        XCTAssertTrue(labels.label(for: a.id).hasPrefix("Work · "))
    }
    func testChildrenIncludeDisambiguatedAncestorsAndDifferentParentPaths() {
        let a = LibraryFolder(name: "Work"), b = LibraryFolder(name: "Work")
        let childA = LibraryFolder(name: "Notes", parentID: a.id), childB = LibraryFolder(name: "Notes", parentID: b.id)
        let labels = LibraryFolderLabels(folders: [a, b, childA, childB])
        XCTAssertEqual(labels.label(for: childA.id), labels.label(for: a.id) + " / Notes")
        XCTAssertNotEqual(labels.label(for: childA.id), labels.label(for: childB.id))
        let other = LibraryFolder(name: "Other"), work = LibraryFolder(name: "Work", parentID: other.id)
        XCTAssertEqual(LibraryFolderLabels(folders: [a, other, work]).label(for: work.id), "Other / Work")
    }
    func testCollidingShortIdentifiersExpandUntilUnique() throws {
        let a = LibraryFolder(id: try XCTUnwrap(UUID(uuidString: "00000000-0000-4000-8000-000000123456")), name: "Work")
        let b = LibraryFolder(id: try XCTUnwrap(UUID(uuidString: "00000000-0000-4000-8000-010000123456")), name: "Work")
        let labels = LibraryFolderLabels(folders: [a, b])
        XCTAssertNotEqual(labels.label(for: a.id), labels.label(for: b.id))
    }
}
