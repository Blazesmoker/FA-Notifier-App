import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:html/dom.dart' as dom;
import 'package:http/http.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../network.dart';
import '../parsing_utils.dart';
import '../widgets/PulsatingLoadingIndicator.dart';

class TagBlocklistParseResult {
  const TagBlocklistParseResult({
    required this.blockedTags,
    required this.total,
    required this.nonce,
  });

  final List<String> blockedTags;
  final int? total;
  final String? nonce;
}

class TagBlocklistApiService {
  static TagBlocklistParseResult parse(dom.Document document, String rawHtml) {
    dom.Element? tagSection;
    for (final section in document.querySelectorAll('section')) {
      final h2 = section.querySelector('.section-header h2') ?? section.querySelector('h2');
      if (h2 == null) continue;
      if (h2.text.trim().toLowerCase() == 'tag block list') {
        tagSection = section;
        break;
      }
    }
    tagSection ??= document.querySelector('section');

    // Nonce (required for add/remove).
    String? nonce = document.querySelector('body')?.attributes['data-tag-blocklist-nonce']?.trim();
    if (nonce == null || nonce.isEmpty) {
      nonce = RegExp(r'data-tag-blocklist-nonce\s*=\s*"([^"]+)"', caseSensitive: false)
          .firstMatch(rawHtml)
          ?.group(1)
          ?.trim();
    }

    // Blocked tags can be provided both in the control markup (data-tag-name) and on <body>.
    final blocked = <String>{};

    final bodyRaw = document.querySelector('body')?.attributes['data-tag-blocklist'] ?? '';
    if (bodyRaw.trim().isNotEmpty) {
      blocked.addAll(
        bodyRaw
            .trim()
            .split(RegExp(r'\s+'))
            .where((t) => t.trim().isNotEmpty)
            .map((t) => t.trim().toLowerCase()),
      );
    }

    final scope = tagSection ?? document;
    for (final el in scope.querySelectorAll('a.tag-block.remove-tag[data-tag-name]')) {
      final name = el.attributes['data-tag-name']?.trim().toLowerCase();
      if (name != null && name.isNotEmpty) blocked.add(name);
    }

    int? total;
    final totalText = scope.querySelector('#tag-blocklist-total')?.text.trim();
    if (totalText != null && totalText.isNotEmpty) {
      total = int.tryParse(totalText);
    }

    final blockedTags = blocked.toList()..sort();

    return TagBlocklistParseResult(
      blockedTags: blockedTags,
      total: total,
      nonce: (nonce != null && nonce.isNotEmpty) ? nonce : null,
    );
  }
}

class TagBlocklistScreen extends StatefulWidget {
  const TagBlocklistScreen({super.key});

  @override
  State<TagBlocklistScreen> createState() => _TagBlocklistScreenState();
}

class _TagBlocklistScreenState extends State<TagBlocklistScreen> {
  static const _profileUrl = 'https://www.furaffinity.net/controls/profile/';
  static const _routeUrl = 'https://www.furaffinity.net/route/tag_blocking';

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    iOptions: IOSOptions(
      accountName: 'flutter_secure_storage_service',
      accessibility: KeychainAccessibility.first_unlock,
    ),
  );

  final TextEditingController _addController = TextEditingController();
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
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _sfwEnabled = prefs.getBool('sfwEnabled') ?? true;
    });
  }

  String _decodeBody(Response response) {
    try {
      return utf8.decode(response.bodyBytes, allowMalformed: true);
    } catch (_) {
      return latin1.decode(response.bodyBytes, allowInvalid: true);
    }
  }

  Future<Response> _getWithCookie(String url) async {
    final cookieA = await _secureStorage.read(key: 'fa_cookie_a');
    final cookieB = await _secureStorage.read(key: 'fa_cookie_b');
    if (cookieA == null || cookieB == null) {
      throw Exception('Not logged in.');
    }

    final sfwValue = _sfwEnabled ? '1' : '0';
    return httpClient.get(
      Uri.parse(url),
      headers: <String, String>{
        'Cookie': 'a=$cookieA; b=$cookieB; sfw=$sfwValue',
        'User-Agent': 'Mozilla/5.0 (compatible; YourApp/1.0)',
      },
    );
  }

  Future<void> _fetchBlocklist() async {
    setState(() => _loading = true);
    try {
      final resp = await _getWithCookie(_profileUrl);
      if (resp.statusCode != 200) {
        throw Exception('Failed to load profile controls: ${resp.statusCode}');
      }
      final decoded = _decodeBody(resp);
      final doc = await parseHtml(decoded);
      final parsed = TagBlocklistApiService.parse(doc, decoded);

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
    final cookieA = await _secureStorage.read(key: 'fa_cookie_a');
    final cookieB = await _secureStorage.read(key: 'fa_cookie_b');
    final sfwValue = _sfwEnabled ? '1' : '0';

    if (cookieA == null || cookieB == null) {
      throw Exception('Not logged in.');
    }
    if (_nonce == null || _nonce!.isEmpty) {
      throw Exception('Missing tag blocklist nonce.');
    }

    final response = await httpClient.post(
      Uri.parse(_routeUrl),
      headers: <String, String>{
        'Cookie': 'a=$cookieA; b=$cookieB; sfw=$sfwValue',
        'User-Agent': 'Mozilla/5.0 (compatible; YourApp/1.0)',
        'Referer': _profileUrl,
        'Origin': 'https://www.furaffinity.net',
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: <String, String>{
        'action': shouldBlock ? 'add-tag' : 'remove-tag',
        'key': _nonce!,
        'tag_name': tagName,
      },
    );

    if (response.statusCode != 200) {
      throw Exception('Tag blocklist request failed: ${response.statusCode}');
    }
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
    const bool isBlocked = true;

    final Color accent = isBlocked ? Colors.redAccent : const Color(0xFFE09321);
    final Color border = isBlocked ? accent.withOpacity(0.55) : const Color(0xFF2A2A2A);

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
      backgroundColor: const Color(0xFF111111),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111111),
        title: const Text('Tag Blocklist'),
      ),
      body: Stack(
        children: [
          RefreshIndicator(
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
                const Divider(height: 18, color: Colors.black, thickness: 4),
                _buildAddSection(),
              ],
            ),
          ),
          if (_loading)
            AbsorbPointer(
              child: Container(
                color: const Color(0xFF111111),
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


