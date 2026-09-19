import 'package:material_ui/material_ui.dart';
import 'package:fanotifier/features/settings/domain/fur_affinity_settings_models.dart';
import 'package:fanotifier/shared/utils/app_snack_bar.dart';

void showSettingsMutationSnackBar(
  BuildContext context, {
  required String section,
  required FaSettingsMutationResult result,
  String? successText,
  String? failureText,
}) {
  if (result.success) {
    showAppSnackBar(
      context,
      successText ?? '$section settings changed successfully.',
      backgroundColor: Colors.green.shade700,
    );
    return;
  }

  final code = result.statusCode == null
      ? 'network error'
      : 'HTTP ${result.statusCode}';
  final detail = _safeResultDetail(result.message);
  final suffix = detail == null ? code : '$code: $detail';
  showAppSnackBar(
    context,
    failureText == null
        ? '$section settings change failed ($suffix).'
        : '$failureText ($suffix).',
    backgroundColor: Colors.red.shade700,
    durationSeconds: 4,
  );
}

String settingsLoadFailureText(Object error) {
  if (error is FaSettingsRequestException && error.statusCode != null) {
    return 'Failed to load settings (HTTP ${error.statusCode}).';
  }
  return 'Failed to load settings.';
}

String? _safeResultDetail(String? message) {
  final cleaned = message?.replaceAll(RegExp(r'\s+'), ' ').trim() ?? '';
  if (cleaned.isEmpty) return null;
  if (cleaned.length <= 100) return cleaned;
  return '${cleaned.substring(0, 97).trim()}...';
}
