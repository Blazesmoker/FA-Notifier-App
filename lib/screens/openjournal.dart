import 'dart:async';
import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:extended_text/extended_text.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:url_launcher/url_launcher_string.dart';
import 'package:linkify/linkify.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:share_plus/share_plus.dart';
import '../network.dart';
import '../parsing_utils.dart';
import '../providers/timezone_provider.dart';
import '../utils/specialTextSpanBuilder.dart';
import '../widgets/PulsatingLoadingIndicator.dart';
import 'add_comment_screen.dart';
import 'add_journal_comment_screen.dart';
import 'create_journal.dart';
import 'editcommentscreen.dart';
import 'editjournalcommentscreen.dart';
import 'journal_reply_screen.dart';
import 'keyword_search_screen.dart';
import 'openpost.dart';
import 'user_profile_screen.dart';
import 'reply_screen.dart';
import 'avatardownloadscreen.dart';
import 'package:html/dom.dart' as dom;
import 'package:flutter_html/flutter_html.dart' as html_pkg;

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

class OpenJournal extends StatefulWidget {
  final String uniqueNumber;

  const OpenJournal({required this.uniqueNumber, Key? key}) : super(key: key);

  @override
  _OpenJournalState createState() => _OpenJournalState();
}

class _OpenJournalState extends State<OpenJournal> with WidgetsBindingObserver {
  String? profileImageUrl;
  String? username;
  String? submissionTitle;
  String? submissionDescription;
  DateTime? publicationTime;
  int commentsCount = 0;
  List<Map<String, dynamic>> comments = [];
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    iOptions: IOSOptions( 
    accountName: 'flutter_secure_storage_service',
    accessibility: KeychainAccessibility.first_unlock),
  );
  final TextEditingController _commentController = TextEditingController();
  bool _isTyping = false;

  String? authorDisplayName;
  String? authorUserName;
  String? authorSymbol;
  String? authorUserTitle;
  bool isJournalClassic = false;

  // User timezone and DST settings
  String? userTimezoneIanaName;
  bool isDstCorrectionApplied = false;

  // Watch/unwatch links
  String? watchLink;
  String? unwatchLink;
  bool isWatching = false;

  // Loading state and owner flag
  bool isLoading = true;
  bool isOwner = false;
  String? deleteLink;
  bool _isDeleting = false;
  bool _deleteLinkMatchesCurrentId(String link) {
    final m = RegExp(r'/controls/deletejournal/(\d+)/').firstMatch(link);
    return m != null && m.group(1) == widget.uniqueNumber;
  }

  // Additional post info
  String? category;
  String? type;
  String? species;
  String? gender;
  String? size;
  String? fileSize;
  List<String> keywords = [];



  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _fetchPostDetails().then((_) {
      _fetchUserPageLinks();          // fire & forget
    });

  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _commentController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    final keyboardVisible = WidgetsBinding.instance.window.viewInsets.bottom > 0;
    setState(() => _isTyping = keyboardVisible);
  }

  /// Dedicated helper to recover full link from a truncated comment HTML.
  String? _getFullLinkFromCommentHtml(String commentHtml, String truncatedUrl) {
    final document = html_parser.parse(commentHtml);
    for (var anchor in document.querySelectorAll('a.auto_link_shortened')) {
      if (anchor.text.trim() == truncatedUrl) {
        return anchor.attributes['title'] ?? anchor.attributes['href'];
      }
    }
    return null;
  }

  /// Helper for full submission description HTML.
  String? _getFullLinkFromFetchedHtml(String truncatedUrl, {String? htmlSource}) {
    final String? source = htmlSource ?? submissionDescription;
    if (source == null) return null;
    final document = html_parser.parse(source);
    for (var anchor in document.querySelectorAll('a.auto_link_shortened')) {
      if (anchor.text.trim() == truncatedUrl) {
        return anchor.attributes['title'] ?? anchor.attributes['href'];
      }
    }
    return null;
  }

  /// Link handler method.
  Future<void> _handleFALink(BuildContext context, String url, {String? htmlSource}) async {
    String fullUrlToMatch = url;
    if (htmlSource != null) {
      final recoveredLink = _getFullLinkFromCommentHtml(htmlSource, url);
      if (recoveredLink != null) {
        fullUrlToMatch = recoveredLink;
      }
    } else if (url.contains('.....')) {
      final recoveredLink = _getFullLinkFromFetchedHtml(url, htmlSource: htmlSource);
      if (recoveredLink != null) {
        fullUrlToMatch = recoveredLink;
      }
    }
    final Uri uri = Uri.parse(fullUrlToMatch);
    final String urlToMatch = uri.toString();

    // Gallery Folder Regex
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

    // User Regex
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

    // Submission/View Regex (unchanged, no username involved)
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

    // Fallback: Launch externally
    await launchUrlString(fullUrlToMatch, mode: LaunchMode.externalApplication);
  }

  Future<void> _fetchPostDetails() async {
    String? cookieA = await _secureStorage.read(key: 'fa_cookie_a');
    String? cookieB = await _secureStorage.read(key: 'fa_cookie_b');
    if (cookieA == null || cookieB == null) {
      setState(() {
        isLoading = false;
      });
      return;
    }
    final journalUrl = 'https://www.furaffinity.net/journal/${widget.uniqueNumber}/';
    final response = await httpClient.get(
      Uri.parse(journalUrl),
      headers: {
        'Cookie': 'a=$cookieA; b=$cookieB',
        'User-Agent': 'Mozilla/5.0 (compatible; YourApp/1.0)',
        'Accept-Encoding': 'gzip',
      },
    );
    if (response.statusCode == 200 || response.statusCode == 200) {
      final decodedBody = utf8.decode(response.bodyBytes, allowMalformed: true);
      var document = html_parser.parse(decodedBody);

      dom.Element? profileImgEl;
      String? displayName;
      String? authorSlug;
      String? symbol;
      String? userTitle;

      final modernDetails = document.querySelector('userpage-nav-user-details');
      final classicTitleBox = document.querySelector('td.journal-title-box');
      isJournalClassic = (modernDetails == null) && (classicTitleBox != null);

      if (!isJournalClassic && modernDetails != null) {
        final modernHeader = modernDetails.parent;
        profileImgEl = modernHeader?.querySelector('userpage-nav-avatar img');

        displayName = modernDetails
            .querySelector('a.c-usernameBlock__displayName span.js-displayName')
            ?.text
            .trim();

        final userNameA = modernDetails.querySelector('a.c-usernameBlock__userName') ??
            modernDetails.querySelector('a.c-usernameBlock__displayName');
        symbol = userNameA?.querySelector('span.c-usernameBlock__symbol')?.text.trim();

        final href = userNameA?.attributes['href'];
        if (href != null) {
          final path = Uri.parse(href).path.toLowerCase();
          final m = RegExp(r'^/user/([^/]+)/?$').firstMatch(path);
          if (m != null) authorSlug = m.group(1);
        }



        dom.Element? utSpan =
            modernDetails.querySelector('span.user-title') ??
                modernHeader?.querySelector('span.user-title') ??
                document.querySelector('userpage-nav-header span.user-title');

        if (utSpan != null) {

          if (utSpan.text.contains('|')) {

            final clone = (utSpan.clone(true) as dom.Element);

            clone.querySelectorAll('.hideonmobile').forEach((e) => e.remove());

            var t = clone.text.replaceAll('\u00A0', ' ')
                .replaceAll(RegExp(r'\s+'), ' ')
                .trim();

            final parts = t.split('|');
            final titleText = parts.first.trim();
            if (titleText.isNotEmpty) {
              userTitle = titleText;
            }
          }

        }
      } else {
        dom.Element? classicTable;
        var cur = classicTitleBox;
        while (cur != null && cur.localName != 'table') {
          cur = cur.parent;
        }
        classicTable = cur;

        profileImgEl = classicTable?.querySelector('td.avatar-box img.avatar') ??
            document.querySelector('td.avatar-box img.avatar');

        displayName = classicTitleBox
            ?.querySelector('a.c-usernameBlock__displayName span.js-displayName')
            ?.text
            ?.trim();

        final userNameA = classicTitleBox?.querySelector('a.c-usernameBlock__userName') ??
            classicTitleBox?.querySelector('a.c-usernameBlock__displayName');
        symbol = userNameA?.querySelector('span.c-usernameBlock__symbol')?.text.trim();

        final href = userNameA?.attributes['href'];
        if (href != null) {
          final path = Uri.parse(href).path.toLowerCase();
          final m = RegExp(r'^/user/([^/]+)/?$').firstMatch(path);
          if (m != null) authorSlug = m.group(1);
        }
      }


      bool ownerFound = document
          .querySelector('a.owner_edit_journal.action-link') != null;
      document
          .querySelectorAll('a.owner_edit_journal.action-link')
          .forEach((el) => el.remove());


      var titleElem = document.querySelector('div.no_overflow') ??
          document.querySelector('h2.journal-title');
      var descriptionElem = document.querySelector('div.journal-content.user-submitted-links') ??
          document.querySelector('div.journal-body');
      var publicationTimeElem = document.querySelector('div.section-header span.popup_date') ??
          document.querySelector('span.popup_date');

      setState(() {
        isOwner = ownerFound;

        final rawSrc = profileImgEl?.attributes['src'];
        profileImageUrl = (rawSrc == null) ? null
            : (rawSrc.startsWith('//') ? 'https:$rawSrc' : rawSrc);

        authorDisplayName = displayName;
        authorUserName    = authorSlug;
        authorSymbol      = (symbol == null || symbol!.isEmpty) ? '@' : symbol;
        authorUserTitle   = userTitle;

        username = authorSlug ?? username;

        submissionTitle = titleElem?.text.trim();
        submissionDescription = descriptionElem?.innerHtml.replaceAllMapped(
          RegExp(r'src="(//[^"]+)"|href="(//[^"]+)"'),
              (m) {
            final url = m.group(1) ?? m.group(2);
            return url != null ? m[0]!.replaceFirst('//', 'https://') : m[0]!;
          },
        );

        if (submissionDescription != null) {
          final descDoc = html_parser.parse(submissionDescription);
          for (final el in descDoc.querySelectorAll('a.auto_link_shortened')) {
            final full = el.attributes['title'] ?? el.attributes['href'];
            if (full != null) el.innerHtml = full;
          }
          submissionDescription = descDoc.body?.innerHtml ?? submissionDescription;
        }

        if (publicationTimeElem != null) {
          final rawTime = publicationTimeElem.attributes['title']?.trim();
          if (rawTime != null && rawTime.isNotEmpty) _parsePublicationTime(rawTime);
        }
      });
      if (isOwner) {
        await _fetchDeleteLink(cookieA, cookieB);
      }

      setState(() {
        isLoading = false;
      });
      unawaited(_fetchComments(decodedBody));
    } else {
      print('Failed to fetch journal details: ${response.statusCode}');
    }
  }



  Future<void> _fetchDeleteLink(String cookieA, String cookieB) async {
    int pageIndex = 1;
    String? found;
    while (pageIndex <= 10) {
      final controlUrl = 'https://www.furaffinity.net/controls/journal/$pageIndex/${widget.uniqueNumber}/';
      final response = await httpClient.get(
        Uri.parse(controlUrl),
        headers: {
          'Cookie': 'a=$cookieA; b=$cookieB',
          'User-Agent': 'Mozilla/5.0 (compatible; YourApp/1.0)',
        },
      );

      if (response.statusCode != 200) break;

      final document = html_parser.parse(response.body);

      final candidates = document.querySelectorAll('a.delete[onclick*="/controls/deletejournal/"]');

      for (final el in candidates) {
        final onclickAttr = el.attributes['onclick'] ?? '';

        final m = RegExp(r"showConfirm\('Are you sure you want to delete this journal\?','([^']+)'\)")
            .firstMatch(onclickAttr);
        if (m == null) continue;

        final relUrl = m.group(1)!;
        if (_deleteLinkMatchesCurrentId(relUrl)) {

          found = relUrl.startsWith('http')
              ? relUrl
              : 'https://www.furaffinity.net$relUrl';
          break;
        }
      }

      if (found != null) break;
      pageIndex++;
    }

    if (mounted) {
      setState(() {
        deleteLink = found;
      });
    }

    if (found == null) {
      debugPrint('Delete link not found or did not match journal ${widget.uniqueNumber}.');
    }
  }


  Future<void> _confirmAndDeleteJournal() async {
    if (_isDeleting) return;

    final titleForDialog = (submissionTitle == null || submissionTitle!.trim().isEmpty)
        ? '#${widget.uniqueNumber}'
        : submissionTitle!.trim();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm deletion'),
        content: Text('Are you sure you want to delete journal "$titleForDialog"?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Delete')),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isDeleting = true);

    try {
      final cookieA = await _secureStorage.read(key: 'fa_cookie_a');
      final cookieB = await _secureStorage.read(key: 'fa_cookie_b');
      if (cookieA == null || cookieB == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please log in to perform this action.'), backgroundColor: Colors.red),
        );
        return;
      }

      if (deleteLink == null || !_deleteLinkMatchesCurrentId(deleteLink!)) {
        await _fetchDeleteLink(cookieA, cookieB);
      }
      if (deleteLink == null || !_deleteLinkMatchesCurrentId(deleteLink!)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Safe delete failed: couldn't confirm delete link for this journal."),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      final uri = Uri.parse(deleteLink!);
      final resp = await httpClient.get(
        uri,
        headers: {
          'Cookie': 'a=$cookieA; b=$cookieB',
          'User-Agent': 'Mozilla/5.0 (compatible; YourApp/1.0)',
        },
      );


      if (resp.statusCode >= 200 && resp.statusCode < 400) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Journal "$titleForDialog" deleted.'), backgroundColor: Colors.green),
        );
        Navigator.of(context).pop(true);
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Delete failed (HTTP ${resp.statusCode}).'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error while deleting: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }
  }

  Future<void> _fetchUserPageLinks() async {
    if (username == null) return;
    String? cookieA = await _secureStorage.read(key: 'fa_cookie_a');
    String? cookieB = await _secureStorage.read(key: 'fa_cookie_b');
    if (cookieA == null || cookieB == null) return;
    final userPageUrl = 'https://www.furaffinity.net/user/$username/';
    final response = await httpClient.get(
      Uri.parse(userPageUrl),
      headers: {
        'Cookie': 'a=$cookieA; b=$cookieB',
        'User-Agent': 'Mozilla/5.0 (compatible; YourApp/1.0)',
      },
    );
    if (response.statusCode == 200) {
      var document = html_parser.parse(response.body);
      var watchLinkElement = document.querySelector('a.button.standard.go[href^="/watch/"]');
      var unwatchLinkElement = document.querySelector('a.button.standard.stop[href^="/unwatch/"]');
      setState(() {
        watchLink = watchLinkElement?.attributes['href'];
        unwatchLink = unwatchLinkElement?.attributes['href'];
        isWatching = unwatchLinkElement != null;
      });
    } else {
      print('Failed to fetch user page links: ${response.statusCode}');
    }
  }

  void _parsePublicationTime(String rawTime) {
    try {
      final format = DateFormat('MMM d, yyyy hh:mm a');
      DateTime naiveDateTime = format.parse(rawTime);
      if (isDstCorrectionApplied) {
        naiveDateTime = naiveDateTime.subtract(const Duration(hours: 1));
      }
      publicationTime = naiveDateTime.toUtc();
    } catch (e, stackTrace) {
      print("Error parsing publication time: $e");
      print("Stack trace: $stackTrace");
    }
  }

  String? getFormattedPublicationTime() {
    if (publicationTime == null) return null;
    final localTime = publicationTime!.toLocal();
    return DateFormat.yMMMd().add_jm().format(localTime);
  }

  Future<void> _sendWatchUnwatchRequest(String urlPath, {required bool shouldWatch}) async {
    String? cookieA = await _secureStorage.read(key: 'fa_cookie_a');
    String? cookieB = await _secureStorage.read(key: 'fa_cookie_b');
    if (cookieA == null || cookieB == null) {
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
      final response = await httpClient.get(
        Uri.parse(fullUrl),
        headers: {
          'Cookie': 'a=$cookieA; b=$cookieB',
          'User-Agent': 'Mozilla/5.0 (compatible; YourApp/1.0)',
        },
      );
      if (response.statusCode == 200) {
        await _fetchUserPageLinks();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${shouldWatch ? 'Now watching $username' : 'Stopped watching $username'}'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to ${shouldWatch ? 'watch' : 'unwatch'} user.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('An error occurred while trying to ${shouldWatch ? 'watch' : 'unwatch'} user.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }



  // Fetch comments
  Future<void> _fetchComments(String body) async {

    final document = await compute(parseHtml, body);

    // Selects both modern and classic comment containers
    final commentContainers = document.querySelectorAll('.comment_container, table.container-comment');
    List<Map<String, dynamic>> loadedComments = [];

    print("Number of comment containers found: ${commentContainers.length}");

    for (var commentContainer in commentContainers) {
      // Checks if comment is deleted in modern style or classic style
      final innerContainer = commentContainer.querySelector('comment-container');
      bool isDeleted = innerContainer?.classes.contains('deleted-comment-container') ?? false;


      bool isClassic = commentContainer.localName == 'table';


      bool isClassicDeleted = false;
      dom.Element? classicDeletedCell;
      if (isClassic) {
        classicDeletedCell = commentContainer.querySelector('td.comment-deleted');
        if (classicDeletedCell != null) {
          isClassicDeleted = true;
          isDeleted = true;
        }
      }


      // Width percentage / nesting
      double widthPercent = 100.0;
      if (!isClassic) {
        String? style = commentContainer.attributes['style'];
        if (style != null) {
          final widthRegex = RegExp(r'width\s*:\s*(\d+(?:\.\d+)?)%');
          final match = widthRegex.firstMatch(style);
          if (match != null) {
            widthPercent = double.tryParse(match.group(1) ?? '') ?? 100.0;
          }
        }
      } else {
        // Classic style: use table's "width" attribute
        String? tableWidth = commentContainer.attributes['width'];
        if (tableWidth != null) {
          String numericPart = tableWidth.replaceAll('%', '').trim();
          widthPercent = double.tryParse(numericPart) ?? 100.0;
        }
      }


      // Profile image
      String? profileImage = commentContainer.querySelector('.avatar img')?.attributes['src'];
      if (profileImage == null || profileImage.isEmpty) {
        profileImage = commentContainer.querySelector('img.avatar')?.attributes['src'];
      }
      if (profileImage != null && profileImage.startsWith('//')) {
        profileImage = 'https:$profileImage';
      }


      // Comment text & HTML
      String? commentText;
      String? commentHtml;

      if (isDeleted) {
        if (isClassicDeleted && classicDeletedCell != null) {
          // Classic hidden comment cell
          commentText = classicDeletedCell.text.trim();
          commentHtml = classicDeletedCell.innerHtml;
        } else {
          final deletedElement = commentContainer.querySelector('comment-user-text.comment_text');
          if (deletedElement != null) {
            commentText = deletedElement.text.trim();
            commentHtml = deletedElement.outerHtml;
          }
        }
      } else {
        var commentTextElement = commentContainer.querySelector('.comment_text .user-submitted-links');
        commentTextElement ??= commentContainer.querySelector('div.message-text');

        if (commentTextElement != null) {
          String rawHtml = commentTextElement.innerHtml;
          // Converts emoji <i> tags into placeholders.

          rawHtml = rawHtml.replaceAllMapped(
            // Handles <i class="smilie ..."></i>, <i class="smilie ..." />, and variations
            RegExp(r'<i\s+class="(smilie\s+[^"]+)"[^>]*>(?:\s*<\/i>)?|<i\s+class="(smilie\s+[^"]+)"[^>]*/?>',
                caseSensitive: false),
                (m) {
              final cls = (m.group(1) ?? m.group(2))!;
              return '[${cls.replaceAll(' ', '-')}]';
            },
          );
          rawHtml = rawHtml
              .replaceAll(RegExp(r'<i\s+class="bbcode\s+bbcode_i"[^>]*>', caseSensitive: false), '[[i]]')
              .replaceAll(RegExp(r'</i>', caseSensitive: false), '[[/i]]')

              // Bold
              .replaceAll(RegExp(r'<strong\s+class="bbcode\s+bbcode_b"[^>]*>', caseSensitive: false), '[[b]]')
              .replaceAll(RegExp(r'</strong>', caseSensitive: false), '[[/b]]')
              // (optional fallback if FA ever emits <b class="bbcode bbcode_b">)
              .replaceAll(RegExp(r'<b\s+class="bbcode\s+bbcode_b"[^>]*>', caseSensitive: false), '[[b]]')
              .replaceAll(RegExp(r'</b>', caseSensitive: false), '[[/b]]')

              // Underline
              .replaceAll(RegExp(r'<u\s+class="bbcode\s+bbcode_u"[^>]*>', caseSensitive: false), '[[u]]')
              .replaceAll(RegExp(r'</u>', caseSensitive: false), '[[/u]]');

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

      }


      // 5) Username, user title, icons
      final displayNameAnchor = commentContainer.querySelector('a.c-usernameBlock__displayName span.js-displayName');
      String? displayName = displayNameAnchor?.text.trim();

      String parsedSymbol = '';
      String parsedUserName = '';
      final userNameAnchor = commentContainer.querySelector('a.c-usernameBlock__userName');
      if (userNameAnchor != null) {
        final symbolElement = userNameAnchor.querySelector('span.c-usernameBlock__symbol');
        if (symbolElement != null) {
          parsedSymbol = symbolElement.text.trim();
        }
        final fullText = userNameAnchor.text.trim();
        parsedUserName = fullText.replaceFirst(parsedSymbol, '').trim();
      }
      final effectiveUserName = parsedUserName.isNotEmpty ? parsedUserName : displayName;
      final usernameForUI = effectiveUserName ?? "Anonymous";

      String? userTitle = commentContainer.querySelector('comment-title.custom-title')?.text.trim();
      userTitle ??= commentContainer.querySelector('span.custom-title.hideonmobile.font-small')?.text.trim();

      final iconBeforeElements = commentContainer.querySelectorAll('usericon-block-before img');
      final iconBeforeUrls = iconBeforeElements.map((elem) {
        String? src = elem.attributes['src'];
        if (src != null) {
          if (src.startsWith('//')) return 'https:$src';
          if (src.startsWith('/')) return 'https://www.furaffinity.net$src';
          return src;
        }
        return '';
      }).where((url) => url.isNotEmpty).toList();

      final iconAfterElements = commentContainer.querySelectorAll('usericon-block-after img');
      final iconAfterUrls = iconAfterElements.map((elem) {
        String? src = elem.attributes['src'];
        if (src != null) {
          if (src.startsWith('//')) return 'https:$src';
          if (src.startsWith('/')) return 'https://www.furaffinity.net$src';
          return src;
        }
        return '';
      }).where((url) => url.isNotEmpty).toList();


      // Date
      final dateElem = commentContainer.querySelector('.popup_date');
      final popupDateFull = dateElem?.attributes['title']?.trim();
      final popupDateRelative = dateElem?.text.trim();


      // Hide/unhide link
      String? hideLink;
      final hideElements = commentContainer.querySelectorAll('comment-hide');
      for (var element in hideElements) {
        final link = element.querySelector('a[href*="action=hide_comment"]');
        if (link != null) {
          hideLink = link.attributes['href'];
          break;
        }
      }
      if (hideLink != null && hideLink.startsWith('/')) {
        hideLink = 'https://www.furaffinity.net$hideLink';
      }


      // Extract comment ID from both "modern" or "classic" reply link
      dom.Element? replyAnchor = commentContainer.querySelector('.replyto_link');
      if (replyAnchor != null && replyAnchor.localName != 'a') {
        // If the element with .replyto_link isn’t the anchor itself, check its children.
        replyAnchor = replyAnchor.querySelector('a');
      }
      // Fallback for classic style if needed.
      replyAnchor ??= commentContainer.querySelector('td.reply-link a');

      String? commentId;
      if (replyAnchor != null) {
        final href = replyAnchor.attributes['href'] ?? '';
        final match = RegExp(r'/replyto/(?:journal/)?(\d+)/').firstMatch(href);
        if (match != null) {
          commentId = match.group(1); // e.g. "60584241"
          print('Parsed comment ID: $commentId');
        } else {
          print('[DEBUG] Original reply href: "$href"');
        }
      }



      // Extract edit link
      final editLinkElem = commentContainer.querySelector('comment-edit a.edit_link');
      String? editLink;
      if (editLinkElem != null) {
        editLink = editLinkElem.attributes['href'];
        if (editLink != null && editLink.startsWith('/')) {
          editLink = 'https://www.furaffinity.net$editLink';
        }
      }


      // Build comment map
      final commentMap = <String, dynamic>{
        'profileImage': profileImage,
        'displayName': displayName,
        'userName': effectiveUserName,
        'username': usernameForUI,
        'symbol': parsedSymbol.isNotEmpty ? parsedSymbol : '@',
        'userTitle': userTitle,
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
        'deleted': isDeleted,
        'hideLink': hideLink,
        'editLink': editLink,
      };

      // If deleted, adjust text and remove user data
      if (isDeleted) {
        String hiddenText = commentText ?? "";
        hiddenText = hiddenText.replaceAll(
            RegExp(r'Unhide\s+Comment(\s*<span.*?<\/span>)?', caseSensitive: false),
            ''
        ).trim();
        commentMap['text'] = hiddenText;
        commentMap['profileImage'] = null;
        commentMap['displayName'] = null;
        commentMap['userName'] = null;

        // If available, update hideLink with un-hide link from classic style
        final unhideLinkElement = commentContainer.querySelector('div.font-small.floatright a[href*="action=unhide_comment"]');
        if (unhideLinkElement != null) {
          String? unhideLink = unhideLinkElement.attributes['href'];
          if (unhideLink != null && unhideLink.startsWith('/')) {
            unhideLink = 'https://www.furaffinity.net$unhideLink';
          }
          commentMap['hideLink'] = unhideLink;
        }
      } else {
        // For non-deleted comments, ensure important fields
        if (profileImage == null || effectiveUserName == null || commentText == null) {
          continue;
        }
      }

      // Add to the list
      loadedComments.add(commentMap);
    }

    // Update state with all parsed comments
    setState(() {
      comments = loadedComments;
      commentsCount = loadedComments.length;
    });
  }



  Future<void> hideComment(String hideLink, String commentId) async {
    final shouldHide = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Confirmation"),
          content: const Text("Are you sure you want to hide this comment?"),
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
        if (cookieA == null || cookieB == null) return;
        final response = await httpClient.get(
          Uri.parse(hideLink),
          headers: {
            'Cookie': 'a=$cookieA; b=$cookieB',
            'User-Agent': 'Mozilla/5.0 (compatible; YourApp/1.0)',
          },
        );
        if (response.statusCode == 200) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Comment successfully hidden!"),
              backgroundColor: Colors.green,
            ),
          );
          await _fetchPostDetails();
        } else {
          print('Failed to hide comment. Status code: ${response.statusCode}');
        }
      } catch (e) {
        print('Error hiding comment: $e');
      }
    }
  }

  Future<void> _unhideComment(String unhideLink, String commentId) async {
    final shouldUnhide = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Confirmation"),
          content: const Text("Are you sure you want to unhide this comment?"),
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
        final response = await httpClient.get(
          Uri.parse(unhideLink),
          headers: {
            'Cookie': 'a=$cookieA; b=$cookieB',
            'User-Agent': 'Mozilla/5.0 (compatible; YourApp/1.0)',
          },
        );
        if (response.statusCode == 200) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Comment successfully un-hidden!"),
              backgroundColor: Colors.green,
            ),
          );
          await _fetchPostDetails();
        } else {
          print('Failed to unhide comment. Status code: ${response.statusCode}');
        }
      } catch (e) {
        print('Error un-hiding comment: $e');
      }
    }
  }

  void _sharePost() {
    final postUrl = 'https://www.furaffinity.net/journal/${widget.uniqueNumber}/';
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
        'popupDateFull': DateFormat('MMM d, yyyy hh:mm a').format(DateTime.now()),
        'commentId': null,
        'deleted': false,
      });
      commentsCount = commentsCount + 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    return Scaffold(
      appBar: AppBar(
        title: const Text("Journal"),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              switch (value) {
                case 'share':
                  _sharePost();
                  break;
                case 'edit':
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => CreateJournalScreen(
                        uniqueNumber: widget.uniqueNumber,
                      ),
                    ),
                  ).then((_) => _fetchPostDetails());
                  break;
                case 'delete':
                  if (!isOwner) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('You do not have permission to delete this journal.')),
                    );
                    break;
                  }
                  unawaited(_confirmAndDeleteJournal());
                  break;
              }
            },
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              const PopupMenuItem<String>(
                value: 'share',
                child: Text('Share'),
              ),
              if (isOwner) const PopupMenuItem<String>(
                value: 'edit',
                child: Text('Edit'),
              ),
              if (isOwner) const PopupMenuItem<String>(
                value: 'delete',
                child: Text('Delete'),
              ),
            ],
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: PulsatingLoadingIndicator(size: 78.0, assetPath: 'assets/icons/fathemed.png'))
        : GestureDetector(
    behavior: HitTestBehavior.deferToChild,
        onTap: () {
          FocusScope.of(context).unfocus();
        },
    child: SelectionArea(
    key: _journalSelectionKey,
    child: RefreshIndicator(
        onRefresh: _fetchPostDetails,
        child: CustomScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
                child: Card(
                  color: const Color(0xFF151515),

                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [

                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (profileImageUrl != null)
                              Padding(
                                padding: const EdgeInsets.only(right: 8.0, top: 4.0),
                                child: GestureDetector(
                                  onTap: () {
                                    if (authorUserName != null && authorUserName!.isNotEmpty) {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => UserProfileScreen(
                                            nickname: authorUserName!,
                                          ),
                                        ),
                                      );
                                    }
                                  },
                                  child: CachedNetworkImage(
                                    imageUrl: profileImageUrl!,
                                    width: 46,
                                    height: 46,
                                    fit: BoxFit.cover,
                                    placeholder: (context, url) => Image.asset(
                                      'assets/images/defaultpic.gif',
                                      width: 46, height: 46, fit: BoxFit.cover,
                                    ),
                                    errorWidget: (context, url, error) => Image.asset(
                                      'assets/images/defaultpic.gif',
                                      width: 46, height: 46, fit: BoxFit.cover,
                                    ),
                                  ),
                                ),
                              ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [

                                  Text(
                                    authorDisplayName ?? authorUserName ?? 'Anonymous',
                                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                                    overflow: TextOverflow.ellipsis,
                                  ),

                                  if (authorUserName != null && authorUserName!.isNotEmpty)
                                    Text(
                                      '${(authorSymbol == null || authorSymbol!.isEmpty) ? '@' : authorSymbol!}${authorUserName!}',
                                      style: const TextStyle(fontSize: 11, color: Color(0xFFE09321)),
                                    ),

                                  if (!isJournalClassic && (authorUserTitle ?? '').isNotEmpty)
                                    Text(
                                      authorUserTitle!,
                                      style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),


                        Divider(color: Colors.grey.shade900, thickness: 1.5, height: 24),


                        Text(
                          submissionTitle ?? '',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                        ),


                        const SizedBox(height: 6),
                        Text('Posted on: ${getFormattedPublicationTime() ?? ''}'),


                        Divider(color: Colors.grey.shade900, thickness: 1.5, height: 24),


                        Theme(
                            data: Theme.of(context).copyWith(
                              textSelectionTheme: TextSelectionThemeData(
                                selectionColor: const Color(0xFFE09321).withOpacity(0.4),
                                selectionHandleColor: const Color(0xFFE09321),
                              ),
                            ),
                        child: SelectionArea(
                          child: html_pkg.Html(
                            data: submissionDescription ?? '',
                            style: {
                              "body": html_pkg.Style(
                                textAlign: TextAlign.left,
                                fontSize: html_pkg.FontSize(16),
                                padding: html_pkg.HtmlPaddings.zero,
                                margin: html_pkg.Margins.zero,
                                backgroundColor: Colors.transparent,
                              ),
                              "a": html_pkg.Style(
                                textDecoration: TextDecoration.none,
                                color: const Color(0xFFE09321),
                              ),
                              "hr": html_pkg.Style(
                                padding: html_pkg.HtmlPaddings.symmetric(vertical: 8),
                                margin: html_pkg.Margins.symmetric(vertical: 8),
                                height: html_pkg.Height(1),
                              ),

                            },
                            onLinkTap: (url, _, __) => _handleFALink(context, url!),
                            extensions: [
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
                                      return const SizedBox.shrink();
                                  }
                                },
                              ),
                              html_pkg.TagExtension(
                                tagsToExtend: {"img"},
                                builder: (html_pkg.ExtensionContext context) {
                                  final src = context.attributes['src'];
                                  if (src == null) return const SizedBox.shrink();
                                  final resolvedUrl = src.startsWith('//') ? 'https:$src' : src;
                                  // Check if this image is a profile emoji.
                                  if (resolvedUrl.contains("a.furaffinity.net") &&
                                      resolvedUrl.endsWith(".gif")) {
                                    return CachedNetworkImage(
                                      imageUrl: resolvedUrl,
                                      width: 50, // profile emoji size.
                                      height: 50,
                                      fit: BoxFit.contain,
                                      placeholder: (context, url) => const SizedBox(
                                        width: 50,
                                        height: 50,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      ),
                                      errorWidget: (context, url, error) => Image.asset(
                                        'assets/images/defaultpic.gif',
                                        width: 50,
                                        height: 50,
                                        fit: BoxFit.contain,
                                      ),
                                    );
                                  }

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
                        )
                      )




                      ],

                    ),
                  ),
                ),
              ),
            ),
            const SliverToBoxAdapter(
              child: const Divider(
                height: 3.0,
                color: Color(0xFF111111),
                thickness: 3.0,
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 12.0),
                child: Center(
                  child: Text(
                    commentsCount > 0 ? '$commentsCount Comments' : 'No Comments',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
            const SliverToBoxAdapter(
              child: const Divider(
                height: 3.0,
                color: Color(0xFF111111),
                thickness: 3.0,
              ),
            ),
            const SliverToBoxAdapter(
              child: SizedBox(height: 8),
            ),

            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                      (context, index) {
                    final comment = comments[index];
                    return CommentWidget(
                      key: ValueKey(comment['commentId'] ?? index),
                      comment: comment,
                      onHide: () async {
                        hideComment(comment['hideLink'], comment['commentId']);
                      },
                      onEdit: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => EditJournalCommentScreen(
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
                      },
                      onReply: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => JournalReplyScreen(
                              submissionId: widget.uniqueNumber,
                              commentId: comment['commentId'] ?? '',
                              onSendReply: (replyText) {
                                // handle reply
                              },
                              username: comment['username'] ?? 'Anonymous',
                              profileImage: comment['profileImage'] ?? '',
                              commentText: comment['text'] ?? '',
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
                        _unhideComment(comment['hideLink'], comment['commentId'] ?? '');
                      }
                          : null,
                      handleLink: (url) async {
                        final commentHtml = comment['commentHtml'] ?? '';
                        await _handleFALink(context, url, htmlSource: commentHtml);
                      },
                    );
                  },
                  childCount: comments.length,
                ),
              ),
            ),

            SliverToBoxAdapter(child: SizedBox(height: keyboardHeight + 20)),
          ],
        ),
      ),
    ),
      ),
      bottomNavigationBar: isLoading
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
                if (comments.isNotEmpty)
                  SizedBox(
                    width: 36,
                    height: 36,
                    child: FloatingActionButton.small(
                      heroTag: 'journal_scroll_top',
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
                const SizedBox(width: 8),
                Expanded(
                  child: GestureDetector(
                    onTap: () async {
                      final ok = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => AddJournalCommentScreen(
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
                            hintText: 'Add a comment…',
                            hintStyle: const TextStyle(color: Colors.white54),
                            contentPadding:
                            const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                            filled: true,
                            fillColor: const Color(0xFF151515),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide.none,
                            ),
                            suffixIcon:
                            const Icon(Icons.send, color: Colors.white54),
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

    );
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
}


final GlobalKey<SelectionAreaState> _journalSelectionKey = GlobalKey();

/// A stateful widget for an individual comment.
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
  _CommentWidgetState createState() =>
      _CommentWidgetState();
}

class _CommentWidgetState extends State<CommentWidget> {
  bool _showFullDate = false;

  @override
  Widget build(BuildContext context) {
    double widthPercent =
    (widget.comment['width'] ?? 100).toDouble();
    int nestingLevel =
    ((100.0 - widthPercent) / 3.0).round().clamp(0, 4);
    double leftPadding = nestingLevel * 16.0;
    if (widget.comment['deleted'] == true) {
      return Padding(
        padding:
        EdgeInsets.only(left: leftPadding, bottom: 6.0),
        child: Container(
          padding: const EdgeInsets.symmetric(
              vertical: 16.0, horizontal: 12.0),
          decoration: BoxDecoration(
            color: Colors.grey.shade900,
            borderRadius: BorderRadius.circular(4.0),
          ),
          child: Row(
            mainAxisAlignment:
            MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  widget.comment['text'] ?? '',
                  style: const TextStyle(
                      fontSize: 12, color: Colors.grey),
                ),
              ),
              if (widget.comment['hideLink'] != null)
                TextButton(
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 0),
                    tapTargetSize:
                    MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: widget.onUnhide,
                  child: const Text(
                    'Unhide',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 14),
                  ),
                ),
            ],
          ),
        ),
      );
    }
    return Padding(
      padding:
      EdgeInsets.only(left: leftPadding, bottom: 6.0),
      child: Container(
        padding: const EdgeInsets.only(
            right: 12.0,
            left: 12.0,
            top: 8.0,
            bottom: 2.0),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF0b0b0b),
              Color(0xFF202020)
            ],
          ),
          borderRadius: BorderRadius.circular(8.0),
        ),
        child: Column(
          crossAxisAlignment:
          CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment:
              CrossAxisAlignment.start,
              children: [
                if (widget.comment['profileImage'] != null)
                  Padding(
                    padding: const EdgeInsets.only(
                        right: 8.0, top: 4.0),
                    child: GestureDetector(
                      onTap: () {
                        if (widget.comment['username'] !=
                            null) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  UserProfileScreen(
                                    nickname: widget.comment[
                                    'username'],
                                  ),
                            ),
                          );
                        }
                      },
                      child: CachedNetworkImage(
                        imageUrl: widget.comment[
                        'profileImage'],
                        width: 46,
                        height: 46,
                        fit: BoxFit.cover,
                        placeholder:
                            (context, url) =>
                            Image.asset(
                              'assets/images/defaultpic.gif',
                              width: 46,
                              height: 46,
                              fit: BoxFit.cover,
                            ),
                        errorWidget:
                            (context, url, error) =>
                            Image.asset(
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
                    crossAxisAlignment:
                    CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (widget.comment[
                          'iconBeforeUrls'] !=
                              null &&
                              widget.comment[
                              'iconBeforeUrls']
                                  .isNotEmpty)
                            ...widget.comment[
                            'iconBeforeUrls']
                                .map((url) {
                              final isEditedIcon =
                              url.contains(
                                  'edited.png');
                              return Padding(
                                padding:
                                const EdgeInsets.only(
                                    right: 4.0),
                                child: Image.network(
                                  url,
                                  width: 16,
                                  height: 16,
                                  color: isEditedIcon
                                      ? Colors.white
                                      : null,
                                  colorBlendMode:
                                  isEditedIcon
                                      ? BlendMode
                                      .srcIn
                                      : null,
                                ),
                              );
                            }),
                          Flexible(
                            child: Text(
                              widget.comment[
                              'displayName'] ??
                                  widget.comment[
                                  'username'] ??
                                  'Anonymous',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight:
                                FontWeight.bold,
                              ),
                              overflow:
                              TextOverflow.ellipsis,
                            ),
                          ),
                          if (widget.comment[
                          'iconAfterUrls'] !=
                              null &&
                              widget.comment[
                              'iconAfterUrls']
                                  .isNotEmpty)
                            ...widget.comment[
                            'iconAfterUrls']
                                .map((url) =>
                                Padding(
                                  padding:
                                  const EdgeInsets.only(
                                      left:
                                      4.0),
                                  child: Image.network(
                                    url,
                                    width: 16,
                                    height: 16,
                                  ),
                                )),
                          if (widget.comment[
                          'isOP'] ==
                              true)
                            const Padding(
                              padding:
                              EdgeInsets.only(
                                  left: 4.0),
                              child: Text(
                                'OP',
                                style: TextStyle(
                                  color: Colors.blue,
                                  fontSize: 13,
                                  fontWeight:
                                  FontWeight.bold,
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
                      if ((widget.comment[
                      'userTitle'] ??
                          '')
                          .isNotEmpty)
                        Text(
                          widget.comment['userTitle'],
                          style: TextStyle(
                            fontSize: 12,
                            color:
                            Colors.grey.shade400,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(
                  left: 0.0,
                  right: 8.0,
                  top: 11.0,
                  bottom: 1.0),
              child: Theme(
                data: Theme.of(context).copyWith(
                  textSelectionTheme:
                  TextSelectionThemeData(
                    selectionColor: Color(0xFFE09321)
                        .withOpacity(0.4),
                    selectionHandleColor:
                    const Color(0xFFE09321),
                  ),
                ),
                child: ExtendedText(
                  widget.comment['text'] ?? '',
                  specialTextSpanBuilder:
                  EmojiSpecialTextSpanBuilder(
                    onTapLink: widget.handleLink,
                  ),
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade300,
                  ),
                ),
              ),
            ),
            Row(
              mainAxisAlignment:
              MainAxisAlignment.spaceBetween,
              children: [
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _showFullDate =
                      !_showFullDate;
                    });
                  },
                  child: Padding(
                    padding:
                    const EdgeInsets.symmetric(
                        vertical: 12.0),
                    child: Text(
                      _showFullDate
                          ? (widget.comment[
                      'popupDateFull'] ??
                          widget.comment[
                          'popupDateRelative'] ??
                          '')
                          : (widget.comment[
                      'popupDateRelative'] ??
                          ''),
                      style: TextStyle(
                        fontSize: 12,
                        color:
                        Colors.grey.shade400,
                      ),
                    ),
                  ),
                ),
                Row(
                  children: [
                    if (widget.comment[
                    'hideLink'] !=
                        null)
                      IconButton(
                        padding: EdgeInsets.zero,
                        constraints:
                        const BoxConstraints(),
                        icon: const Icon(
                            Icons.visibility_off,
                            size: 16,
                            color: Colors.white),
                        onPressed: widget.onHide,
                      ),
                    if (widget.comment[
                    'editLink'] !=
                        null)
                      TextButton(
                        style:
                        TextButton.styleFrom(
                          padding:
                          const EdgeInsets.only(
                              left: 4.0,
                              right: 8),
                          minimumSize:
                          const Size(0, 0),
                          tapTargetSize:
                          MaterialTapTargetSize
                              .shrinkWrap,
                        ),
                        onPressed: widget.onEdit,
                        child: Row(
                          mainAxisSize:
                          MainAxisSize.min,
                          children: const [
                            Icon(Icons.edit,
                                size: 16,
                                color: Colors.white),
                            SizedBox(width: 4),
                            Text('Edit',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 14)),
                          ],
                        ),
                      ),
                    TextButton(
                      style:
                      TextButton.styleFrom(
                        padding:
                        const EdgeInsets.only(
                            left: 6),
                        minimumSize:
                        const Size(0, 0),
                        tapTargetSize:
                        MaterialTapTargetSize
                            .shrinkWrap,
                      ),
                      onPressed: widget.onReply,
                      child: Row(
                        mainAxisSize:
                        MainAxisSize.min,
                        children: const [
                          Icon(Icons.reply,
                              size: 19,
                              color: Colors.white),
                          SizedBox(width: 4),
                          Text('Reply',
                              style: TextStyle(
                                  color:
                                  Colors.white,
                                  fontSize: 14)),
                        ],
                      ),
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