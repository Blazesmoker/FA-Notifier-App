import 'dart:convert';

import 'package:fanotifier/features/notes/domain/note_image_preview_mode.dart';
import 'package:fanotifier/features/notes/domain/note_image_preview_link.dart';
import 'package:fanotifier/features/notes/domain/note_submission_preview.dart';
import 'package:fanotifier/features/notes/domain/note_submission_preview_repository.dart';
import 'package:fanotifier/features/profile/domain/avatar_image_data.dart';
import 'package:fanotifier/features/profile/domain/profile_media_export_repository.dart';
import 'package:fanotifier/features/profile/presentation/image_inspect_screen.dart';
import 'package:fanotifier/shared/fa/user_submitted_html_linkifier.dart';
import 'package:fanotifier/shared/navigation/fa_link_handler.dart';
import 'package:fanotifier/shared/widgets/fa_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart' as html_pkg;
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:provider/provider.dart';

bool noteBodyContainsPreviewLinks(
  String content, {
  required bool isHtml,
}) {
  return _prepareNoteMarkup(content, isHtml: isHtml).urls.isNotEmpty;
}

class NoteBodyWithPreviews extends StatefulWidget {
  const NoteBodyWithPreviews({
    super.key,
    required this.content,
    required this.isHtml,
    required this.mode,
    required this.repository,
  });

  final String content;
  final bool isHtml;
  final NoteImagePreviewMode mode;
  final NoteSubmissionPreviewRepository repository;

  @override
  State<NoteBodyWithPreviews> createState() =>
      _NoteBodyWithPreviewsState();
}

class _NoteBodyWithPreviewsState extends State<NoteBodyWithPreviews> {
  late _PreparedNoteMarkup _prepared;
  final Map<String, _OccurrenceState> _states = {};

  @override
  void initState() {
    super.initState();
    _prepare();
    _scheduleAutomaticLoads();
  }

  @override
  void didUpdateWidget(covariant NoteBodyWithPreviews oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.content != widget.content ||
        oldWidget.isHtml != widget.isHtml) {
      _prepare();
      _scheduleAutomaticLoads();
    }
    if (oldWidget.mode != widget.mode) {
      _scheduleAutomaticLoads();
    }
  }

  void _prepare() {
    _prepared = _prepareNoteMarkup(widget.content, isHtml: widget.isHtml);
    final removedIds = _states.keys
        .where((id) => !_prepared.urls.containsKey(id))
        .toList();
    for (final id in removedIds) {
      _states.remove(id)?.dispose();
    }
    for (final entry in _prepared.urls.entries) {
      _states.putIfAbsent(entry.key, () => _OccurrenceState(entry.value));
    }
  }

  @override
  void dispose() {
    for (final state in _states.values) {
      state.dispose();
    }
    super.dispose();
  }

  void _scheduleAutomaticLoads() {
    if (widget.mode != NoteImagePreviewMode.always) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.mode != NoteImagePreviewMode.always) return;
      for (final id in _prepared.urls.keys) {
        final state = _states[id];
        if (state != null && state.status == _PreviewStatus.idle) {
          _load(id, expandAfterLoad: true);
        }
      }
    });
  }

  Future<void> _load(String id, {required bool expandAfterLoad}) async {
    final state = _states[id];
    if (state == null || state.status == _PreviewStatus.loading) return;
    state.setLoading();
    try {
      final preview = await widget.repository.loadPreview(
        state.submissionUrl,
        confirmNsfw: _showNsfwConfirmationDialog,
      );
      if (!mounted) return;
      state.setResult(preview, expandAfterLoad: expandAfterLoad);
    } catch (_) {
      if (!mounted) return;
      state.setError();
    }
  }

  Future<bool> _showNsfwConfirmationDialog() async {
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) {
            return AlertDialog(
              title: const Text('NSFW Content'),
              content: const Text(
                'This post is marked NSFW. Are you sure you want to view it?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  style: TextButton.styleFrom(backgroundColor: Colors.black),
                  child: const Text('No', style: TextStyle(color: Colors.white)),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  style: TextButton.styleFrom(backgroundColor: Colors.black),
                  child: const Text('Yes', style: TextStyle(color: Colors.red)),
                ),
              ],
            );
          },
        ) ??
        false;
  }

  void _toggleExpanded(String id) {
    final state = _states[id];
    if (state?.preview == null) return;
    state!.toggleExpanded();
  }

  Widget _buildControl(String id) {
    final state = _states[id];
    if (state == null) return const SizedBox.shrink();
    return SelectionContainer.disabled(
      child: ListenableBuilder(
        listenable: state,
        builder: (context, _) => _buildControlValue(id, state),
      ),
    );
  }

  Widget _buildControlValue(String id, _OccurrenceState state) {
    switch (state.status) {
      case _PreviewStatus.idle:
        return _buildPreviewAction(
          label: 'show image',
          onTap: () => _load(id, expandAfterLoad: true),
        );
      case _PreviewStatus.loading:
        return _buildPreviewAction(
          label: 'show image',
          isLoading: true,
        );
      case _PreviewStatus.error:
        return _buildPreviewAction(
          label: 'show image',
          hasError: true,
          onTap: () => _load(id, expandAfterLoad: true),
        );
      case _PreviewStatus.loaded:
        final preview = state.preview;
        if (preview == null) return const SizedBox.shrink();
        return _buildPreviewAction(
          label: state.expanded ? 'hide image' : 'show image',
          onTap: () => _toggleExpanded(id),
        );
    }
  }

  Widget _buildPreviewAction({
    required String label,
    VoidCallback? onTap,
    bool isLoading = false,
    bool hasError = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 2, top: 2, right: 4),
      child: Semantics(
        button: true,
        label: label,
        child: Material(
          color: const Color(0xFF2A2A2A),
          shape: const StadiumBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 4,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.image_search,
                    color: Color(0xFFE09321),
                    size: 24,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    label,
                    style: const TextStyle(
                      color: Color(0xFFE09321),
                      fontSize: 16,
                    ),
                  ),
                  if (isLoading) ...[
                    const SizedBox(width: 6),
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ],
                  if (hasError) ...[
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.error_outline,
                      color: Colors.redAccent,
                      size: 18,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildExpanded(String id, double width) {
    final state = _states[id];
    if (state == null) return const SizedBox.shrink();
    return SelectionContainer.disabled(
      child: ListenableBuilder(
        listenable: state,
        builder: (context, _) {
          final preview = state.preview;
          return AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            switchInCurve: Curves.easeInOut,
            switchOutCurve: Curves.easeInOut,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: child,
            ),
            child: state.expanded && preview != null
                ? SizedBox(
                    key: ValueKey('expanded-$id'),
                    width: width,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: _buildLargePreview(id, preview),
                    ),
                  )
                : SizedBox.shrink(key: ValueKey('collapsed-$id')),
          );
        },
      ),
    );
  }

  Widget _buildLargePreview(
    String id,
    NoteSubmissionPreview preview,
  ) {
    return Center(
      child: Stack(
        children: [
          GestureDetector(
            onTap: () => _openImageInspector(preview),
            onLongPressStart: (details) =>
                _showImageMenu(details.globalPosition, preview),
            child: Image.memory(
              preview.imageBytes,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
              gaplessPlayback: true,
            ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF2A2A2A).withValues(alpha: 0.65),
                border: Border.all(
                  color: Colors.white12,
                  width: 1,
                ),
              ),
              child: IconButton(
                onPressed: () => _toggleExpanded(id),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: 48,
                  height: 48,
                ),
                splashRadius: 24,
                tooltip: 'Hide image',
                icon: const Icon(
                  Icons.image_not_supported_outlined,
                  color: Color(0xFFE09321),
                  size: 24,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  AvatarImageData _imageData(NoteSubmissionPreview preview) {
    return AvatarImageData(
      bytes: preview.imageBytes,
      extension: preview.extension,
    );
  }

  Future<void> _openImageInspector(NoteSubmissionPreview preview) async {
    await Navigator.push(
      context,
      ImageInspectScreen.route(
        imageUrl: preview.imageUrl,
        imageData: _imageData(preview),
      ),
    );
  }

  Future<void> _showImageMenu(
    Offset position,
    NoteSubmissionPreview preview,
  ) async {
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: const [
        PopupMenuItem(value: 'download', child: Text('Download')),
        PopupMenuItem(value: 'share', child: Text('Share image')),
      ],
    );
    if (!mounted || selected == null) return;
    if (selected == 'download') {
      await _downloadImage(preview);
    } else if (selected == 'share') {
      await _shareImage(preview);
    }
  }

  Future<void> _downloadImage(NoteSubmissionPreview preview) async {
    final repository = context.read<ProfileMediaExportRepository>();
    if (!await repository.requestImageExportPermission()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Photo permission denied'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }
    final saved = await repository.saveImageToGallery(_imageData(preview));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          saved ? 'Image saved to gallery!' : 'Failed to save image to gallery.',
        ),
        backgroundColor: saved ? Colors.green : Colors.red,
      ),
    );
  }

  Future<void> _shareImage(NoteSubmissionPreview preview) async {
    final repository = context.read<ProfileMediaExportRepository>();
    if (!await repository.requestImageExportPermission()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Permission denied'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }
    await repository.shareImage(_imageData(preview));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final previewWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width - 32;
        return html_pkg.Html(
          data: _prepared.html,
          style: {
            'body': html_pkg.Style(
              margin: html_pkg.Margins.zero,
              padding: html_pkg.HtmlPaddings.zero,
              color: Colors.white,
              fontSize: html_pkg.FontSize(16),
            ),
            'b': html_pkg.Style(fontWeight: FontWeight.bold),
            'strong': html_pkg.Style(fontWeight: FontWeight.bold),
            'i': html_pkg.Style(fontStyle: FontStyle.italic),
            '.bbcode_i': html_pkg.Style(fontStyle: FontStyle.italic),
            'u': html_pkg.Style(textDecoration: TextDecoration.underline),
            '.bbcode_u': html_pkg.Style(
              textDecoration: TextDecoration.underline,
            ),
            '.bbcode_center': html_pkg.Style(
              display: html_pkg.Display.block,
              textAlign: TextAlign.center,
            ),
            '.bbcode_left': html_pkg.Style(
              display: html_pkg.Display.block,
              textAlign: TextAlign.left,
            ),
            '.bbcode_right': html_pkg.Style(
              display: html_pkg.Display.block,
              textAlign: TextAlign.right,
            ),
            'a': html_pkg.Style(
              color: const Color(0xFFE09321),
              textDecoration: TextDecoration.none,
            ),
          },
          onLinkTap: (url, _, __) {
            if (url != null) handleFALink(context, url);
          },
          extensions: [
            faHtmlImageExtension(),
            html_pkg.TagExtension.inline(
              tagsToExtend: {'note-preview-control'},
              builder: (extensionContext) {
                final id = extensionContext.attributes['data-id'];
                return WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: Transform.translate(
                    offset: const Offset(0, -1.0),
                    child: id == null
                        ? const SizedBox.shrink()
                        : _buildControl(id),
                  ),
                );
              },
            ),
            html_pkg.TagExtension(
              tagsToExtend: {'note-preview-expanded'},
              builder: (extensionContext) {
                final id = extensionContext.attributes['data-id'];
                return id == null
                    ? const SizedBox.shrink()
                    : _buildExpanded(id, previewWidth);
              },
            ),
          ],
        );
      },
    );
  }
}

enum _PreviewStatus {
  idle,
  loading,
  loaded,
  error,
}

class _OccurrenceState extends ChangeNotifier {
  _OccurrenceState(this.submissionUrl);

  final String submissionUrl;
  _PreviewStatus status = _PreviewStatus.idle;
  NoteSubmissionPreview? preview;
  bool expanded = false;

  void setLoading() {
    status = _PreviewStatus.loading;
    notifyListeners();
  }

  void setResult(
    NoteSubmissionPreview? value, {
    required bool expandAfterLoad,
  }) {
    preview = value;
    status = value == null ? _PreviewStatus.error : _PreviewStatus.loaded;
    expanded = value != null && expandAfterLoad;
    notifyListeners();
  }

  void setError() {
    status = _PreviewStatus.error;
    expanded = false;
    notifyListeners();
  }

  void toggleExpanded() {
    if (preview == null) return;
    expanded = !expanded;
    notifyListeners();
  }
}

class _PreparedNoteMarkup {
  const _PreparedNoteMarkup(this.html, this.urls);

  final String html;
  final Map<String, String> urls;
}

_PreparedNoteMarkup _prepareNoteMarkup(
  String content, {
  required bool isHtml,
}) {
  final rawSource = isHtml
      ? content
      : const HtmlEscape(HtmlEscapeMode.element)
          .convert(content)
          .replaceAll('\r\n', '\n')
          .replaceAll('\n', '<br>');
  final source = linkifyBareWebUrlsInHtml(rawSource);
  final document = html_parser.parse('<div id="note-preview-root">$source</div>');
  final root = document.querySelector('#note-preview-root')!;
  final urls = <String, String>{};
  var nextId = 0;

  String addOccurrence(String submissionUrl) {
    final id = 'note-preview-${nextId++}';
    urls[id] = submissionUrl;
    return id;
  }

  for (final anchor in root.querySelectorAll('a[href]').toList()) {
    final href = anchor.attributes['href'];
    final previewUrl = href == null ? null : _previewUrlFrom(href);
    if (previewUrl == null) continue;
    final id = addOccurrence(previewUrl);
    final parent = anchor.parentNode;
    if (parent == null) continue;
    final anchorIndex = parent.nodes.indexOf(anchor);
    parent.nodes.insert(
      anchorIndex + 1,
      _previewElement('note-preview-control', id),
    );
    parent.nodes.insert(
      anchorIndex + 2,
      _previewElement('note-preview-expanded', id),
    );
  }

  return _PreparedNoteMarkup(root.innerHtml, urls);
}

dom.Element _previewElement(String tag, String id) {
  return dom.Element.tag(tag)..attributes['data-id'] = id;
}

String? _previewUrlFrom(String value) {
  var candidate = value.trim();
  while (candidate.isNotEmpty &&
      const {'.', ',', ';', ':', '!', '?', ')', ']', '}'}
          .contains(candidate[candidate.length - 1])) {
    candidate = candidate.substring(0, candidate.length - 1);
  }
  return NoteImagePreviewLink.tryParse(candidate)?.url;
}
