import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:provider/provider.dart';

import 'package:fanotifier/features/settings/domain/fur_affinity_contacts_models.dart';
import 'package:fanotifier/features/settings/domain/fur_affinity_settings_repository.dart';
import 'package:fanotifier/features/settings/presentation/contacts_and_media_controller.dart';
import 'package:fanotifier/features/settings/presentation/fur_affinity_settings_widgets.dart';
import 'package:fanotifier/shared/utils/external_link_launcher.dart';
import 'package:fanotifier/shared/widgets/confirm_close_dialog.dart';
import 'package:fanotifier/shared/widgets/fa_network_image.dart';
import 'package:fanotifier/shared/widgets/pulsating_loading_indicator.dart';

class ContactsAndMediaScreen extends StatefulWidget {
  const ContactsAndMediaScreen({super.key, this.onChanged});

  final VoidCallback? onChanged;

  @override
  State<ContactsAndMediaScreen> createState() =>
      _ContactsAndMediaScreenState();
}

class _ContactsAndMediaScreenState extends State<ContactsAndMediaScreen> {
  late final ContactsAndMediaController _controller;
  bool _allowPop = false;

  @override
  void initState() {
    super.initState();
    _controller = ContactsAndMediaController(
      context.read<FurAffinitySettingsRepository>(),
    );
    _controller.load();
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
      section: 'Contacts & Social Media',
      result: result,
      successText: 'Contact information updated successfully.',
      failureText: 'Contact information update failed',
    );
  }

  Future<void> _requestClose() async {
    if (_controller.saving) return;
    if (_controller.dirty) {
      final close = await ConfirmCloseDialog.show(
        context,
        title: 'Discard changes?',
        message: 'Your contact information changes have not been saved.',
      );
      if (!mounted || !close) return;
    }
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop(_controller.didSave);
    });
  }

  Future<void> _openVerificationLink(Uri uri) async {
    var opened = false;
    try {
      opened = await tryLaunchExternalUri(uri);
    } catch (_) {}
    if (!mounted || opened) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Colors.red.shade700,
        content: const Text('Could not open this contact link.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return PopScope(
          canPop: _allowPop ||
              (!_controller.dirty && !_controller.saving),
          onPopInvokedWithResult: (didPop, result) {
            if (!didPop) _requestClose();
          },
          child: Scaffold(
            backgroundColor: furAffinitySettingsBackground,
            appBar: AppBar(
              title: const Text('Contacts & Social Media'),
              actions: [
                SettingsSaveAction(
                  dirty: _controller.dirty && _controller.valid,
                  saving: _controller.saving,
                  onPressed: _save,
                ),
              ],
            ),
            body: SafeArea(
              top: false,
              minimum: const EdgeInsets.only(bottom: 12),
              maintainBottomViewPadding: true,
              child: _buildBody(),
            ),
          ),
        );
      },
    );
  }

  Widget _buildBody() {
    if (_controller.loading) {
      return const Center(
        child: PulsatingLoadingIndicator(
          size: 78,
          assetPath: 'assets/icons/fathemed.png',
        ),
      );
    }
    final form = _controller.form;
    if (_controller.loadError != null || form == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                settingsLoadFailureText(
                  _controller.loadError ?? 'Unknown error',
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 14),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: furAffinitySettingsAccent,
                  foregroundColor: Colors.black,
                ),
                onPressed: _controller.load,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final itemBuilders = <WidgetBuilder>[];
    for (final section in form.sections) {
      itemBuilders.add(
        (_) => Padding(
          padding: const EdgeInsets.fromLTRB(32, 8, 32, 7),
          child: Text(
            section.title.toUpperCase(),
            style: const TextStyle(
              color: furAffinitySettingsSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
        ),
      );
      for (var index = 0; index < section.fields.length; index++) {
        final field = section.fields[index];
        final isFirst = index == 0;
        final isLast = index == section.fields.length - 1;
        itemBuilders.add(
          (_) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: furAffinitySettingsGroup,
                borderRadius: BorderRadius.vertical(
                  top: isFirst ? const Radius.circular(12) : Radius.zero,
                  bottom: isLast ? const Radius.circular(12) : Radius.zero,
                ),
              ),
              child: Column(
                children: [
                  if (!isFirst)
                    const Divider(
                      height: 1,
                      thickness: 0.5,
                      indent: 16,
                      endIndent: 16,
                      color: furAffinitySettingsDivider,
                    ),
                  _ContactFieldRow(
                    field: field,
                    controller: _controller.controllerFor(field.name),
                    enabled: _controller.enabled(field.name),
                    validationStatus: _controller.validationStatus(field),
                    verificationUri: _controller.verificationUri(field),
                    onOpenVerificationLink: _openVerificationLink,
                  ),
                ],
              ),
            ),
          ),
        );
      }
      itemBuilders.add(
        (_) => section.description == null
            ? const SizedBox(height: 10)
            : Padding(
                padding: const EdgeInsets.fromLTRB(32, 7, 32, 10),
                child: Text(
                  section.description!,
                  style: const TextStyle(
                    color: furAffinitySettingsSecondary,
                    fontSize: 12,
                    height: 1.3,
                  ),
                ),
              ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(top: 8, bottom: 36),
      scrollCacheExtent: const ScrollCacheExtent.pixels(500),
      itemCount: itemBuilders.length,
      itemBuilder: (context, index) => itemBuilders[index](context),
    );
  }
}

class _ContactFieldRow extends StatelessWidget {
  const _ContactFieldRow({
    required this.field,
    required this.controller,
    required this.enabled,
    required this.validationStatus,
    required this.verificationUri,
    required this.onOpenVerificationLink,
  });

  final FaContactField field;
  final TextEditingController controller;
  final bool enabled;
  final FaContactValidationStatus validationStatus;
  final Uri? verificationUri;
  final ValueChanged<Uri> onOpenVerificationLink;

  TextInputType get _keyboardType {
    if (field.inputType == 'email') return TextInputType.emailAddress;
    if (field.inputType == 'number') return TextInputType.number;
    if (field.validationRules.contains(FaContactValidationRule.url)) {
      return TextInputType.url;
    }
    return TextInputType.text;
  }

  @override
  Widget build(BuildContext context) {
    final foreground = enabled ? Colors.white : Colors.white38;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 32,
                height: 32,
                child: field.iconUri == null
                    ? const Icon(
                        Icons.link_rounded,
                        color: furAffinitySettingsSecondary,
                      )
                    : FaNetworkImage(
                        field.iconUri.toString(),
                        width: 32,
                        height: 32,
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) => const Icon(
                          Icons.link_rounded,
                          color: furAffinitySettingsSecondary,
                        ),
                      ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  field.label,
                  style: TextStyle(color: foreground, fontSize: 16),
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Stack(
            children: [
              TextField(
                controller: controller,
                enabled: enabled,
                keyboardType: _keyboardType,
                maxLength: field.maxLength,
                autocorrect: false,
                enableSuggestions: false,
                cursorColor: furAffinitySettingsAccent,
                style: TextStyle(
                  color: enabled ? Colors.white : Colors.white38,
                  fontSize: 15,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  counterText: '',
                  filled: true,
                  fillColor: furAffinitySettingsField,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 11,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(9),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(9),
                    borderSide: const BorderSide(
                      color: furAffinitySettingsAccent,
                    ),
                  ),
                  disabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(9),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              if (controller.text.isEmpty && field.placeholder.isNotEmpty)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 18, right: 12),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: SizedBox(
                          width: double.infinity,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              field.placeholder,
                              maxLines: 1,
                              softWrap: false,
                              style: const TextStyle(
                                color: furAffinitySettingsSecondary,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          if (validationStatus != FaContactValidationStatus.none) ...[
            const SizedBox(height: 7),
            Row(
              children: [
                Icon(
                  validationStatus == FaContactValidationStatus.valid
                      ? Icons.check_circle_outline
                      : Icons.error_outline,
                  size: 15,
                  color: validationStatus == FaContactValidationStatus.valid
                      ? Colors.lightGreenAccent
                      : Colors.deepOrangeAccent,
                ),
                const SizedBox(width: 5),
                Text(
                  validationStatus == FaContactValidationStatus.valid
                      ? 'Should work'
                      : 'May not work',
                  style: TextStyle(
                    color: validationStatus == FaContactValidationStatus.valid
                        ? Colors.lightGreenAccent
                        : Colors.deepOrangeAccent,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ],
          if (verificationUri != null) ...[
            const SizedBox(height: 6),
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => onOpenVerificationLink(verificationUri!),
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          verificationUri.toString(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: furAffinitySettingsAccent,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      const SizedBox(width: 5),
                      const Icon(
                        Icons.open_in_new_rounded,
                        color: furAffinitySettingsAccent,
                        size: 14,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
