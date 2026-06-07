import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

class IosScrollRecovery {
  IosScrollRecovery._();

  static final ValueNotifier<int> _revision = ValueNotifier<int>(0);

  static ValueListenable<int> get listenable => _revision;
  static int get revision => _revision.value;

  static void addListener(VoidCallback listener) {
    _revision.addListener(listener);
  }

  static void removeListener(VoidCallback listener) {
    _revision.removeListener(listener);
  }

  static void notifyTranslationSheetDismissed({
    IosScrollRecoveryScope? scope,
  }) {
    if (!Platform.isIOS) return;
    if (scope != null) {
      scope.notify();
      return;
    }
    _bump();
  }

  static double currentOffset(ScrollController controller) {
    if (!controller.hasClients) return 0.0;
    return controller.position.pixels;
  }

  static void restoreOffset(ScrollController controller, double offset) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!controller.hasClients) return;
      final position = controller.position;
      final restoredOffset = offset.clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      position.jumpTo(restoredOffset);
    });
  }

  static void _bump() {
    _revision.value++;
  }
}

class IosScrollRecoveryScope {
  final ValueNotifier<int> _revision = ValueNotifier<int>(0);
  bool _disposed = false;

  ValueListenable<int> get listenable => _revision;
  int get revision => _revision.value;

  void notify() {
    if (_disposed) return;
    _revision.value++;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _revision.dispose();
  }
}

class IosScrollRecoverySingleChildScrollView extends StatefulWidget {
  const IosScrollRecoverySingleChildScrollView({
    super.key,
    this.recoveryScope,
    this.physics,
    required this.child,
  });

  final IosScrollRecoveryScope? recoveryScope;
  final ScrollPhysics? physics;
  final Widget child;

  @override
  State<IosScrollRecoverySingleChildScrollView> createState() =>
      _IosScrollRecoverySingleChildScrollViewState();
}

class _IosScrollRecoverySingleChildScrollViewState
    extends State<IosScrollRecoverySingleChildScrollView> {
  final ScrollController _controller = ScrollController();
  late ValueListenable<int> _recoveryListenable;
  late int _scrollableKey;

  @override
  void initState() {
    super.initState();
    _recoveryListenable = _resolveRecoveryListenable();
    _scrollableKey = _recoveryListenable.value;
    _recoveryListenable.addListener(_handleRecovery);
  }

  @override
  void didUpdateWidget(IosScrollRecoverySingleChildScrollView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextRecoveryListenable = _resolveRecoveryListenable();
    if (identical(_recoveryListenable, nextRecoveryListenable)) return;

    _recoveryListenable.removeListener(_handleRecovery);
    _recoveryListenable = nextRecoveryListenable;
    _scrollableKey = _recoveryListenable.value;
    _recoveryListenable.addListener(_handleRecovery);
  }

  @override
  void dispose() {
    _recoveryListenable.removeListener(_handleRecovery);
    _controller.dispose();
    super.dispose();
  }

  ValueListenable<int> _resolveRecoveryListenable() {
    return widget.recoveryScope?.listenable ?? IosScrollRecovery.listenable;
  }

  void _handleRecovery() {
    if (!mounted) return;
    final offset = IosScrollRecovery.currentOffset(_controller);
    setState(() {
      _scrollableKey = _recoveryListenable.value;
    });
    IosScrollRecovery.restoreOffset(_controller, offset);
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      key: ValueKey<int>(_scrollableKey),
      controller: _controller,
      physics: widget.physics,
      child: widget.child,
    );
  }
}
