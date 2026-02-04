import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import '../services/fa_http.dart';
import '../utils/fa_link_handler.dart';

class FindSourceScreen extends StatefulWidget {
  const FindSourceScreen({Key? key}) : super(key: key);

  @override
  State<FindSourceScreen> createState() => _FindSourceScreenState();
}

class _FindSourceScreenState extends State<FindSourceScreen>
    with SingleTickerProviderStateMixin {
  final ImagePicker _picker = ImagePicker();

  XFile? _image;
  bool _loading = false;
  String? _error;
  List<String> _results = [];
  double? _accuracy;


  bool _selectionMode = false;
  final Set<String> _selectedLinks = {};

  DateTime? _lastRequestTime;
  String? _lastImageHash;
  static const Duration _cooldown = Duration(seconds: 10);

  static const String _iqdbEndpoint = 'https://e621.net/iqdb_queries.json';

  static const Color _orange = Color(0xFFE09321);

  static final Color _selectedBg = _orange.withValues(alpha: 0.15);


  List<String> _faAuthorLinks = [];
  List<String> _faPostLinks = [];
  List<String> _e621PostLinks = [];

  // Whitelist
  static const Set<String> _allowedDomains = {
    'furaffinity.net',
    'www.furaffinity.net',
    'e621.net',
    'www.e621.net',
  };

  String _e621UserAgent() {
    return '${FAHttp.appName}/${FAHttp.appVersion} (by Blazesmoker on e621)';
  }

  bool _isAllowed(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    return _allowedDomains.contains(uri.host.toLowerCase());
  }

  void _clearState() {
    setState(() {
      _image = null;
      _loading = false;
      _error = null;
      _results.clear();
      _accuracy = null;
      _lastRequestTime = null;
      _lastImageHash = null;
      _selectionMode = false;
      _selectedLinks.clear();
      _faAuthorLinks.clear();
      _faPostLinks.clear();
      _e621PostLinks.clear();
    });
  }

  Future<void> _pickImage() async {
    final img = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 2000,
      maxHeight: 2000,
      imageQuality: 100,
    );

    if (img == null) return;

    setState(() {
      _image = img;
      _results.clear();
      _accuracy = null;
      _error = null;
      _selectionMode = false;
      _selectedLinks.clear();
      _faAuthorLinks.clear();
      _faPostLinks.clear();
      _e621PostLinks.clear();
    });
  }

  Future<String> _hashImage(File file) async {
    final bytes = await file.readAsBytes();
    return sha256.convert(bytes).toString();
  }

  bool _canSendRequest() {
    if (_lastRequestTime == null) return true;
    return DateTime.now().difference(_lastRequestTime!) > _cooldown;
  }

  Future<void> _search() async {
    if (_image == null) {
      setState(() => _error = 'Pick an image first');
      return;
    }

    if (!_canSendRequest()) {
      setState(() => _error = 'Please wait a few seconds before searching again');
      return;
    }

    final file = File(_image!.path);
    final hash = await _hashImage(file);

    if (hash == _lastImageHash) {
      setState(() => _error = 'This image was already searched');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _results.clear();
      _accuracy = null;
      _selectionMode = false;
      _selectedLinks.clear();
      _faAuthorLinks.clear();
      _faPostLinks.clear();
      _e621PostLinks.clear();
    });

    try {
      final request = http.MultipartRequest('POST', Uri.parse(_iqdbEndpoint));
      request.headers['User-Agent'] = _e621UserAgent();
      request.headers['Accept'] = 'application/json';
      request.files.add(
        await http.MultipartFile.fromPath('file', file.path),
      );

      final response =
      await request.send().timeout(const Duration(seconds: 30));
      final body = await response.stream.bytesToString();

      debugPrint('e621 IQDB response (${response.statusCode}):');
      debugPrint(body);

      if (response.statusCode != 200) {
        throw _FriendlyError('IQDB failed (${response.statusCode})');
      }

      final decoded = json.decode(body);

      final rawSources = <String>{};
      final postIds = <int>{};
      double? bestScore;

      void collect(dynamic v) {
        if (v is Map) {
          if (v['score'] != null && bestScore == null) {
            bestScore = double.tryParse(v['score'].toString());
          }

          final source = v['source'] ?? v['post']?['posts']?['source'];
          if (source is String) {
            for (final line in source.split('\n')) {
              final link = line.trim();
              if (link.isNotEmpty) rawSources.add(link);
            }
          }

          final postId = v['post']?['posts']?['id'];
          if (postId != null) {
            try {
              postIds.add(int.parse(postId.toString()));
            } catch (_) {}
          }

          v.values.forEach(collect);
        } else if (v is List) {
          for (final e in v) {
            collect(e);
          }
        }
      }

      collect(decoded);

      final hasDisallowedSource = rawSources.any((s) {
        final uri = Uri.tryParse(s);
        if (uri == null) return true;
        final host = uri.host.toLowerCase();
        if (host.contains('e621.net')) return false;
        return !_allowedDomains.contains(host);
      });


      final faAuthor = <String>{};
      final faPosts = <String>{};

      final e621Posts = <String>{};


      for (final s in rawSources) {
        if (!_isAllowed(s)) continue;
        if (s.contains('furaffinity.net')) {
          if (s.contains('/user/') || s.contains('/profile/')) {
            faAuthor.add(s);
          } else {
            faPosts.add(s);
          }
        }
      }

      // add e621 posts only if there's no disallowed source (user requested)
      if (!hasDisallowedSource) {
        for (final id in postIds) {
          e621Posts.add('https://e621.net/posts/$id');
        }
      } else {
        // If disallowed sources exist, we intentionally omit e621 links per request
        debugPrint('Disallowed source detected — suppressing e621 post links.');
      }

      // If nothing whitelist-matching found, show specific message
      if (faAuthor.isEmpty && faPosts.isEmpty && e621Posts.isEmpty) {
        setState(() => _error = 'Couldn’t find source from FurAffinity.net');
        return;
      }

      // Maintain original _results list for copy-all / legacy code compatibility
      final combined = <String>[];
      // single FA header logic: authors first then posts
      combined.addAll(faAuthor);
      combined.addAll(faPosts);
      combined.addAll(e621Posts);

      setState(() {
        _faAuthorLinks = faAuthor.toList()..sort();
        _faPostLinks = faPosts.toList()..sort();
        _e621PostLinks = e621Posts.toList()..sort();
        _results = combined;
        _accuracy = bestScore;
        _lastRequestTime = DateTime.now();
        _lastImageHash = hash;
      });
    } on TimeoutException {
      setState(() => _error = 'Request timed out');
    } on SocketException {
      setState(() => _error = 'No internet connection');
    } on _FriendlyError catch (e) {
      setState(() => _error = e.message);
    } catch (e, st) {
      debugPrint('Unexpected error: $e\n$st');
      setState(() => _error = 'Unexpected error');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _copyLink(String link) {
    Clipboard.setData(ClipboardData(text: link));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Link copied')),
    );
  }

  void _copyAllLinks() {
    final text = _results.join('\n');
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('All links copied')),
    );
  }

  void _copySelectedLinks() {
    if (_selectedLinks.isEmpty) return;
    final text = _selectedLinks.join('\n');
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Copied ${_selectedLinks.length} link(s)')),
    );
    setState(() {
      _selectionMode = false;
      _selectedLinks.clear();
    });
  }

  void _toggleSelection(String link) {
    setState(() {
      if (_selectedLinks.contains(link)) {
        _selectedLinks.remove(link);
      } else {
        _selectedLinks.add(link);
      }
    });
  }

  void _enterSelectionMode(String initial) {
    setState(() {
      _selectionMode = true;
      _selectedLinks.clear();
      _selectedLinks.add(initial);
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _selectionMode = false;
      _selectedLinks.clear();
    });
  }

  PreferredSizeWidget _buildAppBar() {
    if (_selectionMode) {
      return AppBar(
        title: Text('Selected: ${_selectedLinks.length}'),
        backgroundColor: const Color(0xFF111111),
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Copy selected',
            icon: const Icon(Icons.copy),
            onPressed: _selectedLinks.isEmpty ? null : _copySelectedLinks,
            color: _orange,
          ),
          IconButton(
            tooltip: 'Cancel',
            icon: const Icon(Icons.close),
            onPressed: _exitSelectionMode,
            color: Colors.white,
          ),
        ],
      );
    } else {
      return AppBar(
        title: const Text('Find Source'),
        backgroundColor: const Color(0xFF111111),
        elevation: 0,
        actions: [
          // NEW: info button left of the clear icon
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: _showInfoDialog,
            color: Colors.white,
          ),
          IconButton(
            icon: const Icon(Icons.cleaning_services),
            onPressed: _loading ? null : _clearState,
            color: Colors.white,
          ),
        ],
      );
    }
  }

  void _showInfoDialog() {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),

          title: const Center(
            child: Text(
              'Important info',
              style: TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),

          content: RichText(
            text: TextSpan(
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
              ),
              children: [
                const TextSpan(text: 'This screen searches '),
                TextSpan(
                  text: 'e621.net',
                  style: TextStyle(color: _orange),
                  recognizer: TapGestureRecognizer()
                    ..onTap = () {
                      Navigator.of(ctx).pop();
                      handleFALink(context, 'https://e621.net');
                    },
                ),
                const TextSpan(
                  text: ' for FurAffinity–related image sources.\n\n',
                ),
                const TextSpan(
                  text: 'Tip: Long-press a link to select and copy multiple links.',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),

          actionsAlignment: MainAxisAlignment.end,
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text(
                'Close',
                style: TextStyle(color: Colors.redAccent),
              ),
            ),
          ],
        );
      },
    );
  }



  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _buildLinkTile(String link) {
    final selected = _selectedLinks.contains(link);
    Icon leadingIcon = const Icon(Icons.link, size: 18);

    if (link.contains('furaffinity.net')) {
      if (link.contains('/user/') || link.contains('/profile/')) {
        leadingIcon = const Icon(Icons.person, size: 18);
      } else {
        leadingIcon = const Icon(Icons.photo_library, size: 18);
      }
    } else if (link.contains('e621.net')) {
      leadingIcon = const Icon(Icons.link, size: 18);
    }

    return Material(
      color: Colors.transparent,
      child: ListTile(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
        ),
        dense: true,
        selected: selected,
        selectedTileColor: _selectedBg,
        contentPadding: const EdgeInsets.symmetric(horizontal: 6),
        leading: selected
            ? Icon(Icons.check_circle, color: _orange, size: 18)
            : IconTheme(
          data: const IconThemeData(color: Colors.white70, size: 18),
          child: leadingIcon,
        ),
        title: Transform.translate(
          offset: const Offset(-8, 0),
          child: Text(
            link,
            style: TextStyle(
              color: _orange,
              fontSize: 13,
            ),
          ),
        ),
        onTap: () {
          if (_selectionMode) {
            _toggleSelection(link);
          } else {
            debugPrint('TAPPED LINK >>> $link');
            handleFALink(context, link);
          }
        },
        onLongPress: () {
          if (!_selectionMode) {
            _enterSelectionMode(link);
          } else {
            _toggleSelection(link);
          }
        },
        trailing: _selectionMode
            ? IconButton(
          icon: Icon(
            selected ? Icons.check : Icons.circle_outlined,
            color: selected ? _orange : Colors.white24,
            size: 18,
          ),
          onPressed: () => _toggleSelection(link),
        )
            : IconButton(
          icon: const Icon(Icons.copy),
          color: Colors.white,
          onPressed: () => _copyLink(link),
        ),
      ),
    );

  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
        value: const SystemUiOverlayStyle(
          systemNavigationBarColor: Color(0xFF111111),
          systemNavigationBarIconBrightness: Brightness.light,
          statusBarColor: Color(0xFF111111),
          statusBarIconBrightness: Brightness.light,
        ),
        child: WillPopScope(
      onWillPop: () async {
        if (_selectionMode) {
          _exitSelectionMode();
          return false;
        }
        return true;
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF111111),
        appBar: _buildAppBar(),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            child: Column(
              children: [
                GestureDetector(
                  onTap: _pickImage,
                  child: Container(
                    height: 250,
                    decoration: BoxDecoration(
                      color: const Color(0xFF2A2A2A),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: const Color(0xFF1A1A1A),
                        width: 3,
                      ),
                    ),
                    child: _image == null
                        ? Center(
                      child: Text(
                        'Tap here to load image',
                        style: TextStyle(color: _orange),
                      ),
                    )
                        : ClipRRect(
                      borderRadius: BorderRadius.circular(11),
                      child: Image.file(
                        File(_image!.path),
                        fit: BoxFit.contain,
                        width: double.infinity,
                        height: double.infinity,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 10),

                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: _accuracy == null
                      ? SizedBox(
                    width: double.infinity,
                    key: const ValueKey('search'),
                    child: ElevatedButton(
                      onPressed: _loading ? null : _search,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _orange,
                        padding:
                        const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: _loading
                          ? const SizedBox(
                        height: 18,
                        width: 18,
                        child:
                        CircularProgressIndicator(strokeWidth: 2),
                      )
                          : const Text('Search'),
                    ),
                  )
                      : Row(
                    key: const ValueKey('accuracy'),
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Text(
                          'Accuracy: ${_accuracy!.toStringAsFixed(2)}%',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _results.isEmpty ? null : _copyAllLinks,
                        icon: Icon(Icons.copy, size: 16, color: _orange),
                        label: Text(
                          'Copy all',
                          style: TextStyle(color: _orange),
                        ),
                      ),
                    ],
                  ),
                ),

                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Colors.redAccent),
                    ),
                  ),

                const SizedBox(height: 6),

                Expanded(
                  child: ListView.separated(
                    itemCount: _computeListItemCount(),
                    separatorBuilder: (_, __) => const Divider(color: Colors.white12),
                    itemBuilder: (context, index) {
                      final mapping = _mapIndexToLink(index);
                      final link = mapping?.link;
                      final isHeader = mapping?.isHeader ?? false;

                      if (mapping == null) return const SizedBox();

                      if (isHeader) {
                        return _buildSectionHeader(mapping.link ?? '');
                      } else {
                        return _buildLinkTile(link!);
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
    );

  }


  int _computeListItemCount() {
    var count = 0;
    final hasFa = _faAuthorLinks.isNotEmpty || _faPostLinks.isNotEmpty;
    if (hasFa) {
      count += 1;
      count += _faAuthorLinks.length;
      count += _faPostLinks.length;
    }
    if (_e621PostLinks.isNotEmpty) {
      count += 1 + _e621PostLinks.length;
    }
    return count;
  }

  _IndexMapping? _mapIndexToLink(int index) {
    var i = index;

    final hasFa = _faAuthorLinks.isNotEmpty || _faPostLinks.isNotEmpty;
    if (hasFa) {
      if (i == 0) return _IndexMapping(link: 'Fur Affinity.net', isHeader: true);
      i -= 1;
      if (i < _faAuthorLinks.length) return _IndexMapping(link: _faAuthorLinks[i]);
      i -= _faAuthorLinks.length;
      if (i < _faPostLinks.length) return _IndexMapping(link: _faPostLinks[i]);
      i -= _faPostLinks.length;
    }

    if (_e621PostLinks.isNotEmpty) {
      if (i == 0) return _IndexMapping(link: 'e621.net', isHeader: true);
      i -= 1;
      if (i < _e621PostLinks.length) return _IndexMapping(link: _e621PostLinks[i]);
      i -= _e621PostLinks.length;
    }

    return null;
  }
}

class _IndexMapping {
  final String? link;
  final bool isHeader;
  _IndexMapping({this.link, this.isHeader = false});
}

class _FriendlyError implements Exception {
  final String message;
  const _FriendlyError(this.message);
}
