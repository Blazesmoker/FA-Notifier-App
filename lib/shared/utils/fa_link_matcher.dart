enum FALinkTargetType {
  gallery,
  galleryFolder,
  scraps,
  user,
  journalUser,
  journal,
  submission,
  external,
}

class FALinkTarget {
  const FALinkTarget({
    required this.type,
    required this.url,
    this.username,
    this.folderNumber,
    this.folderName,
    this.journalId,
    this.submissionId,
  });

  final FALinkTargetType type;
  final String url;
  final String? username;
  final String? folderNumber;
  final String? folderName;
  final String? journalId;
  final String? submissionId;
}

String buildFAGalleryFolderUrl({
  required String username,
  required String folderNumber,
  required String folderName,
}) {
  return 'https://www.furaffinity.net/gallery/$username/folder/$folderNumber/$folderName/';
}

FALinkTarget matchFALink(String url) {
  final uri = Uri.parse(url);
  final urlToMatch = uri.toString();

  final galleryRegex = RegExp(
    r'^https?://(?:www\.)?furaffinity\.net/gallery/([a-zA-Z0-9\-_.~]+)(?:/folder/(\d+)/([a-zA-Z0-9\-_.~]+))?/?$',
  );
  final galleryMatch = galleryRegex.firstMatch(urlToMatch);
  if (galleryMatch != null) {
    final folderNumber = galleryMatch.group(2);
    final folderName = galleryMatch.group(3);
    return FALinkTarget(
      type: folderNumber != null && folderName != null
          ? FALinkTargetType.galleryFolder
          : FALinkTargetType.gallery,
      url: url,
      username: galleryMatch.group(1),
      folderNumber: folderNumber,
      folderName: folderName,
    );
  }

  final scrapsRegex = RegExp(
    r'^https?://(?:www\.)?furaffinity\.net/scraps/([a-zA-Z0-9\-_.~]+)(?:/.*)?$',
  );
  final scrapsMatch = scrapsRegex.firstMatch(urlToMatch);
  if (scrapsMatch != null) {
    return FALinkTarget(
      type: FALinkTargetType.scraps,
      url: url,
      username: scrapsMatch.group(1),
    );
  }

  final userRegex = RegExp(
    r'^(?:https?://(?:www\.)?furaffinity\.net)?/user/([a-zA-Z0-9\-_.~]+)/?$',
  );
  final userMatch = userRegex.firstMatch(urlToMatch);
  if (userMatch != null) {
    return FALinkTarget(
      type: FALinkTargetType.user,
      url: url,
      username: userMatch.group(1),
    );
  }

  final journalRegex = RegExp(
    r'^(?:https?://(?:www\.)?furaffinity\.net)?/(?:journals/([a-zA-Z0-9\-_.~]+)|journal/(\d+))(?:/.*)?(?:#.*)?$',
  );
  final journalMatch = journalRegex.firstMatch(urlToMatch);
  if (journalMatch != null) {
    final username = journalMatch.group(1);
    final journalId = journalMatch.group(2);
    return FALinkTarget(
      type: username != null
          ? FALinkTargetType.journalUser
          : FALinkTargetType.journal,
      url: url,
      username: username,
      journalId: journalId,
    );
  }

  final viewRegex = RegExp(
    r'^(?:https?://(?:www\.)?(?:furaffinity|fxfuraffinity)\.net)?/view/(\d+)(?:/.*)?(?:#.*)?$',
  );
  final viewMatch = viewRegex.firstMatch(urlToMatch);
  if (viewMatch != null) {
    return FALinkTarget(
      type: FALinkTargetType.submission,
      url: url,
      submissionId: viewMatch.group(1),
    );
  }

  return FALinkTarget(
    type: FALinkTargetType.external,
    url: url,
  );
}
