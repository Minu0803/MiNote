#!/usr/bin/env python3
"""Run real finger UI and retain live saved JSON at declared gesture boundaries.

Read-only observation: never seeds, deletes, or changes app data. No app test hooks.
"""
import argparse
import copy
import hashlib
import json
from pathlib import Path
import subprocess
import sys

parser = argparse.ArgumentParser()
parser.add_argument('device')
parser.add_argument('derived_data', type=Path)
parser.add_argument('result', type=Path)
parser.add_argument('--all-tests', action='store_true')
parser.add_argument('--selection-tests', action='store_true')
args = parser.parse_args()
log = args.result.with_suffix('.log')
evidence = args.result.with_suffix('.ink-evidence')
if args.result.exists() or log.exists() or evidence.exists():
    raise SystemExit('Use a new result path; existing test evidence must be preserved.')
evidence.mkdir(parents=True)
command = ['xcodebuild','-project','MiNote.xcodeproj','-scheme','MiNote',
           '-destination',f'platform=iOS Simulator,id={args.device}', '-derivedDataPath',str(args.derived_data),
           '-resultBundlePath',str(args.result),'-parallel-testing-enabled','NO','-collect-test-diagnostics','never']
if not args.all_tests:
    command += ['-only-testing:MiNoteUITests/' + ('SelectionCommandUITests' if args.selection_tests else 'LassoUITests')]
command += ['CODE_SIGNING_ALLOWED=NO','COMPILATION_CACHE_ENABLE_CACHING=NO','test']
snapshots = {}
asset_hashes = {}
errors = []
with log.open('x') as output:
    process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1)
    for line in process.stdout:
        output.write(line); output.flush()
        marker = next((m for m in ['MINOTE_LASSO_STAGE ', 'MINOTE_SELECTION_STAGE '] if m in line),None)
        if marker is None:
            continue
        try:
            meta = json.loads(line.split(marker,1)[1])
            container = Path(subprocess.check_output(['xcrun','simctl','get_app_container',args.device,'com.minote.foundation','data'],text=True).strip())
            root = container / 'Documents' / 'MiNote'
            catalog = json.loads((root / 'library.json').read_bytes())
            # Catalog v1 stores IDs/folders only; titles belong to each document.
            matches = []
            for note in catalog['notes']:
                candidate = (root / 'notes' / note['id'] / 'document.json').read_bytes()
                if json.loads(candidate)['title'] == meta['title']:
                    matches.append((candidate,root / 'notes' / note['id']))
            assert len(matches) == 1, 'Observer must identify the UI-created note exactly.'
            raw, directory = matches[0]
            doc = json.loads(raw)
            page = next((p for p in doc['pages'] if p['id'] == doc.get('lastOpenedPageID')), doc['pages'][0])
            (evidence / (meta['phase']+'.json')).write_bytes(raw)
            assert len(page['strokes']) == meta['count'], (meta, len(page['strokes']))
            assert meta['phase'] not in snapshots
            snapshots[meta['phase']] = doc
            asset_hashes[meta['phase']] = {asset['id']:hashlib.sha256((directory / 'assets' / (asset['id']+'.pdf')).read_bytes()).hexdigest() for asset in doc['pdfAssets']}
            if meta['phase'].startswith('pdf'):
                assert len(doc['pdfAssets'])==1
                asset=doc['pdfAssets'][0]
                assert asset['originalFilename']=='MiNote-Second.pdf'
                source=(root.parent / 'MiNote-Second.pdf').read_bytes()
                assert len(source)==asset['byteCount']
                assert asset_hashes[meta['phase']][asset['id']]==hashlib.sha256(source).hexdigest()
            print('Captured actual saved ink:', meta['phase'], meta['count'], 'revision',doc['revision'],flush=True)
        except Exception as error:
            errors.append(str(error)); print('Observer error:', error,flush=True)
    status = process.wait()
if status:
    print('Xcode invocation failed:',status,'evidence retained:',evidence)
    raise SystemExit(status)
try:
    assert not errors, errors
    selection = {k:v for k,v in snapshots.items() if k.startswith(('dup','del'))}
    if selection or args.selection_tests or args.all_tests:
        from selection_evidence import verify
        verify(selection)
    snapshots = {k:v for k,v in snapshots.items() if k not in selection}
    if args.selection_tests and not args.all_tests:
        raise SystemExit(0)
    phases = ['pen1','move1','pen2','undoPen2','undoMove','undoPen1','redoPen1','redoMove','redoPen2','eraseMoved','undoErase','redoErase','restoreErase','zoom','rotation','portrait','relaunch']
    pdf_phases = ['pdfPen','pdfMove','pdfZoom','pdfRelaunch']
    assert set(snapshots) == set(phases+pdf_phases), list(snapshots)
    def active(doc): return next((p for p in doc['pages'] if p['id']==doc.get('lastOpenedPageID')),doc['pages'][0])
    def ink(phase): return active(snapshots[phase])['strokes']
    first = ink('pen1')[0]; moved = ink('move1')[0]
    before_value = dict(first); after_value = dict(moved)
    before_transform = before_value.pop('transform'); after_transform = after_value.pop('transform')
    assert before_value == after_value, 'Moving must preserve the actual native stroke UUID/points/ink.'
    for key in ['a','b','c','d']: assert before_transform[key] == after_transform[key]
    assert after_transform['tx'] > before_transform['tx'] and after_transform['ty'] > before_transform['ty']
    assert snapshots['move1']['revision'] == snapshots['pen1']['revision'] + 1
    for before, after in zip(phases[:9],phases[1:9]):
        assert snapshots[after]['revision'] == snapshots[before]['revision'] + 1, (before,after)
    assert ink('pen2')[0] == moved and len(ink('pen2')) == 2
    assert ink('pen2')[1]['id'] != first['id']
    assert ink('undoPen2') == [moved]
    assert ink('undoMove') == [first]
    assert ink('undoPen1') == []
    assert ink('redoPen1') == [first]
    assert ink('redoMove') == [moved]
    assert ink('redoPen2') == ink('pen2') == ink('relaunch')
    assert ink('eraseMoved') == ink('redoErase') == [ink('pen2')[1]]
    assert ink('undoErase') == ink('restoreErase') == ink('pen2')
    for phase in ['zoom','rotation','portrait']:
        assert ink(phase) == ink('pen2')
        assert snapshots[phase]['revision'] == snapshots['restoreErase']['revision']
    for phase in phases:
        doc = snapshots[phase]
        assert doc['id'] == snapshots['pen1']['id']
        assert doc['pages'][0]['id'] == snapshots['pen1']['pages'][0]['id']
    pdf_before=ink('pdfPen')[0]; pdf_after=ink('pdfMove')[0]
    b=dict(pdf_before); a=dict(pdf_after); bt=b.pop('transform'); at=a.pop('transform')
    assert b==a
    assert at['tx']>bt['tx'] and at['ty']>bt['ty']
    assert {k:at[k] for k in ['a','b','c','d']} == {k:bt[k] for k in ['a','b','c','d']}
    assert active(snapshots['pdfPen'])['pdfSource']['rotation']==90
    assert snapshots['pdfMove']['revision']==snapshots['pdfPen']['revision']+1
    expected_pdf=copy.deepcopy(snapshots['pdfPen']); expected_pdf['revision']+=1; active(expected_pdf)['strokes']=[pdf_after]
    assert expected_pdf==snapshots['pdfMove']
    for phase in pdf_phases:
        assert snapshots[phase]['id']==snapshots['pdfPen']['id']
        assert asset_hashes[phase]==asset_hashes['pdfPen']
    for phase in ['pdfZoom','pdfRelaunch']:
        assert ink(phase)==ink('pdfMove')
        assert snapshots[phase]['revision']==snapshots['pdfMove']['revision']
    print('Actual native pen→move→pen Undo3/Redo3: UUID/point data/linear transform/order/location/relaunch preserved; UI and live saved bytes verified.')
except Exception as error:
    print('Saved-ink verification failed:',error,'evidence retained:',evidence)
    raise SystemExit(1)
