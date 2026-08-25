import 'package:fanotifier/shared/fa/fa_bbcode_webview_scripts.dart';

String buildEditSubmissionBaseScript() {
  return '''
(function() {
  if (document.getElementById('fa-edit-submission-style')) return;
  if (!document.querySelector('#submission-edit, #form-submission-change-info, form[name="uploadform"]')) return;

  var styleParent = document.head || document.documentElement;
  if (!styleParent) return;

  var style = document.createElement('style');
  style.id = 'fa-edit-submission-style';
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
    .newsBlock,
    #columnpage > .sidebar,
    .sidebarAds,
    .rectangleAd,
    #controlpanelnav { display:none!important; }

    .return-links, .return-links * { display:none!important; }

    html, body, #main-window, .content, #site-content, #submission-edit {
      background:#000!important;
      color:#fff!important;
      margin:0!important;
      padding:0!important;
    }

    #columnpage { display:block!important; }
    #columnpage > .content {
      box-sizing:border-box!important;
      float:none!important;
      max-width:none!important;
      width:100%!important;
    }

    a { color:#1e90ff!important; }

    .table { display:flex!important; flex-direction:column!important; }
    .table-cell { display:block!important; width:auto!important; margin-bottom:16px!important; }
  `;
  styleParent.appendChild(style);
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
