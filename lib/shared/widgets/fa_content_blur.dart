import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:visibility_detector/visibility_detector.dart';

import 'package:fanotifier/shared/fa/domain/fa_content_block_data.dart';
import 'package:fanotifier/shared/fa/presentation/fa_content_block_controller.dart';

class FaImageBlur extends StatelessWidget {
  const FaImageBlur({
    super.key,
    required this.blurred,
    required this.child,
    this.sigma = 60,
  });

  final bool blurred;
  final Widget child;
  final double sigma;

  @override
  Widget build(BuildContext context) {
    if (!blurred) return child;
    return ClipRect(
      child: ImageFiltered(
        enabled: blurred,
        imageFilter: ui.ImageFilter.blur(
          sigmaX: sigma,
          sigmaY: sigma,
          tileMode: ui.TileMode.clamp,
        ),
        child: child,
      ),
    );
  }
}

class FaContentBlurScope extends InheritedWidget {
  const FaContentBlurScope({
    super.key,
    required this.blurred,
    required super.child,
  });

  final bool blurred;

  static bool blurredOf(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<FaContentBlurScope>()
            ?.blurred ??
        false;
  }

  @override
  bool updateShouldNotify(FaContentBlurScope oldWidget) {
    return blurred != oldWidget.blurred;
  }
}

class FaContentBlur extends StatefulWidget {
  const FaContentBlur({
    super.key,
    required this.submissionId,
    required this.child,
    this.data = const FaContentBlockData(),
    this.lookupMissingTags = true,
  });

  final String submissionId;
  final FaContentBlockData data;
  final Widget child;
  final bool lookupMissingTags;

  @override
  State<FaContentBlur> createState() => _FaContentBlurState();
}

class _FaContentBlurState extends State<FaContentBlur> {
  late final FaContentBlockController _controller;
  late final bool Function() _isVisible;
  final Key _visibilityKey = UniqueKey();
  bool _visible = false;
  bool _lookupScheduled = false;
  bool _listeningForLookup = false;

  @override
  void initState() {
    super.initState();
    _controller = context.read<FaContentBlockController>();
    _isVisible = () => mounted &&
        _visible &&
        (ModalRoute.of(context)?.isCurrent ?? true);
    _syncLookupListener();
  }

  void _syncLookupListener() {
    final listen = widget.lookupMissingTags &&
        !widget.data.tagsKnown &&
        widget.submissionId.isNotEmpty;
    if (listen == _listeningForLookup) return;
    _listeningForLookup = listen;
    if (listen) {
      _controller.addListener(_scheduleLookup);
    } else {
      _controller.removeListener(_scheduleLookup);
    }
  }

  void _scheduleLookup() {
    if (_lookupScheduled ||
        !widget.lookupMissingTags ||
        !_isVisible() ||
        !_controller.needsTagLookup(widget.submissionId, widget.data)) {
      return;
    }
    _lookupScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _lookupScheduled = false;
      if (!_isVisible()) return;
      _controller.resolveMissingTags(
        widget.submissionId,
        widget.data,
        isVisible: _isVisible,
      );
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void didUpdateWidget(covariant FaContentBlur oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.submissionId != widget.submissionId) {
      _controller.removeLookupInterest(oldWidget.submissionId, _isVisible);
    }
    if (!widget.lookupMissingTags || widget.data.tagsKnown) {
      _controller.removeLookupInterest(widget.submissionId, _isVisible);
    }
    _syncLookupListener();
  }

  @override
  void dispose() {
    _visible = false;
    _controller.removeListener(_scheduleLookup);
    _controller.removeLookupInterest(widget.submissionId, _isVisible);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.select<FaContentBlockController, (bool, bool)>(
      (controller) => (
        controller.isBlocked(widget.submissionId, widget.data),
        controller.needsTagLookup(widget.submissionId, widget.data),
      ),
    );
    final image = FaContentBlurScope(blurred: state.$1, child: widget.child);
    if (!widget.lookupMissingTags ||
        !state.$2 ||
        widget.submissionId.isEmpty) {
      return image;
    }
    if (ModalRoute.of(context)?.isCurrent ?? true) _scheduleLookup();
    return VisibilityDetector(
      key: _visibilityKey,
      onVisibilityChanged: (info) {
        _visible = info.visibleFraction > 0;
        _scheduleLookup();
      },
      child: image,
    );
  }
}
