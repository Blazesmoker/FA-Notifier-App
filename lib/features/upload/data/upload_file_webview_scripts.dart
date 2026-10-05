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
          var supportedInputNames = [
            'submission',
            'thumbnail',
            'newsubmission',
            'newthumbnail'
          ];
          if (supportedInputNames.indexOf(inputName) === -1) {
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
      if (window.__faUploadFilePickerHandlerInstalled) return;
      window.__faUploadFilePickerHandlerInstalled = true;

      document.addEventListener('click', function(e) {
        var target = e.target;
        if (!target || typeof target.closest !== 'function') return;

        var input = target.closest('input[type="file"][name="submission"], input[type="file"][name="thumbnail"]');
        if (!input) {
          var label = target.closest('label[for="submissionFileInput"], label[for="thumbnailFileInput"]');
          if (label) input = document.getElementById(label.htmlFor);
        }
        if (!input) {
          var dragDrop = target.closest('#submissionFileDragDropArea, #thumbnailFileDragDropArea');
          if (dragDrop) {
            var inputName = dragDrop.id === 'submissionFileDragDropArea' ? 'submission' : 'thumbnail';
            input = document.querySelector('input[type="file"][name="' + inputName + '"]');
          }
        }
        if (!input || input.type !== 'file' || (input.name !== 'submission' && input.name !== 'thumbnail')) return;

        e.preventDefault();
        e.stopImmediatePropagation();
        window.flutter_inappwebview.callHandler('selectFile', input.name);
      }, true);
    })();
  ''';
}

String buildUploadWrapSelectionScript(String tag) {
  return buildFaBbcodeWrapSelectionScript(tag);
}
