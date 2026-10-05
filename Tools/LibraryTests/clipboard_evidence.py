#!/usr/bin/env python3
"""Read-only saved JSON observation for actual native clipboard UI actions."""
import argparse, copy, json, subprocess
from pathlib import Path

def verify(s, frames):
    phases=['clipSource','clipCopied','clipBlank','clipPasted','clipPen','clipUndoPen','clipUndoPaste','clipRedoPaste','clipRedoPen','clipReopen','clipSourceAgain','clipOtherNote','clipOtherUndo','clipOtherRedo']
    assert set(s)==set(phases), set(s)
    def page(phase):
        d=s[phase]; return next((p for p in d['pages'] if p['id']==d.get('lastOpenedPageID')),d['pages'][0])
    def ink(phase): return page(phase)['strokes']
    assert s['clipSource']==s['clipCopied'], 'Copy must not edit source or revision.'
    source=ink('clipSource')[0]; pasted=ink('clipPasted')[0]
    t=source['transform']; pts=source['points']
    xs=[t['a']*p['x']+t['c']*p['y']+t['tx'] for p in pts]
    ys=[t['b']*p['x']+t['d']*p['y']+t['ty'] for p in pts]
    for phase in ('clipPasted','clipOtherNote'):
        clone=ink(phase)[0]; p=page(phase)
        assert clone['id'] != source['id']
        expected=copy.deepcopy(source); expected['id']=clone['id']
        viewport, rendered=frames[phase]
        vx,vy,vw,vh=viewport; rx,ry,rw,rh=rendered
        centerX=(vx+vw/2-rx)*p['width']/rw
        centerY=(vy+vh/2-ry)*p['height']/rh
        expected['transform']['tx'] += centerX-(min(xs)/2+max(xs)/2)
        expected['transform']['ty'] += centerY-(min(ys)/2+max(ys)/2)
        for key in ('tx','ty'):
            assert abs(clone['transform'][key]-expected['transform'][key]) <1e-6, (phase,key,clone['transform'],expected['transform'])
            expected['transform'][key]=clone['transform'][key]
        assert clone==expected, phase
    assert ink('clipOtherNote')[0]['id'] != pasted['id']
    full=ink('clipPen'); assert full[0]==pasted and len(full)==2 and full[1]['id']!=pasted['id']
    for phase,want in [('clipUndoPen',[pasted]),('clipUndoPaste',[]),('clipRedoPaste',[pasted]),('clipRedoPen',full),('clipReopen',full),('clipSourceAgain',[source]),('clipOtherUndo',[]),('clipOtherRedo',ink('clipOtherNote'))]:
        assert ink(phase)==want, phase
    for phase in phases[2:11]:
        assert s[phase]['pages'][0]==s['clipSource']['pages'][0], phase
    for before,after in [('clipBlank','clipPasted'),('clipPasted','clipPen'),('clipPen','clipUndoPen'),('clipUndoPen','clipUndoPaste'),('clipUndoPaste','clipRedoPaste'),('clipRedoPaste','clipRedoPen'),('clipOtherNote','clipOtherUndo'),('clipOtherUndo','clipOtherRedo')]:
        b=s[before]; a=s[after]; want=copy.deepcopy(b); want['revision']+=1
        target=next((p for p in want['pages'] if p['id']==want.get('lastOpenedPageID')),want['pages'][0]); target['strokes']=ink(after)
        assert want==a, 'Other metadata changed: '+after
    assert s['clipRedoPen']==s['clipReopen']
    print('Actual clipboard UI: source preserved, fresh UUIDs/all values/order/viewport placement/native Undo/Redo/across page and note/reopen verified.')

def main():
    parser=argparse.ArgumentParser(); parser.add_argument('device'); parser.add_argument('derived_data'); parser.add_argument('result',type=Path)
    args=parser.parse_args(); log=args.result.with_suffix('.log'); evidence=args.result.with_suffix('.ink-evidence')
    if log.exists() or args.result.exists() or evidence.exists(): raise SystemExit('Use a new evidence path.')
    evidence.mkdir(parents=True)
    cmd=['xcodebuild','-project','MiNote.xcodeproj','-scheme','MiNote','-destination',f'platform=iOS Simulator,id={args.device}','-derivedDataPath',args.derived_data,'-resultBundlePath',str(args.result),'-parallel-testing-enabled','NO','-only-testing:MiNoteUITests/ClipboardUITests','CODE_SIGNING_ALLOWED=NO','COMPILATION_CACHE_ENABLE_CACHING=NO','test']
    snapshots={}; frames={}; errors=[]
    with log.open('x') as out:
        process=subprocess.Popen(cmd,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,bufsize=1)
        for line in process.stdout:
            out.write(line); out.flush()
            if 'MINOTE_CLIPBOARD_STAGE ' not in line: continue
            try:
                meta=json.loads(line.split('MINOTE_CLIPBOARD_STAGE ',1)[1])
                container=Path(subprocess.check_output(['xcrun','simctl','get_app_container',args.device,'com.minote.foundation','data'],text=True).strip())
                root=container/'Documents/MiNote'; catalog=json.loads((root/'library.json').read_bytes())
                matches=[]
                for note in catalog['notes']:
                    raw=(root/'notes'/note['id']/'document.json').read_bytes(); doc=json.loads(raw)
                    if doc['title']==meta['title']: matches.append((raw,doc))
                assert len(matches)==1
                raw,doc=matches[0]; active=next((p for p in doc['pages'] if p['id']==doc.get('lastOpenedPageID')),doc['pages'][0])
                assert len(active['strokes'])==meta['count']; assert meta['phase'] not in snapshots
                snapshots[meta['phase']]=doc; frames[meta['phase']]=meta['pasteFrames']; (evidence/(meta['phase']+'.json')).write_bytes(raw)
                (evidence/(meta['phase']+'.frames')).write_text(json.dumps(meta['pasteFrames']))
                print('Captured clipboard saved ink:',meta['phase'],meta['count'],'revision',doc['revision'],flush=True)
            except Exception as e: errors.append(str(e)); print('Observer error:',e,flush=True)
        rc=process.wait()
    if rc: raise SystemExit(rc)
    assert not errors,errors
    verify(snapshots,frames)
if __name__=='__main__': main()
