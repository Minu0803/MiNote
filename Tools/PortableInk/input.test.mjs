import test from 'node:test';
import assert from 'node:assert/strict';
import { StrokeInput } from './input.mjs';

const owner = {documentID:'document1',pageID:'page1'};
const p = {x:10,y:20,timeOffset:0};
test('gesture retains its original owner and sampled coordinates',()=>{
  const input=new StrokeInput();
  assert.equal(input.begin(1,owner),true);
  input.add(1,owner,p);
  const result=input.finish(1,owner,{...p,x:30,timeOffset:0.1});
  assert.deepEqual(result,{...owner,points:[p,{...p,x:30,timeOffset:0.1}]});
  assert.equal(input.pointerID,null);
});
test('page or document replacement cancels instead of crossing ownership',()=>{
  for(const next of [{...owner,pageID:'page2'},{...owner,documentID:'document2'}]){
    const input=new StrokeInput();input.begin(1,owner);input.add(1,owner,p);
    assert.equal(input.finish(1,next,p),null);
    assert.equal(input.pointerID,null);
  }
});
test('mode exit or lost capture cancels and permits a fresh gesture',()=>{
  const input=new StrokeInput();input.begin(1,owner);input.add(1,owner,p);
  input.cancel(1);
  assert.equal(input.finish(1,owner,p),null);
  assert.equal(input.begin(2,owner),true);
});
test('secondary pointer events cannot append or cancel primary input',()=>{
  const input=new StrokeInput();input.begin(1,owner);input.add(1,owner,p);
  assert.equal(input.begin(2,owner),false);
  input.cancel(2);input.add(2,owner,{...p,x:999});
  assert.equal(input.finish(2,owner,p),null);
  assert.equal(input.pointerID,1);
  assert.deepEqual(input.finish(1,owner,p).points,[p,p]);
});
