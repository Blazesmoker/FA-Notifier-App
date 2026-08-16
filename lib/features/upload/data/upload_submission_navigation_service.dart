import 'package:fanotifier/features/upload/data/upload_webview_navigation_policy.dart';
import 'package:fanotifier/features/upload/domain/upload_navigation_repository.dart';

class UploadSubmissionNavigationService
    implements UploadNavigationRepository {
  const UploadSubmissionNavigationService({
    this._webViewNavigationPolicy = const UploadWebViewNavigationPolicy(),
  });

  final UploadWebViewNavigationPolicy _webViewNavigationPolicy;

  @override
  String get initialUrl => 'https://www.furaffinity.net/submit/';

  @override
  String get finalizeUrl => 'https://www.furaffinity.net/submit/finalize/';

  @override
  bool isFinalizeUrl(String url) {
    final parsed = Uri.tryParse(url);
    if (parsed == null) return false;
    return parsed.path.startsWith('/submit/finalize');
  }

  @override
  bool isInitialSubmitUrl(String url) {
    return url.startsWith(initialUrl);
  }

  @override
  bool isUploadSuccessfulUrl(String url) {
    return url.contains('upload-successful');
  }

  @override
  int? extractSubmissionId(String url) {
    try {
      final uri = Uri.parse(url);
      if (uri.pathSegments.length >= 2 && uri.pathSegments[0] == 'view') {
        final idStr = uri.pathSegments[1];
        return int.tryParse(idStr);
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  @override
  bool shouldBlockIosHost(String host) {
    return _webViewNavigationPolicy.shouldBlockIosHost(host);
  }
}
