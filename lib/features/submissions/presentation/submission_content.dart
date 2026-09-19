import 'package:flutter/rendering.dart' show SelectedContent;
import 'package:material_ui/material_ui.dart';

import 'package:fanotifier/features/submissions/domain/submission_file_download_result.dart';
import 'package:fanotifier/features/submissions/domain/submission_attachment.dart';
import 'package:fanotifier/features/submissions/presentation/widgets/submission_attachment_fallback.dart';
import 'package:fanotifier/features/submissions/presentation/widgets/submission_attachment_styles.dart';
import 'package:fanotifier/features/submissions/presentation/widgets/submission_audio_player.dart';
import 'package:fanotifier/features/submissions/presentation/widgets/submission_document_viewer.dart';

class SubmissionContent extends StatefulWidget {
  const SubmissionContent({
    required this.attachment,
    required this.onDownload,
    required this.onShowMessage,
    required this.routeDetached,
    this.selectionAreaKey,
    this.onSelectionChanged,
    this.contextMenuBuilder,
    super.key,
  });

  final SubmissionAttachment attachment;
  final Future<SubmissionFileDownloadResult> Function() onDownload;
  final void Function(String message, Color backgroundColor) onShowMessage;
  final bool routeDetached;
  final GlobalKey<SelectionAreaState>? selectionAreaKey;
  final ValueChanged<SelectedContent?>? onSelectionChanged;
  final Widget Function(BuildContext, SelectableRegionState)?
      contextMenuBuilder;

  @override
  State<SubmissionContent> createState() =>
      _SubmissionContentState();
}

class _SubmissionContentState
    extends State<SubmissionContent> {
  bool _isDownloading = false;
  bool _showFullFileName = false;

  @override
  void didUpdateWidget(covariant SubmissionContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.attachment.fileName != widget.attachment.fileName) {
      _showFullFileName = false;
    }
  }

  Future<void> _download() async {
    if (_isDownloading) return;
    setState(() {
      _isDownloading = true;
    });
    final result = await widget.onDownload();
    if (!mounted) return;
    setState(() {
      _isDownloading = false;
    });
    _showDownloadResult(result);
  }

  void _showDownloadResult(SubmissionFileDownloadResult result) {
    switch (result.status) {
      case SubmissionFileDownloadStatus.saved:
        _showMessage('File saved.', Colors.green);
        return;
      case SubmissionFileDownloadStatus.cancelled:
        return;
      case SubmissionFileDownloadStatus.httpFailure:
        final statusCode = result.statusCode;
        _showMessage(
          statusCode == null
              ? 'Failed to download file.'
              : 'Failed to download file. HTTP $statusCode.',
          Colors.red,
        );
        return;
      case SubmissionFileDownloadStatus.failed:
        _showMessage('Failed to download file.', Colors.red);
        return;
    }
  }

  void _showMessage(String message, Color backgroundColor) {
    widget.onShowMessage(message, backgroundColor);
  }

  @override
  Widget build(BuildContext context) {
    final attachment = widget.attachment;
    final isMusic =
        attachment.kind == SubmissionAttachmentKind.music;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 12.0),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: attachmentSurfaceColor,
          border: Border.all(color: const Color(0xFF2A2A2A)),
          borderRadius: BorderRadius.circular(10.0),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(
                    isMusic ? Icons.audiotrack : Icons.description_outlined,
                    color: const Color(0xFFE09321),
                    size: 27.0,
                  ),
                  const SizedBox(width: 10.0),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Tooltip(
                          message: _showFullFileName
                              ? 'Use compact file name'
                              : 'Show full file name',
                          child: InkWell(
                            borderRadius: BorderRadius.circular(4.0),
                            onTap: () {
                              setState(() {
                                _showFullFileName = !_showFullFileName;
                              });
                            },
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 1.0),
                              child: Text(
                                attachment.fileName,
                                maxLines: _showFullFileName ? null : 2,
                                overflow: _showFullFileName
                                    ? TextOverflow.visible
                                    : TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize:
                                      _showFullFileName ? 11.0 : 15.0,
                                  height: _showFullFileName ? 1.2 : null,
                                  fontWeight: _showFullFileName
                                      ? FontWeight.w500
                                      : FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 2.0),
                        Text(
                          isMusic
                              ? 'Music · ${attachment.extension.toUpperCase()}'
                              : 'Document · ${attachment.extension.toUpperCase()}',
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 12.0,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8.0),
                  Tooltip(
                    message: 'Download',
                    child: SizedBox.square(
                      dimension: 44.0,
                      child: OutlinedButton(
                        onPressed: _isDownloading ? null : _download,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFE09321),
                          side: const BorderSide(color: Color(0xFF5A4A32)),
                          padding: EdgeInsets.zero,
                          shape: const CircleBorder(),
                        ),
                        child: _isDownloading
                            ? const SizedBox(
                                width: 17.0,
                                height: 17.0,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.0,
                                ),
                              )
                            : const Icon(
                                Icons.download_outlined,
                                size: 20.0,
                              ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12.0),
              _buildContent(attachment),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent(SubmissionAttachment attachment) {
    if (attachment.supportsPlayback) {
      return SubmissionAudioPlayer(
        url: attachment.playbackUrl!,
        routeDetached: widget.routeDetached,
      );
    }
    if (attachment.kind == SubmissionAttachmentKind.music) {
      return const AttachmentFallback(
        icon: Icons.music_off_outlined,
        message:
            'MIDI playback is not available. Download the original file to open it.',
      );
    }
    if (attachment.supportsPreview) {
      return SubmissionDocumentViewer(
        attachment: attachment,
        routeDetached: widget.routeDetached,
        selectionAreaKey: widget.selectionAreaKey,
        onSelectionChanged: widget.onSelectionChanged,
        contextMenuBuilder: widget.contextMenuBuilder,
      );
    }
    return const AttachmentFallback(
      icon: Icons.file_download_outlined,
      message:
          'Preview is not available for legacy DOC files. Download the original file to open it.',
    );
  }
}
