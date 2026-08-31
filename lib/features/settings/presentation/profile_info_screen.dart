import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'package:fanotifier/features/settings/domain/fur_affinity_settings_repository.dart';
import 'package:fanotifier/features/settings/presentation/fur_affinity_settings_widgets.dart';
import 'package:fanotifier/features/settings/presentation/profile_info_controller.dart';
import 'package:fanotifier/shared/utils/bbcode_context_menu.dart';
import 'package:fanotifier/shared/widgets/confirm_close_dialog.dart';
import 'package:fanotifier/shared/widgets/pulsating_loading_indicator.dart';
import 'package:fanotifier/shared/widgets/tags_and_codes_webview_widget.dart';

class ProfileInfoScreen extends StatefulWidget {
  const ProfileInfoScreen({super.key, this.onChanged});

  final VoidCallback? onChanged;

  @override
  State<ProfileInfoScreen> createState() => _ProfileInfoScreenState();
}

class _ProfileInfoScreenState extends State<ProfileInfoScreen> {
  late final ProfileInfoController _controller;
  bool _allowPop = false;

  @override
  void initState() {
    super.initState();
    _controller = ProfileInfoController(
      context.read<FurAffinitySettingsRepository>(),
    )..load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final result = await _controller.save();
    if (!mounted || result == null) return;
    if (result.success) widget.onChanged?.call();
    showSettingsMutationSnackBar(
      context,
      section: 'Profile Info',
      result: result,
      successText: 'Profile information updated successfully.',
      failureText: 'Profile information update failed',
    );
  }

  Future<void> _close() async {
    if (_controller.saving) return;
    if (_controller.dirty) {
      final discard = await ConfirmCloseDialog.show(
        context,
        title: 'Discard changes?',
        message: 'Your profile information changes have not been saved.',
      );
      if (!mounted || !discard) return;
    }
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop(_controller.didSave);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => ValueListenableBuilder<bool>(
        valueListenable: _controller.dirtyListenable,
        builder: (context, dirty, child) => PopScope(
          canPop: _allowPop || (!dirty && !_controller.saving),
          onPopInvokedWithResult: (didPop, result) {
            if (!didPop) _close();
          },
          child: child!,
        ),
        child: Theme(
          data: Theme.of(context).copyWith(
            splashFactory: NoSplash.splashFactory,
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
          ),
          child: Scaffold(
            backgroundColor: furAffinitySettingsBackground,
            appBar: AppBar(
              title: const Text('Profile Info'),
              actions: [
                ValueListenableBuilder<bool>(
                  valueListenable: _controller.dirtyListenable,
                  builder: (context, dirty, child) => SettingsSaveAction(
                    dirty: dirty,
                    saving: _controller.saving,
                    onPressed: _save,
                  ),
                ),
              ],
            ),
            body: SafeArea(
              top: false,
              minimum: const EdgeInsets.only(bottom: 12),
              maintainBottomViewPadding: true,
              child: _body(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _body() {
    if (_controller.loading) {
      return const Center(
        child: PulsatingLoadingIndicator(
          size: 78,
          assetPath: 'assets/icons/fathemed.png',
        ),
      );
    }
    if (_controller.snapshot == null) {
      return Center(
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: furAffinitySettingsAccent,
            foregroundColor: Colors.black,
          ),
          onPressed: _controller.load,
          child: Text(settingsLoadFailureText('${_controller.loadError}')),
        ),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.only(top: 8, bottom: 36),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          IosSettingsSection(
            header: 'User Profile',
            footer: 'Selecting text allows you to use tags and formatting.',
            children: [_text('profileinfo', 'Profile Information', multiline: true, tagsHelp: true)],
          ),
          IosSettingsSection(
            header: 'Account Personalization',
            footer: 'Setting a Display Name overrides how your username looks on the site. This is purely visual and does not apply when your original username is required, including login, password reset, text macros such as :iconusername:, your userpage URL, or generated upload file names. Display Names allow alphanumeric characters, spaces, dots, underscores, dashes, and tildes; emojis and non-Latin characters are not allowed. They must be 3–30 characters. The change cooldown is 7 days when available; FA+ reduces it to 1 day. User Titles appear next to your name on most content you post and must stay SFW.',
            children: [
              _text('display_name', 'Display Name', subtitle: 'Maximum 30 characters.'),
              _text('custom_title', 'User Title', subtitle: 'Maximum 32 characters. Keep it SFW.'),
            ],
          ),
          IosSettingsSection(
            header: 'Personal Information',
            footer: 'Share as much or as little personal information as you want. Text fields in this section allow up to 255 characters.',
            children: [
              _text('species', 'Species'),
              _select('mood', 'Mood'),
              _text('music', 'Favorite Music'),
              _text('favoritemovie', 'Favorite Movie'),
              _text('favoritegame', 'Favorite Game'),
              _text('favoriteplatform', 'Favorite Gaming Platform'),
              _text('favoriteartist', 'Favorite Artist'),
              _text('favoriteanimal', 'Favorite Animal'),
              _text('favoritefood', 'Favorite Food'),
              _text('favoritewebsite', 'Favorite Website'),
              _text('quote', 'Favorite Quote', multiline: true),
            ],
          ),
          IosSettingsSection(
            footer: 'Select the featured submission to display on your user page. Choose Disabled if you do not want one.',
            children: [_select('featured', 'Featured Submission')],
          ),
          IosSettingsSection(
            footer: 'Select the profile picture to display on your user page. Submissions must be located in your Scraps gallery. Choose Disabled to use no Profile ID submission.',
            children: [_select('profile_pic', 'Profile ID')],
          ),
          IosSettingsSection(
            header: 'Block List',
            footer: 'The hide-content option controls whether content by blocked users is censored. Blocked users cannot comment on your submissions or journals, shout on your userpage, or send you notes. Enter ONE correctly spelled username per line or blocking will not work. Use the text box only to import or export the block list. Up to 5,000 lines can be updated, and the cooldown occurs regardless of list size. The change cooldown is 7 days when available; FA+ raises the import limit to 10,000.',
            children: [
              _select('hide_blocked_user_content', 'Hide Blocked User Content'),
              _text('blocklist', 'Blocked Users', multiline: true),
            ],
          ),
          IosSettingsSection(
            footer: 'Maximum length: 1,024 characters. Selecting text allows you to use tags and formatting.',
            children: [_text('submissionfooter', 'Submission Footer', multiline: true, tagsHelp: true)],
          ),
          IosSettingsSection(
            footer: 'Selecting text allows you to use tags and formatting.',
            children: [_text('journalheader', 'Journal Header', multiline: true, tagsHelp: true)],
          ),
          IosSettingsSection(
            footer: 'Selecting text allows you to use tags and formatting.',
            children: [_text('journalfooter', 'Journal Footer', multiline: true, tagsHelp: true)],
          ),
        ],
      ),
    );
  }

  Widget _text(
    String name,
    String title, {
    String? subtitle,
    bool multiline = false,
    bool tagsHelp = false,
  }) {
    final field = _controller.field(name);
    final textController = _controller.controller(name);
    final compact = const {
      'profileinfo',
      'submissionfooter',
      'journalheader',
      'journalfooter',
    }.contains(name);
    return Padding(
      padding: EdgeInsets.fromLTRB(16, compact ? 4 : 8, 8, compact ? 4 : 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                  ),
                ),
              ),
              if (tagsHelp) const InfoIconButton(),
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(subtitle, style: const TextStyle(color: furAffinitySettingsSecondary, fontSize: 12)),
          ],
          SizedBox(height: compact ? 3 : 6),
          TextField(
            controller: textController,
            enabled: field?.enabled ?? false,
            cursorColor: furAffinitySettingsAccent,
            style: const TextStyle(color: Colors.white),
            minLines: 1,
            maxLines: multiline ? null : 1,
            maxLength: field?.maxLength ?? (name == 'submissionfooter' ? 1024 : null),
            contextMenuBuilder:
                tagsHelp ? BBCodeContextMenu.builder(textController) : null,
            decoration: InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.symmetric(
                horizontal: 12,
                vertical: compact ? 4.5 : 9,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _select(String name, String title) {
    final field = _controller.field(name);
    final options = field?.options ?? const [];
    final current = _controller.value(name);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: InkWell(
        onTap: field?.enabled ?? false
            ? () async {
                final selected = await showSettingsChoice(
                  context,
                  title: title,
                  currentValue: current,
                  options: options,
                );
                if (selected != null) _controller.setValue(name, selected);
              }
            : null,
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: title,
            labelStyle: const TextStyle(color: Colors.white),
            enabled: field?.enabled ?? false,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _selectedOptionLabel(options, current),
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
              Icon(
                Icons.arrow_drop_down,
                color: field?.enabled ?? false
                    ? furAffinitySettingsAccent
                    : Colors.white38,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _selectedOptionLabel(Iterable options, String current) {
    for (final option in options) {
      if (option.value == current) return option.label;
    }
    return '';
  }
}
