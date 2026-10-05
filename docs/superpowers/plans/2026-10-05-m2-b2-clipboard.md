# M2-B2 Selected Ink Clipboard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans. 직접 구현하고 단계 끝에 fresh reviewer 한 번을 사용한다. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 선택 획을 복사하고 같은 노트의 다른 페이지 또는 다른 노트에 붙여넣어, 새 UUID와 원래 필기 값을 유지한 채 같은 페이지 Undo/Redo·저장·백업으로 이어간다.

**Architecture:** Foundation의 작은 버전 있는 ink payload와 paste 명령을 추가한다. UIKit의 사용자 실행 paste control/provider는 앱에 두며, 현재 canvas를 캡처한 소유 문서·페이지·generation·revision에만 완료 결과를 적용한다. M2-B의 명시적 native snapshot/alias/Undo 경계를 재사용한다.

**Tech Stack:** Swift/Foundation, SwiftUI/UIKit/PencilKit/PDFKit, iPadOS18+, 외부 의존성 없음.

**Spec:** `docs/superpowers/specs/2026-09-26-minote-product-design.md` 객체 복사·안정 ID·호환성. 선행 M2-B 결과와 `docs/format/document-v3.md`, `docs/format/backup-v1.md`.

**상태:** 계획만 작성, M2-B2 미구현. 완료된 M2-B 결과/진행 기록/Git 상태를 확인한 후 다음 실행에서 진행한다.

## Global Constraints

- 기본 저장소 main 직접 작업, no branch/worktree/PR/push. 한 단위만 구현하며 실제 입력·프로그램 callback·실기기 결과를 구분한다.
- 기존 schema3/catalog1/backup1 유지. MiNoteCore에 UIKit/PencilKit/클립보드 접근을 넣지 않는다.
- 사용자 복사/붙여넣기 실행에서만 클립보드에 접근한다. 앱 열기·페이지 전환·selection 변경 때 읽거나 clipboard 존재 여부를 조회하지 않는다.
- 커스텀 type `com.minote.ink-selection`, JSON payload version1, `strokes: [InkStroke]`만 지원한다. 펜·형광펜만; PDF bytes/문서 제목/폴더/Undo/선택 overlay는 넣지 않는다. 보수 입력 한도8MiB·2,000획·총100,000 제어점. 초과/미래 버전/중복 ID/NaN·overflow·알 수 없는 필드는 오류이며 잘라내거나 원본을 지우지 않는다. 한도는 M3 실기기 측정 후 조정한다.
- 복사는 문서 순서의 선택 전체 획을 그대로 담는다. 빈 선택은 clipboard와 문서·이력 무변경. 인코딩 성공 전 기존 clipboard를 대체하지 않는다.
- 붙여넣기는 모든 새 획에 새 UUID를 부여하고 문서 순서대로 현재 page 끝에 추가한다. source 값/순서는 유지하며 tx/ty만 같은 dx/dy를 더한다. 새 획만 선택, Undo/Redo는 선택 초기화와 revision+1. 실패/빈 명령은 문서·현재 화면·이력 무변경.
- 배치는 제어점에 각 affine을 한 번 적용한 중심선 bounding box의 중심을, paste 시작 때 캡처한 visible viewport 중심의 페이지 좌표에 맞춘다. 기본 이동은 `dx = viewportCenter.x - boundsCenter.x`, `dy = viewportCenter.y - boundsCenter.y`; brush 외곽 여백/크기 변경/페이지 밖 유한 좌표 clip 없음. PDF rotation/zoom이 두 번 반영되지 않는다.
- 지연 provider 완료는 시작 문서 ID/pageID/generation/revision과 다르면 오류로 폐기한다. 저장 실패·backup/import/export busy·미직렬화 필기에도 적용하지 않는다. 대기 중 새 입력은 유지한다.
- 공통 payload는 편집 포맷 교환 시험을 제공하며 일반 외부 이미지/텍스트/PDF 붙여넣기는 후속이다. 실기기 Pencil/손바닥/발열 및 외부 앱 clipboard 권한은 별도 검증 대기다.

## Review Focus

1. provider 읽는 동안 노트/page 전환·재실행·새 native 필기가 오면 이전 요청이 새 문서나 입력을 덮어쓰지 않아야 한다(Task2/3).
2. 거대한/손상/미래 버전·잘못된 UUID/transform·혼합 type payload를 일부만 적용하지 않아야 한다(Task1/2).
3. 같은 모양 원본/복제본을 paste/Undo한 뒤 native erase/append할 때 다른 UUID의 alias를 추측하지 않아야 한다(Task2).
4. crop/0·90·180·270도 PDF와 zoom/scroll에서 viewport 중심 배치와 출력 좌표가 같아야 한다(Task3).
5. clipboard 읽기 실패·저장 ENOSPC·backup busy는 화면/clipboard/양 저장본·Undo/Redo stack을 보존해야 한다(Task2/3).

## 파일과 인터페이스

- Create `Packages/MiNoteCore/Sources/MiNoteCore/InkClipboard.swift`: `InkClipboardPayload: Codable, Equatable, Sendable` (`schemaVersion`, `strokes`), `InkClipboardCodec.encode(_ payload: InkClipboardPayload) throws -> Data`, `decode(_ data: Data) throws -> InkClipboardPayload`, `bounds(of strokes: [InkStroke]) throws -> InkClipboardBounds`. Bounds는 Foundation Double minX/minY/maxX/maxY, centerX/Y를 제공한다. byte 한도는 decode 전 검사한다.
- Modify `InkCommands.swift`: `paste(strokes: [InkStroke], pageID: UUID, dx: Double, dy: Double, expectedRevision: Int64, in document: NoteDocument) throws -> NoteDocument`.
- Create app `MiNote/InkClipboardAccess.swift`: provider custom type 한도 있는 async read와 copy write. `write(_ data: Data) throws`, `read(from providers: [NSItemProvider]) async throws -> Data`. file provider도 한도 검사하며 완료/취소 후 자기 임시 자원만 정리한다.
- Create `MiNote/InkPasteControl.swift`: UIKit `UIPasteControl`의 사용자 action/provider를 SwiftUI에 연결한다. 타입 광고는 커스텀 type만; 읽기를 자동 호출하지 않는다.
- Modify `EditorSession.swift`: `copySelectedInk() throws -> Data?`, `pasteInk(_ payload: InkClipboardPayload, dx: Double, dy: Double) throws -> InkTransition?`. copy nil=empty, paste는 코어/기존 snapshot 수용을 재사용한다.
- Modify `InkUndoCoordinator.swift`: `paste(_ payload: InkClipboardPayload, dx: Double, dy: Double) throws`를 공통 perform 경계에 연결한다. 필요하면 기존 기능을 바꾸지 않는 명령 소유 구조만 추출한다.
- Modify `NoteCanvas.swift`: CanvasReference는 시작의 native canvas 캡처와 viewportCenter/page 좌표 변환을 제공한다. async 요청 stamp를 캡처/검증하고 같은 coordinator만 호출한다.
- Modify `NoteEditorView.swift`: 올가미 copy button `copySelectedInk`; native paste control `pasteSelectedInk`. copy 선택/eligibility 기반, paste active page/eligibility 기반. clipboard 상태 자동 조회로 enable하지 않는다.
- Tests: Create core `InkClipboardTests.swift`, app `InkClipboardTests.swift`, UI `ClipboardUITests.swift`; 기존 InkUndoTests/SelectionSessionTests, portable lab 명령·fixture 소비자 확장.

### Task 1: 한도 있는 payload와 독립 paste 명령

**Interfaces:** 기존 InkStroke/DocumentCodec를 소비, 위 codec/bounds/InkCommands.paste를 제공한다.

- [ ] RED: pen/marker·같은 모양/다른 UUID가 encode/decode에서 완전히 같고 affine bbox를 한 번 계산한다. 8MiB+1/2,001획/100,001점·empty payload·unknown key/미래 버전/중복 ID/NaN/singular/overflow는 거부한다.
- [ ] RED: 선택 두 획 paste는 원본 문서·다른 페이지/삭제 페이지/PDF metadata 불변, 새 UUID 두 개 append/rev+1. empty command는 Int64.max에서도 no-op지만 문서 검증을 생략하지 않는다. stale/wrong/deleted page/revision overflow는 입력 불변 오류.
- [ ] `swift test --package-path Packages/MiNoteCore --filter InkClipboardTests`에서 missing API RED → 최소 구현 → 전체 `swift test --package-path Packages/MiNoteCore` 0fail → PROGRESS/commit.

### Task 2: 사용자 실행 clipboard와 native Undo 경계

**Interfaces:** Task1 payload/paste를 소비, 앱 clipboard access/paste control/session/history/소유 stamp 제공.

- [ ] RED 실제 UI: pen→lasso copy→다른 blank page paste→pen→Undo3/Redo3. read-only saved JSON에서 원본 유지·새 UUID·순서·위치·reopen 확인. system paste control를 사용하고 test-only 앱 seed/가짜 manager로 대체하지 않는다.
- [ ] RED 프로그램 provider 경계: 반환 전 page/note/generation/revision 변경 및 native A→finalB capture→paste→queuedB; 새 입력/현재 페이지/실제 manager stack 보존. 잘못된/다중 provider와 cancel/오류는 atomic no-op.
- [ ] RED: 반복 paste·동일 모양·native erase/append·raw system Undo/Redo로 provenance 유지 또는 모호성 저장 중단/화면·양 disk 유지. 빈 copy와 실패 인코딩은 기존 clipboard 보존, copy는 revision/history 무변경.
- [ ] native 사용자 paste control/한도 read/owner stamp/버튼 구현 → 관련 app와 실제 UI GREEN → 전체 app → PROGRESS/commit. 실패 fixture 요청은 실제권한확인과 구분한다.

### Task 3: 저장·복구·PDF·공통 payload 왕복

**Interfaces:** Task2의 소유 stamp와 transition을 소비해 영속/독립 교환 결과 제공.

- [ ] RED: paste autosave/relaunch/새 library `.minote` 복원에서 UUID·필기값·다른 metadata·원본 PDF bytes 유지, 선택/Undo 초기화.
- [ ] RED: 실제 backup writer gate/ENOSPC와 지연 provider/raw Undo/Redo 양 stack 보존, retry 후 정확한 재생. 기다리는 동안 입력한 필기를 버리지 않는다.
- [ ] RED: zoom1/2/5·scroll·4crop rotation마다 실제 production host 화면 pixel과 PDF 출력에서 paste 위치 일치, selection outline 출력 제외, 원본 SHA 불변. 단순 좌표 왕복을 실제 화면 검증으로 표시하지 않는다.
- [ ] actual app payload/pasted fixture→independent JS decode/paste fresh UUID manifest 및 추가 편집→iPad owned native edit/Undo/save/reopen. 모든 scalar/metadata 비교, 예상 JSON 복사 금지.
- [ ] 관련 app/core/Node/fixture check GREEN, 문서 포맷/provenance와 PROGRESS/commit.

### Task 4: 양OS 마감·한번 리뷰·기록

**Interfaces:** Task1~3 증거와 한도를 소비해 완료 기록/후속 시작점 제공.

- [ ] 전체 core/Node/모든 fixture check,18.6→26.4 full scheme/actualUI/read-only observer 순차.26 새DD/cacheOFF; 기존 데이터/로그 삭제 없음. OS 권한 prompt가 자동화되지 않는 경우 정확히 미검증으로 남긴다.
- [ ] fresh reviewer 한 번, 위 Review Focus 전달. Important 원인/RED→수정→GREEN/전체 gate, 재리뷰 없음.
- [ ] AGENTS/PROGRESS/README/milestone/Notion append+재조회. 다음 텍스트 unit은 실제 결과 기반 계획만; main commit/clean, no push.

## 자기 점검·첫 시작점

Foundation payload→owned clipboard/native history→영속/교환→마감의 경계와 함수명이 일치한다. Review Focus마다 담당 Task 회귀가 있고 외부 객체/다음 기능을 섞지 않았다. 기존 전체 제품 spec 중 텍스트·이미지·검색·실기기·다른 플랫폼은 후속으로 보존했다. 한도는 초기 보수값이고 shipping 성능 보장이 아니다.

재개 첫 작업: AGENTS→PROGRESS→Git/이 계획→M2-B 실제 history/identity/capture 테스트 읽기, core payload/paste RED 작성. 이번 문서는 미구현이며 현재 실행에서 clipboard 접근은 하지 않는다.
