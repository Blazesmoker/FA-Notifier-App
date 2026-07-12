import 'package:FANotifier/features/submissions/domain/openpost_models.dart';

class OpenPostUserActionsLoadResult {
  const OpenPostUserActionsLoadResult({
    required this.statusCode,
    this.actions,
  });

  final int statusCode;
  final OpenPostUserPageActions? actions;
}
