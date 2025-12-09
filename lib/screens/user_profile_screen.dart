// user_profile_screen.dart
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:FANotifier/screens/shout_widget.dart';
import 'package:FANotifier/screens/user_description_webview.dart';
import 'package:auto_size_text/auto_size_text.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import 'package:flutter_html/flutter_html.dart' as html_pkg;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart';
import '../model/shout.dart';
import '../model/user_link.dart';
import '../network.dart';
import '../parsing_utils.dart';
import '../utils/html_tags_debug.dart';
import '../widgets/PulsatingLoadingIndicator.dart';
import 'user_profile_styles.dart';
import 'avatardownloadscreen.dart';
import 'create_journal.dart';
import 'new_message.dart';
import 'openjournal.dart';
import 'openpost.dart';
import 'profilegallery.dart';
import 'profilefavs.dart';
import 'profilescraps.dart';
import 'user_grid_section.dart';
import 'view_list_screen.dart';
import 'post_shout.dart';
import 'profilejournals.dart';
import 'package:html/dom.dart' as dom;
import '../utils/fa_link_handler.dart';
import '../utils/utils.dart';
import 'user_profile_api_service.dart';
import '../model/shout.dart';

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

  List<String> userIconBeforeUrls = [];

  String? profileDisplayName;
  String? profileUserNamePart;
  String? userIconBeforeUrl;
  String? userIconAfterUrl;

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

  String? profileBannerUrl;
  String? profileImageUrl;
  String? username;
  String? symbolUsername;
  String? userTitle;
  String? registrationDate;
  String? userDescription;
  List<String> keywords = [];
  List<Widget> sections = [];
  List<Shout> shouts = [];
  String sanitizedUsername = '';

  List<UserLink> recentWatchers = [];
  int recentWatchersCount = 0;

  List<UserLink> recentlyWatched = [];
  int recentlyWatchedCount = 0;

  int? views;
  int? submissions;
  int? favs;
  int? commentsEarned;
  int? commentsMade;
  int? journals;

  bool isWatching = false;
  String? watchLink;
  String? unwatchLink;
  String? unblockLink;
  String? blockLink;
  bool isBlocked = false;
  bool blockUsesPost = false;
  bool unblockUsesPost = false;

  String? featuredImageUrl;
  String? featuredImageTitle;
  String? featuredPostNumber;

  String? extractedUserProfilePostNumber;
  String? extractedUserProfileTexts;

  String? userProfileImageUrl;
  String? userProfilePostNumber;
  String? userProfileTexts;

  List<Map<String, String>> contactInformationLinks = [];
  bool isOwnProfile = false;
  bool isLoading = true;
  bool _webViewLoaded = false;
  String errorMessage = '';
  bool hasRealUserProfile = true;

  bool isClassicMarkup = false;
  bool acceptingTrades = false;
  bool acceptingCommissions = false;

  List<String> userIconAfterUrls = [];


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

  int currentShoutPage = 1;
  int totalShoutPages = 1;
  bool isLoadingMoreShouts = false;
  String? shoutPaginationKey;



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
    String? cookieA = await _secureStorage.read(key: 'fa_cookie_a');
    String? cookieB = await _secureStorage.read(key: 'fa_cookie_b');


    final sfwValue = _sfwEnabled ? '1' : '0';

    if (cookieA == null || cookieB == null) {
      print('No cookies found. User might not be logged in.');
      showAppSnackBar(context, 'Please log in to perform this action.', backgroundColor: Colors.red);
      return;
    }

    final fullUrl = 'https://www.furaffinity.net$urlPath';
    try {
      final response = await httpClient.get(
        Uri.parse(fullUrl),
        headers: {

          'Cookie': 'a=$cookieA; b=$cookieB; sfw=$sfwValue',
          'User-Agent': 'Mozilla/5.0 (compatible; YourApp/1.0)',
        },
      );

      if (response.statusCode == 200) {
        print('${shouldWatch ? 'Watch' : 'Unwatch'} action successful.');

        setState(() {
          isWatching = shouldWatch;
        });


        showAppSnackBar(context, '${shouldWatch ? 'Now watching $username' : 'Stopped watching $username'}', backgroundColor: Colors.green);
      } else {
        print('Failed to ${shouldWatch ? 'watch' : 'unwatch'}. Status code: ${response.statusCode}');

        showAppSnackBar(context, 'Failed to ${shouldWatch ? 'watch' : 'unwatch'} user.', backgroundColor: Colors.red);
      }
    } catch (e) {
      print('Error during ${shouldWatch ? 'watch' : 'unwatch'}: $e');

      showAppSnackBar(context, 'An error occurred while trying to ${shouldWatch ? 'watch' : 'unwatch'} user.', backgroundColor: Colors.red);
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
                style: {
                  "body": html_pkg.Style(
                    textAlign: TextAlign.left,
                    fontSize: html_pkg.FontSize(16),
                    color: Colors.white,
                  ),
                  "p": html_pkg.Style(
                    fontSize: html_pkg.FontSize(16),
                    color: Colors.white,
                  ),
                  "a": html_pkg.Style(
                    color: const Color(0xFFE09321),
                    textDecoration: TextDecoration.none,
                  ),
                  "img": html_pkg.Style(
                    width: html_pkg.Width(50.0),
                    height: html_pkg.Height(50.0),
                  ),
                  "strong": html_pkg.Style(
                    color: Colors.black,
                    fontWeight: FontWeight.bold,
                  ),
                  "u": html_pkg.Style(
                    color: Colors.black,
                  ),
                  ".bbcode_right": html_pkg.Style(
                    textAlign: TextAlign.right,
                  ),
                  ".bbcode_right .bbcode_sup, .bbcode_right sup": html_pkg.Style(
                    textAlign: TextAlign.right,
                  ),
                  ".bbcode_center": html_pkg.Style(
                    textAlign: TextAlign.center,
                  ),
                  ".bbcode_left": html_pkg.Style(
                    textAlign: TextAlign.left,
                  ),
                  "hr": html_pkg.Style(
                    padding: HtmlPaddings.symmetric(vertical: 8),
                    margin: Margins.symmetric(vertical: 8),
                    height: html_pkg.Height(1),
                  ),
                },
                extensions: [
                  // Extension for <i> tags and FA emoji images.
                  html_pkg.TagExtension(
                    tagsToExtend: {"i"},
                    builder: (html_pkg.ExtensionContext context) {
                      final classAttr = context.attributes['class'];
                      if (classAttr == 'bbcode bbcode_i') {
                        return Text(
                          context.styledElement?.element?.text ?? "",
                          style: const TextStyle(
                            fontStyle: FontStyle.italic,
                            color: Colors.white,
                          ),
                        );
                      }
                      switch (classAttr) {
                        case 'smilie tongue':
                          return Image.asset('assets/emojis/tongue.png', width: 20, height: 20);
                        case 'smilie evil':
                          return Image.asset('assets/emojis/evil.png', width: 20, height: 20);
                        case 'smilie lmao':
                          return Image.asset('assets/emojis/lmao.png', width: 20, height: 20);
                        case 'smilie gift':
                          return Image.asset('assets/emojis/gift.png', width: 20, height: 20);
                        case 'smilie derp':
                          return Image.asset('assets/emojis/derp.png', width: 20, height: 20);
                        case 'smilie teeth':
                          return Image.asset('assets/emojis/teeth.png', width: 20, height: 20);
                        case 'smilie cool':
                          return Image.asset('assets/emojis/cool.png', width: 20, height: 20);
                        case 'smilie huh':
                          return Image.asset('assets/emojis/huh.png', width: 20, height: 20);
                        case 'smilie cd':
                          return Image.asset('assets/emojis/cd.png', width: 20, height: 20);
                        case 'smilie coffee':
                          return Image.asset('assets/emojis/coffee.png', width: 20, height: 20);
                        case 'smilie sarcastic':
                          return Image.asset('assets/emojis/sarcastic.png', width: 20, height: 20);
                        case 'smilie veryhappy':
                          return Image.asset('assets/emojis/veryhappy.png', width: 20, height: 20);
                        case 'smilie wink':
                          return Image.asset('assets/emojis/wink.png', width: 20, height: 20);
                        case 'smilie whatever':
                          return Image.asset('assets/emojis/whatever.png', width: 20, height: 20);
                        case 'smilie crying':
                          return Image.asset('assets/emojis/crying.png', width: 20, height: 20);
                        case 'smilie love':
                          return Image.asset('assets/emojis/love.png', width: 20, height: 20);
                        case 'smilie serious':
                          return Image.asset('assets/emojis/serious.png', width: 20, height: 20);
                        case 'smilie yelling':
                          return Image.asset('assets/emojis/yelling.png', width: 20, height: 20);
                        case 'smilie oooh':
                          return Image.asset('assets/emojis/oooh.png', width: 20, height: 20);
                        case 'smilie angel':
                          return Image.asset('assets/emojis/angel.png', width: 20, height: 20);
                        case 'smilie dunno':
                          return Image.asset('assets/emojis/dunno.png', width: 20, height: 20);
                        case 'smilie nerd':
                          return Image.asset('assets/emojis/nerd.png', width: 20, height: 20);
                        case 'smilie sad':
                          return Image.asset('assets/emojis/sad.png', width: 20, height: 20);
                        case 'smilie zipped':
                          return Image.asset('assets/emojis/zipped.png', width: 20, height: 20);
                        case 'smilie smile':
                          return Image.asset('assets/emojis/smile.png', width: 20, height: 20);
                        case 'smilie badhairday':
                          return Image.asset('assets/emojis/badhairday.png', width: 20, height: 20);
                        case 'smilie embarrassed':
                          return Image.asset('assets/emojis/embarrassed.png', width: 20, height: 20);
                        case 'smilie note':
                          return Image.asset('assets/emojis/note.png', width: 20, height: 20);
                        case 'smilie sleepy':
                          return Image.asset('assets/emojis/sleepy.png', width: 20, height: 20);
                        default:
                          return const SizedBox.shrink();
                      }
                    },
                  ),
                  // Extension for <img> tags.
                  html_pkg.TagExtension(
                    tagsToExtend: {"img"},
                    builder: (html_pkg.ExtensionContext context) {
                      final src = context.attributes['src'];
                      if (src == null) {
                        return const SizedBox.shrink();
                      }
                      final resolvedUrl = src.startsWith('//') ? 'https:$src' : src;
                      return CachedNetworkImage(
                        imageUrl: resolvedUrl,
                        width: 50,
                        height: 50,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => const SizedBox(
                          width: 50,
                          height: 50,
                          child: CircularProgressIndicator(),
                        ),
                        errorWidget: (context, url, error) => Image.asset(
                          'assets/images/defaultpic.gif',
                          width: 50,
                          height: 50,
                          fit: BoxFit.cover,
                        ),
                      );
                    },
                  ),

                ],
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
    String? cookieA = await _secureStorage.read(key: 'fa_cookie_a');
    String? cookieB = await _secureStorage.read(key: 'fa_cookie_b');


    final sfwValue = _sfwEnabled ? '1' : '0';

    if (cookieA == null || cookieB == null) {
      showAppSnackBar(context, "Please log in to perform this action.", backgroundColor: Colors.red);
      return;
    }

    final url = "https://www.furaffinity.net/controls/shouts/";
    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Cookie': 'a=$cookieA; b=$cookieB; sfw=$sfwValue',
          'Content-Type': 'application/x-www-form-urlencoded',
          'User-Agent': 'Mozilla/5.0 (compatible; YourApp/1.0)',
          'Referer': 'https://www.furaffinity.net/controls/shouts/',
        },
        body: {
          'do': 'update',
          'shouts[]': shout.id,
        },
      );
      final payload = Uri(queryParameters: {'do': 'update', 'shouts[]': shout.id}).query;


      if (response.statusCode == 302) {

        showAppSnackBar(context, "Shout deleted.", backgroundColor: Colors.green);

        await _fetchUserProfile();
      } else {
        showAppSnackBar(context, "Failed to delete shout.", backgroundColor: Colors.red);
      }
    } catch (e) {
      showAppSnackBar(context, "Error: $e", backgroundColor: Colors.red);
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

      // DEBUG LOGGING
      print("=== PARSED DATA DEBUG ===");
      print("symbolUsername: ${parsed.symbolUsername}");
      print("userTitle: ${parsed.userTitle}");
      print("registrationDate: ${parsed.registrationDate}");
      print("featuredImageUrl: ${parsed.featuredImageUrl}");
      print("featuredImageTitle: ${parsed.featuredImageTitle}");
      print("featuredPostNumber: ${parsed.featuredPostNumber}");
      print("userProfileTexts: ${parsed.userProfileTexts?.substring(0, min(100, parsed.userProfileTexts?.length ?? 0))}");
      print("recentWatchersCount: ${parsed.recentWatchersCount}");
      print("recentWatchers.length: ${parsed.recentWatchers.length}");
      print("recentlyWatchedCount: ${parsed.recentlyWatchedCount}");
      print("recentlyWatched.length: ${parsed.recentlyWatched.length}");
      print("hasRealUserProfile: ${parsed.hasRealUserProfile}");
      print("========================");

      setState(() {
        profileBannerUrl = parsed.profileBannerUrl;
        profileImageUrl = parsed.profileImageUrl;
        profileDisplayName = parsed.profileDisplayName;
        profileUserNamePart = parsed.profileUserNamePart;
        symbolUsername = parsed.symbolUsername;
        username = parsed.username;
        userTitle = parsed.userTitle;
        registrationDate = parsed.registrationDate;
        userDescription = parsed.userDescription;
        hasRealUserProfile = parsed.hasRealUserProfile;
        isClassicMarkup = parsed.isClassicMarkup;
        acceptingTrades = parsed.acceptingTrades;
        acceptingCommissions = parsed.acceptingCommissions;
        userIconBeforeUrls = parsed.userIconBeforeUrls;
        userIconAfterUrls = parsed.userIconAfterUrls;
        views = parsed.views;
        submissions = parsed.submissions;
        favs = parsed.favs;
        commentsEarned = parsed.commentsEarned;
        commentsMade = parsed.commentsMade;
        journals = parsed.journals;
        featuredImageUrl = parsed.featuredImageUrl;
        featuredImageTitle = parsed.featuredImageTitle;
        featuredPostNumber = parsed.featuredPostNumber;
        userProfileImageUrl = parsed.userProfileImageUrl;
        userProfilePostNumber = parsed.userProfilePostNumber;
        userProfileTexts = parsed.userProfileTexts;
        contactInformationLinks = parsed.contactInformationLinks;
        recentWatchers = parsed.recentWatchers;
        recentWatchersCount = parsed.recentWatchersCount;
        recentlyWatched = parsed.recentlyWatched;
        recentlyWatchedCount = parsed.recentlyWatchedCount;
        shouts = parsed.shouts;
        shoutPaginationKey = parsed.shoutPaginationKey;
        currentShoutPage = parsed.currentShoutPage;
        totalShoutPages = parsed.totalShoutPages;
        watchLink = parsed.watchLink;
        unwatchLink = parsed.unwatchLink;
        blockLink = parsed.blockLink;
        unblockLink = parsed.unblockLink;
        blockUsesPost = parsed.blockUsesPost;
        unblockUsesPost = parsed.unblockUsesPost;
        isWatching = parsed.isWatching;
        isBlocked = parsed.isBlocked;
        isOwnProfile = parsed.isOwnProfile;
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
      final payload = await _api.fetchShoutPage(
        sanitizedUsername: sanitizedUsername,
        shoutPaginationKey: shoutPaginationKey,
        nextPage: nextPage,
        sfwEnabled: _sfwEnabled,
      );

      if (payload == null) {
        print("Missing shout pagination key; cannot load more shouts.");
        return;
      }

      final decodedBody = payload.body;

      final newShouts = _api.parseAdditionalShoutsJson(
        decodedBody,
        shouts.map((s) => s.id).toSet(),
      );

      setState(() {
        shouts.addAll(newShouts);
        currentShoutPage = payload.nextPage;
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

  // Small stat item helper
  Widget _buildStatItem(String count, String label) {
    return Column(
      children: [
        Text(
          count,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 16.0,
          ),
        ),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 12.0),
        ),
      ],
    );
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


  Widget _buildUserProfileSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1F1F1F),
          borderRadius: BorderRadius.circular(8.0),
        ),
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'User Profile',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 8.0),
            if (userProfileImageUrl != null)
              GestureDetector(
                onTap: () {
                  if (userProfilePostNumber != null) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => OpenPost(
                          imageUrl: userProfileImageUrl!,
                          uniqueNumber: userProfilePostNumber!,
                        ),
                      ),
                    );
                  }
                },
                child: Center(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8.0),
                    child: CachedNetworkImage(
                      imageUrl: userProfileImageUrl!,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => const SizedBox(
                        height: 200,
                        child: Center(child: CircularProgressIndicator()),
                      ),
                      errorWidget: (context, url, error) => const SizedBox(),
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 8.0),

            if (isClassicMarkup)
              Center(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      "Accepting Trades: ${acceptingTrades ? "Yes" : "No"}",
                      style: const TextStyle(color: Colors.white),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "Accepting Commissions: ${acceptingCommissions ? "Yes" : "No"}",
                      style: const TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 8.0),
            html_pkg.Html(
              data: userProfileTexts!,
              style: userProfileHtmlStylesCompact(),
              extensions: buildUserProfileBBCodeExtensions(),
              onLinkTap: (url, _, __) => _handleFALink(context, url!),
            ),
          ],
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

  Widget _buildContactInformationSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1F1F1F),
          borderRadius: BorderRadius.circular(8.0),
        ),
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Contact Information',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 8.0),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: contactInformationLinks.map((contact) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4.0),
                  child: Row(
                    children: [
                      Text(
                        '${contact['label']}: ',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16.0,
                        ),
                      ),
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            final href = contact['href'];
                            if (href != null && href.isNotEmpty) {
                              _launchURL(href);
                            }
                          },
                          child: Text(
                            contact['value'] ?? '',
                            style: const TextStyle(
                              color: Color(0xFFE09321),
                              fontSize: 16.0,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShoutsSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1F1F1F), Colors.black],
            stops: [0.0, 0.06],
          ),
          borderRadius: BorderRadius.circular(8.0),
        ),
        padding: const EdgeInsets.only(top: 16.0, bottom: 64.0, right: 0.0, left: 0.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Text(
              'Shouts',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 0.0),
            Padding(
              padding: const EdgeInsets.fromLTRB(12.0, 12.0, 12.0, 12.0),
              child: GestureDetector(
                onTap: () async {
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
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
                  decoration: BoxDecoration(
                    color: const Color(0xFF232323),
                    borderRadius: BorderRadius.circular(10.0),
                  ),
                  child: Row(
                    children: const [
                      Expanded(
                        child: Text(
                          'Type here to leave a shout!',
                          style: TextStyle(color: Colors.white54),
                        ),
                      ),
                      Icon(Icons.send, color: Colors.white54),
                    ],
                  ),
                ),
              ),
            ),
            if (shouts.isEmpty)
              const Text(
                'No shouts yet. Be the first to shout!',
                style: TextStyle(color: Colors.white70),
              )
            else
              Column(
                children: [
                  ListView.separated(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: shouts.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 8.0),
                    itemBuilder: (context, index) {
                      final shout = shouts[index];
                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onLongPress: () async {
                          final plainText = html_parser.parse(shout.text).body?.text ?? shout.text;
                          final action = await showDialog<String>(
                            context: context,
                            builder: (context) {
                              final maxHeight = MediaQuery.of(context).size.height * 0.6;
                              return AlertDialog(
                                scrollable: true,
                                titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                                title: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(4.0),
                                      child: Image.network(
                                        shout.avatarUrl,
                                        width: 40,
                                        height: 40,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            shout.username,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          Text(
                                            '${shout.symbol} ${shout.profileNickname}',
                                            style: const TextStyle(
                                              color: Color(0xFFE09321),
                                              fontSize: 14,
                                              fontWeight: FontWeight.normal,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                content: ConstrainedBox(
                                  constraints: BoxConstraints(maxHeight: maxHeight),
                                  child: SingleChildScrollView(
                                    child: Text(
                                      plainText,
                                      style: const TextStyle(color: Colors.white),
                                    ),
                                  ),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(context, 'copy'),
                                    child: const Text('Copy text'),
                                  ),
                                  if (isOwnProfile)
                                    TextButton(
                                      onPressed: () => Navigator.pop(context, 'delete'),
                                      style: TextButton.styleFrom(foregroundColor: Colors.red),
                                      child: const Text("Delete"),
                                    ),
                                ],
                              );
                            },
                          );
                          if (action == 'copy') {
                            await Clipboard.setData(ClipboardData(text: plainText));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Shout text copied'),
                                backgroundColor: Colors.green,
                              ),
                            );
                          } else if (action == 'delete') {
                            _confirmDeleteShout(index, shout);
                          }
                        },
                        child: ShoutWidget(
                          shout: shout,
                          onDelete: () {
                            if (isOwnProfile) {
                              _confirmDeleteShout(index, shout);
                            }
                          },
                        ),
                      );
                    },
                  ),
                  if (currentShoutPage < totalShoutPages)
                    Padding(
                      padding: const EdgeInsets.only(top: 16.0),
                      child: isLoadingMoreShouts
                          ? const CircularProgressIndicator(
                              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFE09321)),
                            )
                          : ElevatedButton(
                              onPressed: _loadMoreShouts,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFE09321),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8.0),
                                ),
                              ),
                              child: const Text(
                                'Load More',
                                style: TextStyle(
                                  fontSize: 16.0,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeaturedSubmission() {
    if (featuredImageUrl == null || featuredImageTitle == null || featuredPostNumber == null) {
      return const SizedBox();
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1F1F1F),
          borderRadius: BorderRadius.circular(8.0),
        ),
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Featured Submission',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 8.0),
            GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => OpenPost(
                      imageUrl: featuredImageUrl!,
                      uniqueNumber: featuredPostNumber!,
                    ),
                  ),
                );
              },
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8.0),
                child: CachedNetworkImage(
                  imageUrl: featuredImageUrl!,
                  fit: BoxFit.contain,
                  placeholder: (context, url) => const SizedBox(
                    height: 200,
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  errorWidget: (context, url, error) => const SizedBox(
                    height: 200,
                    child: Center(
                      child: Icon(Icons.broken_image, size: 100, color: Colors.redAccent),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8.0),
            Text(
              featuredImageTitle!,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white),
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
    print('==================== [_sendBlockUnblockRequest] START ====================');
    print('[_sendBlockUnblockRequest] Raw args:');
    print('  urlOrPath: $urlOrPath');
    print('  keyValue: $keyValue');
    print('  shouldBlock: $shouldBlock');
    print('  usePost: $usePost');

    String? cookieA = await _secureStorage.read(key: 'fa_cookie_a');
    String? cookieB = await _secureStorage.read(key: 'fa_cookie_b');
    final sfwValue = _sfwEnabled ? '1' : '0';

    print('[_sendBlockUnblockRequest] Cookies / SFW state:');
    print('  cookieA is null: ${cookieA == null}');
    print('  cookieB is null: ${cookieB == null}');
    if (cookieA != null) {
      print('  cookieA length: ${cookieA.length}');
    }
    if (cookieB != null) {
      print('  cookieB length: ${cookieB.length}');
    }
    print('  _sfwEnabled: $_sfwEnabled');
    print('  sfwValue: $sfwValue');

    if (cookieA == null || cookieB == null) {
      print('[_sendBlockUnblockRequest] ERROR: No cookies found. Aborting.');
      showAppSnackBar(
        context,
        'Please log in to perform this action.',
        backgroundColor: Colors.red,
      );
      print('==================== [_sendBlockUnblockRequest] END (no cookies) ====================');
      return;
    }

    final fullUrl = urlOrPath.startsWith('http')
        ? urlOrPath
        : 'https://www.furaffinity.net$urlOrPath';
    print('[_sendBlockUnblockRequest] fullUrl (after prefix check): $fullUrl');

    final uri = Uri.parse(fullUrl);
    print('[_sendBlockUnblockRequest] Parsed uri: $uri');
    print('[_sendBlockUnblockRequest] uri.scheme: ${uri.scheme}');
    print('[_sendBlockUnblockRequest] uri.host: ${uri.host}');
    print('[_sendBlockUnblockRequest] uri.path: ${uri.path}');
    print('[_sendBlockUnblockRequest] uri.query: ${uri.query}');
    print('[_sendBlockUnblockRequest] uri.pathSegments: ${uri.pathSegments}');

    final targetUrl = uri.toString();
    print('[_sendBlockUnblockRequest] targetUrl: $targetUrl');

    String refererUsername = sanitizedUsername;
    print('[_sendBlockUnblockRequest] Initial refererUsername (sanitizedUsername): $refererUsername');

    final segments = uri.pathSegments;
    print('[_sendBlockUnblockRequest] segments length: ${segments.length}');
    if (segments.isNotEmpty) {
      for (int i = 0; i < segments.length; i++) {
        print('[_sendBlockUnblockRequest] segments[$i]: ${segments[i]}');
      }
    }

    if (segments.length >= 2 && (segments.first == 'block' || segments.first == 'unblock')) {
      final candidateUsername = segments[1];
      print('[_sendBlockUnblockRequest] Detected block/unblock path, candidate username from URL: $candidateUsername');
      refererUsername = candidateUsername;
    } else {
      print('[_sendBlockUnblockRequest] Did NOT detect /block/username or /unblock/username pattern. Keeping sanitizedUsername.');
    }

    print('[_sendBlockUnblockRequest] Final refererUsername: $refererUsername');

    try {
      final uriTarget = Uri.parse(targetUrl);
      print('[_sendBlockUnblockRequest] uriTarget: $uriTarget');

      final headers = <String, String>{
        'Cookie': 'a=$cookieA; b=$cookieB; sfw=$sfwValue',
        'User-Agent': 'Mozilla/5.0 (compatible; YourApp/1.0)',
        'Referer': 'https://www.furaffinity.net/user/$refererUsername/',
      };

      print('[_sendBlockUnblockRequest] Request headers:');
      headers.forEach((k, v) {
        if (k.toLowerCase() == 'cookie') {
          print('  $k: ${v.substring(0, v.length.clamp(0, 200))}${v.length > 200 ? '... (truncated)' : ''}');
        } else {
          print('  $k: $v');
        }
      });

      late http.Response response;

      if (usePost) {
        print('[_sendBlockUnblockRequest] Performing POST request...');
        print('[_sendBlockUnblockRequest] POST body: { key: $keyValue }');

        response = await http.post(
          uriTarget,
          headers: {
            ...headers,
            'Content-Type': 'application/x-www-form-urlencoded',
          },
          body: {'key': keyValue},
        );
      } else {
        print('[_sendBlockUnblockRequest] Performing GET request...');
        response = await http.get(uriTarget, headers: headers);
      }

      print('[_sendBlockUnblockRequest] Response received:');
      print('  statusCode: ${response.statusCode}');
      print('  isRedirect (3xx): ${response.statusCode >= 300 && response.statusCode < 400}');
      print('  response.headers:');
      response.headers.forEach((k, v) {
        print('    $k: $v');
      });

      final previewLength = min(500, response.body.length);
      final previewBody = response.body.substring(0, previewLength);
      print('[_sendBlockUnblockRequest] Response body preview ($previewLength chars):');
      print(previewBody);

      if (response.statusCode == 302 || response.statusCode == 200) {
        print('[_sendBlockUnblockRequest] ${shouldBlock ? 'Block' : 'Unblock'} action SUCCESS.');
        await _fetchUserProfile();
        showAppSnackBar(
          context,
          shouldBlock ? 'Author blocked' : 'Author unblocked',
          backgroundColor: Colors.green,
        );
      } else {
        print('[_sendBlockUnblockRequest] ERROR: Failed to ${shouldBlock ? 'block' : 'unblock'}. Status code: ${response.statusCode}');
        showAppSnackBar(
          context,
          'Failed to ${shouldBlock ? 'block' : 'unblock'} author.',
          backgroundColor: Colors.red,
        );
      }
    } catch (e, st) {
      print('[_sendBlockUnblockRequest] EXCEPTION during ${shouldBlock ? 'block' : 'unblock'}: $e');
      print('[_sendBlockUnblockRequest] Stacktrace: $st');
      showAppSnackBar(
        context,
        'An error occurred while trying to ${shouldBlock ? 'block' : 'unblock'} author.',
        backgroundColor: Colors.red,
      );
    }

    print('==================== [_sendBlockUnblockRequest] END ====================');
  }



  Future<void> _handleBlockUnblock() async {
    print('==================== [_handleBlockUnblock] START ====================');
    print('[_handleBlockUnblock] isBlocked: $isBlocked');
    print('[_handleBlockUnblock] blockLink: $blockLink');
    print('[_handleBlockUnblock] unblockLink: $unblockLink');
    print('[_handleBlockUnblock] blockUsesPost: $blockUsesPost');
    print('[_handleBlockUnblock] unblockUsesPost: $unblockUsesPost');

    if (isBlocked) {
      print('[_handleBlockUnblock] Entered UNBLOCK branch');

      if (unblockLink == null) {
        print('[_handleBlockUnblock] ERROR: unblockLink is null');
        showAppSnackBar(
          context,
          'Cannot unblock author at this time.',
          backgroundColor: Colors.red,
        );
        print('==================== [_handleBlockUnblock] END (unblockLink null) ====================');
        return;
      }

      print('[_handleBlockUnblock] Raw unblockLink: $unblockLink');
      final unblockUri = Uri.parse(unblockLink!);
      print('[_handleBlockUnblock] Parsed unblockUri: $unblockUri');
      print('[_handleBlockUnblock] unblockUri.scheme: ${unblockUri.scheme}');
      print('[_handleBlockUnblock] unblockUri.host: ${unblockUri.host}');
      print('[_handleBlockUnblock] unblockUri.path: ${unblockUri.path}');
      print('[_handleBlockUnblock] unblockUri.query: ${unblockUri.query}');
      print('[_handleBlockUnblock] unblockUri.pathSegments: ${unblockUri.pathSegments}');

      final key = unblockUri.queryParameters['key'];
      print('[_handleBlockUnblock] Extracted unblock key: $key');

      if (key == null || key.isEmpty) {
        print('[_handleBlockUnblock] ERROR: Unblock key is null or empty');
        showAppSnackBar(
          context,
          'Cannot unblock author at this time.',
          backgroundColor: Colors.red,
        );
        print('==================== [_handleBlockUnblock] END (unblock key invalid) ====================');
        return;
      }

      print('[_handleBlockUnblock] Calling _sendBlockUnblockRequest for UNBLOCK');
      await _sendBlockUnblockRequest(
        unblockLink!,
        key,
        shouldBlock: false,
        usePost: unblockUsesPost,
      );
      print('[_handleBlockUnblock] Returned from _sendBlockUnblockRequest (UNBLOCK)');
    } else {
      print('[_handleBlockUnblock] Entered BLOCK branch');

      if (blockLink == null) {
        print('[_handleBlockUnblock] ERROR: blockLink is null');
        showAppSnackBar(
          context,
          'Cannot block author at this time.',
          backgroundColor: Colors.red,
        );
        print('==================== [_handleBlockUnblock] END (blockLink null) ====================');
        return;
      }

      print('[_handleBlockUnblock] Raw blockLink: $blockLink');
      final blockUri = Uri.parse(blockLink!);
      print('[_handleBlockUnblock] Parsed blockUri: $blockUri');
      print('[_handleBlockUnblock] blockUri.scheme: ${blockUri.scheme}');
      print('[_handleBlockUnblock] blockUri.host: ${blockUri.host}');
      print('[_handleBlockUnblock] blockUri.path: ${blockUri.path}');
      print('[_handleBlockUnblock] blockUri.query: ${blockUri.query}');
      print('[_handleBlockUnblock] blockUri.pathSegments: ${blockUri.pathSegments}');

      final key = blockUri.queryParameters['key'];
      print('[_handleBlockUnblock] Extracted block key: $key');

      if (key == null || key.isEmpty) {
        print('[_handleBlockUnblock] ERROR: Block key is null or empty');
        showAppSnackBar(
          context,
          'Cannot block author at this time.',
          backgroundColor: Colors.red,
        );
        print('==================== [_handleBlockUnblock] END (block key invalid) ====================');
        return;
      }

      print('[_handleBlockUnblock] Calling _sendBlockUnblockRequest for BLOCK');
      await _sendBlockUnblockRequest(
        blockLink!,
        key,
        shouldBlock: true,
        usePost: blockUsesPost,
      );
      print('[_handleBlockUnblock] Returned from _sendBlockUnblockRequest (BLOCK)');
    }

    print('==================== [_handleBlockUnblock] END ====================');
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
                                    _buildStatItem(views?.toString() ?? '0', 'Views'),
                                    _buildStatItem(submissions?.toString() ?? '0', 'Submissions'),
                                    _buildStatItem(favs?.toString() ?? '0', 'Favs'),
                                    _buildStatItem(recentWatchersCount.toString(), 'Watched'),
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
    return ListView(
      padding: const EdgeInsets.only(left: 8.0, right: 8.0, bottom: 8.0),
      children: [
        if (hasRealUserProfile && userDescription != null && userDescription!.trim().isNotEmpty)
          GestureDetector(
            onLongPressStart: _handleDescriptionLongPress,
            child: UserDescriptionWebView(
              key: _webViewKey,
              sanitizedUsername: sanitizedUsername,
              initialHtml: userDescription,
              forceHybridComposition: false,
              onWebViewLoaded: (loaded) {
                Future.delayed(Duration(milliseconds: 25), () {
                  setState(() {
                    _webViewLoaded = loaded;
                  });
                });
              },
            ),
          ),
        const SizedBox(height: 16.0),
        if (featuredImageUrl != null && featuredImageUrl!.isNotEmpty &&
            featuredImageTitle != null && featuredImageTitle!.isNotEmpty &&
            featuredPostNumber != null && featuredPostNumber!.isNotEmpty)
          ...[
            _buildFeaturedSubmission(),
            const SizedBox(height: 8.0),
          ],
        if (hasRealUserProfile &&
            userProfileTexts != null &&
            userProfileTexts!.isNotEmpty &&
            userProfileTexts != 'No additional profile information.')
          _buildUserProfileSection(),
        const SizedBox(height: 8.0),
        if (contactInformationLinks.isNotEmpty) _buildContactInformationSection(),
        const SizedBox(height: 8.0),
        if (recentWatchers.isNotEmpty || recentWatchersCount > 0)
          UserGridSection(
            title: 'Recent Watchers',
            viewListText: 'Watched by $recentWatchersCount',
            users: recentWatchers,
            sanitizedUsername: sanitizedUsername,
          ),
        const SizedBox(height: 8.0),
        if (recentlyWatched.isNotEmpty || recentlyWatchedCount > 0)
          UserGridSection(
            title: 'Recently Watched',
            viewListText: 'Watching $recentlyWatchedCount',
            users: recentlyWatched,
            sanitizedUsername: sanitizedUsername,
          ),
        const SizedBox(height: 8.0),
        _buildShoutsSection(),
        const SizedBox(height: 8.0),
      ],
    );
  }






    /// Builds the Gallery section content.
  Widget _buildGallerySection() {

    final galleryUrl = _selectedFolderUrl.isNotEmpty
        ? _selectedFolderUrl
        : 'https://www.furaffinity.net/gallery/$sanitizedUsername/';


    return CustomScrollView(
      slivers: [

        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Gallery',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                PopupMenuButton<FaFolder>(
                  onSelected: (FaFolder folder) {

                    setState(() {
                      _selectedFolderName = folder.name;
                      _selectedFolderUrl = folder.url;
                    });

                  },
                  itemBuilder: (context) {
                    return _allFolders.map((folder) {
                      return PopupMenuItem<FaFolder>(
                        value: folder,
                        child: Text(folder.name),
                      );
                    }).toList();
                  },
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE09321),
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: const Color(0xFFE09321),
                      disabledForegroundColor: Colors.white,
                    ),
                    onPressed: null,
                    child: Text(
                      'Folder: $_selectedFolderName',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        ProfileGallerySliver(
          username: widget.nickname,
          selectedFolderUrl: galleryUrl,
          onFoldersParsed: _onFoldersParsed,
        ),
      ],
    );
  }






  /// Builds the Scraps section content.
  Widget _buildScrapsSection() {
    return CustomScrollView(
      slivers: [

        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Scraps',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ],
            ),
          ),
        ),

        ProfileScrapsSliver(username: sanitizedUsername),
      ],
    );
  }

  Widget _buildFavoritesSection() {
    return CustomScrollView(
      slivers: [

        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Favs',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ],
            ),
          ),
        ),

        ProfileFavsSliver(username: sanitizedUsername),
      ],
    );
  }

  /// Builds the Journals section content.
  Widget _buildJournalsSection() {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Journals',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                ),

                if (isOwnProfile)
                  ElevatedButton(
                    onPressed: () {

                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => CreateJournalScreen(),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Color(0xFFE09321),
                    ),
                    child: const Text(
                      'Create Journal',
                      style: TextStyle(
                        color: Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),

        ProfileJournals(
          key: _journalsKey,
          username: sanitizedUsername,
        ),
      ],
    );
  }


}

class FixedSliverPersistentHeaderDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;
  final double height;

  FixedSliverPersistentHeaderDelegate({
    required this.child,
    required this.height,
  });

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return SizedBox.expand(child: child);
  }

  @override
  bool shouldRebuild(covariant FixedSliverPersistentHeaderDelegate oldDelegate) {
    return oldDelegate.child != child || oldDelegate.height != height;
  }
}



class NavigationSliderSliverDelegate extends SliverPersistentHeaderDelegate {
  final double minHeight;
  final double maxHeight;
  final Widget child;

  NavigationSliderSliverDelegate({
    required this.minHeight,
    required this.maxHeight,
    required this.child,
  });

  @override
  double get minExtent => minHeight;

  @override
  double get maxExtent => max(maxHeight, minHeight);

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return SizedBox.expand(child: child);
  }

  @override
  bool shouldRebuild(NavigationSliderSliverDelegate oldDelegate) {
    return false;
  }

}


class CollapsibleSliverPersistentHeader extends SliverPersistentHeaderDelegate {
  final double minHeight;
  final double maxHeight;
  final Widget child;

  CollapsibleSliverPersistentHeader({
    required this.minHeight,
    required this.maxHeight,
    required this.child,
  });

  @override
  double get minExtent => minHeight;

  @override
  double get maxExtent => max(maxHeight, minHeight);

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    // Calculate the current height based on shrinkOffset
    double currentHeight = maxExtent - shrinkOffset;
    if (currentHeight < minExtent) {
      currentHeight = minExtent;
    }

    // Calculate opacity based on shrinkOffset
    double opacity = (currentHeight - minExtent) / (maxExtent - minExtent);
    if (opacity < 0.0) opacity = 0.0;
    if (opacity > 1.0) opacity = 1.0;

    return Opacity(
      opacity: opacity,
      child: child,
    );
  }

  @override
  bool shouldRebuild(CollapsibleSliverPersistentHeader oldDelegate) {
    return maxHeight != oldDelegate.maxHeight ||
        minHeight != oldDelegate.minHeight ||
        child != oldDelegate.child;
  }
}

/// A custom navigation slider widget to replace the TabBar.
class NavigationSlider extends StatefulWidget {
  final List<ProfileSection> sections;
  final TabController tabController;
  final String Function(ProfileSection) getTabTitle;
  final IconData Function(ProfileSection) getIconForSection;

  final void Function(int index, bool isAlreadySelected)? onTabTapped;


  const NavigationSlider({
    Key? key,
    required this.sections,
    required this.tabController,
    required this.getTabTitle,
    required this.getIconForSection,
    this.onTabTapped,
  }) : super(key: key);

  @override
  _NavigationSliderState createState() => _NavigationSliderState();
}

class _NavigationSliderState extends State<NavigationSlider> {

  int _selectedIndex = 0;
  final ScrollController _listScrollController = ScrollController();
  void _scrollToCenter(int index) {
    final itemWidth = 106.0;
    final screenWidth = MediaQuery.of(context).size.width;
    final targetScrollOffset = (itemWidth * index) - (screenWidth / 2) + (itemWidth / 2);

    _listScrollController.animateTo(
      targetScrollOffset,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }



  @override
  void initState() {
    super.initState();

    _selectedIndex = widget.tabController.index;
    widget.tabController.addListener(_onTabChanged);
    widget.tabController.animation?.addListener(_onAnimationChanged);

  }

  @override
  void dispose() {

    widget.tabController.removeListener(_onTabChanged);
    widget.tabController.animation?.removeListener(_onAnimationChanged);
    super.dispose();
  }

  void _onTabChanged() {
    if (widget.tabController.indexIsChanging) {
      setState(() {
        _selectedIndex = widget.tabController.index;
      });
      _scrollToCenter(_selectedIndex);
    }
  }

  void _onAnimationChanged() {
    if (widget.tabController.animation == null) return;
    int newIndex = widget.tabController.animation!.value.round();
    if (newIndex != _selectedIndex) {
      setState(() {
        _selectedIndex = newIndex;
      });
      _scrollToCenter(_selectedIndex);
    }
  }


  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Divider(
          height: 4.0,
          color: Color(0xFF111111),
          thickness: 4.0,
        ),
        Container(
          color: Colors.black,
          padding: const EdgeInsets.symmetric(horizontal: 4.0),
          child: SizedBox(
            height: 54,
            child: ListView(
              controller: _listScrollController,
              scrollDirection: Axis.horizontal,
              physics: Platform.isIOS
                  ? const ClampingScrollPhysics()   // more native for iOS
                  : const ClampingScrollPhysics(),  // default for Android
              children: widget.sections.asMap().entries.map((entry) {
                final index = entry.key;
                final section = entry.value;
                final isSelected = _selectedIndex == index;

                return GestureDetector(
                  onTap: () {
                    bool isAlreadySelected = index == _selectedIndex;
                    if (isAlreadySelected) {
                      widget.onTabTapped?.call(index, true);
                    } else {
                      widget.tabController.animateTo(index);
                    }
                  },
                  child: SizedBox(
                    width: 106,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      margin: const EdgeInsets.symmetric(horizontal: 1.4, vertical: 6.0),
                      padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 8.0),
                      decoration: BoxDecoration(
                        color: isSelected ? const Color(0xFFE09321) : Color(0xFF1F1F1F),
                        borderRadius: BorderRadius.circular(4.0),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            widget.getIconForSection(section),
                            color: Colors.white,
                            size: 20.0,
                          ),
                          const SizedBox(width: 4.0),

                          Flexible(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                widget.getTabTitle(section),
                                maxLines: 1,
                                softWrap: false,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),

        const Divider(
          height: 4.0,
          color: Color(0xFF111111),
          thickness: 4.0,
        ),
      ],
    );
  }
}