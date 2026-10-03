export function transformPoint(point, t) {
  return {x:t.a*point.x+t.c*point.y+t.tx, y:t.b*point.x+t.d*point.y+t.ty};
}
export function viewportToPage(point, scale) {
  if (!Number.isFinite(scale) || scale <= 0) throw new Error('잘못된 화면 배율입니다.');
  return {x:point.x/scale,y:point.y/scale};
}
export function pointAppearance(color, p) {
  return {radiusX:p.width/2,radiusY:p.height*(p.secondaryScale??1)/2,rotation:p.azimuth,
    alpha:color.alpha*p.opacity,rgb:`rgb(${Math.round(color.red*255)}, ${Math.round(color.green*255)}, ${Math.round(color.blue*255)})`};
}
export function drawPage(context, page, viewportScale) {
  context.save();
  context.scale(viewportScale,viewportScale);
  context.beginPath(); context.rect(0,0,page.width,page.height); context.clip();
  context.fillStyle = 'white'; context.fillRect(0,0,page.width,page.height);
  if (page.paper==='ruled' || page.paper==='grid') {
    context.strokeStyle='rgb(217, 217, 217)'; context.lineWidth=0.5; context.beginPath();
    for(let y=24;y<page.height;y+=24) { context.moveTo(0,y); context.lineTo(page.width,y); }
    if(page.paper==='grid') for(let x=24;x<page.width;x+=24) { context.moveTo(x,0); context.lineTo(x,page.height); }
    context.stroke();
  }
  for (const stroke of page.strokes) {
    context.save(); const t = stroke.transform;
    context.transform(t.a,t.b,t.c,t.d,t.tx,t.ty);
    context.lineCap = 'round'; context.lineJoin = 'round';
    for (let i=0;i<stroke.points.length;i++) {
      const p=stroke.points[i], appearance=pointAppearance(stroke.color,p);
      context.fillStyle=appearance.rgb; context.strokeStyle=appearance.rgb;
      context.globalAlpha=appearance.alpha;
      if (i>0) {
        const prior=stroke.points[i-1]; context.lineWidth=(prior.width+p.width)/2;
        context.beginPath(); context.moveTo(prior.x,prior.y); context.lineTo(p.x,p.y); context.stroke();
      }
      context.beginPath();
      context.ellipse(p.x,p.y,appearance.radiusX,appearance.radiusY,appearance.rotation,0,Math.PI*2);
      context.fill();
    }
    context.restore();
  }
  context.restore();
}
