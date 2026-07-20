import 'package:fanotifier/features/settings/domain/tag_blocklist_parse_result.dart';

abstract interface class TagBlocklistRepository {
  Future<TagBlocklistParseResult> fetch({required bool sfwEnabled});

  Future<void> updateTag({
    required bool sfwEnabled,
    required String nonce,
    required String tagName,
    required bool shouldBlock,
  });
}
