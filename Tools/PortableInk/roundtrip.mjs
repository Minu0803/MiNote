import { readFile, writeFile } from 'node:fs/promises';
import { readDocument, writeDocument, readInkClipboard, applyEdit } from './document.mjs';
const directory = new URL('../../Packages/MiNoteCore/Tests/MiNoteCoreTests/Fixtures/PortableInk/', import.meta.url);
const selection=process.argv.includes('--selection');
if (selection && (process.argv.includes('--v3') || process.argv.includes('--lasso'))) throw new Error('Choose one fixture family');
const clipboard=process.argv.includes('--clipboard');
if(clipboard && ['--selection','--v3','--lasso'].some(flag=>process.argv.includes(flag))) throw new Error('Choose one fixture family');
if(clipboard) {
  const target=readDocument(await readFile(new URL('clipboard-target.json',directory),'utf8'));
  const payload=readInkClipboard(await readFile(new URL('clipboard-payload.json',directory),'utf8'));
  const command=JSON.parse(await readFile(new URL('clipboard-command.json',directory),'utf8'));
  const pasted=applyEdit(target,{...command,payload});
  const actual=readDocument(await readFile(new URL('clipboard-pasted.json',directory),'utf8'));
  const {isDeepStrictEqual}=await import('node:util');
  if(!isDeepStrictEqual(pasted,actual)) throw new Error('Independent paste differs from actual iPad');
  const edits=JSON.parse(await readFile(new URL('edits.json',directory),'utf8'));
  const output=writeDocument(edits.reduce(applyEdit,pasted)), destination=new URL('clipboard-edited.json',directory);
  if(process.argv.includes('--check')) {
    if(await readFile(destination,'utf8')!==output) throw new Error('clipboard-edited.json is stale');
    console.log('Actual clipboard payload/paste equals independent JavaScript; reverse fixture matches');
  } else { await writeFile(destination,output); console.log('Generated clipboard-edited.json'); }
} else if (selection) {
  let doc=readDocument(await readFile(new URL('selection-source.json',directory),'utf8'));
  const commands=JSON.parse(await readFile(new URL('selection-commands.json',directory),'utf8'));
  for(const [index,name] of ['selection-duplicated','selection-deleted'].entries()) {
    doc=applyEdit(doc,commands[index]);
    const actual=readDocument(await readFile(new URL(name+'.json',directory),'utf8'));
    // Key order differs between Apple's encoder and JS. Compare full semantic values.
    const {isDeepStrictEqual}=await import('node:util');
    if(!isDeepStrictEqual(doc,actual)) throw new Error('Independent command differs from actual app '+name);
  }
  const edits=JSON.parse(await readFile(new URL('edits.json',directory),'utf8'));
  const output=writeDocument(edits.reduce(applyEdit,doc));
  const destination=new URL('selection-edited.json',directory);
  if(process.argv.includes('--check')) {
    if(await readFile(destination,'utf8')!==output) throw new Error('selection-edited.json is stale');
    console.log('Actual app delete/duplicate equals independent JavaScript; reverse fixture matches');
  } else { await writeFile(destination,output); console.log('Generated selection-edited.json'); }
} else {
const prefix = process.argv.includes('--v3') ? 'multi-' : '';
if (process.argv.includes('--v3') && process.argv.includes('--lasso')) throw new Error('Choose one fixture family');
const lasso = process.argv.includes('--lasso');
const input = await readFile(new URL(lasso ? 'lasso-moved.json' : prefix + 'source.json', directory), 'utf8');
const commands = JSON.parse(await readFile(new URL('edits.json', directory), 'utf8'));
const result = commands.reduce(applyEdit, readDocument(input));
const output = writeDocument(result);
const destination = new URL((lasso ? 'lasso-' : prefix) + 'edited.json', directory);
if (process.argv.includes('--check')) {
  if (await readFile(destination, 'utf8') !== output) throw new Error('edited.json is stale; regenerate from source and manifest');
  console.log('PortableInk fixture matches real JavaScript command output');
} else {
  await writeFile(destination, output);
  console.log('Generated edited.json at revision ' + result.revision);
}

}
