String buildUploadFileInputScript({
  required String base64Data,
  required String fileName,
  required String extension,
  required bool returnResult,
}) {
  final returnSuccess = returnResult ? 'return true;' : '';
  final returnFailure = returnResult ? 'return false;' : '';

  return '''
      (function() {
        try {
          var base64 = "$base64Data";
          var binary = atob(base64);
          var array = new Uint8Array(binary.length);
          for (var i = 0; i < binary.length; i++) {
            array[i] = binary.charCodeAt(i);
          }
          
          var blob = new Blob([array], { type: 'image/$extension' });
          var file = new File([blob], "$fileName", { 
            type: 'image/$extension',
            lastModified: Date.now()
          });
          
          var dt = new DataTransfer();
          dt.items.add(file);
          
          var input = document.querySelector('input[name="submission"]');
          if (input) {
            input.files = dt.files;
            input.dispatchEvent(new Event('change', { bubbles: true }));
            
            if (window.submissionUploader && window.submissionUploader.updateFileInfo) {
              window.submissionUploader.updateFileInfo();
            }
          }
          
          $returnSuccess
        } catch(e) {
          console.error('Error setting file:', e);
          $returnFailure
        }
      })();
    ''';
}

String buildUploadFilePickerHandlerScript() {
  return '''
    (function() {
      var input = document.querySelector('input[name="submission"]');
      if (!input) return;
      
      var originalClick = input.onclick;
      input.onclick = null;
      
      input.addEventListener('click', function(e) {
        e.preventDefault();
        e.stopPropagation();
        window.flutter_inappwebview.callHandler('selectFile');
        return false;
      }, true);
      
      var dragDrop = document.querySelector('#submissionFileDragDropArea');
      if (dragDrop) {
        dragDrop.addEventListener('click', function(e) {
          if (e.target.tagName !== 'INPUT') {
            e.preventDefault();
            e.stopPropagation();
            window.flutter_inappwebview.callHandler('selectFile');
            return false;
          }
        }, true);
      }
    })();
  ''';
}

String buildUploadWrapSelectionScript(String tag) {
  return '''
(function(){
  var open='[$tag]';
  var close='[/$tag]';
  var active=document.activeElement;

  if (active && (active.tagName==='TEXTAREA' || (active.tagName==='INPUT' && active.type==='text'))) {
    var s=active.selectionStart, e=active.selectionEnd;
    if (s!=null && e!=null && e>s) {
      var before=active.value.substring(0,s);
      var sel=active.value.substring(s,e);
      var after=active.value.substring(e);
      active.value=before+open+sel+close+after;
      active.selectionStart=before.length+open.length;
      active.selectionEnd=active.selectionStart+sel.length;
      active.dispatchEvent(new Event('input',{bubbles:true}));
    }
    return;
  }

  var sel=window.getSelection();
  if (!sel || sel.rangeCount===0) return;
  var r=sel.getRangeAt(0);
  var t=sel.toString();
  var node=document.createTextNode(open+t+close);
  r.deleteContents();
  r.insertNode(node);

  var nr=document.createRange();
  nr.setStartAfter(node);
  nr.collapse(true);
  sel.removeAllRanges();
  sel.addRange(nr);
})();
''';
}
