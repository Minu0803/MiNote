"""Independent assertions over saved documents from real selection UI gestures."""
import copy

DUP = ['dupPen1','dupClone','dupPen2','dupUndoPen2','dupUndoClone','dupUndoPen1',
       'dupRedoPen1','dupRedoClone','dupRedoPen2','dupReopen']
DELETE = ['delPen1','delDelete','delUndo','delRedo','delPen2','delErase','delUndoErase',
          'delUndoPen2','delUndoDelete','delRedoDelete','delRedoPen2','delReopen']

def verify(snapshots):
    assert set(snapshots) == set(DUP + DELETE), list(snapshots)
    def ink(phase): return snapshots[phase]['pages'][0]['strokes']
    original = ink('dupPen1')[0]
    clone = ink('dupClone')[1]
    assert ink('dupClone')[0] == original
    assert clone['id'] != original['id']
    expected = copy.deepcopy(original)
    expected['id'] = clone['id']
    expected['transform']['tx'] += 20
    expected['transform']['ty'] += 20
    assert clone == expected, 'Clone changes only UUID and tx/ty by 20pt.'
    all_ink = ink('dupPen2')
    assert all_ink[:2] == [original,clone] and len({s['id'] for s in all_ink}) == 3
    for phase,want in [('dupUndoPen2',[original,clone]),('dupUndoClone',[original]),
                       ('dupUndoPen1',[]),('dupRedoPen1',[original]),('dupRedoClone',[original,clone]),
                       ('dupRedoPen2',all_ink),('dupReopen',all_ink)]:
        assert ink(phase) == want, phase
    first = ink('delPen1')
    added = ink('delPen2')
    assert len(first) == len(added) == 1 and first[0]['id'] != added[0]['id']
    for phase,want in [('delDelete',[]),('delUndo',first),('delRedo',[]),('delErase',[]),
                       ('delUndoErase',added),('delUndoPen2',[]),('delUndoDelete',first),
                       ('delRedoDelete',[]),('delRedoPen2',added),('delReopen',added)]:
        assert ink(phase) == want, phase
    for phases in [DUP,DELETE]:
        for before,after in zip(phases,phases[1:]):
            b=snapshots[before]; a=snapshots[after]
            assert a['revision'] == b['revision'] + (0 if after.endswith('Reopen') else 1), (before,after)
            expected = copy.deepcopy(b)
            expected['revision'] = a['revision']; expected['pages'][0]['strokes'] = ink(after)
            assert expected == a, 'Unselected document/page/PDF metadata changed: '+after
    print('Actual selection UI: UUID/values/order/20pt/Undo/Redo/eraser/reopen and all other metadata verified.')
