String buildFindCreatedJournalPathScript() {
  return '''
(function() {
  const links = document.querySelectorAll('a[href^="/journal/"]');
  for (const link of links) {
    const href = link.getAttribute('href');
    if (href && href.endsWith('/')) return href;
  }
  return null;
})();
''';
}

String buildJournalFormInjectionScript() {
  return '''
      (function() {
        if (window.__journalCssInjected) return;
        window.__journalCssInjected = true;

        var style = document.createElement('style');
        style.type = 'text/css';
        style.innerHTML = \`
          .sidebar {
            display: none !important;
          }
          #journal-form {
            margin: 0 auto !important;
            padding: 0 !important;
            width: 100% !important;
            max-width: 600px !important;
            background-color: #ffffff !important;
            box-shadow: 0 0 10px rgba(0,0,0,0.1) !important;
            border-radius: 8px !important;
          }
          #journal-form .section-body {
            padding: 10px !important;
          }
          .mobile-navigation,
          #header,
          #footer,
          .leaderboardAd,
          .news-block,
          .mobile-notification-bar,
          nav#ddmenu,
          .online-stats,
          .footnote,
          .footerAds,
          .floatleft,
          .submenu-trigger,
          .banner-svg,
          .leaderboardAd,
          .newsBlock,
          .footerAds__column,
          .message-bar-desktop,
          .notification-container,
          .dropdown,
          .dropzone { 
            display: none !important; 
          }
        \`;
        document.head.appendChild(style);

        var headers = document.querySelectorAll('.section-header h2');
        headers.forEach(function(header) {
          if (header.textContent.trim() === 'Previous Journals') {
            var section = header.closest('section');
            if (section) {
              section.style.display = 'none';
            }
          }
        });
      })();
    ''';
}

String buildJournalWrapSelectionScript(String tag) {
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
