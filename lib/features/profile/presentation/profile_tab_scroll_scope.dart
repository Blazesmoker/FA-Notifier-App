import 'package:material_ui/material_ui.dart';

class ProfileTabScrollScope extends StatefulWidget {
  const ProfileTabScrollScope({
    super.key,
    required this.tabController,
    required this.tabIndex,
    required this.recoveryKey,
    required this.child,
    this.onActiveChanged,
    this.onMediaVisibilityChanged,
  });

  final TabController tabController;
  final int tabIndex;
  final int recoveryKey;
  final Widget child;
  final ValueChanged<bool>? onActiveChanged;
  final ValueChanged<bool>? onMediaVisibilityChanged;

  static bool canFetch(BuildContext context) {
    final configuration =
        context.getInheritedWidgetOfExactType<_ProfileTabScrollConfiguration>();
    if (ModalRoute.of(context)?.isCurrent == false) return false;
    if (configuration == null) return true;
    final controller = configuration.tabController;
    final animationValue = controller.animation?.value ?? controller.index;
    return controller.index == configuration.tabIndex &&
        !controller.indexIsChanging &&
        (animationValue - configuration.tabIndex).abs() < 0.001;
  }

  @override
  State<ProfileTabScrollScope> createState() =>
      _ProfileTabScrollScopeState();
}

class _ProfileTabScrollScopeState extends State<ProfileTabScrollScope>
    with AutomaticKeepAliveClientMixin<ProfileTabScrollScope> {
  late final ScrollController _inactiveScrollController;
  late bool _isActive;
  late bool _isMediaVisible;
  late bool _isFetchActive;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _inactiveScrollController = ScrollController();
    _isActive = widget.tabController.index == widget.tabIndex;
    _isMediaVisible = _calculateMediaVisibility();
    _isFetchActive = _calculateFetchActivity();
    widget.tabController.addListener(_handleTabChanged);
    widget.tabController.animation?.addListener(_handleTabChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        widget.onActiveChanged?.call(_isFetchActive);
        widget.onMediaVisibilityChanged?.call(_isMediaVisible);
      }
    });
  }

  @override
  void didUpdateWidget(ProfileTabScrollScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tabController != widget.tabController) {
      oldWidget.tabController.removeListener(_handleTabChanged);
      oldWidget.tabController.animation?.removeListener(_handleTabChanged);
      widget.tabController.addListener(_handleTabChanged);
      widget.tabController.animation?.addListener(_handleTabChanged);
    }
    _handleTabChanged();
  }

  bool _calculateMediaVisibility() {
    final animationValue =
        widget.tabController.animation?.value ?? widget.tabController.index;
    final distance = (animationValue - widget.tabIndex).abs();
    return distance < 1.0 ||
        (widget.tabController.indexIsChanging &&
            widget.tabController.index == widget.tabIndex);
  }

  void _handleTabChanged() {
    final isActive = widget.tabController.index == widget.tabIndex;
    final isMediaVisible = _calculateMediaVisibility();
    final isFetchActive = _calculateFetchActivity();
    if (!mounted ||
        (_isActive == isActive &&
            _isMediaVisible == isMediaVisible &&
            _isFetchActive == isFetchActive)) {
      return;
    }
    final activeChanged = _isFetchActive != isFetchActive;
    final mediaVisibilityChanged = _isMediaVisible != isMediaVisible;
    setState(() {
      _isActive = isActive;
      _isMediaVisible = isMediaVisible;
      _isFetchActive = isFetchActive;
    });
    if (activeChanged) {
      widget.onActiveChanged?.call(isFetchActive);
    }
    if (mediaVisibilityChanged) {
      widget.onMediaVisibilityChanged?.call(isMediaVisible);
    }
  }

  bool _calculateFetchActivity() {
    final controller = widget.tabController;
    final animationValue = controller.animation?.value ?? controller.index;
    return controller.index == widget.tabIndex &&
        !controller.indexIsChanging &&
        (animationValue - widget.tabIndex).abs() < 0.001;
  }

  @override
  void dispose() {
    widget.tabController.removeListener(_handleTabChanged);
    widget.tabController.animation?.removeListener(_handleTabChanged);
    _inactiveScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final nestedScrollController = PrimaryScrollController.of(context);
    final scrollController =
        _isActive ? nestedScrollController : _inactiveScrollController;
    return TickerMode(
      enabled: TickerMode.valuesOf(context).enabled && _isMediaVisible,
      child: PrimaryScrollController(
        controller: scrollController,
        child: _ProfileTabScrollConfiguration(
          tabController: widget.tabController,
          tabIndex: widget.tabIndex,
          recoveryKey: widget.recoveryKey,
          fetchesActive: _isFetchActive,
          child: widget.child,
        ),
      ),
    );
  }
}

class _ProfileTabScrollConfiguration extends InheritedWidget {
  const _ProfileTabScrollConfiguration({
    required this.tabController,
    required this.tabIndex,
    required this.recoveryKey,
    required this.fetchesActive,
    required super.child,
  });

  final TabController tabController;
  final int tabIndex;
  final int recoveryKey;
  final bool fetchesActive;

  @override
  bool updateShouldNotify(_ProfileTabScrollConfiguration oldWidget) {
    return tabController != oldWidget.tabController ||
        tabIndex != oldWidget.tabIndex ||
        recoveryKey != oldWidget.recoveryKey ||
        fetchesActive != oldWidget.fetchesActive;
  }
}

class ProfileTabScrollViewport extends StatefulWidget {
  const ProfileTabScrollViewport({
    super.key,
    required this.child,
    this.onActivated,
    this.onLoadMore,
  });

  ProfileTabScrollViewport.scrollView({
    super.key,
    Key? storageKey,
    ScrollPhysics? physics,
    required List<Widget> slivers,
    this.onActivated,
    this.onLoadMore,
  }) : child = CustomScrollView(
          key: storageKey,
          physics: physics,
          slivers: slivers,
        );

  final Widget child;
  final VoidCallback? onActivated;
  final VoidCallback? onLoadMore;

  @override
  State<ProfileTabScrollViewport> createState() =>
      _ProfileTabScrollViewportState();
}

class _ProfileTabScrollViewportState extends State<ProfileTabScrollViewport> {
  (ScrollController, int)? _viewportIdentity;
  ScrollMetrics? _metrics;
  bool _wasActive = false;
  bool _activationPending = false;
  bool _checkScheduled = false;

  void _scheduleCheck() {
    if (_checkScheduled ||
        (widget.onActivated == null && widget.onLoadMore == null)) {
      return;
    }
    _checkScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkScheduled = false;
      if (!mounted || !ProfileTabScrollScope.canFetch(context)) return;
      if (_activationPending) {
        _activationPending = false;
        widget.onActivated?.call();
      }
      final metrics = _metrics;
      if (metrics != null && metrics.extentAfter <= 600.0) {
        widget.onLoadMore?.call();
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _handleMetrics(ScrollMetrics metrics, int depth) {
    if (depth != 0 || metrics.axis != Axis.vertical) return;
    _metrics = metrics;
    if (ProfileTabScrollScope.canFetch(context)) _scheduleCheck();
  }

  @override
  Widget build(BuildContext context) {
    final configuration = context
        .dependOnInheritedWidgetOfExactType<_ProfileTabScrollConfiguration>();
    final controller = PrimaryScrollController.of(context);
    final identity = (controller, configuration?.recoveryKey ?? 0);
    if (_viewportIdentity != identity) {
      _viewportIdentity = identity;
      _metrics = null;
    }
    final active = ProfileTabScrollScope.canFetch(context);
    if (active != _wasActive) {
      _wasActive = active;
      _activationPending = active;
      if (active) _scheduleCheck();
    }
    final viewport = KeyedSubtree(
      key: ValueKey<(ScrollController, int)>(identity),
      child: widget.child,
    );
    if (widget.onActivated == null && widget.onLoadMore == null) {
      return viewport;
    }
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (notification) {
        _handleMetrics(notification.metrics, notification.depth);
        return false;
      },
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          _handleMetrics(notification.metrics, notification.depth);
          return false;
        },
        child: viewport,
      ),
    );
  }
}
