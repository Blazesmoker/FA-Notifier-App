import 'package:material_ui/material_ui.dart';

class NotesSelectionControls extends StatelessWidget {
  const NotesSelectionControls({
    super.key,
    required this.selectedCount,
    required this.onSelectAll,
    required this.onExit,
    this.showAllPages = false,
    this.onSelectAllPages,
    this.progressText,
    this.onCancelFetching,
  });

  static const double bottomClearance = 76;
  static const double progressBottomClearance = 132;
  static const Color _accent = Color(0xFFE09321);
  static const Color _surface = Color(0xFF1A1A1A);
  static const BorderSide _border = BorderSide(color: Color(0xFF3A3A3A));

  final int selectedCount;
  final VoidCallback? onSelectAll;
  final VoidCallback? onExit;
  final bool showAllPages;
  final VoidCallback? onSelectAllPages;
  final String? progressText;
  final VoidCallback? onCancelFetching;

  Widget _textBubble(String text, VoidCallback? onTap) {
    return Material(
      color: _surface,
      elevation: 8,
      shape: const StadiumBorder(side: _border),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        child: SizedBox(
          height: 48,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Center(
              widthFactor: 1,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  text,
                  maxLines: 1,
                  style: TextStyle(
                    color: onTap == null ? Colors.grey : _accent,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (progressText != null) ...[
            Material(
              color: Colors.grey[850],
              elevation: 8,
              shape: const StadiumBorder(side: _border),
              clipBehavior: Clip.antiAlias,
              child: SizedBox(
                height: 48,
                child: Padding(
                  padding: const EdgeInsets.only(left: 14),
                  child: Row(
                    children: [
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(_accent),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            progressText!,
                            maxLines: 1,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Cancel selecting all pages',
                        onPressed: onCancelFetching,
                        icon: const Icon(Icons.close, color: Colors.red),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: _textBubble(
                        'Select All ($selectedCount)',
                        onSelectAll,
                      ),
                    ),
                    if (showAllPages) ...[
                      const SizedBox(width: 8),
                      Flexible(
                        child: _textBubble('Select All Pages', onSelectAllPages),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Material(
                color: _surface,
                elevation: 8,
                shape: const CircleBorder(side: _border),
                clipBehavior: Clip.antiAlias,
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: IconButton(
                    tooltip: 'Exit selection',
                    onPressed: onExit,
                    icon: Icon(
                      Icons.close,
                      color: onExit == null ? Colors.grey : Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
