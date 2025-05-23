import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

class EditSubmissionScreen extends StatefulWidget {
  final String initialUrl;

  const EditSubmissionScreen({Key? key, required this.initialUrl})
      : super(key: key);

  @override
  _EditSubmissionScreenState createState() => _EditSubmissionScreenState();
}

class _EditSubmissionScreenState extends State<EditSubmissionScreen> {
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  late final WebViewController _webViewController;

  // detect if it's the "Update Submission File" page by checking the URL:
  bool get _isUpdateSubmissionScreen =>
      widget.initialUrl.contains('changesubmission');

  @override
  void initState() {
    super.initState();
    _initializeWebViewController();
  }


  Future<String> _getSfwCookieValue() async {
    final prefs = await SharedPreferences.getInstance();
    final sfwEnabled = prefs.getBool('sfwEnabled') ?? true;
    return sfwEnabled ? '1' : '0';
  }

  void _initializeWebViewController() {
    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) async {
            // If it returns to a "/view/" page, then success -> pop
            if (url.contains('furaffinity.net/view/')) {
              Navigator.pop(context);
            }
            await _injectCustomCssAndJs();
          },
          onWebResourceError: (error) {
            debugPrint("Web resource error: $error");
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.initialUrl));


    _setCookies();


    if (Platform.isAndroid) {
      final androidController =
      _webViewController.platform as AndroidWebViewController;
      androidController.setOnShowFileSelector(_androidFilePicker);
    }
  }

  /// Inject custom CSS to hide navbars, ads, footers

  Future<void> _injectCustomCssAndJs() async {
    // Hides unwanted elements & forces .table to stack vertically
    await _webViewController.runJavaScript('''
      (function() {
        var style = document.createElement('style');
        style.type = 'text/css';
        style.innerHTML = `
          /* Hide headers, footers, ads, navbars, etc. */
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
          .newsBlock {
            display: none !important;
          }

          /* Hide "Manage Submissions - Back to Submission Page" links */
          .return-links,
          .return-links * {
            display: none !important;
          }

          /* Dark background + white text (optional) */
          html, body, #main-window, .content, #site-content {
            background-color: #000 !important;
            color: #fff !important;
            margin: 0 !important;
            padding: 0 !important;
          }

          /* Links more visible on dark background */
          a {
            color: #1e90ff !important;
          }

          /* Force table cells to stack vertically (one column) */
          .table {
            display: flex !important;
            flex-direction: column !important;
          }
          .table-cell {
            display: block !important;
            width: auto !important;
            margin-bottom: 16px !important;
          }
        `;
        document.head.appendChild(style);
      })();
    ''');


    if (_isUpdateSubmissionScreen) {
      await _webViewController.runJavaScript('''
        (function() {
          try {
            var imageCell = document.querySelector('.table-cell.valigntop.p20r');
            var fileCell  = document.querySelector('.table-cell.valigntop.alignleft');
            if (imageCell && fileCell) {
              // Add fileCell after imageCell, putting it below.
              var parentRow = imageCell.parentNode;
              if (parentRow) {
                parentRow.appendChild(fileCell);
              }
            }
          } catch(e) {
            console.log('Error reordering: ' + e);
          }
        })();
      ''');
    }
  }


  Future<void> _setCookies() async {

    final cookieKeys = ['a', 'b', 'cc', 'folder', 'nodesc', 'sz', 'sfw'];
    for (var key in cookieKeys) {
      String cookieValue;
      if (key == 'sfw') {
        cookieValue = await _getSfwCookieValue();
      } else {
        final storageKey = 'fa_cookie_$key';
        cookieValue = (await _secureStorage.read(key: storageKey)) ?? '';
      }
      if (cookieValue.isNotEmpty) {
        await _webViewController.runJavaScript('''
          document.cookie = "$key=$cookieValue; path=/; domain=.furaffinity.net; secure; httponly";
        ''');
      }
    }
  }

  Future<List<String>> _androidFilePicker(FileSelectorParams params) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'gif'],
      );
      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        return [file.uri.toString()];
      }
    } catch (e) {
      debugPrint("Error selecting file: $e");
    }
    return [];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Submission'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: WebViewWidget(controller: _webViewController),
    );
  }
}
