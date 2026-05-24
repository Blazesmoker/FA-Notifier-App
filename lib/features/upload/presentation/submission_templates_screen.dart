// lib/screens/submission_templates_screen.dart

import 'dart:ui';

import 'package:flutter/material.dart';

import 'package:FANotifier/features/upload/data/submission_template_store.dart';
import 'package:FANotifier/features/upload/domain/submission_template.dart';

class SubmissionTemplatesScreen extends StatefulWidget {
  final SubmissionTemplateStore store;

  const SubmissionTemplatesScreen({Key? key, required this.store}) : super(key: key);

  @override
  State<SubmissionTemplatesScreen> createState() => _SubmissionTemplatesScreenState();
}

class _SubmissionTemplatesScreenState extends State<SubmissionTemplatesScreen> with TickerProviderStateMixin {
  static const Color _accent = Color(0xFFE09321);

  final Set<String> _expanded = <String>{};
  bool _loading = true;
  List<SubmissionTemplate> _templates = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await widget.store.loadTemplates();
    if (!mounted) return;
    setState(() {
      _templates = list;
      _loading = false;
    });
  }

  Future<void> _showRenameDialog(SubmissionTemplate template) async {
    final controller = TextEditingController(text: template.name);

    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.black,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: _accent, width: 0.5),
          borderRadius: BorderRadius.circular(22),
        ),
        title: const Text('Rename Template', style: TextStyle(color: _accent)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Template name',
            hintStyle: const TextStyle(color: Colors.white38),
            enabledBorder: OutlineInputBorder(
              borderSide: const BorderSide(color: _accent, width: 0.8),
              borderRadius: BorderRadius.circular(14),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: const BorderSide(color: _accent, width: 1.2),
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
        actionsAlignment: MainAxisAlignment.spaceBetween,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Save', style: TextStyle(color: _accent)),
          ),
        ],
      ),
    );

    final trimmed = (newName ?? '').trim();
    if (trimmed.isEmpty) return;

    await widget.store.renameTemplate(template.id, trimmed);
    await _load();
  }

  Future<void> _showDeleteDialog(SubmissionTemplate template) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.black,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: _accent, width: 0.5),
          borderRadius: BorderRadius.circular(22),
        ),
        title: Text('Delete template "${template.name}"?', style: const TextStyle(color: _accent)),
        content: const Text('This cannot be undone.', style: TextStyle(color: Colors.white70)),
        actionsAlignment: MainAxisAlignment.spaceBetween,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );

    if (ok != true) return;

    await widget.store.deleteTemplate(template.id);
    await _load();
  }

  Future<void> _showLongPressMenu(SubmissionTemplate template) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.black,
      useSafeArea: true,
      isScrollControlled: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        side: BorderSide(color: _accent, width: 0.5),
      ),
      builder: (context) {
        final bottomPad = MediaQuery.of(context).padding.bottom;
        return Padding(
          padding: EdgeInsets.only(bottom: bottomPad),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: const Text('Rename', style: TextStyle(color: Colors.white)),
                leading: const Icon(Icons.drive_file_rename_outline, color: _accent),
                onTap: () => Navigator.of(context).pop('rename'),
              ),
              ListTile(
                title: const Text('Delete', style: TextStyle(color: Colors.white)),
                leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
                onTap: () => Navigator.of(context).pop('delete'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );

    if (action == 'rename') {
      await _showRenameDialog(template);
    } else if (action == 'delete') {
      await _showDeleteDialog(template);
    }
  }

  Future<void> _confirmApply(SubmissionTemplate template) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.black,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: _accent, width: 0.5),
          borderRadius: BorderRadius.circular(22),
        ),
        title: Text('Apply template "${template.name}"?', style: const TextStyle(color: _accent)),
        actionsAlignment: MainAxisAlignment.spaceBetween,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Apply', style: TextStyle(color: _accent)),
          ),
        ],
      ),
    );

    if (ok == true && mounted) {
      Navigator.of(context).pop(template);
    }
  }

  Widget _fieldRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(color: Colors.white, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  String _selectToText(TemplateSelectValue? v) {
    if (v == null) return 'Not set';
    final label = v.label.trim();
    if (label.isNotEmpty) return label;
    return v.value.trim().isNotEmpty ? v.value : 'Not set';
  }

  String _textOrNotSet(String? v) {
    if (v == null) return 'Not set';
    return v.trim().isEmpty ? 'Not set' : v;
  }

  String _foldersText(SubmissionTemplateFields f) {
    final newFolder = (f.folderName ?? '').trim();
    if (newFolder.isNotEmpty) return newFolder;

    final folders = f.folders ?? const <TemplateSelectValue>[];
    if (folders.isEmpty) return 'Not set';

    final labels = folders
        .map((e) => e.label.trim().isNotEmpty ? e.label.trim() : e.value.trim())
        .where((x) => x.isNotEmpty)
        .toList();

    if (labels.isEmpty) return 'Not set';
    return labels.join(', ');
  }

  void _toggleExpanded(String id) {
    setState(() {
      if (_expanded.contains(id)) {
        _expanded.remove(id);
      } else {
        _expanded.add(id);
      }
    });
  }

  Future<void> _onReorderItem(int oldIndex, int newIndex) async {
    setState(() {
      final item = _templates.removeAt(oldIndex);
      _templates.insert(newIndex, item);
    });
    await widget.store.saveOrder(_templates.map((e) => e.id).toList());
  }

  Widget _templateItem(SubmissionTemplate template, int index) {
    final expanded = _expanded.contains(template.id);

    return Padding(
      key: ValueKey(template.id),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Material(
        color: Colors.black,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => _confirmApply(template),
          onLongPress: () => _showLongPressMenu(template),
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: _accent, width: 0.6),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(
                    children: [
                      ReorderableDelayedDragStartListener(
                        index: index,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                          child: Icon(Icons.unfold_more, color: _accent.withValues(alpha: 0.9)),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          template.name,
                          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        icon: AnimatedRotation(
                          turns: expanded ? 0.5 : 0.0,
                          duration: const Duration(milliseconds: 200),
                          child: Icon(Icons.expand_more, color: _accent),
                        ),
                        onPressed: () => _toggleExpanded(template.id),
                      ),
                    ],
                  ),
                ),
                ClipRect(
                  child: AnimatedSize(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeInOut,
                    child: ConstrainedBox(
                      constraints: expanded ? const BoxConstraints() : const BoxConstraints(maxHeight: 0),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                        child: Column(
                          children: [
                            _fieldRow('Category', _selectToText(template.fields.category)),
                            _fieldRow('Theme', _selectToText(template.fields.theme)),
                            _fieldRow('Species', _selectToText(template.fields.species)),
                            _fieldRow('Rating', _selectToText(template.fields.rating)),
                            _fieldRow('Title', _textOrNotSet(template.fields.title)),
                            _fieldRow('Description', _textOrNotSet(template.fields.description)),
                            _fieldRow('Keywords', _textOrNotSet(template.fields.keywords)),
                            _fieldRow('Folder Name', _foldersText(template.fields)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _proxyDecorator(Widget child, int index, Animation<double> animation) {
    final t = Curves.easeInOut.transform(animation.value);
    final elev = lerpDouble(0, 8, t) ?? 0;
    return Material(
      elevation: elev,
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('Templates'),
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (_templates.isEmpty
          ? const Center(
        child: Text('No templates yet.', style: TextStyle(color: Colors.white70)),
      )
          : ReorderableListView.builder(
        padding: const EdgeInsets.only(top: 6, bottom: 18),
        itemCount: _templates.length,
        onReorderItem: _onReorderItem,
        proxyDecorator: _proxyDecorator,
        itemBuilder: (context, index) => _templateItem(_templates[index], index),
      )),
    );
  }
}
