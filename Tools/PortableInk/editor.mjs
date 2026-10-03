import { readDocument, writeDocument, applyEdit } from './document.mjs';
export class InkEditor {
  document = null;
  open(text) { const next=readDocument(text); this.document=next; }
  edit(command) { const next=applyEdit(this.document,command); this.document=next; }
  export() { return writeDocument(this.document); }
}
