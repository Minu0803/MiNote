import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { readDocument, writeDocument, applyEdit } from './document.mjs';

const input = readFileSync(new URL('../../Packages/MiNoteCore/Tests/MiNoteCoreTests/Fixtures/PortableInk/source.json', import.meta.url), 'utf8');
const original = JSON.parse(input);
const pageID = original.pages[0].id, strokeID = original.pages[0].strokes[0].id;
const moved = { kind: 'translateStroke', pageID, strokeID, dx: 12, dy: -8 };
const newID = '00000000-0000-4000-8000-000000000106';

test('read/write preserves every portable value and PDF metadata', () => {
  assert.deepEqual(JSON.parse(writeDocument(readDocument(input))), original);
});
test('translation edits only the selected UUID in document points', () => {
  const before = readDocument(input), result = applyEdit(before, moved);
  assert.deepEqual(before, original);
  assert.equal(result.revision, 41);
  assert.equal(result.pages[0].strokes[0].transform.tx, 17);
  assert.equal(result.pages[0].strokes[0].transform.ty, -2);
  const expected = structuredClone(original);
  expected.revision = 41; expected.pages[0].strokes[0].transform.tx = 17; expected.pages[0].strokes[0].transform.ty = -2;
  assert.deepEqual(result, expected);
});
test('deleting one of two identical strokes retains the other UUID', () => {
  const result = applyEdit(readDocument(input), { kind: 'deleteStroke', pageID, strokeID });
  assert.deepEqual(result.pages[0].strokes.map(s => s.id), original.pages[0].strokes.slice(1).map(s => s.id));
  assert.deepEqual(result.pages[1], original.pages[1]);
});
test('append keeps all previous strokes and owns a copy of the new stroke', () => {
  const stroke = structuredClone(original.pages[0].strokes[0]); stroke.id = newID;
  const result = applyEdit(readDocument(input), { kind: 'appendStroke', pageID, stroke });
  stroke.points[0].x = 999;
  assert.equal(result.pages[0].strokes.length, 5);
  assert.equal(result.pages[0].strokes[4].points[0].x, 80);
  assert.deepEqual(result.pages[0].strokes.slice(0, 4), original.pages[0].strokes);
});
test('failed command leaves input unchanged and does not increment revision', () => {
  const before = readDocument(input);
  for (const cmd of [
    {...moved, pageID: newID}, {...moved, strokeID: newID}, {...moved, dx: Infinity},
    {...moved, kind: 'erasePart'}, {...moved, unexpected: true},
    {kind:'appendStroke', pageID, stroke: original.pages[1].strokes[0]},
  ]) assert.throws(() => applyEdit(before, cmd));
  assert.deepEqual(before, original);
});
test('UUID comparison is case insensitive, duplicate IDs are rejected', () => {
  const d = structuredClone(original);
  d.pages[0].strokes[0].id = 'AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA';
  const result = applyEdit(d, {...moved, strokeID: d.pages[0].strokes[0].id.toLowerCase()});
  assert.equal(result.pages[0].strokes[0].transform.tx, 17);
  d.pages[0].strokes[1].id = d.pages[0].strokes[0].id.toLowerCase();
  assert.throws(() => writeDocument(d));
});
test('unknown schema, tools and fields cannot be silently rewritten', () => {
  for (const mutate of [
    d => d.schemaVersion = 3, d => d.pages[0].strokes[0].tool = 'pencil',
    d => d.syncState = {}, d => d.pages[0].strokes[0].mask = [],
    d => d.pages[0].strokes[0].points[0].threshold = 0.2,
    d => d.pdfAsset.checksum = 'future',
  ]) { const d = structuredClone(original); mutate(d); assert.throws(() => readDocument(JSON.stringify(d))); }
});
test('invalid geometry, colors, monotonic time and PDF mapping are rejected', () => {
  for (const mutate of [
    d => d.pages = [], d => d.pages[0].width = 0,
    d => d.pages[0].strokes[0].points = [], d => d.pages[0].strokes[0].color.alpha = 2,
    d => d.pages[0].strokes[0].points[1].timeOffset = -1,
    d => d.pages[0].strokes[0].points[0].force = -1,
    d => d.pages[0].strokes[0].transform.d = 0,
    d => d.lastOpenedPageID = newID, d => d.pages[2].pdfSource.index = 0,
    d => d.pages[2].pdfSource.rotation = 45, d => d.pages[2].width = 300,
    d => d.pdfAsset.byteCount = 0, d => d.pages.pop(),
    d => d.pages[0].strokes[0].randomSeed = 4294967296,
  ]) { const d = structuredClone(original); mutate(d); assert.throws(() => writeDocument(d)); }
});
test('unsafe revision or overflow never loses Int64 precision', () => {
  const d = structuredClone(original); d.revision = Number.MAX_SAFE_INTEGER;
  assert.throws(() => applyEdit(d, moved));
  d.revision = 9223372036854775807;
  assert.throws(() => readDocument(JSON.stringify(d)));
});
test('NaN and malformed structures are blocked before encoding', () => {
  const d = structuredClone(original); d.pages[0].strokes[0].points[0].x = NaN;
  assert.throws(() => writeDocument(d));
  for (const text of ['{', 'null', '[]', '{"schemaVersion":2}']) assert.throws(() => readDocument(text));
});
test('omitted legacy secondaryScale and optional null metadata are retained', () => {
  const d = structuredClone(original); delete d.pages[0].strokes[0].points[0].secondaryScale;
  d.pages[0].pdfSource = null;
  assert.deepEqual(JSON.parse(writeDocument(readDocument(JSON.stringify(d)))), d);
});
