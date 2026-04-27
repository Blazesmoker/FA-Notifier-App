import 'package:flutter/material.dart';
import 'package:html/parser.dart';
import 'package:FANotifier/features/profile/domain/user_link.dart';
import 'package:FANotifier/shared/widgets/PulsatingLoadingIndicator.dart';
import 'package:FANotifier/features/profile/presentation/user_profile_screen.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:FANotifier/shared/fa/fa_cookie_helper.dart';
import 'package:FANotifier/shared/fa/fa_http.dart';

class ViewListScreen extends StatefulWidget {
  final String title;
  final String sanitizedUsername;
  final int expectedUserCount;

  const ViewListScreen({
    Key? key,
    required this.title,
    required this.sanitizedUsername,
    required this.expectedUserCount,
  }) : super(key: key);

  @override
  _ViewListScreenState createState() => _ViewListScreenState();
}

class _ViewListScreenState extends State<ViewListScreen> {
  static const int _usersPerPage = 200;
  static const int _maxRetries = 5;
  static const Duration _pageOpenDelay = Duration(seconds: 2);
  static const Duration _retryDelay = Duration(seconds: 3);

  final _secureStorage = FlutterSecureStorage(
    iOptions: IOSOptions(
        accountName: 'flutter_secure_storage_service',
        accessibility: KeychainAccessibility.first_unlock),
  );
  List<UserLink> users = [];
  List<UserLink> filteredUsers = [];
  bool isLoading = true;
  String errorMessage = '';
  String searchQuery = '';
  String retryMessage = '';
  int loadedUsersCount = 0;
  final Set<String> _seenUsernames = <String>{};

  int get _expectedUserCount =>
      widget.expectedUserCount < 0 ? 0 : widget.expectedUserCount;

  int get _estimatedTotalPages {
    if (_expectedUserCount == 0) {
      return 0;
    }
    return (_expectedUserCount / _usersPerPage).ceil();
  }

  Duration get _remainingTime {
    final totalPages = _estimatedTotalPages;
    if (totalPages == 0) {
      return Duration.zero;
    }

    final loadedPages =
        loadedUsersCount == 0 ? 0 : (loadedUsersCount / _usersPerPage).ceil();
    final remainingPages = (totalPages - loadedPages).clamp(0, totalPages);

    return Duration(seconds: remainingPages * _pageOpenDelay.inSeconds);
  }

  String get _listLabel {
    return widget.title == 'Recent Watchers'
        ? 'Recent Watchers'
        : 'Recently Watched Users';
  }

  @override
  void initState() {
    super.initState();
    _fetchAllUsers();
  }

  List<UserLink> _applySearchFilter(String query) {
    if (query.isEmpty) {
      return List<UserLink>.from(users);
    }

    final lowercaseQuery = query.toLowerCase();
    return users
        .where(
          (user) => user.cleanUsername.toLowerCase().contains(lowercaseQuery),
        )
        .toList();
  }

  String _buildPageUrl(int page) {
    final route = widget.title == 'Recent Watchers' ? 'to' : 'by';
    return 'https://www.furaffinity.net/watchlist/$route/${widget.sanitizedUsername}?page=$page';
  }

  String _formatDuration(Duration duration) {
    final totalSeconds = duration.inSeconds;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;

    if (minutes > 0) {
      return '$minutes min $seconds sec';
    }
    return '$seconds sec';
  }

  Future<List<UserLink>?> _fetchUsersForPage({
    required int page,
    required String cookieHeader,
  }) async {
    for (int attempt = 1; attempt <= _maxRetries; attempt++) {
      if (attempt > 1 && mounted) {
        setState(() {
          retryMessage = 'Retrying page $page ($attempt/$_maxRetries)...';
        });
      }

      try {
        final response = await http.get(
          Uri.parse(_buildPageUrl(page)),
          headers: {
            'Cookie': cookieHeader,
            'User-Agent': FAHttp.userAgent,
          },
        );

        if (response.statusCode == 200) {
          final document = parse(response.body);
          final elements = document.querySelectorAll(
            '.watch-list-items a[href*="/user/"]',
          );

          final List<UserLink> pageUsers = [];
          for (final element in elements) {
            final href = element.attributes['href'];
            final rawUsername = element.text.trim();

            if (href == null || href.isEmpty || rawUsername.isEmpty) {
              continue;
            }

            final profileUrl = href.startsWith('http')
                ? href
                : 'https://www.furaffinity.net$href';
            final user = UserLink(rawUsername: rawUsername, url: profileUrl);
            final key = user.cleanUsername.toLowerCase();

            if (_seenUsernames.add(key)) {
              pageUsers.add(user);
            }
          }

          return pageUsers;
        }
      } catch (_) {
        // Retries are handled below.
      }

      if (attempt < _maxRetries) {
        await Future.delayed(_retryDelay);
      }
    }

    return null;
  }

  Future<void> _fetchAllUsers() async {
    String? cookieA = await _secureStorage.read(key: 'fa_cookie_a');
    String? cookieB = await _secureStorage.read(key: 'fa_cookie_b');

    if (cookieA == null || cookieB == null) {
      setState(() {
        errorMessage = 'No cookies found. User might not be logged in.';
        isLoading = false;
      });
      debugPrint("No cookies found.");
      return;
    }

    if (_expectedUserCount == 0) {
      setState(() {
        filteredUsers = users;
        isLoading = false;
      });
      return;
    }

    final totalPages = _estimatedTotalPages;
    final cookieHeader = await FaCookieHelper.appendCfClearanceToCookieHeader(
      'a=$cookieA; b=$cookieB',
    );

    for (int currentPage = 1; currentPage <= totalPages; currentPage++) {
      if (!mounted || loadedUsersCount >= _expectedUserCount) {
        break;
      }

      final newUsers = await _fetchUsersForPage(
        page: currentPage,
        cookieHeader: cookieHeader,
      );

      if (!mounted) {
        return;
      }

      if (newUsers == null) {
        setState(() {
          errorMessage =
              'Failed to load page $currentPage after $_maxRetries attempts.';
          isLoading = false;
          retryMessage = '';
        });
        return;
      }

      setState(() {
        users.addAll(newUsers);
        loadedUsersCount = users.length;
        filteredUsers = _applySearchFilter(searchQuery);
        retryMessage = '';
      });

      if (newUsers.isEmpty) {
        break;
      }

      if (currentPage < totalPages && loadedUsersCount < _expectedUserCount) {
        await Future.delayed(_pageOpenDelay);
      }
    }

    if (!mounted) {
      return;
    }

    setState(() {
      isLoading = false;
      filteredUsers = _applySearchFilter(searchQuery);
    });
  }

  void _filterUsers(String query) {
    setState(() {
      searchQuery = query;
      filteredUsers = _applySearchFilter(query);
    });
  }

  Widget _buildLoadingState() {
    final displayedLoaded = loadedUsersCount > _expectedUserCount
        ? _expectedUserCount
        : loadedUsersCount;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const PulsatingLoadingIndicator(
            size: 78.0,
            assetPath: 'assets/icons/fathemed.png',
          ),
          const SizedBox(height: 20),
          Text(
            'Loaded $displayedLoaded/$_expectedUserCount of $_listLabel for searching.',
            style: const TextStyle(color: Colors.white, fontSize: 16),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Remaining time ~${_formatDuration(_remainingTime)}',
            style: const TextStyle(color: Colors.white70, fontSize: 14),
            textAlign: TextAlign.center,
          ),
          if (retryMessage.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              retryMessage,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLoadedState() {
    return Column(
      children: [
        if (errorMessage.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Text(
              errorMessage,
              style: const TextStyle(color: Colors.redAccent, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: TextField(
            onChanged: _filterUsers,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Search by username',
              hintStyle: const TextStyle(color: Colors.grey),
              filled: true,
              fillColor: const Color(0xFF353535),
              prefixIcon: const Icon(Icons.search, color: Colors.grey),
              isDense: true,
              contentPadding: EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 0.0,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8.0),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: filteredUsers.length,
            itemBuilder: (context, index) {
              final user = filteredUsers[index];
              return Column(
                children: [
                  ListTile(
                    title: Text(
                      user.cleanUsername,
                      style: const TextStyle(color: Color(0xFFE09321)),
                    ),
                    onTap: () {
                      Navigator.push(
                        context,
                        UserProfileScreen.route(
                          nickname: user.nickname,
                        ),
                      );
                    },
                  ),
                  const Divider(
                    height: 1.0,
                    color: Colors.grey,
                    thickness: 0.3,
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: Colors.black,
      ),
      backgroundColor: Colors.black,
      body: isLoading ? _buildLoadingState() : _buildLoadedState(),
    );
  }
}
