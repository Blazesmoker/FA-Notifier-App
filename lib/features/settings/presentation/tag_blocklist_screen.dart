import 'package:FANotifier/features/settings/data/tag_blocklist_service.dart';
import 'package:FANotifier/core/preferences/sfw_mode_preference.dart';
import 'package:flutter/material.dart';

import 'package:FANotifier/shared/widgets/PulsatingLoadingIndicator.dart';

class TagBlocklistScreen extends StatefulWidget {
  const TagBlocklistScreen({super.key});

  @override
  State<TagBlocklistScreen> createState() => _TagBlocklistScreenState();
}

class _TagBlocklistScreenState extends State<TagBlocklistScreen> {
  final TextEditingController _addController = TextEditingController();
  final SfwModePreference _sfwModePreference = SfwModePreference();
  final Set<String> _tagToggleInFlight = <String>{};

  bool _sfwEnabled = true;
  bool _loading = true;
  bool _adding = false;

  String? _nonce;
  int? _total;
  List<String> _blockedTags = const [];

  @override
  void initState() {
    super.initState();
    Future.wait([
      _loadSfwEnabled(),
      _fetchBlocklist(),
    ]);
  }

  @override
  void dispose() {
    _addController.dispose();
    super.dispose();
  }

  Future<void> _loadSfwEnabled() async {
    final sfwEnabled = await _sfwModePreference.loadSfwEnabled();
    if (!mounted) return;
    setState(() {
      _sfwEnabled = sfwEnabled;
    });
  }

  Future<void> _fetchBlocklist() async {
    setState(() => _loading = true);
    try {
      final parsed = await fetchTagBlocklist(
        sfwEnabled: _sfwEnabled,
      );

      if (!mounted) return;
      setState(() {
        _nonce = parsed.nonce;
        _total = parsed.total;
        _blockedTags = parsed.blockedTags;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _blockedTags = const [];
        _total = null;
        _nonce = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load tag blocklist: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _sendTagBlocklistRequest(String tagName, {required bool shouldBlock}) async {
    if (_nonce == null || _nonce!.isEmpty) {
      throw Exception('Missing tag blocklist nonce.');
    }

    await sendTagBlocklistRequest(
      sfwEnabled: _sfwEnabled,
      nonce: _nonce!,
      tagName: tagName,
      shouldBlock: shouldBlock,
    );
  }

  Future<void> _removeTag(String tagName) async {
    if (_tagToggleInFlight.contains(tagName)) return;
    if (_nonce == null || _nonce!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tag blocking is unavailable right now (missing nonce).'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _tagToggleInFlight.add(tagName));
    final prev = List<String>.from(_blockedTags);
    setState(() {
      _blockedTags = _blockedTags.where((t) => t != tagName).toList(growable: false);
      _total = _blockedTags.length;
    });

    try {
      await _sendTagBlocklistRequest(tagName, shouldBlock: false);
      await _fetchBlocklist();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Tag unblocked: $tagName'), backgroundColor: Colors.green),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _blockedTags = prev;
        _total = prev.length;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to unblock tag: $tagName'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _tagToggleInFlight.remove(tagName));
    }
  }

  Future<void> _addTag() async {
    final raw = _addController.text.trim();
    if (raw.isEmpty) return;
    final tagName = raw.toLowerCase();

    if (_adding) return;
    if (_nonce == null || _nonce!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tag blocking is unavailable right now (missing nonce).'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _adding = true);
    try {
      await _sendTagBlocklistRequest(tagName, shouldBlock: true);
      _addController.clear();
      await _fetchBlocklist();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Tag blocked: $tagName'), backgroundColor: Colors.green),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to block tag: $tagName'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          title,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
        ),
      ),
    );
  }

  Widget _buildTagPill(String tagName) {
    final bool inFlight = _tagToggleInFlight.contains(tagName);
    const Color accent = Colors.redAccent;
    final Color border = accent.withValues(alpha: 0.55);

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF151515),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: border, width: 1),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Tooltip(
            message: 'Click to remove this tag from the blocklist!',
            child: InkWell(
              onTap: inFlight ? null : () => _removeTag(tagName),
              borderRadius: BorderRadius.circular(999),
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
                child: Center(
                  child: inFlight
                      ? const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.black),
                          ),
                        )
                      : const Icon(Icons.remove, size: 16, color: Colors.black),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            tagName,
            style: const TextStyle(fontSize: 13, color: Colors.white, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _buildManageSection() {
    final countText = (_total != null && _total! > 0) ? ' (${_total!})' : '';
    final title = 'Manage Tag Blocklist$countText';

    if (_blockedTags.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(title),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 6),
            child: Text(
              'No blocked tags.',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(title),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4),
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: _blockedTags.map(_buildTagPill).toList(growable: false),
          ),
        ),
      ],
    );
  }

  Widget _buildAddSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Add Tag to Blocklist'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 10),
              TextField(
                controller: _addController,
                enabled: !_adding,
                cursorColor: Colors.white,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'tag name',
                  hintStyle: const TextStyle(color: Colors.white54),
                  filled: true,
                  fillColor: const Color(0xFF151515),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Colors.black, width: 1),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Colors.black, width: 1.5),
                  ),
                ),
                onSubmitted: (_) => _addTag(),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                height: 42,
                child: ElevatedButton(
                  onPressed: _adding ? null : _addTag,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE09321),
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: _adding
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                        )
                      : const Text('Add Tag', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('Tag Blocklist'),
      ),
      body: Stack(
        children: [
          RefreshIndicator(
            color: const Color(0xFFE09321),
            backgroundColor: Colors.black,
            onRefresh: _fetchBlocklist,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                if (_nonce == null || _nonce!.isEmpty)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Text(
                      'Warning: Tag blocking nonce not found. Add/remove may not work until FA changes markup.',
                      style: TextStyle(color: Colors.redAccent, fontSize: 13),
                    ),
                  ),
                _buildManageSection(),
                const Divider(height: 18, color: Color(0xFF111111), thickness: 4),
                _buildAddSection(),
              ],
            ),
          ),
          if (_loading)
            AbsorbPointer(
              child: Container(
                color: Colors.black,
                child: const Center(
                  child: PulsatingLoadingIndicator(
                    size: 78.0, // medium
                    assetPath: 'assets/icons/fathemed.png',
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

