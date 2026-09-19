import 'dart:convert';

String buildSubmissionAudioHtml(String url) {
  final encodedUrl = jsonEncode(url);
  return '''
<!doctype html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<style>
*{box-sizing:border-box}
html,body{width:100%;height:100%;margin:0;overflow:hidden;background:#151515;color:#fff;color-scheme:dark;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif}
.player{position:relative;height:100%;padding:8px 12px 4px}
audio{display:block;width:100%;height:54px;touch-action:pan-x}
.rate{display:grid;grid-template-columns:auto minmax(80px,1fr) 42px;gap:10px;align-items:center;height:42px;font-size:13px;color:#bbb}
input{width:100%;accent-color:#e09321;touch-action:pan-x}
output{text-align:right;color:#e09321;font-variant-numeric:tabular-nums}
#error{display:none;position:absolute;left:12px;right:12px;bottom:1px;padding:1px 3px;background:rgba(21,21,21,.92);font-size:10px;color:#ff7777}
#error:not(:empty){display:block}
</style>
</head>
<body>
<div class="player">
<audio id="player" controls controlslist="nodownload noplaybackrate" preload="metadata"></audio>
<div class="rate">
<label for="rate">Speed</label>
<input id="rate" type="range" min="0.25" max="2" step="0.25" value="1">
<output id="rateValue">1×</output>
</div>
<div id="error"></div>
</div>
<script>
const player=document.getElementById('player');
const rate=document.getElementById('rate');
const rateValue=document.getElementById('rateValue');
player.src=$encodedUrl;
function applyRate(){
  const value=Number(rate.value);
  player.defaultPlaybackRate=value;
  player.playbackRate=value;
  const label=Number.isInteger(value)?value.toFixed(0):value.toFixed(2).replace(/0\$/,'');
  rateValue.textContent=label+'×';
}
rate.addEventListener('input',applyRate);
player.addEventListener('loadedmetadata',applyRate);
player.addEventListener('error',function(){
  document.getElementById('error').textContent='Unable to play this file. You can still download it.';
});
applyRate();
</script>
</body>
</html>
''';
}

String buildSubmissionOdtHtml(String contentUrl) {
  final documentUrl = jsonEncode(contentUrl);
  return '''
<!doctype html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,minimum-scale=1,maximum-scale=4,user-scalable=yes">
<style>
html,body{margin:0;padding:0;background:#151515;color:#e0e0e0;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif}
#status{padding:28px 16px;text-align:center}
#document{width:100%;overflow:hidden;background:#fff;color:#000}
</style>
<script src="https://www.furaffinity.net/themes/beta/js/compiled/webodf.0.5.9.min.js"></script>
</head>
<body>
<div id="status">Loading document…</div>
<div id="document"></div>
<script>
(function(){
  const host=document.getElementById('document');
  const status=document.getElementById('status');
  let ready=false;
  let failed=false;
  let reportScheduled=false;
  function report(){
    const height=Math.max(
      document.body.scrollHeight,
      document.documentElement.scrollHeight,
      host.scrollHeight,
      180
    );
    if(window.flutter_inappwebview){
      window.flutter_inappwebview.callHandler('openPostDocumentHeight',height);
    }
  }
  function scheduleReport(){
    if(reportScheduled){
      return;
    }
    reportScheduled=true;
    requestAnimationFrame(function(){
      reportScheduled=false;
      report();
    });
  }
  function fail(message){
    if(failed||ready){
      return;
    }
    failed=true;
    status.textContent=message;
    if(window.flutter_inappwebview){
      window.flutter_inappwebview.callHandler('openPostDocumentError',message);
    }
  }
  try{
    if(!window.odf||!window.odf.OdfCanvas){
      fail('Unable to preview this ODT file. Download the original file to open it.');
      return;
    }
    const canvas=new window.odf.OdfCanvas(host);
    canvas.addListener('statereadychange',function(){
      if(ready){
        return;
      }
      ready=true;
      if(window.flutter_inappwebview){
        window.flutter_inappwebview.callHandler('openPostDocumentReady');
      }
      if(status.isConnected){
        status.remove();
      }
      try{
        canvas.fitToWidth(host.clientWidth);
      }catch(_){}
      scheduleReport();
      setTimeout(scheduleReport,250);
      setTimeout(scheduleReport,1000);
    });
    canvas.load($documentUrl);
    new MutationObserver(scheduleReport).observe(document.body,{
      childList:true,
      subtree:true
    });
    if(window.ResizeObserver){
      new ResizeObserver(scheduleReport).observe(host);
    }
    window.addEventListener('resize',function(){
      try{
        canvas.fitToWidth(host.clientWidth);
      }catch(_){}
      scheduleReport();
    });
  }catch(error){
    fail('Unable to preview this ODT file. Download the original file to open it.');
  }
})();
</script>
</body>
</html>
''';
}
