import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

const Color managementAccent = Color(0xFFE09321);
const Color managementBackground = Colors.black;
const Color managementCard = Color(0xFF1A1A1A);
const Color fallbackFolderColor = Color(0xFF455A64);
const Color selectedSubmissionOverlay = Color(0x3AE09321);
const Color submissionCheckboxBackground = Color(0x66000000);
const double managementMenuVerticalPadding = 12;
const double managementActionsFadeCeilingAboveButtons = 50.0;
const double _managementActionsFadeTransitionStart = 0.0;
const double _managementActionsFadeBlackStop = 1.0;
const double _managementActionsFadePosition = 0.20;
const double _managementActionsFadeSmoothness = 1.0;
const int _managementActionsFadeSteps = 64;
const double managementActionsScrollClearance = 160.0;
const Duration submissionPreviewAnimationDuration =
    Duration(milliseconds: 180);
const double submissionPreviewInitialScale = 0.94;
const double submissionPreviewBarrierOpacity = 0.78;
const double submissionPreviewScreenPadding = 20.0;
const double submissionPreviewBorderRadius = 10.0;

final List<double> managementActionsFadeStops = List<double>.generate(
  _managementActionsFadeSteps + 1,
  (index) => index / _managementActionsFadeSteps,
  growable: false,
);

final List<Color> managementActionsFadeColors = List<Color>.generate(
  _managementActionsFadeSteps + 1,
  (index) => Color.fromARGB(
    (_managementActionsFadeAlpha(index / _managementActionsFadeSteps) * 255)
        .round(),
    0,
    0,
    0,
  ),
  growable: false,
);

double _managementActionsFadeAlpha(double stop) {
  final transitionStart =
      _managementActionsFadeTransitionStart.clamp(0.0, 0.99).toDouble();
  final blackStop = _managementActionsFadeBlackStop
      .clamp(transitionStart + 0.01, 1.0)
      .toDouble();
  if (stop <= transitionStart) return 0.0;
  if (stop >= blackStop) return 1.0;

  final progress =
      (stop - transitionStart) / (blackStop - transitionStart);
  final position =
      _managementActionsFadePosition.clamp(0.01, 0.99).toDouble();
  final smoothness =
      _managementActionsFadeSmoothness.clamp(0.0, 1.0).toDouble();
  final steepness = 14.0 - (smoothness * 12.0);
  final shiftedProgress = (progress * (1.0 - position)) /
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
