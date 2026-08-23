import 'dart:convert';

import 'package:fanotifier/shared/fa/fa_bbcode_webview_scripts.dart';

String buildUploadFileInputScript({
  required String base64Data,
  required String fileName,
  required String extension,
  String inputName = 'submission',
}) {
  const returnSuccess = 'return true;';
  const returnFailure = 'return false;';

  final mimeType = switch (extension.toLowerCase()) {
    'jpg' || 'jpeg' => 'image/jpeg',
    'png' => 'image/png',
    'gif' => 'image/gif',
    _ => 'application/octet-stream',
  };
  final encodedBase64 = jsonEncode(base64Data);
  final encodedFileName = jsonEncode(fileName);
  final encodedMimeType = jsonEncode(mimeType);
  final encodedInputName = jsonEncode(inputName);

  return '''
      (function() {
        try {
          var base64 = $encodedBase64;
          var binary = atob(base64);
          var array = new Uint8Array(binary.length);
          for (var i = 0; i < binary.length; i++) {
            array[i] = binary.charCodeAt(i);
          }
          
          var blob = new Blob([array], { type: $encodedMimeType });
          var file = new File([blob], $encodedFileName, {
            type: $encodedMimeType,
            lastModified: Date.now()
          });
          
          var dt = new DataTransfer();
          dt.items.add(file);
          
          var inputName = $encodedInputName;
          if (inputName !== 'submission' && inputName !== 'thumbnail') {
            return false;
          }
          var input = document.querySelector('input[name="' + inputName + '"]');
          if (input) {
            input.files = dt.files;
            input.dispatchEvent(new Event('change', { bubbles: true }));
            
            if (inputName === 'submission' && window.submissionUploader && window.submissionUploader.updateFileInfo) {
              window.submissionUploader.updateFileInfo();
            }
            $returnSuccess
          }
          $returnFailure
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
