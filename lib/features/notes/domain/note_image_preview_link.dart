enum NoteImagePreviewSource {
  furAffinity,
  imgur,
  googleImages,
  googleImageResult,
  googleImageShare,
  googleDrive,
  dropbox,
}

class NoteImagePreviewLink {
  const NoteImagePreviewLink({
    required this.source,
    required this.uri,
  });

  final NoteImagePreviewSource source;
  final Uri uri;

  String get url => uri.toString();

  static NoteImagePreviewLink? tryParse(String value) {
    return _tryParse(value, canUnwrapExternalUrl: true);
  }

  static NoteImagePreviewLink? _tryParse(
    String value, {
    required bool canUnwrapExternalUrl,
  }) {
    final trimmed = value.trim();
    final normalized = trimmed.startsWith('//')
        ? 'https:$trimmed'
        : trimmed.startsWith('/')
            ? 'https://www.furaffinity.net$trimmed'
            : trimmed;
    final uri = Uri.tryParse(normalized);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return null;

    final host = uri.host.toLowerCase();
    final segments = uri.pathSegments
        .where((segment) => segment.isNotEmpty)
        .toList();

    if (_isFurAffinityHost(host)) {
      if (canUnwrapExternalUrl &&
          segments.isNotEmpty &&
          segments.first.toLowerCase() == 'externalurl') {
        final target = uri.queryParameters['q'];
        if (target == null || target.trim().isEmpty) return null;
        return _tryParse(target, canUnwrapExternalUrl: false);
      }
      if (segments.length >= 2 &&
          segments.first.toLowerCase() == 'view' &&
          int.tryParse(segments[1]) != null) {
        return NoteImagePreviewLink(
          source: NoteImagePreviewSource.furAffinity,
          uri: Uri.parse(
            'https://www.furaffinity.net/view/${segments[1]}/',
          ),
        );
      }
      return null;
    }

    if (_isImgurHost(host) &&
        segments.length >= 2 &&
        segments.first.toLowerCase() == 'gallery') {
      final galleryId = _imgurGalleryId(segments.last);
      if (galleryId == null) return null;
      return NoteImagePreviewLink(
        source: NoteImagePreviewSource.imgur,
        uri: Uri.https('imgur.com', '/gallery/$galleryId'),
      );
    }

    if (_isGoogleHost(host) &&
        uri.path == '/imgres' &&
        _isHttpImageUrl(uri.queryParameters['imgurl'])) {
      return NoteImagePreviewLink(
        source: NoteImagePreviewSource.googleImageResult,
        uri: uri
            .replace(scheme: 'https', host: 'www.google.com')
            .removeFragment(),
      );
    }

    if (_isGoogleHost(host) &&
        uri.path == '/search' &&
        uri.queryParameters['udm'] == '2' &&
        _fragmentValue(uri, 'sv')?.isNotEmpty == true) {
      return NoteImagePreviewLink(
        source: NoteImagePreviewSource.googleImages,
        uri: uri.replace(scheme: 'https', host: 'www.google.com'),
      );
    }

    if (_isGoogleShareHost(host) && segments.isNotEmpty) {
      return NoteImagePreviewLink(
        source: NoteImagePreviewSource.googleImageShare,
        uri: Uri.https('share.google', '/${segments.join('/')}'),
      );
    }

    if (_isGoogleDriveHost(host) &&
        segments.length >= 4 &&
        segments[0].toLowerCase() == 'file' &&
        segments[1].toLowerCase() == 'd' &&
        segments[2].isNotEmpty &&
        segments[3].toLowerCase() == 'view') {
      return NoteImagePreviewLink(
        source: NoteImagePreviewSource.googleDrive,
        uri: Uri.parse(
          'https://drive.google.com/file/d/${segments[2]}/view',
        ),
      );
    }

    if (_isDropboxHost(host) &&
        segments.length >= 4 &&
        segments[0].toLowerCase() == 'scl' &&
        segments[1].toLowerCase() == 'fi') {
      return NoteImagePreviewLink(
        source: NoteImagePreviewSource.dropbox,
        uri: uri.replace(
          scheme: 'https',
          host: 'www.dropbox.com',
        ).removeFragment(),
      );
    }

    return null;
  }
}

bool _isFurAffinityHost(String host) {
  return host == 'furaffinity.net' || host.endsWith('.furaffinity.net');
}

bool _isImgurHost(String host) {
  return host == 'imgur.com' || host == 'www.imgur.com';
}

String? _imgurGalleryId(String pathSegment) {
  return RegExp(r'(?:^|-)([A-Za-z0-9]{5,10})$')
      .firstMatch(pathSegment)
      ?.group(1);
}

bool _isGoogleHost(String host) {
  return host == 'google.com' || host == 'www.google.com';
}

bool _isGoogleShareHost(String host) {
  return host == 'share.google';
}

bool _isHttpImageUrl(String? value) {
  if (value == null || value.isEmpty) return false;
  final uri = Uri.tryParse(value);
  return uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
}

bool _isGoogleDriveHost(String host) {
  return host == 'drive.google.com';
}

bool _isDropboxHost(String host) {
  return host == 'dropbox.com' || host == 'www.dropbox.com';
}

String? _fragmentValue(Uri uri, String key) {
  try {
    return Uri.splitQueryString(uri.fragment)[key];
  } on FormatException {
    return null;
  }
}
