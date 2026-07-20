import 'package:flutter/material.dart';
import 'package:fanotifier/shared/fa/domain/notifications.dart';
import 'package:fanotifier/shared/fa/domain/notification_counts.dart';
import 'package:fanotifier/features/notifications/domain/fa_notification_models.dart';
import 'package:fanotifier/features/notifications/domain/fa_notifications_page_snapshot.dart';
import 'package:fanotifier/features/notifications/domain/fa_notifications_page_parser_state.dart';
import 'package:fanotifier/features/notifications/domain/fa_notifications_repository.dart';
import 'package:fanotifier/shared/fa/domain/fa_notification_state_port.dart';
import 'package:fanotifier/features/notifications/domain/notification_shout_merge_policy.dart';

/// Centralized service for notifications.
class FANotificationService with ChangeNotifier implements FaNotificationStatePort {
  FANotificationService({
    required FaNotificationsRepository repository,
  }) : _repository = repository;

  final FaNotificationsRepository _repository;

  FaNotificationsRepository get _notificationsRepository => _repository;

  bool isLoading = true;
  bool hasFetched = false;
  @override
  String? errorMessage;
  List<NotificationSection> sections = [];
  String? currentUsername;
  String? linkUsername;
  String? currentUsernameFromLink;

  static const NotificationShoutMergePolicy _shoutMergePolicy =
      NotificationShoutMergePolicy();
  String? displayName;
  String? username;
  bool shoutsEnriched = false;
  String _shoutsLightSignature = '';
  String? _shoutsEnrichedSignature;
  String get shoutsLightSignature => _shoutsLightSignature;
  String? get shoutsEnrichedSignature => _shoutsEnrichedSignature;

  bool get shoutsNeedEnrich {
    return _shoutMergePolicy.needsEnrichment(
      sections: sections,
      lightSignature: _shoutsLightSignature,
      enrichedSignature: _shoutsEnrichedSignature,
    );
  }
  /// Stores counts from the message-bar (e.g., {"W": 1, "F": 2, "J": 3}).
  Map<String, int> messageBarCounts = {};
  @override
  bool hasValidLatestCountsSnapshot = false;
  @override
  NotificationCounts latestCounts = NotificationCounts(
    submissions: 0,
    watches: 0,
    comments: 0,
    favorites: 0,
    journals: 0,
    notes: 0,
  );
  Notifications latestTopBarNotifications = Notifications(
    submissions: '0',
    watches: '0',
    journals: '0',
    notes: '0',
    comments: '0',
    favorites: '0',
    registeredUsersOnline: '0',
  );

  @override
  void applyTopbarCounts(NotificationCounts counts) {
    hasValidLatestCountsSnapshot = true;
    latestCounts = counts;
    _setMessageBarCount('S', counts.submissions);
    _setMessageBarCount('W', counts.watches);
    _setMessageBarCount('C', counts.comments);
    _setMessageBarCount('F', counts.favorites);
    _setMessageBarCount('J', counts.journals);
    _setMessageBarCount('N', counts.notes);
    latestTopBarNotifications = Notifications(
      submissions: '${counts.submissions}',
      watches: '${counts.watches}',
      journals: '${counts.journals}',
      notes: '${counts.notes}',
      comments: '${counts.comments}',
      favorites: '${counts.favorites}',
      registeredUsersOnline: latestTopBarNotifications.registeredUsersOnline,
    );
    notifyListeners();
  }

  void _setMessageBarCount(String key, int value) {
    if (value > 0) {
      messageBarCounts[key] = value;
    } else {
      messageBarCounts.remove(key);
    }
  }

  void clearAllNotifications() {
    isLoading = false;
    hasFetched = true;
    errorMessage = null;
    sections.clear();
    notifyListeners();
  }

  void setItemChecked(NotificationItem item, bool checked) {
    item.isChecked = checked;
    notifyListeners();
  }

  /// Fetch and parse notifications from /msg/others/.
  @override
  Future<void> fetchNotifications() async {
    isLoading = true;
    errorMessage = null;
    hasValidLatestCountsSnapshot = false;
    notifyListeners();

    try {
      final parserState = FaNotificationsPageParserState(
        linkUsername: linkUsername,
        displayName: displayName,
      );
      late final FaNotificationsPageSnapshot pageSnapshot;
      try {
        pageSnapshot = await _notificationsRepository.fetchNotifications(
          messageBarCounts: messageBarCounts,
          parserState: parserState,
        );
      } finally {
        if (parserState.hasValidLatestCountsSnapshot) {
          latestCounts = parserState.latestCounts!;
          hasValidLatestCountsSnapshot = true;
        }
        final parsedTopBarNotifications =
            parserState.latestTopBarNotifications;
        if (parsedTopBarNotifications != null) {
          latestTopBarNotifications = parsedTopBarNotifications;
        }
        if (parserState.hasParsedCurrentUsername) {
          currentUsername = parserState.currentUsername;
          currentUsernameFromLink = currentUsername;
        }
        linkUsername = parserState.linkUsername;
        displayName = parserState.displayName;
      }

      final prevEnrichedSig = _shoutsEnrichedSignature;
      final prevById = (prevEnrichedSig != null)
          ? _shoutMergePolicy.captureById(sections)
          : <String, NotificationItem>{};

      sections = pageSnapshot.sections.toList();
      debugPrint("[fetchNotifications] Parsed sections: "
          "${sections.map((s) => s.title).toList()}");
      // Shouts signature is used to decide if we need enrichment when the user opens the tab.
      final newSig = _shoutMergePolicy.signatureFromSections(sections);
      _shoutsLightSignature = newSig;

      // If we already enriched these exact shout IDs before, preserve the enriched data
      // across background refreshes without re-fetching.
      if (newSig.isNotEmpty && prevEnrichedSig != null && prevEnrichedSig == newSig && prevById.isNotEmpty) {
        final shoutSectionIndex =
            _shoutMergePolicy.shoutSectionIndex(sections);
        if (shoutSectionIndex != -1) {
          sections[shoutSectionIndex].items =
              _shoutMergePolicy.mergePreviousEnrichedItems(
            existingItems: sections[shoutSectionIndex].items,
            previousItemsById: prevById,
          );
        }
        shoutsEnriched = true;
        _shoutsEnrichedSignature = newSig;
      } else if (newSig.isNotEmpty &&
          _shoutMergePolicy.appearsEnriched(sections)) {
        // Classic msg/others already includes shout bodies/avatars.
        shoutsEnriched = true;
        _shoutsEnrichedSignature = newSig;
      } else {
        shoutsEnriched = false;
      }


    } catch (e, st) {

      errorMessage = e.toString();
      debugPrint("[fetchNotifications] Error: $e\n$st");
    } finally {


      isLoading = false;
      hasFetched = true;
      notifyListeners();
    }
  }


  Future<List<Shout>> fetchProfileShouts(
    String myUsername, {
    bool forceRefresh = false,
  }) {
    return _notificationsRepository.fetchProfileShouts(
      myUsername,
      forceRefresh: forceRefresh,
    );
  }

  Future<List<Shout>> fetchMsgCenterShouts() {
    return _notificationsRepository.fetchMsgCenterShouts();
  }

  Future<List<Map<String, dynamic>>> fetchMsgOthersShouts() {
    return _notificationsRepository.fetchMsgOthersShouts();
  }

  Future<void> removeSelected(int sectionIndex) async {
    if (sectionIndex < 0 || sectionIndex >= sections.length) return;
    List<NotificationItem> selectedItems = sections[sectionIndex].items.where((item) => item.isChecked).toList();
    if (selectedItems.isEmpty) return;
    isLoading = true;
    notifyListeners();
    try {
      final mutationSession =
          await _notificationsRepository.createMutationSession();
      String tLower = sections[sectionIndex].title.toLowerCase();
      final statusCode = await _notificationsRepository.removeSelected(
        mutationSession,
        sectionTitle: sections[sectionIndex].title,
        formAction: sections[sectionIndex].formAction,
        itemIds: selectedItems.map((item) => item.id),
      );
      if (tLower.contains('shouts')) {
        if (statusCode == 200 || statusCode == 302) {
          sections[sectionIndex].items.removeWhere((x) => x.isChecked);
          if (sections[sectionIndex].items.isEmpty) {
            sections.removeAt(sectionIndex);
          }
          notifyListeners();
        } else {
          throw Exception('Failed to remove selected shouts.');
        }
      } else {
        if (statusCode == 302) {
          sections[sectionIndex].items.removeWhere((x) => x.isChecked);
          if (sections[sectionIndex].items.isEmpty) {
            sections.removeAt(sectionIndex);
          }
          notifyListeners();
        } else {
          throw Exception('Failed to remove selected items.');
        }
      }
    } catch (e, st) {
      errorMessage = e.toString();
      debugPrint("[removeSelected] $e\n$st");
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  /// Nuke an entire section.
  Future<void> nukeSection(int sectionIndex) async {
    if (sectionIndex < 0 || sectionIndex >= sections.length) return;
    isLoading = true;
    notifyListeners();
    try {
      final mutationSession =
          await _notificationsRepository.createMutationSession();
      final statusCode = await _notificationsRepository.nukeSection(
        mutationSession,
        sectionTitle: sections[sectionIndex].title,
        formAction: sections[sectionIndex].formAction,
      );
      if (statusCode == 302) {
        sections[sectionIndex].items.clear();
        sections.removeAt(sectionIndex);
        notifyListeners();
      } else {
        throw Exception('Failed to nuke items.');
      }
    } catch (e, st) {
      errorMessage = e.toString();
      debugPrint("[nukeSection] $e\n$st");
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }



  /// Remove all notifications in all sections.
  Future<void> removeAllNotifications() async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();
    try {
      final mutationSession =
          await _notificationsRepository.createMutationSession();
      for (int i = sections.length - 1; i >= 0; i--) {
        List<NotificationItem> items = sections[i].items;
        if (items.isEmpty) continue;
        if (!_notificationsRepository.canRemoveAllFromSection(
          sections[i].title,
        )) {
          continue;
        }
        final statusCode =
            await _notificationsRepository.removeAllFromSection(
          mutationSession,
          sectionTitle: sections[i].title,
          formAction: sections[i].formAction,
          itemIds: items.map((item) => item.id),
        );
        if (statusCode == 302) {
          sections[i].items.clear();
          sections.removeAt(i);
        } else {
          throw Exception('Failed to remove all from section: ${sections[i].title}');
        }
      }
    } catch (e, st) {
      errorMessage = e.toString();
      debugPrint("[removeAllNotifications] $e\n$st");
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  /// Update the shouts section with new data.
  void updateShouts(List<dynamic> newShouts) {
    int idx = _shoutMergePolicy.shoutSectionIndex(sections);
    if (idx == -1) return;
    final updated = _shoutMergePolicy.updatedItems(
      existingItems: sections[idx].items,
      newShouts: newShouts,
    );
    sections[idx].items = updated;
    shoutsEnriched = true;
    final sig = _shoutMergePolicy.signatureFromItems(updated);
    _shoutsLightSignature = sig;
    _shoutsEnrichedSignature = sig;
    notifyListeners();
  }

  Future<List<Shout>> enrichShoutsFromProfileIfNeeded({bool force = false}) async {
    final idx = _shoutMergePolicy.shoutSectionIndex(sections);
    if (idx == -1) return const <Shout>[];
    if (!force && shoutsEnriched) {
      return _shoutMergePolicy.shoutsFromItems(sections[idx].items);
    }

    final my = (currentUsername ?? '').trim();
    if (my.isEmpty) return const <Shout>[];

    final profileShouts = await fetchProfileShouts(my, forceRefresh: true);

    final currentItems = sections[idx].items;
    final enriched = _shoutMergePolicy.mergeWithProfile(
      currentItems: currentItems,
      profileShouts: profileShouts,
    );

    updateShouts(enriched);
    return enriched;
  }

  /// Toggle selection of all items in a section.
  void toggleSelectAll(int sectionIndex) {
    if (sectionIndex < 0 || sectionIndex >= sections.length) return;
    bool shouldSelectAll = sections[sectionIndex].items.any((item) => !item.isChecked);
    for (var item in sections[sectionIndex].items) {
      item.isChecked = shouldSelectAll;
    }
    notifyListeners();
  }

  /// Mark/unmark a single shout by ID.
  void setShoutCheckedById(String id, bool isChecked) {
    int idx = _shoutMergePolicy.shoutSectionIndex(sections);
    if (idx == -1) return;
    for (var item in sections[idx].items) {
      if (item.id == id) {
        item.isChecked = isChecked;
        notifyListeners();
        break;
      }
    }
  }



  Future<String?> fetchAvatarUrl(String username) {
    return _notificationsRepository.fetchAvatarUrl(username);
  }

  Future<String?> fetchSubmissionPreview(String submissionId) {
    return _notificationsRepository.fetchSubmissionPreview(
      submissionId,
    );
  }
}
