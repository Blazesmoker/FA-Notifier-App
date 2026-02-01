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
import '../services/fa_http.dart';
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
import 'openjournal_comments.dart';
import 'package:html/dom.dart' as dom;
import 'package:flutter_html/flutter_html.dart' as html_pkg;
import '../utils/fa_link_handler.dart';
import '../utils/utils.dart';
import 'openjournal_api_service.dart';

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
  String? publicationTimeRaw;
  int commentsCount = 0;
  List<Map<String, dynamic>> comments = [];
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    iOptions: IOSOptions(
        accountName: 'flutter_secure_storage_service',
        accessibility: KeychainAccessibility.first_unlock),
  );
  late final OpenJournalApiService _api;
  final TextEditingController _commentController = TextEditingController();
  bool _isTyping = false;
  final ValueNotifier<bool> _showScrollToTopNotifier = ValueNotifier<bool>(false);

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

  // Favorite links
  String? favoriteLink;
  String? unfavoriteLink;
  bool isFavorited = false;

  // Block/unblock links
  String? blockLink;
  String? unblockLink;
  bool isBlocked = false;

  // Media links
  String? fullViewImageUrl;
  String? fileLink;

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
    _scrollController.addListener(_onScroll);
    _api = OpenJournalApiService(_secureStorage);
    // Only fetch the journal itself on open.
    // Extra "helper" fetches (user-page links, delete key) are done *on-demand*
    // when the user taps the relevant action, to avoid spammy requests.
    _fetchPostDetailsNew();

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

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final shouldShow = _scrollController.offset > 350;
    if (shouldShow == _showScrollToTopNotifier.value) return;
    _showScrollToTopNotifier.value = shouldShow;
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
  String _getFullLinkFromFetchedHtml(String truncatedUrl, {String? htmlSource}) {
    final String? source = htmlSource ?? submissionDescription;
    if (source == null) return truncatedUrl;
    final document = html_parser.parse(source);
    for (var anchor in document.querySelectorAll('a.auto_link_shortened')) {
      if (anchor.text.trim() == truncatedUrl) {
        return anchor.attributes['title'] ?? anchor.attributes['href'] ?? truncatedUrl;
      }
    }
    return truncatedUrl;
  }

  Future<void> _fetchPostDetailsNew() async {
    try {
      final result = await _api.fetchJournal(widget.uniqueNumber);
      try {
        final String titleLower = (result.title ?? '').toLowerCase();
        final String descLower = (result.submissionDescription ?? '').toLowerCase();
        final String rawLower = (result.dateTimeRaw ?? '').toLowerCase();

        final bool looksLikeSystemError = titleLower.contains('system error') ||
            descLower.contains('not in our database') ||
            descLower.contains('this submission does not exist') ||
            titleLower.contains('not in our database') ||
            rawLower.contains('not in our database');

        if (looksLikeSystemError) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('This journal does not exist or has been deleted'),
                backgroundColor: Colors.red,
                duration: Duration(seconds: 3),
              ),
            );

            Future.delayed(const Duration(milliseconds: 400), () {
              if (!mounted) return;
              Navigator.of(context).pop();
            });
          });
          return;
        }
      } catch (e) {
        debugPrint('Error while checking for system-error markers: $e');
      }
      setState(() {
        isJournalClassic = result.isJournalClassic;
        isOwner = result.ownerEditLink != null;
        profileImageUrl = result.profileImageUrl;
        authorDisplayName = result.displayName;
        authorUserName = result.authorSlug;
        authorSymbol = result.symbol;
        authorUserTitle = result.userTitle;
        submissionDescription = result.submissionDescription;
        submissionTitle = result.title;
        publicationTime = result.dateTime;
        publicationTimeRaw = result.dateTimeRaw;
        commentsCount = result.commentsCount;
        favoriteLink = result.favoriteLink;
        unfavoriteLink = result.unfavoriteLink;
        isFavorited = result.isFavorited;
        watchLink = result.watchLink;
        unwatchLink = result.unwatchLink;
        isWatching = result.isWatching;
        blockLink = result.blockLink;
        unblockLink = result.unblockLink;
        isBlocked = result.isBlocked;
        category = result.category;
        type = result.type;
        species = result.species;
        gender = result.gender;
        keywords = result.keywords;
        fullViewImageUrl = result.fullViewImageUrl;
        fileLink = result.fileLink;
        deleteLink = result.deleteLink;
        isLoading = false;
      });

      if (publicationTime == null && publicationTimeRaw != null) {
        _parsePublicationTime(publicationTimeRaw!);
      }

      if (result.commentBodies.isNotEmpty) {
        setState(() {
          comments = result.commentBodies;
          commentsCount = result.commentsCount;
        });
      } else if (submissionDescription != null) {
        unawaited(_fetchCommentsNew(submissionDescription!));
      }
    } catch (e) {
      setState(() => isLoading = false);
      debugPrint('Failed to fetch journal details: $e');

      if (!mounted) return;

      final lower = e.toString().toLowerCase();
      final bool isNotFound = (e is JournalNotFoundException) ||
          lower.contains('not in our database') ||
          lower.contains('does not exist') ||
          lower.contains('deleted') ||
          lower.contains('not found');

      final String message = isNotFound
          ? 'This journal does not exist or has been deleted'
          : 'Failed to load journal';

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );

        Future.delayed(const Duration(milliseconds: 400), () {
          if (!mounted) return;
          Navigator.of(context).pop();
        });
      });
    }

  }

  Future<void> _fetchDeleteLinkFallback() async {
    try {
      final key = await _api.fetchDeleteKey(widget.uniqueNumber);
      if (key != null && key.trim().isNotEmpty) {
        setState(() {
          // Controls page returns a delete "key"; construct a safe delete URL.
          deleteLink =
              'https://www.furaffinity.net/controls/deletejournal/${widget.uniqueNumber}/?key=${Uri.encodeQueryComponent(key.trim())}';
        });
      }
    } catch (e) {
      debugPrint('Failed to fetch delete key: $e');
    }
  }

  Future<void> _fetchUserPageLinksNew() async {
    final slug = authorUserName ?? username;
    if (slug == null) return;
    try {
      final links = await _api.fetchUserPageLinks(slug);
      setState(() {
        watchLink = links['watchLink'];
        unwatchLink = links['unwatchLink'];
        blockLink = links['blockLink'];
        unblockLink = links['unblockLink'];
        isWatching = unwatchLink != null;
        isBlocked = unblockLink != null;
      });
    } catch (e) {
      debugPrint('Failed to fetch user page links: $e');
    }
  }

  Future<void> _fetchCommentsNew(String body) async {
    try {
      final parsed = await _api.fetchCommentsFromBody(body);
      if (mounted) {
        setState(() {
          comments = parsed;
        });
      }
    } catch (e) {
      debugPrint('Failed to parse comments: $e');
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
        showAppSnackBar(context, 'Please log in to perform this action.', backgroundColor: Colors.red);
        return;
      }

      if (deleteLink == null || !_deleteLinkMatchesCurrentId(deleteLink!)) {
        await _fetchDeleteLinkFallback();
      }
      if (deleteLink == null || !_deleteLinkMatchesCurrentId(deleteLink!)) {
        showAppSnackBar(context,
            "Safe delete failed: couldn't confirm delete link for this journal.",
            backgroundColor: Colors.red);
        return;
      }

      final uri = Uri.parse(deleteLink!);
      final resp = await httpClient.get(
        uri,
        headers: {
          'Cookie': 'a=$cookieA; b=$cookieB',
          'User-Agent': FAHttp.userAgent,
        },
      );


      if (resp.statusCode >= 200 && resp.statusCode < 400) {
        if (!mounted) return;
        showAppSnackBar(context, 'Journal "$titleForDialog" deleted.', backgroundColor: Colors.green);
        Navigator.of(context).pop(true);
      } else {
        if (!mounted) return;
        showAppSnackBar(context,
            'Delete failed (HTTP ${resp.statusCode}).',
            backgroundColor: Colors.red);
      }
    } catch (e) {
      if (!mounted) return;
      showAppSnackBar(context, 'Error while deleting: $e', backgroundColor: Colors.red);
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }
  }

  void _parsePublicationTime(String rawTime) {
    try {
      final trimmed = rawTime.trim();
      if (trimmed.isEmpty) return;
      final lower = trimmed.toLowerCase();
      // Skip relative strings like "a week ago", "4 months ago", "a year ago".
      if (lower.contains('ago')) {
        return;
      }
      // Skip anything without a digit; these aren't absolute dates.
      if (!RegExp(r'\d').hasMatch(trimmed)) {
        return;
      }

      final formats = [
        DateFormat("MMMM d, yyyy h:mm:ss a"),
        DateFormat("MMMM d, yyyy hh:mm:ss a"),
        DateFormat("MMMM d, yyyy h:mm a"),
        DateFormat("MMMM d, yyyy hh:mm a"),
        DateFormat("MMM d, yyyy h:mm a"),
        DateFormat("MMM d, yyyy hh:mm a"),
        DateFormat("MMM d yyyy h:mm a"),
        DateFormat("yyyy-MM-dd HH:mm:ss"),
      ];

      DateTime? parsed;

      for (final fmt in formats) {
        try {
          parsed = fmt.parse(trimmed, true);
          break;
        } catch (_) {}
      }

      parsed ??= DateTime.tryParse(trimmed);

      if (parsed != null) {
        if (isDstCorrectionApplied) {
          parsed = parsed.subtract(const Duration(hours: 1));
        }
        publicationTime = parsed.toUtc();
      }
    } catch (e, stackTrace) {
      debugPrint("Error parsing publication time: $e");
      debugPrint("Stack trace: $stackTrace");
    }
  }

  String? getFormattedPublicationTime() {
    if (publicationTimeRaw != null && publicationTimeRaw!.isNotEmpty) {
      return publicationTimeRaw;
    }
    if (publicationTime == null) return null;
    final localTime = publicationTime!.toLocal();
    return DateFormat.yMMMd().add_jm().format(localTime);
  }


  Future<void> _sendWatchUnwatchRequest(String urlPath, {required bool shouldWatch}) async {
    String? cookieA = await _secureStorage.read(key: 'fa_cookie_a');
    String? cookieB = await _secureStorage.read(key: 'fa_cookie_b');
    if (cookieA == null || cookieB == null) {
      showAppSnackBar(context,
          'Please log in to perform this action.',
          backgroundColor: Colors.red);
      return;
    }
    final fullUrl = 'https://www.furaffinity.net$urlPath';
    try {
      final response = await httpClient.get(
        Uri.parse(fullUrl),
        headers: {
          'Cookie': 'a=$cookieA; b=$cookieB',
          'User-Agent': FAHttp.userAgent,
        },
      );
      if (response.statusCode == 200) {
        await _fetchUserPageLinksNew();
        showAppSnackBar(context,
            '${shouldWatch ? 'Now watching $username' : 'Stopped watching $username'}',
            backgroundColor: Colors.green);
      } else {
        showAppSnackBar(context,
            'Failed to ${shouldWatch ? 'watch' : 'unwatch'} user.',
            backgroundColor: Colors.red);
      }
    } catch (e) {
      showAppSnackBar(context,
          'An error occurred while trying to ${shouldWatch ? 'watch' : 'unwatch'} user.',
          backgroundColor: Colors.red);
    }
  }
  // (legacy _fetchComments removed; use _fetchCommentsNew)
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
            'User-Agent': FAHttp.userAgent,
          },
        );
        if (response.statusCode == 200) {
          showAppSnackBar(context, "Comment successfully hidden!", backgroundColor: Colors.green);
          await _fetchPostDetailsNew();
        } else {
          debugPrint('Failed to hide comment. Status code: ${response.statusCode}');
        }
      } catch (e) {
        debugPrint('Error hiding comment: $e');
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
            'User-Agent': FAHttp.userAgent,
          },
        );
        if (response.statusCode == 200) {
          showAppSnackBar(context, "Comment successfully un-hidden!", backgroundColor: Colors.green);
          await _fetchPostDetailsNew();
        } else {
          debugPrint('Failed to unhide comment. Status code: ${response.statusCode}');
        }
      } catch (e) {
        debugPrint('Error un-hiding comment: $e');
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
            position: PopupMenuPosition.under,
            offset: const Offset(0, 8),
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
                  ).then((_) => _fetchPostDetailsNew());
                  break;
                case 'delete':
                  if (!isOwner) {
                    showAppSnackBar(context, 'You do not have permission to delete this journal.', backgroundColor: Colors.red);
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
        onRefresh: _fetchPostDetailsNew,
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
                                  child: Image.network(
                                    profileImageUrl!,
                                    width: 46,
                                    height: 46,
                                    fit: BoxFit.cover,
                                    loadingBuilder: (context, child, loadingProgress) {
                                      if (loadingProgress == null) {
                                        return child;
                                      }
                                      return Image.asset(
                                        'assets/images/defaultpic.gif',
                                        width: 46,
                                        height: 46,
                                        fit: BoxFit.cover,
                                      );
                                    },
                                    errorBuilder: (context, error, stackTrace) {
                                      return Image.asset(
                                        'assets/images/defaultpic.gif',
                                        width: 46,
                                        height: 46,
                                        fit: BoxFit.cover,
                                      );
                                    },
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
                            onLinkTap: (url, _, __) => handleFALink(context, url!, htmlSource: submissionDescription, getFullUrl: _getFullLinkFromFetchedHtml),
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
                                    return Image.network(
                                      resolvedUrl,
                                      width: 50, // profile emoji size.
                                      height: 50,
                                      fit: BoxFit.contain,
                                      loadingBuilder: (context, child, loadingProgress) {
                                        if (loadingProgress == null) {
                                          return child;
                                        }
                                        return const SizedBox(
                                          width: 50,
                                          height: 50,
                                          child: CircularProgressIndicator(strokeWidth: 2),
                                        );
                                      },
                                      errorBuilder: (context, error, stackTrace) {
                                        return Image.asset(
                                          'assets/images/defaultpic.gif',
                                          width: 50,
                                          height: 50,
                                          fit: BoxFit.contain,
                                        );
                                      },
                                    );

                                  }

                                  return Image.network(
                                    resolvedUrl,
                                    width: 50,
                                    height: 50,
                                    fit: BoxFit.cover,
                                    loadingBuilder: (context, child, loadingProgress) {
                                      if (loadingProgress == null) {
                                        return child;
                                      }
                                      return const SizedBox(
                                        width: 50,
                                        height: 50,
                                        child: CircularProgressIndicator(),
                                      );
                                    },
                                    errorBuilder: (context, error, stackTrace) {
                                      return Image.asset(
                                        'assets/images/defaultpic.gif',
                                        width: 50,
                                        height: 50,
                                        fit: BoxFit.cover,
                                      );
                                    },
                                  );

                                },
                              ),
                            ],
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
                      onHide: (comment['hideLink'] != null)
                          ? () => hideComment(comment['hideLink'], comment['commentId'] ?? '')
                          : null,
                      onEdit: (comment['editLink'] != null)
                          ? () {
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
                      }
                          : null,
                      onReply: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => JournalReplyScreen(
                              submissionId: widget.uniqueNumber,
                              commentId: comment['commentId'] ?? '',
                              onSendReply: (replyText) {},
                              username: comment['username'] ?? 'Anonymous',
                              profileImage: comment['profileImage'] ?? '',
                              commentText: comment['text'] ?? '',
                            ),
                          ),
                        ).then((result) {
                          if (result == true) {
                            _fetchPostDetailsNew();
                          }
                        });
                      },
                      onUnhide: (comment['deleted'] == true && comment['unhideLink'] != null)
                          ? () => _unhideComment(comment['unhideLink'], comment['commentId'] ?? '')
                          : null,
                      handleLink: (url) async {
                        final commentHtml = comment['commentHtml'] ?? '';
                        await handleFALink(
                          context,
                          url,
                          htmlSource: commentHtml,
                          getFullUrl: _getFullLinkFromFetchedHtml,
                        );
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
                          builder: (_) => AddJournalCommentScreen(
                            submissionTitle: submissionTitle ?? '',
                            onSendComment: _addComment,
                            uniqueNumber: widget.uniqueNumber,
                          ),
                        ),
                      );
                      if (ok == true) _fetchPostDetailsNew();
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
class JournalNotFoundException implements Exception {
  @override
  String toString() => 'Journal not found';
}
