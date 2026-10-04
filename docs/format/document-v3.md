# MiNote 문서 schema v3

M1-B의 Foundation 문서/저장과 iPad 편집기, 독립 JavaScript 시험 도구의 계약이다. 획·좌표·PencilKit 양자화 및 렌더러 제한은 `ink-v2.md`의 필기 규칙을 유지한다. 서버 동기화 규격이 아니다.

## 문서·페이지·자산

- 문서: `schemaVersion: 3`, UUID `id`, 0 이상 Int64 `revision`, `title`, 비어 있지 않은 `pages`, `pdfAssets`, `deletedPages`, 선택 `lastOpenedPageID`.
- 모든 활성/삭제 페이지는 `id`, 유한 양수 `width`/`height`, `strokes`, `paper`(blank/ruled/grid), Bool `isBookmarked`, 선택 `pdfSource`를 가진다. v3에서 용지·책갈피 필드는 필수다. 기본 새 페이지는 흰색 A4 595.2756×841.8898pt이며 좌상단 원점/1pt=1/72인치다.
- PDF source: 등록된 자산의 UUID `assetID`, 0 기반 `index`, 원본 `mediaBox`/`cropBox`, `rotation`(0/90/180/270). 크기는 회전된 crop box와 0.001pt 미만 차이다. 같은 자산/index를 여러 페이지가 참조하거나 일부 index만 남아 있어도 유효하다. PDF 페이지의 paper는 blank다.
- 자산의 `id`, `originalFilename`, `pageCount`, `byteCount`, `importedAt`는 원본 metadata다. 파일은 노트 디렉터리의 `assets/<UUID>.pdf`이며 파일명으로 경로를 만들지 않는다. 활성 참조가 없는 보관 자산도 유지·검사한다.
- `DeletedPage`는 `page` 전체, 삭제 당시 `originalIndex`(0…999), Unix 초 `deletedAt`(유한·0 이상)이다. ID는 내부 page.id다. `lastOpenedPageID`는 활성 페이지만 참조한다.
- 문서·자산·활성/삭제 페이지·획 ID는 한 문서 안에서 겹치지 않는다. 문자열 UUID 비교는 대소문자를 구분하지 않는다. 획 ID는 삭제 페이지를 포함해 유일하다.
- 현재 상한: 활성+삭제 페이지 1,000개, 보관 자산 합계 500MiB, 개별 PDF 100MiB/500페이지/회전 후 한 변 2,000pt. 실기기 성능을 보증하는 수치가 아니다.

## 구버전과 저장

`DocumentCodec.decode`는 v1/v2/v3를 읽고 메모리 문서를 v3로 정규화한다. v1은 PDF 없는 단일 페이지, v2는 단일 PDF의 원본 index 전체·유일 mapping을 먼저 검사한다. v2 pdfAsset은 pdfAssets로 옮기고 해당 페이지 source.assetID를 연결한다. 기존 문서/페이지/획/자산 IDs, revision, ink/geometry는 유지하며 새 용지는 blank/책갈피 false/삭제 목록 []다. encode는 v3만 출력한다.

첫 재저장 전 정상 primary의 raw v1/v2 bytes를 backup으로 기록한다. 라이브러리 최초 이주는 루트의 raw primary/backup/PDF를 유지하고 노트별 디렉터리에 모든 자산을 복사한다. catalog는 version 1 그대로다. 이후 backup은 직전 정상 저장본이다.

DocumentStore actor는 revision 확인부터 JSON 원자 교체까지 suspension 없이 수행한다. 새 자산을 원자 저장한 뒤 참조를 JSON에 commit한다. 실패한 새 자산은 미연결 상태로 보존하며 M1-C에서 정리한다. 모든 보관 자산의 regular file/byteCount를 확인하고, 누락/크기 불일치·미래 schema·I/O 오류로 빈 문서를 만들거나 이전 단일 PDF로 돌아가지 않는다. 기존 정상 JSON·backup은 보호한다.

## 페이지 명령과 편집기

`PageCommands.apply(_:to:)`는 입력 value를 바꾸지 않고 성공당 revision을 한 번 증가시킨다.

| 명령 | 결과와 선택 |
|---|---|
| insert(after:paper:) | 해당 페이지 뒤에 새 A4, 새 페이지 선택 |
| duplicate | 바로 뒤에 새 페이지/모든 획 IDs, ink/geometry/PDF 참조 유지, 책갈피 false, 복제본 선택 |
| move(toIndex:) | 제거 후 최종 0 기반 index로 삽입, 기존 선택 ID 유지 |
| delete | 마지막 페이지 삭제 금지; 전체 페이지/index/시간 보관; 현재 페이지 삭제 시 가까운 남은 페이지 선택 |
| restore | 원래 index를 활성 수 이내로 clamp, 원래 모든 IDs/ink/source 유지, 복원본 선택 |
| setPaper / setBookmark | 활성 페이지 속성만 변경, 선택 유지; PDF 용지는 변경 금지 |

스토어 명령은 `expectedRevision`이 현재 파일과 같아야 한다. 구조와 선택을 같은 저장에 포함한다. PDF 가져오기는 선택한 활성 페이지 바로 뒤에 삽입하고 첫 새 PDF 페이지를 선택한다.

편집 세션은 현재 drawing을 먼저 flush하고 저장 상태/전체 snapshot을 await 뒤 다시 확인한다. 실패·지원하지 않는 drawing·늦은 native callback이면 같은 화면을 유지한다. actor commit 중 추가 필기가 도착한 드문 경합은 원래 구조+최신 필기를 더 높은 revision으로 보상 저장해 구조 작업을 취소한다. 보상 실패도 drawing/문서를 메모리에 유지하고 재시도한다. 이를 위해 세션 구조 작업은 Int64.max−1 이상에서 차단하며 공통 value 명령은 정상 Int64 경계를 따른다.

페이지/구조 전환은 새 Canvas generation으로 Undo history를 다시 시작하고 오래된 delegate를 받지 않는다. 통합 구조 Undo는 후속이다. 화면 PDF cache는 2개, 썸네일 cache는 24개/한 변 256px다. 오래된 pageID/revision 결과는 게시하지 않는다.

## 용지·PDF 출력·독립 도구

줄/격자는 24pt 간격, 0.5pt 회색(white=0.85) 선으로 화면/썸네일/출력에서 같은 좌표를 쓴다. PDF 원본은 변경하지 않는다. 활성 페이지를 문서 순서대로 출력하며 각 source page를 복사한 뒤 그 페이지 ink만 붙인다. 삭제 페이지는 출력하지 않는다. 모든 sourceURLs 누락/출력 경로 중복은 오류다.

필기는 최대 216dpi/한 변 4096px 이미지로 고정하며 원본 PDF 본문 텍스트/벡터와 crop/rotation을 유지한다. 원본 양식·주석 및 일부 링크는 영향을 받는다. 이미지 출력은 편집 가능한 백업이 아니다.

JS는 v2 입력을 v2로, v3 입력을 v3로 출력한다. v3 active-page 획 이동/삭제/새 pen 추가 때 자산/삭제 페이지/용지/책갈피/미수정 IDs를 유지한다. 미래 schema/알 수 없는 필드/잘못된 관계/unsafe integer는 거부하며 기존 열린 문서를 보존한다. Canvas는 기본 획을 근사하고 용지를 표시하며 PDF 원본 배경은 표시하지 않는다.

실제 PencilKit에서 만든 `multi-source.json`을 기존 manifest `edits.json`으로 처리한 결과가 `multi-edited.json`이다. iPad 테스트는 이 파일을 다시 편집·Undo/Redo·저장·재열기하고 두 자산 및 삭제 페이지를 비교한다. 실기기 Apple Pencil/장시간/발열/큰 실제 PDF 검증은 대기다.

## M2-A 선택·이동과 현재 페이지 이력

`InkCommands.translate(strokeIDs:pageID:dx:dy:expectedRevision:in:)`는 활성 페이지의 정확한 UUID 집합/리비전과 문서 전체를 검증한다. 선택 획의 `transform.tx/ty`에 문서 단위 이동량만 더하며 점·선형 변환·ID·순서·비선택 데이터는 유지한다. 성공한 이동/Undo/Redo는 revision을 한 번 증가시킨다. 빈 선택/0 이동은 무변경이고 비유한 값·합산 overflow·stale/잘못된 ID는 오류다. 유한 페이지 밖 위치는 허용한다.

선택 polygon/UUID 집합/drag ghost는 화면 상태이며 JSON/backup/PDF에 넣지 않는다. 닫힌 even-odd 영역 또는 경계에 보간 중심선이 닿으면 획 전체를 선택한다. affine 변환 후 페이지 단위 최대2pt 간격으로 중심선을 검사하며 굵기 외곽만 닿는 경우는 선택하지 않는다. 선택 내부 drag 종료 한 번만 명령을 적용하고 취소/zoom/회전은 preview를 제거한다. navigation pan은 Pencil 입력을 제외해 필기/올가미와 경쟁하지 않는다.

앱의 `InkCanvasView`가 실제 UndoManager를 소유한다. opaque PencilKit 내부 등록 대신 실제 delegate 입력 snapshot과 이동 명령을 같은 이력에 등록하고, 같은 gesture의 후속 callback은 최종 drawing으로 합친다. 명시적 canvas 캡처도 같은 coordinator를 통과한다. 시스템/toolbar Undo 모두 처리 중·저장 실패·다른 page/generation에서 replay 전에 차단한다. 미지원 필기만 메모리에 남은 경우에는 Undo로 정상 필기를 회복할 수 있다.

원래 native drawing을 유지하며 UUID별 현재 canonical value와 이동 전후 historical aliases를 구분한다. 다른 UUID 사이 provenance가 모호하면 추측하지 않고 오류로 현재 화면/정상 저장본을 보존한다. Undo 이력/aliases는 현재 캔버스 수명에만 존재하며 페이지 전환·복원·재실행 때 초기화한다.

actual app의 `lasso-source.json` revision40에서 PDF 페이지 획을 (30,-15) 이동해 `lasso-moved.json` revision41을 만들었다. 독립 JS가 같은 이동 결과 전체를 비교하고 추가 편집한 `lasso-edited.json` revision44를 iPad가 다시 편집/Undo/Redo/save/reopen한다. schema v3/catalog v1/backup v1은 변경하지 않았다.
