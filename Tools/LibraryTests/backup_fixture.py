#!/usr/bin/env python3
"""Transfer an actual UI-exported backup only into a new dedicated simulator."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import zipfile

parser = argparse.ArgumentParser()
parser.add_argument('device')
parser.add_argument('source', type=Path, help='Actual Files-saved Backup-*.minote from BackupUITests')
parser.add_argument('--verify', action='store_true')
args = parser.parse_args()
def simctl(*values):
    return subprocess.check_output(['xcrun', 'simctl', *values], text=True).strip()
all_devices = json.loads(simctl('list', 'devices', 'available', '-j'))['devices']
device = next(d for group in all_devices.values() for d in group if d['udid'] == args.device)
if not device['name'].startswith('MiNote M1-C Backup '):
    raise SystemExit('Refusing to modify a general-purpose simulator.')
if not args.source.name.startswith('Backup-') or args.source.suffix != '.minote':
    raise SystemExit('Use the actual Files output identified by MINOTE_BACKUP_FILE in the UI test log.')
archive_bytes = args.source.read_bytes()
with zipfile.ZipFile(args.source) as archive:
    assert archive.testzip() is None
    document = json.loads(archive.read('document.json'))
    assert document['title'].startswith('Backup-') and document['schemaVersion'] == 3
    assert len(document['pages']) == 7 and len(document['deletedPages']) == 1 and len(document['pdfAssets']) == 2
    pdfs = {a['id']: archive.read('assets/' + a['id'].upper() + '.pdf') for a in document['pdfAssets']}
container = Path(simctl('get_app_container', args.device, 'com.minote.foundation', 'data'))
documents = container / 'Documents'
root = documents / 'MiNote'
transferred = documents / 'Transfer.minote'
origin = documents / 'Transfer-origin.json'
digest = hashlib.sha256(archive_bytes).hexdigest()
if not args.verify:
    if root.exists() or transferred.exists() or origin.exists():
        raise SystemExit('Refusing to reseed existing data. Create a new dedicated Backup simulator.')
    documents.mkdir(exist_ok=True)
    with transferred.open('xb') as output:
        output.write(archive_bytes)
    with origin.open('x') as output:
        json.dump({'sha256': digest, 'source': args.source.name}, output)
    print('Transferred actual Files backup to empty installation:', args.device, digest)
else:
    assert json.loads(origin.read_text())['sha256'] == digest
    assert transferred.read_bytes() == archive_bytes
    catalog = json.loads((root / 'library.json').read_bytes())
    assert len(catalog['notes']) == 1
    assert catalog['notes'][0]['id'].lower() == document['id'].lower()
    note = root / 'notes' / document['id']
    actual = json.loads((note / 'document.json').read_bytes())
    assert actual['id'] == document['id'] and actual['schemaVersion'] == 3
    assert actual['title'] == document['title'] + ' (복원)' and actual['revision'] > document['revision']
    assert actual['pdfAssets'] == document['pdfAssets'] and actual['deletedPages'] == document['deletedPages']
    assert len(actual['pages']) == len(document['pages'])
    for i, (before, after) in enumerate(zip(document['pages'], actual['pages'])):
        for key in ['id', 'width', 'height', 'pdfSource', 'paper', 'isBookmarked']:
            assert after.get(key) == before.get(key), (i, key)
        assert after['strokes'][:len(before['strokes'])] == before['strokes'], i
        assert len(after['strokes']) == len(before['strokes']) + (1 if i == 3 else 0), i
    assert actual['lastOpenedPageID'] == document['pages'][3]['id']
    assert (note / 'document.backup.json').is_file()
    for asset_id, raw in pdfs.items():
        assert (note / 'assets' / (asset_id.upper() + '.pdf')).read_bytes() == raw
    print('Transferred UI backup: document/page/stroke/asset IDs, all PDF bytes, retained page metadata preserved; new ink/Undo/redo/relaunch verified')
