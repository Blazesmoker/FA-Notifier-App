import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:fanotifier/core/preferences/translator_settings_provider.dart';
import 'package:fanotifier/features/profile/domain/profile_shout_text_repository.dart';
import 'package:fanotifier/features/profile/domain/shout.dart';
import 'package:fanotifier/features/profile/presentation/shout_widget.dart';
import 'package:fanotifier/features/profile/presentation/user_profile_shout_selection_controller.dart';
import 'package:fanotifier/shared/translation/ios_scroll_recovery.dart';
import 'package:fanotifier/shared/translation/native_translate_launcher.dart';
import 'package:fanotifier/shared/translation/translation_service.dart';
import 'package:fanotifier/shared/utils/bbcode_context_menu.dart';
import 'package:fanotifier/shared/widgets/fa_network_image.dart';
import 'package:material_ui/material_ui.dart';

class UserProfileShoutsSection extends StatelessWidget {
  const UserProfileShoutsSection({
    super.key,
    required this.shouts,
    required this.isOwnProfile,
    required this.selectionController,
    required this.currentShoutPage,
    required this.totalShoutPages,
    required this.isLoadingMoreShouts,
    required this.onOpenPostShout,
    required this.onLoadMoreShouts,
    required this.onConfirmDeleteShout,
    required this.onToggleSelectionMode,
    required this.onToggleShoutSelection,
  });

  final List<Shout> shouts;
  final bool isOwnProfile;
  final UserProfileShoutSelectionController selectionController;
  final int currentShoutPage;
  final int totalShoutPages;
  final ValueListenable<bool> isLoadingMoreShouts;
  final Future<void> Function(BuildContext context) onOpenPostShout;
  final Future<void> Function() onLoadMoreShouts;
  final Future<void> Function(int index, Shout shout) onConfirmDeleteShout;
  final VoidCallback onToggleSelectionMode;
  final ValueChanged<Shout> onToggleShoutSelection;

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
        padding: const EdgeInsets.only(
          top: 16.0,
          bottom: 64.0,
          right: 0.0,
          left: 0.0,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _buildHeader(context),
            if (shouts.isEmpty)
              const Text(
                'No shouts yet. Be the first to shout!',
                style: TextStyle(color: Colors.white70),
              )
            else
              _buildShoutsList(),
            if (currentShoutPage < totalShoutPages) _buildPagination(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Column(
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
        ValueListenableBuilder<bool>(
          valueListenable: selectionController.selectionMode,
          builder: (context, isSelectionMode, child) {
            return Column(
              children: [
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
                            child: const Row(
                              children: [
                                Expanded(
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerLeft,
                                    child: Padding(
                                      padding: EdgeInsets.only(right: 12.0),
                                      child: Text(
                                        'Type here to leave a shout!',
                                        style: TextStyle(color: Colors.white54),
                                      ),
                                    ),
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
                          alignment: const AlignmentDirectional(-1.0, -1.0),
                          child: child,
                        ),
                      ),
                    );
                  },
                  child: isSelectionMode
                      ? Padding(
                          key: const ValueKey('selection-mode-label'),
                          padding:
                              const EdgeInsets.fromLTRB(12.0, 8.0, 12.0, 12.0),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: ValueListenableBuilder<int>(
                              valueListenable: selectionController.selectedCount,
                              builder: (context, selectedCount, child) {
                                return Text(
                                  selectedCount == 0
                                      ? 'Selection mode enabled'
                                      : '$selectedCount shout${selectedCount == 1 ? '' : 's'} selected',
                                  style: const TextStyle(
                                    color: Color(0xFFE09321),
                                    fontSize: 13.0,
                                    fontWeight: FontWeight.w600,
                                  ),
                                );
                              },
                            ),
                          ),
                        )
                      : const SizedBox(
                          key: ValueKey('selection-mode-spacer'),
                          height: 12.0,
                        ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildShoutsList() {
    return ListView.separated(
      padding: EdgeInsets.zero,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: shouts.length,
      separatorBuilder: (context, index) => const SizedBox(height: 8.0),
      itemBuilder: (context, index) {
        final shout = shouts[index];
        return KeyedSubtree(
          key: ValueKey<String>(
            'profile-shout-${selectionController.selectionId(shout)}',
          ),
          child: ValueListenableBuilder<bool>(
            valueListenable: selectionController.selectionMode,
            builder: (context, isSelectionMode, child) {
              return ValueListenableBuilder<bool>(
                valueListenable: selectionController.selectionFor(shout),
                builder: (context, isSelected, child) {
                  return _buildShout(
                    context,
                    index,
                    shout,
                    isSelectionMode,
                    isSelected,
                  );
                },
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildShout(
    BuildContext context,
    int index,
    Shout shout,
    bool isSelectionMode,
    bool isSelected,
  ) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: isSelectionMode ? () => onToggleShoutSelection(shout) : null,
      onLongPress: isSelectionMode
          ? () => onToggleShoutSelection(shout)
          : () => _openShoutActions(context, index, shout),
      child: AbsorbPointer(
        absorbing: isSelectionMode,
        child: ShoutWidget(
          shout: shout,
          isSelectionMode: isSelectionMode,
          isSelected: isSelected,
          onDelete: () {
            if (isOwnProfile) {
              onConfirmDeleteShout(index, shout);
            }
          },
        ),
      ),
    );
  }

  Future<void> _openShoutActions(
    BuildContext context,
    int index,
    Shout shout,
  ) async {
    final plainText = context
        .read<ProfileShoutTextRepository>()
        .plainTextFromHtml(shout.text);
    final translatorSettings = context.read<TranslatorSettingsProvider>();
    final translationService = TranslationService.instance;
    var dialogOpen = true;
    var selectedShoutText = '';
    StateSetter? updateDialog;
    final recoveryScope = IosScrollRecoveryScope();
    String? action;
    try {
      action = await showDialog<String>(
        context: context,
        builder: (context) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              updateDialog = setDialogState;
              final showTranslateButton =
                  translationService.shouldOfferTranslation(
                plainText,
                translatorSettings,
                onLanguageDetectionUpdated: () {
                  if (dialogOpen) {
                    updateDialog?.call(() {});
                  }
                },
              );
              final maxHeight = MediaQuery.of(context).size.height * 0.6;
              return AlertDialog(
                scrollable: true,
                titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                title: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4.0),
                      child: FaNetworkImage(
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
                  child: IosScrollRecoverySingleChildScrollView(
                    recoveryScope: recoveryScope,
                    child: SelectionArea(
                      onSelectionChanged: (content) {
                        selectedShoutText = content?.plainText ?? '';
                      },
                      contextMenuBuilder: ReadOnlySelectionContextMenu.builder(
                        selectedTextProvider: () => selectedShoutText,
                        includeIosTranslate: true,
                        recoveryScope: recoveryScope,
                      ),
                      child: Text(
                        plainText,
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                ),
                actions: [
                  if (showTranslateButton)
                    IconButton(
                      tooltip: 'Translate',
                      icon: const Icon(
                        Icons.g_translate,
                        color: Colors.white,
                      ),
                      onPressed: () => NativeTranslateLauncher.open(
                        plainText,
                        targetLanguageCode:
                            translatorSettings.targetLanguageCode,
                        recoveryScope: recoveryScope,
                      ),
                    ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, 'copy'),
                    child: const Text('Copy text'),
                  ),
                  if (isOwnProfile || shout.ownShoutDeleteUrl != null)
                    TextButton(
                      onPressed: () => Navigator.pop(context, 'delete'),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.red,
                      ),
                      child: const Text('Delete'),
                    ),
                ],
              );
            },
          );
        },
      );
    } finally {
      dialogOpen = false;
      recoveryScope.dispose();
    }
    if (action == 'copy') {
      await Clipboard.setData(ClipboardData(text: plainText));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Shout text copied'),
          backgroundColor: Colors.green,
        ),
      );
    } else if (action == 'delete') {
      await onConfirmDeleteShout(index, shout);
    }
  }

  Widget _buildPagination() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(top: 16.0),
        child: ValueListenableBuilder<bool>(
          valueListenable: isLoadingMoreShouts,
          builder: (context, isLoading, child) {
            if (isLoading) {
              return const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(
                  Color(0xFFE09321),
                ),
              );
            }
            return ElevatedButton(
              onPressed: onLoadMoreShouts,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE09321),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24.0,
                  vertical: 12.0,
                ),
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
            );
          },
        ),
      ),
    );
  }
}
