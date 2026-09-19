import 'package:material_ui/material_ui.dart';

import 'package:fanotifier/features/submissions/domain/submission_document_models.dart';

Widget buildSubmissionTagsPanel({
  required List<FaPostTag> keywordTags,
  required List<FaPostTag> metaKeywordTags,
  required Set<String> tagToggleInFlight,
  required Future<void> Function(FaPostTag) onToggleTagBlock,
  required ValueChanged<String> onSearch,
}) {
  final bool hasAnyTags =
      keywordTags.isNotEmpty || metaKeywordTags.isNotEmpty;

  // Guard: some posts have *only* meta keywords. In that case, older parsing
  // fallbacks could end up treating the meta section as normal keywords,
  // making the UI show the same chips twice. If both groups are identical,
  // show only the meta group.
  final Set<String> keywordSet =
      keywordTags.map((t) => t.name.toLowerCase()).toSet();
  final Set<String> metaSet =
      metaKeywordTags.map((t) => t.name.toLowerCase()).toSet();
  final bool hideKeywordGroup = keywordSet.isNotEmpty &&
      metaSet.isNotEmpty &&
      keywordSet.length == metaSet.length &&
      keywordSet.containsAll(metaSet);

  if (!hasAnyTags) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
      child: Text(
        'No keywords available.',
        style: TextStyle(fontSize: 13, color: Colors.grey),
        textAlign: TextAlign.center,
      ),
    );
  }

  return Padding(
    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (keywordTags.isNotEmpty && !hideKeywordGroup)
          _buildTagsGroup(
            tagToggleInFlight: tagToggleInFlight,
            onToggleTagBlock: onToggleTagBlock,
            onSearch: onSearch,
            title: 'Keywords',
            tags: keywordTags,
            allowSearch: true,
          ),
        if (metaKeywordTags.isNotEmpty) ...[
          const SizedBox(height: 12),
          _buildTagsGroup(
            tagToggleInFlight: tagToggleInFlight,
            onToggleTagBlock: onToggleTagBlock,
            onSearch: onSearch,
            title: 'Meta Keywords',
            tags: metaKeywordTags,
            allowSearch: false,
          ),
        ],
      ],
    ),
  );
}

Widget _buildTagsGroup({
  required Set<String> tagToggleInFlight,
  required Future<void> Function(FaPostTag) onToggleTagBlock,
  required ValueChanged<String> onSearch,
  required String title,
  required List<FaPostTag> tags,
  required bool allowSearch,
}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Center(
        child: Text(
          title,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ),
      const SizedBox(height: 10),
      Wrap(
        alignment: WrapAlignment.start,
        runAlignment: WrapAlignment.start,
        spacing: 10,
        runSpacing: 10,
        children: tags
            .map((t) => _buildTagPill(
                  t,
                  allowSearch: allowSearch,
                  tagToggleInFlight: tagToggleInFlight,
                  onToggleTagBlock: onToggleTagBlock,
                  onSearch: onSearch,
                ))
            .toList(growable: false),
      ),
    ],
  );
}

Widget _buildTagPill(FaPostTag tag, {
  required bool allowSearch,
  required Set<String> tagToggleInFlight,
  required Future<void> Function(FaPostTag) onToggleTagBlock,
  required ValueChanged<String> onSearch,
}) {
  final bool inFlight = tagToggleInFlight.contains(tag.name);
  final bool isBlocked = tag.isBlocked;

  final Color accent = isBlocked ? Colors.redAccent : const Color(0xFFE09321);
  final Color border =
      isBlocked ? accent.withValues(alpha: 0.55) : const Color(0xFF2A2A2A);

  return Container(
    decoration: BoxDecoration(
      color: const Color(0xFF151515),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: border, width: 1),
    ),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: isBlocked
              ? 'Click to remove this tag from the blocklist!'
              : 'Click to add this tag to the blocklist!',
          child: InkWell(
            onTap: inFlight ? null : () => onToggleTagBlock(tag),
            borderRadius: BorderRadius.circular(999),
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: accent,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: inFlight
                    ? const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.black),
                        ),
                      )
                    : Icon(
                        isBlocked ? Icons.remove : Icons.add,
                        size: 16,
                        color: Colors.black,
                      ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        InkWell(
          onTap: (allowSearch && tag.isSearchable)
              ? () => onSearch(tag.name)
              : null,
          child: Text(
            tag.name,
            style: TextStyle(
              fontSize: 13,
              color: (allowSearch && tag.isSearchable)
                  ? Colors.white
                  : Colors.white70,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
}
