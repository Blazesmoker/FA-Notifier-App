// lib/screens/upload_submission_screen.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

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
  late final WebViewController _webViewController;

  bool _isWaitingToOpenSubmission = false;
  int? _submissionId;
  int _countdown = 6;
  Timer? _timer;

  bool _isFinalizeReady = false;

  bool _toolsMenuOpen = false;
  late final AnimationController _toolsMenuController;
  late final Animation<double> _toolsMenuSize;
  late final Animation<double> _toolsMenuFade;
  late final Animation<Offset> _toolsMenuSlide;

  @override
  void initState() {
    super.initState();

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

    _initializeWebViewController();
  }

  bool _isFinalizeUrl(String url) {
    final u = Uri.tryParse(url);
    if (u == null) return false;
    return u.path.startsWith('/submit/finalize');
  }

  Future<String> _getSfwCookieValue() async {
    final prefs = await SharedPreferences.getInstance();
    final sfwEnabled = prefs.getBool('sfwEnabled') ?? true;
    return sfwEnabled ? '1' : '0';
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

  void _initializeWebViewController() {
    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) async {
            debugPrint("Page started loading: $url");
            _setFinalizeReady(_isFinalizeUrl(url));

            if (url.contains('upload-successful')) {
              final submissionId = _extractSubmissionId(url);

              if (submissionId != null) {
                await _webViewController.loadRequest(Uri.parse(initialUrl));

                if (!mounted) return;
                setState(() {
                  _isWaitingToOpenSubmission = true;
                  _submissionId = submissionId;
                  _countdown = 6;
                });

                _startCountdown();
              }
            } else if (url.startsWith(initialUrl)) {
              await _injectInitialCss();
            } else if (_isFinalizeUrl(url)) {
              await _injectFinalizeCss();
            }
          },
          onPageFinished: (url) async {
            debugPrint("Page finished loading: $url");
            _setFinalizeReady(_isFinalizeUrl(url));

            if (url.startsWith(initialUrl)) {
              await _injectInitialCss();
            } else if (_isFinalizeUrl(url)) {
              await _injectFinalizeCss();
            }
          },
          onWebResourceError: (error) {
            debugPrint("Web resource error: $error");
          },
        ),
      )
      ..loadRequest(Uri.parse(initialUrl));

    addFileSelectionListener();
    _setCookies();
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
          setState(() {
            _isWaitingToOpenSubmission = false;
            _countdown = 6;
          });
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
    await _webViewController.runJavaScript('''
      (function() {
        var style = document.createElement('style');
        style.type = 'text/css';
        style.innerHTML = `
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
          .online-stats,
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
        `;
        document.head.appendChild(style);
      })();
    ''');
  }

  Future<void> _injectFinalizeCss() async {
    await _webViewController.runJavaScript('''
      (function() {
        var style = document.createElement('style');
        style.type = 'text/css';
        style.innerHTML = `
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
        `;
        document.head.appendChild(style);
      })();
    ''');
  }

  void addFileSelectionListener() async {
    if (Platform.isAndroid) {
      final androidController = _webViewController.platform as AndroidWebViewController;
      await androidController.setOnShowFileSelector(_androidFilePicker);
    }
  }

  Future<List<String>> _androidFilePicker(FileSelectorParams params) async {
    final source = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.black,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: _accent, width: 0.5),
          borderRadius: BorderRadius.circular(22),
        ),
        title: const Text('Select source', style: TextStyle(color: _accent)),
        content: const Text('Choose between Files or Gallery', style: TextStyle(color: Colors.white70)),
        actionsAlignment: MainAxisAlignment.spaceBetween,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop('files'),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Text('Files', style: TextStyle(color: _accent)),
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
                Text('Gallery', style: TextStyle(color: _accent)),
                SizedBox(width: 8),
                Icon(Icons.image, color: _accent),
              ],
            ),
          ),
        ],
      ),
    );

    if (source == 'files') {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'gif', 'pdf'],
      );

      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        return [file.uri.toString()];
      }
    } else if (source == 'gallery') {
      final pickedFile = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (pickedFile != null) {
        final file = File(pickedFile.path);
        return [file.uri.toString()];
      }
    }

    return [];
  }

  Future<void> _setCookies() async {
    List<String> cookieKeys = ['a', 'b', 'cc', 'folder', 'nodesc', 'sz', 'sfw'];

    for (var key in cookieKeys) {
      String cookieValue;
      if (key == 'sfw') {
        cookieValue = await _getSfwCookieValue();
      } else {
        String storageKey = 'fa_cookie_$key';
        cookieValue = (await _secureStorage.read(key: storageKey)) ?? '';
      }

      if (cookieValue.isNotEmpty) {
        await _webViewController.runJavaScript('''
          document.cookie = "$key=$cookieValue; path=/; domain=.furaffinity.net; secure";
        ''');
      }
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
    try {
      final res = await _webViewController.runJavaScriptReturningResult('''
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
    try {
      final res = await _webViewController.runJavaScriptReturningResult('''
        (function() {
          function __b64(o) { return 'B64:' + btoa(unescape(encodeURIComponent(JSON.stringify(o)))); }
          try {
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
      if (map == null || map['ok'] != true) return null;

      final fields = map['fields'];
      if (fields is! Map<String, dynamic>) return null;

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
    } catch (_) {
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
    final fields = await _readFinalizeFields();
    if (fields == null) {
      _showSnack('Failed to read finalize form.', isError: true);
      return;
    }

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

    await _templateStore.upsertTemplate(template);
    _showSnack('Template saved.', isError: false);
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

      final res = await _webViewController.runJavaScriptReturningResult('''
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
          title: const Text('Upload Submission'),
          centerTitle: true,
          actions: _isFinalizeReady
              ? [
            IconButton(
              tooltip: 'More',
              icon: Icon(
                (_toolsMenuOpen || _toolsMenuController.value > 0) ? Icons.close : Icons.more_vert,
                color: _accent,
              ),
              onPressed: _toggleToolsMenu,
            ),
          ]
              : null,
        ),
        body: Stack(
          children: [
            WebViewWidget(controller: _webViewController),
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
