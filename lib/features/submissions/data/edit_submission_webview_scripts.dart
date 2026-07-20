import 'package:fanotifier/shared/fa/fa_bbcode_webview_scripts.dart';

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
  return buildFaBbcodeWrapSelectionScript(tag);
}
