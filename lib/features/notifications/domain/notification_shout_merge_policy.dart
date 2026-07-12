import 'package:FANotifier/features/notifications/domain/fa_notification_models.dart';

class NotificationShoutMergePolicy {
  const NotificationShoutMergePolicy();

  int shoutSectionIndex(List<NotificationSection> sections) {
    return sections.indexWhere(
      (section) => section.title.toLowerCase().contains('shouts'),
    );
  }

  bool needsEnrichment({
    required List<NotificationSection> sections,
    required String lightSignature,
    required String? enrichedSignature,
  }) {
    if (shoutSectionIndex(sections) == -1) return false;
    if (appearsEnriched(sections)) return false;
    if (lightSignature.isEmpty) return false;
    return enrichedSignature != lightSignature;
  }

  String signatureFromSections(List<NotificationSection> sections) {
    final index = shoutSectionIndex(sections);
    if (index == -1) return '';
    return signatureFromItems(sections[index].items);
  }

  String signatureFromItems(List<NotificationItem> items) {
    final ids = items
        .map((item) => item.id.trim())
        .where((id) => id.isNotEmpty)
        .toList(growable: false);
    return ids.join(',');
  }

  Map<String, NotificationItem> captureById(
    List<NotificationSection> sections,
  ) {
    final index = shoutSectionIndex(sections);
    if (index == -1) return <String, NotificationItem>{};
    final itemsById = <String, NotificationItem>{};
    for (final item in sections[index].items) {
      itemsById[item.id] = item;
    }
    return itemsById;
  }

  List<NotificationItem> mergePreviousEnrichedItems({
    required List<NotificationItem> existingItems,
    required Map<String, NotificationItem> previousItemsById,
  }) {
    final rebuilt = <NotificationItem>[];
    for (final item in existingItems) {
      final previous = previousItemsById[item.id];
      final mergedContent = previous != null && previous.content.isNotEmpty
          ? previous.content
          : item.content;
      final mergedUsername =
          previous != null && (previous.username ?? '').isNotEmpty
              ? previous.username
              : item.username;
      final mergedLinkUsername =
          previous != null && (previous.linkUsername ?? '').isNotEmpty
              ? previous.linkUsername
              : item.linkUsername;
      final mergedAvatarUrl =
          previous != null && (previous.avatarUrl ?? '').isNotEmpty
              ? previous.avatarUrl
              : item.avatarUrl;

      rebuilt.add(
        NotificationItem(
          id: item.id,
          content: mergedContent,
          username: mergedUsername,
          linkUsername: mergedLinkUsername,
          submissionId: item.submissionId,
          journalId: item.journalId,
          url: item.url,
          avatarUrl: mergedAvatarUrl,
          date: item.date,
          fullDate: item.fullDate,
          isChecked: item.isChecked,
        ),
      );
    }
    return rebuilt;
  }

  bool appearsEnriched(List<NotificationSection> sections) {
    final index = shoutSectionIndex(sections);
    if (index == -1) return false;
    final items = sections[index].items;
    if (items.isEmpty) return false;
    return items.any((item) {
      final removed = _isRemoved(item.content);
      if (removed) return false;
      return item.content.trim().isNotEmpty;
    });
  }

  List<NotificationItem> updatedItems({
    required List<NotificationItem> existingItems,
    required List<dynamic> newShouts,
  }) {
    final updated = <NotificationItem>[];
    for (var shout in newShouts) {
      NotificationItem? oldItem = existingItems.firstWhere(
        (item) => item.id == shout.id,
        orElse: () => NotificationItem(
          id: shout.id,
          content: shout.textContent,
          username: shout.nickname,
          linkUsername: shout.nicknameLink,
          avatarUrl: shout.avatarUrl,
          date: shout.postedAgo,
          fullDate: shout.postedTitle,
        ),
      );
      updated.add(
        NotificationItem(
          id: shout.id,
          content: shout.textContent,
          username: shout.nickname,
          linkUsername: shout.nicknameLink,
          avatarUrl: shout.avatarUrl,
          date: shout.postedAgo,
          fullDate: shout.postedTitle,
          isChecked: oldItem.isChecked,
        ),
      );
    }
    return updated;
  }

  List<Shout> shoutsFromItems(List<NotificationItem> items) {
    return items.map((item) {
      return Shout(
        id: item.id,
        nickname: item.username ?? '',
        nicknameLink: item.linkUsername ?? '',
        postedTitle: item.fullDate,
        avatarUrl: item.avatarUrl ?? '',
        postedAgo: item.date,
        textContent: item.content,
        isRemoved: _isRemoved(item.content),
        isChecked: item.isChecked,
      );
    }).toList();
  }

  List<Shout> mergeWithProfile({
    required List<NotificationItem> currentItems,
    required List<Shout> profileShouts,
  }) {
    final enriched = <Shout>[];
    for (final item in currentItems) {
      final removed = _isRemoved(item.content);
      final wantLink = (item.linkUsername ?? '').trim().toLowerCase();
      final wantName = (item.username ?? '').trim().toLowerCase();
      final wantStamp = _normalizeStamp(item.fullDate);

      Shout? match;
      if (!removed) {
        for (final profileShout in profileShouts) {
          final profileLink = profileShout.nicknameLink.trim().toLowerCase();
          final profileName = profileShout.nickname.trim().toLowerCase();
          final profileStamp = _normalizeStamp(profileShout.postedTitle);
          final linkMatches = wantLink.isNotEmpty && profileLink.isNotEmpty
              ? wantLink == profileLink
              : true;
          final nameMatches =
              wantName.isNotEmpty ? profileName == wantName : true;
          if (profileStamp == wantStamp && linkMatches && nameMatches) {
            match = profileShout;
            break;
          }
        }
      }

      enriched.add(
        Shout(
          id: item.id,
          nickname: item.username ?? '',
          nicknameLink: item.linkUsername ?? '',
          postedTitle: item.fullDate,
          avatarUrl: match?.avatarUrl ?? (item.avatarUrl ?? ''),
          postedAgo: item.date,
          textContent: match?.textContent ?? item.content,
          isRemoved: removed,
          isChecked: item.isChecked,
        ),
      );
    }
    return enriched;
  }

  String _normalizeStamp(String value) {
    return value
        .replaceFirst(RegExp(r'^on\s+', caseSensitive: false), '')
        .trim();
  }

  bool _isRemoved(String content) {
    return content.toLowerCase().contains('shout has been removed');
  }
}
