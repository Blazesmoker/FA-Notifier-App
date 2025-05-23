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
import '../utils/html_tags_debug.dart';
import '../widgets/PulsatingLoadingIndicator.dart';
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
import 'package:html/parser.dart' as html_parser;


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

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();


  bool _sfwEnabled = true;


  Future<void> _loadSfwEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _sfwEnabled = prefs.getBool('sfwEnabled') ?? true;
    });
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


  late ScrollController _scrollController;


  late TabController _tabController;


  int _previousIndex = 0;


  late Future<String> _userDescriptionFuture;


  final double _avatarFadeStart = 0.0;
  final double _avatarFadeEnd = 140.0;
  final double _avatarScaleStart = 0.0;
  final double _avatarScaleEnd = 140.0;

  final double _bannerScaleStart = 0.0;
  final double _bannerScaleEnd = 180.0;

  @override
  void initState() {
    super.initState();

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

    _fetchUserProfile();
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please log in to perform this action.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final fullUrl = 'https://www.furaffinity.net$urlPath';
    try {
      final response = await http.get(
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


        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${shouldWatch ? 'Now watching $username' : 'Stopped watching $username'}'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        print('Failed to ${shouldWatch ? 'watch' : 'unwatch'}. Status code: ${response.statusCode}');

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to ${shouldWatch ? 'watch' : 'unwatch'} user.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      print('Error during ${shouldWatch ? 'watch' : 'unwatch'}: $e');

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('An error occurred while trying to ${shouldWatch ? 'watch' : 'unwatch'} user.'),
          backgroundColor: Colors.red,
        ),
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Please log in to perform this action."),
          backgroundColor: Colors.red,
        ),
      );
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

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Shout deleted."),
            backgroundColor: Colors.green,
          ),
        );

        await _fetchUserProfile();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Failed to delete shout."),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Error: $e"),
          backgroundColor: Colors.red,
        ),
      );
    }
  }


  Future<void> _launchURL(String url) async {
    final Uri uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {

      print('Could not launch $url');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not launch URL: $url')),
      );
    }
  }

  /// Fetches the user's profile data from FurAffinity.
  Future<void> _fetchUserProfile() async {
    try {
      print("Fetching user profile...");
      String? cookieA = await _secureStorage.read(key: 'fa_cookie_a');
      String? cookieB = await _secureStorage.read(key: 'fa_cookie_b');


      final sfwValue = _sfwEnabled ? '1' : '0';

      if (cookieA == null || cookieB == null) {
        setState(() {
          errorMessage = 'No cookies found. User might not be logged in.';
          isLoading = false;
        });
        print("No cookies found.");
        return;
      }


      final sanitizedUsername = _sanitizeUsername(widget.nickname);
      final profileUrl = 'https://www.furaffinity.net/user/$sanitizedUsername/';
      print("Profile URL: $profileUrl");

      final response = await http.get(
        Uri.parse(profileUrl),
        headers: {
          'Cookie': 'a=$cookieA; b=$cookieB; sfw=$sfwValue',
          'User-Agent': 'Mozilla/5.0 (compatible; YourApp/1.0)',
        },
      );

      print("HTTP status code: ${response.statusCode}");
      if (response.statusCode == 200) {
        final decodedBody = utf8.decode(response.bodyBytes, allowMalformed: true);




        _parseUserProfile(decodedBody);


        var document = html_parser.parse(decodedBody);

        var watchLinkElement = logQuery(document, 'a.button.standard.go[href^="/watch/"]')
            ?? logQuery(document, 'a[href^="/watch/"]');

        var unwatchLinkElement = logQuery(document, 'a.button.standard.stop[href^="/unwatch/"]')
            ?? logQuery(document, 'a[href^="/unwatch/"]');


        var blockLinkElement = logQuery(document, 'a.button.standard.stop[href^="/block/"]')
            ?? logQuery(document, 'form[action^="/block/"]');
        String? computedBlockLink;
        if (blockLinkElement != null) {
          if (blockLinkElement.localName == 'form') {

            final keyElem = blockLinkElement.querySelector('input[name="key"]')
                ?? blockLinkElement.querySelector('button[name="key"]');
            final keyValue = keyElem?.attributes['value'] ?? '';
            if (keyValue.isNotEmpty) {
              computedBlockLink = 'https://www.furaffinity.net/block/$username/?key=$keyValue';
            }
          } else {
            computedBlockLink = blockLinkElement.attributes['href'];
          }
        }





        var unblockLinkElement = logQuery(document, 'a.button.standard.stop[href^="/unblock/"]')
            ?? logQuery(document, 'form[action^="/unblock/"]');
        String? computedUnblockLink;
        if (unblockLinkElement != null) {
          if (unblockLinkElement.localName == 'form') {
            final keyElem = unblockLinkElement.querySelector('input[name="key"]')
                ?? unblockLinkElement.querySelector('button[name="key"]');
            final keyValue = keyElem?.attributes['value'] ?? '';
            if (keyValue.isNotEmpty) {
              computedUnblockLink = 'https://www.furaffinity.net/unblock/$username/?key=$keyValue';
            }
          } else {
            computedUnblockLink = unblockLinkElement.attributes['href'];
          }
        }



        setState(() {
          watchLink = watchLinkElement?.attributes['href'];
          unwatchLink = unwatchLinkElement?.attributes['href'];
          blockLink = computedBlockLink;
          unblockLink = computedUnblockLink;
          isWatching = unwatchLinkElement != null;
          isBlocked = computedUnblockLink != null;
          isLoading = false;
        });


        print("Block/Unblock Link: $blockLink / $unblockLink");
        print("Watch/Unwatch Link: $watchLink / $unwatchLink");
        print("isBlocked: $isBlocked");
      } else {
        setState(() {
          errorMessage = 'Failed to fetch profile: ${response.statusCode}';
          isLoading = false;
        });
        print("Failed to fetch profile. Status code: ${response.statusCode}");
      }
    } catch (e) {
      setState(() {
        errorMessage = 'An error occurred: $e';
        isLoading = false;
      });
      print("An error occurred while fetching profile: $e");
    }
  }


  String _sanitizeUsername(String username) {
    return username.replaceAll(RegExp(r'[^a-zA-Z0-9-_.]'), '').toLowerCase();
  }

  void switchToGalleryTab() {
    _tabController.animateTo(ProfileSection.Gallery.index);
  }


  void _parseUserProfile(String htmlBody) {

    final document = html_parser.parse(htmlBody);


    bool localHasRealUserProfile = true;


    // Extract Profile Banner
    final bannerElem = logQuery(document, 'site-banner picture source[media="(min-width: 800px)"]')
        ?? logQuery(document, 'site-banner img')
        ?? logQuery(document, 'source[media="(min-width: 800px)"]');


    if (bannerElem != null) {
      String bannerUrl = bannerElem.attributes['srcset'] ?? bannerElem.attributes['src'] ?? '';
      if (bannerUrl.startsWith('/themes/beta/img/banners/logo/')) {
        profileBannerUrl = 'https://www.furaffinity.net$bannerUrl';
      } else if (bannerUrl.startsWith('//')) {
        profileBannerUrl = 'https:$bannerUrl';
      } else if (bannerUrl.startsWith('http://') || bannerUrl.startsWith('https://')) {
        profileBannerUrl = bannerUrl;
      } else {
        profileBannerUrl = 'https://www.furaffinity.net$bannerUrl';
      }
    } else {
      profileBannerUrl = 'https://www.furaffinity.net/themes/beta/img/banners/logo/fa-banner-summer.jpg';
    }
    print("Profile banner URL: $profileBannerUrl");


    // Extract Profile Picture (Main Avatar)
    final profilePicElem = logQuery(document, 'userpage-nav-avatar img')
        ?? logQuery(document, 'img.avatar');

    profileImageUrl = profilePicElem != null
        ? (profilePicElem.attributes['src']?.replaceFirst('//', 'https://'))
        : null;
    print("Main Profile Image URL: $profileImageUrl");


    // Extract Username (Display name and nickname for appbar)
    final displayNameElem = logQuery(document, 'a.c-usernameBlock__displayName .js-displayName')
        ?? logQuery(document, 'a.js-displayName-block .js-displayName');

    final displayName = displayNameElem?.text.trim() ?? 'Unknown User';

    final userNameElem = logQuery(document, 'a.c-usernameBlock__userName span')
        ?? logQuery(document, 'a.js-userName-block span');

    final symbolElem = logQuery(document, 'a.c-usernameBlock__userName span .c-usernameBlock__symbol')
        ?? logQuery(document, 'a.js-userName-block span .c-usernameBlock__symbol');

    String symbolText = symbolElem?.text.trim() ?? '';
    String fullUserName = userNameElem?.text.trim() ?? '';
    String nicknameWithoutSymbol = fullUserName;
    if (symbolText.isNotEmpty) {
      nicknameWithoutSymbol = fullUserName.replaceFirst(symbolText, '').trim();
    }
    // For the appbar, combine the symbol and nickname with a space.
    symbolUsername = symbolText.isNotEmpty ? '$symbolText $nicknameWithoutSymbol' : fullUserName;
    // For profile header display, use only the display name.
    profileDisplayName = displayName;
    profileUserNamePart = '';
    // Use displayName for internal sanitized username (for URL building, etc.)
    username = _sanitizeUsername(displayName);
    print("Username: $username, Appbar nickname: $symbolUsername");



    // Icon Blocks (for profile header)
    final usernameContainer = logQuery(document, '.c-usernameBlock')
        ?? logQuery(document, 'div.c-usernameBlock');


    final iconBeforeElems = usernameContainer?.querySelectorAll('usericon-block-before img');
    if (iconBeforeElems != null && iconBeforeElems.isNotEmpty) {
      userIconBeforeUrls = iconBeforeElems.map((imgElem) {
        String? src = imgElem.attributes['src'];
        if (src != null) {
          if (src.startsWith('//')) return 'https:$src';
          if (src.startsWith('/')) return 'https://www.furaffinity.net$src';
          return src;
        }
        return '';
      }).where((src) => src.isNotEmpty).toList();
    }

    // For icons after the nickname
    final iconAfterElems = usernameContainer?.querySelectorAll('usericon-block-after img');
    if (iconAfterElems != null && iconAfterElems.isNotEmpty) {
      userIconAfterUrls = iconAfterElems.map((imgElem) {
        String? src = imgElem.attributes['src'];
        if (src != null) {
          if (src.startsWith('//')) return 'https:$src';
          if (src.startsWith('/')) return 'https://www.furaffinity.net$src';
          return src;
        }
        return '';
      }).where((src) => src.isNotEmpty).toList();
    }

    setState(() {
      this.userIconBeforeUrls = userIconBeforeUrls;
      this.userIconAfterUrls = userIconAfterUrls;
    });

    final iconAfterElem = document.querySelector('usericon-block-after img');
    if (iconAfterElem != null) {
      String? src = iconAfterElem.attributes['src'];
      if (src != null) {
        if (src.startsWith('//')) {
          userIconAfterUrl = 'https:$src';
        } else if (src.startsWith('/')) {
          userIconAfterUrl = 'https://www.furaffinity.net$src';
        } else {
          userIconAfterUrl = src;
        }
      }
    }


    // Extract User Title and Registration Date using regex
    final userTitleElem = logQuery(document, 'span.user-title');

    if (userTitleElem != null) {

      String fullText = userTitleElem.text.trim();

      final regExp = RegExp(r'Registered:\s*(.+)$');
      final regMatch = regExp.firstMatch(fullText);
      if (regMatch != null) {
        registrationDate = regMatch.group(1)!.trim();

        userTitle = fullText.substring(0, regMatch.start).trim();

        if (userTitle!.endsWith("|")) {
          userTitle = userTitle?.substring(0, userTitle!.length - 1).trim();
        }
      } else {
        userTitle = fullText;
        registrationDate = "";
      }
      print("User title: $userTitle");
      print("Registration date: $registrationDate");
    } else {
      // Fallback: Classic

      final classicHtml = document.body?.innerHtml ?? "";
      final userTitleMatch = RegExp(r'<b>\s*User Title:\s*<\/b>\s*([^<]+)').firstMatch(classicHtml);
      final registeredMatch = RegExp(r'<b>\s*Registered Since:\s*<\/b>\s*([^<]+)').firstMatch(classicHtml);
      if (userTitleMatch != null) {
        userTitle = userTitleMatch.group(1)?.trim();
      } else {
        userTitle = "";
      }
      if (registeredMatch != null) {
        registrationDate = registeredMatch.group(1)?.trim();
      } else {
        registrationDate = 'N/A';
      }
      print("Classic User title: $userTitle");
      print("Classic Registration date: $registrationDate");
    }


    final sectionElem = logQuery(document, 'section.userpage-layout-profile')
        ?? logQuery(document, 'td.ldot');

    if (sectionElem != null) {

      if (sectionElem.localName == 'section') {
        userDescription = sectionElem.outerHtml.trim();
      }

      else if (sectionElem.localName == 'td') {
        String classicHtml = sectionElem.innerHtml;

        const headerMarker = '<b>Artist Profile:</b><br>';
        final splitIndex = classicHtml.indexOf(headerMarker);
        if (splitIndex != -1) {
          userDescription = classicHtml.substring(splitIndex + headerMarker.length).trim();
        } else {
          userDescription = classicHtml.trim();
        }
      }

      if (userDescription!.contains('<i>Not Available...</i>')) {
        localHasRealUserProfile = false;
        print("User Profile states: 'Not Available...'; marking as no real profile.");
        setState(() {
          hasRealUserProfile = localHasRealUserProfile;

          if (!hasRealUserProfile) {
            _webViewLoaded = true;
          }
          isLoading = false;
        });
      }
    } else {
      userDescription = 'No description available.';
      localHasRealUserProfile = false;
    }
    print("User description: $userDescription");



    // Extract Stats from the right column (Views, Submissions, Favs, etc.)


    dom.Element? statsSection = document.querySelector('.userpage-section-right .section-body');
    String statsText = "";
    if (statsSection != null) {
      statsText = statsSection.text.trim();
    } else {

      dom.Element? classicStatsTable;
      for (dom.Element table in document.querySelectorAll('table')) {
        var firstRow = table.querySelector('tr');
        if (firstRow != null) {
          var firstCell = firstRow.querySelector('td');
          if (firstCell != null && firstCell.text.trim() == 'Statistics') {
            classicStatsTable = table;
            break;
          }
        }
      }
      if (classicStatsTable != null) {

        var statsCell = classicStatsTable.querySelector('tr:nth-child(2) td[align="left"]');
        statsText = statsCell?.text.trim() ?? "";
      }
    }

    if (statsText.isNotEmpty) {

      views = _extractStatValue(statsText, 'Views:') ?? _extractStatValue(statsText, 'Page Visits:') ?? 0;
      submissions = _extractStatValue(statsText, 'Submissions:') ?? 0;
      favs = _extractStatValue(statsText, 'Favs:') ?? _extractStatValue(statsText, 'Favorites:') ?? 0;
      commentsEarned = _extractStatValue(statsText, 'Comments Earned:') ?? _extractStatValue(statsText, 'Comments Received:') ?? 0;
      commentsMade = _extractStatValue(statsText, 'Comments Made:') ?? _extractStatValue(statsText, 'Comments Given:') ?? 0;
      journals = _extractStatValue(statsText, 'Journals:') ?? 0;
      print("Views: $views");
      print("Submissions: $submissions");
      print("Favs: $favs");
      print("Comments Earned: $commentsEarned");
      print("Comments Made: $commentsMade");
      print("Journals: $journals");
    } else {
      views = 0;
      submissions = 0;
      favs = 0;
      commentsEarned = 0;
      commentsMade = 0;
      journals = 0;
      print("Stats section not found. Using default stat values.");
    }




    print("Extracting User Profile Section...");


    bool isClassicPage = document.body != null &&
        document.body!.attributes['data-static-path'] == '/themes/classic';

    bool userProfileFound = false;

    if (!isClassicPage) {
      // Modern
      final userpageSections = document.querySelectorAll('.userpage-section-right');
      for (var section in userpageSections) {
        final headerElem = section.querySelector('.section-header h2');
        if (headerElem != null && headerElem.text.trim() == 'User Profile') {

          final imageElem = section.querySelector('.section-submission.aligncenter a img');
          if (imageElem != null) {
            String? imageSrc = imageElem.attributes['src'];
            userProfileImageUrl = imageSrc != null
                ? (imageSrc.startsWith('//') ? 'https:$imageSrc' : imageSrc)
                : null;
            print("User Profile Section Image URL: $userProfileImageUrl");
          } else {
            userProfileImageUrl = null;
            print("User Profile Section Image not found. No image will be displayed.");
          }
          final linkElem = section.querySelector('.section-submission.aligncenter a');
          if (linkElem != null) {
            String? href = linkElem.attributes['href'];
            if (href != null) {
              final hrefParts = href.split('/');
              extractedUserProfilePostNumber = hrefParts.length > 2 ? hrefParts[2] : 'N/A';
              print("User Profile Section Post Number: $extractedUserProfilePostNumber");
            } else {
              extractedUserProfilePostNumber = 'N/A';
              print("Post number href not found. Using default.");
            }
          } else {
            extractedUserProfilePostNumber = 'N/A';
            print("Post number link not found. Using default.");
          }

          final sectionBodyElem = section.querySelector('.section-body');
          extractedUserProfileTexts = sectionBodyElem != null && sectionBodyElem.innerHtml.trim().isNotEmpty
              ? sectionBodyElem.innerHtml.trim()
              : 'No additional profile information.';
          print("User Profile Section Texts Extracted: $extractedUserProfileTexts");
          userProfileFound = true;
          break;
        }
      }
    }

    if (isClassicPage || !userProfileFound) {
      if (!isClassicPage) {
        print("Modern User Profile section not found. Trying classic markup...");
      }
      // Classic

      final profileIdElem = document.getElementById('profilepic-submission');


      if (profileIdElem != null) {
        final anchor = profileIdElem.querySelector('a[href^="/view/"]');
        if (anchor != null) {
          String? href = anchor.attributes['href'];
          if (href != null) {
            final hrefParts = href.split('/');
            extractedUserProfilePostNumber = hrefParts.length > 2 ? hrefParts[2] : 'N/A';
            print("Classic User Profile Post Number: $extractedUserProfilePostNumber");
          } else {
            extractedUserProfilePostNumber = 'N/A';
            print("Classic Post number href not found. Using default.");
          }

          final imageElem = profileIdElem.querySelector('img');
          if (imageElem != null) {
            String? imageSrc = imageElem.attributes['src'];
            userProfileImageUrl = imageSrc != null
                ? (imageSrc.startsWith('//') ? 'https:$imageSrc' : imageSrc)
                : null;
            print("Classic User Profile Image URL: $userProfileImageUrl");
          } else {
            userProfileImageUrl = null;
            print("Classic User Profile Image not found. No image will be displayed.");
          }
        } else {
          userProfileImageUrl = null;
          extractedUserProfilePostNumber = 'N/A';
          print("Classic Profile ID table anchor not found. Using default values.");
        }
      } else {
        userProfileImageUrl = null;
        extractedUserProfilePostNumber = 'N/A';
        print("Classic Profile ID table not found.");
      }


      final artistInfoTables = document.querySelectorAll('table.maintable');
      bool artistInfoFound = false;
      for (var table in artistInfoTables) {
        final headerElem = table.querySelector('td.cat b');
        if (headerElem != null && headerElem.text.trim() == 'Artist Information') {
          final infoCell = table.querySelector('td.alt1.user-info');
          if (infoCell != null) {
            extractedUserProfileTexts = infoCell.innerHtml.trim();
            print("Classic Artist Information extracted: $extractedUserProfileTexts");
          } else {
            extractedUserProfileTexts = 'No additional profile information.';
            print("Classic Artist Information cell not found. Using default.");
          }
          artistInfoFound = true;
          break;
        }
      }
      if (!artistInfoFound) {
        extractedUserProfileTexts = 'No additional profile information.';
        print("Classic Artist Information table not found. Using default.");
      }


      isClassicMarkup = true;
      List<dom.Element> optionYesElements = document.querySelectorAll('span.option-yes');
      acceptingTrades = optionYesElements.any((elem) => elem.text.trim().toLowerCase().contains("trades"));
      acceptingCommissions = optionYesElements.any((elem) => elem.text.trim().toLowerCase().contains("commissions"));
      print("Classic markup: Accepting Trades: $acceptingTrades, Accepting Commissions: $acceptingCommissions");
    }

    if (!userProfileFound && !isClassicPage) {
      print("User Profile section (modern/classic) extraction completed with classic fallback.");
    }


    // Extract Featured Submission
    final featuredSectionHeader = document.querySelector('.userpage-section-left .section-header h2');
    if (featuredSectionHeader != null && featuredSectionHeader.text.trim() == 'Featured Submission') {
      final featuredSection = featuredSectionHeader.parent?.parent;
      if (featuredSection != null) {
        final imageElem = featuredSection.querySelector('.section-body .aligncenter.preview_img a img');
        if (imageElem != null) {
          String? imageSrc = imageElem.attributes['src'];
          featuredImageUrl = imageSrc != null
              ? (imageSrc.startsWith('//') ? 'https:$imageSrc' : imageSrc)
              : null;
          print("Featured image URL: $featuredImageUrl");
        } else {
          featuredImageUrl = null;
          print("Featured image not found. Section will not be displayed.");
        }
        final linkElem = featuredSection.querySelector('.section-body .aligncenter.preview_img a');
        if (linkElem != null) {
          String? href = linkElem.attributes['href'];
          if (href != null) {
            final hrefParts = href.split('/');
            featuredPostNumber = hrefParts.length > 2 ? hrefParts[2] : 'N/A';
            print("Featured post number: $featuredPostNumber");
          } else {
            featuredPostNumber = 'N/A';
            print("Featured post href not found. Using default.");
          }
        } else {
          featuredPostNumber = 'N/A';
          print("Featured post link not found. Using default.");
        }
        final titleElem = featuredSection.querySelector('.userpage-featured-title h2 a');
        featuredImageTitle = titleElem != null && titleElem.text.trim().isNotEmpty
            ? titleElem.text.trim()
            : null;
        print("Featured image title: $featuredImageTitle");
      } else {
        featuredImageUrl = null;
        featuredPostNumber = 'N/A';
        featuredImageTitle = null;
        print("Featured Submission section not fully found. Section will not be displayed.");
      }
    } else {
      // Classic
      print("Modern Featured Submission section not found. Trying classic markup...");
      dom.Element? featuredTable;
      for (dom.Element table in document.querySelectorAll('table.maintable')) {
        final headerElem = table.querySelector('td.cat b');
        if (headerElem != null && headerElem.text.trim() == 'Featured Submission') {
          featuredTable = table;
          break;
        }
      }
      if (featuredTable != null) {
        final contentCell = featuredTable.querySelector('td.alt1#featured-submission');
        if (contentCell != null) {
          final anchor = contentCell.querySelector('center a[href^="/view/"]');
          if (anchor != null) {
            String? href = anchor.attributes['href'];
            if (href != null) {
              final hrefParts = href.split('/');
              featuredPostNumber = hrefParts.length > 2 ? hrefParts[2] : 'N/A';
              print("Classic Featured post number: $featuredPostNumber");
            } else {
              featuredPostNumber = 'N/A';
              print("Classic Featured post href not found. Using default.");
            }
            final img = anchor.querySelector('img');
            if (img != null) {
              String? imageSrc = img.attributes['src'];
              featuredImageUrl = imageSrc != null
                  ? (imageSrc.startsWith('//') ? 'https:$imageSrc' : imageSrc)
                  : null;
              print("Classic Featured image URL: $featuredImageUrl");
            } else {
              featuredImageUrl = null;
              print("Classic Featured image not found. Section will not be displayed.");
            }
          } else {
            featuredPostNumber = 'N/A';
            print("Classic Featured submission anchor not found. Using default.");
          }
          final spanTitle = contentCell.querySelector('center b span');
          featuredImageTitle = spanTitle != null && spanTitle.text.trim().isNotEmpty
              ? spanTitle.text.trim()
              : null;
          print("Classic Featured image title: $featuredImageTitle");
        } else {
          featuredImageUrl = null;
          featuredPostNumber = 'N/A';
          featuredImageTitle = null;
          print("Classic Featured submission content cell not found.");
        }
      } else {
        featuredImageUrl = null;
        featuredPostNumber = 'N/A';
        featuredImageTitle = null;
        print("Featured Submission section not found. Section will not be displayed.");
      }
    }



    // Extract Contact Information
    print("Extracting Contact Information...");
    List<Map<String, String>> contacts = [];
    dom.Element? contactInfoSection = document.querySelector('#userpage-contact');

    if (contactInfoSection != null) {

      final contactItems = contactInfoSection.querySelectorAll('.user-contact-item');
      for (var item in contactItems) {
        final labelElement = item.querySelector('.user-contact-user-info .highlight');
        final valueElement = item.querySelector('.user-contact-user-info a');
        String? label = labelElement?.text.trim();

        if (label != null && label.endsWith(':')) {
          label = label.substring(0, label.length - 1);
        }
        String? href = valueElement?.attributes['href'];
        String value = valueElement?.text.trim() ?? 'N/A';
        if (label != null && href != null) {

          if (valueElement!.children.isNotEmpty &&
              valueElement.children.first.localName == 'i') {
            value = valueElement.children.first.text.trim();
          }
          if (value.isNotEmpty && value != 'N/A') {
            contacts.add({'label': label, 'value': value, 'href': href});
          }
        }
      }
    } else {

      dom.Element? classicContactSection;
      // Loop through tables to find one with header "Contact Information"
      for (dom.Element table in document.querySelectorAll('table.maintable')) {
        final headerElem = table.querySelector('td.cat b');
        if (headerElem != null && headerElem.text.trim() == 'Contact Information') {
          classicContactSection = table.querySelector('td.alt1.user-contacts');
          break;
        }
      }
      if (classicContactSection != null) {
        final classicItems =
        classicContactSection.querySelectorAll('.classic-contact-info-item');
        for (var item in classicItems) {
          final labelElem = item.querySelector('.contact-service-name strong');
          String? label = labelElem?.text.trim();
          if (label != null && label.endsWith(':')) {
            label = label.substring(0, label.length - 1);
          }
          final valueElem = item.querySelector('a');
          String? href = valueElem?.attributes['href'];
          String value = valueElem?.text.trim() ?? 'N/A';
          if (label != null && href != null) {
            contacts.add({'label': label, 'value': value, 'href': href});
          }
        }
      }
    }

    setState(() {
      contactInformationLinks = contacts;
    });
    print("Contact Information extracted.");




    // Parsing for Recent Watchers
    print("Extracting Recent Watchers...");
    List<UserLink> tempRecentWatchers = [];
    int tempRecentWatchersCount = 0;
    dom.Element? recentWatchersSection = document.querySelector('section.userpage-left-column.watched-by-block');

    if (recentWatchersSection != null) {
      // Modern
      final viewListLink = recentWatchersSection.querySelector('.section-header .floatright h3 a');
      if (viewListLink != null) {
        final linkText = viewListLink.text.trim();
        final countMatch = RegExp(r'Watched by (\d+)').firstMatch(linkText);
        if (countMatch != null && countMatch.groupCount >= 1) {
          tempRecentWatchersCount = int.tryParse(countMatch.group(1)!) ?? 0;
        }
      }
      final userElements = recentWatchersSection.querySelectorAll('.section-body span.c-usernameBlockSimple__displayName');
      for (var userElem in userElements) {
        String watcherName = userElem.text.trim();
        final linkElem = userElem.parent;
        String href = linkElem?.attributes['href'] ?? '';
        String fullUrl = href.startsWith('http') ? href : 'https://www.furaffinity.net$href';
        if (watcherName.isNotEmpty && href.isNotEmpty) {
          tempRecentWatchers.add(UserLink(rawUsername: watcherName, url: fullUrl));
        }
      }
      print("Recent Watchers (modern) Count: $tempRecentWatchersCount");
    } else {
      // Classic
      print("Modern Recent Watchers section not found. Trying classic markup...");
      dom.Element? watchersTable;
      for (dom.Element table in document.querySelectorAll('table.maintable')) {
        final headerElem = table.querySelector('td.cat b');
        if (headerElem != null && headerElem.text.trim() == 'Watched By') {
          watchersTable = table;
          break;
        }
      }
      if (watchersTable != null) {
        final watchersCell = watchersTable.querySelector('td#watched-by');
        if (watchersCell != null) {
          final userElements = watchersCell.querySelectorAll('span.c-usernameBlockSimple__displayName');
          for (var userElem in userElements) {
            String watcherName = userElem.text.trim();
            final linkElem = userElem.parent;
            String href = linkElem?.attributes['href'] ?? '';
            String fullUrl = href.startsWith('http') ? href : 'https://www.furaffinity.net$href';
            if (watcherName.isNotEmpty && href.isNotEmpty) {
              tempRecentWatchers.add(UserLink(rawUsername: watcherName, url: fullUrl));
            }
          }

          final countLink = watchersTable.querySelector('td.cat a');
          if (countLink != null) {
            final linkText = countLink.text.trim();
            final countMatch = RegExp(r'\((\d+)\)').firstMatch(linkText);
            if (countMatch != null && countMatch.groupCount >= 1) {
              tempRecentWatchersCount = int.tryParse(countMatch.group(1)!) ?? 0;
            }
          }
        }
        print("Recent Watchers (classic) Count: $tempRecentWatchersCount");
      } else {
        print("Classic Recent Watchers section not found.");
      }
    }
    print("Recent Watchers List: ${tempRecentWatchers.map((u) => u.rawUsername).toList()}");



    // Parsing for Recently Watched
    print("Extracting Recently Watched...");
    List<UserLink> tempRecentlyWatched = [];
    int tempRecentlyWatchedCount = 0;
    dom.Element? recentlyWatchedSection = document.querySelector('section.userpage-left-column.is-watching-block');

    if (recentlyWatchedSection != null) {
      // Modern
      final viewListLink = recentlyWatchedSection.querySelector('.section-header .floatright h3 a');
      if (viewListLink != null) {
        final linkText = viewListLink.text.trim();
        final countMatch = RegExp(r'Watching (\d+)').firstMatch(linkText);
        if (countMatch != null && countMatch.groupCount >= 1) {
          tempRecentlyWatchedCount = int.tryParse(countMatch.group(1)!) ?? 0;
        }
      }
      final userElements = recentlyWatchedSection.querySelectorAll('.section-body span.c-usernameBlockSimple__displayName');
      for (var userElem in userElements) {
        String watchedName = userElem.text.trim();
        final linkElem = userElem.parent;
        String href = linkElem?.attributes['href'] ?? '';
        String fullUrl = href.startsWith('http') ? href : 'https://www.furaffinity.net$href';
        if (watchedName.isNotEmpty && href.isNotEmpty) {
          tempRecentlyWatched.add(UserLink(rawUsername: watchedName, url: fullUrl));
        }
      }
      print("Recently Watched (modern) Count: $tempRecentlyWatchedCount");
    } else {
      // Classic
      print("Modern Recently Watched section not found. Trying classic markup...");
      dom.Element? watchingTable;
      for (dom.Element table in document.querySelectorAll('table.maintable')) {
        final headerElem = table.querySelector('td.cat b');
        if (headerElem != null && headerElem.text.trim() == 'Is Watching') {
          watchingTable = table;
          break;
        }
      }
      if (watchingTable != null) {

        final watchingCell = watchingTable.querySelector('td#is-watching');
        if (watchingCell != null) {
          final userElements = watchingCell.querySelectorAll('span.c-usernameBlockSimple__displayName');
          for (var userElem in userElements) {
            String watchedName = userElem.text.trim();
            final linkElem = userElem.parent;
            String href = linkElem?.attributes['href'] ?? '';
            String fullUrl = href.startsWith('http') ? href : 'https://www.furaffinity.net$href';
            if (watchedName.isNotEmpty && href.isNotEmpty) {
              tempRecentlyWatched.add(UserLink(rawUsername: watchedName, url: fullUrl));
            }
          }

          final countLink = watchingTable.querySelector('td.cat a');
          if (countLink != null) {
            final linkText = countLink.text.trim();
            final countMatch = RegExp(r'\((\d+)\)').firstMatch(linkText);
            if (countMatch != null && countMatch.groupCount >= 1) {
              tempRecentlyWatchedCount = int.tryParse(countMatch.group(1)!) ?? 0;
            }
          }
        }
        print("Recently Watched (classic) Count: $tempRecentlyWatchedCount");
      } else {
        print("Classic Recently Watched section not found.");
      }
    }
    print("Recently Watched List: ${tempRecentlyWatched.map((u) => u.rawUsername).toList()}");




    // Extract Shouts
    print("Extracting Shouts...");
    List<Shout> tempShouts = [];


    dom.Element? shoutsSection = document.querySelector('.userpage-section-right.no-border');

    if (shoutsSection != null) {
      final shoutContainers = shoutsSection.querySelectorAll('div.comment_container');
      for (var container in shoutContainers) {
        // Extract avatar URL
        final avatarElem = container.querySelector('img.comment_useravatar');
        String avatarUrl = avatarElem != null
            ? (avatarElem.attributes['src']!.startsWith('//')
            ? 'https:${avatarElem.attributes['src']!}'
            : avatarElem.attributes['src']!)
            : 'assets/images/defaultpic.gif';


        final displayNameElem = container.querySelector('a.c-usernameBlock__displayName .js-displayName');
        final userNameElem = container.querySelector('a.c-usernameBlock__userName .js-userName-block span');
        final displayName = displayNameElem?.text.trim() ?? 'Unknown';
        final userNamePart = userNameElem?.text.trim() ?? '';


        final symbolElem = container.querySelector('a.c-usernameBlock__userName .c-usernameBlock__symbol');
        final symbol = symbolElem?.text.trim() ?? "~";


        final usernameWithoutSymbol = userNamePart.replaceFirst(symbol, '').trim();


        String cmtUsername = (usernameWithoutSymbol.isEmpty ||
            displayName.toLowerCase() == usernameWithoutSymbol.toLowerCase())
            ? displayName
            : '$displayName\n@$usernameWithoutSymbol';


        final usernameLink = container.querySelector('div.avatar a');
        String? profileNickname = usernameLink?.attributes['href'] != null
            ? usernameLink!.attributes['href']!.split('/').where((part) => part.isNotEmpty).last
            : 'Unknown';


        final dateElem = container.querySelector('span.popup_date');
        String relativeDate = dateElem?.text.trim() ?? 'Unknown date';
        String fullDate = dateElem?.attributes['title']?.trim() ?? relativeDate;

        final textElem = container.querySelector('comment-user-text.comment_text');
        String text = textElem?.innerHtml.trim() ?? '';

        String shoutId = '';
        final anchor = container.querySelector('a.comment_anchor[id^="shout-"]');
        if (anchor != null) {
          final idAttr = anchor.attributes['id'] ?? '';
          if (idAttr.startsWith('shout-')) {
            shoutId = idAttr.substring('shout-'.length);
          }
        }


        final shoutUsernameContainer = container.querySelector('.c-usernameBlock');
        List<String> shoutIconBeforeUrls = [];
        if (shoutUsernameContainer != null) {
          final beforeIcons = shoutUsernameContainer.querySelectorAll('usericon-block-before img');
          shoutIconBeforeUrls = beforeIcons.map((imgElem) {
            String? src = imgElem.attributes['src'];
            if (src != null) {
              if (src.startsWith('//')) return 'https:$src';
              if (src.startsWith('/')) return 'https://www.furaffinity.net$src';
              return src;
            }
            return '';
          }).where((src) => src.isNotEmpty).toList();
        }
        List<String> shoutIconAfterUrls = [];
        if (shoutUsernameContainer != null) {
          final afterIcons = shoutUsernameContainer.querySelectorAll('usericon-block-after img');
          shoutIconAfterUrls = afterIcons.map((imgElem) {
            String? src = imgElem.attributes['src'];
            if (src != null) {
              if (src.startsWith('//')) return 'https:$src';
              if (src.startsWith('/')) return 'https://www.furaffinity.net$src';
              return src;
            }
            return '';
          }).where((src) => src.isNotEmpty).toList();
        }



        tempShouts.add(Shout(
          id: shoutId,
          avatarUrl: avatarUrl,
          username: cmtUsername,
          profileNickname: profileNickname,
          date: relativeDate,
          text: text,
          popupDateFull: fullDate,
          popupDateRelative: relativeDate,
          iconBeforeUrls: shoutIconBeforeUrls,
          iconAfterUrls: shoutIconAfterUrls,
          symbol: symbol,
        ));
      }
      print("Modern shouts extracted: ${tempShouts.length}");
    } else {

      print("Modern Shouts section not found. Trying classic markup...");

      List<dom.Element> shoutTables = document
          .querySelectorAll('table.maintable')
          .where((table) => table.attributes['id']?.startsWith('shout-') ?? false)
          .toList();
      for (var table in shoutTables) {

        String idAttr = table.attributes['id'] ?? "";
        String shoutId = "";
        if (idAttr.startsWith("shout-")) {
          shoutId = idAttr.substring("shout-".length);
        }

        final avatarElem = table.querySelector('img.avatar');
        String avatarUrl = avatarElem != null
            ? (avatarElem.attributes['src']!.startsWith('//')
            ? 'https:${avatarElem.attributes['src']!}'
            : avatarElem.attributes['src']!)
            : 'assets/images/defaultpic.gif';

        final usernameBlock = table.querySelector('.c-usernameBlock');
        String displayName = "Unknown";
        String userNamePart = "";
        String symbol = "~";
        if (usernameBlock != null) {
          final displayNameElem = usernameBlock.querySelector('a.c-usernameBlock__displayName .js-displayName');
          if (displayNameElem != null) {
            displayName = displayNameElem.text.trim();
          }
          final userNameElem = usernameBlock.querySelector('a.c-usernameBlock__userName span');
          if (userNameElem != null) {
            userNamePart = userNameElem.text.trim();
          }
          final symbolElem = usernameBlock.querySelector('span.c-usernameBlock__symbol');
          if (symbolElem != null) {
            symbol = symbolElem.text.trim();
          }
        }
        String usernameWithoutSymbol = userNamePart.replaceFirst(symbol, '').trim();

        String cmtUsername = (usernameWithoutSymbol.isEmpty ||
            displayName.toLowerCase() == usernameWithoutSymbol.toLowerCase())
            ? displayName
            : '$displayName\n@$usernameWithoutSymbol';


        String? profileNickname = "Unknown";
        final avatarLink = table.querySelector('td.alt1 a');
        if (avatarLink != null) {
          String href = avatarLink.attributes['href'] ?? "";
          if (href.isNotEmpty) {
            profileNickname = href.split('/').where((part) => part.isNotEmpty).last;
          }
        }

        String relativeDate = "Unknown date";
        String fullDate = "Unknown date";
        final dateElem = table.querySelector('span.popup_date');
        if (dateElem != null) {
          relativeDate = dateElem.text.trim();
          fullDate = dateElem.attributes['title']?.trim() ?? relativeDate;
        }

        String text = "";
        final textElem = table.querySelector('td.alt1.addpad div.no_overflow');
        if (textElem != null) {
          text = textElem.innerHtml.trim();
        }

        List<String> shoutIconBeforeUrls = [];
        List<String> shoutIconAfterUrls = [];
        if (usernameBlock != null) {
          final beforeIcons = usernameBlock.querySelectorAll('usericon-block-before img');
          shoutIconBeforeUrls = beforeIcons.map((imgElem) {
            String? src = imgElem.attributes['src'];
            if (src != null) {
              if (src.startsWith('//')) return 'https:$src';
              if (src.startsWith('/')) return 'https://www.furaffinity.net$src';
              return src;
            }
            return '';
          }).where((src) => src.isNotEmpty).toList();
          final afterIcons = usernameBlock.querySelectorAll('usericon-block-after img');
          shoutIconAfterUrls = afterIcons.map((imgElem) {
            String? src = imgElem.attributes['src'];
            if (src != null) {
              if (src.startsWith('//')) return 'https:$src';
              if (src.startsWith('/')) return 'https://www.furaffinity.net$src';
              return src;
            }
            return '';
          }).where((src) => src.isNotEmpty).toList();
        }


        tempShouts.add(Shout(
          id: shoutId,
          avatarUrl: avatarUrl,
          username: cmtUsername,
          profileNickname: profileNickname,
          date: relativeDate,
          text: text,
          popupDateFull: fullDate,
          popupDateRelative: relativeDate,
          iconBeforeUrls: shoutIconBeforeUrls,
          iconAfterUrls: shoutIconAfterUrls,
          symbol: symbol,
        ));
      }
      print("Classic shouts extracted: ${tempShouts.length}");
    }

    print("Shouts extracted: ${tempShouts.length}");




    // Watch/Unwatch/Block/Unblock link detection
    var watchLinkElement = logQuery(document, 'a.button.standard.go[href^="/watch/"]')
        ?? logQuery(document, 'a[href^="/watch/"]');

    var unwatchLinkElement = logQuery(document, 'a.button.standard.stop[href^="/unwatch/"]')
        ?? logQuery(document, 'a[href^="/unwatch/"]');

    var blockLinkElement = logQuery(document, 'a.button.standard.stop[href^="/block/"]')
        ?? logQuery(document, 'form[action^="/block/"]');
    String? computedBlockLink;
    if (blockLinkElement != null) {
      if (blockLinkElement.localName == 'form') {

        final keyElem = blockLinkElement.querySelector('input[name="key"]')
            ?? blockLinkElement.querySelector('button[name="key"]');
        final keyValue = keyElem?.attributes['value'] ?? '';
        if (keyValue.isNotEmpty) {
          computedBlockLink = 'https://www.furaffinity.net/block/$username/?key=$keyValue';
        }
      } else {
        computedBlockLink = blockLinkElement.attributes['href'];
      }
    }



    var unblockLinkElement = logQuery(document, 'a.button.standard.stop[href^="/unblock/"]')
        ?? logQuery(document, 'form[action^="/unblock/"]');
    String? computedUnblockLink;
    if (unblockLinkElement != null) {
      if (unblockLinkElement.localName == 'form') {
        final keyElem = unblockLinkElement.querySelector('input[name="key"]')
            ?? unblockLinkElement.querySelector('button[name="key"]');
        final keyValue = keyElem?.attributes['value'] ?? '';
        if (keyValue.isNotEmpty) {
          computedUnblockLink = 'https://www.furaffinity.net/unblock/$username/?key=$keyValue';
        }
      } else {
        computedUnblockLink = unblockLinkElement.attributes['href'];
      }
    }



    bool localIsOwnProfile = watchLinkElement == null &&
        unwatchLinkElement == null &&
        blockLinkElement == null &&
        unblockLinkElement == null;


    // Update widget state with all parsed data
    setState(() {
      isLoading = false;
      this.userDescription = userDescription;
      this.hasRealUserProfile = localHasRealUserProfile;
      this.username = username;
      this.symbolUsername = symbolUsername;
      this.userTitle = userTitle;
      this.registrationDate = registrationDate;
      this.profileImageUrl = profileImageUrl;
      this.profileBannerUrl = profileBannerUrl;
      this.views = views;
      this.submissions = submissions;
      this.favs = favs;
      this.commentsEarned = commentsEarned;
      this.commentsMade = commentsMade;
      this.journals = journals;
      this.userProfileImageUrl = userProfileImageUrl;
      this.userProfilePostNumber = extractedUserProfilePostNumber;
      this.userProfileTexts = extractedUserProfileTexts;
      this.featuredImageUrl = featuredImageUrl;
      this.featuredImageTitle = featuredImageTitle;
      this.featuredPostNumber = featuredPostNumber;
      this.recentWatchers = tempRecentWatchers;
      this.recentWatchersCount = tempRecentWatchersCount;
      this.recentlyWatched = tempRecentlyWatched;
      this.recentlyWatchedCount = tempRecentlyWatchedCount;
      this.shouts = tempShouts;
      this.isOwnProfile = localIsOwnProfile;
    });

    print("Finished parsing user profile.");
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

  /// Defines styles for BBCode handling in the user description.
  final Map<String, html_pkg.Style> htmlStyles = {
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
      color: Color(0xFFE09321),
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
  };

  /// Builds extensions for handling BBCode and emojis.
  List<html_pkg.HtmlExtension> _buildBBCodeExtensions() {
    return [
      html_pkg.TagExtension(
        tagsToExtend: {"i"},
        builder: (html_pkg.ExtensionContext context) {
          final classAttr = context.attributes['class'];

          if (classAttr == 'bbcode bbcode_i') {
            return Text(
              context.styledElement?.element?.text ?? "",
              style: const TextStyle(fontStyle: FontStyle.italic, color: Colors.white),
            );
          }

          // Map FA emoji classes to corresponding image assets
          switch (classAttr) {
            case 'smilie tongue':
              return Image.asset('assets/emojis/tongue.png',
                  width: 20, height: 20);
            case 'smilie evil':
              return Image.asset('assets/emojis/evil.png',
                  width: 20, height: 20);
            case 'smilie lmao':
              return Image.asset('assets/emojis/lmao.png',
                  width: 20, height: 20);
            case 'smilie gift':
              return Image.asset('assets/emojis/gift.png',
                  width: 20, height: 20);
            case 'smilie derp':
              return Image.asset('assets/emojis/derp.png',
                  width: 20, height: 20);
            case 'smilie teeth':
              return Image.asset('assets/emojis/teeth.png',
                  width: 20, height: 20);
            case 'smilie cool':
              return Image.asset('assets/emojis/cool.png',
                  width: 20, height: 20);
            case 'smilie huh':
              return Image.asset('assets/emojis/huh.png',
                  width: 20, height: 20);
            case 'smilie cd':
              return Image.asset('assets/emojis/cd.png',
                  width: 20, height: 20);
            case 'smilie coffee':
              return Image.asset('assets/emojis/coffee.png',
                  width: 20, height: 20);
            case 'smilie sarcastic':
              return Image.asset('assets/emojis/sarcastic.png',
                  width: 20, height: 20);
            case 'smilie veryhappy':
              return Image.asset('assets/emojis/veryhappy.png',
                  width: 20, height: 20);
            case 'smilie wink':
              return Image.asset('assets/emojis/wink.png',
                  width: 20, height: 20);
            case 'smilie whatever':
              return Image.asset('assets/emojis/whatever.png',
                  width: 20, height: 20);
            case 'smilie crying':
              return Image.asset('assets/emojis/crying.png',
                  width: 20, height: 20);
            case 'smilie love':
              return Image.asset('assets/emojis/love.png',
                  width: 20, height: 20);
            case 'smilie serious':
              return Image.asset('assets/emojis/serious.png',
                  width: 20, height: 20);
            case 'smilie yelling':
              return Image.asset('assets/emojis/yelling.png',
                  width: 20, height: 20);
            case 'smilie oooh':
              return Image.asset('assets/emojis/oooh.png',
                  width: 20, height: 20);
            case 'smilie angel':
              return Image.asset('assets/emojis/angel.png',
                  width: 20, height: 20);
            case 'smilie dunno':
              return Image.asset('assets/emojis/dunno.png',
                  width: 20, height: 20);
            case 'smilie nerd':
              return Image.asset('assets/emojis/nerd.png',
                  width: 20, height: 20);
            case 'smilie sad':
              return Image.asset('assets/emojis/sad.png',
                  width: 20, height: 20);
            case 'smilie zipped':
              return Image.asset('assets/emojis/zipped.png',
                  width: 20, height: 20);
            case 'smilie smile':
              return Image.asset('assets/emojis/smile.png',
                  width: 20, height: 20);
            case 'smilie badhairday':
              return Image.asset('assets/emojis/badhairday.png',
                  width: 20, height: 20);
            case 'smilie embarrassed':
              return Image.asset('assets/emojis/embarrassed.png',
                  width: 20, height: 20);
            case 'smilie note':
              return Image.asset('assets/emojis/note.png',
                  width: 20, height: 20);
            case 'smilie sleepy':
              return Image.asset('assets/emojis/sleepy.png',
                  width: 20, height: 20);
            default:
              return const SizedBox.shrink(); // Handle unknown emojis
          }
        },
      ),
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

    ];
  }

  final Map<String, html_pkg.Style> htmlStylesUserProfile = {
    "body": html_pkg.Style(
      padding: HtmlPaddings.zero,
      margin: Margins.zero,
      textAlign: TextAlign.left,
      fontSize: html_pkg.FontSize(16),
      color: Colors.white,
    ),
    "p": html_pkg.Style(
      padding: html_pkg.HtmlPaddings.zero,
      margin: html_pkg.Margins.zero,
      fontSize: html_pkg.FontSize(16),
      color: Colors.white,
    ),
    "a": html_pkg.Style(
      padding: html_pkg.HtmlPaddings.zero,
      margin: html_pkg.Margins.zero,
      color: Color(0xFFE09321),
      textDecoration: TextDecoration.none,
    ),
    "img": html_pkg.Style(
      padding: html_pkg.HtmlPaddings.zero,
      margin: html_pkg.Margins.zero,
      width: html_pkg.Width(50.0),
      height: html_pkg.Height(50.0),
    ),
    "strong": html_pkg.Style(
      padding: HtmlPaddings.symmetric(vertical: 8),
      margin: Margins.symmetric(vertical: 4),
      color: Colors.white,
      fontWeight: FontWeight.bold,
    ),
    "u": html_pkg.Style(
      padding: html_pkg.HtmlPaddings.zero,
      margin: html_pkg.Margins.zero,
      color: Colors.white,
    ),
    ".bbcode_right": html_pkg.Style(
      padding: html_pkg.HtmlPaddings.zero,
      margin: html_pkg.Margins.zero,
      textAlign: TextAlign.right,
    ),
    ".bbcode_right .bbcode_sup, .bbcode_right sup": html_pkg.Style(
      padding: html_pkg.HtmlPaddings.zero,
      margin: html_pkg.Margins.zero,
      textAlign: TextAlign.right,
    ),
    ".bbcode_center": html_pkg.Style(
      padding: html_pkg.HtmlPaddings.zero,
      margin: html_pkg.Margins.zero,
      textAlign: TextAlign.center,
    ),
    ".bbcode_left": html_pkg.Style(
      padding: html_pkg.HtmlPaddings.zero,
      margin: html_pkg.Margins.zero,
      textAlign: TextAlign.left,
    ),
  };

  Widget _buildShoutsSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 0.0),
      child: Container(
        decoration: BoxDecoration(
          color: Color(0xFF1F1F1F),
          borderRadius: BorderRadius.circular(8.0),
        ),
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Shouts Header
            const Text(
              'Shouts',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8.0),
            GestureDetector(
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
                margin: const EdgeInsets.only(bottom: 16.0),
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                decoration: BoxDecoration(
                  color: Color(0xFF353535),
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

            shouts.isEmpty
                ? const Text(
              'No shouts yet. Be the first to shout!',
              style: TextStyle(color: Colors.white70),
            )
                : ListView.separated(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: shouts.length,
              separatorBuilder: (context, index) => const Divider(
                color: Colors.white,
                thickness: 0.3,
              ),
              itemBuilder: (context, index) {
                final shout = shouts[index];
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onLongPress: () {
                    _confirmDeleteShout(index, shout);
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
          ],
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
                      fit: BoxFit.contain,
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
              style: htmlStylesUserProfile,
              extensions: _buildBBCodeExtensions(),
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
            // Display icons before the nickname.
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
              onOpen: (link) async {
              },
              selectionControls: MaterialTextSelectionControls(),
            ),
            const SizedBox(width: 4),
            // Display icons after the nickname.
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
              onOpen: (link) async {
              },
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
          color: Color(0xFF1F1F1F),
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
                            _launchURL(contact['href']!);
                          },
                          child: Text(
                            contact['value']!,
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


  Future<void> _handleFALink(BuildContext context, String url) async {
    final Uri uri = Uri.parse(url);
    final String urlToMatch = uri.toString();

    // Gallery Folder Link
    // Matches URLs like: https://www.furaffinity.net/gallery/username/folder/123456/folderName/

    final RegExp galleryFolderRegex = RegExp(
        r'^https?://(?:www\.)?furaffinity\.net/gallery/([^/]+)/folder/(\d+)/([^/]+)/?$'
    );
    if (galleryFolderRegex.hasMatch(urlToMatch)) {
      final match = galleryFolderRegex.firstMatch(urlToMatch)!;
      final String tappedUsername = match.group(1)!;
      final String folderNumber = match.group(2)!;
      final String folderName = match.group(3)!;
      final String folderUrl = 'https://www.furaffinity.net/gallery/$tappedUsername/folder/$folderNumber/$folderName/';

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
        r'^(?:https?://(?:www\.)?furaffinity\.net)?/user/([^/]+)/?$'
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
        r'^(?:https?://(?:www\.)?furaffinity\.net)?/journal/(\d+)/.*$'
    );
    if (journalRegex.hasMatch(urlToMatch)) {
      final String journalId = journalRegex.firstMatch(urlToMatch)!.group(1)!;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => OpenJournal(uniqueNumber: journalId),
        ),
      );
      return;
    }

    // Submission/View Link
    final RegExp viewRegex = RegExp(
        r'^(?:https?://(?:www\.)?furaffinity\.net)?/view/(\d+)(?:/.*)?(?:#.*)?$'
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

  void _copyProfileLinkToClipboard() {
    final profileLink = 'https://www.furaffinity.net/user/$sanitizedUsername/';
    Clipboard.setData(ClipboardData(text: profileLink)).then((_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Copied profile link!'),
          backgroundColor: Colors.green,
        ),
      );
    }).catchError((error) {
      print('Failed to copy profile link: $error');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to copy profile link.'),
          backgroundColor: Colors.red,
        ),
      );
    });
  }

  Future<void> _sendBlockUnblockPostRequest(String urlPath, String keyValue, {required bool shouldBlock}) async {
    String? cookieA = await _secureStorage.read(key: 'fa_cookie_a');
    String? cookieB = await _secureStorage.read(key: 'fa_cookie_b');
    final sfwValue = _sfwEnabled ? '1' : '0';

    if (cookieA == null || cookieB == null) {
      print('No cookies found. Please log in.');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please log in to perform this action.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final fullUrl = 'https://www.furaffinity.net$urlPath'; // e.g. "/unblock/username/"
    try {
      final response = await http.post(
        Uri.parse(fullUrl),
        headers: {
          'Cookie': 'a=$cookieA; b=$cookieB; sfw=$sfwValue',
          'Content-Type': 'application/x-www-form-urlencoded',
          'User-Agent': 'Mozilla/5.0 (compatible; YourApp/1.0)',
          'Referer': 'https://www.furaffinity.net/user/$username/',
        },
        body: {'key': keyValue},
      );

      if (response.statusCode == 302 || response.statusCode == 200) {
        print('${shouldBlock ? 'Block' : 'Unblock'} action successful.');
        await _fetchUserProfile();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${shouldBlock ? 'Author blocked' : 'Author unblocked'}'),
            backgroundColor: Colors.green,
          ),
        );
      }
      else {
        print('Failed to ${shouldBlock ? 'block' : 'unblock'}. Status code: ${response.statusCode}');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to ${shouldBlock ? 'block' : 'unblock'} author.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      print('Error during ${shouldBlock ? 'block' : 'unblock'}: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('An error occurred while trying to ${shouldBlock ? 'block' : 'unblock'} author.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }


  Future<void> _handleBlockUnblock() async {
    if (isBlocked) {
      if (unblockLink == null) {
        print('Unblock link not available.');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Cannot unblock author at this time.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      final unblockUri = Uri.parse(unblockLink!);
      final key = unblockUri.queryParameters['key'];
      if (key == null || key.isEmpty) {
        print('Unblock key not available.');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Cannot unblock author at this time.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      await _sendBlockUnblockPostRequest('/unblock/$username/', key, shouldBlock: false);
    } else {
      if (blockLink == null) {
        print('Block link not available.');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Cannot block author at this time.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      final blockUri = Uri.parse(blockLink!);
      final key = blockUri.queryParameters['key'];
      if (key == null || key.isEmpty) {
        print('Block key not available.');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Cannot block author at this time.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      await _sendBlockUnblockPostRequest('/block/$username/', key, shouldBlock: true);
    }
  }



  String _injectFACSS(String userDescHtml) {
    return '''
<html>
  <head>
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <base href="https://www.furaffinity.net/">

    <link rel="stylesheet" href="https://fonts.googleapis.com/css?family=Open+Sans:300,300i,400,400i,500,500i,600,600i,700,700i">
    <link rel="stylesheet" href="https://www.furaffinity.net/themes/beta/css/ui_theme_dark.css?u=2024112800">
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/wenk/1.0.8/wenk.min.css">
    
    <style>
      /* Force black background */
      html, body {
        margin: 0 !important;
        padding: 0 !important;
        background-color: #000 !important;
        color: #fff !important;
        font-family: 'Open Sans', sans-serif;
      }
      /* If you want a small padding around text, do it here: */
      body {
        margin: 8px; /* or remove if you want NO gray border at all */
      }
      /* Additional overrides to ensure FurAffinity’s CSS doesn’t set a gray BG anywhere else: */
      .container, .section-body, .userpage-layout-profile, .user-submitted-links {
        background-color: transparent !important;
      }
      img {
        max-width: 100% ; 
        height: auto ;
      }
      a.iconusername img {
        width: 60px ;
        height: auto ;
      }
      @media (max-width: 600px) {
        a.iconusername img {
          width: 40px ;
        }
      }
      @media (min-width: 1200px) {
        a.iconusername img {
          width: 80px ;
        }
      }
      code {
        display: block; 
        margin: 10px 0; 
      }
      .bbcode_center {
        text-align: center !important;
      }
      .bbcode_right {
        text-align: right !important;
      }
      .bbcode_left {
        text-align: left !important;
      }
      h1, h2, h3, h4, h5, h6 {
        text-align: center;
      }
      sup.bbcode_sup {
        display: block;
        text-align: center;
        margin-bottom: 10px;
      }
      a.auto_link.named_url {
        color: #ffeda4; 
        text-decoration: none;
      }
      a.auto_link.named_url:hover {
        text-decoration: underline;
      }
    </style>

    <script src="https://www.furaffinity.net/themes/beta/js/prototype.1.7.3.min.js"></script>
    <script src="https://www.furaffinity.net/themes/beta/js/common.js?u=2024112800"></script>
    <script src="https://www.furaffinity.net/themes/beta/js/script.js?u=2024112800"></script>
  </head>
  <body class="ui_theme_dark">
    $userDescHtml
  </body>
</html>
''';
  }

  // Method to send block/unblock request
  Future<void> _sendBlockUnblockRequest(String urlPath, {required bool shouldBlock}) async {
    String? cookieA = await _secureStorage.read(key: 'fa_cookie_a');
    String? cookieB = await _secureStorage.read(key: 'fa_cookie_b');
    final sfwValue = _sfwEnabled ? '1' : '0';

    if (cookieA == null || cookieB == null) {
      print('No cookies found. User might not be logged in.');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please log in to perform this action.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final fullUrl = 'https://www.furaffinity.net$urlPath';
    try {
      final response = await http.get(
        Uri.parse(fullUrl),
        headers: {
          'Cookie': 'a=$cookieA; b=$cookieB; sfw=$sfwValue',
          'User-Agent': 'Mozilla/5.0 (compatible; YourApp/1.0)',
        },
      );

      if (response.statusCode == 200) {
        print('${shouldBlock ? 'Block' : 'Unblock'} action successful.');

        await _fetchUserProfile();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${shouldBlock ? 'Author blocked' : 'Author unblocked'}'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        print('Failed to ${shouldBlock ? 'block' : 'unblock'}. Status code: ${response.statusCode}');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to ${shouldBlock ? 'block' : 'unblock'} author.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      print('Error during ${shouldBlock ? 'block' : 'unblock'}: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('An error occurred while trying to ${shouldBlock ? 'block' : 'unblock'} author.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget buildAnimatedBanner(BoxConstraints constraints) {

    double alignmentX = -1.0;
    if (profileBannerUrl?.contains('fa-banner') ?? false) {
      double shiftFraction = 30.0 / constraints.maxWidth * 2;
      alignmentX += shiftFraction;
    }

    return AnimatedBuilder(
      animation: _scrollController,
      builder: (context, child) {
        // Get current scroll offset
        double offset = _scrollController.hasClients ? _scrollController.offset : 0.0;

        // Compute new scale (from 1.0 to 0.8)
        double newScale;
        if (offset <= _bannerScaleStart) {
          newScale = 1.0;
        } else if (offset >= _bannerScaleEnd) {
          newScale = 1.0; // For example, scale down to 80%
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
            'https://www.furaffinity.net/themes/beta/img/banners/logo/fa-banner-summer.jpg',
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
        onTap: () {
          if (profileImageUrl != null) {

          }
        },
        child: CachedNetworkImage(
          imageUrl: profileImageUrl ?? '',
          width: avatarSize,
          height: avatarSize,
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

  /// Builds the main UI of the screen with unified scrolling.
  @override
  Widget build(BuildContext context) {
    // Define constants for the avatar and text alignment.
    const double avatarLeft = 16.0;
    const double avatarWidth = 90.0;
    const double marginBetweenAvatarAndText = 0.0;
    final double textLeftPadding = avatarLeft + avatarWidth + marginBetweenAvatarAndText;
    bool showLoadingIndicator = isLoading || !_webViewLoaded;

    return DefaultTabController(
      length: ProfileSection.values.length,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
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
                    icon: const Icon(Icons.arrow_back),
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
                      Text(
                        symbolUsername ?? 'Profile',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18.0,
                          fontWeight: FontWeight.bold,
                        ),
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
                          icon: const Icon(Icons.more_vert),
                          onPressed: () async {
                            final RenderBox button =
                            context.findRenderObject() as RenderBox;
                            final RenderBox overlay =
                            Overlay.of(context)
                                .context
                                .findRenderObject() as RenderBox;
                            final RelativeRect position =
                            RelativeRect.fromRect(
                              Rect.fromPoints(
                                button.localToGlobal(
                                  const Offset(0, 0),
                                  ancestor: overlay,
                                ),
                                button.localToGlobal(
                                  Offset(0, button.size.height + 10),
                                  ancestor: overlay,
                                ),
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
                                  child: Text(isBlocked
                                      ? 'Unblock author'
                                      : 'Block author'),
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
                                launchUrlString(
                                    'https://www.furaffinity.net/controls/troubletickets/');
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
                            color: Colors.black.withOpacity(0.3),
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
                        Stack(
                          children: [
                            Column(
                              crossAxisAlignment:
                              CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: double.infinity,
                                  color: const Color(0xFF111111),
                                  child: Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                        8.0, 0.0, 8.0, 8.0),
                                    child: Row(
                                      crossAxisAlignment:
                                      CrossAxisAlignment.center,
                                      children: [
                                        MediaQuery(
                                          data: MediaQuery.of(context)
                                              .copyWith(
                                              textScaleFactor: 1.0),
                                          child: Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                              CrossAxisAlignment
                                                  .start,
                                              children: [
                                                Padding(
                                                  padding: EdgeInsets.only(
                                                      left:
                                                      textLeftPadding),
                                                  child: FittedBox(
                                                    fit: BoxFit.scaleDown,
                                                    alignment: Alignment
                                                        .centerLeft,
                                                    child:
                                                    _buildProfileHeaderNameRow(),
                                                  ),
                                                ),
                                                Visibility(

                                                  visible: true,

                                                  maintainSize: true,
                                                  maintainAnimation: true,
                                                  maintainState: true,
                                                  child: Padding(
                                                    padding: EdgeInsets.only(
                                                      top: 4.0,
                                                      left: textLeftPadding,
                                                    ),
                                                    child: FittedBox(
                                                      fit: BoxFit.scaleDown,
                                                      alignment: Alignment.centerLeft,
                                                      child: Text(

                                                        (userTitle?.isNotEmpty ?? false) ? userTitle! : " ",
                                                        style: const TextStyle(
                                                          color: Colors.white70,
                                                          fontSize: 16.0,
                                                        ),
                                                        maxLines: 1,
                                                      ),
                                                    ),
                                                  ),
                                                )
                                                ,
                                                const SizedBox(
                                                    height: 30.0),
                                              ],
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        if (isOwnProfile)
                                          SizedBox(
                                            width: 110,
                                            height: 38,
                                            child: ElevatedButton(
                                              onPressed:
                                              _showEditProfileDialog,
                                              style: ElevatedButton
                                                  .styleFrom(
                                                backgroundColor:
                                                Colors.black,
                                                shape:
                                                RoundedRectangleBorder(
                                                  borderRadius:
                                                  BorderRadius
                                                      .circular(2),
                                                ),
                                                side:
                                                const BorderSide(
                                                  color: Color(
                                                      0xFFE09321),
                                                ),
                                              ),
                                              child: FittedBox(
                                                fit: BoxFit.scaleDown,
                                                child: const Text(
                                                  "Edit Profile",
                                                  style: TextStyle(
                                                    color:
                                                    Colors.white,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          )
                                        else
                                          Column(
                                            mainAxisSize:
                                            MainAxisSize.min,
                                            children: [
                                              SizedBox(
                                                width: 110,
                                                height: 38,
                                                child: ElevatedButton(
                                                  onPressed:
                                                      () => _handleWatchButtonPressed(),
                                                  style: ElevatedButton
                                                      .styleFrom(
                                                    backgroundColor:
                                                    Colors.black,
                                                    shape:
                                                    RoundedRectangleBorder(
                                                      borderRadius:
                                                      BorderRadius
                                                          .circular(
                                                          2),
                                                    ),
                                                    side:
                                                    const BorderSide(
                                                      color: Color(
                                                          0xFFE09321),
                                                    ),
                                                  ),
                                                  child: FittedBox(
                                                    fit: BoxFit.scaleDown,
                                                    child: Text(
                                                      isWatching
                                                          ? "-Watch"
                                                          : "+Watch",
                                                      style:
                                                      const TextStyle(
                                                        color: Colors
                                                            .white,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(
                                                  height: 5),
                                              SizedBox(
                                                width: 110,
                                                height: 38,
                                                child: ElevatedButton(
                                                  onPressed: () {
                                                    Navigator.push(
                                                      context,
                                                      MaterialPageRoute(
                                                        builder: (context) =>
                                                            NewMessageScreen(
                                                              recipient:
                                                              sanitizedUsername,
                                                            ),
                                                      ),
                                                    );
                                                  },
                                                  style: ElevatedButton
                                                      .styleFrom(
                                                    backgroundColor:
                                                    const Color(
                                                        0xFFE09321),
                                                    shape:
                                                    RoundedRectangleBorder(
                                                      borderRadius:
                                                      BorderRadius
                                                          .circular(
                                                          2),
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
                            Positioned(
                              bottom: 18.0,
                              left: 30.0,
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
        floatingActionButton: AnimatedBuilder(
          animation: _tabController,
          builder: (context, child) {
            bool showFab = _tabController.index != ProfileSection.Home.index;
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
        ),
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
        if (hasRealUserProfile)
          GestureDetector(
            onLongPressStart: (LongPressStartDetails details) async {
              // Get the overlay's RenderBox to convert the global position.
              final RenderBox overlay = Overlay.of(context)!.context.findRenderObject() as RenderBox;
              // Create a RelativeRect based on the press position.
              final RelativeRect position = RelativeRect.fromRect(
                details.globalPosition & const Size(40, 40),
                Offset.zero & overlay.size,
              );
              // Show the popup menu at that position.
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
                // Retrieve plain text from the webview and copy it.
                String? plainText = await _webViewKey.currentState?.getPlainText();
                if (plainText != null) {
                  await Clipboard.setData(ClipboardData(text: plainText));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Text copied to clipboard')),
                  );
                }
              } else if (selected == 'select') {

                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => UserDescriptionWebViewScreen(
                      sanitizedUsername: sanitizedUsername,
                    ),
                  ),
                );
              }
            },
            child: UserDescriptionWebView(
              key: _webViewKey,
              sanitizedUsername: sanitizedUsername,
              forceHybridComposition: false,
              onWebViewLoaded: (loaded) {
                setState(() {
                  _webViewLoaded = loaded;
                });
              },
            ),
          )
        ,
        const SizedBox(height: 16.0),
        if (featuredImageUrl != null && featuredImageTitle != null && featuredPostNumber != null)
          ...[
            _buildFeaturedSubmission(),
            const SizedBox(height: 8.0),
          ],
        if (hasRealUserProfile && userProfileTexts != null) _buildUserProfileSection(),
        const SizedBox(height: 8.0),
        if (contactInformationLinks.isNotEmpty) _buildContactInformationSection(),
        const SizedBox(height: 8.0),
        if (recentWatchers.isNotEmpty)
          UserGridSection(
            title: 'Recent Watchers',
            viewListText: 'Watched by $recentWatchersCount',
            users: recentWatchers,
            sanitizedUsername: sanitizedUsername,
          ),
        const SizedBox(height: 8.0),
        if (recentlyWatched.isNotEmpty)
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

  Widget _buildFeaturedSubmission() {
    if (featuredImageUrl == null ||
        featuredImageTitle == null ||
        featuredPostNumber == null) {
      return const SizedBox();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: Container(
        decoration: BoxDecoration(
          color: Color(0xFF1F1F1F),
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