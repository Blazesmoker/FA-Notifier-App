String buildEditSubmissionBaseScript() {
  return '''
(function() {
  if (window.__faInjected) return;
  window.__faInjected = true;

  var style = document.createElement('style');
  style.innerHTML = `
    .mobile-navigation,
    #header,
    #footer,
    .leaderboardAd,
    .news-block,
    .footerAds,
    .message-bar-desktop,
    nav#ddmenu,
    .mobile-notification-bar,
    .notification-container,
    .online-stats,
    .banner-svg,
    .floatleft,
    .footnote,
    .dropdown,
    .submenu-trigger,
    .footerAds__column,
    .newsBlock { display:none!important; }

    .return-links, .return-links * { display:none!important; }

    html, body, #main-window, .content, #site-content {
      background:#000!important;
      color:#fff!important;
      margin:0!important;
      padding:0!important;
    }

    a { color:#1e90ff!important; }

    .table { display:flex!important; flex-direction:column!important; }
    .table-cell { display:block!important; width:auto!important; margin-bottom:16px!important; }
  `;
  document.head.appendChild(style);
})();
''';
}

String buildMoveSubmissionFileCellScript() {
  return '''
(function() {
  try {
    var imageCell = document.querySelector('.table-cell.valigntop.p20r');
    var fileCell  = document.querySelector('.table-cell.valigntop.alignleft');
    if (imageCell && fileCell && imageCell.parentNode) {
      imageCell.parentNode.appendChild(fileCell);
    }
  } catch(e){}
})();
''';
}

String buildWrapSelectionScript(String tag) {
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
