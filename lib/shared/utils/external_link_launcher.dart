import 'package:url_launcher/url_launcher.dart';

Future<bool> tryLaunchExternalUri(Uri uri) async {
  if (!await canLaunchUrl(uri)) {
    return false;
  }
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}

Future<bool> tryLaunchExternalUrl(String url) {
  return tryLaunchExternalUri(Uri.parse(url));
}

Future<void> launchExternalUriWithFallback(Uri uri) async {
  if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
    await launchUrl(uri);
  }
}
