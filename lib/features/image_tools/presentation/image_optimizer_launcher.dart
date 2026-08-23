import 'package:material_ui/material_ui.dart';
import 'package:flutter/cupertino.dart' show CupertinoPageRoute;

import 'package:fanotifier/features/image_tools/domain/image_optimizer_models.dart';
import 'package:fanotifier/features/image_tools/presentation/image_optimizer_screen.dart';
import 'package:fanotifier/features/upload/domain/upload_file_picker_gateway.dart';
import 'package:fanotifier/features/upload/domain/upload_selected_file.dart';

Future<UploadSelectedFile?> pickImageSource(
  BuildContext context,
  UploadFilePickerGateway gateway,
) async {
  final source = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Select source'),
      content: const Text('Choose an image from Files or Gallery.'),
      actions: [
        TextButton.icon(
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFFE09321),
          ),
          onPressed: () => Navigator.of(context).pop('files'),
          icon: const Icon(Icons.insert_drive_file_outlined),
          label: const Text('Files'),
        ),
        TextButton.icon(
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFFE09321),
          ),
          onPressed: () => Navigator.of(context).pop('gallery'),
          icon: const Icon(Icons.image_outlined),
          label: const Text('Gallery'),
        ),
      ],
    ),
  );
  if (source == 'files') return gateway.pickFile();
  if (source == 'gallery') return gateway.pickGalleryImage();
  return null;
}

Future<UploadSelectedFile?> pickAndOptimizeImage(
  BuildContext context,
  UploadFilePickerGateway gateway,
  ImageOptimizationConstraints constraints,
) async {
  final selected = await pickImageSource(context, gateway);
  if (selected == null || !context.mounted) return null;
  final result = await Navigator.of(context).push<ImageOptimizationResult>(
    CupertinoPageRoute(
      builder: (_) => ImageOptimizerScreen(
        originalBytes: selected.bytes,
        originalFileName: selected.fileName,
        constraints: constraints,
      ),
    ),
  );
  if (result == null) return null;
  return UploadSelectedFile.fromBytes(
    fileName: result.fileName,
    bytes: result.bytes,
    extension: result.format.extension,
  );
}
