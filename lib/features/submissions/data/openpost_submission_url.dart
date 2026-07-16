import 'package:FANotifier/shared/fa/parsing_utils.dart';

String? normalizeOpenPostSubmissionUrl(String? value) {
  final normalized = normalizeFaUrl(value);
  if (normalized == null || !isTrustedOpenPostSubmissionUrl(normalized)) {
    return null;
  }
  return normalized;
}

bool isTrustedOpenPostSubmissionUrl(String value) {
  final uri = Uri.tryParse(value);
  if (uri == null || uri.scheme != 'https' || !uri.hasAuthority) {
    return false;
  }
  final host = uri.host.toLowerCase();
  return host == 'furaffinity.net' || host.endsWith('.furaffinity.net');
}
