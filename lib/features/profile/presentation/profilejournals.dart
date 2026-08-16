import 'package:material_ui/material_ui.dart';
import 'dart:async';
import 'package:flutter_html/flutter_html.dart';
import 'package:provider/provider.dart';
import 'package:fanotifier/features/profile/domain/profile_journals_repository.dart';
import 'package:fanotifier/shared/widgets/pulsating_loading_indicator.dart';
import 'package:fanotifier/shared/widgets/fa_network_image.dart';
import 'package:fanotifier/features/journals/presentation/openjournal.dart';

class ProfileJournals extends StatefulWidget {
  final String username;

  const ProfileJournals({required this.username, super.key});

  @override
  ProfileJournalsState createState() => ProfileJournalsState();
}

class ProfileJournalsState extends State<ProfileJournals> {
  int currentPage = 1;
  bool isLoading = false;
  List<Map<String, dynamic>> journals = [];
  bool hasMore = true;
  int _fetchGeneration = 0;

  late final ProfileJournalsRepository _profileJournalsRepository;

  @override
  void initState() {
    super.initState();
    _profileJournalsRepository = context.read<ProfileJournalsRepository>();
    unawaited(_fetchJournals(currentPage));
  }

  @override
  void didUpdateWidget(ProfileJournals oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.username != widget.username) {
      unawaited(refreshJournals());
    }
  }

  Future<void> refreshJournals() async {
    if (!mounted) return;
    _fetchGeneration++;
    setState(() {
      journals.clear();
      currentPage = 1;
      hasMore = true;
      isLoading = false;
    });
    await _fetchJournals(currentPage);
  }

  void loadNextPage() {
    if (!mounted || isLoading || !hasMore) return;
    unawaited(_fetchJournals(currentPage));
  }

  void _handleJournalMutated() {
    if (!mounted) return;
    unawaited(refreshJournals());
  }

  Future<void> _openJournal(String uniqueNumber) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => OpenJournal(
          uniqueNumber: uniqueNumber,
          onJournalMutated: _handleJournalMutated,
        ),
      ),
    );
  }

  Future<void> _fetchJournals(int pageNumber) async {
    if (isLoading || !hasMore) {
      return;
    }
    final fetchGeneration = _fetchGeneration;
    setState(() {
      isLoading = true;
    });
    try {
      final page = await _profileJournalsRepository.fetchJournalsPage(
        username: widget.username,
        pageNumber: pageNumber,
      );
      if (!mounted || fetchGeneration != _fetchGeneration) {
        return;
      }

      setState(() {
        journals.addAll(page.journals);
        hasMore = page.hasMore;
        isLoading = false;
        currentPage = pageNumber + 1;
      });
    } catch (e, stackTrace) {
      if (!mounted || fetchGeneration != _fetchGeneration) {
        return;
      }
      setState(() {
        isLoading = false;
      });
      debugPrint(
          'ProfileJournals: Error fetching journals from page $pageNumber: $e');
      debugPrint('Stack trace: $stackTrace');
    }
  }

  @override
  Widget build(BuildContext context) {
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

    // The loaded batch is intentionally measured as one sliver. A lazy,
    // variable-height SliverList can revise its estimated extent while the
    // profile header collapses, which interrupts an active nested-scroll fling.
    return SliverToBoxAdapter(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: List<Widget>.generate(
          journals.length + 1,
          (index) {
            if (index < journals.length) {
              final journal = journals[index];

              return RepaintBoundary(
                key: ValueKey('profile-journal-${journal['uniqueNumber']}'),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      vertical: 1.0, horizontal: 8.0),
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
                            onLinkTap: (url, _, _) async {
                              await _openJournal(journal['uniqueNumber']);
                            },
                            extensions: [
                              faHtmlImageExtension(),
                              TagExtension(
                                tagsToExtend: {"i"},
                                builder: (ExtensionContext context) {
                                  final classAttr = context.attributes['class'];
                                  switch (classAttr) {
                                    case 'smilie tongue':
                                      return Image.asset(
                                          'assets/emojis/tongue.png',
                                          width: 20,
                                          height: 20);
                                    case 'smilie evil':
                                      return Image.asset(
                                          'assets/emojis/evil.png',
                                          width: 20,
                                          height: 20);
                                    case 'smilie lmao':
                                      return Image.asset(
                                          'assets/emojis/lmao.png',
                                          width: 20,
                                          height: 20);
                                    case 'smilie gift':
                                      return Image.asset(
                                          'assets/emojis/gift.png',
                                          width: 20,
                                          height: 20);
                                    case 'smilie derp':
                                      return Image.asset(
                                          'assets/emojis/derp.png',
                                          width: 20,
                                          height: 20);
                                    case 'smilie teeth':
                                      return Image.asset(
                                          'assets/emojis/teeth.png',
                                          width: 20,
                                          height: 20);
                                    case 'smilie cool':
                                      return Image.asset(
                                          'assets/emojis/cool.png',
                                          width: 20,
                                          height: 20);
                                    case 'smilie huh':
                                      return Image.asset(
                                          'assets/emojis/huh.png',
                                          width: 20,
                                          height: 20);
                                    case 'smilie cd':
                                      return Image.asset('assets/emojis/cd.png',
                                          width: 20, height: 20);
                                    case 'smilie coffee':
                                      return Image.asset(
                                          'assets/emojis/coffee.png',
                                          width: 20,
                                          height: 20);
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
                                      return Image.asset(
                                          'assets/emojis/wink.png',
                                          width: 20,
                                          height: 20);
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
                                      return Image.asset(
                                          'assets/emojis/love.png',
                                          width: 20,
                                          height: 20);
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
                                      return Image.asset(
                                          'assets/emojis/oooh.png',
                                          width: 20,
                                          height: 20);
                                    case 'smilie angel':
                                      return Image.asset(
                                          'assets/emojis/angel.png',
                                          width: 20,
                                          height: 20);
                                    case 'smilie dunno':
                                      return Image.asset(
                                          'assets/emojis/dunno.png',
                                          width: 20,
                                          height: 20);
                                    case 'smilie nerd':
                                      return Image.asset(
                                          'assets/emojis/nerd.png',
                                          width: 20,
                                          height: 20);
                                    case 'smilie sad':
                                      return Image.asset(
                                          'assets/emojis/sad.png',
                                          width: 20,
                                          height: 20);
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
                                      return Image.asset(
                                          'assets/emojis/note.png',
                                          width: 20,
                                          height: 20);
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
                                  _openJournal(journal['uniqueNumber']);
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
                        _openJournal(journal['uniqueNumber']);
                      },
                    ),
                  ),
                ),
              );
            } else {
              if (hasMore) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16.0),
                  child: Center(
                    child: isLoading
                        ? const CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Color(0xFFE09321),
                            ),
                          )
                        : ElevatedButton(
                            onPressed: loadNextPage,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFE09321),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24.0,
                                vertical: 12.0,
                              ),
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
                );
              } else {
                return const SizedBox(height: 80.0);
              }
            }
          },
        ),
      ),
    );
  }
}
