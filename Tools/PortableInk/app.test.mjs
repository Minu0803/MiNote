import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { runInNewContext } from 'node:vm';
import { randomUUID } from 'node:crypto';
import { InkEditor } from './editor.mjs';
import { StrokeInput } from './input.mjs';
import { viewportToPage } from './render.mjs';

const source=readFileSync(new URL('../../Packages/MiNoteCore/Tests/MiNoteCoreTests/Fixtures/PortableInk/source.json',import.meta.url),'utf8');
const before=JSON.parse(source);
const code=readFileSync(process.env.PORTABLE_APP_SOURCE??new URL('./app.mjs',import.meta.url),'utf8');
// Test the real event handlers with only DOM/canvas/environment boundaries faked.
async function lab(){
  const elements=new Map(),captures=new Set();
  const make=()=>({value:'',style:{},classList:{toggle(){}},setAttribute(){},
    replaceChildren(...children){this.children=children;this.value=children[0]?.value??'';},
    click(){},remove(){},clientWidth:900,
    getContext(){return new Proxy({},{get:()=>()=>{}});},
    getBoundingClientRect(){return {left:0,top:0,width:before.pages[0].width};},
    setPointerCapture(id){captures.add(id);},hasPointerCapture(id){return captures.has(id);},
    releasePointerCapture(id){captures.delete(id);}});
  const get=id=>{if(!elements.has(id))elements.set(id,make());return elements.get(id);};
  get('zoom').value='1';get('dx').value='12';get('dy').value='-8';
  const environment={InkEditor,StrokeInput,viewportToPage,drawPage(){},devicePixelRatio:1,
    crypto:{randomUUID},Date,Blob,URL,setTimeout(){},ResizeObserver:class{observe(){}},
    document:{getElementById:get,createElement:make,body:{append(){}}},
    fetch:async()=>({ok:true,text:async()=>source})};
  runInNewContext(code.replace(/^import .*;\n/gm,''),environment);
  await get('sample').onclick();
  const snapshot=()=>{get('download').onclick();return JSON.parse(get('export-json').value);};
  const event=(id=1,timeStamp=10)=>({pointerId:id,timeStamp,clientX:20,clientY:30,pressure:0.5});
  const start=()=>{get('pen').onclick();get('canvas').onpointerdown(event());};
  return {get,captures,snapshot,event,start};
}

test('actual page-change handler cancels active input and releases capture',async()=>{
  const ui=await lab();ui.start();
  ui.get('page').value=before.pages[2].id;ui.get('page').onchange();
  ui.get('canvas').onpointerup(ui.event(1,20));
  assert.equal(ui.captures.size,0);
  assert.deepEqual(ui.snapshot(),before);
});
test('successful open of even the same document cancels pending input',async()=>{
  const ui=await lab();ui.start();await ui.get('sample').onclick();
  ui.get('canvas').onpointerup(ui.event(1,20));
  assert.deepEqual(ui.snapshot(),before);
  assert.equal(ui.captures.size,0);
});
test('mode exit, zoom and matching lost capture prevent late commits',async()=>{
  for(const interrupt of [ui=>ui.get('pen').onclick(),ui=>ui.get('zoom').oninput(),
    ui=>ui.get('canvas').onlostpointercapture(ui.event())]){
    const ui=await lab();ui.start();interrupt(ui);
    ui.get('canvas').onpointerup(ui.event(1,20));
    assert.deepEqual(ui.snapshot(),before);
  }
});
test('secondary cancel cannot erase active primary gesture; normal input commits once',async()=>{
  const ui=await lab();ui.start();ui.get('canvas').onpointercancel(ui.event(2));
  ui.get('canvas').onpointerup(ui.event(1,20));
  const result=ui.snapshot();
  assert.equal(result.revision,41);assert.equal(result.pages[0].strokes.length,5);
  assert.deepEqual(result.pages[0].strokes.slice(0,4),before.pages[0].strokes);
  ui.get('canvas').onpointerup(ui.event(1,30));
  assert.deepEqual(ui.snapshot(),result);
});

test('actual file-open and ink handlers retain v3 assets deleted pages and paper metadata',async()=>{
  const text=readFileSync(new URL('../../Packages/MiNoteCore/Tests/MiNoteCoreTests/Fixtures/PortableInk/multi-source.json',import.meta.url),'utf8');
  const expected=JSON.parse(text), ui=await lab();
  await ui.get('file').onchange({target:{files:[{text:async()=>text}],value:'selected'}});
  assert.deepEqual(ui.snapshot(),expected);
  assert.ok(ui.get('page').children[0].textContent.includes('격자'));
  assert.ok(ui.get('page').children[0].textContent.includes('책갈피'));
  ui.start();ui.get('canvas').onpointerup(ui.event(1,20));
  const edited=ui.snapshot();
  assert.equal(edited.schemaVersion,3);assert.equal(edited.revision,41);
  assert.deepEqual(edited.pdfAssets,expected.pdfAssets);assert.deepEqual(edited.deletedPages,expected.deletedPages);
  assert.equal(edited.pages[0].paper,'grid');assert.equal(edited.pages[0].isBookmarked,true);
});
