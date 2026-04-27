//edit_submission_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:shared_preferences/shared_preferences.dart';

class EditSubmissionScreen extends StatefulWidget {
  final String initialUrl;

  const EditSubmissionScreen({
    Key? key,
    required this.initialUrl,
  }) : super(key: key);

  @override
  State<EditSubmissionScreen> createState() => _EditSubmissionScreenState();
}

class _EditSubmissionScreenState extends State<EditSubmissionScreen> {
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    iOptions: IOSOptions(
      accountName: 'flutter_secure_storage_service',
      accessibility: KeychainAccessibility.first_unlock,
    ),
  );

  InAppWebViewController? _webViewController;
  final GlobalKey webViewKey = GlobalKey();

  bool get _isUpdateSubmissionScreen =>
      widget.initialUrl.contains('changesubmission');

  Future<String> _getSfwCookieValue() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getBool('sfwEnabled') ?? true) ? '1' : '0';
  }

  Future<void> _setCookies() async {
    final cookieManager = CookieManager.instance();
    final cookieKeys = ['a', 'b', 'cc', 'cf_clearance', 'folder', 'nodesc', 'sz', 'sfw'];

    for (final key in cookieKeys) {
      String value;
      if (key == 'sfw') {
        value = await _getSfwCookieValue();
      } else {
        value = await _secureStorage.read(key: 'fa_cookie_$key') ?? '';
      }

      if (value.isNotEmpty) {
        await cookieManager.setCookie(
          url: WebUri('https://www.furaffinity.net'),
          name: key,
          value: value,
          domain: '.furaffinity.net',
          path: '/',
          isSecure: true,
          isHttpOnly: true,
        );
      }
    }
  }

  Future<void> _injectCustomCssAndJs() async {
    if (_webViewController == null) return;

    await _webViewController!.evaluateJavascript(source: '''
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
''');

    if (_isUpdateSubmissionScreen) {
      await _webViewController!.evaluateJavascript(source: '''
(function() {
  try {
    var imageCell = document.querySelector('.table-cell.valigntop.p20r');
    var fileCell  = document.querySelector('.table-cell.valigntop.alignleft');
    if (imageCell && fileCell && imageCell.parentNode) {
      imageCell.parentNode.appendChild(fileCell);
    }
  } catch(e){}
})();
''');
    }
  }

  Future<void> _wrapSelection(String tag) async {
    if (_webViewController == null) return;

    await _webViewController!.evaluateJavascript(source: '''
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
''');
  }

  ContextMenu _buildContextMenu() {
    return ContextMenu(
      menuItems: [
        ContextMenuItem(id: 1, title: 'Bold', action: () => _wrapSelection('b')),
        ContextMenuItem(id: 2, title: 'Italic', action: () => _wrapSelection('i')),
        ContextMenuItem(id: 3, title: 'Underline', action: () => _wrapSelection('u')),
        ContextMenuItem(id: 4, title: 'Align Left', action: () => _wrapSelection('left')),
        ContextMenuItem(id: 5, title: 'Align Center', action: () => _wrapSelection('center')),
        ContextMenuItem(id: 6, title: 'Align Right', action: () => _wrapSelection('right')),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = InAppWebViewSettings(
      javaScriptEnabled: true,
      useShouldOverrideUrlLoading: true,
      verticalScrollBarEnabled: true,
      horizontalScrollBarEnabled: false,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Submission'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: InAppWebView(
          key: webViewKey,
          initialUrlRequest: URLRequest(url: WebUri(widget.initialUrl)),
          initialSettings: settings,
          contextMenu: _buildContextMenu(),
          onWebViewCreated: (controller) async {
            _webViewController = controller;
            await _setCookies();
          },
          onLoadStart: (controller, uri) async {
            await _injectCustomCssAndJs();
          },
          onLoadStop: (controller, uri) async {
            await _injectCustomCssAndJs();
            if (uri != null &&
                uri.toString().startsWith('https://www.furaffinity.net/view/')) {
              await Future.delayed(const Duration(milliseconds: 50));
              if (mounted) Navigator.pop(context, true);
            }
          },
        ),
      ),
    );
  }
}
