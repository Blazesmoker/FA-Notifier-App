import 'package:flutter/material.dart';
import 'package:html/parser.dart';
import 'package:http/http.dart' as http;
import 'dart:async';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/fa_http.dart';
import '../widgets/PulsatingLoadingIndicator.dart';
import 'openjournal.dart';

class ProfileJournals extends StatefulWidget {
  final String username;

  const ProfileJournals({required this.username, Key? key}) : super(key: key);

  @override
  ProfileJournalsState createState() => ProfileJournalsState();
}

class ProfileJournalsState extends State<ProfileJournals> {
  int currentPage = 1;
  bool isLoading = false;
  List<Map<String, dynamic>> journals = [];
  bool hasMore = true;

  bool _sfwEnabled = true;

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    iOptions: IOSOptions(
      accountName: 'flutter_secure_storage_service',
      accessibility: KeychainAccessibility.first_unlock,
    ),
  );

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    await _loadSfwEnabled();
    if (mounted) {
      await _fetchJournals(currentPage);
    }
  }

  Future<void> _loadSfwEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool('sfwEnabled') ?? true;
    if (!mounted) return;
    setState(() {
      _sfwEnabled = enabled;
    });
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> refreshJournals() async {
    setState(() {
      journals.clear();
      currentPage = 1;
      hasMore = true;
    });
    await _loadSfwEnabled();
    await _fetchJournals(currentPage);
  }

  Future<String> _getAllCookies() async {
    List<String> cookieNames = [
      'a',
      'b',
      'cc',
      'cf_clearance',
      'folder',
      'nodesc',
      'sz',
    ];

    List<String> cookies = [];

    for (var name in cookieNames) {
      String storageKey = 'fa_cookie_$name';
      String? value = await _secureStorage.read(key: storageKey);
      if (value != null && value.isNotEmpty) {
        cookies.add('$name=$value');
      }
    }

    if (_sfwEnabled) {
      cookies.add('sfw=1');
    }

    String cookieHeader = cookies.join('; ');
    return cookieHeader;
  }

  Future<void> _fetchJournals(int pageNumber) async {
    if (isLoading || !hasMore) {
      return;
    }
    setState(() {
      isLoading = true;
    });
    try {
      final newJournals = await fetchJournals(pageNumber);

      setState(() {
        journals.addAll(newJournals);
        isLoading = false;
        currentPage = pageNumber + 1;
      });
    } catch (e, stackTrace) {
      setState(() {
        isLoading = false;
      });
      debugPrint('ProfileJournals: Error fetching journals from page $pageNumber: $e');
      debugPrint('Stack trace: $stackTrace');
    }
  }

  Future<List<Map<String, dynamic>>> fetchJournals(int pageNumber) async {
    String cookieHeader = await _getAllCookies();

    String url;
    if (pageNumber == 1) {
      url = 'https://www.furaffinity.net/journals/${widget.username}/';
    } else {
      url = 'https://www.furaffinity.net/journals/${widget.username}/$pageNumber/';
    }

    final response = await http.get(
      Uri.parse(url),
      headers: {
        'Cookie': cookieHeader,
        'User-Agent': FAHttp.userAgent,
        'Referer': 'https://www.furaffinity.net',
      },
    );

    if (response.statusCode == 200) {
      return await parseHtmlJournals(response.body);
    } else {
      debugPrint('Response body: ${response.body}');
      throw Exception('ProfileJournals: Failed to load journals: ${response.statusCode}');
    }
  }

  Future<List<Map<String, dynamic>>> parseHtmlJournals(String html) async {
    var document = parse(html);
    var journalElements =
    document.querySelectorAll('section[id^="jid:"], table[id^="jid:"]');

    var buttonElements = document.querySelectorAll('a.button.standard, a.button.older');
    hasMore = false;
    for (var button in buttonElements) {
      if (button.text.trim().toLowerCase() == 'older') {
        hasMore = true;
        break;
      }
    }

    List<Map<String, dynamic>> journalMetadata = [];

    for (var element in journalElements) {
      String? sectionId = element.attributes['id'];
      String? uniqueNumber = sectionId?.replaceFirst('jid:', '');
      String? journalId = uniqueNumber;

      String? title =
      element.querySelector('div.section-header > h2')?.text.trim();
      if (title == null || title.isEmpty) {
        title = element.querySelector('td.cat a')?.text.trim();
      }

      String? datePosted = element
          .querySelector(
          'div.section-header > span.font-small > strong > span.popup_date')
          ?.attributes['title'];
      if (datePosted == null || datePosted.isEmpty) {
        datePosted = element.querySelector('span.popup_date')?.attributes['title'];
      }

      String? contentHtml = element
          .querySelector(
          'div.section-body > div.journal-body.user-submitted-links')
          ?.innerHtml
          .trim();
      if (contentHtml == null || contentHtml.isEmpty) {
        contentHtml =
            element.querySelector('td.addpad div.no_overflow')?.innerHtml.trim();
      }

      String? commentsLink = element
          .querySelector('div.section-footer a[href^="/journal/"]')
          ?.attributes['href'];
      String? commentsText = element
          .querySelector(
          'div.section-footer a[href^="/journal/"] > span.font-large')
          ?.text
          .trim();
      if (commentsLink == null || commentsText == null || commentsText.isEmpty) {
        var commentAnchor =
        element.querySelector('td[align="right"] a[href^="/journal/"]');
        if (commentAnchor != null) {
          commentsLink = commentAnchor.attributes['href'];
          final regex = RegExp(r'Comments\s*\((\d+)\)');
          final match = regex.firstMatch(commentAnchor.text);
          commentsText = match != null ? match.group(1) : '0';
        }
      }
      int commentsCount = int.tryParse(commentsText ?? '0') ?? 0;

      if (uniqueNumber != null &&
          journalId != null &&
          title != null &&
          datePosted != null &&
          contentHtml != null) {
        journalMetadata.add({
          'journalId': journalId,
          'uniqueNumber': uniqueNumber,
          'title': title,
          'datePosted': datePosted,
          'contentHtml': contentHtml,
          'commentsLink': commentsLink,
          'commentsCount': commentsCount,
        });
      }
    }

    return journalMetadata;
  }

  @override
  Widget build(BuildContext context) {
    const int threshold = 5;

    if (journals.isEmpty && isLoading) {
      return const SliverFillRemaining(
        child: Center(
          child: PulsatingLoadingIndicator(
            size: 68.0,
            assetPath: 'assets/icons/fathemed.png',
          ),
        ),
      );
    }

    if (journals.isEmpty && !isLoading) {
      return SliverFillRemaining(
        child: Center(
          child: Text(
            'No journals found.',
            style: TextStyle(
              fontSize: 16.0,
              color: Colors.grey,
            ),
          ),
        ),
      );
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate(
            (context, index) {
          if (index < journals.length) {
            final journal = journals[index];

            if (index >= journals.length - threshold && !isLoading && hasMore) {
              Future.delayed(Duration.zero, () {
                _fetchJournals(currentPage);
              });
            }

            return Padding(
              padding:
              const EdgeInsets.symmetric(vertical: 1.0, horizontal: 8.0),
              child: Card(
                child: ListTile(
                  title: Text(journal['title']),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Posted on: ${journal['datePosted']}'),
                      const SizedBox(height: 8.0),
                      Html(
                        data: journal['contentHtml'],
                        style: {
                          "a": Style(
                            textDecoration: TextDecoration.none,
                            color: const Color(0xFFE09321),
                          ),
                          "hr": Style(
                            padding: HtmlPaddings.symmetric(vertical: 8),
                            margin: Margins.symmetric(vertical: 8),
                            height: Height(1),
                          ),
                          ".bbcode_center": Style(
                            textAlign: TextAlign.center,
                            display: Display.block,
                          ),
                          ".bbcode_right": Style(
                            textAlign: TextAlign.right,
                            display: Display.block,
                          ),
                          ".bbcode_left": Style(
                            textAlign: TextAlign.left,
                            display: Display.block,
                          ),
                        },
                        onLinkTap: (url, _, __) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => OpenJournal(
                                uniqueNumber: journal['uniqueNumber'],
                              ),
                            ),
                          );
                        },
                        extensions: [
                          TagExtension(
                            tagsToExtend: {"i"},
                            builder: (ExtensionContext context) {
                              final classAttr = context.attributes['class'];
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
                                  return Image.asset(
                                      'assets/emojis/sarcastic.png',
                                      width: 20,
                                      height: 20);
                                case 'smilie veryhappy':
                                  return Image.asset(
                                      'assets/emojis/veryhappy.png',
                                      width: 20,
                                      height: 20);
                                case 'smilie wink':
                                  return Image.asset('assets/emojis/wink.png',
                                      width: 20, height: 20);
                                case 'smilie whatever':
                                  return Image.asset(
                                      'assets/emojis/whatever.png',
                                      width: 20,
                                      height: 20);
                                case 'smilie crying':
                                  return Image.asset(
                                      'assets/emojis/crying.png',
                                      width: 20,
                                      height: 20);
                                case 'smilie love':
                                  return Image.asset('assets/emojis/love.png',
                                      width: 20, height: 20);
                                case 'smilie serious':
                                  return Image.asset(
                                      'assets/emojis/serious.png',
                                      width: 20,
                                      height: 20);
                                case 'smilie yelling':
                                  return Image.asset(
                                      'assets/emojis/yelling.png',
                                      width: 20,
                                      height: 20);
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
                                  return Image.asset(
                                      'assets/emojis/zipped.png',
                                      width: 20,
                                      height: 20);
                                case 'smilie smile':
                                  return Image.asset(
                                      'assets/emojis/smile.png',
                                      width: 20,
                                      height: 20);
                                case 'smilie badhairday':
                                  return Image.asset(
                                      'assets/emojis/badhairday.png',
                                      width: 20,
                                      height: 20);
                                case 'smilie embarrassed':
                                  return Image.asset(
                                      'assets/emojis/embarrassed.png',
                                      width: 20,
                                      height: 20);
                                case 'smilie note':
                                  return Image.asset('assets/emojis/note.png',
                                      width: 20, height: 20);
                                case 'smilie sleepy':
                                  return Image.asset(
                                      'assets/emojis/sleepy.png',
                                      width: 20,
                                      height: 20);
                                default:
                                  return const SizedBox.shrink();
                              }
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 8.0),
                      Align(
                        alignment: Alignment.bottomRight,
                        child: Padding(
                          padding: const EdgeInsets.only(
                              right: 0.0, top: 0.0, bottom: 4.0),
                          child: GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => OpenJournal(
                                    uniqueNumber: journal['uniqueNumber'],
                                  ),
                                ),
                              );
                            },
                            child: Text(
                              '${journal['commentsCount']} Comments',
                              style: const TextStyle(fontSize: 14),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => OpenJournal(
                          uniqueNumber: journal['uniqueNumber'],
                        ),
                      ),
                    );
                  },
                ),
              ),
            );
          } else {
            if (hasMore) {
              return const Padding(
                padding: EdgeInsets.all(16.0),
                child: Center(child: CircularProgressIndicator()),
              );
            } else {
              return const SizedBox.shrink();
            }
          }
        },
        childCount: journals.length + (hasMore ? 1 : 0),
      ),
    );
  }
}
