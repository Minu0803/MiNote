import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {readDocument,applyEdit} from './document.mjs';
const directory=new URL('../../Packages/MiNoteCore/Tests/MiNoteCoreTests/Fixtures/PortableInk/',import.meta.url);
const source=readDocument(readFileSync(new URL('multi-source.json',directory),'utf8'));
const ids=['00000000-0000-4000-8000-000000000900','00000000-0000-4000-8000-000000000901'];
function duplicate(doc=source) {
    return {kind:'duplicateStrokes',pageID:doc.pages[0].id,strokeIDs:[doc.pages[0].strokes[2].id,doc.pages[0].strokes[0].id],newIDs:ids,dx:20,dy:20,expectedRevision:doc.revision};
}
test('selected clone appends fresh IDs in source order and preserves all other document values',()=>{
    const result=applyEdit(source,duplicate());
    const a=structuredClone(source.pages[0].strokes[0]), b=structuredClone(source.pages[0].strokes[2]);
    a.id=ids[0]; b.id=ids[1]; a.transform.tx+=20; a.transform.ty+=20; b.transform.tx+=20; b.transform.ty+=20;
    const expected=structuredClone(source); expected.revision=41; expected.pages[0].strokes.push(a,b);
    assert.deepEqual(result,expected);
    const deleted=applyEdit(result,{kind:'deleteStrokes',pageID:result.pages[0].id,strokeIDs:ids,expectedRevision:41});
    const restored=structuredClone(source); restored.revision=42; assert.deepEqual(deleted,restored);
});
test('identical shapes retain separate UUIDs and empty selection preserves maximum safe revision',()=>{
    const doc=structuredClone(source); doc.pages[0].strokes[1]={...structuredClone(doc.pages[0].strokes[0]),id:doc.pages[0].strokes[1].id};
    const cmd=duplicate(doc); cmd.strokeIDs=doc.pages[0].strokes.slice(0,2).map(s=>s.id);
    const result=applyEdit(doc,cmd); assert.equal(new Set(result.pages[0].strokes.map(s=>s.id)).size,6);
    doc.revision=Number.MAX_SAFE_INTEGER;
    for(const kind of ['deleteStrokes','duplicateStrokes']) {
        const empty={kind,pageID:doc.pages[0].id,strokeIDs:[],expectedRevision:doc.revision};
        if(kind==='duplicateStrokes') Object.assign(empty,{newIDs:[],dx:20,dy:20});
        assert.deepEqual(applyEdit(doc,empty),doc);
        const malformed=structuredClone(doc); malformed.pages[0].strokes[0].points[0].x=NaN;
        assert.throws(()=>applyEdit(malformed,empty));
    }
});
test('bad selection ownership, revision, fresh identities and overflow preserve input',()=>{
    const before=structuredClone(source);
    for(const mutate of [c=>c.pageID=source.deletedPages[0].page.id,c=>c.strokeIDs=[source.pages[1].strokes[0].id],
        c=>c.expectedRevision--,c=>c.dx=NaN,c=>c.dy=Infinity,c=>c.newIDs=[ids[0]],
        c=>c.newIDs=[ids[0],ids[0]],c=>c.newIDs[0]=source.deletedPages[0].page.id,
        c=>c.newIDs[0]=source.pdfAssets[0].id,c=>c.strokeIDs=[c.strokeIDs[0],c.strokeIDs[0]]]) {
        const cmd=duplicate(); mutate(cmd); assert.throws(()=>applyEdit(source,cmd)); assert.deepEqual(source,before);
    }
    const huge=structuredClone(source); huge.pages[0].strokes[0].transform.tx=Number.MAX_VALUE;
    const cmd=duplicate(huge); cmd.dx=Number.MAX_VALUE; assert.throws(()=>applyEdit(huge,cmd));
    const max=structuredClone(source); max.revision=Number.MAX_SAFE_INTEGER;
    assert.throws(()=>applyEdit(max,duplicate(max)));
    assert.throws(()=>applyEdit(max,{kind:'deleteStrokes',pageID:max.pages[0].id,strokeIDs:[max.pages[0].strokes[0].id],expectedRevision:max.revision}));
});

test('actual iPad delete and clone values equal independent commands and additional JS edits',()=>{
    let doc=readDocument(readFileSync(new URL('selection-source.json',directory),'utf8'));
    const commands=JSON.parse(readFileSync(new URL('selection-commands.json',directory),'utf8'));
    for(const [index,name] of ['selection-duplicated','selection-deleted'].entries()) {
        doc=applyEdit(doc,commands[index]);
        assert.deepEqual(doc,readDocument(readFileSync(new URL(name+'.json',directory),'utf8')));
    }
    const edits=JSON.parse(readFileSync(new URL('edits.json',directory),'utf8'));
    assert.deepEqual(edits.reduce(applyEdit,doc),readDocument(readFileSync(new URL('selection-edited.json',directory),'utf8')));
});
