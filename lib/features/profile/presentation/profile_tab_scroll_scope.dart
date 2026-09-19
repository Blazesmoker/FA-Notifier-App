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

  @override
  State<ProfileTabScrollScope> createState() =>
      _ProfileTabScrollScopeState();
}

class _ProfileTabScrollScopeState extends State<ProfileTabScrollScope>
    with AutomaticKeepAliveClientMixin<ProfileTabScrollScope> {
  late final ScrollController _inactiveScrollController;
  late bool _isActive;
  late bool _isMediaVisible;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _inactiveScrollController = ScrollController();
    _isActive = widget.tabController.index == widget.tabIndex;
    _isMediaVisible = _calculateMediaVisibility();
    widget.tabController.addListener(_handleTabChanged);
    widget.tabController.animation?.addListener(_handleTabChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        widget.onActiveChanged?.call(_isActive);
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
    if (!mounted ||
        (_isActive == isActive && _isMediaVisible == isMediaVisible)) {
      return;
    }
    final activeChanged = _isActive != isActive;
    final mediaVisibilityChanged = _isMediaVisible != isMediaVisible;
    setState(() {
      _isActive = isActive;
      _isMediaVisible = isMediaVisible;
    });
    if (activeChanged) {
      widget.onActiveChanged?.call(isActive);
    }
    if (mediaVisibilityChanged) {
      widget.onMediaVisibilityChanged?.call(isMediaVisible);
    }
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
        child: KeyedSubtree(
          key: ValueKey<(ScrollController, int)>(
            (scrollController, widget.recoveryKey),
          ),
          child: widget.child,
        ),
      ),
    );
  }
}
