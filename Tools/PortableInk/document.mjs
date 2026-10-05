// A deliberately narrow, DOM-free schema-v2/v3 editor. Reject unsupported input
// before cloning/encoding so JSON.stringify cannot quietly discard user data.
export class PortableInkError extends Error {}
const fail = message => { throw new PortableInkError(message); };
const sameID = (a, b) => a.toLowerCase() === b.toLowerCase();
const uuid = (value, label) => {
  if (typeof value !== 'string' || !/^[\da-f]{8}(-[\da-f]{4}){3}-[\da-f]{12}$/i.test(value)) fail(`${label}: UUID가 필요합니다.`);
};
function shape(value, fields, label) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) fail(`${label}: 객체가 필요합니다.`);
  for (const key of Object.keys(value)) if (!fields.includes(key)) fail(`${label}: 지원하지 않는 필드 ${key}`);
}
function number(value, label, min = -Infinity, max = Infinity) {
  if (!Number.isFinite(value) || value < min || value > max) fail(`${label}: 수치 범위를 확인하세요.`);
}
function integer(value, label, min = 0, max = Number.MAX_SAFE_INTEGER) {
  if (!Number.isSafeInteger(value) || value < min || value > max) fail(`${label}: 정확하게 표현할 수 있는 정수가 필요합니다.`);
}
function rect(value) {
  shape(value, ['x','y','width','height'], 'PDF box');
  number(value.x, 'box x'); number(value.y, 'box y');
  number(value.width, 'box width'); number(value.height, 'box height');
  if (value.width <= 0 || value.height <= 0) fail('PDF box 크기는 양수여야 합니다.');
}
function stroke(value, ids) {
  shape(value, ['id','tool','color','points','transform','randomSeed','creationTime'], '획');
  uuid(value.id, '획 ID');
  const id = value.id.toLowerCase();
  if (ids.has(id)) fail('중복된 획 ID입니다.');
  ids.add(id);
  if (!['pen','marker'].includes(value.tool)) fail('지원하지 않는 필기 도구입니다.');
  integer(value.randomSeed, 'randomSeed', 0, 4294967295);
  number(value.creationTime, 'creationTime');
  shape(value.color, ['red','green','blue','alpha'], '색상');
  for (const key of ['red','green','blue','alpha']) number(value.color[key], key, 0, 1);
  shape(value.transform, ['a','b','c','d','tx','ty'], 'transform');
  for (const key of ['a','b','c','d','tx','ty']) number(value.transform[key], key);
  const t = value.transform, determinant = t.a * t.d - t.b * t.c;
  if (!Number.isFinite(determinant) || Math.abs(determinant) <= 1e-12) fail('역변환할 수 없는 transform입니다.');
  if (!Array.isArray(value.points) || value.points.length === 0) fail('획 제어점이 필요합니다.');
  let prior = 0;
  for (const p of value.points) {
    shape(p, ['x','y','timeOffset','width','height','opacity','force','azimuth','altitude','secondaryScale'], '제어점');
    for (const key of ['x','y','azimuth','altitude']) number(p[key], key);
    for (const key of ['width','height','force']) number(p[key], key, 0);
    number(p.secondaryScale ?? 1, 'secondaryScale', 0);
    if (p.secondaryScale === null) fail('secondaryScale은 생략하거나 수치여야 합니다.');
    number(p.opacity, 'opacity', 0, 1);
    number(p.timeOffset, 'timeOffset', prior); prior = p.timeOffset;
    number(t.a * p.x + t.c * p.y + t.tx, '변환 x');
    number(t.b * p.x + t.d * p.y + t.ty, '변환 y');
  }
}
function validateV3(document) {
  shape(document, ['schemaVersion','id','revision','title','pages','pdfAssets','deletedPages','lastOpenedPageID'], '문서');
  uuid(document.id, '문서 ID'); integer(document.revision, 'revision');
  if (typeof document.title !== 'string') fail('문서 제목은 문자열이어야 합니다.');
  if (!Array.isArray(document.pages) || !document.pages.length || !Array.isArray(document.deletedPages) ||
      document.pages.length + document.deletedPages.length > 1000 || !Array.isArray(document.pdfAssets)) fail('페이지/자산 목록 또는 수 제한입니다.');
  const ids = new Set([document.id.toLowerCase()]), assets = new Map(), active = new Set();
  function objectID(value, label) {
    uuid(value,label); const key=value.toLowerCase();
    if (ids.has(key)) fail('중복된 object ID입니다.'); ids.add(key); return key;
  }
  let totalBytes=0;
  for (const asset of document.pdfAssets) {
    shape(asset, ['id','originalFilename','pageCount','byteCount','importedAt'], 'PDF asset');
    const id=objectID(asset.id,'asset ID');
    integer(asset.pageCount,'pageCount',1,500); integer(asset.byteCount,'byteCount',1,100*1024*1024);
    number(asset.importedAt,'importedAt');
    if (typeof asset.originalFilename !== 'string' || !asset.originalFilename) fail('PDF 파일명이 필요합니다.');
    totalBytes+=asset.byteCount; if(totalBytes>500*1024*1024) fail('자산 용량 제한입니다.'); assets.set(id,asset);
  }
  function page(value,isActive) {
    shape(value,['id','width','height','strokes','pdfSource','paper','isBookmarked'],'페이지');
    const id=objectID(value.id,'페이지 ID'); if(isActive) active.add(id);
    number(value.width,'width'); number(value.height,'height');
    if(value.width<=0 || value.height<=0) fail('페이지 크기는 양수여야 합니다.');
    if(!['blank','ruled','grid'].includes(value.paper) || typeof value.isBookmarked!=='boolean') fail('용지/책갈피 정보가 잘못되었습니다.');
    const source=value.pdfSource;
    if(source!=null) {
      shape(source,['assetID','index','mediaBox','cropBox','rotation'],'PDF source'); uuid(source.assetID,'source assetID');
      const asset=assets.get(source.assetID.toLowerCase()); if(!asset) fail('등록되지 않은 PDF 자산입니다.');
      integer(source.index,'PDF index',0,asset.pageCount-1); rect(source.mediaBox); rect(source.cropBox);
      if(![0,90,180,270].includes(source.rotation) || value.paper!=='blank' || Math.max(value.width,value.height)>2000) fail('PDF rotation/용지/크기를 확인하세요.');
      const swap=source.rotation===90 || source.rotation===270;
      if(Math.abs(value.width-source.cropBox[swap?'height':'width'])>=0.001 ||
         Math.abs(value.height-source.cropBox[swap?'width':'height'])>=0.001) fail('PDF crop과 페이지 크기가 다릅니다.');
    }
    if(!Array.isArray(value.strokes)) fail('획 목록이 필요합니다.');
    for(const valueStroke of value.strokes) stroke(valueStroke,ids);
  }
  for(const value of document.pages) page(value,true);
  for(const deleted of document.deletedPages) {
    shape(deleted,['page','originalIndex','deletedAt'],'삭제 페이지');
    integer(deleted.originalIndex,'originalIndex',0,999); number(deleted.deletedAt,'deletedAt',0); page(deleted.page,false);
  }
  if(document.lastOpenedPageID!=null) {
    uuid(document.lastOpenedPageID,'lastOpenedPageID');
    if(!active.has(document.lastOpenedPageID.toLowerCase())) fail('마지막 활성 페이지가 없습니다.');
  }
}
export function validateDocument(document) {
  if(document?.schemaVersion===3) { validateV3(document); return; }
  shape(document, ['schemaVersion','id','revision','title','pages','pdfAsset','lastOpenedPageID'], '문서');
  if (document.schemaVersion !== 2) fail('시험 도구는 schema v2만 편집합니다.');
  uuid(document.id, '문서 ID'); integer(document.revision, 'revision');
  if (typeof document.title !== 'string') fail('문서 제목은 문자열이어야 합니다.');
  if (!Array.isArray(document.pages) || !document.pages.length) fail('페이지가 필요합니다.');
  const asset = document.pdfAsset;
  if (asset != null) {
    shape(asset, ['id','originalFilename','pageCount','byteCount','importedAt'], 'PDF asset');
    uuid(asset.id, 'asset ID'); integer(asset.pageCount, 'pageCount', 1); integer(asset.byteCount, 'byteCount', 1);
    number(asset.importedAt, 'importedAt');
    if (typeof asset.originalFilename !== 'string' || !asset.originalFilename) fail('PDF 파일명이 필요합니다.');
  }
  const pages = new Set(), strokes = new Set(), indices = new Set();
  for (const page of document.pages) {
    shape(page, ['id','width','height','strokes','pdfSource'], '페이지');
    uuid(page.id, '페이지 ID');
    const id = page.id.toLowerCase();
    if (pages.has(id)) fail('중복된 페이지 ID입니다.'); pages.add(id);
    number(page.width, '페이지 width'); number(page.height, '페이지 height');
    if (page.width <= 0 || page.height <= 0) fail('페이지 크기는 양수여야 합니다.');
    const source = page.pdfSource;
    if (source != null) {
      if (!asset) fail('PDF asset이 없습니다.');
      shape(source, ['index','mediaBox','cropBox','rotation'], 'PDF source');
      integer(source.index, 'PDF index', 0, asset.pageCount - 1);
      if (indices.has(source.index)) fail('중복된 PDF index입니다.'); indices.add(source.index);
      rect(source.mediaBox); rect(source.cropBox);
      if (![0,90,180,270].includes(source.rotation)) fail('지원하지 않는 PDF rotation입니다.');
      const swap = source.rotation === 90 || source.rotation === 270;
      if (Math.abs(page.width - source.cropBox[swap ? 'height' : 'width']) >= 0.001 ||
          Math.abs(page.height - source.cropBox[swap ? 'width' : 'height']) >= 0.001) fail('PDF crop과 페이지 크기가 다릅니다.');
    }
    if (!Array.isArray(page.strokes)) fail('획 목록이 필요합니다.');
    for (const value of page.strokes) stroke(value, strokes);
  }
  if (indices.size !== (asset?.pageCount ?? 0)) fail('PDF 페이지 매핑이 누락되었습니다.');
  if (document.lastOpenedPageID != null) {
    uuid(document.lastOpenedPageID, 'lastOpenedPageID');
    if (!pages.has(document.lastOpenedPageID.toLowerCase())) fail('마지막 페이지가 존재하지 않습니다.');
  }
}
export function readDocument(text) {
  if (typeof text !== 'string') fail('JSON 텍스트가 필요합니다.');
  const document = JSON.parse(text);
  validateDocument(document);
  return document;
}
export function writeDocument(document) {
  validateDocument(document);
  return JSON.stringify(document, null, 2) + '\n';
}
export function applyEdit(document, command) {
  validateDocument(document);
  if (command?.kind === "deleteStrokes" || command?.kind === "duplicateStrokes") return applySelectionEdit(document,command);
  const fields = {
    translateStroke: ['kind','pageID','strokeID','dx','dy'],
    deleteStroke: ['kind','pageID','strokeID'], appendStroke: ['kind','pageID','stroke'],
  };
  if (!command || !Object.hasOwn(fields, command.kind)) fail('지원하지 않는 편집 명령입니다.');
  shape(command, fields[command.kind], '명령'); uuid(command.pageID, '명령 pageID');
  if (document.revision === Number.MAX_SAFE_INTEGER) fail('revision 한도입니다. 원본을 보존합니다.');
  const result = structuredClone(document);
  const page = result.pages.find(p => sameID(p.id, command.pageID));
  if (!page) fail('명령의 페이지가 존재하지 않습니다.');
  if (command.kind === 'appendStroke') {
    if (command.stroke?.tool !== 'pen') fail('새 획은 기본 pen만 추가할 수 있습니다.');
    page.strokes.push(structuredClone(command.stroke));
  } else {
    uuid(command.strokeID, '명령 strokeID');
    const index = page.strokes.findIndex(s => sameID(s.id, command.strokeID));
    if (index < 0) fail('명령의 획이 존재하지 않습니다.');
    if (command.kind === 'deleteStroke') page.strokes.splice(index, 1);
    else {
      number(command.dx, 'dx'); number(command.dy, 'dy');
      page.strokes[index].transform.tx += command.dx;
      page.strokes[index].transform.ty += command.dy;
    }
  }
  result.revision += 1;
  validateDocument(result);
  return result;
}

// Selection commands preserve original order and require caller-provided fresh
// UUIDs, so independently reproduced fixtures do not depend on a shared RNG.
function applySelectionEdit(document,command) {
  const duplicate=command.kind==='duplicateStrokes';
  shape(command,duplicate ? ['kind','pageID','strokeIDs','newIDs','dx','dy','expectedRevision'] : ['kind','pageID','strokeIDs','expectedRevision'],'선택 명령');
  uuid(command.pageID,'pageID'); integer(command.expectedRevision,'expectedRevision');
  if(document.revision!==command.expectedRevision) fail('stale revision');
  const page=document.pages.find(p=>sameID(p.id,command.pageID));
  if(!page) fail('활성 페이지가 없습니다.');
  if(!Array.isArray(command.strokeIDs)) fail('선택 UUID 목록이 필요합니다.');
  const selected=new Set();
  for(const id of command.strokeIDs) { uuid(id,'strokeID'); if(selected.has(id.toLowerCase())) fail('중복 선택 UUID'); selected.add(id.toLowerCase()); }
  const originals=page.strokes.filter(s=>selected.has(s.id.toLowerCase()));
  if(originals.length!==selected.size) fail('선택 획이 현재 페이지에 없습니다.');
  if(duplicate) {
    number(command.dx,'dx'); number(command.dy,'dy');
    if(!Array.isArray(command.newIDs) || command.newIDs.length!==originals.length) fail('복제 UUID 수가 다릅니다.');
    for(const id of command.newIDs) uuid(id,'newID');
  }
  if(selected.size===0) return document;
  if(document.revision===Number.MAX_SAFE_INTEGER) fail('revision 한도');
  const result=structuredClone(document), target=result.pages.find(p=>sameID(p.id,page.id));
  if(duplicate) {
    target.strokes.push(...originals.map((stroke,index)=>{
      const clone=structuredClone(stroke); clone.id=command.newIDs[index];
      clone.transform.tx+=command.dx; clone.transform.ty+=command.dy;
      return clone;
    }));
  } else target.strokes=target.strokes.filter(s=>!selected.has(s.id.toLowerCase()));
  result.revision+=1; validateDocument(result); return result;
}
