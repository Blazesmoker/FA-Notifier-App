import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as html_dom;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:visibility_detector/visibility_detector.dart';
import '../services/favorite_service.dart';
import '../widgets/PulsatingLoadingIndicator.dart';
import 'heart_animation_optimized.dart';
import 'openpost.dart';

/// Data model that represents a group of images posted on the same date.
class DateImageGroup {
  final String dateLabel;
  final List<Map<String, dynamic>> images;
  DateImageGroup({required this.dateLabel, required this.images});
}


class _ListItem {
  final bool isHeader;
  final String? dateLabel;
  final List<Map<String, dynamic>>? rowImages;
  final bool showDividerAfterGroup;

  _ListItem.header(this.dateLabel, {required this.showDividerAfterGroup})
      : isHeader = true,
        rowImages = null;

  _ListItem.row(this.rowImages, {required this.showDividerAfterGroup})
      : isHeader = false,
        dateLabel = null;
}

class SubmissionsScreen extends StatefulWidget {
  const SubmissionsScreen({Key? key}) : super(key: key);

  @override
  State<SubmissionsScreen> createState() => SubmissionsScreenState();
}

class SubmissionsScreenState extends State<SubmissionsScreen>
    with AutomaticKeepAliveClientMixin<SubmissionsScreen> {
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  final FavoriteService _favoriteService = FavoriteService();

  /// All submissions grouped by date
  final List<DateImageGroup> _dateGroups = [];
  final List<Map<String, dynamic>> _flatSubmissionsList = [];
  /// Combined list for the ListView
  final List<_ListItem> _listItems = [];
  /// Scroll controller for pagination
  final ScrollController _scrollController = ScrollController();
  bool _isLoading = false;
  bool _hasMore = true;
  String? _nextPageUrl;
  /// Base URL for delete/nuke actions
  String? _baseSubmissionsUrl;
  /// For multi‐select & deletion
  bool _selectionMode = false;
  final Set<String> _selectedSubmissions = {};
  /// Concurrency management for fetching HQ/fav data
  final Queue<_SubmissionQueueItem> _submissionQueue = Queue();
  static const int _maxConcurrentFetches = 5;
  int _activeFetches = 0;
  // Debounce for favorites
  final Map<String, Timer> _debounceTimers = {};
  final Map<String, bool> _pendingFavStates = {};
  bool _sfwEnabled = true;
  /// Track visible tile indices
  final Set<int> _visibleTileIndices = {};


  bool _isClassicStyle = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_scrollListenerForPagination);
    _loadSfwEnabled().then((_) => _refreshSubmissions());
  }

  @override
  void dispose() {
    _scrollController.removeListener(_scrollListenerForPagination);
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadSfwEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _sfwEnabled = prefs.getBool('sfwEnabled') ?? true;
    });
  }

  Future<void> _saveSfwEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('sfwEnabled', _sfwEnabled);
  }

  Future<bool> _onWillPop() async {
    if (_selectionMode) {
      setState(() {
        _selectionMode = false;
        _selectedSubmissions.clear();
      });
      return false;
    }
    return true;
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
    });
    await _fetchSubmissions();
  }

  Future<void> _fetchSubmissions() async {
    if (_isLoading || !_hasMore) return;
    setState(() => _isLoading = true);

    try {
      String cookieHeader = await _getAuthCookies();
      if (cookieHeader.isEmpty) {
        debugPrint('[Submissions] Missing FA cookies, abort fetch.');
        setState(() => _isLoading = false);
        return;
      }
      if (_sfwEnabled) {
        cookieHeader += '; sfw=1';
      }

      final url = _nextPageUrl ??
          _baseSubmissionsUrl ??
          'https://www.furaffinity.net/msg/submissions/';
      debugPrint('[Submissions] GET $url');

      final response = await http.get(Uri.parse(url), headers: {
        'Cookie': cookieHeader,
        'User-Agent': 'Mozilla/5.0',
      });

      if (response.statusCode == 200) {
        _parseListing(response.body);

        WidgetsBinding.instance.addPostFrameCallback((_) {
          for (var item in _flatSubmissionsList) {
            precacheImage(
              CachedNetworkImageProvider(item['thumbnailUrl']),
              context,
            );
          }
        });
      } else {
        debugPrint('[Submissions] HTTP ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('[Submissions] Exception: $e');
    }

    setState(() => _isLoading = false);
  }

  void _parseListing(String html) {
    final doc = html_parser.parse(html);


    _isClassicStyle =
        doc.body?.attributes['data-static-path']?.contains('/themes/classic') ?? false;

    // Extract base URL for deletion actions
    if (_baseSubmissionsUrl == null) {
      final form = doc.querySelector('form#messages-form');
      if (form != null) {
        final action = form.attributes['action'] ?? '';
        if (action.isNotEmpty) {
          _baseSubmissionsUrl = action.startsWith('http')
              ? action
              : 'https://www.furaffinity.net$action';
        }
      }
    }


    final dateDivs = doc.querySelectorAll('.notifications-by-date');
    for (int i = 0; i < dateDivs.length; i++) {
      final dateDiv = dateDivs[i];
      final heading = dateDiv.querySelector('h3.date-divider') ?? dateDiv.querySelector('h4.date-divider');
      if (heading == null) continue;
      final dateLabel = heading.text.trim();


      final figures = dateDiv.querySelectorAll('figure.t-image');
      if (figures.isEmpty) continue;

      final images = <Map<String, dynamic>>[];
      for (final fig in figures) {
        final map = _extractListingData(fig);
        if (map != null) {
          images.add(map);
        }
      }
      if (images.isNotEmpty) {
        _dateGroups.add(DateImageGroup(dateLabel: dateLabel, images: images));
      }
    }

    // Build the list
    _flatSubmissionsList.clear();
    _listItems.clear();
    bool isLastGroup(int groupIndex) => groupIndex == _dateGroups.length - 1;
    int flatIndexCounter = 0;
    for (int g = 0; g < _dateGroups.length; g++) {
      final group = _dateGroups[g];
      _listItems.add(_ListItem.header(
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
        _listItems.add(_ListItem.row(
          row,
          showDividerAfterGroup: isLastRowInThisGroup && !isLastGroup(g),
        ));
      }
    }

    final next = _extractNextPageUrl(doc);
    _hasMore = (next != null);
    _nextPageUrl = next;
  }

  Map<String, dynamic>? _extractListingData(html_dom.Element fig) {
    final aTag = fig.querySelector('a');
    final img = fig.querySelector('img');
    if (aTag == null || img == null) return null;

    final postUrl = aTag.attributes['href'] ?? '';
    final thumbUrl = img.attributes['src'] ?? '';
    if (postUrl.isEmpty || thumbUrl.isEmpty) return null;

    final widthRaw = img.attributes['data-width'] ?? '100';
    final heightRaw = img.attributes['data-height'] ?? '100';
    final w = double.tryParse(widthRaw) ?? 100.0;
    final h = double.tryParse(heightRaw) ?? 100.0;

    // /view/XXXXXX/
    final match = RegExp(r'/view/(\d+)/').firstMatch(postUrl);
    final uniqueNum = match?.group(1) ?? 'Unknown';

    final resolvedThumb =
    thumbUrl.startsWith('//') ? 'https:$thumbUrl' : thumbUrl;

    return {
      'postUrl': postUrl,
      'uniqueNumber': uniqueNum,
      'thumbnailUrl': resolvedThumb,
      'width': w,
      'height': h,
      'hqUrl': null,
      'isFav': false,
      'initialIsFav': false,
      'favUrl': '',
      'unfavUrl': '',
      'detailFetchQueued': false,
    };
  }

  String? _extractNextPageUrl(html_dom.Document doc) {
    // Modern
    final nextButton = doc.querySelector('a.button.standard.more:not(.prev)');
    if (nextButton != null) {
      final href = nextButton.attributes['href'] ?? '';
      if (href.isNotEmpty) {
        return href.startsWith('http')
            ? href
            : 'https://www.furaffinity.net$href';
      }
    }
    // In classic: .button.standard.more-half
    final moreHalfList = doc.querySelectorAll('a.button.standard.more-half');
    html_dom.Element? nextLink;
    try {
      nextLink = moreHalfList.firstWhere((el) => !el.classes.contains('prev'));
    } catch (_) {
      nextLink = null;
    }
    if (nextLink != null) {
      final href = nextLink.attributes['href'] ?? '';
      if (href.isNotEmpty) {
        return href.startsWith('http')
            ? href
            : 'https://www.furaffinity.net$href';
      }
    }
    return null;
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

  Future<String> _getAuthCookies() async {
    final cookieA = await _secureStorage.read(key: 'fa_cookie_a') ?? '';
    final cookieB = await _secureStorage.read(key: 'fa_cookie_b') ?? '';
    if (cookieA.isEmpty || cookieB.isEmpty) {
      return '';
    }
    return 'a=$cookieA; b=$cookieB';
  }

  Future<void> _onNukePressed() async {
    final confirmNuke = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nuke All?'),
        content: const Text('Do you really want to remove all of your submissions?'),
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
      final cookieHeader = await _getAuthCookies();
      if (cookieHeader.isEmpty) return;

      final url = _baseSubmissionsUrl ?? 'https://www.furaffinity.net/msg/submissions/new/';
      final resp = await http.post(Uri.parse(url), headers: {
        'Cookie': cookieHeader,
        'User-Agent': 'Mozilla/5.0',
      }, body: {'messagecenter-action': 'nuke_notifications'});
      if (resp.statusCode == 302) {
        setState(() {
          _dateGroups.clear();
          _flatSubmissionsList.clear();
          _listItems.clear();
          _submissionQueue.clear();
        });
        debugPrint('[Submissions] Nuke success => cleared UI');
      } else {
        debugPrint('[Submissions] Nuke failed => ${resp.statusCode}');
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
      final cookieHeader = await _getAuthCookies();
      if (cookieHeader.isEmpty) {
        debugPrint('[Submissions] Missing cookies, cannot delete.');
        return;
      }
      final body = <String, String>{'messagecenter-action': 'remove_checked'};
      int idx = 0;
      for (final id in _selectedSubmissions) {
        body['submissions[$idx]'] = id;
        idx++;
      }
      final deleteUrl = _baseSubmissionsUrl ?? 'https://www.furaffinity.net/msg/submissions/new/';
      final resp = await http.post(Uri.parse(deleteUrl), headers: {
        'Cookie': cookieHeader,
        'User-Agent': 'Mozilla/5.0',
        'Content-Type': 'application/x-www-form-urlencoded',
      }, body: body);

      if (resp.statusCode == 302) {
        setState(() {
          for (final group in _dateGroups) {
            group.images.removeWhere((img) => _selectedSubmissions.contains(img['uniqueNumber']));
          }
          _dateGroups.removeWhere((g) => g.images.isEmpty);
          _flatSubmissionsList.clear();
          _listItems.clear();
          int flatIndexCounter = 0;
          for (int g = 0; g < _dateGroups.length; g++) {
            final group = _dateGroups[g];
            final isLast = (g == _dateGroups.length - 1);
            _listItems.add(_ListItem.header(
              group.dateLabel,
              showDividerAfterGroup: !isLast,
            ));
            final imageRows = _splitImagesIntoRows(group.images);
            for (int r = 0; r < imageRows.length; r++) {
              final row = imageRows[r];
              for (final img in row) {
                img['flatIndex'] = flatIndexCounter++;
                _flatSubmissionsList.add(img);
              }
              final isLastRowOfGroup = (r == imageRows.length - 1);
              _listItems.add(_ListItem.row(
                row,
                showDividerAfterGroup: isLastRowOfGroup && !isLast,
              ));
            }
          }
        });
        debugPrint('[Submissions] Successfully deleted selected from UI.');
      } else {
        debugPrint('[Submissions] Deletion request failed => ${resp.statusCode}');
      }
    } catch (e) {
      debugPrint('[Submissions] Error deleting => $e');
    }
  }

  void onTileVisibilityChanged(int flatListIndex, bool isVisible) {
    if (flatListIndex < 0 || flatListIndex >= _flatSubmissionsList.length) return;
    if (isVisible) {
      _visibleTileIndices.add(flatListIndex);
      final item = _flatSubmissionsList[flatListIndex];
      if (item['detailFetchQueued'] == true) return;
      debugPrint('[Submissions] Visibility => queue HQ for item #$flatListIndex / ${item['postUrl']}');
      item['detailFetchQueued'] = true;
      _submissionQueue.add(_SubmissionQueueItem(
        indexInFlatList: flatListIndex,
        postUrl: item['postUrl'],
      ));
      _startNextFetches();
    } else {
      _visibleTileIndices.remove(flatListIndex);
      _submissionQueue.removeWhere((qItem) => qItem.indexInFlatList == flatListIndex);
      _flatSubmissionsList[flatListIndex]['detailFetchQueued'] = false;
    }
  }

  void _startNextFetches() {
    while (_activeFetches < _maxConcurrentFetches && _submissionQueue.isNotEmpty) {
      final qItem = _submissionQueue.removeFirst();
      final postUrl = qItem.postUrl;
      _activeFetches++;

      debugPrint('[Submissions] Start detail fetch for $postUrl. Active: $_activeFetches');

      _fetchSubmissionData(postUrl).then((data) {
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
          }
        });
      }).catchError((err) {
        debugPrint('[Submissions] Error fetching detail => $err');
      }).whenComplete(() {
        _activeFetches--;
        debugPrint('[Submissions] Done detail fetch for $postUrl. Active: $_activeFetches');
        _startNextFetches();
      });
    }
  }

  /// Fetch submission detail data, supporting both modern and classic style pages.
  Future<_SubmissionData> _fetchSubmissionData(String postUrl) async {
    final absoluteUrl = postUrl.startsWith('http')
        ? postUrl
        : 'https://www.furaffinity.net$postUrl';
    debugPrint('[Submissions] HQ fetch: $absoluteUrl');

    final cookieHeader = await _getAuthCookies();
    final resp = await http.get(Uri.parse(absoluteUrl), headers: {
      'Cookie': cookieHeader,
      'User-Agent': 'Mozilla/5.0',
      'Referer': 'https://www.furaffinity.net',
    });

    if (resp.statusCode != 200) {
      throw Exception('Submission detail fetch failed: ${resp.statusCode}');
    }

    // Decode the response using bodyBytes to handle non-ASCII characters.
    final doc = html_parser.parse(utf8.decode(resp.bodyBytes));

    final isClassic = doc.body?.attributes['data-static-path']?.contains('/themes/classic') ?? false;

    /// 1) Extract the high-quality image URL
    String? hqUrl;
    if (isClassic) {
      // Try to find the image with id 'submissionImg'
      final img = doc.querySelector('img#submissionImg');
      if (img != null) {
        final fullview = img.attributes['data-fullview-src'];
        if (fullview != null && fullview.isNotEmpty) {
          hqUrl = fullview.startsWith('//') ? 'https:$fullview' : fullview;
        } else {
          final src = img.attributes['src'] ?? '';
          if (src.isNotEmpty) {
            hqUrl = src.startsWith('//') ? 'https:$src' : src;
          }
        }
      }
    }
    else {
      // Modern style: <div class="submission-area submission-image"> with an <img id="submissionImg">
      final subArea = doc.querySelector('div.submission-area.submission-image');
      if (subArea != null) {
        final img = subArea.querySelector('img#submissionImg');
        if (img != null) {
          final fullview = img.attributes['data-fullview-src'];
          if (fullview != null && fullview.isNotEmpty) {
            hqUrl = fullview.startsWith('//') ? 'https:$fullview' : fullview;
          } else {
            final src = img.attributes['src'] ?? '';
            if (src.isNotEmpty) {
              hqUrl = src.startsWith('//') ? 'https:$src' : src;
            }
          }
        }
      }
    }
    hqUrl ??= ''; // fallback

    /// 2) Extract the favorite/unfavorite URLs
    bool isFav = false;
    String favUrl = '';
    String unfavUrl = '';

    if (!isClassic) {
      // Modern
      final favDiv = doc.querySelector('div.fav');
      if (favDiv != null) {
        for (var aTag in favDiv.querySelectorAll('a')) {
          final href = aTag.attributes['href'] ?? '';
          final absoluteHref = href.startsWith('http')
              ? href
              : 'https://www.furaffinity.net$href';
          if (href.contains('/fav/')) {
            favUrl = absoluteHref;
          } else if (href.contains('/unfav/')) {
            unfavUrl = absoluteHref;
          }
        }
        // If we have an unfav link but no fav link => the user has it faved
        if (unfavUrl.isNotEmpty && favUrl.isEmpty) {
          isFav = true;
        }
      }
    } else {
      // Classic
      final favLinks = doc.querySelectorAll('a[href*="/fav/"]');
      final unfavLinks = doc.querySelectorAll('a[href*="/unfav/"]');

      if (favLinks.isNotEmpty) {
        var raw = favLinks.first.attributes['href'] ?? '';
        if (!raw.startsWith('http') && raw.isNotEmpty) {
          raw = 'https://www.furaffinity.net$raw';
        }
        favUrl = raw;
      }

      if (unfavLinks.isNotEmpty) {
        var raw = unfavLinks.first.attributes['href'] ?? '';
        if (!raw.startsWith('http') && raw.isNotEmpty) {
          raw = 'https://www.furaffinity.net$raw';
        }
        unfavUrl = raw;
      }
      if (unfavUrl.isNotEmpty && favUrl.isEmpty) {
        // Means they have already faved it
        isFav = true;
      }
    }

    return _SubmissionData(
      hqUrl: hqUrl,
      isFav: isFav,
      favUrl: favUrl,
      unfavUrl: unfavUrl,
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        appBar: AppBar(
          centerTitle: true,
          title: const Text('Submissions'),
          actions: [
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
          onRefresh: _refreshSubmissions,
          child: _listItems.isEmpty && !_isLoading
              ? const Center(child: Text('No new submissions found.'))
              : ListView.builder(
            controller: _scrollController,
            itemCount: _listItems.length + (_isLoading ? 1 : 0),
            itemBuilder: (context, index) {
              if (index == _listItems.length) {
                // Show a loading indicator at the bottom
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
          ),
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
      MaterialPageRoute(
        builder: (ctx) => OpenPost(
          imageUrl: (item['hqUrl'] != null && (item['hqUrl'] as String).isNotEmpty)
              ? item['hqUrl'] as String
              : item['thumbnailUrl'] as String,
          uniqueNumber: item['uniqueNumber'] as String,
        ),
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
      final newData = await _fetchSubmissionData(item['postUrl']);
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

class _SubmissionData {
  final String hqUrl;
  final bool isFav;
  final String favUrl;
  final String unfavUrl;
  _SubmissionData({
    required this.hqUrl,
    required this.isFav,
    required this.favUrl,
    required this.unfavUrl,
  });
}

class _SubmissionQueueItem {
  final int indexInFlatList;
  final String postUrl;
  _SubmissionQueueItem({
    required this.indexInFlatList,
    required this.postUrl,
  });
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
          height: height,
          child: HeartAnimationOptimized(
            isFavorite: isFav,
            wasInitiallyFavorited: wasInitiallyFav,
            containerWidth: width,
            containerHeight: height,
            onToggle: (val) => onToggleFavorite(item, val),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8.0),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CachedNetworkImage(
                    imageUrl: displayUrl,
                    fit: BoxFit.cover,
                    fadeInDuration: const Duration(milliseconds: 300),
                    placeholder: (context, url) => CachedNetworkImage(
                      imageUrl: thumbnailUrl,
                      fit: BoxFit.cover,
                      fadeInDuration: Duration.zero,
                      errorWidget: (ctx, url, err) => Container(
                        color: Colors.grey[300],
                        child: const Icon(Icons.error, color: Colors.red),
                      ),
                    ),
                    errorWidget: (ctx, url, err) => Container(
                      color: Colors.grey[300],
                      child: const Icon(Icons.error, color: Colors.red),
                    ),
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
    );
  }
}
