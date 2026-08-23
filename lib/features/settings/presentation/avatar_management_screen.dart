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

class AvatarManagementScreen extends StatefulWidget {
  const AvatarManagementScreen({super.key, this.onChanged});

  final VoidCallback? onChanged;

  @override
  State<AvatarManagementScreen> createState() => _AvatarManagementScreenState();
}

class _AvatarManagementScreenState extends State<AvatarManagementScreen> {
  static const _constraints = ImageOptimizationConstraints(
    title: 'Optimize Avatar',
    allowedFormats: {ImageOutputFormat.gif, ImageOutputFormat.jpeg, ImageOutputFormat.png},
    maxBytes: 75 * 1024,
    maxWidth: 100,
    maxHeight: 100,
    preferredFormat: ImageOutputFormat.gif,
    cropAspectRatio: 1,
  );

  late final FurAffinitySettingsRepository _repository;
  late final UploadFilePickerGateway _picker;
  FaAvatarManagementSnapshot? _snapshot;
  final List<FaAvatarGalleryItem> _gallery = [];
  UploadSelectedFile? _selected;
  Uri? _currentUri;
  Uint8List? _currentBytes;
  bool _loading = true;
  bool _working = false;
  String? _error;

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
      final snapshot = await _repository.loadAvatarManagement();
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _gallery
          ..clear()
          ..addAll(snapshot.gallery);
        _currentUri = snapshot.currentAvatarUri;
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
    setState(() => _working = true);
    final result = await _repository.uploadAvatar(
      form: snapshot,
      file: FaUploadFile(
        bytes: selected.bytes,
        fileName: selected.fileName,
        contentType: selected.mimeType,
      ),
    );
    if (!mounted) return;
    setState(() {
      _working = false;
      if (result.success) {
        _currentBytes = selected.bytes;
        _currentUri = null;
        _selected = null;
      }
    });
    if (result.success) widget.onChanged?.call();
    showSettingsMutationSnackBar(
      context,
      section: 'Avatar Management',
      result: result,
      successText: 'Avatar uploaded successfully.',
      failureText: 'Avatar upload failed',
    );
  }

  Future<void> _choose(FaAvatarGalleryItem item) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Select this avatar?'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FaNetworkImage(
                  item.imageUri.toString(),
                  width: 160,
                  height: 160,
                  fit: BoxFit.contain,
                ),
                const SizedBox(height: 14),
                const Text('Are you sure you want to use this as your current avatar?'),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: furAffinitySettingsAccent,
                  foregroundColor: Colors.black,
                ),
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Select Avatar'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;
    setState(() => _working = true);
    final result = await _repository.chooseAvatar(item.chooseUri);
    if (!mounted) return;
    setState(() {
      _working = false;
      if (result.success) {
        _currentUri = item.imageUri;
        _currentBytes = null;
      }
    });
    if (result.success) widget.onChanged?.call();
    showSettingsMutationSnackBar(
      context,
      section: 'Avatar Management',
      result: result,
      successText: 'Avatar selected successfully.',
      failureText: 'Avatar selection failed',
    );
  }

  Future<void> _remove(FaAvatarGalleryItem item) async {
    final uri = item.removeUri;
    if (uri == null) return;
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Remove avatar?'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FaNetworkImage(item.imageUri.toString(), width: 130, height: 130, fit: BoxFit.contain),
                const SizedBox(height: 14),
                const Text('This removes the avatar from your Personal Avatar Gallery.'),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Remove', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;
    setState(() => _working = true);
    final result = await _repository.removeAvatar(uri);
    if (!mounted) return;
    setState(() {
      _working = false;
      if (result.success) {
        _gallery.removeWhere((entry) => entry.id == item.id);
      }
    });
    if (result.success) widget.onChanged?.call();
    showSettingsMutationSnackBar(
      context,
      section: 'Avatar Management',
      result: result,
      successText: 'Avatar removed successfully.',
      failureText: 'Avatar removal failed',
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_working,
      child: Theme(
        data: Theme.of(context).copyWith(
          splashFactory: NoSplash.splashFactory,
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
        ),
        child: Scaffold(
          backgroundColor: furAffinitySettingsBackground,
          appBar: AppBar(
          title: const Text('Avatar Management'),
          actions: [
            IconButton(
              tooltip: 'Resize or compress an image',
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
                child: PulsatingLoadingIndicator(size: 78, assetPath: 'assets/icons/fathemed.png'),
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
                  : Stack(
                    children: [
                      ListView(
                        padding: const EdgeInsets.only(top: 8, bottom: 36),
                        children: [
                          const IosSettingsSection(
                            header: 'Manage Avatar',
                            footer: 'Avatars may not be rated higher than the site General Rating. Language may contain profanity but may not use it in a sexual context; dialogue may be suggestive, contain sexual innuendo or adult themes, or express views users may find offensive, disrespectful, or controversial. Avatars may not be adult or pornographic, may contain only mild non-gory, non-pervasive, and non-sexual violence, and must not flash rapidly enough to risk seizures. Use only art you are allowed to use; Fur Affinity may remove it at the copyright or character owner’s request.',
                            children: [
                              IosSettingsRow(
                                title: 'General Rating Required',
                                subtitle: 'Language, nudity / sexual situations, violence, rapidly flashing imagery, and copyright restrictions all apply.',
                                leading: Icon(Icons.shield_outlined, color: furAffinitySettingsAccent),
                              ),
                            ],
                          ),
                          IosSettingsSection(
                            header: 'Current Avatar',
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(16),
                                child: Center(child: _currentAvatar()),
                              ),
                            ],
                          ),
                          IosSettingsSection(
                            header: 'Upload Avatar',
                            footer: 'Accepted File Formats - GIF. JPG and PNG may be uploaded but Fur Affinity converts them to GIF, with possible quality loss.\nMax File Size - 75 KB\nMax Dimensions - 100×100 pixels',
                            children: [
                              IosSettingsRow(
                                title: _selected?.fileName ?? 'Choose Image',
                                subtitle: _selected == null ? 'Select an original without changing it.' : '${(_selected!.bytes.lengthInBytes / 1024).toStringAsFixed(1)} KB selected',
                                leading: const Icon(Icons.image_outlined, color: furAffinitySettingsAccent),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () => _pick(optimize: false),
                              ),
                              IosSettingsRow(
                                title: 'Resize or Compress',
                                subtitle: 'Creates and saves a separate changed copy. Animated GIF frames and timing are preserved.',
                                leading: const Icon(Icons.photo_size_select_small, color: furAffinitySettingsAccent),
                                onTap: () => _pick(optimize: true),
                              ),
                            ],
                          ),
                          if (_selected != null) ...[
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              child: Image.memory(_selected!.bytes, height: 140, fit: BoxFit.contain),
                            ),
                            IosSettingsActionButton(
                              label: 'Upload Avatar',
                              loading: _working,
                              onPressed: _upload,
                            ),
                          ],
                          IosSettingsSection(
                            header: 'Personal Avatar Gallery',
                            footer: 'Tap an avatar to preview it and confirm before making it current. Use the remove button to delete an avatar from this gallery.',
                            children: [
                              if (_gallery.isEmpty)
                                const IosSettingsRow(title: 'No personal avatars found.')
                              else
                                Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: GridView.builder(
                                    shrinkWrap: true,
                                    physics: const NeverScrollableScrollPhysics(),
                                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: 3,
                                      mainAxisSpacing: 10,
                                      crossAxisSpacing: 10,
                                    ),
                                    itemCount: _gallery.length,
                                    itemBuilder: (context, index) => _galleryTile(_gallery[index]),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                      if (_working)
                        const Positioned.fill(
                          child: ColoredBox(
                            color: Color(0x88000000),
                            child: Center(child: CircularProgressIndicator()),
                          ),
                        ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _currentAvatar() {
    if (_currentBytes != null) {
      return Image.memory(_currentBytes!, width: 150, height: 150, fit: BoxFit.contain);
    }
    if (_currentUri != null) {
      return FaNetworkImage(_currentUri.toString(), width: 150, height: 150, fit: BoxFit.contain);
    }
    return const SizedBox(
      width: 150,
      height: 150,
      child: Center(child: Text('No current avatar found.')),
    );
  }

  Widget _galleryTile(FaAvatarGalleryItem item) {
    return Stack(
      children: [
        Positioned(
          left: 0,
          top: 14,
          right: 14,
          bottom: 0,
          child: InkWell(
            onTap: () => _choose(item),
            child: FaNetworkImage(item.imageUri.toString(), fit: BoxFit.cover),
          ),
        ),
        if (item.removeUri != null)
          Positioned(
            right: 0,
            top: 0,
            child: Opacity(
              opacity: 0.6,
              child: SizedBox.square(
                dimension: 28,
                child: Material(
                  color: Colors.black,
                  shape: const CircleBorder(),
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: 28,
                      height: 28,
                    ),
                    iconSize: 16,
                    tooltip: 'Remove avatar',
                    onPressed: () => _remove(item),
                    icon: const Icon(
                      Icons.delete_outline,
                      color: Colors.redAccent,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
