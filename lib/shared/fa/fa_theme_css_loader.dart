import 'package:flutter/services.dart';

Future<String> loadFaThemeCss() {
  return rootBundle.loadString('assets/webview/fa/ui_theme_dark.css');
}
