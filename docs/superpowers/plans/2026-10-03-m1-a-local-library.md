# M1-A 로컬 라이브러리 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans. 사용자가 확정한 직접 구현·main 작업을 유지하고 단위 종료 때 fresh reviewer 한 번을 사용한다. 구현 전 이 계획과 PROGRESS의 실제 상태를 대조한다.

**Goal:** 기존 필기/PDF를 보존하면서 여러 노트를 만들고 폴더에 정리하고 휴지통에서 복원한 뒤, 각 노트의 저장된 페이지를 다시 열 수 있게 한다.

**Architecture:** Foundation 모델/actor 저장을 `MiNoteCore`에 두고 노트별 디렉터리에서 기존 `DocumentStore`를 재사용한다. 앱의 `LibrarySession`이 노트 열기/닫기를 직렬화하고, 편집기가 저장을 완료한 뒤에만 이동한다. 라이브러리 metadata와 문서 본문은 별도로 버전 관리한다.

**Tech Stack:** Swift 6, Foundation, SwiftUI, 기존 PencilKit/PDFKit 앱. iPadOS 18 이상, 외부 의존성 없음.

**Spec:** `docs/superpowers/specs/2026-09-26-minote-product-design.md`의 라이브러리/저장/1단계. M0-C 결과는 `docs/PROGRESS.md`, 현재 저장은 `Packages/MiNoteCore/Sources/MiNoteCore/DocumentStore.swift`.

## Global Constraints

- `/Users/minwookim/Documents/GitHub/MiNote`의 main에서 직접 구현한다. branch/worktree/PR을 만들지 않는다.
- 공통 패키지는 Foundation만 사용한다. UI/PencilKit/PDFKit은 앱에 유지한다.
- schema-v2 문서와 노트당 한 PDF, 기존 기본 A4/획/원본 자산을 보존한다. 여러 PDF와 페이지 편집은 M1-B에서 별도 schema 설계한다.
- 동일 문서 편집 세션은 하나이며, 저장 실패/미지원 필기가 있으면 노트 이동을 차단한다.
- 휴지통은 metadata의 soft delete다. 영구 삭제 UI나 자동 삭제는 이 단위에 넣지 않는다.
- 사용자 원본과 기존 backup은 migration 완료 뒤에도 남긴다. 손상된 catalog를 빈 라이브러리로 덮어쓰지 않는다.
- 이번 단위는 라이브러리 JSON catalog를 사용한다. 제품 설계의 SQLite는 장기 색인 후보이며 아직 확정 의존성이 아니다. 기존 actor/원자 저장 방식과 Foundation 경계를 유지하고, 검색/규모 측정 뒤 SQLite 도입을 별도 판단한다.
- M1 전체는 M1-A 라이브러리 → M1-B 페이지 관리/다중 PDF → M1-C `.minote` 백업·복원/임시 파일 수명주기로 나눈다. 이 계획은 M1-A만 구현한다.

## Review Focus

- 편집 직후 뒤로 가기/다른 노트 연속 선택: 저장된 현재 리비전만 넘기며 늦은 저장이 다른 노트로 전달되지 않아야 한다(Task 3).
- 기존 v1/v2·복구본·누락 PDF: 이주 시 ID/원본/백업을 보존하고 오류를 보여야 한다(Task 1).
- catalog 쓰기 실패 또는 문서 생성 직후 중단: 현재 목록을 보존하고 미연결 디렉터리를 숨기거나 지우지 않아야 한다(Task 1/2).
- 폴더 이름 중복/자기 자식으로 이동/휴지통 문서의 폴더 관계: UUID 관계를 검사하고 복원 가능한 위치를 유지해야 한다(Task 2).
- 노트 이름 변경과 자동 저장 경합: 활성 노트는 먼저 flush/닫기 후 이름을 바꾸고, 문서가 제목의 최종 원본이어야 한다(Task 2/3).

## 파일과 인터페이스

새 core 파일 `Library.swift`는 `LibraryCatalog(version: Int = 1, revision: Int64, notes: [LibraryNote], folders: [LibraryFolder])`, `LibraryNote(id: UUID, folderID: UUID?, modifiedAt: Double, trashedAt: Double?)`, `LibraryFolder(id: UUID, name: String, parentID: UUID?)`를 정의한다. 제목은 `NoteDocument.title`을 읽어 목록에 조합하므로 catalog의 중복 제목이 최신 문서를 덮어쓰지 않는다.

`LibraryLoadResult(catalog: LibraryCatalog, recoveredNoteIDs: [UUID], recoveryNotice: String?)`는 디스크 catalog와 일시적 복구 안내를 구분한다. `LibraryStore.swift` actor는 `load() async throws -> LibraryLoadResult`, `documentStore(for id: UUID) throws -> DocumentStore`, `createNote(title: String, folderID: UUID?) async throws -> UUID`, `renameNote(id: UUID, title: String) async throws`, `createFolder(name: String, parentID: UUID?) throws -> UUID`, `renameFolder(id: UUID, name: String) throws`, `moveNote(id: UUID, folderID: UUID?) throws`, `moveFolder(id: UUID, parentID: UUID?) throws`, `trashNote(id: UUID) throws`, `restoreNote(id: UUID) throws`, `markModified(id: UUID, at: Double) throws`를 제공한다. 한 actor가 catalog 리비전을 검사하고 노트별 `DocumentStore` 인스턴스를 보관한다. async mutation은 첫 await 전에 작업 잠금을 잡아 재진입을 거부하며 sync mutation도 같은 busy 잠금을 검사한다. API에서 실제 디스크 성공 후에만 결과를 반환한다.

저장 경로는 `Documents/MiNote/library.json`, `library.backup.json`, `notes/<UUID>/document.json`, `notes/<UUID>/assets/<UUID>.pdf`다. 기존 루트 `document.json`/backup/assets는 migration 입력이며 삭제하지 않는다. 문서 저장 → catalog 원자 저장 순서이고, 미연결 notes 디렉터리는 재시작 때 복구 목록에 노출한다. 새 설치는 빈 catalog 목록에서 시작하며 노트 생성은 사용자의 생성 동작으로 수행한다. 미연결 노트는 원본을 그대로 둔 채 UUID별 복구 항목으로 catalog에 연결하고 recovery notice를 반환한다. 이때 디스크 쓰기 실패는 오류이며 빈 목록으로 성공하지 않는다. catalog version 오류는 자동 복구로 숨기지 않는다. 실제 JSON 손상일 때만 정상 catalog backup을 읽는다.

앱 `LibrarySession.swift`는 `@MainActor ObservableObject`, 목록/선택/오류/busy 상태를 소유한다. `load() async`가 LibraryLoadResult를 화면 목록/복구 안내로 반영한다. `openNote(_ id: UUID) async`, `closeNote() async -> Bool`은 현재 `EditorSession.flush()`와 `.saved`를 확인한다. 처음 연 문서 리비전과 달라졌으면 성공한 flush 뒤 `markModified(id:at:)`를 호출하고 목록을 갱신한다. 미직렬화 오류 상태에서 `retrySave()`가 성공할 때까지 이동하지 않는다. `LibraryView.swift`는 노트/폴더/최근/휴지통 목록과 생성·이름 변경·이동·복원을 제공한다. `NoteEditorView`는 `init(session: EditorSession, onClose: @escaping () -> Void)`로 주입받아 자기 디렉터리를 새로 만들지 않는다.

### Task 1: 기존 노트 보존과 catalog 읽기/저장

**Files:** Create core `Library.swift`, `LibraryStore.swift`, tests `LibraryMigrationTests.swift`, `LibraryStoreTests.swift` (모두 `Packages/MiNoteCore` 아래). 기존 `DocumentStore`는 데이터 손실 회귀를 통과하는 범위만 수정한다.

- [ ] `testLegacyMigrationPreservesIDsInkAssetsAndRawBackup` 작성: source fixture를 기존 루트에 두고 load 두 번 후 같은 노트 ID 하나, revision 40, 모든 페이지/획, PDF bytes와 원래 파일/backup 일치를 확인한다.
- [ ] `testInvalidLegacyOrUnsupportedCatalogBlocksBlankReplacement`와 `testInterruptedCreationExposesUnlinkedNoteForRecovery` 작성. 손상·지원하지 않는 버전·누락 자산 때 원본/catalog를 덮어쓰지 않고, 이미 저장된 문서는 복구 목록에 남아야 한다.
- [ ] `swift test --package-path Packages/MiNoteCore --filter Library`로 실제 RED를 확인한다.
- [ ] 위 모델/저장 경로와 `load`, `documentStore(for:)` 구현. 이주는 노트 디렉터리에 검증된 본문·자산을 먼저 복사하고 catalog commit을 마지막에 한다. catalog write 전후 오류를 주입할 internal test initializer로 원본 불변을 확인한다.
- [ ] core 전체 GREEN과 기존 portable fixture check → PROGRESS → 커밋.

### Task 2: 여러 노트·폴더·휴지통의 안전한 변경

**Files:** Modify core `LibraryStore.swift`; Create `LibraryMutationTests.swift`.

- [ ] `testTwoNotesKeepIndependentPDFAndRevision` 작성: A/B 생성, A 필기 저장 뒤 B blank 유지, A 재열기 후 획/리비전 일치. `testRenameReadsLatestDocumentAndDoesNotDiscardInk`는 rename 직전 완료된 편집도 유지한다.
- [ ] `testMoveFolderRejectsCyclesAndMissingParent`, `testFolderRenameDoesNotChangeIDsOrMembership`, `testTrashAndRestorePreserveNoteAndFolder`, `testCatalogWriteFailureRetainsLastGoodState`, `testConcurrentMutationIsRejectedBeforeSecondCommit` 작성. 폴더를 없애는 UI는 넣지 않으므로 휴지통 노트의 폴더가 dangling 참조가 되지 않는다.
- [ ] 관련 RED 확인 → 위 mutation API 최소 구현. 제목/폴더 이름은 trim 후 비어 있으면 거부하며 UUID가 식별자다. 정렬은 modifiedAt 내림차순/UUID 보조 순서로 고정한다.
- [ ] core 전체 GREEN → 기록 → 커밋.

### Task 3: 저장 완료를 보장하는 편집 세션 전환

**Files:** Create app `LibrarySession.swift`, tests `LibrarySessionTests.swift`; Modify `NoteEditorView.swift`, `MiNoteApp.swift`.

- [ ] `testSwitchAfterEditFlushesOnlyOutgoingNote`, `testFailedSaveOrUnsupportedInkBlocksClose`, `testRepeatedOpenHasOneActiveSession`, `testRenameWaitsUntilEditorIsClosed` 작성. 실제 임시 DocumentStore 두 개를 사용한다.
- [ ] 관련 Xcode RED → `openNote`/`closeNote` 구현. 첫 await 전에 busy 상태를 설정하고 늦은 결과가 현재 선택 ID와 다르면 화면을 교체하지 않는다. 저장 실패 시 동일 그림/노트를 유지하고 재시도한다.
- [ ] 편집기 주입 구조 변경 후 기존 PDF/Canvas/UI 테스트를 함께 실행해 GREEN → 기록 → 커밋.

### Task 4: 라이브러리 화면과 전체 검증

**Files:** Create `LibraryView.swift`, UI tests `LibraryUITests.swift`; Modify 기존 UI 테스트의 편집기 진입 경로 및 Xcode project 파일.

- [ ] UI test `testCreateOrganizeTrashRestoreAndRelaunch` 작성: A/B 노트, 폴더 생성/이동, A 실제 손가락 획 저장, B 열기, A 재열기, 휴지통 이동/복원, 재실행의 제목·폴더·획 확인. 기존 한 노트의 migration UI 경로도 별도 fixture 환경에서 확인한다.
- [ ] 관련 RED → 라이브러리 목록/툴바/생성·이동·이름 변경·휴지통·오류/재시도 화면 구현. 작업 중 버튼 비활성·접근성 ID를 제공한다. 문서 오류 항목은 목록에서 숨기지 않는다.
- [ ] `node --test Tools/PortableInk/*.test.mjs`, `node Tools/PortableInk/roundtrip.mjs --check`, `swift test --package-path Packages/MiNoteCore` 및 18.6/26.4 `MiNote` 전체 Xcode tests 모두 GREEN. 실제 Pencil 평가는 계속 대기다.
- [ ] fresh reviewer 한 번 → 중요 문제 재현/수정/검증 → PROGRESS/Notion/README/AGENTS → 커밋. 실제 결과를 반영해 M1-B 상세 계획을 작성한다. push는 별도 요청 범위다.

## 완료 조건과 자기 점검

여러 노트가 독립적으로 저장되고 기존 노트가 이주되며, 폴더 정리와 휴지통 복원이 실제 재실행 후 유지되어야 한다. 실패한 저장/이주/catalog 때문에 이전 기록이 사라지지 않아야 한다. 현재 페이지/PDF/필기/Undo 기능의 기존 검증도 통과해야 한다.

자기 점검: 라이브러리·노트·폴더·휴지통/안전한 이동은 Task 1~4에 대응한다. 다중 PDF/용지/페이지 관리/검색/`.minote` 백업·임시 export cleanup은 M1-B/C 또는 M2 후속이며 이번 완료로 주장하지 않는다. 이 파일은 다음 실행의 계획이며 아직 코드 구현/검증 결과가 아니다.
