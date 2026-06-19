import 'dart:async';
import 'dart:collection';
import 'package:flutter/material.dart';
import 'package:FANotifier/shared/widgets/fa_network_image.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:FANotifier/core/preferences/sfw_mode_preference.dart';
import 'package:FANotifier/features/submissions/data/favorite_service.dart';
import 'package:FANotifier/features/submissions/data/submissions_service.dart';
import 'package:FANotifier/features/submissions/domain/submission_fetch_models.dart';
import 'package:FANotifier/features/submissions/domain/submission_image_group.dart';
import 'package:FANotifier/features/submissions/domain/submissions_listing_parse_result.dart';
import 'package:FANotifier/shared/widgets/PulsatingLoadingIndicator.dart';
import 'package:FANotifier/shared/widgets/heart_animation_optimized.dart';
import 'package:FANotifier/features/submissions/presentation/openpost.dart';
import 'package:FANotifier/features/submissions/domain/submission_list_item.dart';
import 'package:FANotifier/shared/fa/fa_system_message_parser.dart';
import 'package:FANotifier/shared/widgets/fa_thumbnail_display.dart';
import 'package:FANotifier/shared/widgets/fa_unavailable_screen.dart';

class SubmissionsScreen extends StatefulWidget {
  const SubmissionsScreen({Key? key}) : super(key: key);

  @override
  State<SubmissionsScreen> createState() => SubmissionsScreenState();
}

class SubmissionsScreenState extends State<SubmissionsScreen>
    with AutomaticKeepAliveClientMixin<SubmissionsScreen> {
  final FavoriteService _favoriteService = FavoriteService();
  final SfwModePreference _sfwModePreference = SfwModePreference();
  late final SubmissionsService _submissionsService;

  /// All submissions grouped by date
  final List<DateImageGroup> _dateGroups = [];
  final List<Map<String, dynamic>> _flatSubmissionsList = [];
  /// Combined list for the ListView
  final List<SubmissionListItem> _listItems = [];
  /// Scroll controller for pagination
  final ScrollController _scrollController = ScrollController();
  bool _isLoading = false;
  bool _hasMore = true;

  bool _isError = false;
  String? _errorMessage;


  String? _nextPageUrl;
  /// Base URL for delete/nuke actions
  String? _baseSubmissionsUrl;
  /// For multi‐select & deletion
  bool _selectionMode = false;
  final Set<String> _selectedSubmissions = {};
  /// Concurrency management for fetching HQ/fav data
  final Queue<SubmissionQueueItem> _submissionQueue = Queue();
  static const int _maxConcurrentFetches = 5;
  int _activeFetches = 0;
  // Debounce for favorites
  final Map<String, Timer> _debounceTimers = {};
  final Map<String, bool> _pendingFavStates = {};
  bool _sfwEnabled = true;
  /// Track visible tile indices
  final Set<int> _visibleTileIndices = {};


  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _submissionsService = SubmissionsService();
    _scrollController.addListener(_scrollListenerForPagination);
    _loadSfwEnabled().then((_) => _refreshSubmissions());


  }

  @override
  void dispose() {
    _scrollController.removeListener(_scrollListenerForPagination);
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> scrollToTop({bool animate = true}) async {
    if (!_scrollController.hasClients) return;
    if (!animate) {
      _scrollController.jumpTo(0);
      return;
    }
    await _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _loadSfwEnabled() async {
    final sfwEnabled = await _sfwModePreference.loadSfwEnabled();
    setState(() {
      _sfwEnabled = sfwEnabled;
    });
  }

  void _onWillPop() {
    if (_selectionMode) {
      setState(() {
        _selectionMode = false;
        _selectedSubmissions.clear();
      });
    }
  }

  void _scrollListenerForPagination() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent * 0.9 &&
        !_isLoading &&
        _hasMore) {
      _fetchSubmissions();
    }
  }

  Future<void> refreshSubmissionsManually() => _refreshSubmissions();

  Future<void> _refreshSubmissions() async {
    setState(() {
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
    });
    await _fetchSubmissions();
  }

  Future<void> _fetchSubmissions() async {
    if (_isLoading || !_hasMore) return;
    setState(() {
      _isLoading = true;
      _isError = false;
      _errorMessage = null;
    });

    try {
      if (!await _submissionsService.hasAuthCookies()) {
        debugPrint('[Submissions] Missing FA cookies, abort fetch.');
        setState(() { _isLoading = false; _isError = true; _errorMessage = 'Not logged in'; });
        return;
      }

      final parsed = await _submissionsService.fetchListing(
        nextPageUrl: _nextPageUrl,
        baseSubmissionsUrl: _baseSubmissionsUrl,
        sfwEnabled: _sfwEnabled,
      );
      _applyListing(parsed);

      WidgetsBinding.instance.addPostFrameCallback((_) {
        for (var item in _flatSubmissionsList) {
          final url = item['thumbnailUrl'];
          if (url != null) {
            faNetworkImageProvider(url).then((provider) {
              if (mounted) precacheImage(provider, context);
            });
          }
        }
      });

      setState(() => _isLoading = false);
    } catch (e) {
      debugPrint('[Submissions] fetch failed: $e');
      setState(() {
        _isLoading = false;
        _isError = true;
        _errorMessage = e.toString();
      });

    }
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
    for (int g = 0; g < _dateGroups.length; g++) {
      final group = _dateGroups[g];
      _listItems.add(SubmissionListItem.header(
        group.dateLabel,
        showDividerAfterGroup: !isLastGroup(g),
      ));
      final imageRows = _splitImagesIntoRows(group.images);
      for (int r = 0; r < imageRows.length; r++) {
        final row = imageRows[r];
        for (final img in row) {
          img['flatIndex'] = flatIndexCounter++;
          _flatSubmissionsList.add(img);
        }
        final isLastRowInThisGroup = (r == imageRows.length - 1);
        _listItems.add(SubmissionListItem.row(
          row,
          showDividerAfterGroup: isLastRowInThisGroup && !isLastGroup(g),
        ));
      }
    }
  }

  List<List<Map<String, dynamic>>> _splitImagesIntoRows(List<Map<String, dynamic>> images) {
    final rows = <List<Map<String, dynamic>>>[];
    final normalQueue = <Map<String, dynamic>>[];

    for (var img in images) {
      if (_isWide(img)) {
        if (normalQueue.isNotEmpty) {
          rows.add([normalQueue.removeAt(0), img]);
        } else {
          rows.add([img]);
        }
      } else {
        normalQueue.add(img);
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

  bool _isWide(Map<String, dynamic> img) {
    final w = img['width'] as double;
    final h = img['height'] as double;
    return (w / h) > 1.5;
  }

  Future<void> _onNukePressed() async {
    final confirmNuke = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nuke All?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Do you really want to remove all of your submissions?'),
            if (_sfwEnabled)
              Column(
                children: [
                  const SizedBox(height: 8),
                  Text(
                    "When SFW mode is enabled, all NSFW posts will be nuked too - even if you haven't seen them yet.",
                    style: TextStyle(color: Color(0xFFE09321)),
                  ),
                ],
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Nuke'),
          ),
        ],
      ),
    );
    if (confirmNuke != true) return;

    try {
      final success = await _submissionsService.nukeSubmissions(
        baseSubmissionsUrl: _baseSubmissionsUrl,
      );
      if (success) {
        setState(() {
          _dateGroups.clear();
          _flatSubmissionsList.clear();
          _listItems.clear();
          _submissionQueue.clear();
        });
        debugPrint('[Submissions] Nuke success => cleared UI');
      } else {
        debugPrint('[Submissions] Nuke failed');
      }
    } catch (e) {
      debugPrint('[Submissions] Nuke error => $e');
    }
  }

  Future<void> _onTrashIconPressed() async {
    if (!_selectionMode) {
      setState(() => _selectionMode = true);
      return;
    }
    if (_selectedSubmissions.isEmpty) {
      setState(() => _selectionMode = false);
      return;
    }

    final confirmDelete = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Selected?'),
        content: const Text('Are you sure you want to delete the selected submissions?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('CANCEL'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('DELETE'),
          ),
        ],
      ),
    );
    if (confirmDelete == true) {
      await _deleteSelectedSubmissions();
    }
    setState(() {
      _selectionMode = false;
      _selectedSubmissions.clear();
    });
  }

  Future<void> _deleteSelectedSubmissions() async {
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
        setState(() {
          for (final group in _dateGroups) {
            group.images.removeWhere((img) => _selectedSubmissions.contains(img['uniqueNumber']));
          }
          _dateGroups.removeWhere((g) => g.images.isEmpty);
          _rebuildListItemsFromDateGroups();
        });
        debugPrint('[Submissions] Successfully deleted selected from UI.');
      } else {
        debugPrint('[Submissions] Deletion request failed');
      }
    } catch (e) {
      debugPrint('[Submissions] Error deleting => $e');
    }
  }

  void onTileVisibilityChanged(int flatListIndex, bool isVisible) {
    if (flatListIndex < 0 || flatListIndex >= _flatSubmissionsList.length) return;
    final item = _flatSubmissionsList[flatListIndex];
    if (isVisible) {
      _visibleTileIndices.add(flatListIndex);
      final existingHqUrl = item['hqUrl'] as String? ?? '';
      if (item['detailFetched'] == true || existingHqUrl.isNotEmpty) return;
      if (item['detailFetchQueued'] == true || item['detailFetchInProgress'] == true) return;
      debugPrint('[Submissions] Visibility => queue HQ for item #$flatListIndex / ${item['postUrl']}');
      item['detailFetchQueued'] = true;
      _submissionQueue.add(SubmissionQueueItem(
        indexInFlatList: flatListIndex,
        postUrl: item['postUrl'],
      ));
      _startNextFetches();
    } else {
      _visibleTileIndices.remove(flatListIndex);
      _submissionQueue.removeWhere((qItem) => qItem.indexInFlatList == flatListIndex);
      if (item['detailFetched'] == true || item['detailFetchInProgress'] == true) return;
      item['detailFetchQueued'] = false;
    }
  }

  void _startNextFetches() {
    while (_activeFetches < _maxConcurrentFetches && _submissionQueue.isNotEmpty) {
      final qItem = _submissionQueue.removeFirst();
      final postUrl = qItem.postUrl;
      _activeFetches++;

      debugPrint('[Submissions] Start detail fetch for $postUrl. Active: $_activeFetches');

      if (qItem.indexInFlatList >= 0 && qItem.indexInFlatList < _flatSubmissionsList.length) {
        final item = _flatSubmissionsList[qItem.indexInFlatList];
        item['detailFetchQueued'] = false;
        item['detailFetchInProgress'] = true;
      }

      _submissionsService.fetchSubmissionData(postUrl).then((data) {
        debugPrint('[Submissions] Fetched detail => $postUrl');
        if (!mounted) return;
        setState(() {
          if (qItem.indexInFlatList >= 0 && qItem.indexInFlatList < _flatSubmissionsList.length) {
            final item = _flatSubmissionsList[qItem.indexInFlatList];
            item['hqUrl'] = data.hqUrl;
            item['isFav'] = data.isFav;
            item['initialIsFav'] = data.isFav;
            item['favUrl'] = data.favUrl;
            item['unfavUrl'] = data.unfavUrl;
            item['detailFetched'] = true;
          }
        });
      }).catchError((err) {
        debugPrint('[Submissions] Error fetching detail => $err');
      }).whenComplete(() {
        if (qItem.indexInFlatList >= 0 && qItem.indexInFlatList < _flatSubmissionsList.length) {
          final item = _flatSubmissionsList[qItem.indexInFlatList];
          item['detailFetchInProgress'] = false;
        }
        _activeFetches--;
        debugPrint('[Submissions] Done detail fetch for $postUrl. Active: $_activeFetches');
        _startNextFetches();
      });
    }
  }

  Widget _buildRefreshableBody() {
    final errorMessage = _errorMessage;
    if (_isError &&
        errorMessage != null &&
        isFaMaintenanceOrUnavailableText(errorMessage)) {
      return FaUnavailableScreen(
        message: errorMessage,
        onRefresh: _refreshSubmissions,
      );
    }

    if (_isLoading && _listItems.isEmpty) {
      return ListView(
        physics: AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(height: 220),
          Center(child: CircularProgressIndicator()),
        ],
      );
    }

    if (_isError && _listItems.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          const SizedBox(height: 220),
          const Center(child: Text('Network error. Pull to retry.')),
          if (_errorMessage != null) const SizedBox(height: 8),
          if (_errorMessage != null)
            Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12),
            ),
        ],
      );
    }

    if (_listItems.isEmpty) {
      return ListView(
        physics: AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(height: 220),
          Center(child: Text('No new submissions found.')),
        ],
      );
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
      controller: _scrollController,
      itemCount: _listItems.length + (_isLoading ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _listItems.length) {
          // loading indicator at the bottom
          return const Padding(
            padding: EdgeInsets.only(top: 168.0),
            child: Center(
              child: PulsatingLoadingIndicator(
                size: 88.0,
                assetPath: 'assets/icons/fathemed.png',
              ),
            ),
          );
        }
        final item = _listItems[index];
        if (item.isHeader) {
          return _buildDateHeader(item.dateLabel!, item.showDividerAfterGroup);
        } else {
          return _buildRowWidget(item.rowImages!, item.showDividerAfterGroup);
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return PopScope(
      canPop: !_selectionMode,
      onPopInvokedWithResult: (bool didPop, dynamic result) {
        if (didPop) return;
        if (_selectionMode) {
          _onWillPop();
        }
      },
      child: Scaffold(
        drawerEnableOpenDragGesture: false,
        appBar: AppBar(
          centerTitle: true,
          title: const Text('Submissions'),
          actions: [
            if (_selectionMode)
              IconButton(
                icon: const Icon(Icons.library_add_check, size: 22),
                tooltip: 'Select All',
                onPressed: _toggleAllSelection,
              ),
            IconButton(
              icon: Icon(_selectionMode ? Icons.delete_forever : Icons.delete),
              tooltip: 'Delete Selected',
              onPressed: _onTrashIconPressed,
            ),
            IconButton(
              icon: const Icon(Icons.block, color: Color(0xFFE09321)),
              tooltip: 'Nuke All',
              onPressed: _onNukePressed,
            ),
          ],
        ),
        body: RefreshIndicator(
          color: const Color(0xFFE09321),
          backgroundColor: Colors.black,
          onRefresh: _refreshSubmissions,
          child: _buildRefreshableBody(),
        ),
      ),
    );
  }


  Widget _buildDateHeader(String dateLabel, bool showDividerAfterGroup) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
          child: Text(
            dateLabel,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }

  Widget _buildRowWidget(List<Map<String, dynamic>> rowImages, bool showDivider) {
    final screenHeight = MediaQuery.of(context).size.height;
    final maxHeight = screenHeight * 0.4;

    Widget rowWidget;
    if (rowImages.length == 1) {
      rowWidget = _buildSingleImage(rowImages[0], maxHeight);
    } else {
      rowWidget = _buildDoubleImage(rowImages[0], rowImages[1], maxHeight);
    }

    final rowWithSpacing = Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: rowWidget,
    );

    if (showDivider) {
      return Column(
        children: [
          rowWithSpacing,
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 2.0),
            child: Divider(color: Colors.grey, thickness: 0.3, height: 12),
          ),
        ],
      );
    } else {
      return rowWithSpacing;
    }
  }

  void _toggleAllSelection() {
    setState(() {
      if (_selectedSubmissions.length == _flatSubmissionsList.length) {
        _selectedSubmissions.clear(); // Deselect all
      } else {
        _selectedSubmissions.clear();
        for (var item in _flatSubmissionsList) {
          _selectedSubmissions.add(item['uniqueNumber']);
        }
      }
    });
  }

  Widget _buildSingleImage(Map<String, dynamic> data, double maxHeight) {
    final aspect = (data['width'] as double) / (data['height'] as double);
    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth - 16.0;
        double w = totalWidth;
        double h = w / aspect;
        if (h > maxHeight) {
          final scale = maxHeight / h;
          w *= scale;
          h = maxHeight;
        }
        return Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 2.0),
              child: _FavImageTile(
                item: data,
                width: w,
                height: h,
                selectionMode: _selectionMode,
                isSelected: _selectedSubmissions.contains(data['uniqueNumber']),
                onToggleSelection: _toggleSelection,
                onOpenSubmission: _openSubmission,
                onToggleFavorite: _handleToggleFavorite,
                onVisibilityChanged: onTileVisibilityChanged,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDoubleImage(Map<String, dynamic> left, Map<String, dynamic> right, double maxHeight) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final margin = 4.0;
        final rowWidth = constraints.maxWidth - margin * 2;
        final aLeft = (left['width'] as double) / (left['height'] as double);
        final aRight = (right['width'] as double) / (right['height'] as double);
        final ratio = aRight / aLeft;
        double wLeft = rowWidth / (1.0 + ratio);
        double wRight = rowWidth - wLeft;
        double h = wLeft / aLeft;
        if (h > maxHeight) {
          final scale = maxHeight / h;
          wLeft *= scale;
          wRight *= scale;
          h = maxHeight;
        }
        return Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            _FavImageTile(
              item: left,
              width: wLeft,
              height: h,
              selectionMode: _selectionMode,
              isSelected: _selectedSubmissions.contains(left['uniqueNumber']),
              onToggleSelection: _toggleSelection,
              onOpenSubmission: _openSubmission,
              onToggleFavorite: _handleToggleFavorite,
              onVisibilityChanged: onTileVisibilityChanged,
            ),
            SizedBox(width: margin),
            _FavImageTile(
              item: right,
              width: wRight,
              height: h,
              selectionMode: _selectionMode,
              isSelected: _selectedSubmissions.contains(right['uniqueNumber']),
              onToggleSelection: _toggleSelection,
              onOpenSubmission: _openSubmission,
              onToggleFavorite: _handleToggleFavorite,
              onVisibilityChanged: onTileVisibilityChanged,
            ),
          ],
        );
      },
    );
  }

  void _toggleSelection(String uniqueNumber) {
    setState(() {
      if (_selectedSubmissions.contains(uniqueNumber)) {
        _selectedSubmissions.remove(uniqueNumber);
      } else {
        _selectedSubmissions.add(uniqueNumber);
      }
    });
  }

  void _openSubmission(Map<String, dynamic> item) {
    Navigator.push(
      context,
      OpenPost.route(
        imageUrl:
            (item['hqUrl'] != null && (item['hqUrl'] as String).isNotEmpty)
                ? item['hqUrl'] as String
                : item['thumbnailUrl'] as String,
        uniqueNumber: item['uniqueNumber'] as String,
      ),
    );
  }

  void _handleToggleFavorite(Map<String, dynamic> item, bool newValue) {
    final favUrl = item['favUrl'] as String? ?? '';
    final unfavUrl = item['unfavUrl'] as String? ?? '';
    final uniqueNumber = item['uniqueNumber'] as String;

    // Immediately reflect the change in UI
    setState(() {
      item['isFav'] = newValue;
    });

    // Debounce so we don't hammer the server if user toggles many quickly
    _pendingFavStates[uniqueNumber] = newValue;
    _debounceTimers[uniqueNumber]?.cancel();

    _debounceTimers[uniqueNumber] = Timer(const Duration(seconds: 3), () async {
      final finalState = _pendingFavStates.remove(uniqueNumber);
      _debounceTimers.remove(uniqueNumber);
      if (finalState == null) return;

      final urlToSend = finalState ? favUrl : unfavUrl;
      if (urlToSend.isEmpty) {
        debugPrint('[Submissions] No link found to do fav/unfav.');
        return;
      }

      final success = await _favoriteService.executePostWithRetry(urlToSend);
      if (!success && mounted) {
        debugPrint('[Submissions] Fav/unfav failed => revert');
        setState(() {
          item['isFav'] = !finalState;
        });
        return;
      }

      await _refreshLinksAfterPost(item);
    });
  }

  Future<void> _refreshLinksAfterPost(Map<String, dynamic> item) async {
    try {
      final newData = await _submissionsService.fetchSubmissionData(
        item['postUrl'],
      );
      if (!mounted) return;
      setState(() {
        item['isFav'] = newData.isFav;
        item['favUrl'] = newData.favUrl;
        item['unfavUrl'] = newData.unfavUrl;
        item['hqUrl'] = newData.hqUrl;
      });
    } catch (e) {
      debugPrint('[Submissions] Error refreshing => $e');
    }
  }
}

class _FavImageTile extends StatelessWidget {
  final Map<String, dynamic> item;
  final double width;
  final double height;
  final bool selectionMode;
  final bool isSelected;
  final Function(String uniqueNumber) onToggleSelection;
  final Function(Map<String, dynamic> item) onOpenSubmission;
  final Function(Map<String, dynamic> item, bool newVal) onToggleFavorite;
  final Function(int flatListIndex, bool isVisible) onVisibilityChanged;

  const _FavImageTile({
    Key? key,
    required this.item,
    required this.width,
    required this.height,
    required this.selectionMode,
    required this.isSelected,
    required this.onToggleSelection,
    required this.onOpenSubmission,
    required this.onToggleFavorite,
    required this.onVisibilityChanged,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final thumbnailUrl = item['thumbnailUrl'] as String;
    final hqUrl = item['hqUrl'] as String? ?? '';
    final bool isFav = item['isFav'] as bool? ?? false;
    final bool wasInitiallyFav = item['initialIsFav'] as bool? ?? false;
    final uniqueNumber = item['uniqueNumber'] as String;
    final int flatIndex = item['flatIndex'] as int? ?? -1;
    final displayUrl = hqUrl.isNotEmpty ? hqUrl : thumbnailUrl;
    final String? rating = item['rating'] as String?;
    final String? title = item['title'] as String?;
    final String? author = item['author'] as String?;
    final String? authorProfileUrl = item['authorProfileUrl'] as String?;

    return VisibilityDetector(
      key: Key('visible-$uniqueNumber'),
      onVisibilityChanged: (info) {

        onVisibilityChanged(flatIndex, info.visibleFraction > 0.2);
      },
      child: GestureDetector(
        onTap: () {
          if (selectionMode) {
            onToggleSelection(uniqueNumber);
          } else {
            onOpenSubmission(item);
          }
        },
        onLongPress: () {
          onToggleFavorite(item, !isFav);
        },
        child: SizedBox(
          width: width,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: width,
                height: height,
                child: HeartAnimationOptimized(
                  isFavorite: isFav,
                  wasInitiallyFavorited: wasInitiallyFav,
                  containerWidth: width,
                  containerHeight: height,
                  onToggle: (val) => onToggleFavorite(item, val),
                  child: FaThumbnailOutline(
                    rating: rating,
                    borderRadius: 8.0,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8.0),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          const ColoredBox(color: Color(0xFF2C2C2C)),
                          Stack(
                            fit: StackFit.expand,
                            children: [
                              // --- THUMBNAIL (always visible) ---
                              FaNetworkImage(
                                thumbnailUrl,
                                fit: BoxFit.cover,
                                errorBuilder: (ctx, err, stack) => Container(
                                  color: Colors.grey[300],
                                  child: const Icon(Icons.error, color: Colors.red),
                                ),
                              ),

                              // --- FULL IMAGE (fades in on top) ---
                              _FadeInNetworkImage(
                                imageUrl: displayUrl,
                                fit: BoxFit.cover,
                                duration: const Duration(milliseconds: 300),
                                errorBuilder: (ctx, err, stack) => Container(
                                  color: Colors.grey[300],
                                  child: const Icon(Icons.error, color: Colors.red),
                                ),
                              ),
                            ],
                          ),
                          if (selectionMode)
                            Container(
                              color: isSelected ? Colors.black54 : Colors.black26,
                              child: Center(
                                child: Icon(
                                  isSelected
                                      ? Icons.check_circle
                                      : Icons.radio_button_unchecked,
                                  color: Colors.white,
                                  size: 30,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              FaThumbnailCaption(
                maxWidth: width,
                title: title,
                author: author,
                authorProfileUrl: authorProfileUrl,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
class _FadeInNetworkImage extends StatefulWidget {
  final String imageUrl;
  final BoxFit fit;
  final Duration duration;
  final Widget Function(BuildContext, Object, StackTrace?) errorBuilder;

  const _FadeInNetworkImage({
    required this.imageUrl,
    required this.fit,
    required this.duration,
    required this.errorBuilder,
  });

  @override
  State<_FadeInNetworkImage> createState() => _FadeInNetworkImageState();
}

class _FadeInNetworkImageState extends State<_FadeInNetworkImage> {
  bool _visible = false;

  @override
  Widget build(BuildContext context) {
    return FaNetworkImage(
      widget.imageUrl,
      fit: widget.fit,
      frameBuilder: (context, child, frame, _) {
        if (frame != null && !_visible) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() => _visible = true);
            }
          });
        }

        return AnimatedOpacity(
          opacity: _visible ? 1.0 : 0.0,
          duration: widget.duration,
          curve: Curves.easeOut,
          child: child,
        );
      },
      errorBuilder: widget.errorBuilder,
    );
  }
}
