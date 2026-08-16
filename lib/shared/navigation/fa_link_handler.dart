import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'package:fanotifier/shared/utils/fa_link_matcher.dart';

abstract class FaLinkNavigator {
  const FaLinkNavigator();

  Future<void> open(
    BuildContext context,
    FALinkTarget target,
    String resolvedUrl,
  );
}

String normalizeInputUrl(String url) {
  final cleanUrl = url.trim();
  if (!cleanUrl.startsWith('http://') && !cleanUrl.startsWith('https://')) {
    return 'https://$cleanUrl';
  }
  return cleanUrl;
}

Future<void> handleFALink(
  BuildContext context,
  String url, {
  String? htmlSource,
  String Function(String url, {String? htmlSource})? getFullUrl,
}) async {
  String fullUrlToMatch = url;
  if (url.contains('.....')) {
    if (getFullUrl != null) {
      final recovered = getFullUrl(url, htmlSource: htmlSource);
      fullUrlToMatch = recovered;
    }
  }
  final target = matchFALink(fullUrlToMatch);
  final navigator = Provider.of<FaLinkNavigator>(context, listen: false);
  await navigator.open(context, target, fullUrlToMatch);
}
