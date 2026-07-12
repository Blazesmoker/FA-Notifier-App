import 'package:FANotifier/features/upload/domain/upload_webview_session_gateway.dart';
import 'package:FANotifier/core/fa/fa_webview_cookie_service.dart';

class UploadWebViewSessionGatewayImpl
    implements UploadWebViewSessionGateway {
  const UploadWebViewSessionGatewayImpl({
    FAWebViewCookieService cookieService = const FAWebViewCookieService(),
  }) : _cookieService = cookieService;

  final FAWebViewCookieService _cookieService;

  @override
  Future<void> setCookies() {
    return _cookieService.setCookies();
  }
}
