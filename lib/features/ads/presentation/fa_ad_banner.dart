import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fanotifier/features/ads/presentation/fa_ad_section_controller.dart';
import 'package:fanotifier/shared/widgets/dashed_loading_indicator.dart';

class FaAdBanner extends StatelessWidget {
  const FaAdBanner({
    required this.section,
    required this.slot,
    required this.active,
    required this.onTap,
    super.key,
  });

  final FaAdSectionController section;
  final FaAdSlotController slot;
  final ValueListenable<bool> active;
  final VoidCallback onTap;

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
                  final width = math.min(size.width.toDouble(), constraints.maxWidth);
                  final height = size.height * width / size.width;
                  section.reportLayout(slot, width, height, constraints.maxWidth);
                  return Center(
                    child: SizedBox(
                      width: width, height: height,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: SizedBox(
                          width: size.width.toDouble(), height: size.height.toDouble(),
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

  Widget _content(FaAdSlotState state) {
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
    final size = slot.effectiveSize;
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
