import 'package:FANotifier/model/shout.dart';
import 'package:FANotifier/screens/shout_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:html/parser.dart' as html_parser;

class UserProfileShoutsSection extends StatelessWidget {
  final List<Shout> shouts;
  final bool isOwnProfile;
  final bool isSelectionMode;
  final int selectedShoutCount;
  final int currentShoutPage;
  final int totalShoutPages;
  final bool isLoadingMoreShouts;
  final Future<void> Function(BuildContext context) onOpenPostShout;
  final Future<void> Function() onLoadMoreShouts;
  final Future<void> Function(int index, Shout shout) onConfirmDeleteShout;
  final void Function() onToggleSelectionMode;
  final void Function(Shout shout) onToggleShoutSelection;

  const UserProfileShoutsSection({
    Key? key,
    required this.shouts,
    required this.isOwnProfile,
    required this.isSelectionMode,
    required this.selectedShoutCount,
    required this.currentShoutPage,
    required this.totalShoutPages,
    required this.isLoadingMoreShouts,
    required this.onOpenPostShout,
    required this.onLoadMoreShouts,
    required this.onConfirmDeleteShout,
    required this.onToggleSelectionMode,
    required this.onToggleShoutSelection,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1F1F1F), Colors.black],
            stops: [0.0, 0.06],
          ),
          borderRadius: BorderRadius.circular(8.0),
        ),
        padding: const EdgeInsets.only(top: 16.0, bottom: 64.0, right: 0.0, left: 0.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Text(
              'Shouts',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 0.0),
            Padding(
              padding: const EdgeInsets.fromLTRB(12.0, 12.0, 12.0, 0.0),
              child: Row(
                children: [
                  if (isOwnProfile) ...[
                    GestureDetector(
                      onTap: onToggleSelectionMode,
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: isSelectionMode
                              ? const Color(0xFFE09321)
                              : const Color(0xFF232323),
                          borderRadius: BorderRadius.circular(10.0),
                        ),
                        child: const Icon(
                          Icons.check_circle_outline,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8.0),
                  ],
                  Expanded(
                    child: GestureDetector(
                      onTap: () async {
                        await onOpenPostShout(context);
                      },
                      child: Container(
                        height: 48,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16.0,
                          vertical: 10.0,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF232323),
                          borderRadius: BorderRadius.circular(10.0),
                        ),
                        child: Row(
                          children: const [
                            Expanded(
                              child: Text(
                                'Type here to leave a shout!',
                                style: TextStyle(color: Colors.white54),
                              ),
                            ),
                            Icon(Icons.send, color: Colors.white54),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) {
                return ClipRect(
                  child: FadeTransition(
                    opacity: animation,
                    child: SizeTransition(
                      sizeFactor: animation,
                      axisAlignment: -1.0,
                      child: child,
                    ),
                  ),
                );
              },
              child: isSelectionMode
                  ? Padding(
                      key: const ValueKey('selection-mode-label'),
                      padding: const EdgeInsets.fromLTRB(12.0, 8.0, 12.0, 12.0),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          selectedShoutCount == 0
                              ? 'Selection mode enabled'
                              : '$selectedShoutCount shout${selectedShoutCount == 1 ? '' : 's'} selected',
                          style: const TextStyle(
                            color: Color(0xFFE09321),
                            fontSize: 13.0,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    )
                  : const SizedBox(
                      key: ValueKey('selection-mode-spacer'),
                      height: 12.0,
                    ),
            ),
            if (shouts.isEmpty)
              const Text(
                'No shouts yet. Be the first to shout!',
                style: TextStyle(color: Colors.white70),
              )
            else
              Column(
                children: [
                  ListView.separated(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: shouts.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 8.0),
                    itemBuilder: (context, index) {
                      final shout = shouts[index];
                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: isSelectionMode
                            ? () => onToggleShoutSelection(shout)
                            : null,
                        onLongPress: isSelectionMode
                            ? () => onToggleShoutSelection(shout)
                            : () async {
                          final plainText = html_parser.parse(shout.text).body?.text ?? shout.text;
                          final action = await showDialog<String>(
                            context: context,
                            builder: (context) {
                              final maxHeight = MediaQuery.of(context).size.height * 0.6;
                              return AlertDialog(
                                scrollable: true,
                                titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                                title: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(4.0),
                                      child: Image.network(
                                        shout.avatarUrl,
                                        width: 40,
                                        height: 40,
                                        fit: BoxFit.cover,
                                        errorBuilder: (context, error, stackTrace) {
                                          return Image.asset(
                                            'assets/images/defaultpic.gif',
                                            width: 40,
                                            height: 40,
                                            fit: BoxFit.cover,
                                          );
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            shout.username,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          Text(
                                            '${shout.symbol} ${shout.profileNickname}',
                                            style: const TextStyle(
                                              color: Color(0xFFE09321),
                                              fontSize: 14,
                                              fontWeight: FontWeight.normal,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                content: ConstrainedBox(
                                  constraints: BoxConstraints(maxHeight: maxHeight),
                                  child: SingleChildScrollView(
                                    child: Text(
                                      plainText,
                                      style: const TextStyle(color: Colors.white),
                                    ),
                                  ),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(context, 'copy'),
                                    child: const Text('Copy text'),
                                  ),
                                  if (isOwnProfile)
                                    TextButton(
                                      onPressed: () => Navigator.pop(context, 'delete'),
                                      style: TextButton.styleFrom(foregroundColor: Colors.red),
                                      child: const Text("Delete"),
                                    ),
                                ],
                              );
                            },
                          );
                          if (action == 'copy') {
                            await Clipboard.setData(ClipboardData(text: plainText));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Shout text copied'),
                                backgroundColor: Colors.green,
                              ),
                            );
                          } else if (action == 'delete') {
                            await onConfirmDeleteShout(index, shout);
                          }
                        },
                        child: AbsorbPointer(
                          absorbing: isSelectionMode,
                          child: ShoutWidget(
                            shout: shout,
                            isSelectionMode: isSelectionMode,
                            isSelected: shout.selected,
                            onDelete: () {
                              if (isOwnProfile) {
                                onConfirmDeleteShout(index, shout);
                              }
                            },
                          ),
                        ),
                      );
                    },
                  ),
                  if (currentShoutPage < totalShoutPages)
                    Padding(
                      padding: const EdgeInsets.only(top: 16.0),
                      child: isLoadingMoreShouts
                          ? const CircularProgressIndicator(
                              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFE09321)),
                            )
                          : ElevatedButton(
                              onPressed: onLoadMoreShouts,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFE09321),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8.0),
                                ),
                              ),
                              child: const Text(
                                'Load More',
                                style: TextStyle(
                                  fontSize: 16.0,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
