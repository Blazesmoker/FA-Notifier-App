import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher_string.dart';

import 'package:fanotifier/shared/utils/fa_link_matcher.dart';
import 'package:fanotifier/shared/widgets/external_link_confirmation_dialog.dart';

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

Future<void> handleExternalLink(
  BuildContext context,
  String url,
) async {
  final cleanUrl = url.trim();
  final parsedUrl = Uri.tryParse(cleanUrl);
  if (parsedUrl == null) return;

  if (parsedUrl.hasScheme &&
      parsedUrl.scheme != 'http' &&
      parsedUrl.scheme != 'https') {
    await launchUrlString(
      cleanUrl,
      mode: LaunchMode.externalApplication,
    );
    return;
  }

  final sourceUri = parsedUrl.hasScheme
      ? parsedUrl
      : cleanUrl.startsWith('//')
          ? Uri.tryParse('https:$cleanUrl')
          : cleanUrl.startsWith('/') || cleanUrl.startsWith('#')
              ? Uri.parse('https://www.furaffinity.net').resolve(cleanUrl)
              : Uri.tryParse(normalizeInputUrl(cleanUrl));
  if (sourceUri == null) return;

  final wrappedDestination = _externalUrlDestination(sourceUri);
  if (wrappedDestination == null && _isFurAffinityUri(sourceUri)) {
    await launchUrlString(
      sourceUri.toString(),
      mode: LaunchMode.externalApplication,
    );
    return;
  }

  final destinationUri = wrappedDestination ?? sourceUri;
  if (_isFurAffinityUri(destinationUri)) {
    await handleFALink(context, destinationUri.toString());
    return;
  }

  final selectedUrl = await ExternalLinkConfirmationDialog.show(
    context,
    destinationUrl: destinationUri.toString(),
  );
  if (selectedUrl == null || !context.mounted) return;

  if (selectedUrl == destinationUri.toString()) {
    await launchUrlString(
      selectedUrl,
      mode: LaunchMode.externalApplication,
    );
    return;
  }

  await handleFALink(context, selectedUrl);
}

Uri? _externalUrlDestination(Uri uri) {
  if (!_isFurAffinityUri(uri) ||
      uri.pathSegments.isEmpty ||
      uri.pathSegments.first.toLowerCase() != 'externalurl') {
    return null;
  }

  final destination = Uri.tryParse(uri.queryParameters['q'] ?? '');
  if (destination == null ||
      !destination.hasAuthority ||
      (destination.scheme != 'http' && destination.scheme != 'https')) {
    return null;
  }
  return destination;
}

bool _isFurAffinityUri(Uri uri) {
  final host = uri.host.toLowerCase();
  return host == 'furaffinity.net' ||
      host.endsWith('.furaffinity.net') ||
      host == 'fxfuraffinity.net' ||
      host.endsWith('.fxfuraffinity.net');
}
