abstract final class CrashReportPrivacy {
  static final RegExp _type = RegExp(r'^[A-Za-z_$][A-Za-z0-9_$]{0,99}$');
  static final RegExp _frame = RegExp(
    r'^#\d+\s+([A-Za-z0-9_$.<>= \[\]-]+) \(((?:package|dart):[A-Za-z0-9_./:-]+)\)$',
  );
  static final RegExp _addressFrame = RegExp(
    r'^#\d+\s+abs\s+[a-fA-F0-9]+(?:\s+virt\s+[a-fA-F0-9]+)?',
  );
  static final RegExp _buildId = RegExp(r"^build_id: '[a-fA-F0-9]+'$");
  static final RegExp _instructions = RegExp(
    r'^(?:isolate|vm)_instructions: [a-fA-F0-9]+(?:, (?:isolate|vm)_instructions: [a-fA-F0-9]+)?$',
  );
  static final RegExp _loadingUnit = RegExp(
    r"^loading_unit: \d+(?:, (?:build_id: '[a-fA-F0-9]+'|[a-z_]+: (?:0x)?[a-fA-F0-9]+))*$",
  );

  static String errorType(Object error) {
    final name = error.runtimeType.toString();
    return _type.hasMatch(name) ? name : 'Error';
  }

  static String errorSummary(Object error) {
    final type = errorType(error);
    if (error is! Error) return type;
    try {
      final text = error.toString();
      final message = text.length > 2048 ? text.substring(0, 2048) : text;
      if (message.contains('Null check operator used on a null value')) {
        return '$type: Null check operator used on a null value';
      }
      if (message.contains('setState() called after dispose()')) {
        return '$type: setState() called after dispose()';
      }
      if (message.contains('setState() or markNeedsBuild() called during build')) {
        return '$type: State changed during build';
      }
      if (message.contains('is not a subtype of type')) {
        return '$type: Incompatible runtime types';
      }
      if (message.contains('RenderFlex overflowed')) {
        return '$type: RenderFlex overflow';
      }
      if (message.contains('unbounded height') ||
          message.contains('unbounded width')) {
        return '$type: Unbounded layout constraints';
      }
      if (message.contains('was not initialized') ||
          message.contains('has not been initialized')) {
        return '$type: Value used before initialization';
      }
      if (message.contains('Bad state: No element')) {
        return '$type: No element';
      }
    } catch (_) {}
    return type;
  }

  static StackTrace stack(StackTrace? original) {
    final lines = <String>[];
    try {
      final raw = original?.toString() ?? '';
      final bounded = raw.length > 32768 ? raw.substring(0, 32768) : raw;
      for (final input in bounded.split('\n').take(100)) {
        final line = input.trim();
        final frame = _frame.firstMatch(line);
        if (frame != null) {
          lines.add('#${lines.length} ${frame[1]} (${frame[2]})');
          continue;
        }
        final address = _addressFrame.firstMatch(line);
        if (address != null) {
          lines.add(address[0]!);
        } else if (_buildId.hasMatch(line) ||
            _instructions.hasMatch(line) ||
            _loadingUnit.hasMatch(line) ||
            line == '<asynchronous suspension>') {
          lines.add(line);
        }
      }
    } catch (_) {}
    return StackTrace.fromString(
      lines.isEmpty ? '#0 unavailable (dart:core:0:0)' : lines.join('\n'),
    );
  }

  static String executionContext(String value) {
    const known = {
      'foreground_flutter',
      'foreground_platform',
      'foreground_boot',
      'background_periodic',
    };
    return known.contains(value) ? value : 'unknown';
  }

  static String reason(String? value) {
    const known = {
      'notification_service_initialization_failed',
      'workmanager_initialization_failed',
      'after_first_frame_boot_failed',
      'background_worker_initialization_failed',
      'background_notification_task_failed',
    };
    return known.contains(value) ? value! : 'anonymous_diagnostic';
  }

  static String library(String? value) {
    const known = {
      'widgets library',
      'rendering library',
      'services library',
      'scheduler library',
      'animation library',
      'gestures library',
      'painting library',
      'image resource service',
      'foundation library',
    };
    return known.contains(value) ? value! : 'unknown';
  }

  static String screen(String value) {
    const known = {
      'Login',
      'Browse',
      'Search',
      'Submissions',
      'Notifications',
      'Notes / Inbox',
      'Notes / Sent',
      'Submission Details',
      'Journal Details',
      'Note Details',
      'New Note',
      'Reply to Note',
      'Notes / Trash',
      'Notes / Archive',
      'Profile / Home',
      'Profile / Gallery',
      'Profile / Scraps',
      'Profile / Favorites',
      'Profile / Journals',
      'Image Viewer',
      'Document Viewer',
      'Upload Submission',
      'Submission Templates',
      'Finalize Submission',
      'Edit Submission',
      'Manage Submissions',
      'Manage Submissions / Folders',
      'Manage Submissions / Folder Editor',
      'Create Journal',
      'Edit Journal',
      'Reply to Journal Comment',
      'Edit Journal Comment',
      'Add Comment',
      'Reply to Comment',
      'Edit Comment',
      'Post Shout',
      'Browse Filters',
      'Search Filters',
      'Keyword Search',
      'Find Source',
      'Settings',
      'App Settings',
      'FurAffinity Settings',
      'FurAffinity Settings / Account',
      'FurAffinity Settings / Global Site',
      'FurAffinity Settings / User',
      'Profile / Contacts & Social Media',
      'Profile / Profile Info',
      'Profile / Profile Banner',
      'Profile / Avatar Management',
      'FurAffinity Settings / Password Reset',
      'Notification Settings',
      'Note Settings',
      'Comment Settings',
      'Thumbnail Settings',
      'Time Display Settings',
      'Translator Settings',
      'App Icon Settings',
      'Home Screen Settings',
      'Tag Blocklist',
      'User List',
      'Privacy Settings',
      'Privacy Consent',
      'App Update',
      'Security Check',
      'Notifications / Submissions',
      'Notifications / Watches',
      'Notifications / Comments',
      'Notifications / Favorites',
      'Notifications / Journals',
      'Notifications / Shouts',
      'Notifications / Overview',
    };
    return known.contains(value) ? value : 'unknown';
  }
}
