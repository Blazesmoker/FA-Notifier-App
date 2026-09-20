import 'dart:math' as math;
import 'package:material_ui/material_ui.dart';

const double _messageActionsFadeCeilingAboveButtons = 0.0;
const double _messageActionsFadeTransitionStart = 0.0;
const double _messageActionsFadeBlackStop = 1.00;
const double _messageActionsFadePosition = 0.35;
const double _messageActionsFadeSmoothness = 1.0;
const int _messageActionsFadeSteps = 64;
const double messageActionsFadeBottomOffset = 18.0;
const double messageActionsButtonsBottomOffset = 8.0;
const double messageActionsScrollClearance = 96.0;

List<double> get _messageActionsFadeStops => List<double>.generate(
  _messageActionsFadeSteps + 1,
  (index) => index / _messageActionsFadeSteps,
);

List<Color> get _messageActionsFadeColors => List<Color>.generate(
  _messageActionsFadeSteps + 1,
  (index) => Color.fromARGB(
    (_messageActionsFadeAlpha(index / _messageActionsFadeSteps) * 255).round(),
    0,
    0,
    0,
  ),
);

double _messageActionsFadeAlpha(double stop) {
  final transitionStart = _messageActionsFadeTransitionStart
      .clamp(0.0, 0.99)
      .toDouble();
  final blackStop = _messageActionsFadeBlackStop
      .clamp(transitionStart + 0.01, 1.0)
      .toDouble();
  if (stop <= transitionStart) return 0.0;
  if (stop >= blackStop) return 1.0;

  final progress = (stop - transitionStart) / (blackStop - transitionStart);
  final position = _messageActionsFadePosition.clamp(0.01, 0.99).toDouble();
  final smoothness = _messageActionsFadeSmoothness.clamp(0.0, 1.0).toDouble();
  final steepness = 14.0 - (smoothness * 12.0);
  final shiftedProgress =
      (progress * (1.0 - position)) /
      (position + (progress * (1.0 - (2.0 * position))));

  double sigmoid(double value) {
    return 1.0 / (1.0 + math.exp(-steepness * (value - 0.5)));
  }

  final minimum = sigmoid(0.0);
  final maximum = sigmoid(1.0);
  final normalizedAlpha =
      ((sigmoid(shiftedProgress) - minimum) / (maximum - minimum))
          .clamp(0.0, 1.0)
          .toDouble();
  final edgeSmoothedAlpha =
      normalizedAlpha * normalizedAlpha * (3.0 - (2.0 * normalizedAlpha));
  return (normalizedAlpha +
          ((edgeSmoothedAlpha - normalizedAlpha) * smoothness))
      .clamp(0.0, 1.0)
      .toDouble();
}

Widget buildMessageDetailActions({
  required double messageActionsFadeBottomInset,
  required VoidCallback onMarkUnread,
  required VoidCallback onReply,
}) {
  return Align(
    alignment: Alignment.bottomCenter,
    child: SizedBox(
      width: double.infinity,
      child: Stack(
        alignment: Alignment.bottomCenter,
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final totalHeight = constraints.maxHeight;
                  final fadeHeight = math.max(
                    0.0,
                    totalHeight - messageActionsFadeBottomInset,
                  );
                  final fadeEnd = totalHeight <= 0
                      ? 1.0
                      : (fadeHeight / totalHeight).clamp(0.0, 1.0).toDouble();
                  return DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [..._messageActionsFadeColors, Colors.black],
                        stops: [
                          ..._messageActionsFadeStops.map(
                            (stop) => stop * fadeEnd,
                          ),
                          1.0,
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.only(
              top: _messageActionsFadeCeilingAboveButtons,
              bottom: messageActionsFadeBottomInset,
            ),
            child: Transform.translate(
              offset: const Offset(
                0,
                messageActionsFadeBottomOffset -
                    messageActionsButtonsBottomOffset,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: onMarkUnread,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFE09321),
                      side: const BorderSide(color: Color(0xFFE09321)),
                      tapTargetSize: MaterialTapTargetSize.padded,
                    ),
                    child: const Text('Mark Unread'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: onReply,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE09321),
                      tapTargetSize: MaterialTapTargetSize.padded,
                    ),
                    child: const Text('Reply'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

PopupMenuItem<T> buildMessageDetailMenuItem<T>({
  required T action,
  required IconData icon,
  required String label,
  bool enabled = true,
}) {
  return PopupMenuItem<T>(
    value: action,
    enabled: enabled,
    child: Row(
      children: [
        Icon(icon, color: enabled ? Colors.white : Colors.grey, size: 21),
        const SizedBox(width: 12),
        Text(label),
      ],
    ),
  );
}
