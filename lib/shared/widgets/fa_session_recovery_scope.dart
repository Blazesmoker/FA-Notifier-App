import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:visibility_detector/visibility_detector.dart';

import 'package:fanotifier/app/navigation/app_navigation.dart';
import 'package:fanotifier/shared/fa/domain/fa_session_access.dart';

class FaSessionRecoveryScope extends StatefulWidget {
  const FaSessionRecoveryScope({
    super.key,
    required this.needsRecovery,
    required this.isBusy,
    required this.onRecover,
    required this.child,
    this.isSliver = false,
  });

  final bool Function() needsRecovery;
  final bool Function() isBusy;
  final Future<void> Function() onRecover;
  final Widget child;
  final bool isSliver;

  @override
  State<FaSessionRecoveryScope> createState() => _FaSessionRecoveryScopeState();
}

class _FaSessionRecoveryScopeState extends State<FaSessionRecoveryScope>
    with RouteAware, WidgetsBindingObserver {
  final Key _visibilityKey = UniqueKey();
  StreamSubscription<int>? _subscription;
  ModalRoute<dynamic>? _route;
  late int _handledGeneration;
  late int _pendingGeneration;
  bool _visible = false;
  bool _resumed = true;
  bool _scheduled = false;
  bool _recovering = false;
  Timer? _busyRetry;

  @override
  void initState() {
    super.initState();
    final session = context.read<FaSessionAccess>();
    _handledGeneration = session.verifiedGeneration;
    _pendingGeneration = _handledGeneration;
    _resumed = WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    _subscription = session.verifiedSessions.listen((generation) {
      _pendingGeneration = generation;
      _scheduleRecovery();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != _route) {
      routeObserver.unsubscribe(this);
      _route = route;
      if (route != null) routeObserver.subscribe(this, route);
    }
    _scheduleRecovery();
  }

  @override
  void didUpdateWidget(covariant FaSessionRecoveryScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    _scheduleRecovery();
  }

  @override
  void didPopNext() => _scheduleRecovery();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _resumed = state == AppLifecycleState.resumed;
    if (_resumed) _scheduleRecovery();
  }

  void _visibilityChanged(VisibilityInfo info) {
    _visible = info.visibleFraction > 0;
    if (_visible) _scheduleRecovery();
  }

  void _scheduleRecovery() {
    if (_scheduled || !mounted || _pendingGeneration <= _handledGeneration) {
      return;
    }
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      unawaited(_recover());
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> _recover() async {
    if (!mounted ||
        !_visible ||
        !_resumed ||
        _route?.isCurrent == false ||
        _recovering ||
        _pendingGeneration <= _handledGeneration) {
      return;
    }
    if (widget.isBusy()) {
      _busyRetry?.cancel();
      _busyRetry = Timer(const Duration(milliseconds: 250), _scheduleRecovery);
      return;
    }
    _handledGeneration = _pendingGeneration;
    if (!widget.needsRecovery()) return;
    _recovering = true;
    try {
      await widget.onRecover();
    } catch (_) {
    } finally {
      _recovering = false;
      _scheduleRecovery();
    }
  }

  @override
  void dispose() {
    _busyRetry?.cancel();
    _subscription?.cancel();
    routeObserver.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isSliver) {
      return SliverVisibilityDetector(
        key: _visibilityKey,
        onVisibilityChanged: _visibilityChanged,
        sliver: widget.child,
      );
    }
    return VisibilityDetector(
      key: _visibilityKey,
      onVisibilityChanged: _visibilityChanged,
      child: widget.child,
    );
  }
}
