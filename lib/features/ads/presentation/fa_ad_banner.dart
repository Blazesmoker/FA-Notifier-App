import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fanotifier/features/ads/domain/fa_ad_models.dart';
import 'package:fanotifier/features/ads/presentation/fa_ad_section_controller.dart';
import 'package:fanotifier/shared/widgets/dashed_loading_indicator.dart';

class FaAdBanner extends StatelessWidget {
  const FaAdBanner({
    required this.section,
    required this.slot,
    required this.active,
    required this.onTap,
    this.fillAvailableWidth = false,
    super.key,
  });

  final FaAdSectionController section;
  final FaAdSlotController slot;
  final ValueListenable<bool> active;
  final VoidCallback onTap;
  final bool fillAvailableWidth;

  static FaAdSize renderSize(
    FaAdSize size, double availableWidth, {
    bool fillAvailableWidth = false,
  }) {
    availableWidth = availableWidth.isFinite
        ? math.max(0.0, availableWidth)
        : size.width.toDouble();
    final width = fillAvailableWidth
        ? availableWidth
        : math.min(size.width.toDouble(), availableWidth);
    return FaAdSize(width, size.height * width / size.width);
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: ValueListenableBuilder<bool>(
        valueListenable: active,
        builder: (context, screenActive, _) => ValueListenableBuilder<bool>(
          valueListenable: slot.inViewport,
          builder: (context, inViewport, _) => TickerMode(
            enabled: screenActive && inViewport,
            child: ValueListenableBuilder<FaAdSlotState>(
              valueListenable: slot.state,
              builder: (context, state, _) => LayoutBuilder(
                builder: (context, constraints) {
                  final size = slot.effectiveSize;
                  final rendered = renderSize(size, constraints.maxWidth,
                      fillAvailableWidth: fillAvailableWidth);
                  final width = rendered.width.toDouble();
                  final height = rendered.height.toDouble();
                  section.reportLayout(slot, width, height, constraints.maxWidth);
                  return Center(
                    child: SizedBox(
                      width: width, height: height,
                      child: fillAvailableWidth
                          ? _content(state, renderedSize: rendered)
                          : FittedBox(
                              fit: BoxFit.scaleDown,
                              child: SizedBox(
                                width: size.width.toDouble(),
                                height: size.height.toDouble(),
                                child: _content(state),
                              ),
                            ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _content(FaAdSlotState state, {FaAdSize? renderedSize}) {
    if (state.phase == FaAdSlotPhase.unavailable) {
      return const ColoredBox(
        color: Color(0xFF343434),
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text('Ad unavailable', style: TextStyle(color: Color(0xFFCCCCCC))),
          ),
        ),
      );
    }
    final bytes = state.bytes;
    if (bytes == null) return const _AdLoading();
    final size = renderedSize ?? slot.effectiveSize;
    return Center(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: state.clickBusy ? null : onTap,
        child: Image.memory(
          bytes,
          semanticLabel: 'Advertisement',
          width: size.width.toDouble(),
          height: size.height.toDouble(),
          fit: BoxFit.contain,
          gaplessPlayback: false,
          frameBuilder: (context, child, frame, synchronous) {
            if (frame != null || synchronous) {
              section.imageDecoded(slot, bytes);
              return child;
            }
            return const _AdLoading();
          },
          errorBuilder: (context, error, stack) {
            WidgetsBinding.instance.addPostFrameCallback((_) => section.imageDecodeFailed(slot, bytes));
            return const ColoredBox(color: Color(0xFF343434));
          },
        ),
      ),
    );
  }
}

class _AdLoading extends StatelessWidget {
  const _AdLoading();

  @override
  Widget build(BuildContext context) => const ColoredBox(
        color: Color(0xFF343434),
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DashedLoadingIndicator(size: 16, color: Color(0xFFCCCCCC)),
                SizedBox(height: 3),
                Text('Loading ad', style: TextStyle(fontSize: 11, color: Color(0xFFCCCCCC))),
              ],
            ),
          ),
        ),
      );
}
