import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { transformPoint, viewportToPage, pointAppearance } from './render.mjs';
const doc = JSON.parse(readFileSync(new URL('../../Packages/MiNoteCore/Tests/MiNoteCoreTests/Fixtures/PortableInk/source.json', import.meta.url), 'utf8'));
test('affine geometry respects identity, translation, rotation and anisotropic scale', () => {
  const p = {x:80,y:100};
  assert.deepEqual(transformPoint(p,{a:1,b:0,c:0,d:1,tx:0,ty:0}), p);
  assert.deepEqual(transformPoint(p,doc.pages[0].strokes[0].transform), {x:85,y:106});
  assert.deepEqual(transformPoint(p,doc.pages[0].strokes[1].transform), {x:116,y:145});
  assert.deepEqual(transformPoint(p,doc.pages[0].strokes[3].transform), {x:200,y:100});
});
test('viewport scale never enters stored page coordinates', () => {
  for (const scale of [0.5,1,2]) assert.deepEqual(viewportToPage({x:120*scale,y:90*scale},scale),{x:120,y:90});
  assert.throws(() => viewportToPage({x:1,y:1},0));
});
test('point appearance applies size, secondaryScale, opacity and RGBA', () => {
  const value = pointAppearance({red:1,green:0.5,blue:0,alpha:0.35},
    {width:8,height:4,secondaryScale:1.5,opacity:0.8,azimuth:0.3});
  assert.equal(value.radiusX,4); assert.equal(value.radiusY,3);
  assert.equal(value.alpha,0.35*0.8);
  assert.equal(value.rgb,'rgb(255, 128, 0)');
  assert.equal(value.rotation,0.3);
});
