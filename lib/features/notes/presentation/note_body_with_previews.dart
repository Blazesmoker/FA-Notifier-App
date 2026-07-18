import 'dart:convert';

import 'package:FANotifier/features/notes/domain/note_image_preview_mode.dart';
import 'package:FANotifier/features/notes/domain/note_submission_preview.dart';
import 'package:FANotifier/features/notes/domain/note_submission_preview_repository.dart';
import 'package:FANotifier/features/profile/domain/avatar_image_data.dart';
import 'package:FANotifier/features/profile/domain/profile_media_export_repository.dart';
import 'package:FANotifier/features/profile/presentation/image_inspect_screen.dart';
import 'package:FANotifier/shared/navigation/fa_link_handler.dart';
import 'package:FANotifier/shared/widgets/fa_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart' as html_pkg;
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:provider/provider.dart';

bool noteBodyContainsSubmissionLinks(
  String content, {
  required bool isHtml,
}) {
  return isHtml
      ? _submissionCandidatePattern.hasMatch(content)
      : _submissionTextPattern.hasMatch(content);
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
          _load(id, expandAfterLoad: false);
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
        if (widget.mode == NoteImagePreviewMode.always) {
          return const SizedBox(
            width: 50,
            height: 50,
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        return _buildIconControl(
          icon: Icons.image_search,
          color: const Color(0xFFE09321),
          size: 34.5,
          onTap: () => _load(id, expandAfterLoad: true),
        );
      case _PreviewStatus.loading:
        final size = widget.mode == NoteImagePreviewMode.always ? 50.0 : 28.0;
        return SizedBox(
          width: size,
          height: size,
          child: const Center(
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        );
      case _PreviewStatus.error:
        return _buildIconControl(
          icon: Icons.error_outline,
          color: Colors.redAccent,
          size: widget.mode == NoteImagePreviewMode.always ? 50 : 28,
          onTap: () => _load(
            id,
            expandAfterLoad: widget.mode == NoteImagePreviewMode.manual,
          ),
        );
      case _PreviewStatus.loaded:
        final preview = state.preview;
        if (preview == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(right: 4),
          child: GestureDetector(
            onTap: () => _toggleExpanded(id),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Image.memory(
                preview.imageBytes,
                width: 50,
                height: 50,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.high,
                gaplessPlayback: true,
              ),
            ),
          ),
        );
    }
  }

  Widget _buildIconControl({
    required IconData icon,
    required Color color,
    required double size,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: size,
      height: size,
      child: IconButton(
        padding: EdgeInsets.zero,
        constraints: BoxConstraints.tight(Size.square(size)),
        splashRadius: size / 2,
        icon: Icon(icon, color: color, size: size == 50 ? 28 : 24),
        onPressed: onTap,
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
                      child: _buildLargePreview(preview),
                    ),
                  )
                : SizedBox.shrink(key: ValueKey('collapsed-$id')),
          );
        },
      ),
    );
  }

  Widget _buildLargePreview(NoteSubmissionPreview preview) {
    return Center(
      child: GestureDetector(
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
            html_pkg.TagExtension(
              tagsToExtend: {'note-preview-control'},
              builder: (extensionContext) {
                final id = extensionContext.attributes['data-id'];
                return id == null
                    ? const SizedBox.shrink()
                    : _buildControl(id);
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

final RegExp _submissionTextPattern = RegExp(
  r'https?://(?:www\.)?furaffinity\.net/view/\d+/?',
  caseSensitive: false,
);

final RegExp _submissionCandidatePattern = RegExp(
  r'''(?:https?:)?//(?:www\.)?furaffinity\.net/view/\d+/?|["']/view/\d+/?''',
  caseSensitive: false,
);

_PreparedNoteMarkup _prepareNoteMarkup(
  String content, {
  required bool isHtml,
}) {
  final source = isHtml
      ? content
      : const HtmlEscape(HtmlEscapeMode.element)
          .convert(content)
          .replaceAll('\r\n', '\n')
          .replaceAll('\n', '<br>');
  final document = html_parser.parse('<div id="note-preview-root">$source</div>');
  final root = document.querySelector('#note-preview-root')!;
  final urls = <String, String>{};
  var nextId = 0;

  String addOccurrence(String submissionUrl) {
    final id = 'note-preview-${nextId++}';
    urls[id] = submissionUrl;
    return id;
  }

  final originalTextNodes = <dom.Text>[];
  void collectTextNodes(dom.Node node, bool insideLink) {
    final isLink = node is dom.Element && node.localName == 'a';
    if (node is dom.Text && !insideLink) originalTextNodes.add(node);
    for (final child in node.nodes) {
      collectTextNodes(child, insideLink || isLink);
    }
  }

  collectTextNodes(root, false);

  for (final anchor in root.querySelectorAll('a[href]').toList()) {
    final href = anchor.attributes['href'];
    final submissionUrl = href == null ? null : _submissionUrlFrom(href);
    if (submissionUrl == null) continue;
    final id = addOccurrence(submissionUrl);
    final parent = anchor.parentNode;
    if (parent == null) continue;
    parent.insertBefore(_previewElement('note-preview-control', id), anchor);
    parent.nodes.insert(
      parent.nodes.indexOf(anchor) + 1,
      _previewElement('note-preview-expanded', id),
    );
  }

  for (final textNode in originalTextNodes) {
    final text = textNode.data;
    final matches = _submissionTextPattern.allMatches(text).toList();
    if (matches.isEmpty) continue;
    final parent = textNode.parentNode;
    if (parent == null) continue;
    var offset = 0;
    for (final match in matches) {
      if (match.start > offset) {
        parent.insertBefore(dom.Text(text.substring(offset, match.start)), textNode);
      }
      final label = match.group(0)!;
      final submissionUrl = _submissionUrlFrom(label);
      if (submissionUrl == null) continue;
      final id = addOccurrence(submissionUrl);
      parent.insertBefore(_previewElement('note-preview-control', id), textNode);
      final anchor = dom.Element.tag('a')
        ..attributes['href'] = submissionUrl
        ..text = label;
      parent.insertBefore(anchor, textNode);
      parent.insertBefore(_previewElement('note-preview-expanded', id), textNode);
      offset = match.end;
    }
    if (offset < text.length) {
      parent.insertBefore(dom.Text(text.substring(offset)), textNode);
    }
    textNode.remove();
  }

  return _PreparedNoteMarkup(root.innerHtml, urls);
}

dom.Element _previewElement(String tag, String id) {
  return dom.Element.tag(tag)..attributes['data-id'] = id;
}

String? _submissionUrlFrom(String value) {
  final trimmed = value.trim();
  final normalized = trimmed.startsWith('//')
      ? 'https:$trimmed'
      : trimmed.startsWith('/')
          ? 'https://www.furaffinity.net$trimmed'
          : trimmed;
  final uri = Uri.tryParse(normalized);
  if (uri == null) return null;
  final host = uri.host.toLowerCase();
  if (host != 'furaffinity.net' && !host.endsWith('.furaffinity.net')) {
    return null;
  }
  final segments = uri.pathSegments.where((part) => part.isNotEmpty).toList();
  if (segments.length < 2 ||
      segments.first.toLowerCase() != 'view' ||
      int.tryParse(segments[1]) == null) {
    return null;
  }
  return 'https://www.furaffinity.net/view/${segments[1]}/';
}
