// A gesture owns a document/page until it is committed or explicitly cancelled.
export class StrokeInput {
  pointerID = null;
  owner = null;
  points = [];
  begin(pointerID, owner) {
    if (this.pointerID !== null) return false;
    this.pointerID = pointerID;
    this.owner = {...owner};
    this.points = [];
    return true;
  }
  matches(owner) {
    return this.owner?.documentID === owner.documentID && this.owner?.pageID === owner.pageID;
  }
  add(pointerID, owner, point) {
    if (pointerID !== this.pointerID) return;
    if (!this.matches(owner)) { this.cancel(pointerID); return; }
    this.points.push({...point});
  }
  finish(pointerID, owner, point) {
    if (pointerID !== this.pointerID) return null;
    if (!this.matches(owner)) { this.cancel(pointerID); return null; }
    this.add(pointerID, owner, point);
    const result = {...this.owner, points:this.points};
    this.cancel(pointerID);
    return result;
  }
  cancel(pointerID = this.pointerID) {
    if (pointerID !== this.pointerID) return;
    this.pointerID = null; this.owner = null; this.points = [];
  }
}
