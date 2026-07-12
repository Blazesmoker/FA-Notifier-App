import 'dart:io';

import 'package:FANotifier/core/network/fa_http.dart';

class FreshHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.idleTimeout = const Duration(seconds: 10);
    client.connectionTimeout = const Duration(seconds: 20);
    client.autoUncompress = true;
    client.maxConnectionsPerHost = 8;
    client.userAgent = FAHttp.userAgent;
    return client;
  }
}
