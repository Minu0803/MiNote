## 2026-10-03 M1-A 구현 결과 — 여러 노트와 로컬 라이브러리

**상태: 여러 노트·폴더·휴지통·안전한 편집 세션 전환 구현 및 시뮬레이터 검증 완료. iPad 제품 전체는 아직 개발 중이다.**

### 사용자가 할 수 있는 것

- 새 노트를 만들고 각각의 A4 페이지에 필기한다. 노트마다 JSON, 획 ID·리비전, PDF 원본과 페이지별 필기가 독립적으로 저장된다. 다른 노트를 열거나 앱을 다시 실행해도 저장한 내용으로 이어 쓴다.
- 노트와 폴더 이름을 바꾸고 중첩 폴더에 정리한다. 모든 노트·수정 기준 최근 노트·폴더·휴지통을 탐색한다. 같은 이름의 폴더도 경로와 안정적인 짧은 식별자로 구별한다.
- 휴지통으로 옮긴 노트를 원래 폴더 관계와 필기를 유지해 복원한다. 영구 삭제와 폴더 삭제는 제공하지 않는다.
- 편집기에서 라이브러리로 돌아갈 때 현재 필기 저장과 수정 시각 기록이 끝난 뒤 이동한다. 저장 실패·지원하지 않는 필기·닫는 동안 도착한 추가 필기가 있으면 동일 노트와 화면 필기를 유지한다.
- 이전 단일 노트 설치는 ID·전체 필기·PDF를 보존한 채 새 목록으로 이주한다. 이전 원본 JSON·복구본·PDF는 루트에 남긴다. 손상된 문서를 빈 노트로 교체하지 않고 오류 항목으로 표시한다.

### 저장 구조와 기술 판단

- 공통 모델과 LibraryStore는 Foundation만 사용하며 UI/PencilKit/PDFKit은 앱에 둔다. 외부 의존성을 추가하지 않았다. 앱의 문서 본문은 기존 schema v2를 유지했다.
- metadata는 catalog version 1의 JSON으로 기록하고, 본문은 노트 UUID별 디렉터리로 분리했다. 제목은 본문의 NoteDocument.title에서 읽어 중복 metadata가 최신 제목이나 필기를 덮지 않게 했다.
- 한 LibraryStore actor가 catalog 리비전과 노트별 DocumentStore 인스턴스를 소유한다. async 변경은 첫 await 전에 busy를 설정하고, 문서/자산 저장 뒤 catalog를 원자적으로 commit한다. 디스크 성공 전 목록 변경을 성공으로 게시하지 않는다.
- catalog 쓰기 실패로 연결되지 않은 노트 디렉터리는 다음 load에서 복구 항목으로 회수한다. 파일이 없거나 손상된 항목도 숨기거나 삭제하지 않는다. 미래 catalog 버전·잘못된 폴더 관계·실제 I/O 오류는 빈 목록이나 이전 backup으로 대체하지 않는다. JSON 손상일 때만 정상 catalog backup을 안내와 함께 복원한다.
- 폴더 ID와 참조를 검사하고 자기 자식으로 이동하는 순환 관계와 누락 parent를 거부한다. 이름 중복은 허용하고 UUID로 관계를 유지한다. 휴지통은 metadata의 soft delete다.
- 초기 catalog는 JSON으로 충분한 범위부터 검증했다. SQLite 색인/metadata-only 조회는 검색과 큰 라이브러리 측정 근거가 생긴 뒤 판단한다. 현재 모든 노트의 본문을 읽는 목록 refresh 비용은 최적화 과제로 남긴다.

### 리뷰에서 재현하고 수정한 문제

별도 fresh reviewer 한 번으로 전체 단계 코드를 점검했다. Critical 없음, Important 1건과 Minor 1건이었다.

- 노트 닫기 경합: 첫 flush 뒤 metadata 저장과 목록 refresh를 기다리는 동안 늦은 필기가 도착하면 메모리에는 2획/리비전 2, 디스크에는 1획/리비전 1인데 editor가 제거됐다. 실제 catalog commit에서 늦은 PKDrawing을 전달해 RED를 재현했다. 마지막 await 뒤 최신 문서 전체와 저장 상태를 다시 검사하고 추가 await 없이 editor를 제거한다. 늦은 변경/직렬화 실패는 editor를 유지하며 다음 닫기에서 최신 저장을 확인한다. native canvas도 화면의 enabled 상태를 반영하고 queued callback은 검사 대상으로 받는다.
- 같은 이름 폴더: 실제 UI의 두 폴더 destination label이 같아 사용자가 의도한 위치를 구별할 수 없었다. RED 이후 동일 parent/name의 각 경로 segment에 최소 유일 UUID suffix를 붙이고 모든 ancestor를 VoiceOver와 이동 목록에 포함했다. 식별자 suffix 충돌은 길이를 늘려 구별한다. 실제 두 폴더 사이 이동과 이름 정렬 후 안정성을 확인했다.

### 검증 근거

- `swift test --package-path Packages/MiNoteCore`: **44개, 실패 0**, exit 0. 이전 노트 v1/v2·raw backup·PDF 이주, 실패 후 재시도, 미연결 노트 회수, 두 노트 격리, 최신 필기 후 이름 변경, 폴더 순환/누락, 휴지통 복원, catalog 실패/동시 변경/오래된 actor 차단을 포함한다.
- `node --test Tools/PortableInk/*.test.mjs`: **25개, 실패 0**. `node Tools/PortableInk/roundtrip.mjs --check`: exit 0. 리뷰 수정은 공통 코어와 독립 필기 도구를 변경하지 않았다.
- iPad Pro 11 M4 / iPadOS 18.6, iPad Pro 11 M5 / iPadOS 26.4: 각각 **앱 단위 42개 + 일반 UI 4개 통과, 실패 0**, 양 xcodebuild exit 0 / TEST SUCCEEDED.
- 일반 suite에는 입력 fixture가 없어서 건너뛴 이주 전용 UI 1개가 별도로 있다. 빈 전용 시뮬레이터에 legacy fixture를 seed하여 두 OS에서 각각 **이주 UI 1개 통과, skip 0**을 확인했다. 원본 JSON·backup·PDF bytes 불변과 새 노트의 ID·획·PDF·리비전을 helper로 재확인했다. 이를 일반 suite의 skip과 혼동하지 않는다.
- UI는 실제 손가락 획, 필기 직후 닫기/다른 노트 열기, 폴더 이동/rename, 중복 폴더 선택, 휴지통 복원, 앱 재실행, 기존 Undo/Redo와 Files PDF 가져오기·페이지 탐색·화면 회전·내보내기 미리보기/공유 시트를 실행했다. 늦은 callback 회귀 시험은 programmatic 입력이며 실제 Pencil 측정과 구분한다.
- 최종 로그: `/private/tmp/minote-m1a-core-final.log`, `minote-m1a-node-final.log`, `minote-m1a18-review-final.log`, `minote-m1a26-review-final.log`, `minote-m1a18-migration.log`, `minote-m1a26-migration.log`. 양 review-final/migration xcresult와 첫 실패 이력은 보존했다.

### 커밋과 재개 자료

- `aa92907`: 기존 노트 보존 이주와 catalog 읽기/저장.
- `0ca9545`: 독립 노트·폴더·휴지통 변경.
- `1621e11`: 저장 완료를 보장하는 편집 세션 전환.
- `d44aad5`: 라이브러리 화면과 양 OS UI·별도 이주 검증.
- `d968701`: 늦은 필기 손실 방지와 중복 폴더 구별 리뷰 수정.
- 작업 위치는 기본 저장소의 main이다. 별도 branch/worktree/PR을 만들지 않았고 이번 실행에서 push하지 않았다. 기록/다음 계획은 별도 문서 커밋으로 보존한다.
- 재개 문서: `AGENTS.md`, `docs/PROGRESS.md`, `docs/format/library-v1.md`, `docs/superpowers/plans/2026-10-03-m1-b-pages-and-pdfs.md`. 다음 작업자는 Git과 기록을 대조하고 완료된 M0/M1-A를 반복하지 않는다.

### 현재 제한과 다음 계획

- 노트당 PDF 하나, 초기 흰색 A4와 가져온 PDF 페이지다. 페이지 추가/복제/재정렬/삭제·용지/책갈피와 한 노트의 여러 PDF는 아직 구현하지 않았다.
- 즐겨찾기·제목/폴더/본문 검색·올가미·텍스트·이미지와 동기화/타 플랫폼 앱은 후속이다. Undo history는 페이지/노트 전환 때 다시 시작한다.
- `.minote` 백업·복원, 영구 제거, export 임시 파일/중단 import 자산 cleanup은 M1-C다. 공유 소비자의 파일 사용을 보장하는 수명주기가 필요하다.
- 실제 Pencil 지연·손바닥·발열·장시간 필기·많은 노트/큰 이미지 PDF·전체 접근성/분할 화면 검증은 대기다. 이번 결과는 시뮬레이터에서 확인한 범위다.
- 다음 M1-B 계획은 schema v3로 PDF 자산 배열과 페이지별 참조를 만들고, 기존 v1/v2 원본을 보존하며 페이지 관리·삭제 보관/복원·줄/격자 용지·책갈피·다중 PDF 출력 및 독립 v2/v3 왕복을 단계별로 검증한다. **계획만 작성했으며 아직 M1-B 코드는 구현하지 않았다.**
