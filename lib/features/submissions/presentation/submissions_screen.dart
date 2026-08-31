import 'package:material_ui/material_ui.dart';
import 'package:fanotifier/shared/widgets/fa_network_image.dart';
import 'package:provider/provider.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:fanotifier/shared/widgets/pulsating_loading_indicator.dart';
import 'package:fanotifier/shared/fa/domain/fa_activities_polling_port.dart';
import 'package:fanotifier/features/submissions/presentation/openpost.dart';
import 'package:fanotifier/features/submissions/domain/submission_favorite_repository.dart';
import 'package:fanotifier/features/submissions/domain/submission_list_item.dart';
import 'package:fanotifier/features/submissions/domain/submissions_repository.dart';
import 'package:fanotifier/features/submissions/presentation/submissions_controller.dart';
import 'package:fanotifier/features/submissions/presentation/widgets/submission_favorite_image_tile.dart';
import 'package:fanotifier/shared/fa/fa_system_message_parser.dart';
import 'package:fanotifier/shared/widgets/fa_unavailable_screen.dart';
import 'package:fanotifier/shared/widgets/dashed_loading_indicator.dart';
import 'package:fanotifier/shared/widgets/success_burst_animation.dart';

enum _SubmissionsAppBarAction {
  none,
  deleteSelected,
  deleteSelectedSuccess,
  nukeAll,
}

class SubmissionsScreen extends StatefulWidget {
  const SubmissionsScreen({
    super.key,
    required this.isActive,
  });

  final bool isActive;

  @override
  State<SubmissionsScreen> createState() => SubmissionsScreenState();
}

class SubmissionsScreenState extends State<SubmissionsScreen>
    with AutomaticKeepAliveClientMixin<SubmissionsScreen> {
  late final SubmissionsController _controller;
  late final FaActivitiesPollingPort _activitiesPollingPort;
  final ScrollController _scrollController = ScrollController();
  bool _isScreenVisible = false;
  _SubmissionsAppBarAction _processingAppBarAction =
      _SubmissionsAppBarAction.none;

  List<Map<String, dynamic>> get _flatSubmissionsList =>
      _controller.flatSubmissionsList;
  List<SubmissionListItem> get _listItems => _controller.listItems;
  Set<String> get _selectedSubmissions =>
      _controller.selectedSubmissions;
  bool get _isLoading => _controller.isLoading;
  bool get _hasMore => _controller.hasMore;
  bool get _isError => _controller.isError;
  String? get _errorMessage => _controller.errorMessage;
  bool get _selectionMode => _controller.selectionMode;
  bool get _sfwEnabled => _controller.sfwEnabled;
  bool get _isAppBarActionProcessing =>
      _processingAppBarAction != _SubmissionsAppBarAction.none;
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _activitiesPollingPort = context.read<FaActivitiesPollingPort>();
    _controller = SubmissionsController(
      repository: context.read<SubmissionsRepository>(),
      favoriteRepository: context.read<SubmissionFavoriteRepository>(),
    );
    _controller.addListener(_handleControllerChanged);
    _scrollController.addListener(_scrollListenerForPagination);
    _controller.loadSfwEnabled().then((_) => _refreshSubmissions());
  }

  @override
  void didUpdateWidget(covariant SubmissionsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActive != widget.isActive) {
      _updateDetailFetchActivity();
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_scrollListenerForPagination);
    _scrollController.dispose();
    _controller.removeListener(_handleControllerChanged);
    _controller.dispose();
    _activitiesPollingPort.setSubmissionsScreenVisible(false);
    super.dispose();
  }

  void _handleControllerChanged() {
    if (mounted) {
      setState(() {});
    }
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

  void _onWillPop() {
    if (_selectionMode) {
      _controller.exitSelectionMode();
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

  Future<void> _refreshSubmissions() {
    return _controller.refresh(
      onListingApplied: _scheduleThumbnailPrecache,
    );
  }

  Future<void> _fetchSubmissions() {
    return _controller.fetchSubmissions(
      onListingApplied: _scheduleThumbnailPrecache,
    );
  }

  void _scheduleThumbnailPrecache() {
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
  }

  Future<void> _onNukePressed() async {
    if (_isAppBarActionProcessing) return;
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
    if (confirmNuke != true || !mounted) return;

    setState(() {
      _processingAppBarAction = _SubmissionsAppBarAction.nukeAll;
    });
    try {
      await _controller.nukeSubmissions();
    } finally {
      if (mounted) {
        setState(() {
          _processingAppBarAction = _SubmissionsAppBarAction.none;
        });
      }
    }
  }

  void _updateDetailFetchActivity() {
    _controller.setDetailFetchesActive(
      widget.isActive && _isScreenVisible,
    );
  }

  Future<void> _onTrashIconPressed() async {
    if (_isAppBarActionProcessing) return;
    if (!_selectionMode) {
      _controller.enterSelectionMode();
      return;
    }
    if (_selectedSubmissions.isEmpty) {
      _controller.exitSelectionMode();
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
      if (!mounted) return;
      setState(() {
        _processingAppBarAction =
            _SubmissionsAppBarAction.deleteSelected;
      });
      var deleted = false;
      try {
        deleted = await _controller.deleteSelectedSubmissions();
      } finally {
        if (mounted && !deleted) {
          setState(() {
            _processingAppBarAction = _SubmissionsAppBarAction.none;
          });
        }
      }
      if (deleted && mounted) {
        setState(() {
          _processingAppBarAction =
              _SubmissionsAppBarAction.deleteSelectedSuccess;
        });
        await Future<void>.delayed(SuccessBurstAnimation.displayDuration);
        if (!mounted ||
            _processingAppBarAction !=
                _SubmissionsAppBarAction.deleteSelectedSuccess) {
          return;
        }
      }
    }
    _controller.exitSelectionMode();
  }

  Widget _buildAppBarActionIcon({
    required Widget idleIcon,
    required bool isProcessing,
    bool isSuccess = false,
  }) {
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        Opacity(
          opacity: isProcessing || isSuccess ? 0 : 1,
          child: idleIcon,
        ),
        if (isProcessing)
          const Positioned.fill(
            child: OverflowBox(
              alignment: Alignment.center,
              minWidth: 17,
              maxWidth: 17,
              minHeight: 17,
              maxHeight: 17,
              child: DashedLoadingIndicator(size: 17),
            ),
          ),
        if (isSuccess)
          const Positioned.fill(
            child: SuccessBurstAnimation(),
          ),
      ],
    );
  }

  void onTileVisibilityChanged(int flatListIndex, bool isVisible) {
    _controller.onTileVisibilityChanged(flatListIndex, isVisible);
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
    return VisibilityDetector(
      key: const Key('submissions_screen_visibility'),
      onVisibilityChanged: (info) {
        final isVisible = info.visibleFraction > 0.01;
        _isScreenVisible = isVisible;
        _updateDetailFetchActivity();
        _activitiesPollingPort
            .setSubmissionsScreenVisible(isVisible);
      },
      child: PopScope(
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
                  onPressed:
                      _isAppBarActionProcessing ? null : _toggleAllSelection,
                ),
              IconButton(
                icon: _buildAppBarActionIcon(
                  idleIcon: Icon(
                    _selectionMode ? Icons.delete_forever : Icons.delete,
                  ),
                  isProcessing: _processingAppBarAction ==
                      _SubmissionsAppBarAction.deleteSelected,
                  isSuccess: _processingAppBarAction ==
                      _SubmissionsAppBarAction.deleteSelectedSuccess,
                ),
                tooltip: 'Delete Selected',
                onPressed:
                    _isAppBarActionProcessing ? null : _onTrashIconPressed,
              ),
              IconButton(
                icon: _buildAppBarActionIcon(
                  idleIcon: const Icon(
                    Icons.block,
                    color: Color(0xFFE09321),
                  ),
                  isProcessing: _processingAppBarAction ==
                      _SubmissionsAppBarAction.nukeAll,
                ),
                tooltip: 'Nuke All',
                onPressed:
                    _isAppBarActionProcessing ? null : _onNukePressed,
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
    _controller.toggleAllSelection();
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
              child: SubmissionFavoriteImageTile(
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
            SubmissionFavoriteImageTile(
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
            SubmissionFavoriteImageTile(
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
    _controller.toggleSelection(uniqueNumber);
  }

  void _openSubmission(Map<String, dynamic> item) {
    _controller.setDetailFetchesActive(false);
    Navigator.push(
      context,
      OpenPost.route(
        imageUrl:
            (item['hqUrl'] != null && (item['hqUrl'] as String).isNotEmpty)
                ? item['hqUrl'] as String
                : item['thumbnailUrl'] as String,
        uniqueNumber: item['uniqueNumber'] as String,
      ),
    ).whenComplete(() {
      if (mounted) {
        _updateDetailFetchActivity();
      }
    });
  }

  void _handleToggleFavorite(Map<String, dynamic> item, bool newValue) {
    _controller.handleToggleFavorite(item, newValue);
  }
}
