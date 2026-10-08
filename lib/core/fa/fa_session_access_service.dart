import 'dart:async';

import 'package:fanotifier/core/fa/fa_media_auth.dart';
import 'package:fanotifier/core/fa/fa_webview_cookie_service.dart';
import 'package:fanotifier/core/network/fa_http.dart';
import 'package:fanotifier/shared/fa/domain/fa_session_access.dart';

class FaSessionAccessService implements FaSessionAccess {
  FaSessionAccessService._();

  static final FaSessionAccessService instance = FaSessionAccessService._();

  final StreamController<int> _verifiedSessions =
      StreamController<int>.broadcast();
  int _verifiedGeneration = 0;

  @override
  String get userAgent => FAHttp.userAgent;

  @override
  int get verifiedGeneration => _verifiedGeneration;

  @override
  Stream<int> get verifiedSessions => _verifiedSessions.stream;

  @override
  Future<void> synchronizeWebViewSession() {
    return const FAWebViewCookieService().setCookies(
      preserveExistingSession: true,
      applySfwPreference: false,
      preferStoredClearance: true,
    );
  }

  Future<void> accessVerified() async {
    await synchronizeWebViewSession();
    FaMediaAuth.invalidate();
    _verifiedSessions.add(++_verifiedGeneration);
  }
}
