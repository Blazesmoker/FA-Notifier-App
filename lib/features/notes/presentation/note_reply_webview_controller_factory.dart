import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

class NoteReplyWebViewControllerFactory {
  const NoteReplyWebViewControllerFactory();

  WebViewController create() {
    late final PlatformWebViewControllerCreationParams params;
    if (WebViewPlatform.instance is WebKitWebViewPlatform) {
      params = WebKitWebViewControllerCreationParams(
        allowsInlineMediaPlayback: true,
        mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
      );
    } else {
      params = const PlatformWebViewControllerCreationParams();
    }

    return WebViewController.fromPlatformCreationParams(params);
  }

  Future<void> configure(
    WebViewController controller, {
    required String userAgent,
    required NavigationDelegate navigationDelegate,
  }) async {
    await controller.setUserAgent(userAgent);
    await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    await controller.setNavigationDelegate(navigationDelegate);
  }
}
