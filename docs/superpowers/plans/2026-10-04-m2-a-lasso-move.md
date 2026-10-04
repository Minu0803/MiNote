# M2-A Lasso Selection and Stroke Translation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans. 직접 구현하고 전체 단위 끝에 fresh reviewer 한 번을 사용한다. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 빈 용지와 PDF 페이지에서 올가미로 획 전체를 선택·이동하고, 현재 페이지 Undo/Redo와 저장·백업·재열기에서 ID와 위치를 유지한다.

**Architecture:** 선택 영역은 UIKit 캔버스 위의 임시 overlay이며 저장하지 않는다. Foundation 명령이 선택된 UUID의 문서 좌표 변환만 변경한다. 앱이 PencilKit 재구성과 같은 canvas UndoManager에 명령을 연결하고 native 필기와 선택 이동의 순서를 검증한다.

**Tech Stack:** Swift 6/Foundation, SwiftUI/UIKit/PencilKit/PDFKit, 외부 의존성 없음, iPadOS 18 이상.

**Spec:** `docs/superpowers/specs/2026-09-26-minote-product-design.md` 객체 편집/안정 ID/좌표/Undo. 기존 계약 `docs/format/document-v3.md`, `docs/format/backup-v1.md`; 이전 결과 `docs/PROGRESS.md` M1-C.

## Global Constraints

- 기본 저장소 main에서 직접 작업한다. branch/worktree/PR/push 없음. 이번 문서는 다음 단위의 계획이며 M2-A 구현 결과가 아니다.
- schema v3/catalog v1/backup v1을 유지한다. 코어에 UIKit/PencilKit 타입을 넣지 않는다. PDF 원본·page/stroke/asset IDs와 비선택 획은 불변이다.
- 이번 범위는 획 전체 선택·평행 이동·선택 해제·이동 취소다. 복사/삭제/크기/회전/부분 선택·텍스트·이미지·검색은 후속 단위다.
- 기존 펜/형광펜/획 지우개와 Pencil 기본 입력/시뮬레이터 손가락 전환을 유지한다. 올가미 선택 중 두 손가락 pan/zoom을 유지하고 입력 종류 설정을 적용한다.
- 좌표는 페이지 좌상단 원점, 1/72인치다. zoom·회전은 선택/이동 결과를 바꾸지 않는다. 페이지 밖 이동도 유한한 좌표이면 허용하며 잘라내지 않는다.
- 선택은 보간된 획 중심선의 점/선분이 닫힌 올가미 안 또는 경계와 만나는 획 전체다. 굵기 외곽만 닿는 획은 이번 선택 규칙에 포함하지 않는다. 자기 교차 영역은 even-odd 규칙이다.
- 선택 해제/취소/0 이동은 저장 revision을 올리지 않는다. 성공한 이동/Undo/Redo마다 현재 문서 revision을 한 번 증가시키고 일반 autosave를 사용한다.
- 다른 페이지/노트 전환 때 선택과 Undo를 초기화한다. 미지원 필기/모호 ID/저장 실패는 화면 필기와 정상 디스크를 보존한다. 처리 중 이동/Undo/Redo를 막는다.
- 실기기 Pencil/손바닥/지연/대형 실제 노트 성능은 M3 검증 대기다.

## Review Focus

1. 이동 후 native pen erase/Undo가 원래 획 UUID를 잃거나 같은 모습의 다른 획 UUID를 가져오지 않는가(Task1/2).
2. zoom/화면 회전/회전 PDF에서 올가미와 이동량이 화면 pixel로 저장되거나 다른 페이지에 적용되지 않는가(Task2/3).
3. 필기→이동→필기→Undo/Redo가 하나의 현재 페이지 이력에서 순서대로 작동하고 자동 저장 결과가 일치하는가(Task2/3).
4. gesture 취소/페이지 전환/늦은 delegate/파일 작업 중 필기가 사라지거나 선택 이동이 두 번 commit되지 않는가(Task2/3).
5. 저장 실패·미지원 필기·동일 획 ID 모호성에서 이전 저장본과 화면을 유지하고 재시도·백업에서 명시적으로 처리하는가(Task1/3).

## File Map and Interfaces

- Create core `InkCommands.swift`: `InkCommands.translate(strokeIDs: Set<UUID>, pageID: UUID, dx: Double, dy: Double, expectedRevision: Int64, in: NoteDocument) throws -> NoteDocument`. 기존 value 명령 패턴. 유한량·존재 ID·현재 활성 page·정확 revision·overflow 검사, transform.tx/ty에 문서 이동량을 더하고 전체 codec validate. 빈 집합/0 이동은 동일 value.
- Create core `SelectionGeometry.swift`: `SelectionPoint(x: Double,y: Double)`와 `SelectionGeometry.intersects(polyline: [SelectionPoint], polygon: [SelectionPoint]) throws -> Bool`. 유한 좌표/3개 이상 서로 다른 polygon 꼭짓점 검사; 점/선분과 경계 포함 even-odd 영역. UIKit 경계는 앱이 바꾼다.
- Create app `InkSelection.swift`: `selectedIDs(in: PKDrawing, portable: [InkStroke], polygon: [SelectionPoint]) throws -> Set<UUID>`와 문서 좌표 selection 상태. 현재 native→portable 동일 순서/ID를 먼저 검증하고 PKStrokePath를 최대 2pt 간격으로 보간한 뒤 기존 transform을 적용한다.
- Modify `InkAdapter.swift`, `EditorSession.swift`: 명령이 만든 authoritative pre/post 획 value와 UUID를 native callback에 연결한다. 이동 전후 같은 UUID의 여러 value는 명시적인 이동 이력으로 보존한다. 모호한 다른 UUID 후보는 추측 매칭하지 않는다. 기존 append/erase/재구성 별칭 테스트를 유지한다.
- Create app `LassoOverlay.swift`; Modify `NoteCanvas.swift`, `NoteEditorView.swift`: page UIView 자식 overlay, `convert(_:from:)`로 문서 좌표 취득, 임시 올가미/선택 테두리 표시, 선택 내부 drag 종료 한 번 commit/취소 원복. 이동 중 preview는 문서/저장을 바꾸지 않는다. toolbar `올가미`, `선택 해제` 및 선택 획 수를 접근성으로 제공한다.
- Create app `InkUndoCoordinator.swift`: 실제 PKCanvasView.undoManager에 이동 전후 명령 등록. app drawing 할당의 delegate를 억제하고 같은 canvasGeneration을 유지한다. inverse 등록/Redo와 native pen 이력이 함께 움직이는지 Task2 spike가 구현 확정 조건이다. 다른 페이지는 기존 generation 교체 정책을 유지한다.
- Tests: core `InkCommandTests.swift`, `SelectionGeometryTests.swift`; app `InkSelectionTests.swift`, `InkUndoTests.swift`, `SelectionSessionTests.swift`; UI `LassoUITests.swift`; portable lab 기존 v3 command fixture와 왕복 테스트.

### Task 1: 공통 선택 판정·ID를 보존하는 이동

**Interfaces:** consumes NoteDocument/InkStroke/InkTransform/DocumentCodec; produces 위 두 Foundation API와 selection 규칙.

- [x] RED: transform a=0,b=1,c=-1,d=0,tx=10,ty=20 획을 문서 dx=30,dy=-15 이동하면 tx=40,ty=5이며 제어점/ID/선형 변환은 그대로. 비선택 획/다른 page/PDF/삭제 페이지 전체 불변, revision+1.
- [x] RED: 없는 ID/다른 페이지 ID/stale revision/NaN/Infinity/합산 overflow/Int64.max 거부, 입력 value 불변. 빈 선택·0 이동 동일 value. 이동과 역이동의 모든 값/IDs 일치(의도한 revision 증가 제외).
- [x] RED: polygon 내부/외부/경계/교차 선분/점 획/자기 교차 even-odd, open polygon 자동 닫기, 비유한/부족 꼭짓점 오류. 동일 위치의 두 UUID 선택은 UUID를 연결하는 Task2 InkSelection 시험에서 확인한다.
- [x] `swift test --package-path Packages/MiNoteCore --filter 'InkCommandTests|SelectionGeometryTests'` 실제 실패 확인 → API 구현 → GREEN, 전체 core → PROGRESS → commit.

### Task 2: UIKit 올가미와 native Undo 통합

**Interfaces:** consumes Task1 APIs/현재 PKDrawing+portable page; produces selected UUIDs/drag translation/현재 canvas undo 명령.

- [x] 먼저 실제 PKCanvasView Undo spike RED: native finger 획 입력 → 선택 이동 → native 새 획 → Undo 세 번/Redo 세 번의 순서·위치·ID. programmatic 가짜 UndoManager만으로 통과하지 않는다. drawing 할당이 native Undo를 제거/중복 등록하면 app 명령 적용 방식부터 해결하고 UI 범위를 늘리지 않는다.
- [x] RED: 같은 획 이동 전/후/Undo/Redo/erase/pen append/reconstruction에서 안정 UUID, 동일 모양 획의 기존 ambiguousIdentity 안전 오류. pre/post 이력은 두 번째 이동에도 최신 transform을 과거 value로 되돌리지 않는다.
- [x] RED: 실제 page→overlay 변환 fit/2배/5배/화면 회전, PDF crop/90·270도에서 dx=30,dy=-15 문서량 동일. 2pt 경로 보간 후 기존 affine transform이 선택 판정에 한 번 적용됨.
- [x] RED: 올가미 빈 영역/선택 해제/gesture cancelled/0 drag는 drawing/revision/Undo 불변. Pencil 기본·손가락 전환/두 손가락 pan/zoom, 선택 뒤 pen으로 전환하면 선택만 해제.
- [x] 위 app API/overlay/toolbar 구현 → 관련 app tests+실제 finger UI GREEN → PROGRESS → commit. PKLassoTool의 자동 copy/cut/resize UI를 이번 범위에 노출하지 않는다.

### Task 3: 세션 저장·백업·PDF·경합 검증

**Interfaces:** consumes Task2의 selected UUIDs/이동 명령/native Undo; produces 저장·재열기·내보내기에서 유지되는 선택 이동.

- [ ] RED: 이동 후 autosave/재열기/`.minote` 새 노트 복원/독립 v3 왕복에서 ID·transform·원본 PDF bytes·용지/책갈피/삭제 페이지 보존. 복원은 Undo history를 포함하지 않는다.
- [ ] RED: 페이지 전환·구조 변경·export/import 중 이동과 Undo 차단; 이전 generation callback은 다른 페이지를 변경하지 않음. commit 직전 queued 필기는 현재 세션/디스크에 보존하고 중복 이동 없음.
- [ ] RED: 저장 ENOSPC/미지원 drawing/ID 모호 오류에서 현재 화면과 정상 primary/backup 유지, 선택 command 강행 금지, 재시도 후 최신 정상 snapshot만 backup 허용.
- [ ] RED: crop/회전 PDF 위 선택 이동을 실제 PDF output pixel로 확인하고 PDF source bytes 불변. 선택 테두리는 PDF/backup에 출력하지 않음.
- [ ] session/history/저장 연결 → 관련 app/core/Node v3 왕복 GREEN → PROGRESS → commit.

### Task 4: 양 OS 검증·한 번 리뷰·인계

- [ ] core/Node/v2·v3 --check, app 전체와 Lasso UI를 iPadOS 18.6/26.4 순차 실행. 현재 페이지 native pen→move→pen Undo/Redo, zoom·PDF·재실행의 실제 화면을 보존한다. 기존 library/PDF/backup UI도 유지한다.
- [ ] fresh reviewer 한 번, 위 Review Focus 전부 제공. Important는 실제 RED/수정/GREEN과 관련 최종 시험 후 마감. 실기기 미검증은 따로 기록한다.
- [ ] AGENTS/PROGRESS/milestone/README/Notion에 구현 결과·판단·검증·제한 추가/재조회; 다음 M2 작은 단위는 실제 결과에 맞춰 계획만 작성. main commit/clean, no push.

## 다음 M2 단위

순서는 M2-A 결과에 따라 세부 계획을 확정한다: **M2-B 선택 획 삭제·복사/복제 → M2-C 텍스트 상자 → M2-D 이미지 가져오기·편집 → M2-E 제목/폴더 및 PDF 기존 텍스트 검색 → M2-F 혼합 객체·PDF/페이지 독립 왕복과 구버전 안전성**. OCR/손글씨 인식은 후속 고급 기능이다. 이 목록은 구현 완료나 각 단위의 확정 일정이 아니다.

## 계획 자기 점검 / 첫 재개 작업

Foundation 명령/좌표 → 실제 native Undo와 ID → 저장/경합 → 전체 리뷰의 의존성을 유지했다. 선택 규칙과 비선택 데이터 보존, 취소/에러 경계를 각각 테스트에 연결했다. 저장 스키마를 바꾸지 않으므로 M1-C 백업을 그대로 이용한다. 구버전 객체 보존 규격은 새 텍스트/이미지 단계에서 별도 설계한다.

첫 작업: AGENTS/PROGRESS/Git 대조 → Task1 actual fixture의 이동·오류 RED. M1-C가 종료되지 않았다면 먼저 남은 검증/리뷰/기록을 마감한다. 이번 파일 작성은 M2-A 구현 착수를 뜻하지 않는다.
