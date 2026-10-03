import { readFile, writeFile } from 'node:fs/promises';
import { readDocument, writeDocument, applyEdit } from './document.mjs';
const directory = new URL('../../Packages/MiNoteCore/Tests/MiNoteCoreTests/Fixtures/PortableInk/', import.meta.url);
const prefix = process.argv.includes('--v3') ? 'multi-' : '';
const input = await readFile(new URL(prefix + 'source.json', directory), 'utf8');
const commands = JSON.parse(await readFile(new URL('edits.json', directory), 'utf8'));
const result = commands.reduce(applyEdit, readDocument(input));
const output = writeDocument(result);
const destination = new URL(prefix + 'edited.json', directory);
if (process.argv.includes('--check')) {
  if (await readFile(destination, 'utf8') !== output) throw new Error('edited.json is stale; regenerate from source and manifest');
  console.log('PortableInk fixture matches real JavaScript command output');
} else {
  await writeFile(destination, output);
  console.log('Generated edited.json at revision ' + result.revision);
}
