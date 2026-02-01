import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:extended_text/extended_text.dart';
import 'package:html/dom.dart' as dom;
import 'package:FANotifier/screens/reply_screen.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart';
import '../network.dart';
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
import '../app_theme.dart';
import '../parsing_utils.dart';
import '../providers/timezone_provider.dart';
import '../utils/html_tags_debug.dart';
import '../utils/specialTextSpanBuilder.dart';
import '../widgets/PulsatingLoadingIndicator.dart';
import 'SubmissionDescriptionWebview.dart';
import 'add_comment_screen.dart';
import 'avatardownloadscreen.dart';
import 'openpost_api_service.dart';
import 'edit_submission_screen.dart';
import '../services/fa_http.dart';
import 'editcommentscreen.dart';
import 'keyword_search_screen.dart';
import 'new_message.dart';
import 'user_profile_screen.dart';
import 'openjournal.dart';
import 'openpost_comments.dart';

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
  /// When true, do not fetch author profile on load (saves a request).
  /// Show "+Watch" until user taps it; then fetch profile and update button or perform watch.
  /// Set to true when opening from Browse or Search screens.
  final bool skipInitialWatchCheck;

  const OpenPost({
    required this.imageUrl,
    required this.uniqueNumber,
    this.skipInitialWatchCheck = false,
    Key? key,
  }) : super(key: key);

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
  String? rating; // "general" | "mature" | "adult" | null
  int favoritesCount = 0;
  int viewCount = 0;
  int commentsCount = 0;
  List<Map<String, dynamic>> comments = [];
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    iOptions: IOSOptions( 
    accountName: 'flutter_secure_storage_service',
    accessibility: KeychainAccessibility.first_unlock),
  );
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
  bool _watchLinksLoading = false;
  String? unblockLink;
  bool isBlocked = false;
  String? category;
  String? type;
  String? species;
  String? gender;
  String? size;
  String? fileSize;
  List<String> keywords = [];
  List<FaPostTag> keywordTags = [];
  List<FaPostTag> metaKeywordTags = [];
  String? tagBlocklistNonce;
  bool _showTagsSection = false;
  final Set<String> _tagToggleInFlight = <String>{};
  final ValueNotifier<bool> _showScrollToTopNotifier = ValueNotifier<bool>(false);
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
  final ScrollController _scrollController = ScrollController();


  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_onScroll);

    Future.wait([
      _loadSfwEnabled(),
      _fetchPostDetails(),
    ]).then((_) {
      if (username != null && !widget.skipInitialWatchCheck) {
        _fetchUserPageLinks();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _commentController.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _showScrollToTopNotifier.dispose();
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

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final shouldShow = _scrollController.offset > 350;
    if (shouldShow == _showScrollToTopNotifier.value) return;
    _showScrollToTopNotifier.value = shouldShow;
  }

  Future<void> _loadSfwEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _sfwEnabled = prefs.getBool('sfwEnabled') ?? true;
    });
  }

  Future<Response> _getWithSfwCookie(
      String url, {
        Map<String, String>? additionalHeaders,
        bool skipSfw = false,
      }) async {
    String? cookieA = await _secureStorage.read(key: 'fa_cookie_a');
    String? cookieB = await _secureStorage.read(key: 'fa_cookie_b');

    String cookieHeader = '';
    if (cookieA != null && cookieB != null) {
      cookieHeader = 'a=$cookieA; b=$cookieB';
    }

    if (!skipSfw && _sfwEnabled && !_nsfwAllowed) {
      cookieHeader += '; sfw=1';
    }

    debugPrint('Cookie header being sent: $cookieHeader');

    final headers = <String, String>{
      'Cookie': cookieHeader,
      'User-Agent': FAHttp.userAgent,
    };
    if (additionalHeaders != null) headers.addAll(additionalHeaders);

    final response = await httpClient.get(Uri.parse(url), headers: headers);

    debugPrint('Response status: ${response.statusCode}');


    final ct = (response.headers['content-type'] ?? '').toLowerCase();
    if (response.statusCode == 200 &&
        (ct.contains('text/html') || ct.contains('application/xhtml'))) {

      String decodedBody;
      try {
        decodedBody = utf8.decode(response.bodyBytes);
      } on FormatException {
        try {
          decodedBody = utf8.decode(response.bodyBytes, allowMalformed: true);
        } catch (_) {
          decodedBody = latin1.decode(response.bodyBytes, allowInvalid: true);
        }
      }

      final document = html_parser.parse(decodedBody);


      final allSections = document.querySelectorAll('section');
      for (var section in allSections) {
        final header = section.querySelector('.section-header h2') ??
            section.querySelector('h2');
        final body = section.querySelector('.section-body');

        if (header != null && body != null) {
          final headerText = header.text.toLowerCase().trim();
          final bodyText = body.text.toLowerCase().trim();

          if (headerText.contains('system error') &&
              bodyText.contains('not in our database')) {
            debugPrint('DETECTED: Submission not found error');
            throw Exception("Submission not found in database");
          }
        }
      }


      if (!skipSfw) {
        final noticeSection = document.querySelector('section.notice-message');

        if (noticeSection != null) {
          final noticeText = noticeSection.text.toLowerCase().trim();


          final isMatureWarning =
              (noticeText.contains('mature') || noticeText.contains('adult')) &&
                  (noticeText.contains('rated') || noticeText.contains('content')) &&
                  (noticeText.contains('account settings') ||
                      noticeText.contains('log in') ||
                      noticeText.contains('enable'));

          if (isMatureWarning && !_nsfwAllowed) {
            debugPrint('DETECTED: Mature/Adult content warning - showing dialog');

            final userAgreed = await _showNSFWConfirmationDialog();
            debugPrint('User response: $userAgreed');

            if (userAgreed) {
              setState(() => _nsfwAllowed = true);
              debugPrint('Retrying request with NSFW allowed');
              final retryResponse = await _getWithSfwCookie(
                url,
                additionalHeaders: additionalHeaders,
                skipSfw: true,
              );
              debugPrint('Retry response status: ${retryResponse.statusCode}');
              return retryResponse;
            } else {
              debugPrint('User declined NSFW content');
              throw Exception("User declined to view NSFW content.");
            }
          }
        }


        final body = document.querySelector('body');
        final isOldMatureError = body?.attributes['id'] == 'pageid-matureimage-error';

        if (isOldMatureError && !_nsfwAllowed) {
          debugPrint('DETECTED: Old style mature error - showing dialog');
          final userAgreed = await _showNSFWConfirmationDialog();
          if (userAgreed) {
            setState(() => _nsfwAllowed = true);
            return await _getWithSfwCookie(
              url,
              additionalHeaders: additionalHeaders,
              skipSfw: true,
            );
          } else {
            throw Exception("User declined to view NSFW content.");
          }
        }
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
          content: const Text(
              'This post is marked NSFW. Are you sure you want to view it?'),
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
        decodedBody = utf8.decode(response.bodyBytes, allowMalformed: true);
      } catch (e) {
        try {
          decodedBody = latin1.decode(response.bodyBytes);
        } catch (e2) {
          debugPrint('Failed to decode user page response: $e2');
          return;
        }
      }
      final document = await compute(parseHtml, decodedBody);

      final isClassic = document
          .querySelector('body')
          ?.attributes['data-static-path']
          ?.contains('themes/classic') ??
          false;

      dom.Element? watchLinkElement;
      dom.Element? unwatchLinkElement;
      dom.Element? blockLinkElement;
      dom.Element? unblockLinkElement;
      String? blockKey;
      String? unblockKey;

      if (!isClassic) {
        watchLinkElement =
            logQuery(document, 'a.button.standard.go[href^="/watch/"]');
        unwatchLinkElement =
            logQuery(document, 'a.button.standard.stop[href^="/unwatch/"]');
        blockLinkElement =
            logQuery(document, 'a.button.standard.stop[href^="/block/"]');
        unblockLinkElement =
            logQuery(document, 'a.button.standard.stop[href^="/unblock/"]');

        watchLinkElement ??= logQuery(document, 'a.cat[href^="/watch/"]');
        unwatchLinkElement ??= logQuery(document, 'a.cat[href^="/unwatch/"]');
        blockLinkElement ??= logQuery(document, 'a.cat[href^="/block/"]');
        unblockLinkElement ??= logQuery(document, 'a.cat[href^="/unblock/"]');
      } else {
        watchLinkElement = logQuery(document, 'b > a[href^="/watch/"]');
        unwatchLinkElement = logQuery(document, 'b > a[href^="/unwatch/"]');

        final blockForm = document.querySelector('form[action^="/block/"]');
        if (blockForm != null) {
          final blockButton = blockForm.querySelector('button');
          if (blockButton != null &&
              blockButton.text.trim().contains('+Block')) {
            blockLinkElement = dom.Element.tag('a');
            blockLinkElement.attributes['href'] =
            blockForm.attributes['action']!;
            blockKey = blockButton.attributes['value'];
          }
        }
        final unblockForm = document.querySelector('form[action^="/unblock/"]');
        if (unblockForm != null) {
          final unblockButton = unblockForm.querySelector('button');
          if (unblockButton != null &&
              unblockButton.text.trim().contains('-Unblock')) {
            unblockLinkElement = dom.Element.tag('a');
            unblockLinkElement.attributes['href'] =
            unblockForm.attributes['action']!;
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

  Widget _buildTagsPanel() {
    final bool hasAnyTags = keywordTags.isNotEmpty || metaKeywordTags.isNotEmpty;

    // Guard: some posts have *only* meta keywords. In that case, older parsing
    // fallbacks could end up treating the meta section as normal keywords,
    // making the UI show the same chips twice. If both groups are identical,
    // show only the meta group.
    final Set<String> keywordSet =
        keywordTags.map((t) => t.name.toLowerCase()).toSet();
    final Set<String> metaSet =
        metaKeywordTags.map((t) => t.name.toLowerCase()).toSet();
    final bool hideKeywordGroup = keywordSet.isNotEmpty &&
        metaSet.isNotEmpty &&
        keywordSet.length == metaSet.length &&
        keywordSet.containsAll(metaSet);

    if (!hasAnyTags) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
        child: Text(
          'No keywords available.',
          style: TextStyle(fontSize: 13, color: Colors.grey),
          textAlign: TextAlign.center,
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(12, 10, 12, metaKeywordTags.isNotEmpty ? 4 : 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (keywordTags.isNotEmpty && !hideKeywordGroup)
            _buildTagsGroup(title: 'Keywords', tags: keywordTags, allowSearch: true),
          if (metaKeywordTags.isNotEmpty) ...[
            const SizedBox(height: 12),
            _buildTagsGroup(title: 'Meta Keywords', tags: metaKeywordTags, allowSearch: false),
          ],
        ],
      ),
    );
  }

  Widget _buildTagsGroup({
    required String title,
    required List<FaPostTag> tags,
    required bool allowSearch,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          alignment: WrapAlignment.start,
          runAlignment: WrapAlignment.start,
          spacing: 10,
          runSpacing: 10,
          children: tags
              .map((t) => _buildTagPill(t, allowSearch: allowSearch))
              .toList(growable: false),
        ),
      ],
    );
  }

  Widget _buildTagPill(FaPostTag tag, {required bool allowSearch}) {
    final bool inFlight = _tagToggleInFlight.contains(tag.name);
    final bool isBlocked = tag.isBlocked;

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
            message: isBlocked
                ? 'Click to remove this tag from the blocklist!'
                : 'Click to add this tag to the blocklist!',
            child: InkWell(
              onTap: inFlight ? null : () => _toggleTagBlock(tag),
              borderRadius: BorderRadius.circular(999),
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                ),
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
                      : Icon(
                          isBlocked ? Icons.remove : Icons.add,
                          size: 16,
                          color: Colors.black,
                        ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          InkWell(
            onTap: (allowSearch && tag.isSearchable) ? () => _navigateToSearch(tag.name) : null,
            child: Text(
              tag.name,
              style: TextStyle(
                fontSize: 13,
                color: (allowSearch && tag.isSearchable) ? Colors.white : Colors.white70,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleTagBlock(FaPostTag tag) async {
    if (_tagToggleInFlight.contains(tag.name)) return;

    if (tagBlocklistNonce == null || tagBlocklistNonce!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tag blocking is unavailable right now (missing nonce).'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _tagToggleInFlight.add(tag.name));

    try {
      final shouldBlock = !tag.isBlocked;
      await _sendTagBlocklistRequest(tag.name, shouldBlock: shouldBlock);

      // Update UI immediately so +/− changes without waiting for a full refresh.
      _applyLocalTagBlockState(tag.name, isBlocked: shouldBlock);

      // Refresh so the block/unblock state and blocked-content markers match FA.
      await _fetchPostDetails();

      // If the refreshed HTML didn't reflect the change yet, keep UI consistent.
      _applyLocalTagBlockState(tag.name, isBlocked: shouldBlock);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            shouldBlock ? 'Tag blocked: ${tag.name}' : 'Tag unblocked: ${tag.name}',
          ),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to ${tag.isBlocked ? 'unblock' : 'block'} tag: ${tag.name}'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _tagToggleInFlight.remove(tag.name));
    }
  }

  void _applyLocalTagBlockState(String tagName, {required bool isBlocked}) {
    bool updated = false;

    FaPostTag copyWith(FaPostTag t) => FaPostTag(
          name: t.name,
          isBlocked: isBlocked,
          isMeta: t.isMeta,
          isSearchable: t.isSearchable,
        );

    final updatedKeywords = keywordTags.map((t) {
      if (t.name != tagName) return t;
      updated = true;
      return copyWith(t);
    }).toList(growable: false);

    final updatedMeta = metaKeywordTags.map((t) {
      if (t.name != tagName) return t;
      updated = true;
      return copyWith(t);
    }).toList(growable: false);

    if (!updated) return;
    setState(() {
      keywordTags = updatedKeywords;
      metaKeywordTags = updatedMeta;
    });
  }

  Future<void> _sendTagBlocklistRequest(String tagName, {required bool shouldBlock}) async {
    final cookieA = await _secureStorage.read(key: 'fa_cookie_a');
    final cookieB = await _secureStorage.read(key: 'fa_cookie_b');
    final sfwValue = _sfwEnabled ? '1' : '0';

    if (cookieA == null || cookieB == null) {
      throw Exception('Not logged in.');
    }
    if (tagBlocklistNonce == null || tagBlocklistNonce!.isEmpty) {
      throw Exception('Missing tag blocklist nonce.');
    }

    final url = 'https://www.furaffinity.net/route/tag_blocking';
    final response = await httpClient.post(
      Uri.parse(url),
      headers: <String, String>{
        'Cookie': 'a=$cookieA; b=$cookieB; sfw=$sfwValue',
        'User-Agent': FAHttp.userAgent,
        'Referer': 'https://www.furaffinity.net/view/${widget.uniqueNumber}/',
        'Origin': 'https://www.furaffinity.net',
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: <String, String>{
        'action': shouldBlock ? 'add-tag' : 'remove-tag',
        'key': tagBlocklistNonce!,
        'tag_name': tagName,
      },
    );

    if (response.statusCode != 200) {
      throw Exception('Tag blocklist request failed: ${response.statusCode}');
    }
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
    // When we skipped initial fetch, load links on first use (same as Watch)
    if (blockLink == null && unblockLink == null && username != null) {
      setState(() => _watchLinksLoading = true);
      await _fetchUserPageLinks();
      if (!mounted) return;
      setState(() => _watchLinksLoading = false);
    }
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
      final response = await httpClient.post(
        Uri.parse(fullUrl),
        headers: {
          'Cookie': 'a=$cookieA; b=$cookieB; sfw=$sfwValue',
          'User-Agent': FAHttp.userAgent,
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
    // When we skipped initial fetch (Browse/Search), fetch links on first tap
    if (watchLink == null && unwatchLink == null && username != null) {
      if (_watchLinksLoading) return;
      setState(() => _watchLinksLoading = true);
      await _fetchUserPageLinks();
      if (!mounted) return;
      setState(() => _watchLinksLoading = false);
      // After fetch: if already watching, button will show -Watch; else send watch request below
    }
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
      final document = await compute(parseHtml, decodedBody);


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

    try {
      final response = await _getWithSfwCookie(postUrl);

      if (response.statusCode != 200) {
        debugPrint('Failed to fetch post details: ${response.statusCode}');
        setState(() => isLoading = false);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to load submission'),
              backgroundColor: Colors.red,
            ),
          );
          Navigator.of(context).pop();
        }
        return;
      }

      String decodedBody;
      try {
        decodedBody = utf8.decode(response.bodyBytes, allowMalformed: true);
      } catch (_) {
        try {
          decodedBody = latin1.decode(response.bodyBytes);
        } catch (e2) {
          debugPrint('Failed to decode response body: $e2');
          setState(() => isLoading = false);
          return;
        }
      }

      // Parse the document from the CORRECT response (after retry if needed)
      final document = await compute(parseHtml, decodedBody);

      // Double-check: make sure we didn't get an error page
      final noticeSection = document.querySelector('section.notice-message');
      if (noticeSection != null) {
        final noticeText = noticeSection.text.toLowerCase().trim();
        final isMatureWarning =
            (noticeText.contains('mature') || noticeText.contains('adult')) &&
                (noticeText.contains('rated') || noticeText.contains('content'));

        if (isMatureWarning) {
          debugPrint('ERROR: Still got mature warning after retry - this should not happen');
          setState(() => isLoading = false);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Failed to load NSFW content'),
                backgroundColor: Colors.red,
              ),
            );
            Navigator.of(context).pop();
          }
          return;
        }
      }

      final parsedPost = OpenPostApiService.parsePostDocument(document);
      final parsedComments = OpenPostApiService.parseComments(document);

      setState(() {
        currentUsername = parsedPost.currentUsername;
        username = parsedPost.username;
        linkUsername = parsedPost.linkUsername;
        profileImageUrl = parsedPost.profileImageUrl;
        submissionTitle = parsedPost.submissionTitle;
        fullViewImageUrl = parsedPost.fullViewImageUrl;
        submissionDescription = parsedPost.submissionDescription;
        rating = parsedPost.rating;

        if (parsedPost.publicationTimeRaw != null &&
            parsedPost.publicationTimeRaw!.isNotEmpty) {
          _parsePublicationTime(parsedPost.publicationTimeRaw!);
        }

        favoritesCount = parsedPost.favoritesCount;
        viewCount = parsedPost.viewCount;
        commentsCount = parsedPost.commentsCount;

        favLink = parsedPost.favLink;
        unfavLink = parsedPost.unfavLink;
        isFavorited = parsedPost.isFavorited;

        category = parsedPost.category;
        type = parsedPost.type;
        species = parsedPost.species;
        gender = parsedPost.gender;
        size = parsedPost.size;
        fileSize = parsedPost.fileSize;
        keywords = parsedPost.keywords;
        keywordTags = parsedPost.keywordTags;
        metaKeywordTags = parsedPost.metaKeywordTags;
        tagBlocklistNonce = parsedPost.tagBlocklistNonce;

        imageWidth = parsedPost.imageWidth;
        imageHeight = parsedPost.imageHeight;

        comments = parsedComments;
        commentsCount = parsedComments.length;
        _detailsLoaded = true;
        isLoading = false;
      });

      debugPrint('Post loaded successfully: $submissionTitle');

    } catch (e) {
      debugPrint('Error fetching post details: $e');
      setState(() => isLoading = false);

      if (mounted) {
        String errorMessage = 'Failed to load submission';

        if (e.toString().contains('not found in database')) {
          errorMessage = 'This submission does not exist or has been deleted';
        } else if (e.toString().contains('declined to view NSFW')) {
          errorMessage = 'NSFW content viewing declined';
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );

        // Navigate back after a short delay
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) {
            Navigator.of(context).pop();
          }
        });
      }
    }
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
      final response = await httpClient.post(
        Uri.parse(url),
        headers: {
          'Cookie': 'a=$cookieA; b=$cookieB',
          'User-Agent': FAHttp.userAgent,
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
      final response = await httpClient.post(
        Uri.parse(url),
        headers: {
          'Cookie': 'a=$cookieA; b=$cookieB',
          'User-Agent': FAHttp.userAgent,
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
      rawTime = rawTime.trim();

      try {
        // Correct format for "August 7, 2025 09:26:21 PM"
        final format = DateFormat('MMMM d, yyyy hh:mm:ss a');
        DateTime naiveDateTime = format.parse(rawTime);
        if (isDstCorrectionApplied) {
          naiveDateTime = naiveDateTime.subtract(const Duration(hours: 1));
        }
        publicationTime = naiveDateTime.toUtc();
        debugPrint("Successfully parsed FA date: $publicationTime");
        return;
      } catch (e) {
        debugPrint("Failed to parse with primary format: $e");
      }

      // fallback formats
      List<DateFormat> fallbackFormats = [
        DateFormat('MMM d, yyyy hh:mm:ss a'),
        DateFormat('MMM d, yyyy HH:mm:ss'),
        DateFormat('MMM d, yyyy hh:mm a'),
        DateFormat('MMM d, yyyy HH:mm'),
        DateFormat('yyyy-MM-dd HH:mm:ss'),
      ];

      for (var format in fallbackFormats) {
        try {
          DateTime naiveDateTime = format.parse(rawTime);
          if (isDstCorrectionApplied) {
            naiveDateTime = naiveDateTime.subtract(const Duration(hours: 1));
          }
          publicationTime = naiveDateTime.toUtc();
          debugPrint("Successfully parsed with fallback format: $publicationTime");
          return;
        } catch (e) {
          // continue
        }
      }

      debugPrint("Could not parse date with any format. Raw string: '$rawTime'");

    } catch (e, stackTrace) {
      debugPrint("Error parsing publication time: $e");
      debugPrint("Raw time string was: '$rawTime'");
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
        final response = await httpClient.get(
          Uri.parse(imageUrl),
          headers: {'User-Agent': FAHttp.userAgent},
        );
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
          fileName: "image_${DateTime.now().millisecondsSinceEpoch}.jpg",
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


      final response = await httpClient.get(
        Uri.parse(imageUrl),
        headers: {'User-Agent': FAHttp.userAgent},
      );
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

    // 2. User Link
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

    // 3. Journal Link:
    final RegExp journalRegex = RegExp(
      r'^(?:https?://(?:www\.)?furaffinity\.net)?/(?:journals/([a-zA-Z0-9\-_.~]+)|journal/(\d+))(?:/.*)?(?:#.*)?$',
    );

    if (journalRegex.hasMatch(urlToMatch)) {
      final Match match = journalRegex.firstMatch(urlToMatch)!;
      final String? username = match.group(1);
      final String? journalId = match.group(2);

      if (username != null) {
        // Matched: /journals/username/
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => UserProfileScreen(
              nickname: username,
              initialSection: ProfileSection.Journals,
            ),
          ),
        );
      } else if (journalId != null) {
        // Matched: /journal/12345/
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => OpenJournal(uniqueNumber: journalId),
          ),
        );
      }

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
          builder: (context) => OpenPost(
            uniqueNumber: submissionId,
            imageUrl: '',
          ),
        ),
      );
      return;
    }

    // 5. Fallback: open externally
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
    bool showLoadingIndicator = !_detailsLoaded || !_webViewLoaded;

    return AnnotatedRegion<SystemUiOverlayStyle>(
        value: const SystemUiOverlayStyle(
          systemNavigationBarColor: Colors.black,
          systemNavigationBarIconBrightness: Brightness.light,
          statusBarColor: Color(0xFF111111),
          statusBarIconBrightness: Brightness.light,
        ),
        child: Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        scrolledUnderElevation: 0,
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
    body: Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (_) {
        _commentsSelectionKey.currentState?.clearSelection();
        _commentsSelectionKey.currentState?.hideToolbar();
      },
      child: Stack(
        children: [
          SelectionArea(
            key: _commentsSelectionKey,
            child: RefreshIndicator(
              onRefresh: () async {
                // Re-fetch post details when the user pulls down.
                await _fetchPostDetails();
              },
              child: CustomScrollView(
                controller: _scrollController,
                physics: Platform.isIOS
                    ? const AlwaysScrollableScrollPhysics(parent: ClampingScrollPhysics())
                    : const AlwaysScrollableScrollPhysics(parent: ClampingScrollPhysics()),
                slivers: [
                  SliverToBoxAdapter(
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
                                      child: Image.network(
                                        profileImageUrl!,
                                        fit: BoxFit.cover,
                                        alignment: Alignment.center,

                                        // Shows while loading (no infinite spinner risk)
                                        loadingBuilder: (context, child, loadingProgress) {
                                          if (loadingProgress == null) {
                                            return child;
                                          }
                                          return const Center(
                                            child: CircularProgressIndicator(strokeWidth: 2),
                                          );
                                        },

                                        // Handles errors safely
                                        errorBuilder: (context, error, stackTrace) {
                                          return Image.asset(
                                            'assets/images/defaultpic.gif',
                                            fit: BoxFit.cover,
                                          );
                                        },
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
                                                fontSize: 15,
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
                                onPressed: _watchLinksLoading
                                    ? null
                                    : () => _handleWatchButtonPressed(),
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
                                  child: _watchLinksLoading
                                      ? const SizedBox(
                                          width: 14,
                                          height: 14,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : Text(
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
                      padding: const EdgeInsets.only(bottom: 0.0),
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
                            debugPrint("$fullViewImageUrl image2");
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

                  const Divider(
                    height: 5.0,
                    color: Color(0xFF111111),
                    thickness: 5.0,
                  ),
                  const Divider(
                    height: 3.0,
                    color: Colors.black,
                    thickness: 3.0,
                  ),
                  const Divider(
                    height: 3.0,
                    color: Color(0xFF111111),
                    thickness: 3.0,
                  ),








                  if (submissionTitle != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4.0, top: 4.0),
                      child: Text(
                        submissionTitle!,
                        style: const TextStyle(
                          fontSize: 23,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  if (publicationTime != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: GestureDetector(
                        onTap: () {
                          // Toggle between full and short date display.
                          setState(() {
                            _showFullPublicationDate = !_showFullPublicationDate;
                          });
                        },
                        child: Text(
                          '${getFormattedPublicationTime()}',
                          style: const TextStyle(fontSize: 13, color: Colors.grey),
                        ),
                      ),
                    ),



                  const Divider(
                    height: 5.0,
                    color: Color(0xFF111111),
                    thickness: 5.0,
                  ),
                  const Divider(
                    height: 2.0,
                    color: Colors.black,
                    thickness: 2.0,
                  ),
                  const Divider(
                    height: 3.0,
                    color: Color(0xFF111111),
                    thickness: 3.0,
                  ),
                  if (_isWebViewVisible && submissionDescription != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 16.0, left: 16.0, top: 16.0),
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
                                  initialHtml: submissionDescription,
                                ),
                              ),
                            );
                          }
                        },


                        child: SubmissionDescriptionWebView(
                          key: ValueKey(submissionDescription.hashCode),
                          submissionId: widget.uniqueNumber,
                          initialHtml: submissionDescription,
                          enableTextSelection: false,
                          forceHybridComposition: false,
                          onHeightChanged: (double height) {
                            if (!_webViewLoaded) {
                              Future.delayed(const Duration(milliseconds: 25), () {
                                if (mounted) {
                                  setState(() {
                                    _webViewLoaded = true;
                                  });
                                }
                              });
                            }
                          },
                        ),
                      ),
                    ),


                  const Divider(
                    height: 2.0,
                    color: Color(0xFF111111),
                    thickness: 2.0,
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
                  Padding(
                    padding: const EdgeInsets.only(right: 0.0, left: 0.0, top: 11.0, bottom: 0.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        _buildPublicationAndViewsRow(),

                        Padding(
                          padding: const EdgeInsets.only(bottom: 0.0, top: 11.0),
                          child: const Divider(
                            height: 3.0,
                            color: Color(0xFF111111),
                            thickness: 3.0,
                          ),
                        ),
                        SizedBox(
                          height: 50,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              /*
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

                               */
                              Expanded(
                                child: IconButton(
                                  icon: const Icon(
                                    Icons.mail_outline,
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
                                  icon: Icon(
                                    Icons.numbers,
                                    size: 26,
                                    color: _showTagsSection
                                        ? const Color(0xFFE09321)
                                        : Colors.grey,
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      _showTagsSection = !_showTagsSection;
                                    });
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

                        AnimatedSize(
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeInOut,
                          child: _showTagsSection ? _buildTagsPanel() : const SizedBox.shrink(),
                        ),

                      ],
                    ),
                  ),
                  const Divider(
                    height: 3.0,
                    color: Color(0xFF111111),
                    thickness: 3.0,
                  ),
                  const Divider(
                    height: 4.0,
                    color: Colors.black,
                    thickness: 4.0,
                  ),
                      ],
                    ),
                  ),
                  ..._buildCommentSlivers(),
                  SliverToBoxAdapter(child: SizedBox(height: keyboardHeight)),
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
          if (showLoadingIndicator)
            Container(
              color: const Color(0xFF000000),
              child: const Center(
                child: PulsatingLoadingIndicator(
                  size: 78.0,
                  assetPath: 'assets/icons/fathemed.png',
                ),
              ),
            ),
        ],
      ),
    ),
      bottomNavigationBar: showLoadingIndicator
          ? null
          : Container(
        color: Colors.black,
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              left: 8,
              right: 8,
              bottom: keyboardHeight > 0 ? keyboardHeight : 4,
              top: 8,
            ),
            child: Row(
              children: [
                ClipRect(
                  child: AnimatedSize(
                    duration: const Duration(milliseconds: 210),
                    curve: Curves.easeInOut,
                    alignment: Alignment.centerLeft,
                    child: ValueListenableBuilder<bool>(
                      valueListenable: _showScrollToTopNotifier,
                      builder: (context, show, _) {
                        return Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (show)
                              SizedBox(
                                width: 36,
                                height: 36,
                                child: FloatingActionButton.small(
                                  heroTag: 'scroll_top',
                                  backgroundColor: const Color(0xFFE09321),
                                  elevation: 0,
                                  onPressed: () {
                                    _scrollController.animateTo(
                                      0,
                                      duration: const Duration(milliseconds: 300),
                                      curve: Curves.easeOut,
                                    );
                                  },
                                  child: const Icon(Icons.arrow_upward, size: 18),
                                ),
                              ),
                            if (show) const SizedBox(width: 8),
                          ],
                        );
                      },
                    ),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () async {
                      final ok = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => AddCommentScreen(
                            submissionTitle: submissionTitle ?? '',
                            onSendComment: _addComment,
                            uniqueNumber: widget.uniqueNumber,
                          ),
                        ),
                      );
                      if (ok == true) _fetchPostDetails();
                    },
                    child: AbsorbPointer(
                      child: SizedBox(
                        height: 40,
                        child: TextField(
                          controller: _commentController,
                          readOnly: true,
                          decoration: InputDecoration(
                            hintText: 'Add a comment...',
                            hintStyle: const TextStyle(color: Colors.white54),
                            contentPadding:
                            const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                            filled: true,
                            fillColor: const Color(0xFF151515),
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
              ],
            ),
          ),
        ),
      ),
        ),
    );
  }


  Widget _buildPublicationAndViewsRow() {
    String? ratingLabel(String? r) {
      switch (r) {
        case 'general':
          return 'General';
        case 'mature':
          return 'Mature';
        case 'adult':
          return 'Adult';
        default:
          return null;
      }
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
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
              const SizedBox(width: 4),
              const Text(
                'Views',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        if (viewCount != null && favoritesCount >= 0)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 5.0),
            child: Icon(Icons.circle, size: 4, color: Colors.grey),
          ),
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
              const SizedBox(width: 4),
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
              const SizedBox(width: 4),
              const Text(
                'Comments',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        if (commentsCount >= 0 && ratingLabel(rating) != null)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 5.0),
            child: Icon(Icons.circle, size: 4, color: Colors.grey),
          ),
        if (commentsCount >= 0 && ratingLabel(rating) != null)
          Tooltip(
            message: 'Rating: ${ratingLabel(rating)}',
            child: Text(
              ratingLabel(rating)!,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: AppTheme.ratingTextColor(rating) ?? Colors.white,
              ),
            ),
          ),
      ],
    );
  }
  final _commentsSelectionKey = GlobalKey<SelectableRegionState>();

  List<Widget> _buildCommentSlivers() {
    if (comments.isEmpty) {
      return const [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.only(top: 10.0, bottom: 14.0, right: 8.0, left: 8.0),
            child: Text(
              "No comments.",
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
          ),
        ),
      ];
    }

    return [
      SliverPadding(
        padding: const EdgeInsets.only(top: 8.0, bottom: 0.0, right: 8.0, left: 8.0),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
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
                  final result = await Navigator.push<bool>(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ReplyScreen(
                        comment: comment,
                        uniqueNumber: widget.uniqueNumber,
                        isClassic: _isClassicUserPage,
                        onSendReply: (_) {},
                      ),
                    ),
                  );
                  if (result == true) {
                    _fetchPostDetails();
                  }
                },
                onUnhide: (comment['deleted'] == true && comment['hideLink'] != null)
                    ? () => _unhideComment(comment['hideLink'], "")
                    : null,
                handleLink: (url) async {
                  final commentHtml = comment['commentHtml'] ?? '';
                  await _handleCommentLink(context, url, commentHtml);
                },
              );
            },
            childCount: comments.length,
          ),
        ),
      ),
    ];
  }
}




