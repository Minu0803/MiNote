import { InkEditor } from './editor.mjs';
import { drawPage, viewportToPage } from './render.mjs';
const editor=new InkEditor(), $=id=>document.getElementById(id);
let pageIndex=0, drawing=false, points=[], started=0, pointerID=null;
function message(text,error=false){$('status').textContent=text;$('status').classList.toggle('error',error);}
function attempt(action){try{action();}catch(error){message(error.message,true);}}
function currentPage(){return editor.document?.pages[pageIndex];}
function options(element,values){element.replaceChildren(...values.map(([id,text])=>{const option=document.createElement('option');option.value=id;option.textContent=text;return option;}));}
function refresh(){
  const doc=editor.document,page=currentPage(); if(!doc)return;
  $('export-panel').hidden=true;
  $('empty').hidden=true;$('canvas').style.display='inline-block';
  $('title').textContent=doc.title;$('summary').textContent=`revision ${doc.revision} · ${doc.pages.length}페이지 · 현재 ${page.strokes.length}획`;
  const selected=$('stroke').value;
  options($('page'),doc.pages.map((p,i)=>[p.id,`${i+1} / ${doc.pages.length}${p.pdfSource?' · PDF':''}`]));$('page').value=page.id;
  options($('stroke'),page.strokes.map((s,i)=>[s.id,`${i+1}. ${s.tool} · …${s.id.slice(-6)}`]));
  if(page.strokes.some(s=>s.id===selected))$('stroke').value=selected;
  for(const id of ['page','pen','download'])$(id).disabled=false;
  for(const id of ['stroke','move','delete'])$(id).disabled=!page.strokes.length;
  $('page-label').textContent=`PAGE ${pageIndex+1} · ${page.width.toFixed(1)} × ${page.height.toFixed(1)} pt`;
  render();
}
function render(){
  const page=currentPage();if(!page)return;
  const fit=Math.min(1,Math.max(120,$('stage').clientWidth-32)/page.width);
  const scale=Math.min(fit*Number($('zoom').value),4096/(Math.max(page.width,page.height)*Math.max(1,devicePixelRatio)));
  const canvas=$('canvas'),dpr=Math.max(1,devicePixelRatio);
  canvas.width=Math.max(1,Math.round(page.width*scale*dpr));canvas.height=Math.max(1,Math.round(page.height*scale*dpr));
  canvas.style.width=`${page.width*scale}px`;canvas.style.height=`${page.height*scale}px`;
  const context=canvas.getContext('2d');context.setTransform(dpr,0,0,dpr,0,0);drawPage(context,page,scale);
}
function open(text){editor.open(text);pageIndex=0;drawing=false;$('pen').setAttribute('aria-pressed','false');refresh();message('문서를 열었습니다. 획을 선택해 이동하거나 삭제할 수 있습니다.');}
$('sample').onclick=async()=>{try{const response=await fetch('/Packages/MiNoteCore/Tests/MiNoteCoreTests/Fixtures/PortableInk/source.json');if(!response.ok)throw new Error('샘플을 읽을 수 없습니다. 저장소 루트에서 서버를 실행하세요.');open(await response.text());}catch(error){message(error.message,true);}};
$('file').onchange=async event=>{try{const file=event.target.files[0];if(file)open(await file.text());}catch(error){message(error.message,true);}finally{event.target.value='';}};
$('page').onchange=()=>{pageIndex=editor.document.pages.findIndex(p=>p.id===$('page').value);refresh();};
function edit(kind){attempt(()=>{editor.edit({kind,pageID:currentPage().id,strokeID:$('stroke').value,...(kind==='translateStroke'?{dx:Number($('dx').value),dy:Number($('dy').value)}:{})});refresh();message('편집했습니다. JSON을 다운로드하면 원본과 별도로 보존됩니다.');});}
$('move').onclick=()=>edit('translateStroke');$('delete').onclick=()=>edit('deleteStroke');
$('zoom').oninput=()=>{$('zoom-value').textContent=`${Math.round(Number($('zoom').value)*100)}%`;render();};
$('pen').onclick=()=>{drawing=!drawing;$('pen').setAttribute('aria-pressed',String(drawing));message(drawing?'페이지에서 드래그해 새 펜 획을 그리세요.':'획 선택과 수치 이동 모드입니다.');};
function point(event){const rect=$('canvas').getBoundingClientRect();const p=viewportToPage({x:event.clientX-rect.left,y:event.clientY-rect.top},rect.width/currentPage().width);return {...p,timeOffset:Math.max(points.at(-1)?.timeOffset??0,(event.timeStamp-started)/1000),width:5,height:5,opacity:1,force:event.pressure||1,azimuth:0,altitude:1,secondaryScale:1};}
$('canvas').onpointerdown=event=>{if(!drawing||!editor.document||pointerID!==null)return;pointerID=event.pointerId;started=event.timeStamp;points=[];points.push(point(event));$('canvas').setPointerCapture(pointerID);};
$('canvas').onpointermove=event=>{if(event.pointerId===pointerID)points.push(point(event));};
$('canvas').onpointerup=event=>{if(event.pointerId!==pointerID)return;points.push(point(event));pointerID=null;attempt(()=>{editor.edit({kind:'appendStroke',pageID:currentPage().id,stroke:{id:crypto.randomUUID(),tool:'pen',points,color:{red:0.1,green:0.2,blue:0.9,alpha:1},transform:{a:1,b:0,c:0,d:1,tx:0,ty:0},randomSeed:12,creationTime:Date.now()/1000}});refresh();message('새 펜 획을 추가했습니다.');});};
$('canvas').onpointercancel=()=>{pointerID=null;points=[];};
$('download').onclick=()=>attempt(()=>{const blob=new Blob([editor.export()],{type:'application/json'});const url=URL.createObjectURL(blob);const anchor=document.createElement('a');anchor.href=url;anchor.download='MiNote-portable.json';document.body.append(anchor);anchor.click();anchor.remove();setTimeout(()=>URL.revokeObjectURL(url),30000);$('export-json').value=editor.export();$('export-panel').hidden=false;message('JSON 파일 저장을 요청했습니다. 아래에서도 출력 내용을 확인할 수 있습니다.');});
new ResizeObserver(()=>render()).observe($('stage'));
