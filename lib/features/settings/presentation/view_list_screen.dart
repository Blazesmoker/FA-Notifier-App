import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:fanotifier/shared/fa/domain/user_link.dart';
import 'package:fanotifier/features/settings/domain/watchlist_repository.dart';
import 'package:fanotifier/shared/widgets/pulsating_loading_indicator.dart';
import 'package:fanotifier/features/profile/presentation/user_profile_screen.dart';

class ViewListScreen extends StatefulWidget {
  final String title;
  final String sanitizedUsername;
  final int expectedUserCount;

  const ViewListScreen({
    super.key,
    required this.title,
    required this.sanitizedUsername,
    required this.expectedUserCount,
  });

  @override
  State<ViewListScreen> createState() => _ViewListScreenState();
}

class _ViewListScreenState extends State<ViewListScreen> {
  static const int _usersPerPage = 200;
  static const int _maxRetries = 5;
  static const Duration _pageOpenDelay = Duration(seconds: 2);
  static const Duration _retryDelay = Duration(seconds: 3);

  List<UserLink> users = [];
  List<UserLink> filteredUsers = [];
  bool isLoading = true;
  String errorMessage = '';
  String searchQuery = '';
  String retryMessage = '';
  int loadedUsersCount = 0;
  final Set<String> _seenUsernames = <String>{};
  late final WatchlistRepository _watchlistRepository;

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
    _watchlistRepository = context.read<WatchlistRepository>();
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
    final parsedUsers = await _watchlistRepository.fetchUsersPage(
      title: widget.title,
      sanitizedUsername: widget.sanitizedUsername,
      page: page,
      cookieHeader: cookieHeader,
      maxRetries: _maxRetries,
      retryDelay: _retryDelay,
      onRetry: (message) {
        if (!mounted) return;
        setState(() {
          retryMessage = message;
        });
      },
    );

    if (parsedUsers == null) {
      return null;
    }

    final pageUsers = <UserLink>[];
    for (final user in parsedUsers) {
      final key = user.cleanUsername.toLowerCase();

      if (_seenUsernames.add(key)) {
        pageUsers.add(user);
      }
    }

    return pageUsers;
  }

  Future<void> _fetchAllUsers() async {
    final cookieHeader = await _watchlistRepository.buildCookieHeader();

    if (cookieHeader.isEmpty) {
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
