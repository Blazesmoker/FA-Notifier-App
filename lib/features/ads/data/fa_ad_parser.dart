import 'dart:convert';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

import 'package:fanotifier/core/logging/fa_ads_logging.dart';
import 'package:fanotifier/features/ads/domain/fa_ad_models.dart';

FaAdPageMetadata? parseFaAdPage({
  required String html,
  required Uri documentUri,
  required bool sfwEnabled,
  Document? parsedDocument,
}) {
  try {
    final document = parsedDocument ?? html_parser.parse(html);
    final modeControl = document.querySelector('input#sfw-toggle-mobile') ??
        document.querySelector('input#sfw-toggle');
    if (modeControl != null && modeControl.attributes.containsKey('checked') != sfwEnabled) {
      FaAdsLog.event(FaAdsLogCategory.config, 'page_mode_mismatch_rejected',
          checks: {'modeMatchesRequest': false, 'adsAllowed': false});
      return null;
    }
    Map<String, dynamic>? config;
    for (final script in document.querySelectorAll('script')) {
      final source = script.text;
      final match = RegExp(r'new\s+adManager\s*\(\s*').firstMatch(source);
      if (match == null) continue;
      final end = _objectEnd(source, match.end);
      if (end == null) continue;
      final decoded = jsonDecode(source.substring(match.end, end));
      if (decoded is Map<String, dynamic>) config = decoded;
      break;
    }
    if (config == null) return null;
    final provider = config['providerConfig']?['inhouse'];
    if (provider is! Map) return null;
    final deliveryUri = Uri.parse('${provider['domain']}${provider['dataPath']}');
    if (!isFaAdEndpoint(deliveryUri, 'spc.php') ||
        provider['dataVariableName'] != 'OA_output') {
      return null;
    }
    final slotConfig = config['slotConfig'];
    final inhouse = config['adConfig']?['inhouse'];
    final sizeConfig = config['sizeConfig'];
    if (slotConfig is! Map || inhouse is! Map || sizeConfig is! List) {
      return null;
    }
    final present = document
        .querySelectorAll('ins.jsAdSlot[data-id]')
        .map((element) => element.attributes['data-id'])
        .toSet();
    final forced = config['extraMetadata']?['forceLoadConfigs'];
    final layouts = <FaAdLayout>[];
    for (final breakpoint in sizeConfig) {
      if (breakpoint is! Map || breakpoint['labels'] is! List) continue;
      final labels = breakpoint['labels'] as List;
      if (labels.isEmpty || labels.first is! String) continue;
      final label = labels.first as String;
      final query = breakpoint['mediaQuery']?.toString() ?? '';
      final minimum = RegExp(r'min-width:\s*(\d+)px').firstMatch(query);
      final maximum = RegExp(r'max-width:\s*(\d+)px').firstMatch(query);
      if (minimum == null && maximum == null) continue;
      final slots = <FaAdSlot>[];
      for (final placement in FaAdPlacement.values) {
        final id = placement.websiteId;
        if (!present.contains(id)) continue;
        final cfg = slotConfig[id];
        if (cfg is! Map || cfg['providerPriority'] is! List ||
            !(cfg['providerPriority'] as List).contains('inhouse')) {
          continue;
        }
        final size = _size(cfg['containerSize']?[label]);
        final ad = _zone(inhouse[id], label);
        if (size == null || ad == null) continue;
        slots.add(FaAdSlot(placement: placement, zoneId: ad, size: size));
      }
      final fetchOnly = <int>[];
      if (forced is List) {
        for (final id in forced) {
          final zone = _zone(inhouse[id], label);
          if (zone != null) fetchOnly.add(zone);
        }
      }
      if (slots.isEmpty) continue;
      layouts.add(FaAdLayout(
        minimumWidth: minimum == null ? 0 : double.parse(minimum.group(1)!),
        maximumWidth: maximum == null
            ? double.infinity
            : double.parse(maximum.group(1)!),
        slots: List.unmodifiable(slots),
        fetchOnlyZones: List.unmodifiable(fetchOnly),
      ));
    }
    FaAdsLog.event(FaAdsLogCategory.config, 'page_parsed',
        counts: {'layouts': layouts.length},
        checks: {'fromPageHtml': true, 'inhouseOnly': true,
          'modeControlPresent': modeControl != null, 'modeMatchesRequest': true});
    if (layouts.isEmpty) return null;
    return FaAdPageMetadata(
      documentUri: documentUri,
      deliveryUri: deliveryUri,
      sfwEnabled: sfwEnabled,
      layouts: List.unmodifiable(layouts),
    );
  } catch (_) {
    FaAdsLog.event(FaAdsLogCategory.config, 'page_config_rejected');
    return null;
  }
}

bool faAdPageModeMatches(String html, bool sfwEnabled) {
  final input = RegExp(r'''<input\b[^>]*\bid\s*=\s*['"]sfw-toggle(?:-mobile)?['"][^>]*>''',
      caseSensitive: false).firstMatch(html)?.group(0);
  if (input == null) return true;
  final control = html_parser.parseFragment(input).querySelector('input');
  return control == null || control.attributes.containsKey('checked') == sfwEnabled;
}

FaAdDelivery parseFaAdDelivery(String source, FaAdLayout layout) {
  final fragments = <int, String>{};
  final assignments = RegExp(
    r'''OA_output\[\s*['"]?(\d+)['"]?\s*\]\s*(\+=|=)\s*''',
  );
  for (final match in assignments.allMatches(source)) {
    final literal = _stringExpression(source, match.end);
    if (literal == null) continue;
    final zone = int.parse(match.group(1)!);
    fragments[zone] = match.group(2) == '='
        ? literal
        : '${fragments[zone] ?? ''}$literal';
  }
  final creatives = <int, FaAdCreative>{};
  for (final slot in layout.slots) {
    final fragment = fragments[slot.zoneId];
    if (fragment == null || fragment.isEmpty) continue;
    final document = html_parser.parseFragment(fragment);
    final anchor = document.querySelector('a[href]');
    final image = anchor?.querySelector('img[src]');
    if (anchor == null || image == null) continue;
    final click = Uri.tryParse(anchor.attributes['href'] ?? '');
    final imageUri = Uri.tryParse(image.attributes['src'] ?? '');
    Uri? impression;
    for (final candidate in document.querySelectorAll('img[src]')) {
      final uri = Uri.tryParse(candidate.attributes['src'] ?? '');
      if (uri != null && isFaAdEndpoint(uri, 'lg.php')) {
        impression = uri;
        break;
      }
    }
    final widthText = image.attributes['width']?.trim() ?? '';
    final heightText = image.attributes['height']?.trim() ?? '';
    final width = int.tryParse(widthText);
    final height = int.tryParse(heightText);
    final validDimensions = (widthText.isEmpty || width != null && width > 0) &&
        (heightText.isEmpty || height != null && height > 0);
    if (click == null || !isFaAdEndpoint(click, 'cl.php') ||
        (click.queryParameters['sig'] ?? '').isEmpty ||
        imageUri == null || !isFaAdImage(imageUri) || impression == null ||
        impression.queryParameters['zoneid'] != slot.zoneId.toString() ||
        click.queryParameters['zoneid'] != slot.zoneId.toString() ||
        click.queryParameters['bannerid'] != impression.queryParameters['bannerid']) {
      continue;
    }
    if (!validDimensions) {
      FaAdsLog.event(FaAdsLogCategory.config, 'creative_dimensions_rejected',
          slot: slot.placement.name,
          checks: {'widthValid': widthText.isEmpty || width != null && width > 0,
            'heightValid': heightText.isEmpty || height != null && height > 0});
      continue;
    }
    FaAdsLog.event(FaAdsLogCategory.config, 'creative_size_hints',
        slot: slot.placement.name,
        counts: {'configuredWidth': slot.size.width, 'configuredHeight': slot.size.height,
          'declaredWidth': width ?? 0, 'declaredHeight': height ?? 0},
        checks: {'widthPresent': width != null, 'heightPresent': height != null,
          'intrinsicSizeNeeded': width == null || height == null,
          'exceedsConfiguredSize': width != null && width > slot.size.width ||
              height != null && height > slot.size.height,
          'sizeRestrictedToSlot': false});
    creatives[slot.zoneId] = FaAdCreative(
      imageUri: imageUri,
      clickUri: click,
      impressionUri: impression,
      declaredWidth: width,
      declaredHeight: height,
    );
  }
  return FaAdDelivery(Map.unmodifiable(creatives));
}

bool isFaAdEndpoint(Uri uri, String endpoint) =>
    uri.scheme == 'https' && uri.host == 'rv.furaffinity.net' &&
    !uri.hasPort && uri.userInfo.isEmpty &&
    uri.path == '/live/www/delivery/$endpoint';

bool isFaAdImage(Uri uri) =>
    uri.scheme == 'https' && uri.host == 'rv.furaffinity.net' &&
    !uri.hasPort && uri.userInfo.isEmpty && uri.path.startsWith('/images/');

FaAdSize? _size(dynamic value) {
  if (value is! List || value.length != 2 || value[0] is! int || value[1] is! int) {
    return null;
  }
  if (value[0] <= 0 || value[1] <= 0) return null;
  return FaAdSize(value[0] as int, value[1] as int);
}

int? _zone(dynamic cfg, String label) {
  if (cfg is! Map) return null;
  final variant = cfg['sizeOverride']?[label] ?? cfg['default'];
  if (variant is! Map || variant['tagId'] is! int) return null;
  return variant['tagId'] as int;
}

int? _objectEnd(String source, int start) {
  if (start >= source.length || source[start] != '{') return null;
  var depth = 0;
  var quoted = false;
  var escaped = false;
  for (var index = start; index < source.length; index++) {
    final char = source[index];
    if (quoted) {
      if (escaped) {
        escaped = false;
      } else if (char == r'\') {
        escaped = true;
      } else if (char == '"') {
        quoted = false;
      }
    } else if (char == '"') {
      quoted = true;
    } else if (char == '{') {
      depth++;
    } else if (char == '}' && --depth == 0) {
      return index + 1;
    }
  }
  return null;
}

String? _stringExpression(String source, int start) {
  var index = start;
  final result = StringBuffer();
  while (index < source.length) {
    while (index < source.length && source[index].trim().isEmpty) {
      index++;
    }
    if (index >= source.length || (source[index] != '"' && source[index] != "'")) {
      return null;
    }
    final quote = source[index++];
    var closed = false;
    while (index < source.length) {
      final char = source[index++];
      if (char == quote) {
        closed = true;
        break;
      }
      if (char != r'\') {
        result.write(char);
        continue;
      }
      if (index >= source.length) return null;
      final escape = source[index++];
      if (escape == 'x' || escape == 'u') {
        final length = escape == 'x' ? 2 : 4;
        if (index + length > source.length) return null;
        final code = int.tryParse(source.substring(index, index + length), radix: 16);
        if (code == null) return null;
        result.writeCharCode(code);
        index += length;
      } else {
        result.write(switch (escape) {
          'n' => '\n',
          'r' => '\r',
          't' => '\t',
          'b' => '\b',
          'f' => '\f',
          _ => escape,
        });
      }
    }
    if (!closed) return null;
    while (index < source.length && source[index].trim().isEmpty) {
      index++;
    }
    if (index < source.length && source[index] == ';') return result.toString();
    if (index >= source.length || source[index++] != '+') return null;
  }
  return null;
}
