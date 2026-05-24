String buildNoteReplyFormScript({
  required String replyText,
  required String originalContent,
  required String recipient,
  required String subject,
}) {
  final fullMessage = '$replyText\n\n—————————\n$originalContent';
  final escapedMessage = _escapeJavaScriptString(fullMessage);
  final escapedRecipient = _escapeJavaScriptString(recipient);
  final escapedSubject = _escapeJavaScriptString(subject);

  return '''
      (function() {
        var viewport = document.querySelector('meta[name="viewport"]');
        if (!viewport) {
          viewport = document.createElement('meta');
          viewport.name = 'viewport';
          document.head.appendChild(viewport);
        }
        viewport.content = 'width=device-width, initial-scale=1.0, maximum-scale=3.0, user-scalable=yes';
        
        setTimeout(function() {
          var toField = document.querySelector('input[name="to"]');
          var subjectField = document.querySelector('input[name="subject"]');
          var messageField = document.querySelector('textarea[name="message"]');
          
          if (toField) toField.value = '$escapedRecipient';
          if (subjectField) subjectField.value = '$escapedSubject';
          if (messageField) messageField.value = '$escapedMessage';
          
       
          var style = document.createElement('style');
          style.innerHTML = `
            .block-menu-top, .block-banners, .footer, 
            .headerAds, .leaderboardAd, .footerAds,
            table[cellpadding="10"]:first-of-type { display: none !important; }
            body { padding-top: 20px !important; }
            .maintable { margin-top: 0 !important; }
            .viewmessage .maintable:first-of-type { display: none !important; }
          `;
          document.head.appendChild(style);
          
          var noteForm = document.getElementById('note-form');
          if (noteForm) {
            noteForm.scrollIntoView({ behavior: 'smooth' });
          }
        }, 500);
      })();
    ''';
}

String _escapeJavaScriptString(String value) {
  return value
      .replaceAll('\\', '\\\\')
      .replaceAll('\n', '\\n')
      .replaceAll('\r', '\\r')
      .replaceAll('\'', '\\\'')
      .replaceAll('"', '\\"');
}
