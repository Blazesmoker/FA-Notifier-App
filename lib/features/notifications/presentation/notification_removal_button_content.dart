import 'package:fanotifier/shared/widgets/dashed_loading_indicator.dart';
import 'package:fanotifier/shared/widgets/success_burst_animation.dart';
import 'package:material_ui/material_ui.dart';

enum NotificationRemovalButtonPhase {
  idle,
  processing,
  success,
}

class NotificationRemovalButtonContent extends StatelessWidget {
  const NotificationRemovalButtonContent({
    super.key,
    required this.phase,
  });

  final NotificationRemovalButtonPhase phase;

  @override
  Widget build(BuildContext context) {
    return NotificationActionButtonContent(
      phase: phase,
      idleChild: const Text('Remove Selected'),
    );
  }
}

class NotificationActionButtonContent extends StatelessWidget {
  const NotificationActionButtonContent({
    super.key,
    required this.phase,
    required this.idleChild,
  });

  final NotificationRemovalButtonPhase phase;
  final Widget idleChild;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.center,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Opacity(
            opacity: phase == NotificationRemovalButtonPhase.idle ? 1 : 0,
            child: idleChild,
          ),
          if (phase == NotificationRemovalButtonPhase.processing)
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
          if (phase == NotificationRemovalButtonPhase.success)
            const Positioned.fill(
              child: SuccessBurstAnimation(),
            ),
        ],
      ),
    );
  }
}
