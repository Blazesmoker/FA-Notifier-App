// user_profile_screen.dart
import 'package:FANotifier/screens/user_description_webview.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_html/flutter_html.dart' as html_pkg;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart';
import '../model/shout.dart';
import '../model/user_link.dart';
import '../widgets/PulsatingLoadingIndicator.dart';
import 'user_profile_styles.dart';
import 'user_profile_components.dart';
import 'create_journal.dart';
import 'new_message.dart';
import 'openjournal.dart';
import 'openpost.dart';
import 'profilegallery.dart';
import 'post_shout.dart';
import 'profilejournals.dart';
import '../utils/utils.dart';
import 'user_profile_api_service.dart';
import 'user_profile_sliver_helpers.dart';
import 'user_profile_favorites_section.dart';
import 'user_profile_gallery_section.dart';
import 'user_profile_home_section.dart';
import 'user_profile_journals_section.dart';
import 'user_profile_scraps_section.dart';

class UserProfileScreen extends StatefulWidget {
  final String nickname;
  final ProfileSection initialSection;
  final String? initialFolderUrl;
  final String? initialFolderName;
  const UserProfileScreen({
    Key? key,
    required this.nickname,
    this.initialSection = ProfileSection.Home,
    this.initialFolderUrl,
    this.initialFolderName,
  }) : super(key: key);

  @override
  UserProfileScreenState createState() => UserProfileScreenState();
}

enum ProfileSection { Home, Gallery, Scraps, Favs, Journals }

class UserProfileScreenState extends State<UserProfileScreen> with RouteAware, SingleTickerProviderStateMixin {

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    routeObserver.subscribe(this, ModalRoute.of(context)! as PageRoute);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _scrollController.dispose();
    _scrollController.removeListener(_updateAvatarTransform);
    routeObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  void didPopNext() {

    _journalsKey.currentState?.refreshJournals();
  }

  final GlobalKey<ProfileJournalsState> _journalsKey = GlobalKey<ProfileJournalsState>();
  final GlobalKey<UserDescriptionWebViewState> _webViewKey = GlobalKey<UserDescriptionWebViewState>();

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    iOptions: IOSOptions(
    accountName: 'flutter_secure_storage_service',
    accessibility: KeychainAccessibility.first_unlock),
  );
  late final UserProfileApiService _api;


  bool _sfwEnabled = true;



  Future<void> _loadSfwEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _sfwEnabled = prefs.getBool('sfwEnabled') ?? true;
    });
  }

  /// Handles long-press on the user description for copy/select actions.
  Future<void> _handleDescriptionLongPress(LongPressStartDetails details) async {
    final RenderBox overlay = Overlay.of(context)!.context.findRenderObject() as RenderBox;
    final RelativeRect position = RelativeRect.fromRect(
      details.globalPosition & const Size(40, 40),
      Offset.zero & overlay.size,
    );
    final selected = await showMenu<String>(
      context: context,
      position: position,
      items: const [
        PopupMenuItem<String>(
          value: 'copy',
          child: Text('Copy'),
        ),
        PopupMenuItem<String>(
          value: 'select',
          child: Text('Select Text'),
        ),
      ],
    );
    if (selected == 'copy') {
      final plainText = await _webViewKey.currentState?.getPlainText();
      if (plainText != null) {
        await Clipboard.setData(ClipboardData(text: plainText));
        showAppSnackBar(context, 'Text copied to clipboard', backgroundColor: Colors.green);
      }
    } else if (selected == 'select') {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => UserDescriptionWebViewScreen(
            sanitizedUsername: sanitizedUsername,
            initialHtml: userDescription,
          ),
        ),
      );
    }
  }

  String _selectedFolderName = 'Main Gallery';
  String _selectedFolderUrl = '';
  List<FaFolder> _allFolders = [];

  UserProfileParsed? _profileParsed;

  String? get profileBannerUrl => _profileParsed?.profileBannerUrl;
  String? get profileImageUrl => _profileParsed?.profileImageUrl;
  String? get profileDisplayName => _profileParsed?.profileDisplayName;
  String? get profileUserNamePart => _profileParsed?.profileUserNamePart;
  String? get symbolUsername => _profileParsed?.symbolUsername;
  String? get username => _profileParsed?.username;
  String? get userTitle => _profileParsed?.userTitle;
  String? get registrationDate => _profileParsed?.registrationDate;
  String? get userDescription => _profileParsed?.userDescription;
  bool get hasRealUserProfile => _profileParsed?.hasRealUserProfile ?? true;

  bool get isClassicMarkup => _profileParsed?.isClassicMarkup ?? false;
  bool get acceptingTrades => _profileParsed?.acceptingTrades ?? false;
  bool get acceptingCommissions => _profileParsed?.acceptingCommissions ?? false;

  List<String> get userIconBeforeUrls => _profileParsed?.userIconBeforeUrls ?? const [];
  List<String> get userIconAfterUrls => _profileParsed?.userIconAfterUrls ?? const [];

  int? get views => _profileParsed?.views;
  int? get submissions => _profileParsed?.submissions;
  int? get favs => _profileParsed?.favs;
  int? get commentsEarned => _profileParsed?.commentsEarned;
  int? get commentsMade => _profileParsed?.commentsMade;
  int? get journals => _profileParsed?.journals;

  bool get isWatching => _profileParsed?.isWatching ?? false;
  String? get watchLink => _profileParsed?.watchLink;
  String? get unwatchLink => _profileParsed?.unwatchLink;
  String? get unblockLink => _profileParsed?.unblockLink;
  String? get blockLink => _profileParsed?.blockLink;
  bool get isBlocked => _profileParsed?.isBlocked ?? false;
  bool get blockUsesPost => _profileParsed?.blockUsesPost ?? false;
  bool get unblockUsesPost => _profileParsed?.unblockUsesPost ?? false;

  String? get featuredImageUrl => _profileParsed?.featuredImageUrl;
  String? get featuredImageTitle => _profileParsed?.featuredImageTitle;
  String? get featuredPostNumber => _profileParsed?.featuredPostNumber;

  String? get userProfileImageUrl => _profileParsed?.userProfileImageUrl;
  String? get userProfilePostNumber => _profileParsed?.userProfilePostNumber;
  String? get userProfileTexts => _profileParsed?.userProfileTexts;

  List<Map<String, String>> get contactInformationLinks => _profileParsed?.contactInformationLinks ?? const [];

  List<UserLink> get recentWatchers => _profileParsed?.recentWatchers ?? const [];
  int get recentWatchersCount => _profileParsed?.recentWatchersCount ?? 0;

  List<UserLink> get recentlyWatched => _profileParsed?.recentlyWatched ?? const [];
  int get recentlyWatchedCount => _profileParsed?.recentlyWatchedCount ?? 0;

  List<Shout> get shouts => _profileParsed?.shouts ?? <Shout>[];
  String? get shoutPaginationKey => _profileParsed?.shoutPaginationKey;
  int get currentShoutPage => _profileParsed?.currentShoutPage ?? 1;
  int get totalShoutPages => _profileParsed?.totalShoutPages ?? 1;

  bool get isOwnProfile => _profileParsed?.isOwnProfile ?? false;

  bool _compareFolderUrls(String url1, String url2) {
    final uri1 = Uri.parse(url1);
    final uri2 = Uri.parse(url2);


    String normalizePath(String path) => path.endsWith('/')
        ? path.substring(0, path.length - 1)
        : path;

    return uri1.scheme == uri2.scheme &&
        uri1.host == uri2.host &&
        normalizePath(uri1.path) == normalizePath(uri2.path);
  }

  void _onFoldersParsed(List<FaFolder> folders) {
    setState(() {

      if (_selectedFolderUrl.isNotEmpty) {
        final matchingFolder = folders.firstWhere(
              (folder) => _compareFolderUrls(folder.url, _selectedFolderUrl),
          orElse: () => FaFolder(name: _selectedFolderName, url: _selectedFolderUrl),
        );
        _selectedFolderName = matchingFolder.name;
        _selectedFolderUrl = matchingFolder.url;
      } else if (folders.isNotEmpty) {

        final mainGallery = folders.firstWhere(
              (f) => f.name == 'Main Gallery',
          orElse: () => folders.first,
        );
        _selectedFolderName = mainGallery.name;
        _selectedFolderUrl = mainGallery.url;
      }

      _allFolders = folders;
    });
  }


  void _onFolderSelected(FaFolder folder) {
    setState(() {
      _selectedFolderName = folder.name;
      _selectedFolderUrl = folder.url;
    });
  }

  String sanitizedUsername = '';
  bool isLoading = true;
  bool _webViewLoaded = false;
  String errorMessage = '';


  static const double sliverAppBarExpandedHeight = 120.0;
  static const double sliverAppBarMinHeight = kToolbarHeight - 80.0; // 56.0
  static const double collapsibleHeaderMaxHeight = 110.0;
  static const double navigationSliderHeight = 64.0;

  final double _bannerScaleStart = 0.0;
  final double _bannerScaleEnd = 180.0;


  late ScrollController _scrollController;


  late TabController _tabController;


  int _previousIndex = 0;


  late Future<String> _userDescriptionFuture;


  final double _avatarFadeStart = 0.0;
  final double _avatarFadeEnd = 140.0;
  final double _avatarScaleStart = 0.0;
  final double _avatarScaleEnd = 140.0;

  bool isLoadingMoreShouts = false;



  @override
  void initState() {
    super.initState();

    _api = UserProfileApiService(_secureStorage);

    if (widget.initialFolderUrl != null && widget.initialFolderUrl!.isNotEmpty) {
      _selectedFolderUrl = widget.initialFolderUrl!;
      _selectedFolderName = widget.initialFolderName ?? _selectedFolderName;
    }
    if (widget.initialSection != ProfileSection.Home) {
      _webViewLoaded = true;
    }


    _loadSfwEnabled();


    _scrollController = ScrollController();
    _scrollController.addListener(_updateAvatarTransform);


    _tabController = TabController(
      length: ProfileSection.values.length,
      vsync: this,
      initialIndex: widget.initialSection.index,
    );


    _tabController.addListener(() {
      if (!_tabController.indexIsChanging && _previousIndex != _tabController.index) {
        final double appBarHeight = sliverAppBarExpandedHeight - sliverAppBarMinHeight;
        final double targetOffset = appBarHeight + collapsibleHeaderMaxHeight - 24;

        if (_scrollController.hasClients && _scrollController.offset >= targetOffset) {
          _scrollController.animateTo(
            targetOffset,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
        _previousIndex = _tabController.index;
      }
    });

    sanitizedUsername = _sanitizeUsername(widget.nickname);

    _initAsyncFetch();
  }

  Future<void> _initAsyncFetch() async {
    await _loadSfwEnabled();
    await _fetchUserProfile();
  }

  void _updateAvatarTransform() {
    double offset = _scrollController.offset;

    // Calculate new opacity based on offset
    double newOpacity;
    if (offset <= _avatarFadeStart) {
      newOpacity = 1.0;
    } else if (offset >= _avatarFadeEnd) {
      newOpacity = 0.0;
    } else {
      // Linear interpolation between full opacity (1.0) and no opacity (0.0)
      newOpacity = 1.0 - ((offset - _avatarFadeStart) / (_avatarFadeEnd - _avatarFadeStart));
    }


    double newScale;
    if (offset <= _avatarScaleStart) {
      newScale = 1.0;
    } else if (offset >= _avatarScaleEnd) {
      newScale = 0.2;
    } else {
      double scaleFraction = (offset - _avatarScaleStart) / (_avatarScaleEnd - _avatarScaleStart);
      newScale = 1.0 - (0.8 * scaleFraction);
    }
  }


  IconData _getIconForSection(ProfileSection section) {
    switch (section) {
      case ProfileSection.Home:
        return Icons.home;
      case ProfileSection.Gallery:
        return Icons.photo;
      case ProfileSection.Scraps:
        return Icons.collections_bookmark;
      case ProfileSection.Favs:
        return Icons.favorite;
      case ProfileSection.Journals:
        return Icons.book;
      default:
        return Icons.home;
    }
  }


  String _getTabTitle(ProfileSection section) {
    switch (section) {
      case ProfileSection.Home:
        return 'Home';
      case ProfileSection.Gallery:
        return 'Gallery';
      case ProfileSection.Scraps:
        return 'Scraps';
      case ProfileSection.Favs:
        return 'Favs';
      case ProfileSection.Journals:
        return 'Journals';
      default:
        return 'Home';
    }
  }


  Future<void> _setupWebviewCookies() async {
    String? cookieA = await _secureStorage.read(key: 'fa_cookie_a');
    String? cookieB = await _secureStorage.read(key: 'fa_cookie_b');

    if (cookieA != null && cookieB != null) {
      final cookieManager = CookieManager.instance();


      await cookieManager.setCookie(
        url: WebUri('https://www.furaffinity.net'),
        name: 'a',
        value: cookieA,
      );


      await cookieManager.setCookie(
        url: WebUri('https://www.furaffinity.net'),
        name: 'b',
        value: cookieB,
      );
    }
  }

  Future<void> _sendWatchUnwatchRequest(String urlPath, {required bool shouldWatch}) async {
    final result = await _api.sendWatchUnwatchRequest(
      urlPath,
      shouldWatch: shouldWatch,
      sfwEnabled: _sfwEnabled,
    );

    if (result.missingCookies) {
      print('No cookies found. User might not be logged in.');
      showAppSnackBar(context, 'Please log in to perform this action.', backgroundColor: Colors.red);
      return;
    }

    if (result.success) {
      print('${shouldWatch ? 'Watch' : 'Unwatch'} action successful.');

      setState(() {
        _profileParsed?.isWatching = shouldWatch;
      });

      showAppSnackBar(
        context,
        '${shouldWatch ? 'Now watching $username' : 'Stopped watching $username'}',
        backgroundColor: Colors.green,
      );
    } else if (result.error != null) {
      print('Error during ${shouldWatch ? 'watch' : 'unwatch'}: ${result.error}');
      showAppSnackBar(
        context,
        'An error occurred while trying to ${shouldWatch ? 'watch' : 'unwatch'} user.',
        backgroundColor: Colors.red,
      );
    } else {
      print('Failed to ${shouldWatch ? 'watch' : 'unwatch'}. Status code: ${result.statusCode}');
      showAppSnackBar(
        context,
        'Failed to ${shouldWatch ? 'watch' : 'unwatch'} user.',
        backgroundColor: Colors.red,
      );
    }
  }

  Future<void> _handleWatchButtonPressed() async {
    if (isWatching) {
      if (unwatchLink == null) {
        print('Unwatch link not available.');
        return;
      }
      await _sendWatchUnwatchRequest(unwatchLink!, shouldWatch: false);
      _fetchUserProfile();
    } else {
      if (watchLink == null) {
        print('Watch link not available.');
        return;
      }
      await _sendWatchUnwatchRequest(watchLink!, shouldWatch: true);
      _fetchUserProfile();
    }
  }

  Future<void> _confirmDeleteShout(int index, Shout shout) async {

    if (!isOwnProfile) {
      return;
    }

    setState(() {
      shout.selected = true;
    });
    bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Confirm deletion"),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Are you sure you want to delete shout from ${shout.username}?',
                style: const TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 10),
              html_pkg.Html(
                data: shout.text,
                style: userProfileHtmlStyles(),
                extensions: buildUserProfileBBCodeExtensions(),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text("Delete"),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _deleteShout(index, shout);
    } else {
      setState(() {
        shout.selected = false;
      });
    }
  }

  Future<void> _deleteShout(int index, Shout shout) async {
    final result = await _api.deleteShout(
      shoutId: shout.id,
      sfwEnabled: _sfwEnabled,
    );

    if (result.missingCookies) {
      showAppSnackBar(context, "Please log in to perform this action.", backgroundColor: Colors.red);
      return;
    }

    if (result.success) {
      showAppSnackBar(context, "Shout deleted.", backgroundColor: Colors.green);
      await _fetchUserProfile();
    } else if (result.error != null) {
      showAppSnackBar(context, "Error: ${result.error}", backgroundColor: Colors.red);
    } else {
      showAppSnackBar(context, "Failed to delete shout.", backgroundColor: Colors.red);
    }
  }


  Future<void> _launchURL(String url) async {
    final Uri uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {

      print('Could not launch $url');
      showAppSnackBar(context, 'Could not launch URL: $url', backgroundColor: Colors.red);
    }
  }

  /// Handles FA links inside HTML/description, matching the legacy inline logic.
  Future<void> _handleFALink(BuildContext context, String url) async {
    final Uri uri = Uri.parse(url);
    final String urlToMatch = uri.toString();

    // Gallery Folder Link
    final RegExp galleryFolderRegex = RegExp(
      r'^https?://(?:www\.)?furaffinity\.net/gallery/([a-zA-Z0-9\-_.~]+)/folder/(\d+)/([a-zA-Z0-9\-_.~]+)/?$',
    );
    if (galleryFolderRegex.hasMatch(urlToMatch)) {
      final match = galleryFolderRegex.firstMatch(urlToMatch)!;
      final String tappedUsername = match.group(1)!;
      final String folderNumber = match.group(2)!;
      final String folderName = match.group(3)!;
      final String folderUrl =
          'https://www.furaffinity.net/gallery/$tappedUsername/folder/$folderNumber/$folderName/';
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => UserProfileScreen(
            nickname: tappedUsername,
            initialSection: ProfileSection.Gallery,
            initialFolderUrl: folderUrl,
            initialFolderName: folderName,
          ),
        ),
      );
      return;
    }

    // User Link
    final RegExp userRegex = RegExp(
      r'^(?:https?://(?:www\.)?furaffinity\.net)?/user/([a-zA-Z0-9\-_.~]+)/?$',
    );
    if (userRegex.hasMatch(urlToMatch)) {
      final String tappedUsername = userRegex.firstMatch(urlToMatch)!.group(1)!;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => UserProfileScreen(nickname: tappedUsername),
        ),
      );
      return;
    }

    // Journal Link
    final RegExp journalRegex = RegExp(
      r'^(?:https?://(?:www\.)?furaffinity\.net)?/(?:journals/([a-zA-Z0-9\-_.~]+)|journal/(\d+))(?:/.*)?(?:#.*)?$',
    );
    if (journalRegex.hasMatch(urlToMatch)) {
      final match = journalRegex.firstMatch(urlToMatch)!;
      final String? userNameFromJournal = match.group(1);
      final String? journalId = match.group(2);
      if (userNameFromJournal != null) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => UserProfileScreen(
              nickname: userNameFromJournal,
              initialSection: ProfileSection.Journals,
            ),
          ),
        );
      } else if (journalId != null) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => OpenJournal(uniqueNumber: journalId),
          ),
        );
      }
      return;
    }

    // Submission/View Link
    final RegExp viewRegex = RegExp(
      r'^(?:https?://(?:www\.)?furaffinity\.net)?/view/(\d+)(?:/.*)?(?:#.*)?$',
    );
    if (viewRegex.hasMatch(urlToMatch)) {
      final String submissionId = viewRegex.firstMatch(urlToMatch)!.group(1)!;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => OpenPost(
            uniqueNumber: submissionId,
            imageUrl: '',
          ),
        ),
      );
      return;
    }

    // Fallback: external link
    await launchUrlString(url, mode: LaunchMode.externalApplication);
  }

  /// Fetches the user's profile data from FurAffinity.
  Future<void> _fetchUserProfile() async {
    try {
      final payload = await _api.fetchProfile(
        nickname: widget.nickname,
        sfwEnabled: _sfwEnabled,
      );

      sanitizedUsername = payload.sanitizedUsername;

      final parsed = _api.parseUserProfile(payload.htmlBody);
      final bool shouldShowDescription = parsed.hasRealUserProfile &&
          parsed.userDescription != null &&
          parsed.userDescription!.trim().isNotEmpty;

      setState(() {
        _profileParsed = parsed;
        _webViewLoaded = shouldShowDescription ? _webViewLoaded : true;
        isLoading = false;
      });

      print("Block/Unblock Link: $blockLink / $unblockLink");
      print("Watch/Unwatch Link: $watchLink / $unwatchLink");
      print("isBlocked: $isBlocked");
    } on StateError catch (e) {
      setState(() {
        errorMessage = e.message ?? e.toString();
        isLoading = false;
      });
      print(e.toString());
    } catch (e) {
      setState(() {
        errorMessage = 'An error occurred: $e';
        isLoading = false;
      });
      print("An error occurred while fetching profile: $e");
    }
  }


  final _usernameSanitizeRegex = RegExp(r'[^a-zA-Z0-9\-_.~]');
  String _sanitizeUsername(String username) {
    return username
        .replaceAll(_usernameSanitizeRegex, '')
        .toLowerCase();
  }

  void switchToGalleryTab() {
    _tabController.animateTo(ProfileSection.Gallery.index);
  }

  Future<void> _loadMoreShouts() async {
    if (isLoadingMoreShouts || currentShoutPage >= totalShoutPages) {
      print("Cannot load more shouts. Loading: $isLoadingMoreShouts, Current: $currentShoutPage, Total: $totalShoutPages");
      return;
    }

    setState(() {
      isLoadingMoreShouts = true;
    });

    try {
      final nextPage = currentShoutPage + 1;
      final payload = await _api.fetchAdditionalShouts(
        sanitizedUsername: sanitizedUsername,
        shoutPaginationKey: shoutPaginationKey,
        nextPage: nextPage,
        sfwEnabled: _sfwEnabled,
        existingShoutIds: shouts.map((s) => s.id).toSet(),
      );

      if (payload == null) {
        print("Missing shout pagination key; cannot load more shouts.");
        return;
      }

      setState(() {
        _profileParsed?.shouts.addAll(payload.newShouts);
        if (_profileParsed != null) {
          _profileParsed!.currentShoutPage = payload.nextPage;
        }
      });
    } catch (e) {
      print('Error loading more shouts: $e');
      showAppSnackBar(context, 'Failed to load more shouts', backgroundColor: Colors.red);
    } finally {
      setState(() {
        isLoadingMoreShouts = false;
      });
    }
  }

  /// Helper function to extract integer values from the stats text
  int? _extractStatValue(String statsText, String label) {
    final regex = RegExp('$label\\s*(\\d+)');
    final match = regex.firstMatch(statsText);
    if (match != null && match.groupCount > 0) {
      return int.tryParse(match.group(1)!);
    }
    return null;
  }

  // Animated banner/avatar helpers
  Widget buildAnimatedBanner(BoxConstraints constraints) {
    double alignmentX = -1.0;
    if (profileBannerUrl?.contains('fa-banner') ?? false) {
      double shiftFraction = 30.0 / constraints.maxWidth * 2;
      alignmentX += shiftFraction;
    }

    return AnimatedBuilder(
      animation: _scrollController,
      builder: (context, child) {
        double offset = _scrollController.hasClients ? _scrollController.offset : 0.0;

        double newScale;
        if (offset <= _bannerScaleStart) {
          newScale = 1.0;
        } else if (offset >= _bannerScaleEnd) {
          newScale = 1.0;
        } else {
          double scaleFraction = (offset - _bannerScaleStart) / (_bannerScaleEnd - _bannerScaleStart);
          newScale = 1.0 - (0.2 * scaleFraction);
        }

        return Transform.scale(
          scale: newScale.clamp(1.0, 1.0),
          alignment: Alignment(alignmentX, 0),
          child: child,
        );
      },
      child: CachedNetworkImage(
        imageUrl: profileBannerUrl ??
            'https://d.furaffinity.net/media/banners/modern/fa-banner-summer.jpg',
        fit: BoxFit.cover,
        alignment: Alignment(alignmentX, 0),
        placeholder: (context, url) => const Center(child: CircularProgressIndicator()),
        errorWidget: (context, url, error) => Container(color: Colors.grey),
      ),
    );
  }

  Widget buildAnimatedAvatar() {
    const double avatarLeft = 16.0;
    const double avatarSize = 90.0;

    return AnimatedBuilder(
      animation: _scrollController,
      builder: (context, child) {
        double offset = _scrollController.hasClients ? _scrollController.offset : 0.0;

        double newOpacity;
        if (offset <= _avatarFadeStart) {
          newOpacity = 1.0;
        } else if (offset >= _avatarFadeEnd) {
          newOpacity = 0.0;
        } else {
          newOpacity = 1.0 - ((offset - _avatarFadeStart) / (_avatarFadeEnd - _avatarFadeStart));
        }

        double newScale;
        if (offset <= _avatarScaleStart) {
          newScale = 1.0;
        } else if (offset >= _avatarScaleEnd) {
          newScale = 0.2;
        } else {
          double scaleFraction = (offset - _avatarScaleStart) / (_avatarScaleEnd - _avatarScaleStart);
          newScale = 1.0 - (0.8 * scaleFraction);
        }

        return Positioned(
          bottom: -avatarSize / 1.5,
          left: avatarLeft,
          child: Transform.scale(
            scale: newScale.clamp(0.2, 1.0),
            child: Opacity(
              opacity: newOpacity.clamp(0.0, 1.0),
              child: child,
            ),
          ),
        );
      },
      child: GestureDetector(
        onTap: () {},
        child: CachedNetworkImage(
          imageUrl: profileImageUrl ?? '',
          width: avatarSize,
          height: avatarSize,
          filterQuality: FilterQuality.low,
          fit: BoxFit.cover,
          placeholder: (context, url) => SizedBox(
            width: avatarSize / 2,
            height: avatarSize / 2,
            child: const Center(
              child: CircularProgressIndicator(strokeWidth: 2.0),
            ),
          ),
          errorWidget: (context, url, error) => Image.asset(
            'assets/images/defaultpic.gif',
            width: avatarSize,
            height: avatarSize,
            fit: BoxFit.cover,
          ),
        ),
      ),
    );
  }


  GlobalKey _profileNameRowKey = GlobalKey();

  void _clearProfileNameSelection() {
    setState(() {

      _profileNameRowKey = GlobalKey();
    });
  }



  void _copyProfileLinkToClipboard() {
    final profileLink = 'https://www.furaffinity.net/user/$sanitizedUsername/';
    Clipboard.setData(ClipboardData(text: profileLink)).then((_) {
      showAppSnackBar(context, 'Copied profile link!', backgroundColor: Colors.green);
    }).catchError((error) {
      print('Failed to copy profile link: $error');
      showAppSnackBar(context, 'Failed to copy profile link.', backgroundColor: Colors.red);
    });
  }

  Widget _buildProfileHeaderNameRow() {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTapDown: (TapDownDetails details) {
        final RenderBox? renderBox = _profileNameRowKey.currentContext?.findRenderObject() as RenderBox?;
        if (renderBox != null) {
          final Offset localPosition = renderBox.globalToLocal(details.globalPosition);
          if (!renderBox.size.contains(localPosition)) {
            _clearProfileNameSelection();
          }
        } else {
          _clearProfileNameSelection();
        }
      },
      child: Container(
        key: _profileNameRowKey,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            if (userIconBeforeUrls.isNotEmpty)
              ...userIconBeforeUrls.map(
                    (url) => Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Image.network(url, width: 20, height: 20),
                    ),
                  ),
            SelectableLinkify(
              text: profileDisplayName ?? '',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20.0,
                fontWeight: FontWeight.bold,
              ),
              onOpen: (link) async {},
              selectionControls: MaterialTextSelectionControls(),
            ),
            const SizedBox(width: 4),
            if (userIconAfterUrls.isNotEmpty)
              ...userIconAfterUrls.map(
                    (url) => Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Image.network(url, width: 20, height: 20),
                    ),
                  ),
            SelectableLinkify(
              text: profileUserNamePart ?? '',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20.0,
              ),
              onOpen: (link) async {},
              selectionControls: MaterialTextSelectionControls(),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _sendBlockUnblockRequest(
      String urlOrPath,
      String keyValue, {
        required bool shouldBlock,
        required bool usePost,
      }) async {
    final result = await _api.sendBlockUnblockRequest(
      urlOrPath,
      keyValue,
      shouldBlock: shouldBlock,
      usePost: usePost,
      sfwEnabled: _sfwEnabled,
      sanitizedUsername: sanitizedUsername,
    );

    if (result.missingCookies) {
      showAppSnackBar(
        context,
        'Please log in to perform this action.',
        backgroundColor: Colors.red,
      );
      return;
    }

    if (result.success) {
      await _fetchUserProfile();
      showAppSnackBar(
        context,
        shouldBlock ? 'Author blocked' : 'Author unblocked',
        backgroundColor: Colors.green,
      );
    } else if (result.error != null) {
      showAppSnackBar(
        context,
        'An error occurred while trying to ${shouldBlock ? 'block' : 'unblock'} author.',
        backgroundColor: Colors.red,
      );
    } else {
      showAppSnackBar(
        context,
        'Failed to ${shouldBlock ? 'block' : 'unblock'} author.',
        backgroundColor: Colors.red,
      );
    }
  }

  Future<void> _handleBlockUnblock() async {
    if (isBlocked) {
      if (unblockLink == null) {
        showAppSnackBar(
          context,
          'Cannot unblock author at this time.',
          backgroundColor: Colors.red,
        );
        return;
      }
      final unblockUri = Uri.parse(unblockLink!);

      final key = unblockUri.queryParameters['key'];

      if (key == null || key.isEmpty) {
        showAppSnackBar(
          context,
          'Cannot unblock author at this time.',
          backgroundColor: Colors.red,
        );
        return;
      }

      await _sendBlockUnblockRequest(
        unblockLink!,
        key,
        shouldBlock: false,
        usePost: unblockUsesPost,
      );
    } else {
      if (blockLink == null) {
        showAppSnackBar(
          context,
          'Cannot block author at this time.',
          backgroundColor: Colors.red,
        );
        return;
      }

      final blockUri = Uri.parse(blockLink!);

      final key = blockUri.queryParameters['key'];

      if (key == null || key.isEmpty) {
        showAppSnackBar(
          context,
          'Cannot block author at this time.',
          backgroundColor: Colors.red,
        );
        return;
      }

      await _sendBlockUnblockRequest(
        blockLink!,
        key,
        shouldBlock: true,
        usePost: blockUsesPost,
      );
    }
  }


  /// Builds the main UI of the screen with unified scrolling.
  @override
  Widget build(BuildContext context) {
    // Define constants for the avatar and text alignment.
    const double avatarLeft = 16.0;
    const double avatarWidth = 90.0;
    const double marginBetweenAvatarAndText = 0.0;
    final double textLeftPadding = avatarLeft + avatarWidth + marginBetweenAvatarAndText;
    final bool needsDescriptionLoad = hasRealUserProfile && userDescription != null;
    bool showLoadingIndicator = isLoading ||
        (needsDescriptionLoad &&
            !_webViewLoaded &&
            _tabController.index == ProfileSection.Home.index);

    return DefaultTabController(
      length: ProfileSection.values.length,
      child: Scaffold(
        backgroundColor: Colors.black,
        body:
        SafeArea(
          top: false,
        child: Stack(
          children: [

          GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => _clearProfileNameSelection(),
          child: NotificationListener<ScrollNotification>(
            onNotification: (ScrollNotification notification) {
              _updateAvatarTransform();
              return false;
            },
            child: NestedScrollView(
              controller: _scrollController,

              headerSliverBuilder: (context, innerBoxIsScrolled) => [
                SliverAppBar(
                  centerTitle: false,
                  leading: IconButton(
                    icon: Stack(
                      alignment: Alignment.center,
                      children: [
                        Positioned(left: 1, child: Icon(Icons.arrow_back, size: 24, color: Color(0xFF111111))),
                        Positioned(right: 1, child: Icon(Icons.arrow_back, size: 24, color: Color(0xFF111111))),
                        Positioned(top: 1, child: Icon(Icons.arrow_back, size: 24, color: Color(0xFF111111))),
                        Positioned(bottom: 1, child: Icon(Icons.arrow_back, size: 24, color: Color(0xFF111111))),
                        Icon(Icons.arrow_back, size: 24, color: Colors.white),
                      ],
                    ),
                    onPressed: () {
                      _webViewKey.currentState?.hideWebView();
                      Future.delayed(const Duration(milliseconds: 5), () {
                        Navigator.pop(context);
                      });
                    },
                  ),
                  title: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Stack(
                        children: [
                          // Stroked text as outline
                          Text(
                            symbolUsername ?? 'Profile',
                            style: TextStyle(
                              fontSize: 18.0,
                              fontWeight: FontWeight.bold,
                              foreground: Paint()
                                ..style = PaintingStyle.stroke
                                ..strokeWidth = 2
                                ..color = Color(0xFF111111),
                            ),
                          ),
                          // Filled text on top
                          Text(
                            symbolUsername ?? 'Profile',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18.0,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),

                      if (symbolUsername != null &&
                          symbolUsername!.startsWith('!'))
                        const Padding(
                          padding: EdgeInsets.only(left: 8.0),
                          child: Text(
                            "USER BANNED",
                            style: TextStyle(
                              color: Colors.red,
                              fontSize: 18.0,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  ),
                  expandedHeight: sliverAppBarExpandedHeight,
                  pinned: true,
                  floating: false,
                  snap: false,
                  backgroundColor: Colors.black.withOpacity(
                    (_scrollController.hasClients &&
                        _scrollController.offset > 50)
                        ? (_scrollController.offset / 200).clamp(0.0, 1.0)
                        : 0.0,
                  ),
                  actions: [
                    Builder(
                      builder: (context) {
                        return IconButton(
                          icon: Stack(
                            alignment: Alignment.center,
                            children: [
                              Positioned(left: 1, child: Icon(Icons.more_vert, size: 24, color: Color(0xFF111111))),
                              Positioned(right: 1, child: Icon(Icons.more_vert, size: 24, color: Color(0xFF111111))),
                              Positioned(top: 1, child: Icon(Icons.more_vert, size: 24, color: Color(0xFF111111))),
                              Positioned(bottom: 1, child: Icon(Icons.more_vert, size: 24, color: Color(0xFF111111))),
                              Icon(Icons.more_vert, size: 24, color: Colors.white),
                            ],
                          ),
                          onPressed: () async {
                            final RenderBox button = context.findRenderObject() as RenderBox;
                            final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
                            final RelativeRect position = RelativeRect.fromRect(
                              Rect.fromPoints(
                                button.localToGlobal(const Offset(0, 0), ancestor: overlay),
                                button.localToGlobal(Offset(0, button.size.height + 10), ancestor: overlay),
                              ),
                              Offset.zero & overlay.size,
                            );

                            List<PopupMenuEntry<String>> menuItems = [
                              const PopupMenuItem<String>(
                                value: 'report',
                                child: Text('Report'),
                              ),
                              if (!isOwnProfile)
                                PopupMenuItem<String>(
                                  value: 'block_unblock',
                                  child: Text(isBlocked ? 'Unblock author' : 'Block author'),
                                ),
                              const PopupMenuItem<String>(
                                value: 'copy_link',
                                child: Text('Copy link'),
                              ),
                            ];

                            final selected = await showMenu<String>(
                              context: context,
                              position: position,
                              items: menuItems,
                            );

                            switch (selected) {
                              case 'report':
                                launchUrlString('https://www.furaffinity.net/controls/troubletickets/');
                                break;
                              case 'block_unblock':
                                if (!isOwnProfile) {
                                  await _handleBlockUnblock();
                                }
                                break;
                              case 'copy_link':
                                _copyProfileLinkToClipboard();
                                break;
                              default:
                                break;
                            }
                          },
                        );
                      },
                    ),
                  ],
                  flexibleSpace: LayoutBuilder(
                    builder: (context, constraints) {
                      final double expandedHeight =
                          sliverAppBarExpandedHeight;
                      final double scrollRange =
                          expandedHeight - kToolbarHeight;
                      double shrinkOffset = _scrollController.hasClients
                          ? _scrollController.offset
                          .clamp(0.0, scrollRange)
                          : 0.0;
                      double alignmentX = -1.0;

                      return Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Positioned.fill(
                            child: buildAnimatedBanner(constraints),
                          ),
                          Container(
                            color: Colors.black.withOpacity(0.15),
                          ),
                          buildAnimatedAvatar(),
                        ],
                      );
                    },
                  ),
                ),
                SliverPersistentHeader(
                  delegate: FixedSliverPersistentHeaderDelegate(
                    height: 160,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Divider(
                          height: 4.0,
                          color: Color(0xFF111111),
                          thickness: 3.0,
                        ),
                        const Divider(
                          height: 2.0,
                          color: Colors.black,
                          thickness: 1.0,
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: double.infinity,
                              color: const Color(0xFF111111),
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(8.0, 0.0, 8.0, 8.0),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    MediaQuery(
                                      data: MediaQuery.of(context).copyWith(textScaleFactor: 1.0),
                                      child: Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            SizedBox(
                                              height: 30.0,
                                              child: Padding(
                                                padding: EdgeInsets.only(left: textLeftPadding),
                                                child: FittedBox(
                                                  fit: BoxFit.scaleDown,
                                                  alignment: Alignment.centerLeft,
                                                  child: _buildProfileHeaderNameRow(),
                                                ),
                                              ),
                                            ),
                                            SizedBox(
                                              height: 24.0,
                                              child: Visibility(
                                                visible: true,
                                                maintainSize: true,
                                                maintainAnimation: true,
                                                maintainState: true,
                                                child: Padding(
                                                  padding: EdgeInsets.only(
                                                    top: 0.0,
                                                    left: textLeftPadding,
                                                  ),
                                                  child: FittedBox(
                                                    fit: BoxFit.scaleDown,
                                                    alignment: Alignment.center,
                                                    child: Text(
                                                      (userTitle?.isNotEmpty ?? false)
                                                          ? userTitle!
                                                          : " ",
                                                      style: const TextStyle(
                                                        color: Colors.white70,
                                                        fontSize: 16.0,
                                                      ),
                                                      maxLines: 1,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                top: 8.0,
                                                left: 0.0,
                                              ),
                                              child: FittedBox(
                                                fit: BoxFit.scaleDown,
                                                alignment: Alignment.centerLeft,
                                                child: Text(
                                                  registrationDate != null &&
                                                      registrationDate!.isNotEmpty
                                                      ? 'Joined $registrationDate'
                                                      : '',
                                                  style: const TextStyle(
                                                    color: Colors.white70,
                                                    fontSize: 14.0,
                                                  ),
                                                  maxLines: 1,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    if (isOwnProfile)
                                      SizedBox(
                                        width: 100,
                                        height: 38,
                                        child: ElevatedButton(
                                          onPressed: _showEditProfileDialog,
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.black,
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(2),
                                            ),
                                            side: const BorderSide(
                                              color: Color(0xFFE09321),
                                            ),
                                          ),
                                          child: const FittedBox(
                                            fit: BoxFit.scaleDown,
                                            child: Text(
                                              "Edit Profile",
                                              style: TextStyle(
                                                color: Colors.white,
                                              ),
                                            ),
                                          ),
                                        ),
                                      )
                                    else
                                      Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          SizedBox(
                                            width: 100,
                                            height: 38,
                                            child: ElevatedButton(
                                              onPressed: _handleWatchButtonPressed,
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: Colors.black,
                                                shape: RoundedRectangleBorder(
                                                  borderRadius: BorderRadius.circular(2),
                                                ),
                                                side: const BorderSide(
                                                  color: Color(0xFFE09321),
                                                ),
                                              ),
                                              child: FittedBox(
                                                fit: BoxFit.scaleDown,
                                                child: Text(
                                                  isWatching ? "-Watch" : "+Watch",
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 5),
                                          SizedBox(
                                            width: 100,
                                            height: 38,
                                            child: ElevatedButton(
                                              onPressed: () {
                                                Navigator.push(
                                                  context,
                                                  MaterialPageRoute(
                                                    builder: (context) => NewMessageScreen(
                                                      recipient: sanitizedUsername,
                                                    ),
                                                  ),
                                                );
                                              },
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: const Color(0xFFE09321),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius: BorderRadius.circular(2),
                                                ),
                                              ),
                                              child: const FittedBox(
                                                fit: BoxFit.scaleDown,
                                                child: Text(
                                                  "Note",
                                                  style: TextStyle(
                                                    color: Colors.white,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                  ],
                                ),
                              ),
                            ),
                            const Divider(
                              height: 3.0,
                              color: Colors.black,
                              thickness: 3.0,
                            ),
                            const Divider(
                              height: 4.0,
                              color: Color(0xFF111111),
                              thickness: 4.0,
                            ),
                          ],
                        ),

                        MediaQuery(
                          data: MediaQuery.of(context)
                              .copyWith(textScaleFactor: 1.0),
                          child: Padding(
                            padding:
                            const EdgeInsets.only(top: 8.0),
                            child: Table(
                              columnWidths: const {
                                0: FlexColumnWidth(1),
                                1: FlexColumnWidth(1),
                                2: FlexColumnWidth(1),
                                3: FlexColumnWidth(1),
                              },
                              defaultVerticalAlignment:
                              TableCellVerticalAlignment.middle,
                              children: [
                                TableRow(
                                  children: [
                                    ProfileStatItem(count: views?.toString() ?? '0', label: 'Views'),
                                    ProfileStatItem(count: submissions?.toString() ?? '0', label: 'Submissions'),
                                    ProfileStatItem(count: favs?.toString() ?? '0', label: 'Favs'),
                                    ProfileStatItem(count: recentWatchersCount.toString(), label: 'Watched'),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  pinned: false,
                ),

                SliverPersistentHeader(
                  pinned: true,
                  delegate: NavigationSliderSliverDelegate(
                    minHeight: navigationSliderHeight + 1.0,
                    maxHeight: navigationSliderHeight + 1.0,
                    child: NavigationSlider(
                      sections: ProfileSection.values,
                      tabController: _tabController,
                      getTabTitle: _getTabTitle,
                      getIconForSection: _getIconForSection,
                      onTabTapped: (index, isAlreadySelected) {
                        if (isAlreadySelected) {
                          _scrollController.animateTo(
                            0.0,
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeOut,
                          );
                        }
                      },
                    ),
                  ),
                ),
              ],

              body: TabBarView(
                controller: _tabController,
                children: ProfileSection.values.map((section) {
                  switch (section) {
                    case ProfileSection.Home:
                      return _buildHomeSection();
                    case ProfileSection.Gallery:
                      return _buildGallerySection();
                    case ProfileSection.Scraps:
                      return _buildScrapsSection();
                    case ProfileSection.Favs:
                      return _buildFavoritesSection();
                    case ProfileSection.Journals:
                      return _buildJournalsSection();
                    default:
                      return Center(
                        child: Text(
                          'Unknown section',
                          style: TextStyle(color: Colors.white),
                        ),
                      );
                  }
                }).toList(),
              ),
            ),
          ),
        ),
            if (showLoadingIndicator)
              Container(
                color: Colors.black.withOpacity(1.0),
                child: const Center(
                  child: PulsatingLoadingIndicator(
                    size: 88.0,
                    assetPath: 'assets/icons/fathemed.png',
                  ),
                ),
              ),
          ],
        ),
        ),

        floatingActionButton: !isLoading
        ? AnimatedBuilder(
          animation: _tabController,
          builder: (context, child) {
            // bool showFab = _tabController.index != ProfileSection.Home.index;
            bool showFab = true;
            return AnimatedOpacity(
              opacity: showFab ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              child: Visibility(
                visible: showFab,
                maintainSize: false,
                maintainAnimation: false,
                maintainState: false,
                child: FloatingActionButton(
                  onPressed: () {
                    _scrollController.animateTo(
                      0.0,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOut,
                    );
                  },
                  backgroundColor: const Color(0xFFE09321),
                  child: const Icon(Icons.arrow_upward, color: Colors.white),
                  tooltip: 'Scroll to Top',
                ),
              ),
            );
          },
        )
            : null,
        floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,

      ),
    );
  }


  void _showEditProfileDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Colors.grey[850],
          title: const Text(
            'Edit Profile',
            style: TextStyle(color: Colors.white),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _launchURL('https://www.furaffinity.net/controls/profile/');
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(2),
                    ),
                    side: const BorderSide(color: Color(0xFFE09321)),
                  ),
                  child: const Text(
                    "Profile Info",
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ),
              const SizedBox(height: 8),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _launchURL('https://www.furaffinity.net/controls/profilebanner/');
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(2),
                    ),
                    side: const BorderSide(color: Color(0xFFE09321)),
                  ),
                  child: const Text(
                    "Profile Banner",
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ),
              const SizedBox(height: 8),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _launchURL('https://www.furaffinity.net/controls/contacts/');
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(2),
                    ),
                    side: const BorderSide(color: Color(0xFFE09321)),
                  ),
                  child: const Text(
                    "Contacts & Social Media",
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ),
              const SizedBox(height: 8),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _launchURL('https://www.furaffinity.net/controls/avatar/');
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(2),
                    ),
                    side: const BorderSide(color: Color(0xFFE09321)),
                  ),
                  child: const Text(
                    "Avatar Management",
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text(
                'Close',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildHomeSection() {
    return UserProfileHomeSection(
      hasRealUserProfile: hasRealUserProfile,
      userDescription: userDescription,
      webViewKey: _webViewKey,
      sanitizedUsername: sanitizedUsername,
      onDescriptionLongPressStart: _handleDescriptionLongPress,
      onWebViewLoaded: (loaded) {
        Future.delayed(Duration(milliseconds: 25), () {
          setState(() {
            _webViewLoaded = loaded;
          });
        });
      },
      featuredImageUrl: featuredImageUrl,
      featuredImageTitle: featuredImageTitle,
      featuredPostNumber: featuredPostNumber,
      onOpenPost: (context, imageUrl, uniqueNumber) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => OpenPost(
              imageUrl: imageUrl,
              uniqueNumber: uniqueNumber,
            ),
          ),
        );
      },
      userProfileImageUrl: userProfileImageUrl,
      userProfilePostNumber: userProfilePostNumber,
      userProfileTexts: userProfileTexts,
      isClassicMarkup: isClassicMarkup,
      acceptingTrades: acceptingTrades,
      acceptingCommissions: acceptingCommissions,
      onHandleFALink: _handleFALink,
      contactInformationLinks: contactInformationLinks,
      onLaunchUrl: _launchURL,
      recentWatchers: recentWatchers,
      recentWatchersCount: recentWatchersCount,
      recentlyWatched: recentlyWatched,
      recentlyWatchedCount: recentlyWatchedCount,
      shouts: shouts,
      isOwnProfile: isOwnProfile,
      currentShoutPage: currentShoutPage,
      totalShoutPages: totalShoutPages,
      isLoadingMoreShouts: isLoadingMoreShouts,
      onOpenPostShout: (context) async {
        final result = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => PostShoutScreen(username: sanitizedUsername),
          ),
        );
        if (result == true) {
          await _fetchUserProfile();
        }
      },
      onLoadMoreShouts: _loadMoreShouts,
      onConfirmDeleteShout: _confirmDeleteShout,
    );
  }






    /// Builds the Gallery section content.
  Widget _buildGallerySection() {
    return UserProfileGallerySection(
      nickname: widget.nickname,
      sanitizedUsername: sanitizedUsername,
      selectedFolderName: _selectedFolderName,
      selectedFolderUrl: _selectedFolderUrl,
      allFolders: _allFolders,
      onFolderSelected: _onFolderSelected,
      onFoldersParsed: _onFoldersParsed,
    );
  }






  /// Builds the Scraps section content.
  Widget _buildScrapsSection() {
    return UserProfileScrapsSection(sanitizedUsername: sanitizedUsername);
  }

  Widget _buildFavoritesSection() {
    return UserProfileFavoritesSection(sanitizedUsername: sanitizedUsername);
  }

  /// Builds the Journals section content.
  Widget _buildJournalsSection() {
    return UserProfileJournalsSection(
      sanitizedUsername: sanitizedUsername,
      isOwnProfile: isOwnProfile,
      journalsKey: _journalsKey,
      onCreateJournalPressed: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => CreateJournalScreen(),
          ),
        );
      },
    );
  }


}