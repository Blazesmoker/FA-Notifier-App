class FaContentBlockSnapshot {
  const FaContentBlockSnapshot({required this.blockedTags});

  final Set<String> blockedTags;
}

class FaContentBlockData {
  const FaContentBlockData({
    this.tags = const [],
    this.tagsKnown = false,
    this.snapshot,
  });

  final List<String> tags;
  final bool tagsKnown;
  final FaContentBlockSnapshot? snapshot;

  bool isBlockedBy(FaContentBlockSnapshot? currentSnapshot) {
    final blockedTags = (currentSnapshot ?? snapshot)?.blockedTags;
    if (blockedTags == null || blockedTags.isEmpty) return false;
    if (!tagsKnown) return true;
    return tags.any(blockedTags.contains);
  }
}
