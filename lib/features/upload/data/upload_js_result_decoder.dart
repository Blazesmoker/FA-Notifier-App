import 'dart:convert';

class UploadJsResultDecoder {
  const UploadJsResultDecoder();

  Map<String, dynamic>? decodeMap(Object? result) {
    if (result == null) return null;

    if (result is Map) {
      try {
        return result.cast<String, dynamic>();
      } catch (_) {
        return null;
      }
    }

    String raw = result is String ? result : result.toString();
    raw = raw.trim();
    if (raw.isEmpty) return null;

    final decodedRaw = _decodeJsonMapOrString(raw);
    if (decodedRaw is Map<String, dynamic>) return decodedRaw;
    if (decodedRaw is String) raw = decodedRaw.trim();

    final base64Decoded = _decodeBase64Map(raw);
    if (base64Decoded != null) return base64Decoded;

    final stripped = raw.replaceAll(RegExp(r'^\s*"+|"+\s*$'), '').trim();
    if (stripped.isEmpty) return null;

    final strippedBase64Decoded = _decodeBase64Map(stripped);
    if (strippedBase64Decoded != null) return strippedBase64Decoded;

    final decodedStripped = _decodeJsonMapOrString(stripped);
    if (decodedStripped is Map<String, dynamic>) return decodedStripped;
    if (decodedStripped is String) {
      final decodedNested = _decodeJsonMapOrString(decodedStripped);
      if (decodedNested is Map<String, dynamic>) return decodedNested;
    }

    return null;
  }

  Object? _decodeJsonMapOrString(String value) {
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is String) return decoded;
    } catch (_) {}
    return null;
  }

  Map<String, dynamic>? _decodeBase64Map(String value) {
    if (!value.startsWith('B64:')) return null;

    final b64 = value.substring(4);
    try {
      final jsonStr = utf8.decode(base64Decode(b64));
      final decoded = jsonDecode(jsonStr);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {
      return null;
    }
    return null;
  }
}
