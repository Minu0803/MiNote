# MiNote schema v2 기본 필기 계약

2026-10-03. 현재 코드 `DocumentCodec`, `Document.swift`, `PDFAsset.swift`, `InkAdapter`의 계약이다. M0-C 시험 편집기의 지원 범위는 더 좁으며 완전한 브러시/플랫폼 호환성을 의미하지 않는다.

## 문서와 페이지

JSON에는 `schemaVersion: 2`, UUID `id`, 0 이상 Int64 `revision`, 문자열 `title`, 비어 있지 않은 `pages`를 둔다. 선택 필드 `pdfAsset`, `lastOpenedPageID`는 생략 또는 null이다. 마지막 페이지 ID는 실제 페이지를 참조한다. 페이지는 UUID `id`, 양수 유한 `width`/`height`, `strokes`, 선택 `pdfSource`를 가진다. 페이지 ID는 문서 내에서, 획 ID는 모든 페이지에 걸쳐 유일하다. UUID 비교는 대소문자를 구분하지 않는다.

좌표는 **페이지 좌상단 원점, 1/72인치**다. 화면 픽셀/확대 배율은 저장하지 않는다. PDF 페이지 크기는 회전된 crop box 크기다. source metadata의 raw media/crop 원점은 별개이며 필기 좌표에 다시 더하지 않는다.

PDFAsset은 UUID `id`, `originalFilename`, 양수 정수 `pageCount`/`byteCount`, 유한 Unix 초 `importedAt`이다. 앱의 자산 경로는 `assets/<UUID>.pdf`로 유도하며 외부 URL은 문서에 넣지 않는다. PDFPageSource는 0 기반 `index`, 유한 x/y와 양수 width/height의 `mediaBox`/`cropBox`, 0/90/180/270 `rotation`이다. index는 중복 없이 전체 asset.pageCount와 일치한다. 페이지 크기와 회전된 crop box는 0.001pt 미만 차이여야 한다.

## 획과 제어점

InkStroke는 UUID `id`, `tool`(pen/marker), RGBA `color`(각 0…1), 비어 있지 않은 `points`, `transform`, UInt32 `randomSeed`, 유한 Unix 초 `creationTime`을 보존한다. pen/marker 외의 도구, 부분 삭제 mask 및 표현하지 못하는 PencilKit 속성은 iPad 어댑터에서 오류로 처리한다.

| InkPoint 필드 | 의미와 검증 |
|---|---|
| x, y | 획 로컬 제어점 좌표, 유한 |
| timeOffset | 생성 시각부터 초, 0 이상이며 비감소 |
| width, height | 제어점에서의 필기 크기, 유한·0 이상 |
| opacity | 제어점 불투명도, 0…1 |
| force | 압력 정보, 유한·0 이상 |
| azimuth, altitude | 기울기 정보, 유한 라디안 |
| secondaryScale | 보조 크기 배율, 유한·0 이상; 이전 파일에서 생략 시 1 |

affine 필드 `a,b,c,d,tx,ty`는 유한이고 `abs(a*d-b*c)>1e-12`다. 로컬 좌표에서 페이지 좌표로 `X=a*x+c*y+tx`, `Y=b*x+d*y+ty`를 적용하고 마지막에 viewport 배율을 적용한다. 이동은 페이지 pt의 dx/dy를 tx/ty에 더하며 제어점/style은 바꾸지 않는다.

PencilKit 왕복은 모든 위 필드와 seed를 재구성한다. PKStrokePoint는 재구성할 때 기울기 등을 다시 양자화할 수 있다. 어댑터는 원본과 실제 재구성 결과의 정확한 fingerprint를 모두 후보로 만들고, 전체 획 순서에 맞는 대응이 유일할 때 원래 ID와 원본 속성 전체를 반환한다. raw 우선 탐욕 대응이나 epsilon으로 ID를 결정하지 않는다. 현재 지원 편집은 새 획 추가/획 전체 삭제이며 살아남은 획 순서를 유지한다. 순서 변경은 후속 편집 모델에서 다룬다.

같은 모양의 다른 획은 전체 순서로 식별할 수 있는 범위에서 고유 ID를 유지한다. 완전히 같은 두 인접 획 중 하나만 남는 등 ID 대응이 여러 가지면 `ambiguousIdentity` 오류로 직렬화를 차단한다. 현재 그림과 기존 저장본을 유지하며 임의의 ID나 속성으로 덮어쓰지 않는다. iPadOS 18/26에 공개된 stroke ID를 가정하지 않는다. 페이지별 이력을 쓰며 정규화 후보 재구성 비용은 복잡한 페이지의 M3 측정 대상이다. seed가 렌더러의 브러시 외관을 자동으로 같게 만드는 것은 아니다.

## M0-C 시험 편집기의 계약

시험 도구는 v2 기본 획의 읽기·ID로 이동·획 전체 삭제·새 pen 추가를 수행한다. 원본 문서를 변경하지 않고 성공한 편집마다 revision을 한 번 증가시킨다. 모든 원본 metadata와 수정하지 않은 획 속성은 보존한다. PDF 원본 bytes는 별도 fixture로 보존하고 브라우저는 PDF 배경을 그리지 않는다.

JavaScript 수치의 정확성을 위해 revision/정수 metadata는 safe integer 범위만 편집한다. 더 큰 Int64 revision, 미래 schema, 알 수 없는 필드/도구/잘못된 수치는 편집·저장을 거부한다. iPad의 지원 범위를 전체 JavaScript 도구로 확장했다고 주장하지 않는다. 파일을 거부해도 원본 텍스트와 기존 열린 문서를 보존한다.

Canvas는 크기가 변하는 타원/구간으로 기본 pen/marker를 근사한다. 압력·시간·기울기·seed는 파일에 보존하지만 PencilKit의 곡선/texture/marker 합성과 동일한 픽셀을 보장하지 않는다. renderer의 좌표 오류는 실패, 문서 데이터가 유지되는 texture 차이는 측정된 제한으로 기록한다.

fixture 생성/회수 절차는 `Packages/MiNoteCore/Tests/MiNoteCoreTests/Fixtures/PortableInk/README.md`를 따른다. 두 test bundle은 같은 파일을 resources로 복사한다. 개발 Mac의 절대 파일 경로를 simulator 테스트에서 읽거나 사용자 노트를 덮어쓰지 않는다.
