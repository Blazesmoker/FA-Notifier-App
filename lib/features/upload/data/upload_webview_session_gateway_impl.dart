import 'package:fanotifier/features/upload/domain/upload_webview_session_gateway.dart';
import 'package:fanotifier/core/fa/fa_webview_cookie_service.dart';

class UploadWebViewSessionGatewayImpl
    implements UploadWebViewSessionGateway {
  const UploadWebViewSessionGatewayImpl({
    this._cookieService = const FAWebViewCookieService(),
  });

  final FAWebViewCookieService _cookieService;

  @override
  Future<void> setCookies() {
    return _cookieService.setCookies();
  }
}
