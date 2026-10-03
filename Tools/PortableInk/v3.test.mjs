import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { readDocument, writeDocument, applyEdit } from './document.mjs';
import { InkEditor } from './editor.mjs';
import { drawPage } from './render.mjs';
const fixture = new URL('../../Packages/MiNoteCore/Tests/MiNoteCoreTests/Fixtures/PortableInk/', import.meta.url);
const source = JSON.parse(readFileSync(new URL('source.json', fixture), 'utf8'));
function v3() {
  const doc = structuredClone(source), asset = doc.pdfAsset;
  doc.schemaVersion = 3; doc.pdfAssets = [asset, {...asset, id:'00000000-0000-4000-8000-000000000003'}]; delete doc.pdfAsset;
  for (const p of doc.pages) {
    p.paper = 'blank'; p.isBookmarked = false;
    if (p.pdfSource) p.pdfSource.assetID = asset.id;
  }
  doc.pages[0].paper = 'grid'; doc.pages[0].isBookmarked = true;
  doc.deletedPages = [{page:doc.pages.pop(), originalIndex:4, deletedAt:1700000002}];
  const copy = structuredClone(doc.pages[1]); copy.id = '00000000-0000-4000-8000-000000000090';
  for (const s of copy.strokes) s.id = '00000000-0000-4000-8000-000000000190';
  copy.pdfSource.assetID = doc.pdfAssets[1].id; copy.isBookmarked = true; doc.pages.push(copy);
  return doc;
}
test('testV3EditsKeepMultipleAssetsDeletedPagesAndPageMetadata', () => {
  const doc = v3(), editor = new InkEditor(); editor.open(JSON.stringify(doc));
  editor.edit({kind:'translateStroke',pageID:doc.pages[0].id,strokeID:doc.pages[0].strokes[0].id,dx:12,dy:-8});
  const result = JSON.parse(editor.export());
  assert.equal(result.schemaVersion,3); assert.equal(result.revision,41);
  assert.deepEqual(result.pdfAssets,doc.pdfAssets); assert.deepEqual(result.deletedPages,doc.deletedPages);
  assert.deepEqual(result.pages.slice(1),doc.pages.slice(1));
  assert.equal(result.pages[0].paper,'grid'); assert.equal(result.pages[0].isBookmarked,true);
  assert.deepEqual(doc,v3());
});
test('v3 relations, future schemas and object IDs fail without replacing editor input', () => {
  const doc = v3(), editor = new InkEditor(); editor.open(JSON.stringify(doc));
  for (const mutate of [
    d=>d.schemaVersion=4, d=>d.pages[1].pdfSource.assetID=doc.id,
    d=>d.pdfAssets[1].id=d.pdfAssets[0].id, d=>d.pages[1].pdfSource.index=4,
    d=>d.deletedPages[0].page.id=d.pages[0].id, d=>d.deletedPages[0].originalIndex=-1,
    d=>d.deletedPages[0].page.strokes=[d.pages[0].strokes[0]],
    d=>d.pages[1].paper='ruled', d=>d.pages[0].paper='future',
    d=>d.lastOpenedPageID=d.deletedPages[0].page.id,
    d=>d.pages[0].id=d.pdfAssets[0].id,
  ]) {
    const bad = structuredClone(doc); mutate(bad); assert.throws(()=>editor.open(JSON.stringify(bad)));
    assert.deepEqual(editor.document,doc);
  }
});
test('v3 permits duplicate PDF indices and retained assets with no active reference', () => {
  const doc=v3(), copy=structuredClone(doc.pages[1]); copy.id=crypto.randomUUID(); copy.strokes=[];
  doc.pages.push(copy); assert.deepEqual(readDocument(writeDocument(doc)),doc);
  doc.pages=doc.pages.filter(p=>!p.pdfSource); assert.deepEqual(readDocument(writeDocument(doc)),doc);
});
test('v3 shares the iPad 24pt paper geometry in document coordinates', () => {
  const commands=[], context=new Proxy({}, {get:(_,key)=> (...args)=>commands.push([key,...args]),set:()=>true});
  drawPage(context,{width:72,height:72,paper:'grid',strokes:[]},2);
  for (const command of [['moveTo',0,24],['lineTo',72,24],['moveTo',24,0],['lineTo',24,72]]) {
    assert.ok(commands.some(c=>JSON.stringify(c)===JSON.stringify(command)),JSON.stringify(command));
  }
  assert.ok(commands.some(c=>c[0]==='scale' && c[1]===2));
});

test('actual iPad v3 fixture and independent command output preserve metadata',()=>{
  const original=readDocument(readFileSync(new URL('multi-source.json',fixture),'utf8'));
  assert.deepEqual(original,v3());
  const commands=JSON.parse(readFileSync(new URL('edits.json',fixture),'utf8'));
  const output=commands.reduce(applyEdit,original);
  const recorded=readDocument(readFileSync(new URL('multi-edited.json',fixture),'utf8'));
  assert.deepEqual(output,recorded);assert.equal(recorded.schemaVersion,3);
  assert.deepEqual(recorded.pdfAssets,original.pdfAssets);assert.deepEqual(recorded.deletedPages,original.deletedPages);
});
