import 'dart:convert';

String buildSubmissionAudioHtml(
  String url, {
  bool nativePlaybackSpeedEnabled = true,
  double playbackRate = 1.0,
}) {
  final encodedUrl = jsonEncode(url);
  final controlsList = nativePlaybackSpeedEnabled
      ? 'nodownload'
      : 'nodownload noplaybackrate';
  return '''
<!doctype html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<style>
*{box-sizing:border-box}
html,body{width:100%;height:100%;margin:0;overflow:hidden;background:#151515;color:#fff;color-scheme:dark;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif}
.player{position:relative;height:100%;padding:8px 0 4px}
audio{display:block;width:100%;height:54px;touch-action:pan-x}
#error{display:none;position:absolute;left:0;right:0;bottom:1px;padding:1px 3px;background:rgba(21,21,21,.92);font-size:10px;color:#ff7777}
#error:not(:empty){display:block}
</style>
</head>
<body>
<div class="player">
<audio id="player" controls controlslist="$controlsList" preload="metadata"></audio>
<div id="error"></div>
</div>
<script>
const player=document.getElementById('player');
player.src=$encodedUrl;
player.defaultPlaybackRate=$playbackRate;
player.playbackRate=$playbackRate;
player.addEventListener('error',function(){
  document.getElementById('error').textContent='Unable to play this file. You can still download it.';
});
</script>
</body>
</html>
''';
}

String buildSubmissionAudioPlaybackRateScript(double playbackRate) {
  return '''
(function(){
  const player=document.getElementById('player');
  if(!player){return false;}
  player.defaultPlaybackRate=$playbackRate;
  player.playbackRate=$playbackRate;
  return true;
})();
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
