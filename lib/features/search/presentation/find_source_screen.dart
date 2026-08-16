import 'dart:async';
import 'dart:io';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:fanotifier/features/search/domain/find_source_models.dart';
import 'package:fanotifier/features/search/domain/find_source_repository.dart';
import 'package:fanotifier/shared/navigation/fa_link_handler.dart';

class FindSourceScreen extends StatefulWidget {
  const FindSourceScreen({super.key});

  @override
  State<FindSourceScreen> createState() => _FindSourceScreenState();
}

class _FindSourceScreenState extends State<FindSourceScreen>
    with SingleTickerProviderStateMixin {
  String? _imagePath;
  bool _loading = false;
  String? _error;
  List<String> _results = [];
  double? _accuracy;

  bool _selectionMode = false;
  final Set<String> _selectedLinks = {};

  DateTime? _lastRequestTime;
  String? _lastImageHash;
  static const Duration _cooldown = Duration(seconds: 10);
  static const Color _orange = Color(0xFFE09321);

  static final Color _selectedBg = _orange.withValues(alpha: 0.15);

  List<String> _faAuthorLinks = [];
  List<String> _faPostLinks = [];
  List<String> _e621PostLinks = [];

  void _clearState() {
    setState(() {
      _imagePath = null;
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
    final imagePath =
        await context.read<FindSourceRepository>().pickImagePath();

    if (imagePath == null) return;

    setState(() {
      _imagePath = imagePath;
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

  bool _canSendRequest() {
    if (_lastRequestTime == null) return true;
    return DateTime.now().difference(_lastRequestTime!) > _cooldown;
  }

  Future<void> _search() async {
    if (_imagePath == null) {
      setState(() => _error = 'Pick an image first');
      return;
    }

    if (!_canSendRequest()) {
      setState(() => _error = 'Please wait a few seconds before searching again');
      return;
    }

    final repository = context.read<FindSourceRepository>();
    final hash = await repository.hashImagePath(_imagePath!);

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
      final searchResult = await repository.searchSources(_imagePath!);

      if (searchResult.combinedResults.isEmpty) {
        setState(() => _error = 'Couldn\'t find source from FurAffinity.net');
        return;
      }

      setState(() {
        _faAuthorLinks = searchResult.faAuthorLinks;
        _faPostLinks = searchResult.faPostLinks;
        _e621PostLinks = searchResult.e621PostLinks;
        _results = searchResult.combinedResults;
        _accuracy = searchResult.accuracy;
        _lastRequestTime = DateTime.now();
        _lastImageHash = hash;
      });
    } on TimeoutException {
      setState(() => _error = 'Request timed out');
    } on SocketException {
      setState(() => _error = 'No internet connection');
    } on FindSourceError catch (e) {
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
                const TextSpan(text: ' and '),
                TextSpan(
                  text: 'Fluffle',
                  style: TextStyle(color: _orange),
                  recognizer: TapGestureRecognizer()
                    ..onTap = () {
                      Navigator.of(ctx).pop();
                      handleFALink(context, 'https://fluffle.xyz');
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
      child: PopScope(
        canPop: !_selectionMode,
        onPopInvokedWithResult: (bool didPop, dynamic result) {
          if (didPop) return;
          if (_selectionMode) {
            _exitSelectionMode();
          }
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
                      child: _imagePath == null
                          ? Center(
                        child: Text(
                          'Tap here to load image',
                          style: TextStyle(color: _orange),
                        ),
                      )
                          : ClipRRect(
                        borderRadius: BorderRadius.circular(11),
                        child: Image.file(
                          File(_imagePath!),
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
                          child: CircularProgressIndicator(
                              strokeWidth: 2),
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
                          onPressed:
                          _results.isEmpty ? null : _copyAllLinks,
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
                      itemCount: getFindSourceResultItemCount(
                        faAuthorLinks: _faAuthorLinks,
                        faPostLinks: _faPostLinks,
                        e621PostLinks: _e621PostLinks,
                      ),
                      separatorBuilder: (_, _) =>
                      const Divider(color: Colors.white12),
                      itemBuilder: (context, index) {
                        final mapping = getFindSourceResultItem(
                          index: index,
                          faAuthorLinks: _faAuthorLinks,
                          faPostLinks: _faPostLinks,
                          e621PostLinks: _e621PostLinks,
                        );
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

}
