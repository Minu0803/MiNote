# MiNote 필기 클립보드 v1

사용자가 **복사** 또는 UIKit **붙여넣기**를 실행할 때만 접근한다. 앱은 clipboard 내용·유무를 자동 조회하지 않는다. UIKit paste control은 OS가 제공하는 자체 availability를 사용한다. `com.minote.ink-selection`은 `public.data`를 따르는 JSON이며 이 단계에서 일반 텍스트/이미지/PDF는 받지 않는다.

payload의 최상위 필드는 `schemaVersion: 1`과 `strokes: [InkStroke]`다.

실제 strokes 배열은 document-v3의 InkStroke를 그대로 사용한다. root·획·색상·변환·점의 필드는 모두 필수이며 unknown key도 오류다. `secondaryScale`도 clipboard에서는 생략할 수 없다. 제목·PDF bytes·폴더·페이지·Undo·선택 overlay는 포함하지 않는다. 버전 오류, 중복 ID, 지원하지 않는 도구, 잘못된 숫자/변환과 데이터는 부분 적용하지 않는다.

초기 한도는 JSON 8MiB, 2,000획, 합계100,000 제어점이다. decode 전 byte 한도, 객체 검증 전 획/점 수, encode 완료 후 byte 한도를 검사한다. 문서 성능이나 실기기 사용량 보장은 아니며 M3에서 측정한다. file provider URL은 callback 동안 read-only로 읽으며 최대8MiB+1에서 거부한다. 취소와 callback 경쟁은 continuation을 한 번만 완료한다.

복사는 원본 문서 순서대로 선택 전체 획을 담는다. 빈 선택과 실패한 encoding은 기존 clipboard·문서·이력을 보존한다. 붙여넣기는 모든 새 UUID로 현재 페이지 끝에 추가한다. 모든 필기값을 유지하고 tx/ty만 이동한다. source ID를 재사용하지 않는다.

시작의 실제 live canvas를 캡처한 문서ID/pageID/generation/revision·coordinator 소유 stamp와 viewport 중심을 유지한다. 읽는 동안 전환/편집/실패/backup busy가 발생하면 적용을 거부한다. 완료 시 delegate 전의 최종 canvas도 캡처해 새 필기를 보존한다. 중심선 제어점에 affine을 한 번 적용한 bbox 중심을 시작 viewport의 페이지 좌표 중심에 맞춘다. crop/rotation/zoom은 중복 적용하지 않는다. 페이지 밖 유한 좌표는 자르지 않는다.

성공은 같은 native UndoManager의 한 명령이며 새 획만 선택한다. Undo/Redo는 정확한 ID/value snapshot을 복구하고 선택을 비운다. 페이지·노트 전환/복원/relaunch는 현재 이력을 초기화한다. 다른 페이지로 paste한 뒤 source 페이지의 pen을 undo하는 기능은 없다.

schema3/catalog1/backup1은 유지한다. 실제 앱의 clipboard-payload/target/pasted와 새 UUID만 공유하는 manifest를 독립 JS가 계산해 비교한다. 독립 추가 편집 결과를 iPad가 owned native Undo·저장·재열기로 소비한다. JS는 시험 도구이며 다른 플랫폼 앱이나 외부 앱 clipboard 호환 보장이 아니다.
