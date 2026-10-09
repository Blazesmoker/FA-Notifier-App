import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'package:fanotifier/features/ads/presentation/fa_ad_banner.dart';
import 'package:fanotifier/features/ads/presentation/fa_ad_panel_controller.dart';
import 'package:fanotifier/features/ads/presentation/fa_ad_section_controller.dart';
import 'package:fanotifier/features/ads/presentation/fa_ad_viewport.dart';

class FaAdPanel extends StatelessWidget {
  const FaAdPanel({
    required this.controller,
    required this.viewportKey,
    required this.onTap,
    this.scrollController,
    this.padding = const EdgeInsets.fromLTRB(8, 0, 8, 8),
    this.spacing = 8,
    this.fillAvailableWidth = false,
    super.key,
  });

  final FaAdPanelController controller;
  final GlobalKey viewportKey;
  final ScrollController? scrollController;
  final Future<void> Function(FaAdSectionController, FaAdSlotController) onTap;
  final EdgeInsets padding;
  final double spacing;
  final bool fillAvailableWidth;

  double heightFor(double viewportWidth) {
    final slots = controller.section?.slots;
    if (slots == null || slots.isEmpty) return 0;
    final width = math.max(0.0, viewportWidth - padding.horizontal);
    return padding.vertical + spacing * (slots.length - 1) +
        slots.fold<double>(0, (height, slot) => height +
            FaAdBanner.renderSize(slot.effectiveSize, width,
                fillAvailableWidth: fillAvailableWidth).height.toDouble());
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final section = controller.section;
          if (section == null) return const SizedBox.shrink();
          return Padding(
            padding: padding,
            child: Column(
              key: ObjectKey(section),
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var index = 0; index < section.slots.length; index++) ...[
                  if (index > 0) SizedBox(height: spacing),
                  _banner(section, section.slots[index]),
                ],
              ],
            ),
          );
        },
      );

  Widget _banner(FaAdSectionController section, FaAdSlotController slot) {
    final banner = FaAdBanner(
      section: section,
      slot: slot,
      active: controller.active,
      fillAvailableWidth: fillAvailableWidth,
      onTap: () => onTap(section, slot),
    );
    void register(FaAdGeometryReader reader, bool attached) =>
        controller.registerGeometry(section, slot.definition.placement,
            reader, attached);
    void visible(bool visible, double ratio) => controller.scheduleVisibility();
    final scroll = scrollController;
    if (scroll == null) {
      return FaAdViewport.fixed(
        key: ValueKey(slot.definition.placement),
        viewportKey: viewportKey,
        active: controller.active,
        onGeometryReader: register,
        onVisibility: visible,
        onLayoutChanged: controller.scheduleVisibility,
        child: banner,
      );
    }
    return FaAdViewport(
      key: ValueKey(slot.definition.placement),
      viewportKey: viewportKey,
      scrollController: scroll,
      active: controller.active,
      onGeometryReader: register,
      onVisibility: visible,
      onLayoutChanged: controller.scheduleVisibility,
      child: banner,
    );
  }
}
