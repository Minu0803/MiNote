# MiNote 개발 진행 기록

## 현재 상태
- 완료 단계: **M0-A**, **M0-B**, **M0-C**, **M1-A**, **M1-B — 페이지·용지·책갈피·삭제 복원·다중 PDF**
- 작업 공간: `/Users/minwookim/Documents/GitHub/MiNote`
- 브랜치: `main`
- 시작 기준 커밋: `9695ab6`; 사전 모델·저장소 체크포인트: `dfa943d`
- M0-A 구현 커밋: `fedd789` (`feat(ipad): complete M0-A writing and local recovery`)
- main 통합: `origin/codex/ipad-foundation`에서 `b07e9e2`까지 fast-forward 병합. 이후 사용자가 GitHub Desktop에서 `a943a49`를 push했고 local/main, origin/main, 실제 원격 main 일치를 확인했다.
- 이전 실행: 2026-10-01 재개 요청에 따라 M0-B 전체를 구현·검증·별도 리뷰·Notion 기록까지 완료했다. 한 번에 한 개발 단위 원칙을 유지한다.
- M0-B 기준 커밋: `a943a49`; 구현/검증 커밋: `27f634c`, `4babcf6`, `991b481`, `0cd0139`, `26faf40`, `31a766c`.
- M0-B 종료 당시 코드 커밋: `31a766cbcfa570cf089eebe0ee52b2218dff3bf3`. 최종 인계 문서는 이 기록을 포함하는 마지막 `docs` 커밋에 있다(`git log -1 --oneline`으로 확인). 이번 6개 코드 커밋과 문서 커밋은 **로컬 main에만 있으며 push하지 않았다**.
- 이전 실행: **2026-10-03 M0-C 완료**. 시작 기준 `18843b0`; 시작 시 main clean, origin/main 추적 ref 일치(이번에는 원격 새 조회 없음). 코드 커밋 `0ef4587`, `f9fe764`, `da0a6f7`, `40aef65`, 최종 리뷰 수정 `28b9889e8b186771f163d6a98d551dabda5c2149`.
- M0-C 종료 당시 변경은 로컬 main에만 커밋했고 push하지 않았다. 현재 원격 상태를 의미하는 문장은 아니다. 최종 인계 문서 커밋은 `git log -1 --oneline`으로 확인한다.
- 이전 실행: **2026-10-03 M1-A 완료**. 기준 `fd4def6`; 마지막 코드 `d968701`. 시작 시 main clean, origin/main보다 로컬 6커밋 앞섬(원격 새 조회 없음). 모든 구현은 main에 커밋했고 push하지 않았다.
- 이전 단계: **M1-B 완료**. 기준 80d14c2, 마지막 기능 코드 1d67d9a, 테스트/체크포인트 fddbd66. main에서 직접 구현했고 push하지 않았다. 원격은 새 조회하지 않았으며 추적 ref와 현재 원격을 혼동하지 않는다.
- 현재 단계: **M1-C 편집 백업·복원/파일 정리 진행 중**. 기준19e10af, Task1 archive/Task2 복원/Task3 정리·삭제 복구 구현·검증 완료. 전체 단계/앱 UI/리뷰/Notion은 아직 미완료. 계획 `docs/superpowers/plans/2026-10-03-m1-c-backup-and-cleanup.md`.
- 다음 작업자가 할 첫 작업: Git 상태/HEAD 대조 → M1-C Task4 brief/앱 코드 읽기 → Files·PDFKit·export lease·백업 snapshot RED. 완료된 단계를 반복하지 않는다.
- 마지막 Notion 반영: **2026-10-03T11:50:06.629Z (20:50:06 KST)**; 재조회/내용 검증 11:50:59 UTC. M1-B 결과·기술 판단·검증/실패 이력·리뷰·제한·커밋·다음 M1-C 계획을 기존 내용을 보존하며 추가했다. 이전 M1-A 반영 06:02:45.909Z 기록도 아래에 보존한다.
- 최종 검증: **Node31/0, core60/0**, v2/v3 fixture check exit0, 18.6/26.4 각각 **app53/0 + 일반 UI5통과/fixture-only1skip/0실패**. 별도 seeded migration UI 양1/0/skip0과 원본 bytes 검증 통과. 로그/result와 리뷰 판단은 아래 M1-B 최종 절을 따른다.

## M0-B 완료 결과와 이전 재개 지점
- Files에서 PDF를 가져와 페이지별로 필기·확대·현재 페이지 undo/redo하고, 마지막 페이지와 획을 저장·재실행 후 복원한다. 기존 A4를 유지하며 한 PDF만 연결한다.
- 원본 PDF 자산을 수정하지 않고 필기 포함 새 PDF를 생성해 QuickLook/공유 시트로 전달한다. 필기는 최대 216dpi/4096px 이미지로 고정하고 양식/원본 주석/일부 링크의 영향을 안내한다.
- schema v2 migration과 raw v1 백업, asset-first 저장, revision 검사, asset 누락 오류 차단을 구현했다. 리뷰의 busy undo/redo와 zoom 해상도 문제를 회귀 테스트로 수정했다.
- 최신 검증: core **24/0**; iPadOS 18.6과 26.4 각각 앱 단위 **25/0**, UI **2/0**. 정확한 명령/로그/result는 이 문서 마지막의 ‘리뷰 수정 후 최종 검증’ 절을 따른다.
- 다음 작업자가 바로 할 첫 작업: Git 상태 대조 → `docs/superpowers/plans/2026-10-01-m0-c-portable-ink.md`, `MiNote/InkAdapter.swift`, `MiNoteCore` 모델/codec 읽기 → M0-C 작업 1의 실제 PencilKit→JSON fixture와 계약 테스트 작성. M0-B를 다시 구현하지 않는다.
- 이월 문제: 한 노트/한 PDF, 페이지 전환 시 undo reset, 보수 import 상한(100MB/500페이지/2000pt), 임시 export/orphan 자산 정리(M1), 객체 편집·검색(M2), 실기기/외부 뷰어/분할 화면/실제 큰 이미지 PDF(M3). 물리 Apple Pencil 지연·손바닥·발열은 **실기기 확인 대기**다.

## M0-A 완료 결과
- SwiftUI·UIKit·PencilKit 앱과 Foundation 전용 `MiNoteCore` Swift Package를 구성했다. 외부 라이브러리는 없다.
- A4 한 페이지에 펜·형광펜·획 지우개, 색상·두께 조절, 실행 취소·다시 실행, 손가락 입력 전환, 확대·스크롤을 구현했다.
- 획의 제어점, 시간, 압력, 크기, 불투명도, 기울기, 색상, 도구, 변환 정보, PencilKit seed와 ID를 플랫폼 독립 JSON 문서에 보존한다.
- 편집 후 자동 저장, 최신 리비전 검사, 원자 교체, 직전 정상본 백업, 오류 표시·재시도를 구현했다. 손상되거나 지원하지 않는 스키마는 빈 문서로 덮어쓰지 않는다.
- 앱은 하나의 편집 창으로 제한했다. M0-A 저장소가 단일 actor/파일을 전제로 하고 있어, 별도 앱 창이 같은 리비전을 읽고 마지막 저장이 앞선 편집을 덮어쓸 가능성을 제거한다.
- 코드 리뷰 후 JSON 손상·문서 무결성 오류일 때만 백업 복구를 허용했다. 실제 파일 읽기·접근 오류는 그대로 전파하고 원본과 백업을 보존한다.
- PencilKit의 기본 획에서 실제로 쓰이는 `secondaryScale`을 공통 모델에 추가했다. 기존 schema v1 문서에 값이 없으면 기본값 1로 읽는다.

## M0-A 검증 근거 (이전 기록)
- `swift test --package-path Packages/MiNoteCore`: 16개 테스트, 0 실패. main 체크아웃 로그: `/private/tmp/minote-main-core.log`.
- iPad Pro 11 M4 / iPadOS 18.6, main 체크아웃 `xcodebuild ... test`: 앱 단위 테스트 11개와 UI 테스트 1개 통과. 로그: `/private/tmp/minote-main18.log`; 결과: `/private/tmp/minote-main18.xcresult`.
- iPad Pro 11 M5 / iPadOS 26.4, main 체크아웃 전체 테스트: 앱 단위 테스트 11개와 UI 테스트 1개 통과. 로그: `/private/tmp/minote-main26.log`; 결과: `/private/tmp/minote-main26.xcresult`.
- UI 테스트에서 획 입력, undo/redo, `저장 완료`, 앱 재실행 후 복원을 확인했다.
- 빌드된 `MiNote.app/Info.plist`에서 `UIApplicationSupportsMultipleScenes = false`, `CFBundleExecutable = MiNote`를 확인했다. 빌드 로그: `/private/tmp/minote-scene-review-build3.log`.
- `git diff --check` 통과.
- 별도 리뷰의 데이터 손실 우려 2건을 각각 회귀 테스트·실제 빌드 설정 검증으로 수정했다. 저장소는 파일 없음만 따로 판별하며, 손상 JSON만 백업 복구하고 접근 오류·디렉터리 경로는 그대로 보존한다.
- 미실행 검증: 실기기 Apple Pencil 지연, 손바닥 입력 거부, 발열. 물리 iPad에서 확인해야 한다.

## M0-A 종료 시 다음 재개 지점 (이전 기록)
- M0-A 코드와 검증 근거는 `fedd789`에 있다. 최종 테스트 로그는 위 검증 항목을 따른다.
- M0-B 실행 계획이 저장소와 Notion에 있다. 다음 작업에서는 PDFKit overlay API를 iOS 18에서 확인하고, 회전·crop box를 포함한 좌표 fixture를 만드는 기술 검증부터 시작한다.
- M0-B 구현은 별도 단계로 유지한다. PDF 페이지 매핑 검증 전에 문서 모델이나 캔버스 구조를 확정하지 않는다.
- 사용자는 이후 코딩을 모두 기본 저장소의 `main`에서 진행하도록 지정했다. 새 브랜치·worktree·PR을 만들지 않는다.

## 계속 적용할 규칙
- 재개 시 이 문서, Git 상태, 마지막 검증 로그를 대조하고 진행 중 변경을 먼저 확인한다.
- 장시간 작업 전과 작은 작업 직후 진행 상태를 갱신한다. 통과하지 않은 검증은 완료로 표시하지 않는다.
- 단계 종료마다 앱에서 작동하는 결과, 기술 결정, 테스트 근거, 제한, 다음 시작점을 Notion과 저장소에 기록한다.
- 원격 push·배포는 승인된 범위에 포함하지 않는다.

## Notion
- 마지막 반영: **2026-10-03 11:50:06 UTC (20:50:06 KST)**, `2026-10-03T11:50:06.629Z`. Async update succeeded 뒤 11:50:59 UTC 재조회: M1-B heading 1개, 이전 본문 전체 prefix 보존, Node31/core60/app53/UI5·fddbd66·M1-C 미구현을 확인했다.
- 문서: [MiNote 제품 계획서](https://app.notion.com/p/3e76538f55f68051a2fad6f22562bd3d?pvs=204)
- 이전 M0-C 반영: **2026-10-03 05:05:01 UTC (14:05:01 KST)**. Notion async update succeeded 후 재조회했다(`page_last_edited_at = 2026-10-03T05:05:01.427Z`). M0-C 실제 왕복·25/26/32+2 테스트·리뷰 2건 수정·제한·코드 커밋·M1-A 계획을 확인했다. 기존 M0-A/B 기록을 유지하고 마지막 문장에 결과 섹션을 추가했다.
- M0-B 반영: 2026-10-01 12:58:05 UTC (21:58:05 KST), `2026-10-01T12:58:05.280Z`.
- 이전 반영: 2026-09-26 09:33:38 UTC (18:33:38 KST), M0-A 결과와 M0-B 계획 요약.

## M0-B 실행 체크포인트 (2026-10-01)
- [x] 1: PDFKit·좌표·회전·crop 검증
- [x] 2: schema v2 마이그레이션과 안전한 PDF 자산 가져오기
- [x] 3: 페이지 이동·필기·자동 저장·복원
- [x] 4: 필기 포함 PDF 내보내기
- [x] 5: 양 시뮬레이터 전체 검증·별도 리뷰·Notion·기록
- 결정: 사용자 승인된 제품 설계/기존 M0-B 계획을 실행한다. main 직접 작업 지시가 격리 브랜치 절차보다 우선한다.
- 사전 검사: 1의 좌표가 2 페이지 크기/메타데이터, 3 화면, 4 출력에 공통으로 필요하다. 2 저장의 문서 리비전은 3 가져오기/페이지 편집에서도 같은 문서 ID로 이어간다. 4는 2 원본 자산을 읽되 수정하지 않는다.
- 환경: sandbox 내 simctl은 서비스 접근 권한 때문에 실패했다. 승인된 시뮬레이터 검증용 권한으로 다시 조회하여 18.6/26.4 기기를 확인했다.
- 다음 즉시 작업: 좌표 및 PDF fixture 테스트를 먼저 만들고 실패를 확인한다.

### M0-B 1A: 좌표 기초 검증
- `MiNote/PDFGeometry.swift`, `MiNoteTests/PDFFixture.swift`, `PDFGeometryTests.swift`: 비영점 media/crop 원점과 0/90/180/270도 회전 fixture의 변환·역변환을 검증했다.
- 실패 근거: `/private/tmp/minote-m0b-geometry-red.log` (어댑터 없음). 첫 실행의 8 좌표 실패는 PDFKit이 fixture 재저장 시 원점을 정규화했기 때문이었다. `/private/tmp/minote-m0b-geometry-diagnose.log`에서 실제 bounds를 확인해 raw PDF fixture로 교체했다.
- 통과: `xcodebuild ... -only-testing:MiNoteTests/PDFGeometryTests ... test`, iPadOS 18.6, 1 테스트/0 실패, `/private/tmp/minote-m0b-geometry-green2.log`.
- 결정: PDFKit overlay API(iOS 16+)는 조사했다. M0-B는 기존 `PageZoomHost`에서 PDF 배경+한 개 PencilKit 캔버스와 명시적 페이지 이동을 사용한다. 회전된 crop box 크기를 문서 크기로 쓰므로 PDFView의 overlay 재생성·gesture 경쟁을 피하면서 화면상의 같은 좌표를 유지한다. 페이지 수와 무관하게 화면 캔버스는 하나다. 실제 입력/zoom/화면 회전 검증은 단계 3/5에서 수행한다.
- 다음: schema v2 migration/여러 페이지 테스트의 실제 실패를 확인했다 (`/private/tmp/minote-m0b-core-red2.log`). Foundation 모델을 확장한다. 아직 미커밋인 core 테스트는 이 다음 작업에 해당한다.

### M0-B 2A: Foundation 문서·자산 저장 완료
- schema v2는 여러 페이지, `PDFAsset` UUID/상대 경로/파일명/페이지 수/바이트 수/가져온 시점, 페이지별 media/crop/rotation/index를 보존한다. v1 A4는 ID·리비전·획을 유지해 v2로 읽고, 저장 시 원본 v1 바이트를 backup으로 먼저 보존한다.
- `DocumentStore.attachPDF`는 기대 리비전을 검사하고 PDF 자산을 먼저 원자 저장한 후 JSON을 갱신한다. 기존 A4 페이지는 남고 PDF 페이지를 추가한다. 현재 노트에 한 PDF만 연결하며 후속 가져오기로 원본·필기를 교체하지 않는다. 여러 PDF/노트 선택은 M1 범위다.
- 자산 없음·크기 불일치는 백업의 빈 노트로 자동 복구하지 않고 오류로 차단한다. 가져오기 실패 때 기존 JSON을 유지하며 중단 후 orphan 자산은 안전하게 남는다(정리는 M1).
- 검증: `swift test --package-path Packages/MiNoteCore` 24 테스트/0 실패, `/private/tmp/minote-m0b-core-green.log`. 마이그레이션/다중 페이지 실제 RED는 `minote-m0b-core-red2.log`, PDF 자산 API 누락 RED는 `minote-m0b-assets-red2.log`. 중간 구문 오류는 수정 후 전체 통과했다.
- 다음: 앱에서 security-scoped 파일 조정·PDF 검증·페이지 세션 연결을 구현한다. 잠금/잘림/미지원 크기 및 세션 실패 보존을 테스트한다. PDF 파일 앱 흐름은 아직 미구현이다.

### M0-B 2B/3A: 가져오기·페이지 세션
- `PDFImporter` actor는 security scope를 복사 완료까지 유지하고 NSFileCoordinator로 원본을 읽는다. 암호 잠금, PDF header/EOF 없음, 빈 PDF, 미지원 페이지를 거부한다. PDFKit 객체는 actor 안에 두고 portable metadata/bytes만 넘긴다.
- `EditorSession`은 여러 페이지의 drawing, 페이지마다 독립 획 ID 이력, 마지막 페이지 ID, 기존 문서 보존 가져오기 오류를 처리한다. 동일 획을 다른 페이지에 그릴 때 global history가 ID를 재사용한 실제 RED를 확인했고 페이지별 이력으로 수정했다.
- 검증: iPadOS 18.6 `xcodebuild ... -only-testing:MiNoteTests ... test` 앱 단위 16 테스트/0 실패 (`/private/tmp/minote-m0b-import-green3.log`). 잠금/잘림, 원본 bytes/geometry, 실패 후 현재 필기, 페이지 왕복·재실행, 동일 모양 획의 독립 ID를 검증했다.
- 제한은 임시 보수값 100MB/500페이지/한 변 2,000pt다. 단계 5에서 여러 페이지의 화면 뷰/bitmap 메모리 상한을 측정하고 근거를 남긴다. 실제 대형 PDF·실기기 성능은 아직 미검증이다.
- 다음 즉시 작업: `PDFCanvasTests` RED 확인 → PDF 배경 렌더러, 가변 페이지 크기 zoom host, 페이지 이동과 파일 가져오기 UI. 현재 canvas 테스트는 이 작업의 미커밋 변경이다.

### M0-B 3B/4 작업 중 체크포인트
- PDF 배경은 PDFKit crop-box 렌더링과 top-left 변환을 사용한다. 4 회전의 red/green corner pixel이 기대 위치에 있으며 zoom 후 viewport 변경에도 canvas.bounds가 문서 크기를 유지한다. 앱 단위 18/0 (`minote-m0b-canvas-green.log`).
- 파일 선택/페이지 이동 UI를 연결했다. UI 테스트에서 import 버튼은 존재하나 picker 검색창이 나타나지 않아 **아직 UI 검증 실패**다. `minote-m0b-ui-green2.log`, `minote-m0b-picker-diagnose.log`가 실제 실패 근거이며 후자에 접근성 트리가 있다. 원인 조사 후 재검증한다.
- 단계 4 출력 테스트를 작성했다. 다음: export API 없는 RED를 확인하고 원본 geometry/텍스트/획 위치 검증을 통과시킨 뒤 picker UI 문제로 복귀한다.
- 출력 spike 판단: PDFKit burnInAnnotations는 nonzero MediaBox 원점을 (0,0)으로 정규화한다. custom annotation은 원본 content의 원점 이동을 별도로 적용해야 한다 (`minote-m0b-export-diagnose.log`, 4 회전 blue bbox로 확인). 출력은 media 크기/rotation/crop의 media 대비 위치와 **보이는 페이지 좌표**를 보존하는 것으로 판단했다. raw box 원점까지 동일한 출력은 public PDFKit writer로 보장하지 않는다. PDF 원본과 편집 모델은 전혀 바꾸지 않는다.
- 출력 판단: PencilKit 공개 API는 vector drawing export를 제공하지 않아 획만 최대 216dpi/한 변 4096px 이미지로 합성한다. 원본 PDF 텍스트/벡터 유지와 정확한 필기 모양을 우선한다. 확대 시 필기 해상도 및 원본 annotation/form의 고정화는 앱 안내·Notion·완료 보고에 남긴다.

### M0-B 4A: PDF 합성 출력 기반 완료
- 출력 writer의 원점 이동을 custom annotation에 적용하여 4 회전 모두 canonical (130,120) 획 pixel이 유지된다. 원본 bytes, media 크기/crop 상대 위치/rotation, 검색 가능한 text, 출력 실패 시 원본·기존 대상 보존을 검증했다.
- `xcodebuild ... -only-testing:MiNoteTests ... test` 20 앱 단위 테스트/0 실패 (`/private/tmp/minote-m0b-export-green2.log`). 공유 UI는 아직 연결 전이다.
- 내보내기는 PDFKit writer를 사용하고 원본 파일을 건드리지 않는다. 텍스트/벡터 원본 위에 최대 216dpi, max 4096px의 PencilKit 필기 이미지를 고정 합성한다. vector ink는 후속 엔진 검증에서 검토한다.
- 다음: picker 고정 루트 컨테이너 수정의 UI 테스트 결과 확인. 공유 시트 연결·백그라운드 출력·메모리 검증·전체 리뷰/최종 검증으로 이어간다.
- Picker 원인 확인: 실제 화면에는 파일 선택기가 표시되고 검색은 버튼 뒤에 숨겨져 있었다. 화면/런타임/뒤늦은 AX 트리로 확인했다 (`minote-picker-wait-screen.png`, `minote-m0b-picker-wait.log`). 테스트는 존재하지 않는 검색창을 기다리고 있었다. 시스템 파일 선택기에서 나의 iPad → MiNote → fixture를 선택하는 경로로 변경했다. 다음 실행은 테스트 runner bootstrap crash로 UI 자체가 시작되지 않았으므로 아직 통과 아님 (`minote-m0b-picker-browse.log`).

### M0-B 3/4 기능 연결 완료, 단계 5 검증 중
- iPadOS 18.6 전체 앱 검증: **단위 23/0, UI 2/0** (`/private/tmp/minote-m0b18-full.log`, `/private/tmp/minote-m0b18-full.xcresult`). PDF 입력 undo/redo, 확대, 화면 회전, 페이지 이동·relaunch, QuickLook PDF 미리보기와 실제 공유 시트의 파일 저장 항목까지 확인했다.
- 500페이지 sequential render의 simulator phys_footprint는 85,150,432 → 93,424,400 bytes, 증가 8,273,968 bytes (약 7.9MiB). 한 페이지 뷰/캔버스를 재사용하므로 500개의 bitmap을 보관하지 않는다. fixture는 텍스트·벡터 소형 페이지이며 이미지가 많은 실제 100MB PDF의 성능을 입증하는 수치는 아니다. 한 변 2,000pt/100MB/500페이지 보수 상한을 유지하고 실기기/다양한 큰 자료는 M3 검증에 남긴다.
- PDF 출력은 별도 작업에서 수행한다. UI 없는 InkAdapter 변환은 MainActor 제한을 제거했고 background export도 pixel/geometry 테스트를 통과했다. 공유 전 최신 revision을 저장하며 출력 중 편집을 잠근다.
- 중복 import의 실제 RED에서 늦은 요청이 stale revision 오류로 끝났다. 작업 잠금을 첫 await 전에 획득하고 문서/asset/마지막 페이지 선택을 한 트랜잭션으로 완료하도록 수정했다. commit 후 자산 reopen 실패는 오래된 메모리 문서 편집을 차단하고 authoritative load를 재시도한다.
- 아직 남음: iPadOS 26.4 전체 검증, 최신 core 전체 테스트, 한 차례 별도 코드 리뷰, Notion 결과 반영 및 최종 기록. UI 재실행 테스트는 기존 fixture 노트가 있으면 재가져오기를 건너뛰며, 첫 실제 Files import 통과 근거는 `minote-m0b-flow-green.log`에 있다.
- 최신 core 전체 검증: `swift test --package-path Packages/MiNoteCore`, 24 테스트/0 실패 (`/private/tmp/minote-m0b-core-final.log`). 26.4 전체 테스트는 현재 실행 중이다. 18.6 UI/출력 기능과 core 변경을 커밋한 후 별도 리뷰를 진행한다.
- iPadOS 26.4 전체 검증도 완료: 단위 **23/0**, UI **2/0** (`/private/tmp/minote-m0b26-full.log`, `/private/tmp/minote-m0b26-full.xcresult`). 첫 Files import와 공유 항목을 포함했다. 500페이지 소형 vector fixture footprint는 67,619,144 → 79,104,376 bytes, 증가 11,485,232 bytes (약 11.0MiB). 실기기·실제 이미지 PDF 성능과 구분한다.
- 코드 리뷰: 별도 `/root/m0b_code_review`가 `a943a49..26faf40` 범위를 읽기 전용으로 검토 중이다. 구현상 변경은 리뷰 결과를 받은 후 필요한 회귀 테스트와 함께 수행한다.

### M0-B 리뷰 결과와 수정 시작점
- 별도 리뷰에서 Critical은 없었다. Important/P2 2건: (1) import/export 중 header Undo/Redo가 잠기지 않아 세션과 실제 캔버스 이력이 엇갈림, (2) PDF 배경이 zoom 종료 후 낮은 bitmap 배율 그대로여서 확대 가독성 저하. 둘 다 실제 사용자 동작 문제로 받아들이고 회귀 RED→GREEN으로 수정한다.
- Minor/P3: UUID별 내보내기 임시 파일 정리 수명주기 없음. 단계 5의 이번 중요한 수정 범위와 분리해 M1 파일/복구 관리 작업으로 이월한다. 공유가 끝나기 전 파일을 삭제하지 않도록 소비자 수명주기를 설계해야 한다.
- 리뷰가 제외한 판단: 실기기 Pencil·발열 및 이미지가 많은 실제 큰 PDF는 M3에서 검증한다. ink 이미지 출력/원점 정규화/양식·링크 영향은 이미 기록·UI 안내한 의도적 범위다. 페이지 전환 때 canvas의 Undo 이력은 새로 시작하며 현재 페이지의 undo/redo만 보장한다. Background drawing은 작업별 객체를 소유하고 현재 검증을 통과했다.
- 다음: 작업 잠금의 명령 경계 방어와 zoom 후 4096px 안에서의 PDF 재렌더링 테스트를 만들고 실패를 확인한다. 수정 후 두 시뮬레이터 앱 전체 검증을 다시 수행한다.
- 회귀 RED 확인: 새 명령 인터페이스가 없어 최초 빌드 실패(`minote-m0b-review-red.log`), 인터페이스만 연결한 실제 동작 테스트에서 busy undo/redo와 zoom 해상도 모두 실패했다(`minote-m0b-review-behavior-red.log`, 2 테스트/4 assertions 실패).
- P2 명령 수정: 헤더 버튼과 `CanvasReference.undo(in:)`/`redo(in:)` 양쪽에서 `session.isProcessing`을 검사한다. 실제 500페이지 import/export 작업 중 호출하는 회귀 테스트 **1/0** (`minote-m0b-command-green.log`).
- P2 확대 수정 진행: pinch 중에는 기존 backing을 쓰고 zoom 종료/viewport layout에서 PDF 해상도를 갱신한다. 가장 긴 변을 4096px로 제한하며 문서 좌표와 canvas.bounds는 바꾸지 않는다. PDFCanvasTests를 실행 중이며 아직 최종 통과 기록 전이다.
- P2 확대 회귀 및 배경·zoom·500페이지 테스트 **4/0** (`minote-m0b-zoom-green.log`). 배경 해상도를 늘린 후 이 소형 fixture의 footprint 증가 16,957,464 bytes. 현재 18.6/26.4 앱 전체를 재검증 중이다 (`minote-m0b18-review-final.log`, `minote-m0b26-review-final.log`). 다음은 실제 전체 결과 확인 → 단계 문서/Notion → 최종 커밋이다.

### M0-B 리뷰 수정 후 최종 검증 완료
- 18.6 전체 **앱 단위 25/0, UI 2/0**, xcodebuild exit 0 / TEST SUCCEEDED. 로그 `/private/tmp/minote-m0b18-review-final.log`, result `/private/tmp/minote-m0b18-review-final.xcresult`.
- 26.4 전체 **앱 단위 25/0, UI 2/0**, xcodebuild exit 0 / TEST SUCCEEDED. 로그 `/private/tmp/minote-m0b26-review-final.log`, result `/private/tmp/minote-m0b26-review-final.xcresult`.
- 공통 패키지는 마지막 core 변경 이후 **24/0** (`minote-m0b-core-final.log`). 리뷰 수정은 앱/테스트에만 있었으므로 core는 반복 실행하지 않았다.
- 최종 500페이지 fixture footprint: 18.6은 95,095,544 → 113,560,312 bytes (증가 18,464,768; 약 17.6MiB), 26.4는 64,948,576 → 87,067,000 bytes (증가 22,118,424; 약 21.1MiB). zoom 해상도 수정 후의 현재 측정이며 앞선 수치보다 우선한다. 소형 벡터 PDF 한 종류이고 GPU/실기기/큰 이미지 PDF의 상한을 보장하지 않는다.
- 최종 UI 결과에서 내보내기 QuickLook 화면을 추출해 실제 획·5페이지 표시·안내 문구·공유 버튼을 시각 확인했다. 화면 파일은 `docs/assets/m0b-export-preview.png`로 보존한다. 실제 시스템 Files 가져오기는 앞선 fresh 실행 로그에 있으며 최종 UI 재실행은 기존 노트에 필기를 추가해 복원을 확인했다.
- 마지막 실행 명령:
  `xcodebuild -project MiNote.xcodeproj -scheme MiNote -destination 'platform=iOS Simulator,id=7964CDF4-782A-44C2-BC51-1176AF6C67AB' -derivedDataPath /private/tmp/minote-m0b18 -resultBundlePath /private/tmp/minote-m0b18-review-final.xcresult -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO test`
  26.4는 device `423D4FF6-C678-45F9-9D3E-CB886EE82462`, derivedData `/private/tmp/minote-m0b26`, result `/private/tmp/minote-m0b26-review-final.xcresult`로 실행했다.
- 검증 완료 시점의 미커밋 변경은 P2 캔버스 명령/zoom 수정과 회귀 테스트/이 기록이었다. 이를 `31a766c`로 커밋했다. 이후 README/AGENTS/단계 계획/다음 M0-C 계획과 최종 화면을 정리했고 Notion 결과·동기화 시점을 위에 반영했다. 마지막 코드 변경 이후 테스트 대상 코드는 바꾸지 않았다.
- 완료 인계: 현재 코드 작업은 없고, 최종 기록/계획/스크린샷을 문서 커밋으로 보존한다. 재개 시 `git status --short --branch`로 미커밋 변경을 먼저 대조한다. `git diff --check`는 최종 문서에도 적용한다. M0-C 구현은 이번 실행에 포함하지 않았다.

## M0-C 실행 체크포인트 — 2026-10-03
- [x] 1: 실제 PencilKit fixture·필기 계약·공통 리소스
- [x] 2: 독립 JSON 검증·ID 편집·결정적 왕복 출력
- [ ] 3: Canvas 시험 UI·브라우저 다운로드 검증
- [x] 4: iPad 역방향 편집·양 OS 전체 검증·리뷰·Notion
- 시작: 계획·관련 codec/store/PencilKit 테스트·Git 상태를 읽었다. Node v23.11.0은 `/opt/homebrew/bin/node`; 기존 18.6/26.4 iPad simulator를 확인했다. 작업은 사용자 지정 main에서 직접 수행한다.
- 판단: 기존 승인된 설계/계획을 실행하고 새 승인 단계를 만들지 않는다. scratch와 durable 기록 모두 보존한다. task 추출기가 영어 제목을 요구해 계획의 작업 제목만 Task N으로 정리했다.
- 다음 즉시 작업: fixture 없는 RED → 실제 PencilKit JSON 생성/회수 → 양 test bundle 등록 → core/app 관련 테스트 GREEN. 아직 M0-C 완료 기능은 없다.

### M0-C Task 1 완료
- 실제 PencilKit pen/marker, 크기·압력·불투명도·기울기·secondaryScale와 transform, 같은 모양/다른 ID를 포함한 고정 JSON/PDF fixture를 만들었다. 두 test bundle이 동일 resource를 읽는다. `docs/format/ink-v2.md`에 현재 계약과 시험 범위를 기록했다.
- RED: core fixture URL 없음(`minote-m0c-fixture-core-red.log`). 앱 첫 빌드는 복잡한 식의 type-check timeout이며 분리 후 실제 누락 fixture와 원본 기울기 정규화/ID 손실 RED를 확인했다(`minote-m0c-fixture-app-red2.log`).
- 원인: altitude 1.1000008518440252가 PKStrokePoint 재구성 후 1.1000248206595709로 바뀌어 strict fingerprint가 변경으로 판단했다. `InkAdapter`는 원본 fingerprint를 우선하고 실제 재구성 결과를 lazy 보조 fingerprint로 비교해 기존 ID와 원본 전체 속성을 보존한다. epsilon으로 임의 변경을 숨기지 않으며 같은 ID를 두 번 사용하지 않는다.
- GREEN: core 전체 **25/0** (`/private/tmp/minote-m0c-fixture-core-green.log`), 18.6 앱 단위 전체 **27/0** (`/private/tmp/minote-m0c-fixture-app-green2.log`), 두 명령 exit 0. 관련 8개 실행은 fixture 회수 전 URL 없음 1실패였으며 이를 전체 통과로 기록하지 않는다.
- fixture 회수 판단: test 후 simulator가 Shutdown이라 `simctl get_app_container`가 실패했다. 생성 전용 `PortableInkGenerated` 디렉터리만 검색해 JSON/PDF를 회수했다. Xcode 재설치는 app container UUID를 바꾸므로 하드코딩 경로를 쓰지 않는다. 사용자 노트는 읽거나 바꾸지 않았다.
- 다음: Task 2의 Node 계약/ID 편집 RED를 확인하고 JS 독립 명령을 구현한다. browser/iPad 역방향/26.4/실기기 검증은 아직 완료 아님.

### M0-C Task 2 완료
- DOM/PencilKit 없는 `Tools/PortableInk/document.mjs`가 v2 문서를 검사하고 ID 기반 이동/삭제/새 pen 추가를 원본 변경 없이 수행한다. 성공한 명령당 revision +1이며 fixture 40→43 결과를 JS가 직접 생성했다.
- Node RED: 문서 module 없음(`minote-m0c-document-red.log`). GREEN: `node --test Tools/PortableInk/document.test.mjs` **11/0** (`/private/tmp/minote-m0c-document-green.log`). 도구/필드/미래 schema, UUID 대소문자/중복, geometry/style/time/PDF mapping, invalid commands, 원본 불변을 확인했다. `node Tools/PortableInk/roundtrip.mjs --check`도 exit 0.
- 판단: JS는 safe integer로 정확히 표현되는 revision/정수 metadata만 편집한다. Swift Int64 상한까지 지원하는 척하며 반올림하지 않고 거부한다. 도구의 지원 범위가 iPad보다 좁다는 점을 계약에 명시했다. null secondaryScale/미지 필드를 제거한 JSON 저장도 허용하지 않는다.
- 다음: renderer 좌표·size/alpha 테스트 RED → Canvas UI → 실제 브라우저 편집/다운로드 검증. iPad의 edited.json 역방향 테스트는 Task 4다.

### M0-C Task 3 완료 / Task 4 시작 체크포인트
- Canvas 시험 도구에서 샘플/JSON 열기, 페이지/획 선택, ID 이동·삭제, 드래그 새 pen, 확대, JSON 출력을 구현했다. 좌표 변환/opacity/secondaryScale와 오류 시 현재 문서 보존 테스트를 추가했다.
- RED: renderer/editor module 없음(`minote-m0c-ui-red.log`). GREEN: `node --test Tools/PortableInk/*.test.mjs` **17/0** (`/private/tmp/minote-m0c-ui-green.log`); `node --check Tools/PortableInk/app.mjs` exit 0.
- 실제 브라우저에서 101을 (12,-8) 이동, 103만 삭제, 새 pen 드래그하여 revision 40→43, 4획을 확인했다. PDF 90도 빈 페이지 선택 시 0획/편집 버튼 비활성도 확인했다. 실제 UI 출력 텍스트를 `browser-edited.json`으로 보존했다. 자동 Node 생성 `edited.json`과 별도로 iPad가 모두 읽는다. 화면 증거 `/private/tmp/minote-m0c-browser.jpg`.
- 제한/판단: Codex IAB의 download 이벤트가 두 번 timeout했고 파일 저장 완료는 확인하지 못했다. anchor를 DOM에 연결하고 readonly JSON 출력 대안을 제공했다. 버튼은 저장 요청만 안내한다. 실제 UI 출력이 Swift로 전달되므로 왕복 데이터 검증을 계속하고, 일반 브라우저의 native 다운로드는 미검증으로 남긴다. 실패를 통과로 기록하지 않는다.
- 서버: 저장소 루트 `python3 -m http.server 8765 --bind 127.0.0.1`, 실행 중 session 60760. 테스트 종료 시 이 서버만 정리한다.
- 다음 즉시 작업: 공통 codec의 JS/browser 결과 검증 → 실제 PKDrawing 추가/삭제·Canvas undo/redo·임시 저장소 재열기. 전체 양 OS/별도 리뷰/Notion은 아직 완료 아님.

### M0-C Task 4 검증 진행
- core 전체 **26/0** (`/private/tmp/minote-m0c-core-final.log`). CLI와 실제 browser fixture의 revision/ID/전체 미수정 속성·PDF metadata를 확인했다.
- 18.6 첫 전체 실행은 앱 **29개 중 4 assertion 실패**, UI **2/0**였다(`minote-m0c18-final.log`, exit 65). 이를 성공으로 기록하지 않는다.
- 원인 진단: 시험용 UndoManager가 같은 run-loop의 두 입력을 implicit event group으로 묶어 undo가 둘 다 취소했다. 집중 진단에서 groupingLevel 1을 확인했다(`minote-m0c-undo-diagnose.log`, exit 65). 시험 입력만 groupsByEvent=false로 바꾸어 각 명시적 그룹을 독립시켰다. 실제 앱 undo 동작 변경은 없다.
- 검증 범위: bundled JS/browser 문서 → 실제 PKDrawing → 실제 CanvasReference/Coordinator와 UndoManager의 명시적 snapshot 등록 → 추가·삭제/undo/redo → 임시 DocumentStore/PDF 자산 → 세션 재열기다. snapshot 등록은 programmatic test 입력이며 Pencil gesture와 구분한다. 실제 gesture UI 검증은 기존 UI 테스트에서 수행한다.
- 현재 양 OS 전체 실행 중: `minote-m0c18-green.log` / `minote-m0c26-green.log`, 결과가 확정되기 전 완료로 표시하지 않는다. 작은 transform 0.0001pt 변경이 정규화 비교에 숨지 않는 테스트도 포함한다.
- 코드 체크포인트: Task 1 `0ef4587`, Task 2 `f9fe764`, Task 3 `da0a6f7`; Task 4 미커밋. 다음: 양 실행 exit/result 확인 → 변경 커밋 → fresh reviewer 한 번 → 중요 문제 수정 → Notion/인계.

### M0-C Task 4 리뷰 전 GREEN
- Node **17/0**, core **26/0**, iPadOS 18.6/26.4 각각 앱 단위 **29/0**, UI **2/0**. 각 전체 명령 exit 0이며 양 Xcode 로그 TEST SUCCEEDED를 확인했다. `git diff --check` 통과.
- 명령: `node --test Tools/PortableInk/*.test.mjs`; `node Tools/PortableInk/roundtrip.mjs --check`; `swift test --package-path Packages/MiNoteCore`; `xcodebuild -project MiNote.xcodeproj -scheme MiNote -destination 'platform=iOS Simulator,id=<기기 UUID>' -derivedDataPath /private/tmp/minote-m0c-dd<18|26> -resultBundlePath /private/tmp/minote-m0c<18|26>-green.xcresult test`.
- 기기: 18.6 `7964CDF4-782A-44C2-BC51-1176AF6C67AB`; 26.4 `423D4FF6-C678-45F9-9D3E-CB886EE82462`. 로그: `/private/tmp/minote-m0c-ui-final.log`, `minote-m0c-core-final.log`, `minote-m0c18-green.log`, `minote-m0c26-green.log`.
- 아직 별도 리뷰/Notion/최종 인계는 미완료다. 실기기와 일반 브라우저 native download는 미검증이다. 다음 작업은 fresh reviewer 한 번이며 중요한 문제는 실제 재현 후 수정한다.

### M0-C 별도 리뷰와 수정 (2026-10-03)
- fresh `m0c_code_review` 한 번, 범위 `18843b0..40aef65`. Critical 없음, Important 2건. reviewer는 읽기 전용이며 구현/추가 reviewer를 dispatch하지 않았다.
- 1: raw fingerprint가 다른 획의 재구성 fingerprint와 같을 때 ID와 원본 point data가 서로 바뀌었다. 실제 iPad fixture A/재구성 B로 RED를 확인했다(`minote-m0c-review-ink-red.log`, exit 65). 원본/정규화 후보 전체의 순서를 비교하여 earliest/latest 대응이 같은 경우만 원본 ID/값을 보존한다. 여러 대응/지원하지 않는 재정렬이면 명시적 오류다. 0.0001pt 실제 이동은 숨기지 않는다.
- 같은 모양 중 첫 획 삭제도 원래 순서로 surviving ID를 확인한다. 완전히 같은 인접 획 한 개만 남아 어느 ID인지 알 수 없을 때는 저장을 차단하고 화면/기존 JSON을 보존하는 세션 테스트를 추가했다. ‘모든 중복에서 ID 보존’으로 주장하지 않는다. 정규화는 이제 전체 후보를 재구성하므로 복잡한 페이지 비용은 M3 측정 대상이다.
- 2: pointerup이 시작 페이지 대신 현재 페이지에 저장하는 실제 handler 오류. owner/시작 scale을 입력에 연결하고 open/page/zoom/mode-exit/lost-capture 때 active pointer만 취소·release한다. 실제 이전 `app.mjs`로 handler RED 4개 모두 실패를 확인하고 현 코드 GREEN을 확인했다(`minote-m0c-review-handlers-red.log`, exit 1; `minote-m0c-review-node-green.log`, exit 0). Node test는 DOM/canvas 경계만 대체하고 실제 앱 handler를 실행한다.
- 집중 iPad GREEN: PortableInkTests 6/0(`minote-m0c-review-ink-green.log`). 이후 모호한 ID 실패 시 디스크 보존 테스트를 추가했다.
- 리뷰 이후 최종 전체: Node **25/0**, core **26/0**(core 변경 없음), 18.6/26.4 각각 앱 **32/0**, UI **2/0**; 양 명령 exit 0 / TEST SUCCEEDED. 로그 `/private/tmp/minote-m0c-review-node-green.log`, `minote-m0c-core-final.log`, `minote-m0c18-review-final.log`, `minote-m0c26-review-final.log`; 결과 양 `minote-m0c<18|26>-review-final.xcresult`.
- 실제 browser 파일 chooser로 `browser-edited.json` 재열기 성공. revision 43/4획, 확대 100→200→100 후 출력 텍스트가 fixture와 **완전히 동일**함을 확인했다. 최종 화면 `docs/assets/m0c-portable-ink.jpg`. native download 파일 저장 완료는 계속 미검증이다.
- reviewer set-aside에 대한 판단: main 직접 작업/기록 보존은 사용자 지시; safe-integer/v2/pen 추가/미지 필드 거부는 도구의 선언된 범위; 근사 texture/marker/곡선과 PDF 배경 제외는 승인된 시험 범위; readonly 출력은 실제 왕복 근거이며 native download는 대기; programmatic undo는 명시적 command/session 검증이며 실제 Pencil 입력 결과가 아니다; 물리 Pencil/큰 문서/production JSON import/다른 플랫폼/부분 삭제·미래 객체는 후속이다.
- Swift의 v2 unknown-key decoder는 기존 동작이며 이번에 future 객체를 보존한다고 확장 주장하지 않는다. 중복 삭제 ambiguity는 위의 명시적 차단으로 제한을 고쳤다. exotic JS object/중복 JSON key/extreme finite geometry는 지원 fixture 흐름에서 재현된 결함이 아니므로 지원 확대를 하지 않는다. 조밀한 시험 도구 formatting/입력 중 preview는 후속 개선이다. PDF xref 끝 공백은 원본 bytes 계약이라 제거하지 않는다. 남은 checkbox/Notion/인계는 이번 종료 작업으로 해결한다.
- 다음: 리뷰 수정 코드 커밋 → 완료 기록/Notion 반영 → 다음 M1-A 계획을 인계한다. M1 코드는 이번에 작성하지 않는다.

### M0-C 최종 인계
- 완료 조건: 실제 독립 JSON 이동/삭제/새 pen → iPad 재편집/undo/redo/저장/재열기 통과. 근사 외관/지원 범위/모호한 ID 거부와 native download 미검증을 분리했다. 이 단계의 앱 테스트·리뷰·기록을 완료했다.
- 현재 코드 `28b9889`, 문서는 이 기록이 포함된 마지막 docs 커밋. local main, 이번에는 push하지 않았다. 마지막 결과는 리뷰 후 최종 로그와 양 xcresult이며 이전 실패를 삭제하지 않았다.
- Notion 업데이트 성공/재조회 시각은 위 Notion 절을 따른다. 브라우저 화면·출력 fixture·명령 재현 방법은 저장소에 있다. 시험 HTTP 서버 session 60760과 임시 브라우저 탭은 종료했다.
- 다음 첫 작업: `git status --short --branch` → 이 문서/`2026-10-03-m1-a-local-library.md`/기존 저장 코드를 대조 → M1-A Task 1의 기존 노트·원본 PDF·backup 이주 테스트 RED. 이번 실행에서 M1 코드는 만들지 않았다.
- 계획 자기 점검: M1-A에서 라이브러리와 안전한 세션 전환만 구현하며 M1-B/C/M2의 페이지·백업·객체를 완료로 표현하지 않는다. LibraryLoadResult는 transient 복구 안내, LibraryCatalog는 영구 metadata로 구분했고 Task 간 API/파일/검증 연결을 확인했다.

## M1-A 실행 체크포인트 (2026-10-03)
- [x] Task 1: 기존 노트 보존 이주·catalog 읽기/저장
- [x] Task 2: 독립 노트·폴더·휴지통 변경
- [x] Task 3: 저장 완료를 보장하는 세션 전환
- [x] Task 4: 라이브러리 UI·전체 검증·fresh 리뷰·Notion·인계
- 시작 기준 `fd4def65ac952a0d5efc1a9ea07d02f2d6630689`. main에서 직접 구현하고 별도 브랜치/worktree/PR/push는 하지 않는다. 기존 M0 결과를 반복하지 않는다.
- 사용자가 앞서 제시한 제품 설계와 작성된 M1-A 계획에 대해 계속 진행을 요청했다. 직접 구현/단계 말 한 번 리뷰를 유지하며 새 승인 질문은 만들지 않는다.
- 사전 인터페이스 점검: catalog에는 제목을 중복 저장하지 않는다. LibraryLoadResult가 transient 복구 안내를 포함하고 notes/<UUID>마다 동일 DocumentStore 인스턴스를 사용한다. 저장 실패/미지원 필기 때 close/open을 차단한다. catalog commit은 본문/자산 저장 뒤 수행한다.
- scratch 진행 기록을 보존한다. 다음 즉시 작업은 LibraryMigrationTests/LibraryStoreTests RED 확인이다. 아직 M1-A 완료 기능/검증은 없다.

### M1-A Task 1 완료
- LibraryCatalog/Note/Folder와 Foundation LibraryStore를 추가했다. 기존 v1/v2 노트·PDF·raw backup을 새 notes/<UUID>에 복사 후 catalog를 마지막에 commit한다. 기존 루트 파일은 보존한다. 미연결 디렉터리는 오류 노트라도 목록으로 회수하며, 누락 본문은 blank 생성으로 처리하지 않는다.
- RED: 타입/API 부재 (`/private/tmp/minote-m1a-library-red.log`, exit 1). GREEN 시도 1/2는 테스트 assertion RHS의 try 누락으로 컴파일 실패였으며 실제 기능 통과로 기록하지 않는다. RHS 수정 후 core 전체 **36/0**, exit 0 (`/private/tmp/minote-m1a-task1-core.log`). portable fixture `node Tools/PortableInk/roundtrip.mjs --check` exit 0.
- 검증: 이주 두 번의 멱등성, v1/정상 backup 복구, 지원하지 않는 버전/누락 PDF/손상 JSON/경로 I/O 차단, catalog commit 실패 후 재시도와 미연결 노트 회수. catalog 복구는 손상 JSON에만 적용하고 미래 버전·I/O 오류를 덮지 않는다.
- 다음 첫 작업: LibraryMutationTests RED → 독립 노트/PDF·폴더 순환 거부·휴지통·실패한 commit·동시 mutation 구현. 앱 UI/양 시뮬레이터/실기기/Notion은 아직 M1-A 미검증이다.

### M1-A Task 2 완료
- Task 1 커밋 aa92907. 노트 생성/최신 본문 기준 이름 변경, 폴더 생성/이름 변경/이동, 노트 이동/휴지통/복원을 구현했다. UUID 식별과 folder 관계를 유지하며 순환·누락 parent·빈 이름을 거부한다. 본문 저장 뒤 catalog 실패한 생성은 다음 load에서 회수한다.
- RED: mutation API 없음 (`/private/tmp/minote-m1a-mutation-red.log`, exit 1). GREEN: `swift test --package-path Packages/MiNoteCore` **44/0**, exit 0 (`/private/tmp/minote-m1a-task2-core.log`). 서로 다른 노트의 필기/PDF/리비전 분리, 최신 필기 후 rename, 폴더/휴지통 원본 불변, write 실패, 동시 mutation busy 차단 및 stale actor commit 거부를 확인했다.
- 다음 첫 작업: LibrarySessionTests RED. MainActor 세션이 outgoing editor 저장 상태를 확인한 뒤만 교체하며 실패/미지원 필기는 그대로 유지한다. 앱 UI·양 OS·단계 말 리뷰는 미완료.

### M1-A Task 3 완료
- Task 2 커밋 0ca9545. MainActor LibrarySession은 첫 await 전에 busy를 설정하고 outgoing editor flush/.saved/metadata commit/목록 refresh를 마친 뒤 선택을 교체한다. 실패하면 동일 editor/drawing을 유지한다. referenced ID가 없는 노트를 EditorSession blank fallback으로 새로 만들지 않도록 expectedID를 전달한다. 본문 실패 항목은 목록에 오류로 남는다.
- RED: LibrarySession 타입 없음 (`/private/tmp/minote-m1a-session-red.log`, exit 65). 18.6 전체 GREEN: 앱 단위 **38/0**, 기존 UI **2/0**, exit 0 / TEST SUCCEEDED (`/private/tmp/minote-m1a-task3-green.log`). outgoing 저장/두 노트 격리/중복 열기/실패·미지원 차단/rename 전 close/catalog 실패 뒤 유지 테스트 6개 포함.
- 중간 구성 판단: 주입된 NoteEditorView 검증을 위해 앱 root는 이 커밋에서 기존 디렉터리를 사용한다. Task 4에서 LibraryView로 교체하며 최종 설치는 빈 목록·명시적 사용자 생성이다. 새로운 UI 테스트는 아직 미실행/미커밋이다.
- 다음 첫 작업: Task 4 UI RED → 실제 라이브러리 화면 → 양 OS 전체 검증 → fresh 리뷰/수정 → Notion/다음 계획. 길게 실행하기 전 checkpoint로 본 기록을 남긴다.

### M1-A Task 4 실행 중 체크포인트
- Task 3 커밋 1621e11. LibraryView/최종 앱 root/기존 UI 진입 경로를 구현했다. UI RED는 newNote 버튼 없음으로 실제 실패 (`minote-m1a-ui-red.log`, exit 65).
- 첫 UI GREEN 시도는 세로 화면 NavigationSplitView가 sidebar를 접어 newFolder가 없어서 실패 (`minote-m1a-ui-green1.log`, exit 65). iPad 화면에 폴더 목록을 유지하는 HStack/NavigationStack 구성과 상단 생성 버튼으로 수정했다. 재검증 중 `minote-m1a-ui-green2.log`; 결과 확인 전 성공으로 표시하지 않는다.
- 아직 전체 양 OS/별도 migration UI/리뷰/Notion 미완료. 노트/폴더 메뉴와 sheet 접근성 ID는 UI 테스트에 사용한다. 미커밋 UI 변경은 사용자 변경이 아니라 이번 Task 4다.

- Task 4 추가: 전용 빈 migration simulator 18.6 F4041A43-D58A-495E-AF08-EFE5AD816D95 / 26.4 E8702560-F54F-425A-913C-0F5E008B4FD2를 생성했다. 일반 시뮬레이터 데이터를 seed하지 않는다. Tools/LibraryTests/legacy_fixture.py는 기존 폴더/일반 기기를 거부한다. fixture-only UI check는 일반 suite에서 fixture가 없으면 skip하고 두 전용 기기에서 별도 실행한다.
- seed 첫 실행에서 serialized asset에 computed relativePath가 없다는 KeyError가 발생했다. 공통 PDFAsset의 UUID 기반 경로 규칙을 확인해 수정했으며, 이번 script가 만든 JSON과 backup을 대조하고 누락 PDF만 채웠다. 사용자 문서는 바꾸지 않았다. 이 준비 실패는 migration 기능 테스트 성공이 아니다.
- 전체 실행 중: Node 25/0, core 44/0 exit 0 확인; 양 Xcode 전체/minote-m1a<18|26>-final.log는 진행 중이며 결과를 확정하지 않았다.

### M1-A Task 4 리뷰 전 GREEN
- Node **25/0**, fixture check exit 0, core **44/0**. 양 iPadOS 18.6/26.4 전체 앱 단위 **38/0**, 일반 UI **3 passed / 1 fixture-only skipped / 0 failures**, 양 xcodebuild exit 0 / TEST SUCCEEDED. 로그 `/private/tmp/minote-m1a-node-final.log`, `minote-m1a-core-final.log`, `minote-m1a18-final.log`, `minote-m1a26-final.log`; 양 final xcresult 보존.
- 일반 suite의 skip은 이주 입력 fixture가 없는 환경이다. 별도 빈 기기 18.6/26.4 각각 migration UI **1/0, skip 0**, 양 exit 0 / TEST SUCCEEDED (`minote-m1a18-migration.log`, `minote-m1a26-migration.log` 및 xcresult). legacy 5페이지/4획·복구 안내·PDF 페이지·닫기·재실행을 확인했다. seed helper --verify 양 exit 0: 원본 JSON/backup/PDF bytes 불변, migrated ID·획·PDF 일치 및 revision 증가 확인.
- 18.6 verify 전 boot는 이미 Booted 상태라 exit 149였고 실제 --verify는 exit 0이었다. 이를 기능 검증 실패와 구분한다. 생성한 전용 시험 기기는 재현 가능하도록 보존한다.
- 테스트 기기 기본 UUID는 기존 기록과 같다. 주입된 편집기 외 화면 변경은 이번 UI commit이다. 아직 별도 리뷰/최종 Notion/인계는 미완료다.
- 다음 즉시 작업: 단계 전체 fd4def6..현재 UI commit을 fresh reviewer 한 번에게 읽기 전용 리뷰 → 중요한 결함 RED/수정/GREEN → 최종 기록/Notion/M1-B 계획. 실제 Pencil/손바닥/발열은 대기.

### M1-A 별도 리뷰 / 수정 진행
- fresh m1a_code_review 한 번, 범위 fd4def6..d44aad5. Critical 없음, Important 1(최종 await 후 editor 상태 미확인), Minor 1(같은 이름의 폴더 구별 불가). 리뷰는 읽기 전용이며 추가 reviewer를 만들지 않았다.
- Important 실제 RED: catalogWriter가 실제 metadata commit 중 MainActor에 늦은 PKDrawing을 전달했다. 닫기는 true인데 메모리 2획/리비전2와 디스크 1획/리비전1이 달랐고 미지원 늦은 필기도 화면이 닫혔다 (`/private/tmp/minote-m1a-review-race-red.log`, exit65, assertion6실패). 최종 refresh 후 저장 상태와 문서 snapshot이 동일한지 다시 검사하고 await 없이 선택을 제거하게 수정했다. 늦은 변경이 있으면 editor 유지 후 다음 close에서 최신 저장한다. native canvas도 SwiftUI isEnabled를 반영하며 queued callback은 계속 받아 검사한다.
- 집중 GREEN LibrarySessionTests **7/0**, exit0 / TEST SUCCEEDED (`minote-m1a-review-race-green.log`). 실제 Pencil 입력은 programmatic 늦은 callback 재현과 별개다.
- Minor 실제 UI RED를 실행 중 (`minote-m1a-review-folder-red.log`). 이후 UUID로 일관된 표시를 만들어 sibling collision과 VoiceOver ancestor 경로를 수정한다. 최종 양 OS 전체는 수정 후 다시 실행한다.
- M1-B 다음 계획 `docs/superpowers/plans/2026-10-03-m1-b-pages-and-pdfs.md`를 작성했다. 아직 실행하지 않는다. schema3/페이지별 asset ID·삭제 페이지 보관·여러 PDF·용지·책갈피·독립 v2/v3 호환 계획이다.

- Minor RED: 실제 UI의 두 Twin 폴더 label이 동일했다 (`minote-m1a-review-folder-red.log`, exit65). LibraryFolderLabels가 동일 parent/name의 segment에 UUID의 최소 유일 suffix를 표시하고 모든 ancestor를 포함한다. sidebar/이동/VoiceOver/노트 위치 표시가 같은 경로를 사용한다. suffix 충돌은 길이를 늘려 해결한다.
- 집중 GREEN: 폴더 label 단위 **3/0**, 실제 duplicate-folder 이동 UI **1/0**, exit0 (`minote-m1a-review-folder-green.log`). 다른 부모와 부모 자체의 중복, 정렬 후 label 안정성, short-ID 충돌을 확인했다.
- 리뷰 판단: 다중 PDF/페이지/용지는 M1-B; backup/export-orphan cleanup/영구 삭제는 M1-C; folder deletion은 복원 위치 유지 때문에 제외; search/favorites/configurable order/접근 최근은 M2 이후이며 현재 modifiedAt 정렬; 다중 창/프로세스 경합/외부 rename/sync/타 플랫폼은 단일세션 계약 밖; 많은 노트의 색인/metadata-only load는 측정 후 M3; descendant 선택 차단 UI는 core가 오류 안내하므로 후속; semantically invalid catalog는 원본 보존/JSON 손상만 fallback; 실기기/VoiceOver 전체인증/다양한layout은 별도 대기; fixture-only skip은 두 전용 실행으로 실제검증; JSON/main/기록 보존은 사용자 승인된 판단이다. 이 중 검증 없이 완료로 주장한 항목은 없다.
- 최종 양 OS 전체를 `/private/tmp/minote-m1a<18|26>-review-final.log`/xcresult로 실행한다. core/Node는 리뷰 수정에서 변경되지 않았으므로 직전 전체 GREEN 근거를 유지한다. 이주 저장 로직도 변경되지 않아 별도 seeded migration/원본 bytes 검증을 재사용한다. 변경된 close/labels/native input은 새 전체 앱/UI가 확인한다.

### M1-A 리뷰 수정 후 최종 GREEN
- 변경된 앱 전체: 18.6/26.4 각각 앱 단위 **42/0**, 일반 UI **4 passed / 1 fixture-only skipped / 0 failures**. 양 xcodebuild exit0 / TEST SUCCEEDED, `/private/tmp/minote-m1a18-review-final.log`, `minote-m1a26-review-final.log` 및 review-final xcresult. 중요한 race와 중복 폴더 실제 UI 수정이 포함된다.
- 변경되지 않은 core **44/0**, Node **25/0**, fixture check exit0 근거는 직전 전체 logs를 따른다. 별도 seeded migration UI는 양 **1/0, skip0** 및 helper --verify exit0이며 이주 저장 코드에는 리뷰 변경이 없다. 시뮬레이터 결과가 실제 Pencil 지연·손바닥·발열을 보증하지 않는다.
- 남은 종료 작업: 리뷰 수정 코드 commit → Notion 결과 추가/재조회 → README/AGENTS/다음 계획과 최종 인계 commit. push는 하지 않는다.

### M1-A 최종 인계
- 모든 Task 1~4를 구현/검증/한 번 리뷰/중요 수정/Notion 기록까지 완료했다. 마지막 코드 commit d968701. 마감 문서 commit은 이 기록을 포함한 HEAD(`git log -1 --oneline`)다. 이번에 직접 push하지 않았다.
- 마감 Git 상태 조회에서 origin/main 추적 ref가 d44aad5로 바뀌었고 reflog는 update by push다. 이번 agent는 push 명령을 실행하지 않았다. 원격 새 조회는 하지 않았으며, 추적 ref 기준 d968701 이후 커밋은 앞서 있다. ‘모든 코드가 아직 원격에 없다’고 주장하지 않는다.
- Notion async task task_604b47596ff046a6ac21560489d43515 succeeded. 재조회: 새 M1-A heading 1개, app42/UI4, d968701, M1-B 계획과 기존 M0-C 내용 보존을 확인했다. page_last_edited 2026-10-03T06:02:45.909Z, 검증 06:04:12 UTC. 로컬 동일 결과는 docs/milestones/2026-10-03-m1-a-local-library.md다.
- 선택적인 파일 선택기 상태 스크린샷은 simctl의 Timeout waiting for screen surfaces(exit60)로 생성하지 못했다. 해당 UI는 XCTest에서 실제 가져오기/출력/공유까지 통과했고 screenshot 실패를 기능 통과 근거로 쓰지 않았다. 전용 이주 기기 두 개만 shutdown했고 자료/기기는 보존했다. 일반 기기는 건드리지 않았다.
- 다음 첫 작업: git status/HEAD 대조 → AGENTS/PROGRESS/M1-B 계획/기존 모델·PDF 경계 읽기 → SchemaV3Tests의 v1/v2 ID·ink·asset mapping 보존 RED. M1-B 구현은 이번 실행에 포함하지 않았다. Notebook별 한 PDF/흰색 A4, page Undo reset, `.minote`/cleanup/검색/객체/실기기 대기를 유지한다.
- 계획 자기 점검: M1-B 모델/명령/PDF/session/UI/독립 계약은 Task 1~5; v1/v2 규칙을 migration 전에 검사하고 같은 index 복제/삭제복원/다중PDF실패/주석누적/미래버전·누락 자산은 구체 테스트로 연결했다. PaperRenderer는 Task 3에서 만들고 Task 4가 소비해 의존 순서를 맞췄다. 지원 밖 전체 제품 목표는 후속으로 명시했다.

### M1-B 시작 체크포인트
- 2026-10-03, 기준 80d14c2, main clean. 완료된 M0/M1-A는 반복하지 않는다. 원격 push 없이 main에서 직접 구현하며 기존 scratch/기록은 보존한다.
- 실행 순서: Task 1 v3 migration → 2 페이지 명령 → 3 여러 PDF/출력 → 4 세션/화면 → 5 JS 왕복/양 OS/리뷰/Notion/인계.
- 사전 인터페이스 확인: legacy mapping 검증 후 assetID 연결; 구조+선택을 같은 revision에 commit; 현재 drawing flush와 늦은 callback 검사는 모든 구조 작업에 적용; PaperRenderer는 PDF 작업에서 만든 뒤 UI가 사용; JS v2 fixtures는 원본 v2로 유지.
- 다음 즉시 작업: SchemaV3Tests RED → 모델/codec/저장/library 모든 자산 검사 → core/기존 앱 단위 GREEN. 아직 M1-B 기능·검증은 완료되지 않았다.

### M1-B Task 1 완료
- v3 pdfAssets/assetID/삭제 페이지/용지/책갈피 모델을 추가했다. v1/v2는 기존 유일·전체 PDF mapping과 v1 단일 페이지를 먼저 검사한 뒤 IDs/revision/ink/geometry를 유지해 v3로 읽는다. encode는 v3만 기록한다. library catalog는 v1 그대로다.
- 모든 보관 PDF 자산의 파일/byteCount 검사 및 legacy library 복사를 적용했다. raw v1/v2 backup 유지, 같은 원본 index 복제 허용, active+deleted object ID uniqueness와 1000페이지/500MB 제한을 검증했다.
- RED: initial sandbox Swift cache 접근 실패는 기능 RED가 아니다(minote-m1b-schema-red.log). 승인된 테스트 실행에서 v2→v3/필드 누락 assertion4 실패(red2), 새 API 부재 컴파일 실패(red3)를 확인했다.
- GREEN: swift test --package-path Packages/MiNoteCore 전체 **49/0**, /private/tmp/minote-m1b-task1-core-green.log, exit0. 기존 schema2 기대값과 source.assetID 기대를 v3 계약으로 바꿨다. iPadOS18.6 xcodebuild -only-testing:MiNoteTests **42/0**, minote-m1b-task1-app.log/xcresult, exit0 TEST SUCCEEDED.
- 다음: Task 2 PageCommands/actor 저장 RED. 다중 PDF/페이지 UI/JS v3/26.4/리뷰/Notion은 아직 미완료. 단일 자산 source compatibility는 Task 3/4에서 제거할 임시 연결이다.

### M1-B Task 2 완료
- Task 1 코드 28ea031. PageCommands는 value 입력을 변경하지 않고 insert/duplicate/move/delete/restore/paper/bookmark마다 revision을 한 번 증가시킨다. 삭제 전체 페이지/원래 index/시간을 보관하고 선택을 가까운 활성 페이지로 옮기며, 복원 index는 clamp한다. PDF 참조·필기 값은 유지하고 복제 object IDs는 새로 발급한다.
- actor applyPageCommand는 기대 revision 검사부터 원자 저장까지 suspension 없이 처리한다. stale/backup I/O 실패에서 최신 ink/primary가 그대로이며 retry/재열기 순서·용지·책갈피를 확인했다.
- RED: PageCommand/actor API 부재 컴파일 실패, /private/tmp/minote-m1b-pages-red.log, exit1. GREEN: swift test --package-path Packages/MiNoteCore 전체 **56/0**, minote-m1b-task2-core.log, exit0.
- 다음: Task 3 다중 PDF·독립 출력 RED → asset별 validation·용지 renderer → 관련 앱/core. 앱 UI/JS/양 OS 최종·리뷰·Notion은 아직 미완료.

### M1-B Task 3 완료
- Task 2 코드 c21d9ef. attachPDF는 선택한 page 뒤에 새 PDF를 삽입하고 모든 source.assetID/index/원본 pageCount를 검사한다. 같은 filename의 서로 다른 UUID 자산·기존 ink·실패한 2차 첨부/orphan 보존을 검증했다.
- PDFValidation은 자산별 원본 count/byteCount/geometry와 참조 페이지를 검사하며, 같은 index 반복·부분 index만 남은 노트를 허용한다. PDFExporter sourceURLs는 모든 자산의 누락/출력 경로 중복을 거부하고 PDFPage.copy 후 해당 page ink만 붙인다. 반복 출력에서 주석 누적/다른 복제본 ink가 섞이지 않는 픽셀 검증을 통과했다. PaperRenderer 24pt/0.5pt 용지를 output에 공유한다.
- RED: 새 afterPageID 및 asset-specific validation/export API 부재(core exit1, app exit65), /private/tmp/minote-m1b-multi-core-red.log, minote-m1b-multi-app-red.log. GREEN: core 전체 **59/0**, minote-m1b-task3-core.log; 18.6 app 전체 **44/0**, minote-m1b-task3-app.log, TEST SUCCEEDED/exit0. 기존 원본 bytes·실패 출력·암호 PDF·4회전 검증 포함.
- 남은 임시 연결: EditorSession의 첫 자산 load와 단일 가져오기 UI는 Task 4에서 교체한다. exporter는 이미 전체 sourceURLs를 사용한다. 다음 즉시 작업: PageEditorTests 늦은 callback/flush/자산 전환 RED → 구조 변경 세션/페이지 UI/썸네일. JS·26.4·전체 UI·리뷰·Notion은 미완료.

### M1-B Task 4A 세션 체크포인트
- Task 3 코드 c977bd4. 비동기 페이지 전환/명령/다중 가져오기/빈 노트 PDF 출력에 await 전 잠금, 현재 필기 flush와 await 후 snapshot 검사, 페이지+선택 한 저장, 세대별 canvas owner 보호를 연결했다. 모든 원본 PDF를 순차 검증하고 assetID로 현재 PDF를 선택하며 PDF cache2/thumbnail24·256px 상한을 구현했다.
- RED: 세션 API/cache 미구현, minote-m1b-session-red.log exit65. GREEN: 18.6 앱 전체 **48/0**, minote-m1b-session-green.log exit0 TEST SUCCEEDED. PageEditorTests는 실제 actor reader 안에서 MainActor native callback을 전달해 flush 중/commit 중의 지원/미지원 획 경합을 재현했다.
- 결정: actor commit 대기 중 늦은 callback을 버리지 않는다. commit 완료 후 경합이 감지되면 기존 페이지 구조+최신 필기를 더 높은 revision으로 보상 저장해 작업을 취소하고 화면을 유지한다. 지원하지 않는 drawing은 실패 상태/메모리에 보존한다. 세션 구조 작업은 보상 revision 하나를 위해 Int64.max-1 이상에서 차단한다(현실적인 문서에 영향 없음, 잘못 판단하면 한 번 이른 revision 한도).
- 다음: 페이지 manager 실제 UI RED → 화면·용지 배경·삭제 복원/책갈피·썸네일 연결 → 앱/UI GREEN. Task 4 전체는 아직 완료 아님. JS/26.4/리뷰/Notion은 미완료.

### M1-B Task 4B 화면 검증 완료
- 페이지 manager: 활성/책갈피/삭제 목록, 보이는 thumbnail, A4 blank/ruled/grid 추가·용지 변경, 복제·메뉴/drag 재정렬, 삭제 확인·복원. 현재 page+구조 변화의 Canvas generation을 바꿔 Undo와 오래된 delegate를 분리한다. 화면/thumbnail/출력은 같은 24pt/0.5pt 용지를 사용한다.
- RED: 실제 UI의 pageManager 버튼 미존재 assertion1(minote-m1b-page-ui-red.log, exit65), 화면 paperStyle API 부재(minote-m1b-paper-screen-red.log, exit65). GREEN: 18.6 앱 전체 **51/0** + 새 PageManager UI **1/0**, minote-m1b-pages-ui-green.log exit0 TEST SUCCEEDED. result: /private/tmp/minote-m1b-dd18/Logs/Test/Test-MiNote-2026.10.03_19-12-15-+0900.xcresult.
- UI는 실제 손가락 gesture로 blank/ruled/PDF에 필기하고 페이지 추가/복제/이동/책갈피 필터/삭제/복원/실제 Files A·B 선택/재실행/원래 PDF ink/출력 미리보기를 확인했다. 스토어 직접 호출 시험과 구분한다. 라이브러리 다른 노트 전환 후 다중 PDF/복원 ink는 단위 시험으로도 확인했다.
- 다음: Task 5 JS v2/v3 계약과 iPad 역방향 fixture → 모든 양 OS/별도 migration → fresh 리뷰 한 번 → Notion/정리. 현재 Task 4 완료 근거이며 M1-B 전체 완료는 아님.

### M1-B Task 5 互換 검증 체크포인트
- Task 4 세션 0f87b10/화면 ad46dc4. 기존 전체 18.6 UI 회귀는 task-4-tests.log/result minote-m1b-task4-full.xcresult로 실행 중이다. 새 앱51/새UI1은 이미 통과했다. compiled app을 바꾸지 않는 독립 JS 작업을 겹쳐 수행한다.
- JS v3 RED **4실패**(미지원 pdfAssets/용지 선 부재), minote-m1b-js-red.log. v2 계약을 유지하며 v3 assets/deleted/page metadata 검증·편집 보존·24pt 용지를 구현해 Node 전체 **29/0**, minote-m1b-js-green.log. 기존 v2 roundtrip --check exit0.
- 다음: iPad가 만든 v3 multi-source fixture를 회수 → 실제 JS multi-edited 생성 → native 재편집/Undo/저장/재열기 GREEN → 모든 양 OS/이주 UI/리뷰. 임시 단일 자산 Swift API는 제거 중이며 현재 변경은 아직 최종 검증/커밋 전이다.

### M1-B Task 5 최초 양 OS 전체 결과 / UI 진단
- Node31/0, core60/0. 실제 native v3 generator1/0에서 multi-source.json을 만들고 JS manifest로 multi-edited.json을 생성했다. native fixture 부재 RED1에서 시작했으며 양 OS app53/0에 새 v3 재편집/Undo/저장/재열기가 포함되어 통과했다. v2 fixture --check와 v3 --check도 exit0.
- 최초 전체 xcodebuild 양 exit65: 18.6 LibraryUI에서 누적 폴더로 인해 sheet target이 off-screen/미생성(NoMatches), 26.4 PageUI에서 SwiftUI alert의 동일 ID 부모·자식 Button 두 개로 selector 모호함. app53은 양0실패지만 UI 실패를 성공으로 기록하지 않는다. /private/tmp/minote-m1b18-full.log/xcresult, minote-m1b26-full.log/xcresult.
- 접근성 tree로 원인 확인: sheet에는 Notes/Twin 초반 target만 있고 새 Work는 아래에 있다; 26.4 alert 아래 '삭제' 부모/자식이 같은 ID다. product List에는 범위를 잡을 ID만 추가하고 테스트가 scroll하며 실제 target을 찾도록 수정한다. 삭제는 정확한 alert 아래 firstMatch를 탭한다. 기능 assertion은 유지한다.
- 새 migration18 UUID2021A9D8-702A-4C3E-AD29-FCF747CCFD45, migration26 UUID554DA7BF-9D47-4502-8C8D-1E86FC69568F를 생성·boot·install·seed했다. 이전 사용자/시험 데이터는 덮지 않았다. 아직 migration UI/verify는 실행 전이다.
- 다음: 수정된 UI 관련 양 OS GREEN → 이주 실제 실행/원본 verify → fresh 전체 review 한 번. SDK screenshot export는 sandbox cache 쓰기 거부로 아직 회수하지 않았고 근거는 XCTest tree/결과다.

### M1-B UI 재검증 원인 확인
- 두 번째 양 OS 전체도 app53/0, 페이지/ink/PDF UI 통과지만 LibraryUI scroll 실패로 exit65다(minote-m1b18-ui-retry, minote-m1b26-ui-retry). 실패 attachment를 승인된 xcresulttool로 회수했다.
- 26.4 로그는 moveDestinations 존재 → top에서 swipeDown 3회 → sheet 사라짐이며 실패 AX에는 libraryFolders만 남았다. 이동 sheet를 위로 찾기 전에 반복 아래 drag한 테스트가 interactive dismissal을 유발했다. 새 이동 sheet는 위쪽부터 시작하므로 swipeUp만 사용하고, persistent sidebar만 top으로 돌아간다. 재실행 후 off-screen renamed folder를 미리 존재한다고 요구하던 assertion도 같은 scroll helper로 대체한다. 기존 데이터 삭제/성공 assertion 생략은 없다.
- 다음: LibraryUITests만 양 OS 검증 → 별도 seeded migration/verify → Task5 커밋 및 fresh 리뷰 한 번. 아직 전체 M1-B 완료는 아니다.
- 수정 후 18.6 LibraryUI는 2통과/fixture-only1skip/0실패(minote-m1b18-library-scroll, exit0). 별도 migration18 UI1/0/skip0와 helper --verify exit0까지 확인했다.
- 26.4 library-scroll은 여전히 수정 전 swipeDown/이전 line82를 실행했다. 생성/설치 시험 바이너리 SHA256은 동일하므로 설치 누락으로 단정하지 않는다. 실제 compiled 실행 경로/캐시 경계를 분리하기 위해 새 DerivedData+compile cache 비활성화로 전체 실행한다. 실패 후 diagnostic 수집에 머문 xcodebuild18339만 중단했고 데이터는 보존했다. 26.4 전용 migration은 별도 DerivedData로 실행 중이다.
- 다음 M1-C 계획 docs/superpowers/plans/2026-10-03-m1-c-backup-and-cleanup.md 작성/자기 점검. ZIP stored-only 편집 백업, 새 note 복원, backup 참조/삭제 journal 보호, 공유 lease가 구체 인터페이스/시험에 대응한다. 계획만 작성했고 M1-C 코드는 이번 실행에 포함하지 않는다.

### M1-B 최종 검증 진행 체크포인트
- Node31/0와 v2/v3 roundtrip --check 각 exit0를 다시 확인했다(minote-m1b-node-before-review.log). core60/0도 재실행 exit0(minote-m1b-core-before-review.log).
- 양 전용 migration UI 각각1/0/skip0, xcodebuild exit0 TEST SUCCEEDED(minote-m1b18-migration, minote-m1b26-migration). --verify 양 exit0: raw v2 document/backup/PDF bytes, migrated v3 IDs/ink/geometry/assets 불변을 확인했다. boot 중 이미 Booted 안내는 검증 결과와 구분한다.
- 최종 전체18(minote-m1b18-final-full), 새 DerivedData 전체26(minote-m1b26-fresh-full)는 app53/0을 통과했고 일반 UI 실행 중이다. 26 새 빌드는 수정된 swipeUp을 실제로 실행하므로 이전 결과와 구분한다. 전체 종료 결과를 확인하기 전 완료로 표시하지 않는다.
- 다음: 전체 UI 종료 → Task5 코드/문서 commit → 80d14c2부터 fresh 전체 review 한 번. 리뷰/Notion/최종 인계는 아직 미완료다.
- Task5의 구현/관련 core·Node·native·18.6 LibraryUI 검증을 코드 체크포인트로 커밋한다. 마지막 전체 UI 실행과 읽기 전용 리뷰는 코드 변경 없이 병행하며, 양 OS 전체 결과와 리뷰 수정 검증까지 단계 완료 표시는 보류한다.

### M1-B 리뷰 결과 / 최종 UI 조사
- fresh reviewer 한 번: 80d14c2..1d67d9a, 확정 Critical/Important/Minor 코드 결함 없음. With fixes 판정은 최종 UI 검증 게이트 때문이다. M1-C/전체 메모리/실기기/외부 프로세스 범위 제외 항목과 판단은 최종 절에 보존한다. 추가 reviewer는 만들지 않는다.
- final-full18은 app53/0·LibraryUI2/0·기존 ink/PDF UI2/0이지만 PageUI의 Files local location 셀 실패로 UI총6/skip1/failure1이다. 새 PageUI는 이전 양 OS 실행에서 통과했으나 이를 최종 전체 성공으로 대체하지 않는다. xcresult가 실패 snapshot을 남기지 않아 다음 집중 실행에 actual AX tree를 실패 메시지로 추가한다.
- full26은 duplicate-folder 두 번째 filter 탭 뒤 idle 응답이 멈췄다. 호스트16GiB/free 약70MiB, 중단된 진단 수집/샘플링과 구별한다. 이미 검증한 두 migration 기기를 shutdown하고 과도한 이번 시험 sysdiagnose만 중단했다. 앱 stack sample은 회수하지 못했다. 원인을 특정했다고 주장하지 않는다. 이후 시험은 serial/collect-test-diagnostics never로 환경 경합을 줄인다.
- 마지막 코드1d67d9a. PageUI diagnostic assertion 변경은 미커밋, M1-C 계획/milestone 초안 미커밋. 다음은 집중 PageUI18에서 실제 Files 화면 확인→필요한 selector/탐색 수정→양 OS 전체 UI GREEN→기록/Notion/커밋이다.
- picker-diagnose18 집중 PageUI **1/0**, xcodebuild exit0 TEST SUCCEEDED. 앱 동작/탐색 selector 수정 없이 diagnostic 메시지 추가만으로 실제 A/B 가져오기·재실행·출력을 통과했다. 직전 실패 원인이 특정됐다고 주장하지 않는다. 두 OS를 순서대로 전체 실행하는 serial-final 명령을 시작했다.
- fresh26 LibraryUI는 멈춤 뒤 결국 2통과/fixture1skip/0실패(767초)를 기록했으나 이번 invocation 종료143으로 나머지 UI는 미실행이다. 전체 통과가 아니다. 스택 sample 실패·sysdiagnose 종료/VM 상태도 기능 성공 근거에 포함하지 않는다.
- 통과한 집중 PageUI18의 keepAlways screenshot을 xcresult에서 회수·육안 확인하고 docs/assets/m1b-multi-page-export-preview.png로 보존했다(9페이지 출력/필기 표시). 화면 근거와 실제 Pencil 검증을 구분한다. final serial suites는 아직 실행 중이다.

### M1-B serial-final18 GREEN
- 최종18.6 전체: app **53/0**, 일반 UI **5 passed / fixture-only 1 skipped / 0 failures**, xcodebuild exit0 TEST SUCCEEDED. /private/tmp/minote-m1b18-serial-final.log/xcresult. 마지막 변경은 PageUI 실패 때 AX tree를 남기는 diagnostic뿐이며 실제 A/B 가져오기·페이지/필기/복원·재실행·출력을 모두 통과했다.
- serial-final26는 이어 실행 중이다. stage 완료/Notion 마감은 아직 대기한다. 별도 migration 양1/0/skip0와 raw-byte verify는 직전 정상 근거를 유지한다. 다음 첫 작업은 이 명령의26 결과 확인→README/AGENTS/PROGRESS final→Notion append/re-fetch→문서 커밋이다.
- 리뷰가 보류한 항목의 최종 판단: 강제 종료 직전 미저장/반복 I/O 실패는 last normal save+실패 메모리 유지 계약이며 완전 영속 보장으로 주장하지 않는다. pageID/generation 폐기는 cross-page 보호이고 실제 유효 현재 필기 소실은 확인되지 않았다. cache2/24는 전체 메모리 상한이 아니며 M3에서 측정한다. 인위적 legacy ID 충돌/지원 밖 크기는 strict 오류로 보존한다. 정상 backup 복구는 recognized corruption에만 안내하고 physical asset/future/I/O는 fallback하지 않는다. JS safe integer/근사/PDF 배경 미표시는 시험 도구 제한이다. 통합 Undo/영구 삭제/파일 정리/편집 백업은 후속, multi-process/sync/외부 변조/실기기/VoiceOver 전체/외부 뷰어는 미검증으로 유지한다. Critical/Important 수정 또는 deferred Minor는 없다.

### M1-B 최종 양 OS GREEN / 인계 기록 진행
- Node31/0·v2/v3 --check exit0(minote-m1b-node-before-review), core60/0(minote-m1b-core-before-review). 마지막 core/JS 실행 후 코드 변경은 없다.
- 최종 순차 전체18.6/26.4: 각각 app **53/0**, 일반 UI **5 passed / fixture-only1 skipped / 0 failures**, 양 xcodebuild exit0 TEST SUCCEEDED. logs/results /private/tmp/minote-m1b18-serial-final.log/xcresult, minote-m1b26-serial-final.log/xcresult. 두 번째는 20:46:58 KST에 종료했다. 기존 timeout/실패/종료143과 성공 결과를 구분한다.
- 정확한 공통 명령: xcodebuild -project MiNote.xcodeproj -scheme MiNote -destination 'platform=iOS Simulator,id=<18:7964CDF4-782A-44C2-BC51-1176AF6C67AB|26:423D4FF6-C678-45F9-9D3E-CB886EE82462>' -derivedDataPath <18:/private/tmp/minote-m1b-dd18|26:/private/tmp/minote-m1b-dd26-fresh> -resultBundlePath /private/tmp/minote-m1b<18|26>-serial-final.xcresult -parallel-testing-enabled NO -collect-test-diagnostics never CODE_SIGNING_ALLOWED=NO test (26은 COMPILATION_CACHE_ENABLE_CACHING=NO 추가). 실제 구체 명령은 로그 첫 줄에 있다.
- 별도 seeded migration 양 UI1/0/skip0 + helper --verify exit0. raw legacy JSON/backup/PDF bytes 보존. 이번에 만든 migration18/26 두 기기는 shutdown했고 파일/기기는 보존했다. 일반 기기는 최종 시험 도구의 수명주기를 따른다.
- fresh 전체 reviewer 한 번(80d14c2..1d67d9a), 확정 코드 결함/Minor 없음. 초기 With fixes는 최종 UI 게이트였으며 지금 양 전체 GREEN으로 충족했다. 추가 reviewer나 추측성 앱 수정 없음. 실제 Pencil/손바닥/발열/큰 실제 PDF/전체 접근성은 대기다.
- 다음 M1-C 계획을 실제 v3/여러 자산/삭제 보관/원본 backup/임시 export 현황으로 자기 점검했다. backup 복원/새 UUID 충돌·CRC/경로/취소·journal과 backup 참조·share lease를 Task1~4 시험에 연결하고 Task5에 양 OS/별도 이주/한 번 리뷰/다음 단계 기록을 둔다. M1-C 구현은 이번 실행에 포함하지 않는다.
- 남은 마감: Notion에 milestone append/re-fetch → 마지막 반영 시각/최종 인계 문서 commit → clean 확인. main 직접 작업/로그·scratch 보존은 사용자 승인에 따른 마감 판단이며 merge/PR/push/cleanup 메뉴는 적용하지 않는다.

### M1-B 최종 인계
- Task1~5 구현·검증·한 번 리뷰·Notion 반영을 완료했다. 기능 코드1d67d9a, 마지막 테스트/체크포인트 fddbd66. 최종 문서 커밋은 이 기록을 포함한 HEAD(`git log -1 --oneline`)다. 기본 main에 커밋했고 이번 실행에서 push하지 않았다. 새 원격 조회 없음.
- Notion task_bc850ab357544ae1bd2db01d44b43246 succeeded. page_last_edited_at 2026-10-03T11:50:06.629Z, 재조회 검증 11:50:59 UTC. 새 heading 한 개와 이전 본문 전체 prefix 보존, 실제 검증 counts/커밋/미구현 M1-C를 확인했다. 같은 결과는 docs/milestones/2026-10-03-m1-b-pages-and-pdfs.md와 실제 9페이지 export screenshot에 있다.
- 실행 상태: 진행 중 코드 변경 없음. 기존 로그/result/scratch/시뮬레이터 자료는 보존한다. 다음은 AGENTS/PROGRESS와 docs/superpowers/plans/2026-10-03-m1-c-backup-and-cleanup.md를 읽고 Task1 archive 보존/손상 RED부터 시작한다. M1-B와 이전 완료 단계는 반복하지 않는다.
- 남은 제한: `.minote`/영구 제거/파일 정리 미구현, 통합 Undo/사용자 템플릿/객체/검색 후속, physical Pencil/손바닥/발열/대형 실제 PDF/전체 접근성 미검증. 전체 iPad 제품/다른 플랫폼 개발 완료로 주장하지 않는다.

## M1-C 시작 체크포인트 (2026-10-04)
- 기준19e10af, main clean. origin/main 추적 ref보다8커밋 앞서며 새 원격 조회 없음. main 직접 작업/기존 파일·scratch 보존/no push.
- Task1 stored-only ZIP/manifest와 실제 v3 fixture 보존 → Task2 새 노트 복원 → Task3 backup 참조와 purge journal → Task4 Files/진행·취소/공유 lease/확인 UI → Task5 양 OS 순차·별도 migration/빈 설치 백업 이동·한 번 리뷰·Notion/인계.
- 이전 단계는 반복하지 않는다. 먼저 archive의 path/CRC/header/취소/I/O 실패 RED를 확인한다. 이번 단계 구현은 아직 미완료다.
- 계획 인터페이스 점검: manifest는 자기 자신 제외 document/assets entries이며 ZIP CRC가 manifest를 보호한다. LibraryStore actor 소유 DocumentStore 때문에 restore는 필요 시 async로 구체화하며 await 전 busy/최종 catalog revision 검사를 유지한다. 파일 접근/PDFKit 검증은 앱 경계다.

### M1-C Task1 archive 체크포인트
- StoredZIP/NoteBackup: stored ZIP32, 64KiB PDF I/O, CRC/header/경계/UUID 경로 검증, 버전1 manifest, 원자 출력 교체/취소/자기 staging 정리. 기존 destination 실패 보존. ValidatedBackup은 사용 전 재검증 가능.
- 최초 API 부재 RED exit1(minote-m1c-archive-red.log). 첫 구현 컴파일 실패는 UInt32? 대 Int 비교였고 명시 UInt32 변환 후 해결. 최종 `swift test --package-path Packages/MiNoteCore` **67/0**, exit0(minote-m1c-task1-core.log). 실제 v3+PDF2개 모든 값/바이트 비교 및 Python zipfile CRC 성공. unsafe ZIP14종·CRC·future·manifest 길이/누락·진행 중 Task 취소·ENOSPC 기존 bytes 보존 확인.
- `node --test Tools/PortableInk/*.test.mjs` **31/0**, exit0(minote-m1c-task1-node.log). 아카이브 계약 docs/format/backup-v1.md. 이 결과는 archive 범위이며 Files/PDFKit 복원/정리/양 OS 앱은 아직 미실행이다.
- 다음: Task2 충돌 복원/기존 bytes/실패 orphan 회수 RED → 구현 → core → 기록/커밋. main 직접 작업/no push.

### M1-C Task2 복원 체크포인트
- commit4649208부터 새 노트 복원 구현. 코어에 없는 LibraryNoteRow 대신 실제 코어 LibraryNote를 반환하고 async actor 경계를 사용한다. 제목에 (복원)을 붙이고 필요할 때만 document UUID를 바꾸며 revision/page/stroke/asset IDs는 보존한다.
- staging CRC/문서 재검증,64KiB copy와 복사 결과 CRC, 완성 directory만 notes로 이동, 마지막 catalog commit. 취소/ENOSPC/누락/변조/없는 폴더에서는 기존 노트 bytes 불변. catalog 실패 시 완성 orphan만 다음 load에서 한 번 회수.
- API 부재 RED exit1(minote-m1c-restore-red.log), 관련3/0 GREEN. `swift test --package-path Packages/MiNoteCore` **70/0**, exit0(minote-m1c-task2-core.log). 빈/중복복원·원본 byte·재열기·복사 실패·취소·orphan 검증. 앱 PDFKit 실제 geometry gate/Files 설치 이동은 Task4/5 대기.
- 다음: Task3 cleanup은 DocumentStore actor 안에서 snapshot 검사와 삭제를 함께 수행해 attach/save와 직렬화한다. Library purge journal은 primary commit을 기준으로 commit 전 복구/후 완결하며 primary+catalog backup에서 제거한 뒤 quarantine을 지운다. 긴 작업 전 체크포인트로 남긴다.

### M1-C Task3 파일 수명 체크포인트
- ab1bd27부터 DocumentStore actor 내부 primary+backup 정확한 자산 union 검증/정리, 오류 snapshot 보류, UUID PDF만 후보. unknown/legacy는 유지. 삭제 페이지 purge는 정확한 IDs·revision을 요구하고 현재 잔존 페이지에서 쓰지 않는 해당 자산만 등록 해제하며 previous backup을 보존한다.
- prepared→catalogCommitted→finished journal과 quarantine. load는 orphan 회수 전에 journal을 처리한다. catalog primary가 commit 기준이며 정상 fallback도 대상 참조를 제거한 뒤 bytes 제거. invalid/future/path/중복 위치는 편집 차단. 실패 중 읽기/편집 캐시를 공개하지 않는다.
- API 부재 RED(minote-m1c-maintenance-red); 첫 실행5tests/2failure는 /var↔/private/var URL 별칭 비교 문제라 테스트에서 canonical URL 비교로 수정. 별도 stale handle 재생성 RED3failure(minote-m1c-retired-handle-red) 확인 후 삭제 전 DocumentStore.retire를 await하고 이전 참조 save/load를 차단했다. purgeTrashedNote는 이 직렬화를 위해 async로 구체화했다.
- 최종 `swift test --package-path Packages/MiNoteCore` **77/0**, exit0(minote-m1c-task3-core.log). 7개 write 경계 중단/실제 journal·primary·backup ENOSPC/전후 복구·catalog fallback 재등장 방지·future backup 보존·잘못된 journal 경로·최신 획/이전 backup-only PDF 보존 검증.
- 다음 Task4 앱 연결/실제 Files 확인/공유 lease. core 구현만 검증했고 양 OS app/UI/리뷰/Notion은 대기. 이전 테스트/scratch는 보존한다.
