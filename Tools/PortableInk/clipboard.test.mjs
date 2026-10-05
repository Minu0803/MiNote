import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {readDocument,readInkClipboard,applyEdit} from './document.mjs';
const directory=new URL('../../Packages/MiNoteCore/Tests/MiNoteCoreTests/Fixtures/PortableInk/',import.meta.url);
const source=readDocument(readFileSync(new URL('multi-source.json',directory),'utf8'));
const payload={schemaVersion:1,strokes:source.pages[1].strokes};
const fresh=['00000000-0000-4000-8000-000000009001'];
const command=(doc=source)=>({kind:'pasteStrokes',pageID:doc.pages[0].id,payload,newIDs:fresh,dx:30,dy:-15,expectedRevision:doc.revision});
test('ink payload preserves every field and rejects foreign data at all boundaries',()=>{
 assert.deepEqual(readInkClipboard(JSON.stringify(payload)),payload);
 for(const modify of [v=>v.schemaVersion=2,v=>v.extra='no',v=>v.strokes=[],v=>v.strokes.push(structuredClone(v.strokes[0])),
  v=>v.strokes[0].extra=1,v=>v.strokes[0].points[0].future=1,v=>v.strokes[0].transform.extra=1,
  v=>v.strokes[0].color.space='future',v=>delete v.strokes[0].points[0].secondaryScale]) {
  const bad=structuredClone(payload); modify(bad); assert.throws(()=>readInkClipboard(JSON.stringify(bad)));
 }
 assert.throws(()=>readInkClipboard(' '.repeat(8*1024*1024+1)));
 const huge=structuredClone(payload); huge.strokes=Array.from({length:2001},(_,i)=>({...structuredClone(payload.strokes[0]),id:'00000000-0000-4000-8000-'+String(i+1000).padStart(12,'0')}));
 assert.throws(()=>readInkClipboard(JSON.stringify(huge)));
});
test('paste uses fresh UUIDs and changes only target strokes and one revision',()=>{
 const actual=applyEdit(source,command()); const expected=structuredClone(source); expected.revision++;
 const clone=structuredClone(payload.strokes[0]); clone.id=fresh[0]; clone.transform.tx+=30; clone.transform.ty-=15;
 expected.pages[0].strokes.push(clone); assert.deepEqual(actual,expected);
 assert.deepEqual(readDocument(JSON.stringify(source)),source);
 for(const mutate of [c=>c.expectedRevision--,c=>c.pageID=source.deletedPages[0].page.id,c=>c.dx=NaN,c=>c.newIDs=[source.pdfAssets[0].id],c=>c.newIDs=[]]) {
  const c=command(); mutate(c); assert.throws(()=>applyEdit(source,c));
 }
});
test('fresh pasted IDs cannot reuse payload identities absent from target document',()=>{
 const target=structuredClone(source); target.pages[1].strokes=[];
 const c=command(target); c.newIDs=payload.strokes.map(s=>s.id);
 assert.throws(()=>applyEdit(target,c));
});
test('actual iPad clipboard payload and paste equal independent commands before further edits',()=>{
 const target=readDocument(readFileSync(new URL('clipboard-target.json',directory),'utf8'));
 const payload=readInkClipboard(readFileSync(new URL('clipboard-payload.json',directory),'utf8'));
 const command=JSON.parse(readFileSync(new URL('clipboard-command.json',directory),'utf8'));
 const actual=applyEdit(target,{...command,payload});
 assert.deepEqual(actual,readDocument(readFileSync(new URL('clipboard-pasted.json',directory),'utf8')));
 const edits=JSON.parse(readFileSync(new URL('edits.json',directory),'utf8'));
 assert.deepEqual(edits.reduce(applyEdit,actual),readDocument(readFileSync(new URL('clipboard-edited.json',directory),'utf8')));
});
