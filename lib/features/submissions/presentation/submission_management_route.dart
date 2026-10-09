import 'package:material_ui/material_ui.dart';

class SubmissionManagementRoute<T> extends MaterialPageRoute<T> {
  SubmissionManagementRoute({
    required this.readResult,
    required super.builder,
    super.settings,
  });

  final T Function() readResult;

  @override
  T get currentResult => readResult();
}
