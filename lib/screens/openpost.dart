import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:extended_text/extended_text.dart';
import 'package:html/dom.dart' as dom;
import 'package:FANotifier/screens/reply_screen.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:saver_gallery/saver_gallery.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:url_launcher/url_launcher_string.dart';
import 'package:like_button/like_button.dart';
import 'package:share_plus/share_plus.dart';
import 'package:linkify/linkify.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/timezone_provider.dart';
import '../utils/html_tags_debug.dart';
import '../utils/specialTextSpanBuilder.dart';
import '../widgets/PulsatingLoadingIndicator.dart';
import 'SubmissionDescriptionWebview.dart';
import 'add_comment_screen.dart';
import 'avatardownloadscreen.dart';
import 'edit_submission_screen.dart';
import 'editcommentscreen.dart';
import 'keyword_search_screen.dart';
import 'new_message.dart';
import 'user_profile_screen.dart';
import 'openjournal.dart';
import 'openpost.dart';

// Mapping from FA Timezone Names to IANA Timezones
final Map<String, String> faTimezoneToIana = {
  "International Date Line West": "Etc/GMT+12",
  "Samoa Standard Time": "Pacific/Pago_Pago",
  "Hawaiian Standard Time": "Pacific/Honolulu",
  "Alaskan Standard Time": "America/Anchorage",
  "Pacific Standard Time": "America/Los_Angeles",
  "Mountain Standard Time": "America/Denver",
  "Central Standard Time": "America/Chicago",
  "Eastern Standard Time": "America/New_York",
  "Caracas Standard Time": "America/Caracas",
  "Atlantic Standard Time": "America/Halifax",
  "Newfoundland Standard Time": "America/St_Johns",
  "Greenland Standard Time": "America/Godthab",
  "Mid-Atlantic Standard Time": "Etc/GMT-2",
  "Cape Verde Standard Time": "Atlantic/Cape_Verde",
  "Greenwich Mean Time": "Etc/GMT",
  "W. Europe Standard Time": "Europe/Berlin",
  "E. Europe Standard Time": "Europe/Minsk",
  "Russian Standard Time": "Europe/Moscow",
  "Iran Standard Time": "Asia/Tehran",
  "Arabian Standard Time": "Asia/Riyadh",
  "Afghanistan Standard Time": "Asia/Kabul",
  "West Asia Standard Time": "Asia/Tashkent",
  "India Standard Time": "Asia/Kolkata",
  "Nepal Standard Time": "Asia/Kathmandu",
  "Central Asia Standard Time": "Asia/Almaty",
  "Myanmar Standard Time": "Asia/Yangon",
  "North Asia Standard Time": "Asia/Krasnoyarsk",
  "North Asia East Standard Time": "Asia/Irkutsk",
  "Tokyo Standard Time": "Asia/Tokyo",
  "Cen. Australia Standard Time": "Australia/Adelaide",
  "West Pacific Standard Time": "Pacific/Port_Moresby",
  "Central Pacific Standard Time": "Pacific/Guadalcanal",
  "New Zealand Standard Time": "Pacific/Auckland",
};

class OpenPost extends StatefulWidget {
  final String imageUrl;
  final String uniqueNumber;

  const OpenPost({required this.imageUrl, required this.uniqueNumber, Key? key})
      : super(key: key);

  @override
  _OpenPostState createState() => _OpenPostState();
}

class _OpenPostState extends State<OpenPost> with WidgetsBindingObserver {
  bool _showFullPublicationDate = false;
  String? profileImageUrl;
  String? username;
  String? linkUsername;
  String? submissionTitle;
  String? fullViewImageUrl;
  String? submissionDescription;
  DateTime? publicationTime;
  int favoritesCount = 0;
  int viewCount = 0;
  int commentsCount = 0;
  List<Map<String, dynamic>> comments = [];
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  final TextEditingController _commentController = TextEditingController();
  Timer? _debounceTimer;
  bool _pendingFavoriteState = false;
  String? userTimezoneIanaName;
  String? currentUsername;
  bool isDstCorrectionApplied = false;
  String? favLink;
  String? unfavLink;
  bool isFavorited = false;
  int _likeButtonKeyCounter = 0;
  String? watchLink;
  String? unwatchLink;
  String? blockLink;
  bool isWatching = false;
  String? unblockLink;
  bool isBlocked = false;
  String? category;
  String? type;
  String? species;
  String? gender;
  String? size;
  String? fileSize;
  List<String> keywords = [];
  bool _isTyping = false;
  String? _blockKey;
  String? _unblockKey;
  bool _isClassicUserPage = false;

  bool _isWebViewVisible = true;

  double? imageWidth;
  double? imageHeight;

  bool isLoading = true;

  bool _detailsLoaded = false;
  bool _webViewLoaded = false;


  bool _sfwEnabled = true;

  bool _nsfwAllowed = false;
  final GlobalKey<SubmissionDescriptionWebViewState> _submissionWebViewKey =
  GlobalKey<SubmissionDescriptionWebViewState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    tz.initializeTimeZones();
    _loadSfwEnabled();

    _fetchPostDetails();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _commentController.dispose();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    final keyboardVisible = WidgetsBinding.instance.window.viewInsets.bottom > 0;
    setState(() => _isTyping = keyboardVisible);
  }

  List<String> iconBeforeUrls = [];
  List<String> iconAfterUrls = [];

  String _fixUrl(String url) {
    if (url.startsWith('//')) {
      return 'https:$url';
    } else if (url.startsWith('/')) {
      return 'https://www.furaffinity.net$url';
    }
    return url;
  }


  void _loadSfwEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _sfwEnabled = prefs.getBool('sfwEnabled') ?? true;
    });
  }


  Future<http.Response> _getWithSfwCookie(String url,
      {Map<String, String>? additionalHeaders, bool skipSfw = false}) async {
    String? cookieA = await _secureStorage.read(key: 'fa_cookie_a');
    String? cookieB = await _secureStorage.read(key: 'fa_cookie_b');
    String cookieHeader = '';
    if (cookieA != null && cookieB != null) {
      cookieHeader = 'a=$cookieA; b=$cookieB';
    }
    // Only add sfw cookie if user hasn't allowed NSFW for this post
    if (!skipSfw && _sfwEnabled && !_nsfwAllowed) {
      cookieHeader += '; sfw=1';
    }
    Map<String, String> headers = {
      'Cookie': cookieHeader,
      'User-Agent': 'Mozilla/5.0 (compatible; YourApp/1.0)',
    };
    if (additionalHeaders != null) {
      headers.addAll(additionalHeaders);
    }
    final response = await http.get(Uri.parse(url), headers: headers);

    // Check for NSFW marker in the HTML response only if NSFW not yet allowed.
    if (_sfwEnabled &&
        !_nsfwAllowed &&
        !skipSfw &&
        response.statusCode == 200 &&
        response.body.contains(
          '<div class="section-body alignleft">\n            <h2>System Message</h2>\n            This submission contains Mature or Adult content. To view this submission you must log in and enable the Mature or Adult content via Account Settings.\n        </div>',
        )) {
      bool userAgreed = await _showNSFWConfirmationDialog();
      if (userAgreed) {
        setState(() {
          _nsfwAllowed = true;
        });
        return await _getWithSfwCookie(url,
            additionalHeaders: additionalHeaders, skipSfw: true);
      } else {
        throw Exception("User declined to view NSFW content.");
      }
    }
    return response;
  }

  Future<bool> _showNSFWConfirmationDialog() async {
    return await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('NSFW Content'),
          content:
          const Text('This post is marked NSFW. Are you sure you want to view it?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              style: TextButton.styleFrom(
                backgroundColor: Colors.black,
              ),
              child: const Text('No', style: TextStyle(color: Colors.white)),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: TextButton.styleFrom(
                backgroundColor: Colors.black,
              ),
              child: const Text('Yes', style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    ) ??
        false;
  }

  Future<void> _fetchUserPageLinks() async {
    if (username == null) return;

    final userPageUrl = 'https://www.furaffinity.net/user/$username/';
    final response = await _getWithSfwCookie(userPageUrl);

    if (response.statusCode == 200) {
      String decodedBody;
      try {
        decodedBody = response.body;
      } on FormatException {
        decodedBody = utf8.decode(response.bodyBytes, allowMalformed: true);
      }
      final document = html_parser.parse(decodedBody);





      // Determine if the page is classic by checking data-static-path.
      final isClassic = document
          .querySelector('body')
          ?.attributes['data-static-path']
          ?.contains('themes/classic') ??
          false;

      // These variables will hold the links and keys.
      dom.Element? watchLinkElement;
      dom.Element? unwatchLinkElement;
      dom.Element? blockLinkElement;
      dom.Element? unblockLinkElement;
      String? blockKey;
      String? unblockKey;

      if (!isClassic) {
        // Modern (beta) style selectors.
        watchLinkElement =
            logQuery(document, 'a.button.standard.go[href^="/watch/"]');
        unwatchLinkElement =
            logQuery(document, 'a.button.standard.stop[href^="/unwatch/"]');
        blockLinkElement =
            logQuery(document, 'a.button.standard.stop[href^="/block/"]');
        unblockLinkElement =
            logQuery(document, 'a.button.standard.stop[href^="/unblock/"]');

        // Fallback if necessary.
        watchLinkElement ??= logQuery(document, 'a.cat[href^="/watch/"]');
        unwatchLinkElement ??= logQuery(document, 'a.cat[href^="/unwatch/"]');
        blockLinkElement ??= logQuery(document, 'a.cat[href^="/block/"]');
        unblockLinkElement ??= logQuery(document, 'a.cat[href^="/unblock/"]');
      } else {
        // Classic style selectors.
        // For watch/unwatch, classic pages wrap the link inside a <b> tag.
        watchLinkElement = logQuery(document, 'b > a[href^="/watch/"]');
        unwatchLinkElement = logQuery(document, 'b > a[href^="/unwatch/"]');

        // For block/unblock, classic pages use forms.
        final blockForm = document.querySelector('form[action^="/block/"]');
        if (blockForm != null) {
          final blockButton = blockForm.querySelector('button');
          if (blockButton != null && blockButton.text.trim().contains('+Block')) {
            blockLinkElement = dom.Element.tag('a');
            blockLinkElement.attributes['href'] = blockForm.attributes['action']!;
            // Store the key from the button’s value:
            blockKey = blockButton.attributes['value'];
          }
        }
        final unblockForm = document.querySelector('form[action^="/unblock/"]');
        if (unblockForm != null) {
          final unblockButton = unblockForm.querySelector('button');
          // Only use this if the button text indicates that the user is blocked.
          if (unblockButton != null && unblockButton.text.trim().contains('-Unblock')) {
            unblockLinkElement = dom.Element.tag('a');
            unblockLinkElement.attributes['href'] = unblockForm.attributes['action']!;
            // Store the key from the button’s value:
            unblockKey = unblockButton.attributes['value'];
          }
        }
      }


      setState(() {

        watchLink = watchLinkElement?.attributes['href'];
        unwatchLink = unwatchLinkElement?.attributes['href'];


        blockLink = blockLinkElement?.attributes['href'];
        unblockLink = unblockLinkElement?.attributes['href'];


        _blockKey = blockKey;
        _unblockKey = unblockKey;


        _isClassicUserPage = isClassic;

        // Determine state:
        // In modern pages, if an unwatch link is present, the user is already watching.
        // In classic pages, we assume the presence of the unblock form (and key) means the user is blocked.
        isWatching = (unwatchLinkElement != null);
        isBlocked = (unblockLinkElement != null);
      });
    } else {
      debugPrint('Failed to fetch user page links: ${response.statusCode}');
    }
  }



  Future<void> _showKeywordsDialog() async {
    if (keywords.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No keywords available.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Keywords'),
          content: SingleChildScrollView(
            child: Wrap(
              spacing: 8.0,
              runSpacing: 8.0,
              children: keywords.map((keyword) {
                return ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    _navigateToSearch(keyword);
                  },
                  child: Text(keyword),
                );
              }).toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  void _navigateToSearch(String keyword) {
    String formattedKeyword = '@keywords $keyword';

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => KeywordSearchScreen(initialKeyword: formattedKeyword),
      ),
    );
  }

  Future<void> _handleBlockUnblock() async {
    if (isBlocked) {
      if (unblockLink == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cannot unblock author at this time.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
      final unblockUri = Uri.parse(unblockLink!);

      final key = unblockUri.queryParameters['key'] ?? _unblockKey;
      if (key == null || key.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unblock key is missing.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
      await _sendBlockUnblockPostRequest('/unblock/$linkUsername/', key, shouldBlock: false);
    } else {
      if (blockLink == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cannot block author at this time.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
      final blockUri = Uri.parse(blockLink!);

      final key = blockUri.queryParameters['key'] ?? _blockKey;
      if (key == null || key.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Block key is missing.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
      await _sendBlockUnblockPostRequest('/block/$linkUsername/', key, shouldBlock: true);
    }
  }


  Future<void> _sendBlockUnblockPostRequest(String urlPath, String keyValue, {required bool shouldBlock}) async {
    String? cookieA = await _secureStorage.read(key: 'fa_cookie_a');
    String? cookieB = await _secureStorage.read(key: 'fa_cookie_b');
    final sfwValue = _sfwEnabled ? '1' : '0';

    if (cookieA == null || cookieB == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please log in to perform this action.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final fullUrl = 'https://www.furaffinity.net$urlPath';

    try {
      final response = await http.post(
        Uri.parse(fullUrl),
        headers: {
          'Cookie': 'a=$cookieA; b=$cookieB; sfw=$sfwValue',
          'User-Agent': 'Mozilla/5.0 (compatible; YourApp/1.0)',
          'Referer': 'https://www.furaffinity.net/user/$linkUsername/',
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: {'key': keyValue},
      );

      if (response.statusCode == 200 || response.statusCode == 302) {
        await _fetchUserPageLinks();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${shouldBlock ? 'Author blocked' : 'Author unblocked'}'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to ${shouldBlock ? 'block' : 'unblock'} author.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('An error occurred while trying to ${shouldBlock ? 'block' : 'unblock'} author.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }



  Future<void> _sendWatchUnwatchRequest(String urlPath,
      {required bool shouldWatch}) async {
    String? cookieA = await _secureStorage.read(key: 'fa_cookie_a');
    String? cookieB = await _secureStorage.read(key: 'fa_cookie_b');

    if (cookieA == null || cookieB == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please log in to perform this action.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final fullUrl = 'https://www.furaffinity.net$urlPath';
    try {
      final response = await _getWithSfwCookie(fullUrl);
      if (response.statusCode == 200) {
        await _fetchUserPageLinks();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '${shouldWatch ? 'Now watching $username' : 'Stopped watching $username'}'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
            Text('Failed to ${shouldWatch ? 'watch' : 'unwatch'} user.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'An error occurred while trying to ${shouldWatch ? 'watch' : 'unwatch'} user.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _handleWatchButtonPressed() async {
    if (isWatching) {
      if (unwatchLink == null) return;
      await _sendWatchUnwatchRequest(unwatchLink!, shouldWatch: false);
    } else {
      if (watchLink == null) return;
      await _sendWatchUnwatchRequest(watchLink!, shouldWatch: true);
    }
  }

  Future<void> hideComment(String hideLink, String commentId) async {
    final shouldHide = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Confirmation"),
          content: const Text(
            "Are you sure you want to hide this comment?",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text("Yes"),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text("Cancel"),
            ),
          ],
        );
      },
    );

    if (shouldHide == true) {
      try {
        String? cookieA = await _secureStorage.read(key: 'fa_cookie_a');
        String? cookieB = await _secureStorage.read(key: 'fa_cookie_b');

        if (cookieA == null || cookieB == null) {
          return;
        }

        final response = await _getWithSfwCookie(hideLink);
        if (response.statusCode == 200) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Comment successfully hidden!"),
              backgroundColor: Colors.green,
            ),
          );
          await _fetchPostDetails();
        } else {
          debugPrint('Failed to hide comment. Status code: ${response.statusCode}');
        }
      } catch (e) {
        debugPrint('Error hiding comment: $e');
      }
    }
  }

  Future<void> _fetchFavoriteLinks() async {
    final cookieA = await _secureStorage.read(key: 'fa_cookie_a');
    final cookieB = await _secureStorage.read(key: 'fa_cookie_b');

    // If not logged in, skip
    if (cookieA == null || cookieB == null) {
      return;
    }

    final postUrl = 'https://www.furaffinity.net/view/${widget.uniqueNumber}/';
    final response = await _getWithSfwCookie(postUrl);

    if (response.statusCode == 200) {
      String decodedBody;
      try {
        decodedBody = response.body;
      } on FormatException {
        decodedBody = utf8.decode(response.bodyBytes, allowMalformed: true);
      }
      final document = html_parser.parse(decodedBody);


      // Modern (beta) style
      var favLinkElement = logQuery(document, '.favorite-nav a[href^="/fav/"]');
      var unfavLinkElement = logQuery(document, '.favorite-nav a[href^="/unfav/"]');

      // Classic fallback
      if (favLinkElement == null) {
        favLinkElement = logQuery(document, 'a[href^="/fav/"].button');
      }
      if (unfavLinkElement == null) {
        unfavLinkElement = logQuery(document, 'a[href^="/unfav/"].button');
      }

      setState(() {
        favLink = favLinkElement?.attributes['href'];
        unfavLink = unfavLinkElement?.attributes['href'];
        isFavorited = (unfavLink != null);

      });
    } else {
      debugPrint('Failed to fetch favorite links: ${response.statusCode}');
    }
  }


  Future<void> _fetchPostDetails() async {
    setState(() => isLoading = true);

    final cookieA = await _secureStorage.read(key: 'fa_cookie_a');
    final cookieB = await _secureStorage.read(key: 'fa_cookie_b');

    if (cookieA == null || cookieB == null) {
      setState(() => isLoading = false);
      return;
    }

    final postUrl = 'https://www.furaffinity.net/view/${widget.uniqueNumber}/';
    final response = await _getWithSfwCookie(postUrl);



    if (response.statusCode != 200) {
      debugPrint('Failed to fetch post details: ${response.statusCode}');
      return;
    }

    // Parse the document
    String decodedBody;

    try {
      decodedBody = response.body;
    } on FormatException {
      decodedBody = utf8.decode(response.bodyBytes, allowMalformed: true);
    }
    final document = html_parser.parse(decodedBody);

    await _fetchComments(decodedBody);

    // 1) Current logged-in username
    var currentUserElem = logQuery(document, '#my-username');
    if (currentUserElem == null) {
      // Classic fallback
      currentUserElem = logQuery(document, 'span#my-username');
    }
    if (currentUserElem != null) {
      final fullText = currentUserElem.text.trim();
      final match = RegExp(r'\(([^)]+)\)').firstMatch(fullText);
      if (match != null && match.groupCount >= 1) {
        currentUsername = match.group(1)?.trim();
      } else {
        currentUsername = fullText;
      }
    }

    // 2) Submission author data

    var profileIcon = logQuery(
      document,
        '.submission-id-avatar img, td.alt1 .avatar img, .classic-submission-title.avatar a img, .classic-submissiont-title.avatar a img'

    );



    var usernameAnchor = logQuery(document, '.submission-id-sub-container a[href^="/user/"]');
    if (usernameAnchor == null) {
      // classic fallback
      usernameAnchor = logQuery(document, '.classic-submission-title.information span.c-usernameBlockSimple.username-underlined a[href^="/user/"]');


    }


    String? extractedUsername;
    final userSpan = usernameAnchor?.querySelector('span');
    if (userSpan != null) {
      extractedUsername = userSpan.text.trim();
    } else if (usernameAnchor != null) {
      extractedUsername = usernameAnchor.text.trim();
    }


    String? linkUser;
    final href = usernameAnchor?.attributes['href'];
    if (href != null) {
      final parts = href.split('/');
      if (parts.length >= 3) {
        linkUser = parts[2]; // e.g. /user/username/ => username
      }
    }

    // 3) Submission title
    var titleElem = logQuery(document, '.submission-title h2 p, .classic-submission-title.information h2');

    // 4) Full image
    var imageElem = logQuery(document, '.submission-area img#submissionImg[src], img#submissionImg[src]');
    String? fullViewUrl;
    if (imageElem != null) {
      fullViewUrl = imageElem.attributes['data-fullview-src']?.replaceFirst('//', 'https://');
    }


    // 5) Description
    var descElem = logQuery(document, '.submission-description.user-submitted-links');
    if (descElem == null) {
      descElem = logQuery(
          document,
          // Look for either the modern .submission-description or the classic td.alt1
          '.submission-description, td.alt1[width="70%"][valign="top"][align="left"][style*="padding:8px"]'
      );
    }


    // 6) Publication time
    var publicationTimeElem = logQuery(
      document,
      '.submission-id-sub-container .popup_date, td.alt1.stats-container .popup_date',
    );
    if (publicationTimeElem == null) {
      publicationTimeElem = logQuery(document, '.popup_date');
    }

    // 7) View count
    var viewCountElem = logQuery(document, '.views .font-large');


    if (viewCountElem == null) {
      // Fallback: search for a <b> with text "Views:" in the stats container.
      final statsContainer = logQuery(document, 'td.alt1.stats-container');
      if (statsContainer != null) {
        final boldElements = statsContainer.getElementsByTagName('b');
        String? viewsText;
        for (var b in boldElements) {
          if (b.text.trim() == 'Views:') {

            final nodes = b.parent?.nodes;
            if (nodes != null) {
              final index = nodes.indexOf(b);
              if (index != -1 && index < nodes.length - 1) {

                viewsText = nodes[index + 1].text?.trim();
              }
            }
            break;
          }
        }
        if (viewsText != null && viewsText.isNotEmpty) {

          viewCountElem = dom.Element.tag('span');
          viewCountElem.text = viewsText;
          debugPrint("DEBUG: Parsed view count using classic fallback: ${viewCountElem.text}");
        }
      }
    }

    final parsedViewCount = int.tryParse(viewCountElem?.text.trim() ?? '0') ?? 0;



    // 8) Comments count
    var commentsCountElem = logQuery(document, '.comments .font-large');


    // Fallback: if still null, try to parse from the stats container.
    if (commentsCountElem == null) {
      final statsContainer = logQuery(document, 'td.alt1.stats-container');
      if (statsContainer != null) {
        // Get all <b> elements in the container.
        final boldElements = statsContainer.getElementsByTagName('b');
        String? commentsText;
        for (var b in boldElements) {
          if (b.text.trim() == 'Comments:') {
            final nodes = b.parent?.nodes;
            if (nodes != null) {
              final index = nodes.indexOf(b);
              if (index != -1 && index < nodes.length - 1) {
                commentsText = nodes[index + 1].text?.trim();
              }
            }
            break;
          }
        }
        if (commentsText != null && commentsText.isNotEmpty) {
          commentsCountElem = dom.Element.tag('span');
          commentsCountElem.text = commentsText;
          debugPrint("DEBUG: Parsed comments count using fallback: ${commentsCountElem.text}");
        }
      }
    }

    final parsedCommentsCount = int.tryParse(commentsCountElem?.text.trim() ?? '0') ?? 0;


    // 9) Info section
    var infoSection = logQuery(document, 'section.info.text, td.alt1.stats-container');

    String? localCategory;
    String? localType;
    String? localSpecies;
    String? localGender;
    String? localSize;
    String? localFileSize;
    final isClassic = document
        .querySelector('body')
        ?.attributes['data-static-path']
        ?.contains('themes/classic') ?? false;

    if (infoSection != null) {
      if (!isClassic) {
        // Modern (Beta) Style.
        final divs = infoSection.querySelectorAll('div');
        for (var div in divs) {
          final strong = div.querySelector('strong.highlight');
          if (strong == null) continue;
          final label = strong.text.trim();
          switch (label) {
            case 'Category':
              localCategory = div.querySelector('.category-name')?.text.trim();
              break;
            case 'Theme':
              localType = div.querySelector('.type-name')?.text.trim();
              break;
            case 'Species':
              localSpecies = div.querySelector('span')?.text.trim();
              break;
            case 'Gender':
              localGender = div.querySelector('span')?.text.trim();
              break;
            case 'Size':
              localSize = div.querySelector('span')?.text.trim();
              break;
            case 'File Size':
              localFileSize = div.querySelector('span')?.text.trim();
              break;
          }
        }
      } else {
        // Classic Fallback
        final infoHtml = infoSection.innerHtml;
        final categoryMatch = RegExp(
          r'<b>\s*Category:\s*</b>\s*([^<]+)<br\s*/?>',
          caseSensitive: false,
        ).firstMatch(infoHtml);
        if (categoryMatch != null) {
          localCategory = categoryMatch.group(1)?.trim();
        }
        final themeMatch = RegExp(
          r'<b>\s*Theme:\s*</b>\s*([^<]+)<br\s*/?>',
          caseSensitive: false,
        ).firstMatch(infoHtml);
        if (themeMatch != null) {
          localType = themeMatch.group(1)?.trim();
        }
        final speciesMatch = RegExp(
          r'<b>\s*Species:\s*</b>\s*([^<]+)<br\s*/?>',
          caseSensitive: false,
        ).firstMatch(infoHtml);
        if (speciesMatch != null) {
          localSpecies = speciesMatch.group(1)?.trim();
        }
        final genderMatch = RegExp(
          r'<b>\s*Gender:\s*</b>\s*([^<]+)<br\s*/?>',
          caseSensitive: false,
        ).firstMatch(infoHtml);
        if (genderMatch != null) {
          localGender = genderMatch.group(1)?.trim();
        }
        final sizeMatch = RegExp(
          r'<b>\s*Resolution:\s*</b>\s*([0-9]+)\s*x\s*([0-9]+)<br\s*/?>',
          caseSensitive: false,
        ).firstMatch(infoHtml);
        if (sizeMatch != null) {
          localSize =
          '${sizeMatch.group(1)?.trim()} x ${sizeMatch.group(2)?.trim()}';
        }
        final fileSizeMatch = RegExp(
          r'<b>\s*File Size:\s*</b>\s*([^<]+)<br\s*/?>',
          caseSensitive: false,
        ).firstMatch(infoHtml);
        if (fileSizeMatch != null) {
          localFileSize = fileSizeMatch.group(1)?.trim();
        }
      }
    }

    double? localImageWidth;
    double? localImageHeight;




    if (infoSection != null) {
      if (!isClassic) {
        final divs = infoSection.querySelectorAll('div');
        for (var div in divs) {
          final strong = div.querySelector('strong.highlight');
          if (strong != null && strong.text.trim() == 'Size') {
            final sizeText = div.querySelector('span')?.text.trim(); // e.g. "1377 x 970"
            if (sizeText != null) {
              final dims = sizeText.toLowerCase().split('x');
              if (dims.length >= 2) {
                localImageWidth = double.tryParse(dims[0].trim());
                localImageHeight = double.tryParse(dims[1].trim());
                break;
              }
            }
          }
        }
      } else {
        // Classic style: Look in the Upload Specifications block.
        final infoHtml = infoSection.innerHtml;
        final resMatch = RegExp(
          r'<b>\s*Resolution:\s*</b>\s*([0-9]+)\s*x\s*([0-9]+)<br\s*/?>',
          caseSensitive: false,
        ).firstMatch(infoHtml);

        if (resMatch != null) {
          localImageWidth = double.tryParse(resMatch.group(1)!.trim());
          localImageHeight = double.tryParse(resMatch.group(2)!.trim());
          final formattedResolution = '${localImageWidth?.toInt()} x ${localImageHeight?.toInt()}';

        }
      }
    }




    // 10) Keywords
    var tagsSection = logQuery(document, 'section.tags-row');
    if (tagsSection == null) {
      tagsSection = logQuery(document, '#keywords');
    }
    List<String> extractedKeywords = [];
    if (tagsSection != null) {
      // Beta
      var tagElems = tagsSection.querySelectorAll('span.tags a[href^="/search/@keywords"]');
      if (tagElems.isEmpty) {
        // Classic fallback
        tagElems = tagsSection.querySelectorAll('a[href*="/search/"]');
      }
      for (var t in tagElems) {
        final kw = t.text.trim();
        if (kw.isNotEmpty && !extractedKeywords.contains(kw)) {
          extractedKeywords.add(kw);
        }
      }
    }

    // 11) Favorite count
    var favCountElem = logQuery(document, '.favorites .font-large');


    if (favCountElem == null) {
      // Fallback: Look in the stats container.
      final statsContainer = logQuery(document, 'td.alt1.stats-container');
      if (statsContainer != null) {
        final boldElements = statsContainer.getElementsByTagName('b');
        String? favText;
        for (var b in boldElements) {
          if (b.text.trim() == 'Favorites:') {
            final parentNodes = b.parent?.nodes;
            if (parentNodes != null) {
              int idx = parentNodes.indexOf(b);
              while (idx + 1 < parentNodes.length) {
                idx++;
                final sibling = parentNodes[idx];
                if (sibling is dom.Element && sibling.localName == 'a') {
                  favText = sibling.text.trim();
                  break;
                } else if (sibling is dom.Text) {
                  final trimmed = sibling.text.trim();
                  if (trimmed.isNotEmpty) {
                    favText = trimmed;
                    break;
                  }
                }
              }
            }
            break;
          }
        }
        if (favText != null && favText.isNotEmpty) {
          favCountElem = dom.Element.tag('span');
          favCountElem.text = favText;
          debugPrint("DEBUG: Parsed favorite count using fallback: ${favCountElem.text}");
        }
      }
    }

    final localFavoritesCount = int.tryParse(favCountElem?.text.trim() ?? '0') ?? 0;







    // 12) Fav/unfav links

    // Modern selectors first:
    var favLinkElement = logQuery(document, '.favorite-nav a[href^="/fav/"]');
    if (favLinkElement == null) {
      favLinkElement = logQuery(document, 'a[href^="/fav/"].button');
    }
    var unfavLinkElement = logQuery(document, '.favorite-nav a[href^="/unfav/"]');
    if (unfavLinkElement == null) {
      unfavLinkElement = logQuery(document, 'a[href^="/unfav/"].button');
    }

    // Fallback for classic pages:
    if (favLinkElement == null) {
      final actionsContainers = logQueryAll(document, 'div.alt1.actions.aligncenter');
      for (var actionsDiv in actionsContainers) {
        // Loop over each <b> element inside.
        final boldElements = actionsDiv.getElementsByTagName('b');
        for (var b in boldElements) {
          final a = b.querySelector('a');
          if (a != null &&
              a.attributes['href'] != null &&
              a.attributes['href']!.startsWith('/fav/')) {
            favLinkElement = a;
            break;
          }
        }
        if (favLinkElement != null) break;
      }
    }

    if (unfavLinkElement == null) {
      final actionsContainers = logQueryAll(document, 'div.alt1.actions.aligncenter');
      for (var actionsDiv in actionsContainers) {
        final boldElements = actionsDiv.getElementsByTagName('b');
        for (var b in boldElements) {
          final a = b.querySelector('a');
          if (a != null &&
              a.attributes['href'] != null &&
              a.attributes['href']!.startsWith('/unfav/')) {
            unfavLinkElement = a;
            break;
          }
        }
        if (unfavLinkElement != null) break;
      }
    }

    var localFavLink = favLinkElement?.attributes['href'];
    var localUnfavLink = unfavLinkElement?.attributes['href'];

    debugPrint("DEBUG: localFavLink: $localFavLink");
    debugPrint("DEBUG: localUnfavLink: $localUnfavLink");



    // 13) Parse time
    String? rawTime = publicationTimeElem?.attributes['title']?.trim();
    rawTime ??= publicationTimeElem?.text.trim();

    setState(() {
      username = extractedUsername;
      linkUsername = linkUser;

      profileImageUrl = profileIcon?.attributes['src']
          ?.replaceFirst('//', 'https://');
      submissionTitle = titleElem?.text.trim();

      fullViewImageUrl = imageElem?.attributes['data-fullview-src']
          ?.replaceFirst('//', 'https://');
      fullViewImageUrl ??= imageElem?.attributes['src']
          ?.replaceFirst('//', 'https://');

      submissionDescription = fixTruncatedLinks(
          descElem?.outerHtml.replaceAll('//', 'https://') ?? ''
      );

      if (rawTime != null && rawTime.isNotEmpty) {
        _parsePublicationTime(rawTime);
      }

      favoritesCount = localFavoritesCount;
      viewCount = parsedViewCount;
      commentsCount = parsedCommentsCount;

      favLink = localFavLink;
      unfavLink = localUnfavLink;
      isFavorited = (unfavLink != null);

      category = localCategory;
      type = localType;
      species = localSpecies;
      gender = localGender;
      size = localSize;
      fileSize = localFileSize;
      keywords = extractedKeywords;

      imageWidth = localImageWidth;
      imageHeight = localImageHeight;
    });

    // Also fetch watch/block links for that user
    await _fetchUserPageLinks();

    //setState(() => isLoading = false);

    setState(() {
      _detailsLoaded = true;
    });


  }

  Future<void> _fetchComments(String body) async {
    var document = html_parser.parse(body);

    // Grab both modern and classic comment containers
    var commentContainers =
    document.querySelectorAll('.comment_container, table.container-comment');

    List<Map<String, dynamic>> loadedComments = [];
    String? currentUser = username;

    print("Number of comment containers found: ${commentContainers.length}");

    for (var commentContainer in commentContainers) {
      // Determine if this container is "classic" (table) or "modern" (div)
      bool isClassic = (commentContainer.localName == 'table');

      final innerContainer = commentContainer.querySelector('comment-container');
      // Detect deletion by checking if the inner container has the class "deleted-comment-container"
      bool isDeleted = innerContainer?.classes.contains('deleted-comment-container') ?? false;

      bool isClassicDeleted = false;
      dom.Element? classicDeletedCell;
      if (isClassic) {
        classicDeletedCell = commentContainer.querySelector('td.comment-deleted');
        if (classicDeletedCell != null) {

          isClassicDeleted = true;
          isDeleted = true;
        }
      }

      // Handle width: in modern style, from inline style (style="width:97%"),
      // in classic style from the table's width="97%" attribute
      double widthPercent = 100.0;
      if (!isClassic) {
        // Modern style
        String? style = commentContainer.attributes['style'];
        if (style != null) {
          RegExp widthRegex = RegExp(r'width\s*:\s*(\d+(?:\.\d+)?)%');
          Match? match = widthRegex.firstMatch(style);
          if (match != null) {
            widthPercent = double.tryParse(match.group(1) ?? '') ?? 100.0;
          }
        }
      } else {
        // Classic style
        String? tableWidth = commentContainer.attributes['width'];
        if (tableWidth != null) {
          // The table's width attribute might be "97%" – strip '%' and parse
          String numericPart = tableWidth.replaceAll('%', '').trim();
          double? tableWidthValue = double.tryParse(numericPart);
          if (tableWidthValue != null) {
            widthPercent = tableWidthValue;
          }
        }
      }

      // Get the profile image; in modern: '.avatar img', in classic: '<img class="avatar" >'
      String? profileImage = commentContainer
          .querySelector('img.avatar, .avatar img')
          ?.attributes['src']
          ?.replaceFirst('//', 'https://');


      final displayNameAnchor = commentContainer
          .querySelector('a.c-usernameBlock__displayName span.js-displayName');
      String? displayName = displayNameAnchor?.text.trim();

      // Extract userName (the “@username”)
      String parsedSymbol = '';
      String parsedUserName = '';
      final userNameAnchor =
      commentContainer.querySelector('a.c-usernameBlock__userName');
      if (userNameAnchor != null) {
        final symbolElement =
        userNameAnchor.querySelector('span.c-usernameBlock__symbol');
        if (symbolElement != null) {
          parsedSymbol = symbolElement.text.trim();
        }
        String fullText = userNameAnchor.text.trim();
        parsedUserName = fullText.replaceFirst(parsedSymbol, '').trim();
      }
      final effectiveUserName = parsedUserName.isNotEmpty ? parsedUserName : displayName;
      final usernameForUI = effectiveUserName ?? "Anonymous";

      // User title (classic might be <span class="custom-title hideonmobile font-small">...</span>)
      // Modern is <comment-title class="custom-title">...</comment-title>
      final userTitleElement = commentContainer.querySelector(
          'comment-title.custom-title, span.custom-title'
      );
      String? userTitle = userTitleElement?.text.trim();

      var iconBeforeElements =
      commentContainer.querySelectorAll('usericon-block-before img');
      List<String> iconBeforeUrls = iconBeforeElements.map((elem) {
        String? src = elem.attributes['src'];
        if (src != null) {
          if (src.startsWith('//')) {
            return 'https:$src';
          } else if (src.startsWith('/')) {
            return 'https://www.furaffinity.net$src';
          }
          return src;
        }
        return '';
      }).where((url) => url.isNotEmpty).toList();

      var iconAfterElements =
      commentContainer.querySelectorAll('usericon-block-after img');
      List<String> iconAfterUrls = iconAfterElements.map((elem) {
        String? src = elem.attributes['src'];
        if (src != null) {
          if (src.startsWith('//')) {
            return 'https:$src';
          } else if (src.startsWith('/')) {
            return 'https://www.furaffinity.net$src';
          }
          return src;
        }
        return '';
      }).where((url) => url.isNotEmpty).toList();

      // Parse the comment text.
      // Modern: .comment_text
      // Classic normal: .message-text / .replyto-message
      String? commentText;
      String? commentHtml;
      final commentTextElement = commentContainer.querySelector(
          '.comment_text, .message-text, .replyto-message'
      );



      if (isClassicDeleted && classicDeletedCell != null) {
        commentText = classicDeletedCell.text.trim();
        // e.g. “Comment hidden by its owner”
        commentHtml = classicDeletedCell.innerHtml;
      }

      if (commentTextElement != null) {
        String rawHtml = commentTextElement.innerHtml;
        // Convert emoji <i> tags into placeholders.
        rawHtml = rawHtml.replaceAllMapped(
          RegExp(r'<i\s+class="([^"]+)"\s*\/?>'),
              (match) {
            String classAttr = match.group(1)!;
            return '[' + classAttr.replaceAll(' ', '-') + ']';
          },
        );
        // Fix truncated links.
        rawHtml = fixTruncatedLinks(rawHtml);
        final commentDoc = html_parser.parse(rawHtml);
        commentDoc.querySelectorAll('a.auto_link_shortened').forEach((element) {
          final fullLink = element.attributes['title'] ?? element.attributes['href'];
          if (fullLink != null) {
            element.innerHtml = fullLink;
          }
        });

        commentText = commentDoc.body?.text.trim();
        commentHtml = commentDoc.body?.innerHtml ?? rawHtml;
      }


      // Parse date info (modern has .popup_date)
      final dateElem = commentContainer.querySelector('.popup_date');
      final popupDateFull = dateElem?.attributes['title']?.trim();
      final popupDateRelative = dateElem?.text.trim();

      // Parse hide/unhide link

      final hideLinkModern = commentContainer.querySelector('comment-hide a');
      // Parse hide/unhide link for both modern and classic comments
      String? hideLink;
      final unhideLink = commentContainer.querySelector('a[href*="action=unhide_comment"]');
      if (unhideLink != null) {
        hideLink = unhideLink.attributes['href'];
      } else {
        // Fallback: looks for a hide link with "action=hide_comment"
        final hideLinkCandidate = commentContainer.querySelector('a[href*="action=hide_comment"]');
        if (hideLinkCandidate != null) {
          hideLink = hideLinkCandidate.attributes['href'];
        }
      }


      if (hideLink != null && hideLink.startsWith('/')) {
        hideLink = 'https://www.furaffinity.net$hideLink';
      }

      // Parse comment ID:
      // Modern: from a “replyto” link
      // Classic: from the table id="cid:###"
      String? commentId;
      final replyLinkHref = commentContainer.querySelector('.replyto_link')
          ?.attributes['href'];
      if (replyLinkHref != null) {
        final match = RegExp(r'/replyto/[\w]+/(\d+)/').firstMatch(replyLinkHref);
        if (match != null) {
          commentId = match.group(1);
        }
      }
      if (commentId == null) {
        String? tableId = commentContainer.id; // e.g. "cid:167658070"
        if (tableId != null && tableId.startsWith('cid:')) {
          commentId = tableId.replaceFirst('cid:', '').trim();
        }
      }

      // Parse edit link
      // 1) Modern <comment-edit><a href=...>
      // 2) Classic <a class="edit-link" href="/view/.../edit/...">
      final editLinkModern = commentContainer.querySelector('comment-edit a');
      String? editLink;
      if (editLinkModern != null) {
        editLink = editLinkModern.attributes['href'];
      } else {
        final editLinkClassic = commentContainer.querySelector('a.edit-link[href*="/edit/"]');
        if (editLinkClassic != null) {
          editLink = editLinkClassic.attributes['href'];
        }
      }
      if (editLink != null && editLink.startsWith('/')) {
        editLink = 'https://www.furaffinity.net$editLink';
      }
      final replyLinkElement = commentContainer.querySelector('td.reply-link a');
      String? replyLink = replyLinkElement?.attributes['href'];

      // Build comment map
      Map<String, dynamic> commentMap = {
        'profileImage': profileImage,
        'displayName': displayName,
        'userName': effectiveUserName,
        'username': usernameForUI,
        'symbol': parsedSymbol.isNotEmpty ? parsedSymbol : '@',
        'userTitle': userTitle,
        'replyLink': replyLink,
        'text': commentText,
        'commentHtml': commentHtml,
        'width': widthPercent,
        'isOP': commentContainer.querySelector('.comment_op_marker') != null,
        'popupDateFull': popupDateFull,
        'popupDateRelative': popupDateRelative,
        'showFullDate': false,
        'commentId': commentId,
        'iconBeforeUrls': iconBeforeUrls,
        'iconAfterUrls': iconAfterUrls,
        'deleted': isDeleted,   // or “hidden”
        'hideLink': hideLink,
        'editLink': editLink,
      };

      // Deleted comment logic
      if (isDeleted) {
        // If modern, the text area might contain "Unhide Comment ..."
        // For classic, we might have "Comment hidden by its owner"

        String hiddenText = commentText ?? "";
        hiddenText = hiddenText.replaceAll(
            RegExp(r'Unhide\s+Comment(\s*<span.*?<\/span>)?', caseSensitive: false),
            ''
        ).trim();
        commentMap['text'] = hiddenText;

        // Removes avatar/username details for deleted or hidden comments
        commentMap['profileImage'] = null;
        commentMap['displayName'] = null;
        commentMap['userName'] = null;
      } else {

        if (profileImage == null || effectiveUserName == null || commentText == null) {
          print("Skipping comment due to missing important fields.");
          continue;
        }
      }

      // Add final comment object
      loadedComments.add(commentMap);
    }

    print("Total loaded comments: ${loadedComments.length}");

    setState(() {
      comments = loadedComments;
      commentsCount = loadedComments.length;
    });
  }



  Future<void> _handleDeletePost() async {
    String? cookieA = await _secureStorage.read(key: 'fa_cookie_a');
    String? cookieB = await _secureStorage.read(key: 'fa_cookie_b');

    if (cookieA == null || cookieB == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please log in to perform this action.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final url = 'https://www.furaffinity.net/controls/submissions/';
    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Cookie': 'a=$cookieA; b=$cookieB',
          'User-Agent': 'Mozilla/5.0 (compatible; YourApp/1.0)',
          'Referer': 'https://www.furaffinity.net/view/${widget.uniqueNumber}/',
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: {
          'submission_ids[]': widget.uniqueNumber,
          'delete_submissions_submit': '1',
        },
      );

      if (response.statusCode == 200) {
        var document = html_parser.parse(response.body);
        var confirmInput = document.querySelector('button[name="confirm"]');
        var confirmValue = confirmInput?.attributes['value'];
        var deleteSubmissionsSubmitInput =
        document.querySelector('input[name="delete_submissions_submit"]');
        var deleteSubmissionsSubmitValue =
        deleteSubmissionsSubmitInput?.attributes['value'];
        var submissionIdsInput =
        document.querySelector('input[name="submission_ids[]"]');
        var submissionIdValue = submissionIdsInput?.attributes['value'];

        if (confirmValue == null ||
            deleteSubmissionsSubmitValue == null ||
            submissionIdValue == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to prepare deletion.'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }

        _showDeleteConfirmationDialog(
            confirmValue, deleteSubmissionsSubmitValue, submissionIdValue);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to initiate deletion.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e, stackTrace) {
      debugPrint('Error initiating deletion: $e');
      debugPrint('Stack trace: $stackTrace');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('An unexpected error occurred.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showDeleteConfirmationDialog(String confirmValue,
      String deleteSubmissionsSubmitValue, String submissionIdValue) {
    TextEditingController passwordController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Confirm Deletion'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'The following submission is going to be removed from your gallery:',
                ),
                const SizedBox(height: 8),
                if (fullViewImageUrl != null)
                  Image.network(
                    fullViewImageUrl!,
                    height: 150,
                  ),
                const SizedBox(height: 8),
                const Text(
                  'This procedure is irreversible.\n\nPlease enter your account password below as a confirmation.',
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Password',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
            ElevatedButton(
              onPressed: () {
                String password = passwordController.text;
                if (password.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Password cannot be empty.'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }
                Navigator.of(context).pop();
                _confirmDeletion(confirmValue, deleteSubmissionsSubmitValue,
                    submissionIdValue, password);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red, // Button background color
              ),
              child: const Text('Confirm Deletion'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _confirmDeletion(String confirmValue,
      String deleteSubmissionsSubmitValue, String submissionIdValue,
      String password) async {
    String? cookieA = await _secureStorage.read(key: 'fa_cookie_a');
    String? cookieB = await _secureStorage.read(key: 'fa_cookie_b');

    if (cookieA == null || cookieB == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please log in to perform this action.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final url = 'https://www.furaffinity.net/controls/submissions/';
    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Cookie': 'a=$cookieA; b=$cookieB',
          'User-Agent': 'Mozilla/5.0 (compatible; YourApp/1.0)',
          'Referer': 'https://www.furaffinity.net/controls/submissions/',
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: {
          'delete_submissions_submit': deleteSubmissionsSubmitValue,
          'submission_ids[]': submissionIdValue,
          'password': password,
          'confirm': confirmValue,
        },
      );

      if (response.statusCode == 302) {
        var document = html_parser.parse(response.body);
        String bodyText = document.body?.text.trim() ?? '';
        if (bodyText.isEmpty ||
            bodyText.toLowerCase().contains('there are no submissions to list')) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Submission deleted successfully.'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.of(context).pop();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to delete submission.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to delete submission.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e, stackTrace) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('An error occurred while deleting the submission.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showInfoDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Post Information'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (category != null || type != null)
                  Text(
                    'Category: ${category ?? 'N/A'} / ${type ?? 'N/A'}',
                    style: const TextStyle(fontSize: 16),
                  ),
                const SizedBox(height: 8),
                if (species != null)
                  Text(
                    'Species: $species',
                    style: const TextStyle(fontSize: 16),
                  ),
                const SizedBox(height: 8),
                if (gender != null)
                  Text(
                    'Gender: $gender',
                    style: const TextStyle(fontSize: 16),
                  ),
                const SizedBox(height: 8),
                if (size != null)
                  Text(
                    'Size: $size',
                    style: const TextStyle(fontSize: 16),
                  ),
                const SizedBox(height: 8),
                if (fileSize != null)
                  Text(
                    'File Size: $fileSize',
                    style: const TextStyle(fontSize: 16),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  void _parsePublicationTime(String rawTime) {
    try {
      // We try a couple of common FA formats. Classic used "Dec 31, 2024 11:59 PM"
      // Beta used "MMM d, yyyy hh:mm a" as well
      final format = DateFormat('MMM d, yyyy hh:mm a');
      DateTime naiveDateTime = format.parse(rawTime);
      if (isDstCorrectionApplied) {
        naiveDateTime = naiveDateTime.subtract(const Duration(hours: 1));
      }
      publicationTime = naiveDateTime.toUtc();
    } catch (e, stackTrace) {
      // If that fails, try a fallback parse
      try {
        // For example: "Dec 31st, 2024 23:59" or "Mar 16, 2025 04:05 PM"
        final altFormat = DateFormat("MMM d, yyyy HH:mm");
        DateTime naiveAlt = altFormat.parse(rawTime);
        if (isDstCorrectionApplied) {
          naiveAlt = naiveAlt.subtract(const Duration(hours: 1));
        }
        publicationTime = naiveAlt.toUtc();
      } catch (e2) {
        debugPrint("Error parsing publication time: $e2");
      }
      debugPrint("Error parsing publication time: $e");
      debugPrint("Stack trace: $stackTrace");
    }
  }

  String? getFormattedPublicationTime() {
    if (publicationTime == null) return null;
    final localTime = publicationTime!.toLocal();
    return DateFormat.yMMMd().add_jm().format(localTime);
  }

  void _sharePost() {
    final postUrl = 'https://www.furaffinity.net/view/${widget.uniqueNumber}/';
    final shareContent = '$postUrl';
    Share.share(
      shareContent,
      subject: submissionTitle ?? 'Fur Affinity Post',
    );
  }

  void _addComment(String commentText) {
    setState(() {
      comments.add({
        'profileImage': null,
        'username': 'You',
        'text': commentText,
        'width': 100.0,
        'isOP': false,
      });
      commentsCount = (commentsCount) + 1;
    });
  }

  Future<void> _unhideComment(String unhideLink, String commentId) async {
    final shouldUnhide = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Confirmation"),
          content:
          const Text("Are you sure you want to unhide this comment?"),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text("Yes"),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text("Cancel"),
            ),
          ],
        );
      },
    );

    if (shouldUnhide == true) {
      try {
        String? cookieA = await _secureStorage.read(key: 'fa_cookie_a');
        String? cookieB = await _secureStorage.read(key: 'fa_cookie_b');
        if (cookieA == null || cookieB == null) return;

        final response = await _getWithSfwCookie(unhideLink);
        if (response.statusCode == 200) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Comment successfully un-hidden!"),
              backgroundColor: Colors.green,
            ),
          );
          await _fetchPostDetails();
        } else {
          debugPrint('Failed to unhide comment. Status code: ${response.statusCode}');
        }
      } catch (e) {
        debugPrint('Error un-hiding comment: $e');
      }
    }
  }

  /// Downloads the image from [imageUrl] and saves it to the gallery.
  Future<void> _downloadImage(BuildContext context, String imageUrl) async {
    try {
      bool isPermissionGranted = false;

      if (Platform.isAndroid) {
        isPermissionGranted = await _requestPermissionAndroid();
      } else if (Platform.isIOS) {
        if (await Permission.photosAddOnly.request().isGranted) {
          isPermissionGranted = true;
        }
      }

      if (isPermissionGranted) {
        Uint8List bytes;

        // Attempt to download the image from the URL
        final response = await http.get(Uri.parse(imageUrl));
        if (response.statusCode == 200) {
          bytes = response.bodyBytes;
        } else {
          // If network image download fails, load default image from assets
          bytes = await _loadDefaultImageBytes();
        }

        // Save image to gallery
        final result = await SaverGallery.saveImage(
          bytes,
          quality: 80,
          fileName: "avatar_${DateTime.now().millisecondsSinceEpoch}.jpg",
          skipIfExists: false,
          androidRelativePath: "Pictures/YourAppName/images",
        );

        if (result.isSuccess) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Image saved to gallery!'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to save image to gallery.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Photo permission denied'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to download image: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// Shares the image from [imageUrl] using the device's share menu.
  /// Downloads the image, writes it to a temporary file, then triggers sharing.
  Future<void> _shareImage(BuildContext context, String imageUrl) async {
    try {
      bool isPermissionGranted = false;

      if (Platform.isAndroid) {
        isPermissionGranted = await _requestPermissionAndroid();
      } else if (Platform.isIOS) {
        if (await Permission.photosAddOnly.request().isGranted) {
          isPermissionGranted = true;
        }
      }

      if (!isPermissionGranted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Permission denied'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      Uint8List bytes;


      final response = await http.get(Uri.parse(imageUrl));
      if (response.statusCode == 200) {
        bytes = response.bodyBytes;
      } else {
        bytes = await _loadDefaultImageBytes();
      }


      final tempDir = Directory.systemTemp;
      final tempFile = await File(
          '${tempDir.path}/shared_image_${DateTime.now().millisecondsSinceEpoch}.jpg')
          .create();
      await tempFile.writeAsBytes(bytes);

      // Share the image file using share_plus
      await Share.shareXFiles([XFile(tempFile.path)], text: '');
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to share image: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// Loads default image bytes from assets if image download fails.
  Future<Uint8List> _loadDefaultImageBytes() async {
    final byteData = await rootBundle.load('assets/images/defaultpic.gif');
    return byteData.buffer.asUint8List();
  }

  /// Requests photo/storage permission on Android.
  /// Returns true if granted, false otherwise.
  Future<bool> _requestPermissionAndroid() async {
    final androidInfo = await DeviceInfoPlugin().androidInfo;
    final sdkInt = androidInfo.version.sdkInt;

    if (sdkInt >= 33) {
      final status = await Permission.photos.request();
      return status.isGranted;
    } else {
      final status = await Permission.storage.request();
      return status.isGranted;
    }
  }

  /// Helper method to recover the full link from truncated FA links
  String? _getFullLinkFromFetchedHtml(String truncatedUrl) {
    if (submissionDescription == null) return null;
    var document = html_parser.parse(submissionDescription);
    for (var anchor in document.querySelectorAll('a.auto_link_shortened')) {
      String? fullLink = anchor.attributes['title'] ?? anchor.attributes['href'];
      if (fullLink != null && fullLink.isNotEmpty) {
        return fullLink;
      }
    }
    return null;
  }

  String fixTruncatedLinks(String htmlContent) {
    var document = html_parser.parse(htmlContent);
    for (var anchor in document.querySelectorAll('a.auto_link_shortened')) {
      if (anchor.text.contains(".....")) {
        String? fullLink = anchor.attributes['title'];
        if (fullLink != null && fullLink.isNotEmpty) {
          anchor.text = fullLink;
        }
      }
    }
    return document.outerHtml;
  }





  /// Returns the full URL from a truncated comment link.
  String? _getFullLinkFromCommentHtml(String commentHtml, String truncatedUrl) {
    var document = html_parser.parse(commentHtml);
    for (var anchor in document.querySelectorAll('a.auto_link.auto_link_shortened')) {
      String? fullLink = anchor.attributes['title'] ?? anchor.attributes['href'];
      if (fullLink != null && fullLink.isNotEmpty) {
        return fullLink;
      }
    }
    return null;
  }


  /// Handles FA links found in comments.
  Future<void> _handleCommentLink(
      BuildContext context, String url, String commentHtml) async {
    // If the URL appears truncated, tries to recover the full URL
    if (url.contains(".....")) {
      final recoveredUrl = _getFullLinkFromCommentHtml(commentHtml, url);
      if (recoveredUrl != null && recoveredUrl.isNotEmpty) {
        url = recoveredUrl;

      }
    }

    final Uri uri = Uri.parse(url);
    final String urlToMatch = uri.toString();

    // 1. Gallery Folder Link
    final RegExp galleryFolderRegex = RegExp(
      r'^https?://(?:www\.)?furaffinity\.net/gallery/([^/]+)/folder/(\d+)/([^/]+)/?$',
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

    // 2. User Link
    final RegExp userRegex = RegExp(
      r'^(?:https?://(?:www\.)?furaffinity\.net)?/user/([^/]+)/?$',
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

    // 3. Journal Link
    final RegExp journalRegex = RegExp(
      r'^(?:https?://(?:www\.)?furaffinity\.net)?/journal/(\d+)/.*$',
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

    // 4. Submission/View Link
    final RegExp viewRegex = RegExp(
      r'^(?:https?://(?:www\.)?furaffinity\.net)?/view/(\d+)(?:/.*)?(?:#.*)?$',
    );
    if (viewRegex.hasMatch(urlToMatch)) {
      final String submissionId = viewRegex.firstMatch(urlToMatch)!.group(1)!;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => OpenPost(uniqueNumber: submissionId, imageUrl: ''),
        ),
      );
      return;
    }

    // 5. Fallback: open externally
    await launchUrlString(url, mode: LaunchMode.externalApplication);
  }

  /// Modified _handleFALink with fallback
  Future<void> _handleFALink(BuildContext context, String url) async {
    // If the URL appears truncated
    if (url.contains(".....") && submissionDescription != null) {
      final recoveredUrl = _getFullLinkFromFetchedHtml(url);
      if (recoveredUrl != null && recoveredUrl.isNotEmpty) {
        url = recoveredUrl;
      }
    }

    final Uri uri = Uri.parse(url);
    final String urlToMatch = uri.toString();

    // 1. Gallery Folder Link
    final RegExp galleryFolderRegex = RegExp(
      r'^https?://(?:www\.)?furaffinity\.net/gallery/([^/]+)/folder/(\d+)/([^/]+)/?$',
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

    // 2. User Link
    final RegExp userRegex = RegExp(
      r'^(?:https?://(?:www\.)?furaffinity\.net)?/user/([^/]+)/?$',
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

    // 3. Journal Link
    final RegExp journalRegex = RegExp(
      r'^(?:https?://(?:www\.)?furaffinity\.net)?/journal/(\d+)/.*$',
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

    // 4. Submission/View Link
    final RegExp viewRegex = RegExp(
      r'^(?:https?://(?:www\.)?furaffinity\.net)?/view/(\d+)(?:/.*)?(?:#.*)?$',
    );
    if (viewRegex.hasMatch(urlToMatch)) {
      final String submissionId = viewRegex.firstMatch(urlToMatch)!.group(1)!;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) =>
              OpenPost(uniqueNumber: submissionId, imageUrl: ''),
        ),
      );
      return;
    }

    // 5. Fallback
    await launchUrlString(url, mode: LaunchMode.externalApplication);
  }

  void _showEditDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Edit Submission'),
          content: const Text('What do you want to do?'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _openSubmissionEdit('info');
              },
              child: const Text('Edit Submission Info'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _openSubmissionEdit('file');
              },
              child: const Text('Update Source File'),
            ),
          ],
        );
      },
    );
  }

  void _openSubmissionEdit(String type) {
    String editUrl;
    if (type == 'info') {
      editUrl =
      'https://www.furaffinity.net/controls/submissions/changeinfo/${widget.uniqueNumber}/';
    } else {
      editUrl =
      'https://www.furaffinity.net/controls/submissions/changesubmission/${widget.uniqueNumber}/';
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EditSubmissionScreen(initialUrl: editUrl),
      ),
    ).then((_) {
      _fetchPostDetails();
    });
  }

  void _closePost() {
    setState(() {
      _isWebViewVisible = false;
    });

    Future.delayed(const Duration(milliseconds: 5), () {
      Navigator.pop(context);
    });
  }

  Future<void> _sendFavoriteRequest(bool shouldFavorite) async {
    String? cookieA = await _secureStorage.read(key: 'fa_cookie_a');
    String? cookieB = await _secureStorage.read(key: 'fa_cookie_b');

    if (cookieA == null || cookieB == null) {
      return;
    }

    String? url;
    if (shouldFavorite) {
      if (favLink != null) {
        url = 'https://www.furaffinity.net$favLink';
      } else {
        return;
      }
    } else {
      if (unfavLink != null) {
        url = 'https://www.furaffinity.net$unfavLink';
      } else {
        return;
      }
    }

    try {
      final response = await _getWithSfwCookie(url);
      if (response.statusCode == 200) {
        await _fetchFavoriteLinks();
      } else {
        debugPrint('Failed to toggle favorite: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error toggling favorite: $e');
    }
  }

  Future<bool> _toggleFavorite(bool isLiked) async {
    // Normalize the usernames by removing any leading '~' or '@' symbols.
    String normalizedCurrent = (currentUsername ?? '').replaceAll(RegExp(r'^[~@]'), '');
    String normalizedPost = (username ?? '').replaceAll(RegExp(r'^[~@]'), '');

    if (normalizedCurrent == normalizedPost) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("You cannot favorite your own post."),
          backgroundColor: Colors.red,
        ),
      );
      return isLiked;
    }


    bool newLikeState = !isLiked;
    setState(() {
      isFavorited = newLikeState;
      favoritesCount += newLikeState ? 1 : -1;
    });

    _pendingFavoriteState = newLikeState;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(seconds: 2), () async {
      await _sendFavoriteRequest(_pendingFavoriteState);
    });

    return newLikeState;
  }






  @override
  Widget build(BuildContext context) {
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    // The loading overlay remains visible until both details and webview are loaded.
    bool showLoadingIndicator = !_detailsLoaded || !_webViewLoaded;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Post"),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _closePost,
        ),
        actions: [
          Builder(
            builder: (context) {
              // Build the menu items.
              List<PopupMenuEntry<String>> menuItems = [
                const PopupMenuItem<String>(
                  value: 'report',
                  child: Text('Report'),
                ),
                if (currentUsername == null || currentUsername != username)
                  PopupMenuItem<String>(
                    value: 'block_unblock',
                    child: Text(isBlocked ? 'Unblock author' : 'Block author'),
                  ),
                const PopupMenuItem<String>(
                  value: 'info',
                  child: Text('Info'),
                ),
                PopupMenuItem<String>(
                  value: 'keywords',
                  child: const Text('Keywords'),
                ),
                const PopupMenuItem<String>(
                  value: 'copy_link',
                  child: Text('Copy link'),
                ),
              ];

              if (currentUsername != null && currentUsername == username) {
                menuItems.add(
                  const PopupMenuItem<String>(
                    value: 'edit',
                    child: Text('Edit'),
                  ),
                );
                menuItems.add(
                  PopupMenuItem<String>(
                    value: 'delete',
                    child: Text(
                      'Delete',
                      style: TextStyle(color: Colors.red),
                    ),
                  ),
                );
              }

              return IconButton(
                icon: const Icon(Icons.more_vert),
                onPressed: () async {
                  final RenderBox button = context.findRenderObject() as RenderBox;
                  final RenderBox overlay =
                  Overlay.of(context).context.findRenderObject() as RenderBox;
                  final RelativeRect position = RelativeRect.fromRect(
                    Rect.fromPoints(
                      button.localToGlobal(Offset(0, button.size.height),
                          ancestor: overlay),
                      button.localToGlobal(
                        button.size.bottomRight(Offset(0, button.size.height + 10)),
                        ancestor: overlay,
                      ),
                    ),
                    Offset.zero & overlay.size,
                  );

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
                      await _handleBlockUnblock();
                      break;
                    case 'info':
                      _showInfoDialog();
                      break;
                    case 'keywords':
                      _showKeywordsDialog();
                      break;
                    case 'edit':
                      _showEditDialog();
                      break;
                    case 'delete':
                      _handleDeletePost();
                      break;
                    case 'copy_link':
                      final postUrl = 'https://www.furaffinity.net/view/${widget.uniqueNumber}/';
                      await Clipboard.setData(ClipboardData(text: postUrl));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Link copied to clipboard'),
                          backgroundColor: Colors.green,
                        ),
                      );
                      break;
                    default:
                      break;
                  }
                },
              );
            },
          ),
        ],
      ),
      resizeToAvoidBottomInset: true,
      // Build the main content in a Stack so it can overlay the loading indicator.
      body: Stack(
        children: [
          RefreshIndicator(
            onRefresh: () async {
              // Re-fetch post details when the user pulls down.
              await _fetchPostDetails();
            },
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.only(bottom: keyboardHeight + 20),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  if (profileImageUrl != null && username != null)
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Flexible(
                            child: GestureDetector(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => UserProfileScreen(
                                      nickname: linkUsername ?? username!,
                                    ),
                                  ),
                                );
                              },
                              child: Container(
                                padding: const EdgeInsets.only(right: 6.0),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 36,
                                      height: 36,
                                      decoration: const BoxDecoration(
                                        color: Colors.transparent,
                                        borderRadius: BorderRadius.zero,
                                      ),
                                      child: CachedNetworkImage(
                                        imageUrl: profileImageUrl!,
                                        fit: BoxFit.cover,
                                        alignment: Alignment.center,
                                        errorWidget: (context, url, error) =>
                                            Image.asset(
                                              'assets/images/defaultpic.gif',
                                              fit: BoxFit.cover,
                                            ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Flexible(
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        alignment: Alignment.centerLeft,
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            ...iconBeforeUrls.map(
                                                  (url) => Padding(
                                                padding: const EdgeInsets.only(right: 4.0),
                                                child: Image.network(
                                                  url,
                                                  width: 20,
                                                  height: 20,
                                                  errorBuilder: (context, error, stackTrace) =>
                                                  const Icon(
                                                    Icons.error,
                                                    size: 20,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            Text(
                                              username!,
                                              style: const TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            ...iconAfterUrls.map(
                                                  (url) => Padding(
                                                padding: const EdgeInsets.only(left: 4.0),
                                                child: Image.network(
                                                  url,
                                                  width: 20,
                                                  height: 20,
                                                  errorBuilder: (context, error, stackTrace) =>
                                                  const Icon(
                                                    Icons.error,
                                                    size: 20,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          if (!(currentUsername != null && currentUsername == username))
                            SizedBox(
                              width: 94,
                              height: 24,
                              child: ElevatedButton(
                                onPressed: () => _handleWatchButtonPressed(),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor:
                                  isWatching ? Colors.black : const Color(0xFFE09321),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                  side: const BorderSide(color: Color(0xFFE09321)),
                                ),
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    isWatching ? "-Watch" : "+Watch",
                                    style: TextStyle(
                                      color: isWatching ? Colors.white : Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  if (fullViewImageUrl != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: GestureDetector(
                        onLongPressStart: (details) async {
                          final tapPosition = details.globalPosition;
                          final selected = await showMenu<String>(
                            context: context,
                            position: RelativeRect.fromLTRB(
                              tapPosition.dx,
                              tapPosition.dy,
                              tapPosition.dx,
                              tapPosition.dy,
                            ),
                            items: [
                              const PopupMenuItem(
                                value: 'download',
                                child: Text('Download'),
                              ),
                              const PopupMenuItem(
                                value: 'share',
                                child: Text('Share image'),
                              ),
                            ],
                          );
                          if (selected == 'download') {
                            await _downloadImage(context, fullViewImageUrl!);
                          } else if (selected == 'share') {
                            await _shareImage(context, fullViewImageUrl!);
                          }
                        },
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => AvatarDownloadScreen(
                                imageUrl: fullViewImageUrl!,
                              ),
                            ),
                          );
                        },
                        child: ClipRect(
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final aspectRatio = (imageWidth != null && imageHeight != null)
                                  ? imageWidth! / imageHeight!
                                  : 16 / 9;
                              return AspectRatio(
                                aspectRatio: aspectRatio,
                                child: InteractiveViewer(
                                  minScale: 1.0,
                                  maxScale: 10.0,
                                  child: Image.network(
                                    fullViewImageUrl!,
                                    fit: BoxFit.contain,
                                    loadingBuilder: (
                                        BuildContext context,
                                        Widget child,
                                        ImageChunkEvent? loadingProgress,
                                        ) {
                                      if (loadingProgress == null) {
                                        return child;
                                      }
                                      return Container(
                                        color: Colors.black,
                                        child: Center(
                                          child: CircularProgressIndicator(
                                            value: loadingProgress.expectedTotalBytes != null
                                                ? loadingProgress.cumulativeBytesLoaded /
                                                (loadingProgress.expectedTotalBytes ?? 1)
                                                : null,
                                            valueColor: const AlwaysStoppedAnimation<Color>(
                                              Color(0xFFE09321),
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                    errorBuilder: (context, error, stackTrace) {
                                      return Container(
                                        color: Colors.black,
                                        child: const Center(
                                          child: Icon(
                                            Icons.error_outline,
                                            color: Colors.red,
                                            size: 40,
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  if (submissionTitle != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: Text(
                        submissionTitle!,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  const Divider(color: Colors.grey, thickness: 0.3, height: 16),
                  if (_isWebViewVisible && submissionDescription != null)
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: GestureDetector(
                        onLongPressStart: (LongPressStartDetails details) async {
                          final RenderBox overlay =
                          Overlay.of(context)!.context.findRenderObject() as RenderBox;
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
                            String? plainText = await _submissionWebViewKey.currentState?.getPlainText();
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
                                builder: (context) => SubmissionDescriptionWebViewScreen(
                                  submissionId: widget.uniqueNumber,
                                ),
                              ),
                            );
                          }
                        },
                        child: SubmissionDescriptionWebView(
                          key: _submissionWebViewKey,
                          submissionId: widget.uniqueNumber,
                          onHeightChanged: (double height) {
                            Future.delayed(const Duration(milliseconds: 20), () {
                              setState(() {
                                _webViewLoaded = true;
                              });
                            });

                            print("WebView loaded with height: $height");
                          },
                        ),
                      ),
                    ),
                  const Divider(color: Colors.grey, thickness: 0.3, height: 24),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildPublicationAndViewsRow(),
                        const Divider(color: Colors.grey, thickness: 0.3, height: 24),
                        _buildFavoritesAndCommentsRow(),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 0.0, top: 12.0),
                          child: const Divider(color: Colors.grey, thickness: 0.3, height: 0),
                        ),
                        SizedBox(
                          height: 50,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              Expanded(
                                child: IconButton(
                                  icon: const Icon(
                                    Icons.comment_outlined,
                                    size: 26,
                                    color: Colors.grey,
                                  ),
                                  onPressed: () async {
                                    await Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => AddCommentScreen(
                                          submissionTitle: submissionTitle ?? '',
                                          onSendComment: _addComment,
                                          uniqueNumber: widget.uniqueNumber,
                                        ),
                                      ),
                                    ).then((result) {
                                      if (result == true) {
                                        _fetchPostDetails();
                                      }
                                    });
                                  },
                                  splashRadius: 24,
                                ),
                              ),
                              Expanded(
                                child: IconButton(
                                  icon: const Icon(
                                    Icons.photo_library_outlined,
                                    size: 26,
                                    color: Colors.grey,
                                  ),
                                  onPressed: () {
                                    if (linkUsername != null) {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => UserProfileScreen(
                                            nickname: linkUsername!,
                                            initialSection: ProfileSection.Gallery,
                                          ),
                                        ),
                                      );
                                    } else {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text('Username is unavailable.'),
                                          backgroundColor: Colors.red,
                                        ),
                                      );
                                    }
                                  },
                                  splashRadius: 24,
                                ),
                              ),
                              Expanded(
                                child: IconButton(
                                  icon: LikeButton(
                                    isLiked: isFavorited,
                                    size: 26,
                                    circleColor: const CircleColor(
                                      start: Colors.red,
                                      end: Colors.redAccent,
                                    ),
                                    bubblesColor: const BubblesColor(
                                      dotPrimaryColor: Colors.red,
                                      dotSecondaryColor: Colors.redAccent,
                                    ),
                                    likeBuilder: (bool isLiked) {
                                      return Icon(
                                        isLiked ? Icons.favorite : Icons.favorite_border,
                                        color: isLiked ? Colors.red : Colors.grey,
                                        size: 26,
                                      );
                                    },
                                    animationDuration: const Duration(milliseconds: 500),
                                    onTap: _toggleFavorite,
                                  ),
                                  onPressed: () {
                                    _toggleFavorite(isFavorited);
                                  },
                                  splashRadius: 24,
                                ),
                              ),
                              Expanded(
                                child: IconButton(
                                  icon: const Icon(
                                    Icons.note_outlined,
                                    size: 26,
                                    color: Colors.grey,
                                  ),
                                  onPressed: () {
                                    if (linkUsername != null) {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => NewMessageScreen(
                                            recipient: linkUsername!,
                                          ),
                                        ),
                                      );
                                    } else {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text('Recipient username is unavailable.'),
                                          backgroundColor: Colors.red,
                                        ),
                                      );
                                    }
                                  },
                                  splashRadius: 24,
                                ),
                              ),
                              Expanded(
                                child: IconButton(
                                  icon: const Icon(
                                    Icons.share_outlined,
                                    size: 26,
                                    color: Colors.grey,
                                  ),
                                  onPressed: _sharePost,
                                  splashRadius: 24,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12.0, top: 0.0),
                          child: const Divider(
                            color: Colors.grey,
                            thickness: 0.3,
                            height: 0,
                          ),
                        ),
                        const SizedBox(height: 20),
                        _buildCommentsSection(),
                      ],
                    ),
                  )
                ],
              ),
            ),
          ),
          if (_isTyping)
            Positioned.fill(
              child: GestureDetector(
                onTap: () => FocusScope.of(context).unfocus(),
                child: Container(
                  color: Colors.black.withOpacity(0.5),
                  padding: EdgeInsets.only(bottom: keyboardHeight),
                ),
              ),
            ),
          // Overlay the loading indicator until both details and the webview are loaded.
          if (showLoadingIndicator)
            Container(
              color: Colors.black.withOpacity(1.0),
              child: const Center(
                child: PulsatingLoadingIndicator(
                  size: 78.0,
                  assetPath: 'assets/icons/fathemed.png',
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
            left: 8.0,
            right: 8.0,
            bottom: keyboardHeight > 0 ? keyboardHeight : 4.0,
            top: 8.0,
          ),
          child: GestureDetector(
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => AddCommentScreen(
                    submissionTitle: submissionTitle ?? '',
                    onSendComment: _addComment,
                    uniqueNumber: widget.uniqueNumber,
                  ),
                ),
              ).then((result) {
                if (result == true) {
                  _fetchPostDetails();
                }
              });
            },
            child: AbsorbPointer(
              absorbing: true,
              child: SizedBox(
                height: 40.0,
                child: TextField(
                  controller: _commentController,
                  readOnly: true,
                  decoration: InputDecoration(
                    hintText: 'Add a comment...',
                    hintStyle: const TextStyle(color: Colors.white54),
                    contentPadding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
                    filled: true,
                    fillColor: const Color(0xFF353535),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                    suffixIcon: const Icon(Icons.send, color: Colors.white54),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }


  Widget _buildPublicationAndViewsRow() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (publicationTime != null)
          GestureDetector(
            onTap: () {
              // Toggle between full and short date display.
              setState(() {
                _showFullPublicationDate = !_showFullPublicationDate;
              });
            },
            child: Text(
              '${getFormattedPublicationTime()}',
              style: const TextStyle(fontSize: 14, color: Colors.grey),
            ),
          ),
        if (publicationTime != null && viewCount != null)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 5.0),
            child: Icon(Icons.circle, size: 4, color: Colors.grey),
          ),
        if (viewCount != null)
          Row(
            children: [
              Text(
                '$viewCount',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 2),
              const Text(
                'Views',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildFavoritesAndCommentsRow() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (favoritesCount >= 0)
          Row(
            children: [
              Text(
                '$favoritesCount',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 2),
              const Text(
                'Favs',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        if (favoritesCount >= 0 && commentsCount >= 0)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 5.0),
            child: Icon(Icons.circle, size: 4, color: Colors.grey),
          ),
        if (commentsCount >= 0)
          Row(
            children: [
              Text(
                '$commentsCount',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 2),
              const Text(
                'Comments',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildCommentsSection() {
    if (comments.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(8.0),
        child: Text(
          "No comments.",
          style: TextStyle(fontSize: 16, color: Colors.grey),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: comments.length,
      itemBuilder: (context, index) {
        final comment = comments[index];
        return CommentWidget(
          key: ValueKey(comment['commentId'] ?? index),
          comment: comment,
          onHide: () {
            final hideLink = comment['hideLink'] as String?;
            final cId = comment['commentId'] as String?;
            if (hideLink != null && cId != null) {
              hideComment(hideLink, cId);
            }
          },
          onEdit: () {
            if (comment['editLink'] != null) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => EditCommentScreen(
                    comment: comment,
                    editLink: comment['editLink'],
                    onUpdateComment: (updatedText) {
                      setState(() {
                        comment['text'] = updatedText;
                      });
                    },
                  ),
                ),
              );
            }
          },
          onReply: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ReplyScreen(
                  comment: comment,
                  uniqueNumber: widget.uniqueNumber,
                  isClassic: _isClassicUserPage,
                  onSendReply: (replyText) {

                  },
                ),
              ),
            ).then((result) {
              if (result == true) {
                _fetchPostDetails();
              }
            });
          },

          onUnhide: (comment['deleted'] == true && comment['hideLink'] != null)
              ? () {
            _unhideComment(comment['hideLink'], "");
          }
              : null,
          handleLink: (url) async {
            final commentHtml = comment['commentHtml'] ?? '';
            await _handleCommentLink(context, url, commentHtml);
          },
        );
      },
    );
  }
}

class CommentWidget extends StatefulWidget {
  final Map<String, dynamic> comment;
  final VoidCallback? onHide;
  final VoidCallback? onEdit;
  final VoidCallback? onReply;
  final VoidCallback? onUnhide;
  final Future<void> Function(String url)? handleLink;

  const CommentWidget({
    Key? key,
    required this.comment,
    this.onHide,
    this.onEdit,
    this.onReply,
    this.onUnhide,
    this.handleLink,
  }) : super(key: key);

  @override
  _CommentWidgetState createState() => _CommentWidgetState();
}

class _CommentWidgetState extends State<CommentWidget> {
  bool _showFullDate = false;

  @override
  Widget build(BuildContext context) {
    double widthPercent = (widget.comment['width'] ?? 100).toDouble();
    int nestingLevel = ((100.0 - widthPercent) / 3.0).round().clamp(0, 4);
    double leftPadding = nestingLevel * 16.0;

    if (widget.comment['deleted'] == true) {
      return Padding(
        padding: EdgeInsets.only(left: leftPadding, bottom: 6.0),
        child: Container(
          padding:
          const EdgeInsets.symmetric(vertical: 16.0, horizontal: 12.0),
          decoration: BoxDecoration(
            color: Colors.grey.shade900,
            borderRadius: BorderRadius.circular(4.0),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  widget.comment['text'] ?? '',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                  textAlign: TextAlign.left,
                ),
              ),
              if (widget.comment['hideLink'] != null)
                TextButton(
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 0),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: widget.onUnhide,
                  child: const Text(
                    'Unhide',
                    style: TextStyle(color: Colors.white, fontSize: 14),
                  ),
                ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.only(left: leftPadding, bottom: 6.0),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 12.0),
        decoration: BoxDecoration(
          color: Colors.grey.shade900,
          borderRadius: BorderRadius.circular(8.0),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top row with avatar, username
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.comment['profileImage'] != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 8.0, top: 4.0),
                    child: GestureDetector(
                      onTap: () {
                        if (widget.comment['username'] != null) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => UserProfileScreen(
                                nickname: widget.comment['username'],
                              ),
                            ),
                          );
                        }
                      },
                      child: CachedNetworkImage(
                        imageUrl: widget.comment['profileImage'],
                        width: 46,
                        height: 46,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Image.asset(
                          'assets/images/defaultpic.gif',
                          width: 46,
                          height: 46,
                          fit: BoxFit.cover,
                        ),
                        errorWidget: (context, url, error) => Image.asset(
                          'assets/images/defaultpic.gif',
                          width: 46,
                          height: 46,
                          fit: BoxFit.cover,
                        ),
                      ),

                    ),
                  ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (widget.comment['iconBeforeUrls'] != null &&
                              widget.comment['iconBeforeUrls'].isNotEmpty)
                            ...widget.comment['iconBeforeUrls'].map(
                                  (url) {
                                final isEditedIcon = url.contains('edited.png');
                                return Padding(
                                  padding: const EdgeInsets.only(right: 4.0),
                                  child: Image.network(
                                    url,
                                    width: 16,
                                    height: 16,
                                    color: isEditedIcon ? Colors.white : null,
                                    colorBlendMode: isEditedIcon
                                        ? BlendMode.srcIn
                                        : null,
                                  ),
                                );
                              },
                            ),
                          Flexible(
                            child: Text(
                              widget.comment['displayName'] ??
                                  widget.comment['username'] ??
                                  'Anonymous',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (widget.comment['iconAfterUrls'] != null &&
                              widget.comment['iconAfterUrls'].isNotEmpty)
                            ...widget.comment['iconAfterUrls'].map(
                                  (url) => Padding(
                                padding: const EdgeInsets.only(left: 4.0),
                                child: Image.network(
                                  url,
                                  width: 16,
                                  height: 16,
                                ),
                              ),
                            ),
                          if (widget.comment['isOP'] == true)
                            const Padding(
                              padding: EdgeInsets.only(left: 4.0),
                              child: Text(
                                'OP',
                                style: TextStyle(
                                  color: Colors.blue,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                        ],
                      ),
                      Text(
                        '${widget.comment['symbol'] ?? '~'}${widget.comment['username'] ?? 'Anonymous'}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFFE09321),
                        ),
                      ),
                      if ((widget.comment['userTitle'] ?? '').isNotEmpty)
                        Text(
                          widget.comment['userTitle'],
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade400,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6.0),
              child: SelectionArea(
                child: ExtendedText(
                  widget.comment['text'] ?? '',
                  specialTextSpanBuilder: EmojiSpecialTextSpanBuilder(
                    onTapLink: widget.handleLink,
                  ),
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade300),
                ),

              ),
            ),

            // Footer row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Date
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _showFullDate = !_showFullDate;
                    });
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12.0),
                    child: Text(
                      _showFullDate
                          ? (widget.comment['popupDateFull'] ??
                          widget.comment['popupDateRelative'] ??
                          '')
                          : (widget.comment['popupDateRelative'] ?? ''),
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade400,
                      ),
                    ),
                  ),
                ),
                Row(
                  children: [
                    if (widget.comment['hideLink'] != null)
                      IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        icon: const Icon(Icons.visibility_off,
                            size: 16, color: Colors.white),
                        onPressed: widget.onHide,
                      ),
                    if (widget.comment['editLink'] != null)
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.only(left: 0.0, right: 8),
                          minimumSize: const Size(0, 0),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: widget.onEdit,
                        icon: const Icon(Icons.edit,
                            size: 16, color: Colors.white),
                        label: const Text('Edit',
                            style: TextStyle(color: Colors.white, fontSize: 14)),
                      ),
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.only(left: 0),
                        minimumSize: const Size(0, 0),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: widget.onReply,
                      icon: const Icon(Icons.reply,
                          size: 16, color: Colors.white),
                      label: const Text('Reply',
                          style: TextStyle(color: Colors.white, fontSize: 14)),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
