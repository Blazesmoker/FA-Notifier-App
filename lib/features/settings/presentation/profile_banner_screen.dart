import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'package:fanotifier/features/image_tools/domain/image_optimizer_models.dart';
import 'package:fanotifier/features/image_tools/presentation/image_optimizer_launcher.dart';
import 'package:fanotifier/features/settings/domain/fur_affinity_profile_management_models.dart';
import 'package:fanotifier/features/settings/domain/fur_affinity_settings_repository.dart';
import 'package:fanotifier/features/settings/presentation/fur_affinity_settings_widgets.dart';
import 'package:fanotifier/features/upload/domain/upload_file_picker_gateway.dart';
import 'package:fanotifier/features/upload/domain/upload_selected_file.dart';
import 'package:fanotifier/shared/widgets/fa_network_image.dart';
import 'package:fanotifier/shared/widgets/pulsating_loading_indicator.dart';

class ProfileBannerScreen extends StatefulWidget {
  const ProfileBannerScreen({super.key, this.onChanged});

  final VoidCallback? onChanged;

  @override
  State<ProfileBannerScreen> createState() => _ProfileBannerScreenState();
}

class _ProfileBannerScreenState extends State<ProfileBannerScreen> {
  static const _constraints = ImageOptimizationConstraints(
    title: 'Prepare Profile Banner',
    allowedFormats: {ImageOutputFormat.jpeg, ImageOutputFormat.png, ImageOutputFormat.gif},
    maxBytes: 10 * 1024 * 1024,
    maxWidth: 1850,
    maxHeight: 300,
    preferredFormat: ImageOutputFormat.jpeg,
    siteConvertsToJpeg: true,
    cropAspectRatio: 1850 / 300,
    allowAnimatedFrameSelection: true,
    allowStretch: true,
  );

  late final FurAffinitySettingsRepository _repository;
  late final UploadFilePickerGateway _picker;
  FaProfileBannerSnapshot? _snapshot;
  UploadSelectedFile? _selected;
  bool _loading = true;
  bool _saving = false;
  bool _removing = false;
  String? _error;

  bool get _working => _saving || _removing;

  @override
  void initState() {
    super.initState();
    _repository = context.read<FurAffinitySettingsRepository>();
    _picker = context.read<UploadFilePickerGateway>();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final snapshot = await _repository.loadProfileBanner();
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$error';
      });
    }
  }

  Future<void> _pick({required bool optimize}) async {
    if (_working) return;
    final selected = optimize
        ? await pickAndOptimizeImage(context, _picker, _constraints)
        : await pickImageSource(context, _picker);
    if (!mounted || selected == null) return;
    setState(() => _selected = selected);
  }

  Future<void> _upload() async {
    final snapshot = _snapshot;
    final selected = _selected;
    if (snapshot == null || selected == null || _working) return;
    setState(() => _saving = true);
    final result = await _repository.uploadProfileBanner(
      form: snapshot,
      file: FaUploadFile(
        bytes: selected.bytes,
        fileName: selected.fileName,
        contentType: selected.mimeType,
      ),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    showSettingsMutationSnackBar(
      context,
      section: 'Profile Banner',
      result: result,
      successText: 'Profile banner updated successfully.',
      failureText: 'Profile banner update failed',
    );
    if (result.success) {
      widget.onChanged?.call();
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _remove() async {
    final snapshot = _snapshot;
    final currentBannerUri = snapshot?.currentBannerUri;
    if (snapshot == null ||
        currentBannerUri == null ||
        !snapshot.canRemove ||
        _working) {
      return;
    }
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: furAffinitySettingsGroup,
            title: const Text('Remove profile banner?'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: AspectRatio(
                    aspectRatio: 1850 / 300,
                    child: FaNetworkImage(
                      currentBannerUri.toString(),
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'This removes the current banner from your Fur Affinity profile.',
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text(
                  'Remove',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;
    setState(() => _removing = true);
    final result = await _repository.removeProfileBanner(snapshot);
    if (!mounted) return;
    setState(() => _removing = false);
    showSettingsMutationSnackBar(
      context,
      section: 'Profile Banner',
      result: result,
      successText: 'Profile banner removed successfully.',
      failureText: 'Profile banner removal failed',
    );
    if (result.success) {
      widget.onChanged?.call();
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(
        splashFactory: NoSplash.splashFactory,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
      ),
      child: Scaffold(
        backgroundColor: furAffinitySettingsBackground,
        appBar: AppBar(
        title: const Text('Profile Banner'),
        actions: [
          IconButton(
            tooltip: 'Crop, resize or compress an image',
            onPressed: _working ? null : () => _pick(optimize: true),
            icon: const Icon(
              Icons.photo_size_select_small,
              color: furAffinitySettingsAccent,
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: 12),
        maintainBottomViewPadding: true,
        child: _loading
            ? const Center(
              child: PulsatingLoadingIndicator(
                size: 78,
                assetPath: 'assets/icons/fathemed.png',
              ),
            )
            : _snapshot == null
                ? Center(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: furAffinitySettingsAccent,
                        foregroundColor: Colors.black,
                      ),
                      onPressed: _load,
                      child: Text(_error ?? 'Retry'),
                    ),
                  )
                : ListView(
                  padding: const EdgeInsets.only(top: 8, bottom: 36),
                  children: [
                    const IosSettingsSection(
                      header: 'Manage Profile Banner',
                      footer: 'Profile banners must not be rated higher than the site General Rating under the Upload Policy. Language may contain profanity but may not use it in a sexual context; dialogue may be suggestive, contain sexual innuendo or adult themes, or express views users may find offensive, disrespectful, or controversial. Banners must be free of nudity, including genitalia or their outlines, sheaths, female areolae or nipples, and detailed or exaggerated bulges. They must be free of sexual or excessive fetish themes except brief affection such as a kiss or hug. Use only art you are allowed to use; Fur Affinity may remove a banner at the copyright or character owner’s request.',
                      children: [
                        IosSettingsRow(
                          title: 'General Rating Required',
                          subtitle: 'Language, nudity / sexual situations, sexual or excessive fetish themes, and copyright restrictions all apply.',
                          leading: Icon(Icons.shield_outlined, color: furAffinitySettingsAccent),
                        ),
                      ],
                    ),
                    if (_snapshot!.currentBannerUri != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                        child: _CurrentBannerCard(
                          imageUri: _snapshot!.currentBannerUri!,
                          removing: _removing,
                          onRemove: _snapshot!.canRemove ? _remove : null,
                        ),
                      ),
                    IosSettingsSection(
                      header: 'Upload Profile Banner',
                      footer: 'Accepted File Formats - JPG, PNG, GIF\nMax File Size - 10 MB\nMax Dimensions - 1850×300 pixels\nUploaded images will be converted to JPG and shrunken if they exceed the maximum dimensions. For the best experience, use 1850×300 or an image close to that aspect ratio.',
                      children: [
                        IosSettingsRow(
                          title: _selected?.fileName ?? 'Choose Image',
                          subtitle: _selected == null ? 'Select an original without changing it.' : '${(_selected!.bytes.lengthInBytes / 1024).toStringAsFixed(1)} KB selected',
                          leading: const Icon(Icons.image_outlined, color: furAffinitySettingsAccent),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: _working ? null : () => _pick(optimize: false),
                        ),
                        IosSettingsRow(
                          title: 'Crop, Resize or Compress',
                          subtitle: 'Choose the exact banner position and create a separate 1850×300 copy. Your original stays untouched.',
                          leading: const Icon(Icons.photo_size_select_small, color: furAffinitySettingsAccent),
                          onTap: _working ? null : () => _pick(optimize: true),
                        ),
                      ],
                    ),
                    if (_selected != null) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: _WebsiteBannerPreview(bytes: _selected!.bytes),
                      ),
                    ],
                    IosSettingsActionButton(
                      label: 'Upload Profile Banner',
                      loading: _saving,
                      onPressed: _selected == null || _working ? null : _upload,
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _CurrentBannerCard extends StatelessWidget {
  const _CurrentBannerCard({
    required this.imageUri,
    required this.removing,
    required this.onRemove,
  });

  final Uri imageUri;
  final bool removing;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: furAffinitySettingsGroup,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: furAffinitySettingsDivider),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(12, 11, 12, 9),
              child: Text(
                'Current Banner',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            AspectRatio(
              aspectRatio: 1850 / 300,
              child: ColoredBox(
                color: Colors.black,
                child: FaNetworkImage(
                  imageUri.toString(),
                  fit: BoxFit.cover,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: SizedBox(
                height: 42,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.withValues(alpha: 0.82),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor:
                        Colors.red.withValues(alpha: 0.32),
                    disabledForegroundColor:
                        Colors.white.withValues(alpha: 0.55),
                  ),
                  onPressed: removing ? null : onRemove,
                  icon: removing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.delete_outline_rounded),
                  label: Text(
                    removing ? 'Removing…' : 'Remove Profile Banner',
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WebsiteBannerPreview extends StatelessWidget {
  const _WebsiteBannerPreview({required this.bytes});

  final Uint8List bytes;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: furAffinitySettingsGroup,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: furAffinitySettingsDivider),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 34,
              decoration: BoxDecoration(
                color: const Color(0xFF171717),
                border: Border.all(color: furAffinitySettingsDivider),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: const Row(
                children: [
                  Icon(
                    Icons.pets_rounded,
                    size: 17,
                    color: furAffinitySettingsAccent,
                  ),
                  SizedBox(width: 7),
                  Text(
                    'Fur Affinity profile header',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            AspectRatio(
              aspectRatio: 1850 / 300,
              child: Image.memory(
                bytes,
                fit: BoxFit.cover,
                gaplessPlayback: true,
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Text(
                'Website preview · recommended 1850×300 frame. Fur Affinity converts the upload to JPG and may shrink it.',
                style: TextStyle(
                  color: furAffinitySettingsSecondary,
                  fontSize: 12,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
