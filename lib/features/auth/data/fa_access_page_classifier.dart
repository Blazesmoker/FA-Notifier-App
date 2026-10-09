import 'package:html/parser.dart' as html_parser;

import 'package:fanotifier/core/fa/fa_cookie_helper.dart';
import 'package:fanotifier/core/network/fa_request_coordinator.dart';
import 'package:fanotifier/features/auth/domain/cloudflare_http_access_result.dart';
import 'package:fanotifier/shared/fa/fa_system_message_parser.dart';

CloudflareHttpAccessResult classifyFaAccessPage({
  required String url,
  required String body,
  int? statusCode,
  Map<String, String>? headers,
}) {
  final uri = Uri.tryParse(url);
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.userInfo.isNotEmpty ||
      (uri.hasPort && uri.port != 443) ||
      (uri.host != 'www.furaffinity.net' && uri.host != 'furaffinity.net')) {
    return const CloudflareHttpAccessResult(
      status: CloudflareHttpAccessStatus.denied,
    );
  }
  if (FaCookieHelper.isCloudflareChallengePage(
    body: body,
    statusCode: statusCode,
    headers: headers,
  )) {
    return CloudflareHttpAccessResult(
      status: CloudflareHttpAccessStatus.challenged,
      statusCode: statusCode,
    );
  }

  final document = html_parser.parse(body);
  final isDocument = FaCookieHelper.isFaDocument(
    body: body,
    statusCode: statusCode,
    headers: headers,
    parsedDocument: document,
  );
  final message = parseFaSystemMessage(
    body,
    parsedDocument: document,
    allowBodyFallback: !isDocument,
  );
  if (message != null &&
      message.isMaintenanceOrUnavailable &&
      isFaMaintenanceOrUnavailableText(message.message, includeHttp403: false)) {
    String? retryAfterHeader;
    for (final entry in (headers ?? <String, String>{}).entries) {
      if (entry.key.toLowerCase() == 'retry-after') {
        retryAfterHeader = entry.value;
        break;
      }
    }
    return CloudflareHttpAccessResult(
      status: CloudflareHttpAccessStatus.siteUnavailable,
      statusCode: statusCode,
      siteUnavailableMessage: message.message,
      retryAfter: parseRetryAfterHeader(retryAfterHeader) ?? message.retryAfter,
    );
  }
  return CloudflareHttpAccessResult(
    status: isDocument
        ? CloudflareHttpAccessStatus.granted
        : CloudflareHttpAccessStatus.denied,
    statusCode: statusCode,
    pageHtml: isDocument ? body : null,
    finalUrl: isDocument ? uri.toString() : null,
  );
}

void recordFaAccessAvailability(CloudflareHttpAccessResult result) {
  final message = result.siteUnavailableMessage;
  if (result.status != CloudflareHttpAccessStatus.siteUnavailable ||
      message == null) {
    return;
  }
  FaRequestCoordinator.instance.recordMaintenanceOrUnavailable(
    message: message,
    retryAfter: result.retryAfter,
    preserveExistingBackoff: true,
  );
}
