// lib/hotel_booking/upload_submission.dart

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'openpost.dart';

class UploadSubmissionScreen extends StatefulWidget {
  const UploadSubmissionScreen({Key? key}) : super(key: key);

  @override
  _UploadSubmissionScreenState createState() => _UploadSubmissionScreenState();
}

class _UploadSubmissionScreenState extends State<UploadSubmissionScreen> {
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  final String initialUrl = 'https://www.furaffinity.net/submit/';
  final String finalizeUrl = 'https://www.furaffinity.net/submit/finalize/';
  late final WebViewController _webViewController;

  // State variables for the countdown and navigation
  bool _isWaitingToOpenSubmission = false;
  int? _submissionId;
  int _countdown = 6;
  Timer? _timer;

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
            print("Page started loading: $url");

            if (url.contains('upload-successful')) {
              // Extract the submission ID from the URL
              final submissionId = _extractSubmissionId(url);

              if (submissionId != null) {
                // Navigate back to the initial page
                await _webViewController.loadRequest(Uri.parse(initialUrl));

                // Show the full-screen indicator with countdown
                setState(() {
                  _isWaitingToOpenSubmission = true;
                  _submissionId = submissionId;
                  _countdown = 6;
                });

                // Start the countdown
                _startCountdown();
              }
            } else if (url.startsWith(initialUrl)) {
              // Inject CSS for the initial submit page
              print("Injecting initial CSS");
              await _injectInitialCss();
            } else if (url.startsWith(finalizeUrl)) {
              // Inject CSS for the finalize page
              print("Injecting finalize CSS");
              await _injectFinalizeCss();
            }
          },
          onPageFinished: (url) async {
            print("Page finished loading: $url");
            if (url.startsWith(initialUrl)) {
              await _injectInitialCss();
            } else if (url.startsWith(finalizeUrl)) {
              await _injectFinalizeCss();
            }
          },
          onWebResourceError: (error) {
            print("Web resource error: $error");
          },
        ),
      )
      ..loadRequest(Uri.parse(initialUrl));

    addFileSelectionListener();
    _setCookies();

  }


  /// Extracts the submission ID from the URL
  int? _extractSubmissionId(String url) {
    try {
      final uri = Uri.parse(url);
      if (uri.pathSegments.length >= 2 && uri.pathSegments[0] == 'view') {
        final idStr = uri.pathSegments[1];
        return int.tryParse(idStr);
      }
    } catch (e) {
      print('Error parsing submission ID: $e');
    }
    return null;
  }

  /// Starts the countdown timer and navigates to OpenPost after countdown
  void _startCountdown() {
    _timer = Timer.periodic(const Duration(seconds: 1), (Timer timer) {
      if (_countdown == 1) {
        timer.cancel();
        // Navigate to OpenPost with the submission ID
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => OpenPost(
              imageUrl: '',
              uniqueNumber: _submissionId.toString(),
            ),
          ),
        ).then((_) {
          // When returning from OpenPost, reset to initial page
          setState(() {
            _isWaitingToOpenSubmission = false;
            _countdown = 6;
          });
        });
      } else {
        setState(() {
          _countdown--;
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// Inject CSS to hide specific unwanted elements on the initial submit page
  Future<void> _injectInitialCss() async {
    await _webViewController.runJavaScript('''
      (function() {
        var style = document.createElement('style');
        style.type = 'text/css';
        style.innerHTML = `
          /* Hide navigation bars, headers, footers, ads, etc. */
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
          
          

          /* Adjust content area if necessary */
          .content {
            margin: 0 !important;
            padding: 0 !important;
          }
        `;
        document.head.appendChild(style);
      })();
    ''');
  }

  /// Inject CSS to display only #site-content and CAPTCHA-related elements on the finalize page
  Future<void> _injectFinalizeCss() async {
    await _webViewController.runJavaScript('''
      (function() {
        var style = document.createElement('style');
        style.type = 'text/css';
        style.innerHTML = `
          /* Hide specific unwanted elements */
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

          /* Adjust content area if necessary */
          .content {
            margin: 0 !important;
            padding: 0 !important;
          }
        `;
        document.head.appendChild(style);
      })();
    ''');
  }

  /// Add file selection listener for Android
  void addFileSelectionListener() async {
    if (Platform.isAndroid) {
      final androidController =
      _webViewController.platform as AndroidWebViewController;
      await androidController.setOnShowFileSelector(_androidFilePicker);
    }
  }

  /// Handle file selection
  Future<List<String>> _androidFilePicker(FileSelectorParams params) async {
    // Shows a dialog to choose the source
    final source = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: Color(0xFFE09321), width: 0.5),
          borderRadius: BorderRadius.circular(22),
        ),
        title: const Text('Select source'),
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
                  style: TextStyle(color: Color(0xFFE09321)),
                ),
                SizedBox(width: 8),
                Icon(Icons.insert_drive_file, color: Color(0xFFE09321)),
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
                  style: TextStyle(color: Color(0xFFE09321)),
                ),
                SizedBox(width: 8),
                Icon(Icons.image, color: Color(0xFFE09321)),
              ],
            ),
          ),
        ],
      ),
    );

    if (source == 'files') {
      // Use FilePicker for file selection
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
      // Use image_picker for gallery selection
      final pickedFile =
      await ImagePicker().pickImage(source: ImageSource.gallery);
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
        await _webViewController.runJavaScript(
          '''
          document.cookie = "$key=$cookieValue; path=/; domain=.furaffinity.net; secure";
          ''',
        );
      }

    }


  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
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
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _webViewController),
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
    );
  }
}
