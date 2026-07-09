import 'package:FANotifier/shared/fa/fa_bbcode_webview_scripts.dart';

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
  return buildFaBbcodeWrapSelectionScript(tag);
}
