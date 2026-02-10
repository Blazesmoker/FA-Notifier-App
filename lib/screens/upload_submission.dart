// lib/screens/upload_submission_screen.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/tags_and_codes_webview_widget.dart';
import 'openpost.dart';
import 'submission_template_store.dart';
import 'submission_templates_screen.dart';

class UploadSubmissionScreen extends StatefulWidget {
  const UploadSubmissionScreen({Key? key}) : super(key: key);

  @override
  _UploadSubmissionScreenState createState() => _UploadSubmissionScreenState();
}

class _UploadSubmissionScreenState extends State<UploadSubmissionScreen> with TickerProviderStateMixin {
  static const Color _accent = Color(0xFFE09321);

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    iOptions: IOSOptions(
      accountName: 'flutter_secure_storage_service',
      accessibility: KeychainAccessibility.first_unlock,
    ),
  );

  final SubmissionTemplateStore _templateStore = SubmissionTemplateStore();

  final String initialUrl = 'https://www.furaffinity.net/submit/';
  final String finalizeUrl = 'https://www.furaffinity.net/submit/finalize/';
  InAppWebViewController? _webViewController;
  final GlobalKey webViewKey = GlobalKey();

  bool _isWaitingToOpenSubmission = false;
  int? _submissionId;
  int _countdown = 6;
  Timer? _timer;
  bool _isProcessingUploadSuccess = false;
  bool _isFinalizeReady = false;

  bool _toolsMenuOpen = false;
  late final AnimationController _toolsMenuController;
  late final Animation<double> _toolsMenuSize;
  late final Animation<double> _toolsMenuFade;
  late final Animation<Offset> _toolsMenuSlide;


  ValueNotifier<String>? _uploadedFileUri;
  List<int>? _uploadedFileBytes;
  String? _uploadedFileName;


  Future<JsPromptResponse?> _handleFileChooser(
      InAppWebViewController controller,
      JsPromptRequest jsPromptRequest,
      ) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'gif'],
        allowMultiple: false,
        withData: true,
      );

      if (result == null || result.files.isEmpty) {
        return JsPromptResponse(
          message: '',
          handledByClient: true,
        );
      }

      final file = result.files.first;
      _uploadedFileName = file.name;
      _uploadedFileBytes = file.bytes?.toList();

      if (_uploadedFileBytes == null && file.path != null) {
        final fileFromPath = File(file.path!);
        _uploadedFileBytes = await fileFromPath.readAsBytes();
      }

      if (_uploadedFileBytes == null) {
        debugPrint('Failed to read file bytes');
        return JsPromptResponse(
          message: '',
          handledByClient: true,
        );
      }

      final base64Data = base64Encode(_uploadedFileBytes!);

      await controller.evaluateJavascript(source: '''
      (function() {
        try {
          var base64 = "$base64Data";
          var binary = atob(base64);
          var array = new Uint8Array(binary.length);
          for (var i = 0; i < binary.length; i++) {
            array[i] = binary.charCodeAt(i);
          }
          
          var blob = new Blob([array], { type: 'image/${file.extension ?? 'png'}' });
          var file = new File([blob], "$_uploadedFileName", { 
            type: 'image/${file.extension ?? 'png'}',
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
          
          return true;
        } catch(e) {
          console.error('Error setting file:', e);
          return false;
        }
      })();
    ''');

      debugPrint('File loaded successfully: $_uploadedFileName');
      return JsPromptResponse(
        message: 'success',
        handledByClient: true,
      );

    } catch (e) {
      debugPrint('Error in file chooser: $e');
      return JsPromptResponse(
        message: '',
        handledByClient: true,
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _requestPermissions();

    _toolsMenuController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
      reverseDuration: const Duration(milliseconds: 200),
    );

    final curveIn = CurvedAnimation(parent: _toolsMenuController, curve: Curves.easeInOut);
    _toolsMenuSize = curveIn;
    _toolsMenuFade = curveIn;
    _toolsMenuSlide = Tween<Offset>(
      begin: const Offset(0, -0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _toolsMenuController, curve: Curves.easeOutCubic));

  }

  bool _isFinalizeUrl(String url) {
    final u = Uri.tryParse(url);
    if (u == null) return false;
    return u.path.startsWith('/submit/finalize');
  }

  Future<void> _requestPermissions() async {
    if (Platform.isAndroid) {
      await [
        Permission.storage,
        Permission.photos,
      ].request();
    }
  }

  Future<String> _getSfwCookieValue() async {
    final prefs = await SharedPreferences.getInstance();
    final sfwEnabled = prefs.getBool('sfwEnabled') ?? true;
    return sfwEnabled ? '1' : '0';
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

  void _setFinalizeReady(bool value) {
    if (!mounted) return;
    if (_isFinalizeReady == value) return;
    setState(() => _isFinalizeReady = value);
    if (!value) {
      _closeToolsMenu();
    }
  }

  Future<void> _openToolsMenu() async {
    if (!mounted) return;
    if (_toolsMenuOpen && _toolsMenuController.status == AnimationStatus.forward) return;
    if (_toolsMenuController.isAnimating) return;

    setState(() => _toolsMenuOpen = true);
    await _toolsMenuController.forward(from: _toolsMenuController.value.clamp(0.0, 1.0));
  }

  Future<void> _closeToolsMenu() async {
    if (!mounted) return;
    if (!_toolsMenuOpen && _toolsMenuController.value == 0) return;
    if (_toolsMenuController.isAnimating) return;

    await _toolsMenuController.reverse(from: _toolsMenuController.value.clamp(0.0, 1.0));
    if (!mounted) return;
    setState(() => _toolsMenuOpen = false);
  }

  void _toggleToolsMenu() {
    if (!mounted) return;
    if (_toolsMenuOpen || _toolsMenuController.value > 0) {
      _closeToolsMenu();
    } else {
      _openToolsMenu();
    }
  }

  Future<void> _handleLoadUrl(String? url) async {
    if (url == null) return;

    debugPrint("Page loading: $url");
    _setFinalizeReady(_isFinalizeUrl(url));

    // Prevent double-triggering
    if (url.contains('upload-successful') && !_isProcessingUploadSuccess) {
      _isProcessingUploadSuccess = true;

      final submissionId = _extractSubmissionId(url);

      if (submissionId != null) {


        if (!mounted) {
          _isProcessingUploadSuccess = false;
          return;
        }

        setState(() {
          _isWaitingToOpenSubmission = true;
          _submissionId = submissionId;
          _countdown = 6;
        });

        _startCountdown();


        await Future.delayed(const Duration(seconds: 2));
        _isProcessingUploadSuccess = false;
      } else {
        _isProcessingUploadSuccess = false;
      }
    } else if (url.startsWith(initialUrl)) {
      await _injectInitialCss();
    } else if (_isFinalizeUrl(url)) {
      await _injectFinalizeCss();
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

  int? _extractSubmissionId(String url) {
    try {
      final uri = Uri.parse(url);
      if (uri.pathSegments.length >= 2 && uri.pathSegments[0] == 'view') {
        final idStr = uri.pathSegments[1];
        return int.tryParse(idStr);
      }
    } catch (e) {
      debugPrint('Error parsing submission ID: $e');
    }
    return null;
  }

  void _startCountdown() {
    _timer = Timer.periodic(const Duration(seconds: 1), (Timer timer) {
      if (_countdown == 1) {
        timer.cancel();

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => OpenPost(
              imageUrl: '',
              uniqueNumber: _submissionId.toString(),
            ),
          ),
        ).then((_) {
          if (!mounted) return;
          Navigator.pop(context);
        });
      } else {
        if (!mounted) return;
        setState(() {
          _countdown--;
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _toolsMenuController.dispose();
    super.dispose();
  }

  Future<void> _injectInitialCss() async {
    if (_webViewController == null) return;

    final isIOS = Platform.isIOS;

    if (isIOS) {
      // On iOS with ad blocking, we can inject CSS more simply
      // and add a fallback to force Turnstile re-render if needed
      await _webViewController!.evaluateJavascript(source: '''
        (function() {
          // Inject CSS to hide unwanted elements
          var style = document.createElement('style');
          style.type = 'text/css';
          style.innerHTML = \`
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
            .some-other-class {
              display: none !important;
            }

            .content {
              margin: 0 !important;
              padding: 0 !important;
            }
            
            /* Ensure captcha containers stay visible */
            .section-options,
            .captcha-container,
            #fa-captcha-main,
            .cf-turnstile {
              display: block !important;
              visibility: visible !important;
            }
          \`;
          document.head.appendChild(style);
          
          // Fallback: Force Turnstile re-render after page load
          function ensureTurnstile() {
            setTimeout(function() {
              if (window.turnstile && !document.querySelector('iframe[src*="challenges.cloudflare.com"]')) {
                console.log('Forcing Turnstile re-render on iOS');
                var turnstileElements = document.querySelectorAll('.cf-turnstile');
                turnstileElements.forEach(function(el) {
                  el.innerHTML = '';
                  try {
                    window.turnstile.render(el);
                  } catch(e) {
                    console.log('Turnstile re-render failed:', e);
                  }
                });
              }
            }, 1000);
          }
          
          if (document.readyState === 'loading') {
            document.addEventListener('DOMContentLoaded', ensureTurnstile);
          } else {
            ensureTurnstile();
          }
        })();
      ''');
    } else {
      await _webViewController!.evaluateJavascript(source: '''
        (function() {
          var style = document.createElement('style');
          style.type = 'text/css';
          style.innerHTML = \`
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
            .dropzone,
            .some-other-class {
              display: none !important;
            }

            .content {
              margin: 0 !important;
              padding: 0 !important;
            }
          \`;
          document.head.appendChild(style);
        })();
      ''');
    }
  }

  Future<void> _injectFinalizeCss() async {
    if (_webViewController == null) return;

    final isIOS = Platform.isIOS;

    if (isIOS) {
      // On iOS with ad blocking, inject CSS and add Turnstile re-render fallback
      await _webViewController!.evaluateJavascript(source: '''
        (function() {
          // Inject CSS to hide unwanted elements
          var style = document.createElement('style');
          style.type = 'text/css';
          style.innerHTML = \`
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
            .newsBlock,
            .footerAds__column,
            .message-bar-desktop,
            .notification-container,
            .dropdown {
              display: none !important;
            }

            .content {
              margin: 0 !important;
              padding: 0 !important;
            }
            
            /* Ensure captcha containers stay visible */
            .section-options,
            .captcha-container,
            #fa-captcha-main,
            .cf-turnstile {
              display: block !important;
              visibility: visible !important;
            }
          \`;
          document.head.appendChild(style);
          
          // Fallback: Force Turnstile re-render after page load
          function ensureTurnstile() {
            setTimeout(function() {
              if (window.turnstile && !document.querySelector('iframe[src*="challenges.cloudflare.com"]')) {
                console.log('Forcing Turnstile re-render on iOS');
                var turnstileElements = document.querySelectorAll('.cf-turnstile');
                turnstileElements.forEach(function(el) {
                  el.innerHTML = '';
                  try {
                    window.turnstile.render(el);
                  } catch(e) {
                    console.log('Turnstile re-render failed:', e);
                  }
                });
              }
            }, 1000);
          }
          
          if (document.readyState === 'loading') {
            document.addEventListener('DOMContentLoaded', ensureTurnstile);
          } else {
            ensureTurnstile();
          }
        })();
      ''');
    } else {
      await _webViewController!.evaluateJavascript(source: '''
        (function() {
          var style = document.createElement('style');
          style.type = 'text/css';
          style.innerHTML = \`
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
            .newsBlock,
            .footerAds__column,
            .message-bar-desktop,
            .notification-container,
            .dropdown,
            .dropzone {
              display: none !important;
            }

            .content {
              margin: 0 !important;
              padding: 0 !important;
            }
          \`;
          document.head.appendChild(style);
        })();
      ''');
    }
  }

  void _showSnack(String message, {required bool isError}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(color: Colors.white)),
        backgroundColor: isError ? Colors.red.shade800 : Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Map<String, dynamic>? _decodeJsMap(Object? result) {
    if (result == null) return null;

    if (result is Map) {
      try {
        return result.cast<String, dynamic>();
      } catch (_) {
        return null;
      }
    }

    String raw = result is String ? result : result.toString();
    raw = raw.trim();
    if (raw.isEmpty) return null;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is String) raw = decoded.trim();
    } catch (_) {}

    if (raw.startsWith('B64:')) {
      final b64 = raw.substring(4);
      try {
        final jsonStr = utf8.decode(base64Decode(b64));
        final decoded = jsonDecode(jsonStr);
        if (decoded is Map<String, dynamic>) return decoded;
      } catch (_) {
        return null;
      }
    }

    final stripped = raw.replaceAll(RegExp(r'^\s*"+|"+\s*$'), '').trim();
    if (stripped.isEmpty) return null;

    if (stripped.startsWith('B64:')) {
      final b64 = stripped.substring(4);
      try {
        final jsonStr = utf8.decode(base64Decode(b64));
        final decoded = jsonDecode(jsonStr);
        if (decoded is Map<String, dynamic>) return decoded;
      } catch (_) {
        return null;
      }
    }

    try {
      final decoded = jsonDecode(stripped);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is String) {
        final decoded2 = jsonDecode(decoded);
        if (decoded2 is Map<String, dynamic>) return decoded2;
      }
    } catch (_) {}

    return null;
  }

  Future<void> _clearFinalizeFormToDefaults() async {
    if (_webViewController == null) return;
    try {
      final res = await _webViewController!.evaluateJavascript(source: '''
        (function() {
          function __b64(o) { return 'B64:' + btoa(unescape(encodeURIComponent(JSON.stringify(o)))); }

          function __escapeHTML(text) {
            var htmlEscapes = {
              '&': '&amp;',
              '<': '&lt;',
              '>': '&gt;',
              '"': '&quot;',
              "'": '&#x27;',
              '/': '&#x2F;'
            };
            return String(text).replace(/[&<>"'\\/]/g, function(match) { return htmlEscapes[match]; });
          }

          function __setHidden(el, hidden) {
            if (!el) return;
            try {
              if (hidden) el.classList.add('hidden');
              else el.classList.remove('hidden');
            } catch (_) {}
          }

          function __updateTitlePreview(value) {
            var defaultTitle = document.querySelector('.default-preview-title');
            var userTitle = document.querySelector('.user-preview-title');
            if (!defaultTitle || !userTitle) return;
            var v = String(value || '');
            if (v !== '') {
              __setHidden(defaultTitle, true);
              userTitle.textContent = v.replace(/\\n/g, ' ');
              __setHidden(userTitle, false);
            } else {
              __setHidden(defaultTitle, false);
              __setHidden(userTitle, true);
            }
          }

          function __updateDescPreview(value) {
            var defaultDesc = document.querySelector('.default-preview-text');
            var userDesc = document.querySelector('.user-preview-text');
            if (!defaultDesc || !userDesc) return;
            var v = String(value || '');
            if (v !== '') {
              __setHidden(defaultDesc, true);
              userDesc.innerHTML = __escapeHTML(v).replace(/\\n/g, '<br />');
              __setHidden(userDesc, false);
            } else {
              __setHidden(defaultDesc, false);
              __setHidden(userDesc, true);
              userDesc.innerHTML = '';
            }
          }

          function __syncPreviewToForm() {
            var titleEl = document.querySelector('input#title') || document.querySelector('input[name="title"]');
            var msgEl = document.querySelector('textarea#message');
            var titleVal = titleEl ? String(titleEl.value || '') : '';
            var msgVal = msgEl ? String(msgEl.value || '') : '';
            __updateTitlePreview(titleVal);
            __updateDescPreview(msgVal);
            return true;
          }

          try {
            var form = document.getElementById('myform');
            if (!form) return __b64({ ok: false, error: 'Finalize form not found' });
            form.reset();
            __syncPreviewToForm();
            return __b64({ ok: true });
          } catch (e) {
            return __b64({ ok: false, error: String(e) });
          }
        })();
      ''');

      final map = _decodeJsMap(res);
      if (map == null) {
        _showSnack('Failed to clear form.', isError: true);
        return;
      }
      if (map['ok'] == true) {
        _showSnack('Form cleared.', isError: false);
      } else {
        _showSnack('Failed to clear form.', isError: true);
      }
    } catch (_) {
      _showSnack('Failed to clear form.', isError: true);
    }
  }

  Future<SubmissionTemplateFields?> _readFinalizeFields() async {
    if (_webViewController == null) return null;
    try {
      final res = await _webViewController!.evaluateJavascript(source: '''
        (function() {
          function __b64(o) { return 'B64:' + btoa(unescape(encodeURIComponent(JSON.stringify(o)))); }
          try {
            var form = document.getElementById('myform');
            if (!form) {
              return __b64({ ok: false, error: 'Finalize form not found. Make sure you are on the finalize page.' });
            }

            function selectObj(sel) {
              if (!sel) return null;
              var idx = sel.selectedIndex;
              var label = '';
              if (idx >= 0 && sel.options && sel.options[idx]) label = (sel.options[idx].text || '').trim();
              return { value: String(sel.value || ''), label: label || String(sel.value || '') };
            }

            var catSel = document.querySelector('select[name="cat"]');
            var atypeSel = document.querySelector('select[name="atype"]');
            var speciesSel = document.querySelector('select[name="species"]');

            var titleEl = document.querySelector('input#title');
            var msgEl = document.querySelector('textarea#message');
            var kwEl = document.getElementById('keywords');

            var folderNameEl = document.querySelector('input[name="create_folder_name"]');

            var selectedFolders = [];
            try {
              var checked = document.querySelectorAll('input[name="folder_ids[]"]:checked');
              for (var i = 0; i < checked.length; i++) {
                var cb = checked[i];
                var idAttr = cb.getAttribute('id') || '';
                var labelText = '';
                if (idAttr) {
                  var lbl = document.querySelector('label[for="' + idAttr + '"]');
                  if (lbl) labelText = (lbl.textContent || '').trim();
                }
                if (!labelText) {
                  var wrap = cb.closest('.folder_name');
                  if (wrap) {
                    var lbl2 = wrap.querySelector('label');
                    if (lbl2) labelText = (lbl2.textContent || '').trim();
                  }
                }
                selectedFolders.push({
                  value: String(cb.value || ''),
                  label: labelText || String(cb.value || '')
                });
              }
            } catch (_) {}

            var rEl = document.querySelector('#myform input[name="rating"]:checked');
            var ratingObj = null;
            if (rEl) {
              var lblr = '';
              var labelEl = rEl.closest('label');
              if (labelEl) lblr = (labelEl.textContent || '').trim();
              if (!lblr && rEl.id) {
                var forLbl = document.querySelector('label[for="' + rEl.id + '"]');
                if (forLbl) lblr = (forLbl.textContent || '').trim();
              }
              ratingObj = { value: String(rEl.value || ''), label: lblr || String(rEl.value || '') };
            }

            var out = {
              category: selectObj(catSel),
              theme: selectObj(atypeSel),
              species: selectObj(speciesSel),
              rating: ratingObj,
              title: titleEl ? String(titleEl.value || '') : null,
              description: msgEl ? String(msgEl.value || '') : null,
              keywords: kwEl ? String(kwEl.value || '') : null,
              folderName: folderNameEl ? String(folderNameEl.value || '') : null,
              folders: selectedFolders
            };

            return __b64({ ok: true, fields: out });
          } catch (e) {
            return __b64({ ok: false, error: String(e) });
          }
        })();
      ''');

      final map = _decodeJsMap(res);
      if (map == null) {
        debugPrint('Failed to decode JavaScript result');
        return null;
      }

      if (map['ok'] != true) {
        final error = map['error'] ?? 'Unknown error';
        debugPrint('JavaScript error reading form: $error');
        return null;
      }

      final fields = map['fields'];
      if (fields is! Map<String, dynamic>) {
        debugPrint('Fields is not a Map: $fields');
        return null;
      }

      final normalized = <String, dynamic>{
        'category': fields['category'],
        'theme': fields['theme'],
        'species': fields['species'],
        'rating': fields['rating'],
        'title': fields['title'],
        'description': fields['description'],
        'keywords': fields['keywords'],
        'folderName': fields['folderName'],
        'folders': fields['folders'],
      };

      return SubmissionTemplateFields.fromJson(normalized);
    } catch (e) {
      debugPrint('Exception in _readFinalizeFields: $e');
      return null;
    }
  }

  Future<String?> _promptTemplateName() async {
    final controller = TextEditingController();

    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.black,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: _accent, width: 0.5),
          borderRadius: BorderRadius.circular(22),
        ),
        title: const Text('Save Template', style: TextStyle(color: _accent)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Template name',
            hintStyle: const TextStyle(color: Colors.white38),
            enabledBorder: OutlineInputBorder(
              borderSide: const BorderSide(color: _accent, width: 0.8),
              borderRadius: BorderRadius.circular(14),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: const BorderSide(color: _accent, width: 1.2),
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
        actionsAlignment: MainAxisAlignment.spaceBetween,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Save', style: TextStyle(color: _accent)),
          ),
        ],
      ),
    );

    final trimmed = (name ?? '').trim();
    if (trimmed.isEmpty) return null;
    return trimmed;
  }

  Future<void> _saveTemplateFlow() async {
    debugPrint('_saveTemplateFlow called');

    if (!_isFinalizeReady) {
      _showSnack('Please navigate to the finalize page first.', isError: true);
      return;
    }

    try {
      // Wait a bit to ensure the page is fully loaded
      await Future.delayed(const Duration(milliseconds: 300));

      final fields = await _readFinalizeFields();
      if (fields == null) {
        _showSnack('Failed to read finalize form. Make sure you are on the finalize page.', isError: true);
        return;
      }

      debugPrint('Successfully read fields: ${fields.toJson()}');

      final name = await _promptTemplateName();

      if (name == null) {
        return;
      }

      final trimmed = name.trim();
      if (trimmed.isEmpty) {
        _showSnack('Template name cannot be empty.', isError: true);
        return;
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      final template = SubmissionTemplate(
        id: now.toString(),
        name: trimmed,
        updatedAtMs: now,
        fields: fields,
      );

      debugPrint('Saving template: ${template.name} (id: ${template.id})');
      await _templateStore.upsertTemplate(template);
      debugPrint('Template saved successfully');

      if (!mounted) return;
      _showSnack('Template saved.', isError: false);
    } catch (e) {
      debugPrint('Error saving template: $e');
      if (!mounted) return;
      _showSnack('Failed to save template: ${e.toString()}', isError: true);
    }
  }


  Future<void> _openTemplatesScreen() async {
    final selected = await Navigator.push<SubmissionTemplate?>(
      context,
      MaterialPageRoute(
        builder: (context) => SubmissionTemplatesScreen(store: _templateStore),
      ),
    );

    if (selected == null) return;
    await _applyTemplate(selected);
  }

  Future<void> _applyTemplate(SubmissionTemplate template) async {
    try {
      final fieldsJson = jsonEncode(template.fields.toJson());

      final res = await _webViewController!.evaluateJavascript(source: '''
        (function() {
          function __b64(o) { return 'B64:' + btoa(unescape(encodeURIComponent(JSON.stringify(o)))); }

          function __escapeHTML(text) {
            var htmlEscapes = {
              '&': '&amp;',
              '<': '&lt;',
              '>': '&gt;',
              '"': '&quot;',
              "'": '&#x27;',
              '/': '&#x2F;'
            };
            return String(text).replace(/[&<>"'\\/]/g, function(match) { return htmlEscapes[match]; });
          }

          function __setHidden(el, hidden) {
            if (!el) return;
            try {
              if (hidden) el.classList.add('hidden');
              else el.classList.remove('hidden');
            } catch (_) {}
          }

          function __updateTitlePreview(value) {
            var defaultTitle = document.querySelector('.default-preview-title');
            var userTitle = document.querySelector('.user-preview-title');
            if (!defaultTitle || !userTitle) return;
            var v = String(value || '');
            if (v !== '') {
              __setHidden(defaultTitle, true);
              userTitle.textContent = v.replace(/\\n/g, ' ');
              __setHidden(userTitle, false);
            } else {
              __setHidden(defaultTitle, false);
              __setHidden(userTitle, true);
            }
          }

          function __updateDescPreview(value) {
            var defaultDesc = document.querySelector('.default-preview-text');
            var userDesc = document.querySelector('.user-preview-text');
            if (!defaultDesc || !userDesc) return;
            var v = String(value || '');
            if (v !== '') {
              __setHidden(defaultDesc, true);
              userDesc.innerHTML = __escapeHTML(v).replace(/\\n/g, '<br />');
              __setHidden(userDesc, false);
            } else {
              __setHidden(defaultDesc, false);
              __setHidden(userDesc, true);
              userDesc.innerHTML = '';
            }
          }

          function __syncPreviewToForm() {
            var titleEl = document.querySelector('input#title') || document.querySelector('input[name="title"]');
            var msgEl = document.querySelector('textarea#message');
            var titleVal = titleEl ? String(titleEl.value || '') : '';
            var msgVal = msgEl ? String(msgEl.value || '') : '';
            __updateTitlePreview(titleVal);
            __updateDescPreview(msgVal);
            return true;
          }

          try {
            var fields = $fieldsJson;
            var failed = [];

            function tryFind(selector) {
              try { return document.querySelector(selector); } catch (_) { return null; }
            }

            function setText(selector, value, label) {
              if (value === null || value === undefined) return;
              var el = tryFind(selector);
              if (!el) { failed.push(label); return; }
              el.value = String(value);
              el.dispatchEvent(new Event('input', { bubbles: true }));
              el.dispatchEvent(new Event('change', { bubbles: true }));
            }

            function setSelectByName(name, obj, label) {
              if (!obj || obj.value === null || obj.value === undefined) return;
              var el = tryFind('select[name="' + name + '"]');
              if (!el) { failed.push(label); return; }
              var v = String(obj.value);
              var ok = false;
              for (var i = 0; i < el.options.length; i++) {
                if (String(el.options[i].value) === v) { ok = true; break; }
              }
              if (!ok) { failed.push(label); return; }
              el.value = v;
              el.dispatchEvent(new Event('change', { bubbles: true }));
            }

            function setRating(obj, label) {
              if (!obj || obj.value === null || obj.value === undefined) return;
              var v = String(obj.value);
              var el = tryFind('#myform input[name="rating"][value="' + v + '"]');
              if (!el) { failed.push(label); return; }
              el.checked = true;
              el.dispatchEvent(new Event('change', { bubbles: true }));
            }

            function setFolders(list, label) {
              if (!Array.isArray(list)) return;
              try {
                var all = document.querySelectorAll('input[name="folder_ids[]"]');
                for (var i = 0; i < all.length; i++) {
                  all[i].checked = false;
                  all[i].dispatchEvent(new Event('change', { bubbles: true }));
                }

                for (var j = 0; j < list.length; j++) {
                  var obj = list[j];
                  if (!obj || obj.value === null || obj.value === undefined) continue;
                  var v = String(obj.value);
                  var cb = tryFind('input[name="folder_ids[]"][value="' + v + '"]');
                  if (!cb) { failed.push(label); continue; }
                  cb.checked = true;
                  cb.dispatchEvent(new Event('change', { bubbles: true }));
                }
              } catch (_) {
                failed.push(label);
              }
            }

            var form = document.getElementById('myform');
            if (!form) {
              return __b64({ ok: false, failed: ['Finalize form'] });
            }

            setSelectByName('cat', fields.category, 'Category');
            setSelectByName('atype', fields.theme, 'Theme');
            setSelectByName('species', fields.species, 'Species');
            setRating(fields.rating, 'Maturity Rating');

            setText('input#title', fields.title, 'Title');
            setText('textarea#message', fields.description, 'Description');
            setText('#keywords', fields.keywords, 'Keywords');

            setText('input[name="create_folder_name"]', fields.folderName, 'Folder Name');
            setFolders(fields.folders, 'Folder Name');

            __syncPreviewToForm();
            return __b64({ ok: true, failed: failed });
          } catch (e) {
            return __b64({ ok: false, failed: ['Unknown error'] });
          }
        })();
      ''');

      final map = _decodeJsMap(res);
      if (map == null) {
        _showSnack('Failed to apply template.', isError: true);
        return;
      }

      final ok = map['ok'] == true;
      final failed = (map['failed'] is List) ? (map['failed'] as List).whereType<String>().toList() : <String>[];

      if (!ok) {
        _showSnack('Failed to apply template.', isError: true);
        return;
      }

      if (failed.isNotEmpty) {
        _showSnack('Could not apply: ${failed.join(', ')}', isError: true);
      } else {
        _showSnack('Template applied.', isError: false);
      }
    } catch (_) {
      _showSnack('Failed to apply template.', isError: true);
    }
  }

  double _measureTextWidth(BuildContext context, String text, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      maxLines: 1,
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    return painter.width;
  }

  Widget _toolsMenu(BuildContext context) {
    const labels = <String>['Templates', 'Save template', 'Clear'];
    const textStyle = TextStyle(color: Colors.white, fontSize: 14);
    const rowHPad = 12.0;
    const gap = 12.0;
    const iconSize = 24.0;
    const extraTextPad = 16.0;

    double maxTextWidth = 0;
    for (final t in labels) {
      final w = _measureTextWidth(context, t, textStyle);
      if (w > maxTextWidth) maxTextWidth = w;
    }

    final desiredMenuWidth = maxTextWidth + extraTextPad + (rowHPad * 2) + gap + iconSize;

    final screenW = MediaQuery.of(context).size.width;
    final maxAvailable = max(0.0, screenW - 16);
    final menuWidth = min(desiredMenuWidth, maxAvailable);

    final menu = Material(
      color: Colors.transparent,
      child: Container(
        width: menuWidth,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _accent, width: 0.6),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _toolsItem(
              icon: Icons.list_alt_outlined,
              text: 'Templates',
              onTap: () {
                _closeToolsMenu();
                _openTemplatesScreen();
              },
            ),
            _divider(),
            _toolsItem(
              icon: Icons.save_outlined,
              text: 'Save template',
              onTap: () {
                _closeToolsMenu();
                _saveTemplateFlow();
              },
            ),
            _divider(),
            _toolsItem(
              icon: Icons.cleaning_services_outlined,
              text: 'Clear',
              onTap: () {
                _closeToolsMenu();
                _clearFinalizeFormToDefaults();
              },
            ),
          ],
        ),
      ),
    );

    return Align(
      alignment: Alignment.topRight,
      child: FadeTransition(
        opacity: _toolsMenuFade,
        child: SlideTransition(
          position: _toolsMenuSlide,
          child: SizeTransition(
            sizeFactor: _toolsMenuSize,
            axis: Axis.vertical,
            axisAlignment: -1.0,
            child: menu,
          ),
        ),
      ),
    );
  }

  Widget _divider() => Container(height: 1, color: _accent.withOpacity(0.18));

  Widget _toolsItem({
    required IconData icon,
    required String text,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: 46,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    text,
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Icon(icon, color: _accent, size: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWebView() {
    final settings = InAppWebViewSettings(
      javaScriptEnabled: true,
      useShouldOverrideUrlLoading: true,
      verticalScrollBarEnabled: true,
      horizontalScrollBarEnabled: false,
      allowFileAccess: true,
      allowContentAccess: true,
      allowFileAccessFromFileURLs: true,
      allowUniversalAccessFromFileURLs: true,
    );

    return InAppWebView(
      key: webViewKey,
      initialUrlRequest: URLRequest(url: WebUri(initialUrl)),
      initialSettings: settings,
      contextMenu: _buildContextMenu(),
      onWebViewCreated: (controller) async {
        _webViewController = controller;
        await _setCookies();

        controller.addJavaScriptHandler(
          handlerName: 'selectFile',
          callback: (args) async {
            await _selectAndInjectFile();
          },
        );
      },

      onLoadStart: (controller, uri) async {
        _webViewController = controller;
        await _handleLoadUrl(uri?.toString());
      },
      onLoadStop: (controller, uri) async {
        await _handleLoadUrl(uri?.toString());

        await _injectFilePickerHandler();
      },
      shouldOverrideUrlLoading: (controller, navigationAction) async {
        final uri = navigationAction.request.url;

        if (Platform.isIOS && uri != null) {
          final blockedHosts = {
            'www15.smartadserver.com',
            'securepubads.g.doubleclick.net',
            'cdn.playwire.com',
            'z.moatads.com',
            'pagead2.googlesyndication.com',
            'cdn.intergient.com',
            'cdn.intergi.com',
            'config.playwire.com',
          };

          if (blockedHosts.contains(uri.host)) {
            debugPrint('Blocking ad/tracker request on iOS: ${uri.host}');
            return NavigationActionPolicy.CANCEL;
          }
        }


        return NavigationActionPolicy.ALLOW;
      },
    );
  }

  Future<void> _injectFilePickerHandler() async {
    if (_webViewController == null) return;

    await _webViewController!.evaluateJavascript(source: '''
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
      
      // Also intercept the drag-drop area clicks
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
  ''');
  }

  Future<void> _selectAndInjectFile() async {
    try {
      final source = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: Colors.black,
          shape: RoundedRectangleBorder(
            side: const BorderSide(color: _accent, width: 0.5),
            borderRadius: BorderRadius.circular(22),
          ),
          title: const Text(
            'Select source',
            style: TextStyle(color: _accent),
          ),
          content: const Text(
            'Choose between Files or Gallery',
            style: TextStyle(color: Colors.white70),
          ),
          actionsAlignment: MainAxisAlignment.spaceBetween,
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop('files'),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Text(
                    'Files',
                    style: TextStyle(color: _accent),
                  ),
                  SizedBox(width: 8),
                  Icon(Icons.insert_drive_file, color: _accent),
                ],
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop('gallery'),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Text(
                    'Gallery',
                    style: TextStyle(color: _accent),
                  ),
                  SizedBox(width: 8),
                  Icon(Icons.image, color: _accent),
                ],
              ),
            ),
          ],
        ),
      );

      if (source == null) return;

      File? selectedFile;
      String? fileName;

      if (source == 'files') {
        final result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['jpg', 'jpeg', 'png', 'gif'],
          allowMultiple: false,
          withData: true,
        );

        if (result == null || result.files.isEmpty) return;

        final file = result.files.first;
        fileName = file.name;
        _uploadedFileBytes = file.bytes?.toList();

        if (_uploadedFileBytes == null && file.path != null) {
          selectedFile = File(file.path!);
          _uploadedFileBytes = await selectedFile.readAsBytes();
        }
      } else if (source == 'gallery') {
        final ImagePicker picker = ImagePicker();
        final XFile? pickedFile = await picker.pickImage(
          source: ImageSource.gallery,
        );

        if (pickedFile == null) return;

        selectedFile = File(pickedFile.path);
        fileName = pickedFile.name;
        _uploadedFileBytes = await selectedFile.readAsBytes();
      }

      if (_uploadedFileBytes == null || fileName == null) {
        debugPrint('Failed to read file bytes');
        return;
      }

      _uploadedFileName = fileName;
      final base64Data = base64Encode(_uploadedFileBytes!);


      final extension = fileName.split('.').last.toLowerCase();

      await _webViewController!.evaluateJavascript(source: '''
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
        } catch(e) {
          console.error('Error setting file:', e);
        }
      })();
    ''');

      debugPrint('File loaded successfully: $fileName');
    } catch (e) {
      debugPrint('Error selecting file: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final menuVisible = _isFinalizeReady && (_toolsMenuOpen || _toolsMenuController.value > 0);
    return SafeArea(
      top: false,
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              _timer?.cancel();
              setState(() {
                _isWaitingToOpenSubmission = false;
              });
              Navigator.pop(context);
            },
          ),
          centerTitle: false,
          titleSpacing: 0,
          title: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: const Text(
                'Upload Submission',
                maxLines: 1,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),

          actions: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Transform.translate(
                  offset: _isFinalizeReady
                      ? const Offset(14.0, 0)
                      : Offset.zero,
                  child: InfoIconButton(
                    url: 'https://www.furaffinity.net/help/#tags-and-codes',
                    title: 'Tags & Codes',
                  ),
                ),
                if (_isFinalizeReady)
                  IconButton(
                    tooltip: 'More',
                    icon: Icon(
                      (_toolsMenuOpen || _toolsMenuController.value > 0)
                          ? Icons.close
                          : Icons.more_vert,
                      color: _accent,
                    ),
                    onPressed: _toggleToolsMenu,
                  ),
              ],
            ),
          ],

        ),


        body: Stack(
          children: [
            _buildWebView(),
            if (menuVisible)
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _closeToolsMenu,
                  child: const SizedBox.shrink(),
                ),
              ),
            if (_isFinalizeReady)
              Positioned(
                top: 8,
                right: 8,
                child: IgnorePointer(
                  ignoring: !_toolsMenuOpen && _toolsMenuController.value == 0,
                  child: _toolsMenu(context),
                ),
              ),
            if (_isWaitingToOpenSubmission)
              Positioned.fill(
                child: Container(
                  color: Colors.black,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Waiting to open your submission',
                          style: TextStyle(color: Colors.white, fontSize: 24),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          '$_countdown',
                          style: const TextStyle(color: Colors.white, fontSize: 48),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
