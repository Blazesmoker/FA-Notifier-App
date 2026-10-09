import 'package:material_ui/material_ui.dart';
import 'package:fanotifier/features/ads/domain/fa_ad_models.dart';
import 'package:fanotifier/shared/fa/domain/notifications.dart';
import 'package:fanotifier/shared/fa/domain/notification_counts.dart';
import 'package:fanotifier/features/notifications/domain/fa_notification_models.dart';
import 'package:fanotifier/features/notifications/domain/fa_notifications_page_snapshot.dart';
import 'package:fanotifier/features/notifications/domain/fa_notifications_page_parser_state.dart';
import 'package:fanotifier/features/notifications/domain/fa_notifications_repository.dart';
import 'package:fanotifier/shared/fa/domain/fa_notification_state_port.dart';
import 'package:fanotifier/features/notifications/domain/notification_shout_merge_policy.dart';
import 'package:fanotifier/features/notifications/domain/notification_removal_outcome.dart';
import 'package:fanotifier/core/fa/fa_media_auth.dart';

class FaNotificationsController with ChangeNotifier implements FaNotificationStatePort {
  FaNotificationsController({
    required this._repository,
  });

  final FaNotificationsRepository _repository;
  Future<void>? _fetchNotificationsInFlight;
  int _pageGeneration = 0;
  int _adContextGeneration = 0;
  bool _adSessionClosing = false;
  final Map<String, Future<String?>> _previewFutures = {};
  int _previewSessionRevision = -1;
  Future<List<Shout>>? _shoutsEnrichmentInFlight;
  String? _shoutsEnrichmentInFlightSignature;
  String? _shoutsEnrichmentInFlightUsername;
  Future<NotificationRemovalOutcome>? _notificationMutationInFlight;

  FaNotificationsRepository get _notificationsRepository => _repository;

  bool isLoading = true;
  bool hasFetched = false;
  FaAdPageMetadata? adPageMetadata;
  bool? documentSfwEnabled;
  int adPageRevision = 0;
  @override
  NotificationCounts? listCounts;
  @override
  int? listFetchedAtMilliseconds;
  @override
  int? listStartedAtMilliseconds;
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
  bool _shoutsPageNeedsProfile = false;
  bool get shoutsPageNeedsProfile => _shoutsPageNeedsProfile;
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
    if (hasValidLatestCountsSnapshot && !counts.isDifferentFrom(latestCounts)) {
      return;
    }
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

  void setAdSessionClosing(bool closing) {
    if (_adSessionClosing == closing) return;
    _adSessionClosing = closing;
    _adContextGeneration++;
    adPageMetadata = null;
    adPageRevision++;
    notifyListeners();
  }

  void clearAllNotifications() {
    _previewFutures.clear();
    _pageGeneration++;
    _adContextGeneration++;
    _fetchNotificationsInFlight = null;
    isLoading = false;
    hasFetched = true;
    errorMessage = null;
    sections.clear();
    listCounts = null;
    listFetchedAtMilliseconds = null;
    listStartedAtMilliseconds = null;
    adPageMetadata = null;
    documentSfwEnabled = null;
    adPageRevision++;
    notifyListeners();
  }

  void setItemChecked(NotificationItem item, bool checked) {
    item.isChecked = checked;
    notifyListeners();
  }

  /// Fetch and parse notifications from /msg/others/.
  @override
  Future<void> fetchNotifications({bool? sfwEnabled}) {
    final generation = _pageGeneration;
    final activeRemoval = _notificationMutationInFlight;
    if (activeRemoval != null) {
      return activeRemoval.then<void>((_) async {
        if (generation != _pageGeneration) {
          return;
        }
        await fetchNotifications(sfwEnabled: sfwEnabled);
      });
    }
    final activeFetch = _fetchNotificationsInFlight;
    if (activeFetch != null) {
      if (sfwEnabled == null) return activeFetch;
      return activeFetch.then<void>((_) async {
        if (generation != _pageGeneration || documentSfwEnabled == sfwEnabled) {
          return;
        }
        await fetchNotifications(sfwEnabled: sfwEnabled);
      });
    }

    late final Future<void> fetch;
    fetch = _fetchNotificationsNow(sfwEnabled: sfwEnabled).whenComplete(() {
      if (identical(_fetchNotificationsInFlight, fetch)) {
        _fetchNotificationsInFlight = null;
      }
    });
    _fetchNotificationsInFlight = fetch;
    return fetch;
  }

  Future<void> _fetchNotificationsNow({bool? sfwEnabled}) async {
    final generation = _pageGeneration;
    final adGeneration = _adContextGeneration;
    isLoading = true;
    errorMessage = null;
    hasValidLatestCountsSnapshot = false;
    notifyListeners();

    try {
      final parserState = FaNotificationsPageParserState(
        linkUsername: linkUsername,
        displayName: displayName,
      );
      final fetchedMessageBarCounts = <String, int>{};
      late final FaNotificationsPageSnapshot pageSnapshot;
      try {
        pageSnapshot = await _notificationsRepository.fetchNotifications(
          messageBarCounts: fetchedMessageBarCounts,
          parserState: parserState,
          sfwEnabled: sfwEnabled,
          canAcceptAdContext: () => !_adSessionClosing &&
              adGeneration == _adContextGeneration && generation == _pageGeneration,
        );
      } finally {
        if (generation == _pageGeneration) {
          if (parserState.hasValidLatestCountsSnapshot) {
            messageBarCounts = fetchedMessageBarCounts;
            latestCounts = parserState.latestCounts!;
            hasValidLatestCountsSnapshot = true;
          }
          final parsedTopBarNotifications = parserState.latestTopBarNotifications;
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
      }

      if (generation != _pageGeneration) {
        return;
      }

      final prevEnrichedSig = _shoutsEnrichedSignature;
      final prevById = (prevEnrichedSig != null)
          ? _shoutMergePolicy.captureById(sections)
          : <String, NotificationItem>{};

      sections = pageSnapshot.sections.toList();
      _notificationsRepository.refreshSubmissionPreviews();
      _previewFutures.clear();
      listCounts = parserState.latestCounts;
      listFetchedAtMilliseconds = DateTime.now().millisecondsSinceEpoch;
      listStartedAtMilliseconds = pageSnapshot.startedAtMilliseconds;
      adPageMetadata = !_adSessionClosing && adGeneration == _adContextGeneration
          ? pageSnapshot.ads
          : null;
      documentSfwEnabled = pageSnapshot.documentSfwEnabled;
      adPageRevision++;
      _shoutsPageNeedsProfile = _shoutMergePolicy.needsProfileContent(sections);
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

      if (generation != _pageGeneration) {
        return;
      }
      errorMessage = e.toString();
      debugPrint("[fetchNotifications] Error: $e\n$st");
    } finally {


      if (generation == _pageGeneration) {
        isLoading = false;
        hasFetched = true;
        notifyListeners();
      }
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

  Future<NotificationRemovalOutcome> removeSelected(int sectionIndex) {
    final activeRemoval = _notificationMutationInFlight;
    if (activeRemoval != null) return activeRemoval;
    if (sectionIndex < 0 || sectionIndex >= sections.length) {
      return Future.value(NotificationRemovalOutcome.failed);
    }

    final section = sections[sectionIndex];
    final selectedItems =
        section.items.where((item) => item.isChecked).toList();
    if (selectedItems.isEmpty) {
      return Future.value(NotificationRemovalOutcome.nothingSelected);
    }
    final itemIds = selectedItems
        .map((item) => item.id.trim())
        .where((id) => id.isNotEmpty)
        .toSet();
    if (itemIds.length != selectedItems.length) {
      return Future.value(NotificationRemovalOutcome.failed);
    }

    final selection = _NotificationRemovalSelection(
      sectionTitle: section.title,
      formAction: section.formAction,
      itemIds: itemIds,
    );
    late final Future<NotificationRemovalOutcome> removal;
    removal = _performSelectedRemoval(selection).whenComplete(() {
      if (identical(_notificationMutationInFlight, removal)) {
        _notificationMutationInFlight = null;
      }
    });
    _notificationMutationInFlight = removal;
    return removal;
  }

  Future<NotificationRemovalOutcome> _performSelectedRemoval(
    _NotificationRemovalSelection originalSelection,
  ) async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();
    try {
      final activeFetch = _fetchNotificationsInFlight;
      if (activeFetch != null) {
        await activeFetch;
      }
      errorMessage = null;

      final selection = _currentSelection(originalSelection);
      if (selection.itemIds.isEmpty) {
        return NotificationRemovalOutcome.success;
      }

      final mutationSession =
          await _notificationsRepository.createMutationSession();
      final requestOutcome = await _notificationsRepository.removeSelected(
        mutationSession,
        sectionTitle: selection.sectionTitle,
        formAction: selection.formAction,
        itemIds: selection.itemIds,
      );
      switch (requestOutcome) {
        case NotificationRemovalRequestOutcome.accepted:
          _applySelectedRemoval(selection);
          return NotificationRemovalOutcome.success;
        case NotificationRemovalRequestOutcome.rejected:
          errorMessage = 'Fur Affinity rejected the notification removal.';
          return NotificationRemovalOutcome.failed;
        case NotificationRemovalRequestOutcome.indeterminate:
          return await _reconcileSelectedRemoval(selection);
      }
    } catch (error, stackTrace) {
      errorMessage = error.toString();
      debugPrint('[removeSelected] $error\n$stackTrace');
      return NotificationRemovalOutcome.failed;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<NotificationRemovalOutcome> _reconcileSelectedRemoval(
    _NotificationRemovalSelection selection,
  ) async {
    await _fetchNotificationsNow();
    if (errorMessage != null ||
        !hasValidLatestCountsSnapshot ||
        (currentUsername ?? '').trim().isEmpty) {
      errorMessage = 'Notification removal could not be confirmed.';
      return NotificationRemovalOutcome.indeterminate;
    }
    if (_currentSelection(selection).itemIds.isEmpty) {
      return NotificationRemovalOutcome.success;
    }
    errorMessage = 'Notification removal could not be confirmed.';
    return NotificationRemovalOutcome.indeterminate;
  }

  _NotificationRemovalSelection _currentSelection(
    _NotificationRemovalSelection selection,
  ) {
    final sectionIndex = sections.indexWhere(
      (section) =>
          section.title.trim().toLowerCase() ==
          selection.sectionTitle.trim().toLowerCase(),
    );
    if (sectionIndex == -1) {
      return selection.copyWith(itemIds: const <String>{});
    }
    final section = sections[sectionIndex];
    final currentIds = section.items.map((item) => item.id).toSet();
    return selection.copyWith(
      formAction: section.formAction,
      itemIds: selection.itemIds.intersection(currentIds),
    );
  }

  void _applySelectedRemoval(_NotificationRemovalSelection selection) {
    final sectionIndex = sections.indexWhere(
      (section) =>
          section.title.trim().toLowerCase() ==
          selection.sectionTitle.trim().toLowerCase(),
    );
    if (sectionIndex == -1) return;
    sections[sectionIndex]
        .items
        .removeWhere((item) => selection.itemIds.contains(item.id));
    if (sections[sectionIndex].items.isEmpty) {
      sections.removeAt(sectionIndex);
    }
    if (selection.sectionTitle.toLowerCase().contains('shouts')) {
      final signature = _shoutMergePolicy.signatureFromSections(sections);
      _shoutsLightSignature = signature;
      if (signature.isEmpty) {
        _shoutsEnrichedSignature = null;
        shoutsEnriched = false;
      } else if (_shoutsEnrichedSignature != null) {
        _shoutsEnrichedSignature = signature;
      }
    }
    notifyListeners();
  }

  /// Nuke an entire section.
  Future<NotificationRemovalOutcome> nukeSection(int sectionIndex) {
    final activeMutation = _notificationMutationInFlight;
    if (activeMutation != null) return activeMutation;
    if (sectionIndex < 0 || sectionIndex >= sections.length) {
      return Future.value(NotificationRemovalOutcome.failed);
    }
    final section = sections[sectionIndex];
    final itemIds = section.items.map((item) => item.id.trim()).toSet();
    if (itemIds.isEmpty || itemIds.contains('')) {
      return Future.value(NotificationRemovalOutcome.nothingSelected);
    }
    final selection = _NotificationRemovalSelection(
      sectionTitle: section.title,
      formAction: section.formAction,
      itemIds: itemIds,
    );
    late final Future<NotificationRemovalOutcome> mutation;
    mutation = _performSectionNuke(selection).whenComplete(() {
      if (identical(_notificationMutationInFlight, mutation)) {
        _notificationMutationInFlight = null;
      }
    });
    _notificationMutationInFlight = mutation;
    return mutation;
  }

  Future<NotificationRemovalOutcome> _performSectionNuke(
    _NotificationRemovalSelection originalSelection,
  ) async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();
    try {
      final activeFetch = _fetchNotificationsInFlight;
      if (activeFetch != null) await activeFetch;
      final selection = _currentSelection(originalSelection);
      if (selection.itemIds.isEmpty) {
        return NotificationRemovalOutcome.success;
      }
      final mutationSession =
          await _notificationsRepository.createMutationSession();
      final requestOutcome = await _notificationsRepository.nukeSection(
        mutationSession,
        sectionTitle: selection.sectionTitle,
        formAction: selection.formAction,
      );
      switch (requestOutcome) {
        case NotificationRemovalRequestOutcome.accepted:
          _applySelectedRemoval(selection);
          return NotificationRemovalOutcome.success;
        case NotificationRemovalRequestOutcome.rejected:
          errorMessage = 'Fur Affinity rejected the section removal.';
          return NotificationRemovalOutcome.failed;
        case NotificationRemovalRequestOutcome.indeterminate:
          return await _reconcileSelectedRemoval(selection);
      }
    } catch (e, st) {
      errorMessage = e.toString();
      debugPrint("[nukeSection] $e\n$st");
      return NotificationRemovalOutcome.failed;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }



  /// Remove all notifications in all sections.
  Future<NotificationRemovalOutcome> removeAllNotifications() {
    final activeMutation = _notificationMutationInFlight;
    if (activeMutation != null) return activeMutation;
    final selections = sections
        .where((section) =>
            section.items.isNotEmpty &&
            _notificationsRepository.canRemoveAllFromSection(section.title))
        .map(
          (section) => _NotificationRemovalSelection(
            sectionTitle: section.title,
            formAction: section.formAction,
            itemIds: section.items.map((item) => item.id.trim()).toSet(),
          ),
        )
        .where((selection) =>
            selection.itemIds.isNotEmpty && !selection.itemIds.contains(''))
        .toList();
    if (selections.isEmpty) {
      return Future.value(NotificationRemovalOutcome.nothingSelected);
    }
    late final Future<NotificationRemovalOutcome> mutation;
    mutation = _performRemoveAll(selections).whenComplete(() {
      if (identical(_notificationMutationInFlight, mutation)) {
        _notificationMutationInFlight = null;
      }
    });
    _notificationMutationInFlight = mutation;
    return mutation;
  }

  Future<NotificationRemovalOutcome> _performRemoveAll(
    List<_NotificationRemovalSelection> originalSelections,
  ) async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();
    try {
      final activeFetch = _fetchNotificationsInFlight;
      if (activeFetch != null) await activeFetch;
      final selections = originalSelections
          .map(_currentSelection)
          .where((selection) => selection.itemIds.isNotEmpty)
          .toList();
      if (selections.isEmpty) {
        return NotificationRemovalOutcome.success;
      }
      final mutationSession =
          await _notificationsRepository.createMutationSession();
      for (final selection in selections) {
        final requestOutcome =
            await _notificationsRepository.removeAllFromSection(
          mutationSession,
          sectionTitle: selection.sectionTitle,
          formAction: selection.formAction,
          itemIds: selection.itemIds,
        );
        if (requestOutcome == NotificationRemovalRequestOutcome.accepted) {
          _applySelectedRemoval(selection);
          continue;
        }
        if (requestOutcome == NotificationRemovalRequestOutcome.rejected) {
          errorMessage = 'Fur Affinity rejected removing all notifications.';
          return NotificationRemovalOutcome.failed;
        }
        return await _reconcileAllRemovals(selections);
      }
      return NotificationRemovalOutcome.success;
    } catch (e, st) {
      errorMessage = e.toString();
      debugPrint("[removeAllNotifications] $e\n$st");
      return NotificationRemovalOutcome.failed;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<NotificationRemovalOutcome> _reconcileAllRemovals(
    List<_NotificationRemovalSelection> selections,
  ) async {
    await _fetchNotificationsNow();
    if (errorMessage != null ||
        !hasValidLatestCountsSnapshot ||
        (currentUsername ?? '').trim().isEmpty) {
      errorMessage = 'Removing all notifications could not be confirmed.';
      return NotificationRemovalOutcome.indeterminate;
    }
    if (selections.every(
      (selection) => _currentSelection(selection).itemIds.isEmpty,
    )) {
      return NotificationRemovalOutcome.success;
    }
    errorMessage = 'Removing all notifications could not be confirmed.';
    return NotificationRemovalOutcome.indeterminate;
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
    _shoutsPageNeedsProfile = false;
    final sig = _shoutMergePolicy.signatureFromItems(updated);
    _shoutsLightSignature = sig;
    _shoutsEnrichedSignature = sig;
    notifyListeners();
  }

  Future<List<Shout>> enrichShoutsFromProfileIfNeeded({bool force = false}) {
    final signature = _shoutsLightSignature;
    final myUsername = (currentUsername ?? '').trim();
    final existing = _shoutsEnrichmentInFlight;
    if (existing != null) {
      if (_shoutsEnrichmentInFlightSignature == signature &&
          _shoutsEnrichmentInFlightUsername == myUsername) {
        return existing;
      }
      return existing.then<List<Shout>>(
        (_) => enrichShoutsFromProfileIfNeeded(force: force),
      );
    }

    late final Future<List<Shout>> enrichment;
    enrichment = _enrichShoutsFromProfile(
      force: force,
      signature: signature,
      myUsername: myUsername,
    ).whenComplete(() {
      if (identical(_shoutsEnrichmentInFlight, enrichment)) {
        _shoutsEnrichmentInFlight = null;
        _shoutsEnrichmentInFlightSignature = null;
        _shoutsEnrichmentInFlightUsername = null;
      }
    });
    _shoutsEnrichmentInFlight = enrichment;
    _shoutsEnrichmentInFlightSignature = signature;
    _shoutsEnrichmentInFlightUsername = myUsername;
    return enrichment;
  }

  Future<List<Shout>> _enrichShoutsFromProfile({
    required bool force,
    required String signature,
    required String myUsername,
  }) async {
    final idx = _shoutMergePolicy.shoutSectionIndex(sections);
    if (idx == -1) return const <Shout>[];
    if (!force && shoutsEnriched) {
      return _shoutMergePolicy.shoutsFromItems(sections[idx].items);
    }

    if (myUsername.isEmpty) return const <Shout>[];

    final profileShouts =
        await fetchProfileShouts(myUsername, forceRefresh: true);

    final currentIndex = _shoutMergePolicy.shoutSectionIndex(sections);
    if (currentIndex == -1 ||
        (currentUsername ?? '').trim() != myUsername) {
      return const <Shout>[];
    }
    final currentItems = sections[currentIndex].items;
    if (_shoutsLightSignature != signature) {
      return _shoutMergePolicy.shoutsFromItems(currentItems);
    }
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
    final sessionRevision = FaMediaAuth.changes.value;
    if (_previewSessionRevision != sessionRevision) {
      _previewFutures.clear();
      _previewSessionRevision = sessionRevision;
    }
    return _previewFutures.putIfAbsent(
      submissionId,
      () => _notificationsRepository.fetchSubmissionPreview(submissionId),
    );
  }
}

class _NotificationRemovalSelection {
  const _NotificationRemovalSelection({
    required this.sectionTitle,
    required this.formAction,
    required this.itemIds,
  });

  final String sectionTitle;
  final String formAction;
  final Set<String> itemIds;

  _NotificationRemovalSelection copyWith({
    String? formAction,
    Set<String>? itemIds,
  }) {
    return _NotificationRemovalSelection(
      sectionTitle: sectionTitle,
      formAction: formAction ?? this.formAction,
      itemIds: itemIds ?? this.itemIds,
    );
  }
}
