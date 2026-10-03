# M0-C 공통 필기 왕복 검증 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans. 사용자가 지정한 직접 구현 방식과 main 작업을 유지하며, 단계 끝에 별도 에이전트 리뷰를 한 번 진행한다.

**Goal:** PencilKit에 의존하지 않는 시험 편집기에서 schema-v2 기본 획을 읽고 수정한 JSON을 iPad가 다시 읽어 추가·삭제·저장할 수 있음을 검증한다.

**Architecture:** 외부 라이브러리 없는 JavaScript/Canvas 시험 편집기를 만든다. 문서 검증·편집 명령은 DOM 없이 실행 가능하게 분리하고, 동일한 수정 fixture를 Swift Package와 실제 iPad 어댑터 테스트에 사용한다. 시험 도구의 근사 브러시 외관과 문서 데이터 보존을 각각 판정한다.

**Tech Stack:** Swift 6 / Foundation / PencilKit, JavaScript ES modules / Canvas 2D, Node 내장 test runner(실행 시 런타임 경로 확인).

**Spec:** `docs/superpowers/specs/2026-09-26-minote-product-design.md`의 공통 문서 형식·0단계 왕복 검증. M0-B 결과는 `docs/PROGRESS.md`와 `MiNote/InkAdapter.swift`를 기준으로 한다. 상태: 다음 개발 단위의 계획이며 구현하지 않았다.

## Global Constraints

- 작업은 `/Users/minwookim/Documents/GitHub/MiNote`의 `main`에서 한다. 새 브랜치/worktree/PR을 만들지 않는다.
- 앱은 iPadOS 18 이상. UIKit/PencilKit은 앱 안에, 공통 저장은 Foundation 전용 `MiNoteCore`에 둔다.
- 기존 schema v2, 안정적인 ID, 좌상단 원점과 1/72인치 단위를 유지한다. PDF metadata/asset bytes는 수정하지 않는다.
- 원본 사용자 노트는 시험 데이터로 교체하지 않는다. 모든 왕복 테스트는 임시 저장소를 사용한다.
- 기본 pen/marker의 이동·획 전체 삭제·새 pen 추가만 시험한다. 부분 삭제·마스크·텍스트·이미지·동기화·제품용 다른 플랫폼 앱은 포함하지 않는다.
- 압력·기울기·secondaryScale·seed는 보존하되 PencilKit 브러시의 픽셀 단위 동일성을 선언하지 않는다. 표현하지 못하는 문서는 편집·저장을 차단해 조용한 손실을 막는다.

## Review Focus

- 같은 모양의 서로 다른 획: ID를 기준으로 수정하고 다른 획을 유지해야 한다(작업 2/4).
- nonidentity transform와 다양한 width/height: 이동이 화면 배율에 묶이지 않고 document pt를 사용해야 한다(작업 2/3).
- 비표준 속성·미래 schema: 인식하지 못한 내용을 제거한 새 파일을 저장하면 안 된다(작업 1/2).
- PDF 페이지 매핑/비필기 metadata: 편집 후 자산 정보·페이지 ID·회전/crop이 그대로여야 한다(작업 2/4).
- 역방향 재인코딩: 삭제 획은 되살아나지 않고 수정하지 않은 획 ID와 style이 유지되어야 한다(작업 4).

## 파일 책임

- `docs/format/ink-v2.md`: 현재 필기 계약, 지원 범위, 수치·ID·transform 규칙.
- `Packages/MiNoteCore/Tests/MiNoteCoreTests/Fixtures/PortableInk/`: 실제 PencilKit에서 생성한 입력 JSON, JS로 편집한 기대 JSON, 변경 manifest. 테스트용 PDF fixture는 기존 `PDFFixture`를 재사용한다.
- `Packages/MiNoteCore/Package.swift`, `MiNote.xcodeproj/project.pbxproj`: 같은 fixture 디렉터리를 각 test bundle의 리소스로 등록한다. simulator에서 개발 Mac의 절대 소스 경로를 읽지 않는다.
- `Tools/PortableInk/document.mjs`: 지원 범위 검사, 데이터 복사, ID 기반 편집과 revision 갱신.
- `Tools/PortableInk/render.mjs`: Canvas에 문서 단위 획을 그리는 독립 렌더러.
- `Tools/PortableInk/index.html`, `app.mjs`: 파일 열기·페이지/획 선택·이동·삭제·pen 추가·JSON 다운로드를 위한 시험 UI.
- `Tools/PortableInk/document.test.mjs`, `roundtrip.mjs`: DOM 없는 계약/편집 테스트와 결정적 fixture 생성.
- `Packages/MiNoteCore/Tests/MiNoteCoreTests/PortableInkTests.swift`, `MiNoteTests/PortableInkTests.swift`: 양방향 JSON·어댑터·임시 저장소 검증.

### Task 1: 계약과 실제 입력 fixture

**Interfaces:** 기존 `DocumentCodec.encode(_:) -> Data`, `decode(_:) -> NoteDocument`, `InkAdapter.encode(_:preserving:) -> [InkStroke]`를 소비한다. 입력/기대 fixture와 필드 계약을 산출한다.

- [x] 기존 테스트 helper와 고정 UUID/시각을 사용해 pen/marker, 투명 색, 서로 다른 size/secondaryScale, 중복 모양의 다른 ID, 이동/회전/비등방 transform을 포함한 실제 PencilKit→JSON fixture를 만든다. schema v2 여러 페이지/PDF metadata도 포함한다. 테스트 앱의 Documents에 출력한 뒤 `simctl get_app_container`로 회수해 commit한다.
- [x] `PortableInkTests`에 fixture decode/re-encode 후 document/page/stroke ID·revision·points·style·asset metadata 유지 assertions를 작성한다.
- [x] `swift test --package-path Packages/MiNoteCore` 및 `xcodebuild ... -only-testing:MiNoteTests/PortableInkTests ... test`로 새 fixture 누락/계약 실패를 확인한다.
- [x] `docs/format/ink-v2.md`에 이미 구현된 수치 범위와 affine 적용 순서, PDF crop 좌표, 지원 불가 처리 규칙을 명시한다. fixture를 재생성 가능한 방법과 함께 저장하고 core `.copy("Fixtures/PortableInk")` 및 앱 test resources에 같은 디렉터리를 등록한다.
- [x] 두 테스트 통과를 확인하고 PROGRESS·로그·다음 작업을 기록한 뒤 커밋한다.

### Task 2: 독립 문서 편집 명령

**Interfaces:** `readDocument(text: string) -> object`, `applyEdit(document: object, command: object) -> object`, `writeDocument(document: object) -> string`. command는 `{kind:"translateStroke", pageID, strokeID, dx, dy}`, `{kind:"deleteStroke", pageID, strokeID}`, `{kind:"appendStroke", pageID, stroke}` 세 종류이며 DOM/PencilKit에 의존하지 않는다. ID는 UUID string, dx/dy는 number, stroke는 schema-v2 InkStroke object다.

- [ ] Node 테스트에 기본 왕복 보존, 선택 ID만 이동/삭제, 새 획 중복 ID 거부, 잘못된 페이지/획 ID 거부, 미래 버전/알 수 없는 도구/필드 편집 차단, 잘못된 수치·singular transform 거부를 작성한다.
- [ ] `node --test Tools/PortableInk/document.test.mjs`로 미구현 RED를 확인한다.
- [ ] `document.mjs`에 현재 v2 계약과 시험 범위 검사를 구현한다. 원본 object를 바꾸지 않고 새 object를 반환하며 성공한 편집당 revision을 한 번 증가시킨다. 새 획 ID는 UUID이고 document/page/surviving stroke ID는 유지한다.
- [ ] 이동은 document pt의 dx/dy를 stroke.transform.tx/ty에 더한다. point/style/seed/creationTime 및 다른 페이지와 PDF metadata는 그대로 둔다. revision 상한 초과는 거부한다.
- [ ] 동일 입력/manifest로 `roundtrip.mjs`가 기대 JSON을 결정적으로 생성하게 한다. 모든 계약 테스트 통과와 입력 원본 bytes 불변을 확인하고 기록·커밋한다.

### Task 3: 독립 렌더링과 시험 UI

**Interfaces:** `drawPage(context: CanvasRenderingContext2D, page: object, viewportScale: number) -> void`는 작업 2의 검증된 문서를 소비한다. 앱 UI는 세 편집 명령을 호출하며 다운로드 전에 `writeDocument`를 통과한다.

- [ ] renderer 테스트에 identity/translation/rotation/비등방 transform의 기대 문서 좌표, viewportScale 0.5/1/2일 때 역변환, size/색/alpha 적용을 작성하고 RED를 확인한다. 공유 수학 함수를 DOM 없이 검증한다.
- [ ] renderer는 기본 획을 점/구간의 size와 색으로 근사한다. marker alpha를 유지하고 seed/force/기울기 값은 JSON에 보존한다. 실제 PencilKit texture/곡선 차이는 기록한다.
- [ ] HTML 시험 UI에서 JSON 열기, 페이지/획 ID 선택, 수치 dx/dy 이동, 획 전체 삭제, 기본 pen 추가와 결과 다운로드를 연결한다. 파일은 로컬에서 처리한다. PDF metadata는 유지하며 PDF 배경 자체 렌더링은 이 시험 도구 범위 밖이다.
- [ ] 브라우저에서 fixture를 열고 이동/삭제/추가한 다운로드 JSON을 Node 검사로 확인한다. 빈 획 페이지, marker, 화면 확대도 확인하고 스크린샷·차이를 기록한 뒤 커밋한다.

### Task 4: iPad 역방향 편집·전체 검증

**Interfaces:** 작업 2가 생성한 기대 JSON을 `DocumentCodec.decode`, `InkAdapter.decode(_:) -> PKDrawing`, `EditorSession`과 임시 `DocumentStore`에 전달한다. 사용자 노트를 가져오기/교체하는 제품 UI는 추가하지 않는다.

- [ ] iPad 테스트에 JS에서 수정한 JSON을 decode→PencilKit→encode해 수정하지 않은 ID/style 유지, 이동 좌표 오차 0.01pt 이내, 삭제 ID 부재, 새 pen 편집 가능 assertions를 작성한다. PDF metadata는 core 왕복에서 함께 확인한다.
- [ ] PDF 문서는 원본 fixture bytes를 임시 저장소의 `PDFAsset.relativePath`에 함께 배치해 byteCount/geometry 검증을 통과시킨다. 복원된 drawing에 실제 획을 추가·삭제하고 저장·재열기를 검증한다. 현재 캔버스 undo/redo와도 연결해 JS의 삭제가 다시 나타나지 않는지 확인한다. 데이터 손실이나 속성 차이를 먼저 재현한 뒤 최소 어댑터 수정을 한다.
- [ ] Node 전체, `swift test`, iPadOS 18.6/26.4 `MiNote` 스킴 전체 테스트를 실행한다. 수치·ID 보존과 근사 외관 결과를 구분한다.
- [ ] 별도 에이전트 한 번 리뷰 후 중요한 문제를 수정하고 관련 테스트를 재실행한다. PROGRESS/Notion에 확인한 범위·차이·실기기 대기·다음 M1 시작점을 기록하고 커밋한다.

## 완료 판정

독립 도구에서 읽기만 하거나 PNG를 출력한 결과는 통과로 치지 않는다. 실제 JSON에서 이동/삭제/새 획 추가 후 iPad 재편집·저장·재열기가 통과해야 한다. 브러시 재현이 기대를 벗어나면 지원 범위를 더 좁히거나 어댑터·렌더러 변경을 별도 결정으로 기록하고, Android/Windows 호환 완료를 선언하지 않는다. M1의 노트/폴더/여러 PDF·페이지 관리, `.minote` 백업 UI, 임시 파일 정리는 이 단계 이후다.
