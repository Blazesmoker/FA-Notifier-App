

String documentViewerSetupScript({
  required bool expandsToContent,
  required bool supportsZoom,
  required bool usesReaderPresentation,
  required bool inspectionMode,
}) {
  return '''
(function(){
  const expandsToContent=$expandsToContent;
  const supportsZoom=$supportsZoom;
  const usesReaderPresentation=$usesReaderPresentation;
  const inspectionMode=$inspectionMode;
  let viewport=document.querySelector('meta[name="viewport"]');
  if(!viewport){
    viewport=document.createElement('meta');
    viewport.name='viewport';
    document.head.appendChild(viewport);
  }
  viewport.content=supportsZoom
    ? 'width=device-width,initial-scale=1,minimum-scale=1,maximum-scale=4,user-scalable=yes'
    : 'width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no';
  if((!expandsToContent&&!usesReaderPresentation&&!inspectionMode)||
      window.__openPostDocumentHeightObserver){
    return;
  }
  window.__openPostDocumentHeightObserver=true;
  let reportScheduled=false;
  let observedTarget=null;
  let eventBusBound=false;
  let readerSignature='';
  let readerSignatureSince=0;
  let readerRetryScheduled=false;
  let pageWidthApplied=false;
  let pdfClassificationStarted=false;
  let pdfPreviewMode=null;
  let readerTextReported=false;
  let readerFallbackReady=false;
  const readerStartedAt=Date.now();
  const resizeObserver=window.ResizeObserver
    ? new ResizeObserver(scheduleOpenPostDocumentHeight)
    : null;
  function readerTarget(){
    return document.getElementById('openPostReader')||
      document.getElementById('viewer')||
      document.querySelector('pre')||
      document.querySelector('article')||
      document.querySelector('main')||
      document.body;
  }
  function observeTarget(target){
    if(!resizeObserver||!target||target===observedTarget){
      return;
    }
    resizeObserver.disconnect();
    resizeObserver.observe(target);
    observedTarget=target;
  }
  function applyPdfPageLayout(){
    if(!inspectionMode&&!(usesReaderPresentation&&!expandsToContent)){
      return;
    }
    const app=window.PDFViewerApplication;
    const pdfViewer=app&&app.pdfViewer;
    const viewer=document.getElementById('viewer');
    if(!pdfViewer||!viewer){
      return;
    }
    const pages=viewer.querySelectorAll('.page');
    if(pages.length===0){
      return;
    }
    if(inspectionMode){
      viewer.classList.toggle(
        'openPostInspectionSinglePage',
        pages.length===1
      );
    }
    if(!pageWidthApplied){
      try{
        pdfViewer.currentScaleValue='page-width';
        pageWidthApplied=true;
      }catch(_){}
    }
  }
  function scheduleReaderRetry(){
    if(readerRetryScheduled){
      return;
    }
    readerRetryScheduled=true;
    setTimeout(function(){
      readerRetryScheduled=false;
      scheduleOpenPostDocumentHeight();
    },220);
  }
  function readerLines(textLayer){
    const items=[];
    for(const node of textLayer.querySelectorAll('span')){
      const value=(node.textContent||'').replace(/\\s+/g,' ').trim();
      if(!value){
        continue;
      }
      const rect=node.getBoundingClientRect();
      if(rect.width<=0||rect.height<=0){
        continue;
      }
      items.push({
        value:value,
        left:rect.left,
        right:rect.right,
        top:rect.top,
        bottom:rect.bottom,
        height:rect.height,
        center:rect.top+rect.height/2
      });
    }
    items.sort(function(a,b){
      const vertical=a.center-b.center;
      return Math.abs(vertical)>2?vertical:a.left-b.left;
    });
    const lines=[];
    for(const item of items){
      const last=lines.length>0?lines[lines.length-1]:null;
      const tolerance=last?Math.max(2,Math.min(last.height,item.height)*0.35):0;
      if(!last||Math.abs(last.center-item.center)>tolerance){
        lines.push({
          items:[item],
          center:item.center,
          top:item.top,
          bottom:item.bottom,
          height:item.height
        });
        continue;
      }
      last.items.push(item);
      last.center=(last.center*(last.items.length-1)+item.center)/last.items.length;
      last.top=Math.min(last.top,item.top);
      last.bottom=Math.max(last.bottom,item.bottom);
      last.height=Math.max(last.height,item.height);
    }
    return lines;
  }
  function readerLineText(line){
    line.items.sort(function(a,b){return a.left-b.left;});
    let text='';
    let right=null;
    for(const item of line.items){
      const gap=right===null?0:item.left-right;
      if(text&&gap>Math.max(1,item.height*0.12)&&
          !'.,;:!?)]}'.includes(item.value.charAt(0))){
        text+=' ';
      }
      text+=item.value;
      right=right===null?item.right:Math.max(right,item.right);
    }
    return text;
  }
  function pdfTextLines(items){
    const positioned=[];
    for(const item of items){
      const value=(item.str||'').replace(/\\s+/g,' ').trim();
      if(!value){
        continue;
      }
      const transform=item.transform||[];
      const left=Number(transform[4])||0;
      const center=Number(transform[5])||0;
      const height=Math.max(
        1,
        Math.abs(Number(transform[3]))||Number(item.height)||12
      );
      const width=Math.max(0,Number(item.width)||0);
      positioned.push({
        value:value,
        left:left,
        right:left+width,
        center:center,
        height:height,
        hasEOL:item.hasEOL===true
      });
    }
    positioned.sort(function(a,b){
      const vertical=b.center-a.center;
      return Math.abs(vertical)>2?vertical:a.left-b.left;
    });
    const lines=[];
    for(const item of positioned){
      const last=lines.length>0?lines[lines.length-1]:null;
      const tolerance=last
        ? Math.max(2,Math.min(last.height,item.height)*0.4)
        : 0;
      if(!last||Math.abs(last.center-item.center)>tolerance){
        lines.push({
          items:[item],
          center:item.center,
          height:item.height
        });
        continue;
      }
      last.items.push(item);
      last.center=(last.center*(last.items.length-1)+item.center)/last.items.length;
      last.height=Math.max(last.height,item.height);
    }
    return lines;
  }
  function pdfLineText(line){
    line.items.sort(function(a,b){return a.left-b.left;});
    let text='';
    let right=null;
    for(const item of line.items){
      const gap=right===null?0:item.left-right;
      if(text&&gap>Math.max(1,item.height*0.12)&&
          !'.,;:!?)]}'.includes(item.value.charAt(0))){
        text+=' ';
      }
      text+=item.value;
      right=right===null?item.right:Math.max(right,item.right);
    }
    return text;
  }
  function reportFullReaderText(fullTextPages){
    const fullText=fullTextPages.join('\\n\\n').trim();
    if(fullText&&window.flutter_inappwebview){
      readerTextReported=true;
      window.flutter_inappwebview.callHandler(
        'openPostDocumentFullText',
        fullText
      );
    }
  }
  function normalizedDocumentText(target){
    if(!target){
      return '';
    }
    let value=target.innerText||'';
    if(!value&&typeof target.cloneNode==='function'){
      const clone=target.cloneNode(true);
      for(const node of clone.querySelectorAll('script,style,noscript')){
        node.remove();
      }
      value=clone.textContent||'';
    }
    return value
      .replace(/\\u00a0/g,' ')
      .replace(/\\r\\n?/g,'\\n')
      .replace(/[ \\t]+\\n/g,'\\n')
      .replace(/\\n[ \\t]+/g,'\\n')
      .trim();
  }
  function reportDocumentReaderText(){
    if(readerTextReported){
      return true;
    }
    const viewer=document.getElementById('viewer');
    const candidates=[
      viewer&&viewer.querySelector('pre'),
      viewer&&viewer.querySelector('article'),
      viewer&&viewer.querySelector('main'),
      viewer,
      document.querySelector('pre'),
      document.querySelector('article'),
      document.querySelector('main'),
      document.body
    ];
    for(const frame of document.querySelectorAll('iframe')){
      try{
        const frameDocument=frame.contentDocument;
        if(frameDocument){
          candidates.push(
            frameDocument.querySelector('pre'),
            frameDocument.querySelector('article'),
            frameDocument.querySelector('main'),
            frameDocument.body
          );
        }
      }catch(_){}
    }
    const visited=new Set();
    let text='';
    for(const target of candidates){
      if(!target||visited.has(target)){
        continue;
      }
      visited.add(target);
      const candidate=normalizedDocumentText(target);
      if(candidate&&!/^loading(?:\\.\\.\\.)?\$/i.test(candidate)){
        text=candidate;
        break;
      }
    }
    if(!text){
      scheduleReaderRetry();
      return false;
    }
    const signature='document:'+text.length+':'+
      text.slice(0,64)+':'+text.slice(-64);
    const now=Date.now();
    if(signature!==readerSignature){
      readerSignature=signature;
      readerSignatureSince=now;
      scheduleReaderRetry();
      return false;
    }
    if(now-readerSignatureSince<180){
      scheduleReaderRetry();
      return false;
    }
    reportFullReaderText([text]);
    return readerTextReported;
  }
  function reportReaderFallbackReady(){
    if(readerTextReported||readerFallbackReady||
        Date.now()-readerStartedAt<2000){
      return;
    }
    const target=readerTarget();
    if(!target||target.getBoundingClientRect().height<=0||
        !window.flutter_inappwebview){
      return;
    }
    readerFallbackReady=true;
    window.flutter_inappwebview.callHandler('openPostDocumentReady');
  }
  function buildReaderFromTextContents(pageContents){
    const existing=document.getElementById('openPostReader');
    if(existing){
      return existing;
    }
    const viewer=document.getElementById('viewer');
    if(!viewer||!viewer.parentNode){
      return null;
    }
    const reader=document.createElement('div');
    reader.id='openPostReader';
    let hasText=false;
    const fullTextPages=[];
    for(const items of pageContents){
      const lines=pdfTextLines(items);
      if(lines.length===0){
        continue;
      }
      hasText=true;
      const page=document.createElement('div');
      page.className='openPostReaderPage';
      const pageTextLines=[];
      let previous=null;
      for(const line of lines){
        const lineElement=document.createElement('div');
        lineElement.className='openPostReaderLine';
        const lineText=pdfLineText(line);
        lineElement.textContent=lineText;
        if(previous){
          const gap=Math.abs(previous.center-line.center);
          if(gap>Math.max(previous.height,line.height)*1.6){
            lineElement.style.marginTop='19.6px';
            pageTextLines.push('');
          }
        }
        page.appendChild(lineElement);
        pageTextLines.push(lineText);
        previous=line;
      }
      reader.appendChild(page);
      fullTextPages.push(pageTextLines.join('\\n'));
    }
    if(!hasText){
      return null;
    }
    document.documentElement.classList.add('openPostFullTextReader');
    viewer.parentNode.insertBefore(reader,viewer);
    viewer.style.setProperty('display','none','important');
    reportFullReaderText(fullTextPages);
    return reader;
  }
  function imageOperatorSet(){
    const pdfjs=window.pdfjsLib;
    const ops=pdfjs&&pdfjs.OPS;
    if(ops){
      const values=new Set([
        ops.paintImageMaskXObject,
        ops.paintImageMaskXObjectGroup,
        ops.paintImageXObject,
        ops.paintInlineImageXObject,
        ops.paintInlineImageXObjectGroup,
        ops.paintImageXObjectRepeat,
        ops.paintImageMaskXObjectRepeat,
        ops.paintSolidColorImageMask
      ].filter(function(value){return typeof value==='number';}));
      if(values.size>0){
        return values;
      }
    }
    return new Set([83,84,85,86,87,88,89,90]);
  }
  function reportFullTextReaderHeight(){
    const reader=document.getElementById('openPostReader');
    if(!reader||!window.flutter_inappwebview){
      return;
    }
    const rect=reader.getBoundingClientRect();
    const height=Math.ceil(Math.max(rect.height,reader.scrollHeight)+12);
    if(height>0){
      window.flutter_inappwebview.callHandler(
        'openPostDocumentPreviewHeight',
        {mode:'fullText',height:height}
      );
    }
  }
  function reportVisualPdfPreview(mode){
    if(inspectionMode||expandsToContent){
      return;
    }
    const viewerContainer=document.getElementById('viewerContainer');
    const viewer=document.getElementById('viewer');
    const page=viewer?viewer.querySelector('.page'):null;
    if(!viewerContainer||!page||!window.flutter_inappwebview){
      return;
    }
    const containerRect=viewerContainer.getBoundingClientRect();
    const pageRect=page.getBoundingClientRect();
    const height=Math.ceil(pageRect.bottom-containerRect.top+12);
    if(height>0){
      window.flutter_inappwebview.callHandler(
        'openPostDocumentPreviewHeight',
        {mode:mode,height:height}
      );
    }
  }
  async function classifyPdfPreview(){
    if(pdfClassificationStarted||inspectionMode||expandsToContent||
        !usesReaderPresentation){
      return;
    }
    const app=window.PDFViewerApplication;
    const pdfDocument=app&&app.pdfDocument;
    if(!pdfDocument){
      return;
    }
    pdfClassificationStarted=true;
    try{
      const pageContents=[];
      const imageOps=imageOperatorSet();
      let hasText=false;
      let hasImages=false;
      for(let pageNumber=1;pageNumber<=pdfDocument.numPages;pageNumber++){
        const page=await pdfDocument.getPage(pageNumber);
        const textContent=await page.getTextContent();
        const items=Array.isArray(textContent.items)?textContent.items:[];
        pageContents.push(items);
        if(items.some(function(item){
          return !!(item.str||'').trim();
        })){
          hasText=true;
        }
        const operatorList=await page.getOperatorList();
        const operators=operatorList&&operatorList.fnArray
          ? Array.from(operatorList.fnArray)
          : [];
        if(operators.some(function(operator){return imageOps.has(operator);})){
          hasImages=true;
        }
      }
      if(hasText&&!hasImages&&buildReaderFromTextContents(pageContents)){
        pdfPreviewMode='fullText';
      }else{
        pdfPreviewMode=(hasText&&hasImages)||pdfDocument.numPages>1
          ? 'truncated'
          : 'preview';
      }
    }catch(_){
      pdfPreviewMode='truncated';
    }
    scheduleOpenPostDocumentHeight();
  }
  function buildReaderFromPdf(){
    if(!usesReaderPresentation||document.getElementById('openPostReader')){
      return;
    }
    const viewer=document.getElementById('viewer');
    if(!viewer){
      if(expandsToContent){
        reportDocumentReaderText();
      }
      return;
    }
    const pages=Array.from(viewer.querySelectorAll('.page'));
    if(pages.length===0){
      if(expandsToContent){
        reportDocumentReaderText();
      }
      return;
    }
    const pageLayers=pages.map(function(page){
      return page.querySelector('.textLayer');
    });
    if(expandsToContent&&pageLayers.some(function(layer){return !layer;})){
      return;
    }
    let layers=pageLayers.filter(function(layer){return !!layer;});
    if(layers.length===0){
      if(expandsToContent){
        reportDocumentReaderText();
      }
      return;
    }
    if(!expandsToContent){
      layers=layers.slice(0,1);
    }
    const signature=layers.map(function(layer){
      const spans=layer.querySelectorAll('span');
      return spans.length+':'+(layer.textContent||'').length;
    }).join('|');
    if(!signature||signature===pages.length+':0'){
      if(expandsToContent){
        reportDocumentReaderText();
      }
      return;
    }
    const now=Date.now();
    if(signature!==readerSignature){
      readerSignature=signature;
      readerSignatureSince=now;
      scheduleReaderRetry();
      return;
    }
    if(now-readerSignatureSince<180){
      scheduleReaderRetry();
      return;
    }
    const reader=document.createElement('div');
    reader.id='openPostReader';
    let hasText=false;
    const fullTextPages=[];
    for(const layer of layers){
      const lines=readerLines(layer);
      if(lines.length===0){
        continue;
      }
      hasText=true;
      const page=document.createElement('div');
      page.className='openPostReaderPage';
      const pageTextLines=[];
      let previous=null;
      for(const line of lines){
        const lineElement=document.createElement('div');
        lineElement.className='openPostReaderLine';
        const lineText=readerLineText(line);
        lineElement.textContent=lineText;
        if(previous){
          const gap=line.top-previous.bottom;
          if(gap>Math.max(previous.height,line.height)*0.8){
            lineElement.style.marginTop='19.6px';
            pageTextLines.push('');
          }
        }
        page.appendChild(lineElement);
        pageTextLines.push(lineText);
        previous=line;
      }
      reader.appendChild(page);
      fullTextPages.push(pageTextLines.join('\\n'));
    }
    if(!hasText||!viewer.parentNode){
      if(expandsToContent){
        reportDocumentReaderText();
      }
      return;
    }
    viewer.parentNode.insertBefore(reader,viewer);
    viewer.style.setProperty('display','none','important');
    reportFullReaderText(fullTextPages);
  }
  function trimLastReaderPage(){
    if(document.getElementById('openPostReader')){
      return;
    }
    const viewer=document.getElementById('viewer');
    if(!viewer){
      return;
    }
    const pages=viewer.querySelectorAll('.page');
    const page=pages.length>0?pages[pages.length-1]:null;
    const textLayer=page?page.querySelector('.textLayer'):null;
    if(!page||!textLayer){
      return;
    }
    const pageRect=page.getBoundingClientRect();
    let contentBottom=0;
    for(const node of textLayer.querySelectorAll('span')){
      if(!(node.textContent||'').trim()){
        continue;
      }
      const rect=node.getBoundingClientRect();
      if(rect.width<=0||rect.height<=0){
        continue;
      }
      contentBottom=Math.max(contentBottom,rect.bottom-pageRect.top);
    }
    if(contentBottom<=0){
      return;
    }
    const height=Math.max(36,Math.ceil(contentBottom+16));
    const heightValue=height+'px';
    if(page.dataset.openPostReaderHeight===heightValue){
      return;
    }
    page.dataset.openPostReaderHeight=heightValue;
    page.style.setProperty('height',heightValue,'important');
    page.style.setProperty('min-height','0','important');
  }
  function bindEventBus(){
    const app=window.PDFViewerApplication;
    const eventBus=app&&app.eventBus;
    if(eventBusBound||!eventBus||typeof eventBus.on!=='function'){
      return;
    }
    eventBusBound=true;
    eventBus.on('pagesinit',scheduleOpenPostDocumentHeight);
    eventBus.on('pagesloaded',scheduleOpenPostDocumentHeight);
    eventBus.on('pagerendered',scheduleOpenPostDocumentHeight);
    eventBus.on('textlayerrendered',scheduleOpenPostDocumentHeight);
    eventBus.on('scalechanging',scheduleOpenPostDocumentHeight);
  }
  function reportOpenPostDocumentHeight(){
    bindEventBus();
    applyPdfPageLayout();
    if(usesReaderPresentation&&!expandsToContent){
      classifyPdfPreview();
      if(pdfPreviewMode==='fullText'){
        reportFullTextReaderHeight();
      }else if(pdfPreviewMode){
        reportVisualPdfPreview(pdfPreviewMode);
      }
      return;
    }
    buildReaderFromPdf();
    if(!expandsToContent){
      return;
    }
    if(usesReaderPresentation&&!readerTextReported){
      reportReaderFallbackReady();
    }
    trimLastReaderPage();
    const target=readerTarget();
    if(!target){
      return;
    }
    observeTarget(target);
    const rect=target.getBoundingClientRect();
    if(rect.width<=0||rect.height<=0){
      return;
    }
    const height=Math.ceil(rect.bottom+window.scrollY)+1;
    if(height>0&&window.flutter_inappwebview){
      window.flutter_inappwebview.callHandler('openPostDocumentHeight',height);
    }
  }
  function scheduleOpenPostDocumentHeight(){
    if(reportScheduled){
      return;
    }
    reportScheduled=true;
    requestAnimationFrame(function(){
      reportScheduled=false;
      reportOpenPostDocumentHeight();
    });
  }
  if(window.MutationObserver&&document.body){
    new MutationObserver(scheduleOpenPostDocumentHeight).observe(document.body,{
      childList:true,
      characterData:true,
      subtree:true
    });
  }
  if(document.fonts&&document.fonts.ready){
    document.fonts.ready.then(scheduleOpenPostDocumentHeight);
  }
  window.addEventListener('resize',scheduleOpenPostDocumentHeight);
  setTimeout(scheduleOpenPostDocumentHeight,50);
  setTimeout(scheduleOpenPostDocumentHeight,300);
  setTimeout(scheduleOpenPostDocumentHeight,1000);
  setTimeout(scheduleOpenPostDocumentHeight,2500);
  setTimeout(scheduleOpenPostDocumentHeight,5000);
  scheduleOpenPostDocumentHeight();
})();
''';
}
