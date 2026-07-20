import 'package:fanotifier/features/settings/data/tag_blocklist_service.dart';
import 'package:fanotifier/features/settings/domain/tag_blocklist_parse_result.dart';
import 'package:fanotifier/features/settings/domain/tag_blocklist_repository.dart';

class TagBlocklistRepositoryImpl implements TagBlocklistRepository {
  const TagBlocklistRepositoryImpl();

  @override
  Future<TagBlocklistParseResult> fetch({required bool sfwEnabled}) {
    return fetchTagBlocklist(sfwEnabled: sfwEnabled);
  }

  @override
  Future<void> updateTag({
    required bool sfwEnabled,
    required String nonce,
    required String tagName,
    required bool shouldBlock,
  }) {
    return sendTagBlocklistRequest(
      sfwEnabled: sfwEnabled,
      nonce: nonce,
      tagName: tagName,
      shouldBlock: shouldBlock,
    );
  }
}
