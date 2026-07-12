import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import 'package:FANotifier/core/preferences/sfw_mode_preference.dart';
import 'package:FANotifier/features/submissions/data/favorite_service.dart';
import 'package:FANotifier/features/submissions/data/submissions_service.dart';
import 'package:FANotifier/features/submissions/domain/submission_fetch_models.dart';
import 'package:FANotifier/features/submissions/domain/submission_image_group.dart';
import 'package:FANotifier/features/submissions/domain/submission_list_item.dart';
import 'package:FANotifier/features/submissions/domain/submissions_listing_parse_result.dart';

class SubmissionsController extends ChangeNotifier {
  SubmissionsController({
    SubmissionsService? submissionsService,
    FavoriteService? favoriteService,
    SfwModePreference? sfwModePreference,
  })  : _submissionsService = submissionsService ?? SubmissionsService(),
        _favoriteService = favoriteService ?? FavoriteService(),
        _sfwModePreference = sfwModePreference ?? SfwModePreference();

  static const int _maxConcurrentFetches = 5;

  final SubmissionsService _submissionsService;
  final FavoriteService _favoriteService;
  final SfwModePreference _sfwModePreference;
  final List<DateImageGroup> _dateGroups = [];
  final List<Map<String, dynamic>> _flatSubmissionsList = [];
  final List<SubmissionListItem> _listItems = [];
  final Set<String> _selectedSubmissions = {};
  final Queue<SubmissionQueueItem> _submissionQueue = Queue();
  final Map<String, Timer> _debounceTimers = {};
  final Map<String, bool> _pendingFavStates = {};
  final Set<int> _visibleTileIndices = {};

  bool _isLoading = false;
  bool _hasMore = true;
  bool _isError = false;
  String? _errorMessage;
  String? _nextPageUrl;
  String? _baseSubmissionsUrl;
  bool _selectionMode = false;
  int _activeFetches = 0;
  bool _sfwEnabled = true;
  bool _disposed = false;

  UnmodifiableListView<Map<String, dynamic>> get flatSubmissionsList =>
      UnmodifiableListView(_flatSubmissionsList);
  UnmodifiableListView<SubmissionListItem> get listItems =>
      UnmodifiableListView(_listItems);
  UnmodifiableSetView<String> get selectedSubmissions =>
      UnmodifiableSetView(_selectedSubmissions);
  bool get isLoading => _isLoading;
  bool get hasMore => _hasMore;
  bool get isError => _isError;
  String? get errorMessage => _errorMessage;
  bool get selectionMode => _selectionMode;
  bool get sfwEnabled => _sfwEnabled;

  Future<void> loadSfwEnabled() async {
    _sfwEnabled = await _sfwModePreference.loadSfwEnabled();
    _notifyChanged();
  }

  Future<void> refresh({required VoidCallback onListingApplied}) async {
    _dateGroups.clear();
    _flatSubmissionsList.clear();
    _listItems.clear();
    _hasMore = true;
    _nextPageUrl = null;
    _submissionQueue.clear();
    _activeFetches = 0;
    _baseSubmissionsUrl = null;
    _isError = false;
    _errorMessage = null;
    _notifyChanged();
    await fetchSubmissions(onListingApplied: onListingApplied);
  }

  Future<void> fetchSubmissions({required VoidCallback onListingApplied}) async {
    if (_isLoading || !_hasMore) return;
    _isLoading = true;
    _isError = false;
    _errorMessage = null;
    _notifyChanged();

    try {
      if (!await _submissionsService.hasAuthCookies()) {
        debugPrint('[Submissions] Missing FA cookies, abort fetch.');
        _isLoading = false;
        _isError = true;
        _errorMessage = 'Not logged in';
        _notifyChanged();
        return;
      }

      final parsed = await _submissionsService.fetchListing(
        nextPageUrl: _nextPageUrl,
        baseSubmissionsUrl: _baseSubmissionsUrl,
        sfwEnabled: _sfwEnabled,
      );
      _applyListing(parsed);
      onListingApplied();
      _isLoading = false;
      _notifyChanged();
    } catch (e) {
      debugPrint('[Submissions] fetch failed: $e');
      _isLoading = false;
      _isError = true;
      _errorMessage = e.toString();
      _notifyChanged();
    }
  }

  void enterSelectionMode() {
    _selectionMode = true;
    _notifyChanged();
  }

  void exitSelectionMode() {
    _selectionMode = false;
    _selectedSubmissions.clear();
    _notifyChanged();
  }

  void toggleAllSelection() {
    if (_selectedSubmissions.length == _flatSubmissionsList.length) {
      _selectedSubmissions.clear();
    } else {
      _selectedSubmissions.clear();
      for (var item in _flatSubmissionsList) {
        _selectedSubmissions.add(item['uniqueNumber']);
      }
    }
    _notifyChanged();
  }

  void toggleSelection(String uniqueNumber) {
    if (_selectedSubmissions.contains(uniqueNumber)) {
      _selectedSubmissions.remove(uniqueNumber);
    } else {
      _selectedSubmissions.add(uniqueNumber);
    }
    _notifyChanged();
  }

  Future<void> nukeSubmissions() async {
    try {
      final success = await _submissionsService.nukeSubmissions(
        baseSubmissionsUrl: _baseSubmissionsUrl,
      );
      if (success) {
        _dateGroups.clear();
        _flatSubmissionsList.clear();
        _listItems.clear();
        _submissionQueue.clear();
        _notifyChanged();
        debugPrint('[Submissions] Nuke success => cleared UI');
      } else {
        debugPrint('[Submissions] Nuke failed');
      }
    } catch (e) {
      debugPrint('[Submissions] Nuke error => $e');
    }
  }

  Future<void> deleteSelectedSubmissions() async {
    try {
      if (!await _submissionsService.hasAuthCookies()) {
        debugPrint('[Submissions] Missing cookies, cannot delete.');
        return;
      }

      final success = await _submissionsService.deleteSubmissions(
        baseSubmissionsUrl: _baseSubmissionsUrl,
        submissionIds: _selectedSubmissions,
      );

      if (success) {
        for (final group in _dateGroups) {
          group.images.removeWhere(
              (img) => _selectedSubmissions.contains(img['uniqueNumber']));
        }
        _dateGroups.removeWhere((group) => group.images.isEmpty);
        _rebuildListItemsFromDateGroups();
        _notifyChanged();
        debugPrint('[Submissions] Successfully deleted selected from UI.');
      } else {
        debugPrint('[Submissions] Deletion request failed');
      }
    } catch (e) {
      debugPrint('[Submissions] Error deleting => $e');
    }
  }

  void onTileVisibilityChanged(int flatListIndex, bool isVisible) {
    if (flatListIndex < 0 ||
        flatListIndex >= _flatSubmissionsList.length) {
      return;
    }
    final item = _flatSubmissionsList[flatListIndex];
    if (isVisible) {
      _visibleTileIndices.add(flatListIndex);
      final existingHqUrl = item['hqUrl'] as String? ?? '';
      if (item['detailFetched'] == true || existingHqUrl.isNotEmpty) return;
      if (item['detailFetchQueued'] == true ||
          item['detailFetchInProgress'] == true) {
        return;
      }
      debugPrint(
          '[Submissions] Visibility => queue HQ for item #$flatListIndex / ${item['postUrl']}');
      item['detailFetchQueued'] = true;
      _submissionQueue.add(SubmissionQueueItem(
        indexInFlatList: flatListIndex,
        postUrl: item['postUrl'],
      ));
      _startNextFetches();
    } else {
      _visibleTileIndices.remove(flatListIndex);
      _submissionQueue
          .removeWhere((item) => item.indexInFlatList == flatListIndex);
      if (item['detailFetched'] == true ||
          item['detailFetchInProgress'] == true) {
        return;
      }
      item['detailFetchQueued'] = false;
    }
  }

  void handleToggleFavorite(Map<String, dynamic> item, bool newValue) {
    final favUrl = item['favUrl'] as String? ?? '';
    final unfavUrl = item['unfavUrl'] as String? ?? '';
    final uniqueNumber = item['uniqueNumber'] as String;

    item['isFav'] = newValue;
    _notifyChanged();

    _pendingFavStates[uniqueNumber] = newValue;
    _debounceTimers[uniqueNumber]?.cancel();

    _debounceTimers[uniqueNumber] =
        Timer(const Duration(seconds: 3), () async {
      final finalState = _pendingFavStates.remove(uniqueNumber);
      _debounceTimers.remove(uniqueNumber);
      if (finalState == null) return;

      final urlToSend = finalState ? favUrl : unfavUrl;
      if (urlToSend.isEmpty) {
        debugPrint('[Submissions] No link found to do fav/unfav.');
        return;
      }

      final success = await _favoriteService.executePostWithRetry(urlToSend);
      if (!success && !_disposed) {
        debugPrint('[Submissions] Fav/unfav failed => revert');
        item['isFav'] = !finalState;
        _notifyChanged();
        return;
      }

      await _refreshLinksAfterPost(item);
    });
  }

  void _applyListing(SubmissionsListingParseResult parsed) {
    _baseSubmissionsUrl ??= parsed.baseSubmissionsUrl;
    _dateGroups.addAll(parsed.dateGroups);
    _rebuildListItemsFromDateGroups();
    _hasMore = parsed.nextPageUrl != null;
    _nextPageUrl = parsed.nextPageUrl;
  }

  void _rebuildListItemsFromDateGroups() {
    _flatSubmissionsList.clear();
    _listItems.clear();
    bool isLastGroup(int groupIndex) => groupIndex == _dateGroups.length - 1;
    int flatIndexCounter = 0;
    for (int groupIndex = 0;
        groupIndex < _dateGroups.length;
        groupIndex++) {
      final group = _dateGroups[groupIndex];
      _listItems.add(SubmissionListItem.header(
        group.dateLabel,
        showDividerAfterGroup: !isLastGroup(groupIndex),
      ));
      final imageRows = _splitImagesIntoRows(group.images);
      for (int rowIndex = 0; rowIndex < imageRows.length; rowIndex++) {
        final row = imageRows[rowIndex];
        for (final image in row) {
          image['flatIndex'] = flatIndexCounter++;
          _flatSubmissionsList.add(image);
        }
        final isLastRowInThisGroup = rowIndex == imageRows.length - 1;
        _listItems.add(SubmissionListItem.row(
          row,
          showDividerAfterGroup:
              isLastRowInThisGroup && !isLastGroup(groupIndex),
        ));
      }
    }
  }

  List<List<Map<String, dynamic>>> _splitImagesIntoRows(
      List<Map<String, dynamic>> images) {
    final rows = <List<Map<String, dynamic>>>[];
    final normalQueue = <Map<String, dynamic>>[];

    for (var image in images) {
      if (_isWide(image)) {
        if (normalQueue.isNotEmpty) {
          rows.add([normalQueue.removeAt(0), image]);
        } else {
          rows.add([image]);
        }
      } else {
        normalQueue.add(image);
      }
    }
    while (normalQueue.length >= 2) {
      rows.add([normalQueue.removeAt(0), normalQueue.removeAt(0)]);
    }
    if (normalQueue.isNotEmpty) {
      rows.add([normalQueue.removeAt(0)]);
    }
    return rows;
  }

  bool _isWide(Map<String, dynamic> image) {
    final width = image['width'] as double;
    final height = image['height'] as double;
    return (width / height) > 1.5;
  }

  void _startNextFetches() {
    while (_activeFetches < _maxConcurrentFetches &&
        _submissionQueue.isNotEmpty) {
      final queueItem = _submissionQueue.removeFirst();
      final postUrl = queueItem.postUrl;
      _activeFetches++;

      debugPrint(
          '[Submissions] Start detail fetch for $postUrl. Active: $_activeFetches');

      if (queueItem.indexInFlatList >= 0 &&
          queueItem.indexInFlatList < _flatSubmissionsList.length) {
        final item = _flatSubmissionsList[queueItem.indexInFlatList];
        item['detailFetchQueued'] = false;
        item['detailFetchInProgress'] = true;
      }

      _submissionsService.fetchSubmissionData(postUrl).then((data) {
        debugPrint('[Submissions] Fetched detail => $postUrl');
        if (_disposed) return;
        if (queueItem.indexInFlatList >= 0 &&
            queueItem.indexInFlatList < _flatSubmissionsList.length) {
          final item = _flatSubmissionsList[queueItem.indexInFlatList];
          item['hqUrl'] = data.hqUrl;
          item['isFav'] = data.isFav;
          item['initialIsFav'] = data.isFav;
          item['favUrl'] = data.favUrl;
          item['unfavUrl'] = data.unfavUrl;
          item['detailFetched'] = true;
        }
        _notifyChanged();
      }).catchError((err) {
        debugPrint('[Submissions] Error fetching detail => $err');
      }).whenComplete(() {
        if (queueItem.indexInFlatList >= 0 &&
            queueItem.indexInFlatList < _flatSubmissionsList.length) {
          final item = _flatSubmissionsList[queueItem.indexInFlatList];
          item['detailFetchInProgress'] = false;
        }
        _activeFetches--;
        debugPrint(
            '[Submissions] Done detail fetch for $postUrl. Active: $_activeFetches');
        _startNextFetches();
      });
    }
  }

  Future<void> _refreshLinksAfterPost(Map<String, dynamic> item) async {
    try {
      final newData =
          await _submissionsService.fetchSubmissionData(item['postUrl']);
      if (_disposed) return;
      item['isFav'] = newData.isFav;
      item['favUrl'] = newData.favUrl;
      item['unfavUrl'] = newData.unfavUrl;
      item['hqUrl'] = newData.hqUrl;
      _notifyChanged();
    } catch (e) {
      debugPrint('[Submissions] Error refreshing => $e');
    }
  }

  void _notifyChanged() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
