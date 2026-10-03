import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { InkEditor } from './editor.mjs';
const fixture = name => readFileSync(new URL(`../../Packages/MiNoteCore/Tests/MiNoteCoreTests/Fixtures/PortableInk/${name}.json`, import.meta.url),'utf8');
test('UI controller moves/deletes/adds and exports the actual portable document', () => {
  const editor = new InkEditor(); editor.open(fixture('source'));
  for (const command of JSON.parse(fixture('edits'))) editor.edit(command);
  assert.deepEqual(JSON.parse(editor.export()),JSON.parse(fixture('edited')));
  assert.equal(editor.document.revision,43);
});
test('failed open or edit retains the previously opened note and export', () => {
  const editor = new InkEditor(); editor.open(fixture('source'));
  const original = editor.export();
  assert.throws(() => editor.open('{"schemaVersion":99}'));
  assert.equal(editor.export(), original);
  assert.throws(() => editor.edit({kind:'deleteStroke',pageID:editor.document.pages[0].id,strokeID:editor.document.id}));
  assert.equal(editor.export(), original);
});
test('an unopened editor cannot export a replacement blank note', () => {
  assert.throws(() => new InkEditor().export());
});
