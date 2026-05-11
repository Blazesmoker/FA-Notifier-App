import 'dart:async';
import 'package:FANotifier/features/profile/presentation/user_profile_screen.dart';
import 'package:extended_text/extended_text.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:provider/provider.dart';
import 'package:html/dom.dart' as dom;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:FANotifier/features/notifications/data/fa_activities_polling_service.dart';
import 'package:FANotifier/features/notifications/data/fa_notification_service.dart';
import 'package:FANotifier/features/notifications/data/notification_settings_provider.dart';
import 'package:FANotifier/features/drawer/presentation/drawer_user_controller.dart';
import 'package:FANotifier/shared/utils/specialTextSpanBuilder.dart';
import 'package:FANotifier/shared/widgets/PulsatingLoadingIndicator.dart';
import 'package:FANotifier/features/journals/presentation/openjournal.dart';
import 'package:FANotifier/features/submissions/presentation/openpost.dart';

/// A widget that toggles between relative and absolute date formats when tapped.
class ToggleableDate extends StatefulWidget {
  final String relativeDate;
  final String absoluteDate;

  const ToggleableDate({
    Key? key,
    required this.relativeDate,
    required this.absoluteDate,
  }) : super(key: key);

  @override
  _ToggleableDateState createState() => _ToggleableDateState();
}

class _ToggleableDateState extends State<ToggleableDate> {
  bool _showRelative = true;

  void _toggleDate() {
    setState(() {
      _showRelative = !_showRelative;
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _toggleDate,
      child: Text(
        _showRelative ? widget.relativeDate : widget.absoluteDate,
        style: const TextStyle(
          color: Colors.grey,
          fontSize: 12,
        ),
      ),
    );
  }
}

/// Custom widget to handle avatar images with fallback.
class AvatarWidget extends StatelessWidget {
  final String? imageUrl;
  final String fallbackAsset;
  final double radius;

  const AvatarWidget({
    Key? key,
    required this.imageUrl,
    required this.fallbackAsset,
    this.radius = 24,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: const BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.zero,
      ),
      child: (imageUrl != null && imageUrl!.isNotEmpty)
          ? _AvatarFadeInImage(
              imageUrl: imageUrl!,
              fallbackAsset: fallbackAsset,
            )
          : Image.asset(
              fallbackAsset,
              fit: BoxFit.cover,
            ),
    );
  }
}

/// A stateful widget for the Shouts section.
class ShoutsSectionWidget extends StatefulWidget {
  final FANotificationService service;
  final bool isActive;

  const ShoutsSectionWidget({
    Key? key,
    required this.service,
    required this.isActive,
  }) : super(key: key);

  @override
  ShoutsSectionWidgetState createState() => ShoutsSectionWidgetState();
}

class ShoutsSectionWidgetState extends State<ShoutsSectionWidget>
    with AutomaticKeepAliveClientMixin {
  late Future<List<Shout>> _shoutsFuture;
  List<Shout>? _shouts; // Local list of parsed shouts
  bool _serviceListenerAttached = false;
  bool _isEnriching = false;
  String? _enrichRequestedForSignature;
  String? _autoEnrichScheduledForSignature;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    // Start with whatever msg/others parsed (no network).
    final cached = _deduplicateShouts(_readShoutsFromService());
    _shouts = cached;
    _shoutsFuture = Future.value(cached);

    // Keep shouts UI in sync with service updates (no network).
    widget.service.addListener(_onServiceChanged);
    _serviceListenerAttached = true;

    // Only enrich when the Shouts tab is actually active.
    _maybeAutoEnrich();
  }

  @override
  void didUpdateWidget(covariant ShoutsSectionWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActive != widget.isActive) {
      _maybeAutoEnrich();
    }
  }

  void _maybeAutoEnrich() {
    if (!widget.isActive) return;
    // Only enrich when needed (first open, or shout IDs changed since last enrich).
    if (!widget.service.shoutsNeedEnrich) return;

    final sig = widget.service.shoutsLightSignature;
    if (sig.isNotEmpty && _enrichRequestedForSignature == sig) return;
    _enrichRequestedForSignature = sig;

    setState(() {
      _isEnriching = true;
      _shoutsFuture = widget.service
          .enrichShoutsFromProfileIfNeeded(force: true)
          .then((list) {
        final unique = _deduplicateShouts(list);
        _shouts = unique;
        return unique;
      }).whenComplete(() {
        if (!mounted) return;
        setState(() {
          _isEnriching = false;
        });
      });
    });
  }

  Widget _buildLoadingList(String label) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 180),
        Center(
          child: Column(
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 12),
              Text(label, style: const TextStyle(color: Colors.white70)),
            ],
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    if (_serviceListenerAttached) {
      widget.service.removeListener(_onServiceChanged);
    }
    super.dispose();
  }

  void _onServiceChanged() {
    if (!mounted) return;
    final latest = _readShoutsFromService();
    if (latest.isEmpty) return;
    final unique = _deduplicateShouts(latest);
    final prev = _shouts;
    final bool changed = prev == null ||
        prev.length != unique.length ||
        (prev.isNotEmpty &&
            unique.isNotEmpty &&
            prev.first.id != unique.first.id);
    if (!changed) return;
    if (widget.isActive &&
        _enrichRequestedForSignature == null &&
        widget.service.shoutsNeedEnrich) {
      _shouts = unique;
      _maybeAutoEnrich();
      return;
    }

    setState(() {
      _shouts = unique;
      _shoutsFuture = Future.value(unique);
    });
  }

  List<Shout> _readShoutsFromService() {
    try {
      final idx = widget.service.sections
          .indexWhere((s) => s.title.toLowerCase().contains('shouts'));
      if (idx == -1) return const <Shout>[];
      final items = widget.service.sections[idx].items;
      if (items.isEmpty) return const <Shout>[];
      return items.map((it) {
        return Shout(
          id: it.id,
          nickname: it.username ?? '',
          nicknameLink: it.linkUsername ?? '',
          postedTitle: it.fullDate,
          avatarUrl: it.avatarUrl ?? '',
          postedAgo: it.date,
          textContent: it.content,
          isRemoved:
              it.content.toLowerCase().contains('shout has been removed'),
          isChecked: it.isChecked,
        );
      }).toList();
    } catch (_) {
      return const <Shout>[];
    }
  }

  // Helper to remove duplicates if FA sends the same shout multiple times
  List<Shout> _deduplicateShouts(List<Shout> shouts) {
    final Map<String, Shout> unique = {};
    for (var shout in shouts) {
      unique[shout.id] = shout;
    }
    return unique.values.toList();
  }

  /// Force a fresh fetch of the Shouts from FA
  Future<List<Shout>> _refreshShouts() async {
    FaActivitiesPollingService().resetSchedule();
    final fetchedShouts = await FANotificationService.fetchMsgCenterShouts();
    final uniqueShouts = _deduplicateShouts(fetchedShouts);
    setState(() {
      _shouts = uniqueShouts;
      _shoutsFuture = Future.value(uniqueShouts);
    });

    widget.service.updateShouts(uniqueShouts);
    return uniqueShouts;
  }

  /// Called when user taps "Select All"
  Future<void> toggleSelectAll() async {
    int index = widget.service.sections.indexWhere(
      (s) => s.title.toLowerCase().contains('shouts'),
    );
    if (index == -1) return;
    widget.service.toggleSelectAll(index);

    final providerItems = widget.service.sections[index].items;
    setState(() {
      for (var localShout in _shouts!) {
        try {
          final match =
              providerItems.firstWhere((pi) => pi.id == localShout.id);
          localShout.isChecked = match.isChecked;
        } catch (_) {}
      }
    });
  }

  /// Called when user taps "Remove Selected"
  Future<void> removeSelected() async {
    int index = widget.service.sections.indexWhere(
      (s) => s.title.toLowerCase().contains('shouts'),
    );
    if (index == -1) return;
    await widget.service.removeSelected(index);
    await _refreshShouts();
  }

  /// Called when user taps "Nuke" for the entire "Shouts" section
  Future<void> nukeSection() async {
    int index = widget.service.sections.indexWhere(
      (s) => s.title.toLowerCase().contains('shouts'),
    );
    if (index == -1) return;
    await widget.service.nukeSection(index);
    await _refreshShouts();
  }

  /// Called when the checkbox is toggled
  void _onCheckboxChanged(Shout s, bool? val) {
    if (val == null) return;
    setState(() {
      s.isChecked = val;
    });
    widget.service.setShoutCheckedById(s.id, val);
  }

  /// Replaces <i class="smilie ..."></i> with bracket placeholders like [smilie-lmao]
  String _preprocessFAEmojis(String rawHtml) {
    // Look for e.g. <i class="smilie lmao"></i>
    // and convert to [smilie-lmao].
    final exp =
        RegExp(r'<i\s+class="([^"]+)"[^>]*>(.*?)<\/i>', caseSensitive: false);
    return rawHtml.replaceAllMapped(exp, (match) {
      final classAttr = match.group(1) ?? '';
      if (classAttr.startsWith('smilie ')) {
        final placeholder = '[${classAttr.replaceAll(' ', '-')} ]';
        // e.g. 'smilie lmao' -> '[smilie-lmao]'
        return '[${classAttr.replaceAll(' ', '-')}]';
      }
      return match.group(0)!; // fallback to original if doesn't match
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return RefreshIndicator(
      onRefresh: _refreshShouts,
      child: Column(
        children: [
          const Divider(height: 4.0, color: Color(0xFF111111), thickness: 4.0),
          Expanded(
            child: FutureBuilder<List<Shout>>(
              future: _shoutsFuture,
              builder: (ctx, snapshot) {
                // If we know we need enrichment, show a loader immediately and don't
                // render the "light" msg/others view (default avatars / empty text),
                // even for a single frame.
                final sig = widget.service.shoutsLightSignature;
                final shouldBlockLightView = widget.service.shoutsNeedEnrich &&
                    !_isEnriching &&
                    sig.isNotEmpty &&
                    _enrichRequestedForSignature != sig;

                if (shouldBlockLightView) {
                  // Start enrichment once the tab is actually active (avoid background fetch).
                  if (widget.isActive &&
                      _autoEnrichScheduledForSignature != sig) {
                    _autoEnrichScheduledForSignature = sig;
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!mounted) return;
                      _autoEnrichScheduledForSignature = null;
                      _maybeAutoEnrich();
                    });
                  }
                  return _buildLoadingList('Loading shouts…');
                }

                if (widget.isActive && _isEnriching) {
                  return _buildLoadingList('Loading shouts…');
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return _buildLoadingList('Loading…');
                }
                if (snapshot.hasError) {
                  return ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      const SizedBox(height: 200),
                      Center(
                        child: Text(
                          'Error loading shouts: ${snapshot.error}',
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),
                    ],
                  );
                }

                final data = snapshot.data ?? [];
                _shouts = _deduplicateShouts(data);

                if (_shouts!.isEmpty) {
                  return ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: const [
                      SizedBox(
                        height: 200,
                        child: Center(
                          child: Text(
                            'No shouts found.',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                      ),
                    ],
                  );
                }

                return ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  itemCount: _shouts!.length,
                  itemBuilder: (ctx2, index) {
                    final s = _shouts![index];

                    // The container for each Shout
                    return Padding(
                      key: ValueKey(s.id),
                      padding: EdgeInsets.only(
                        top: index == 0 ? 8.0 : 0.0,
                        left: 0.0,
                        bottom: 0.0,
                      ),
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          // Tapping the row => open user profile
                          Navigator.push(
                            context,
                            UserProfileScreen.route(
                              nickname: widget.service.currentUsernameFromLink!,
                            ),
                          );
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 0.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  // Checkbox area
                                  Material(
                                    type: MaterialType.transparency,
                                    child: ConstrainedBox(
                                      constraints: const BoxConstraints(
                                        minHeight: 66.0,
                                        maxHeight: 66.0,
                                      ),
                                      child: LayoutBuilder(
                                        builder: (context, constraints) {
                                          return InkWell(
                                            onTap: () => _onCheckboxChanged(
                                                s, !s.isChecked),
                                            splashColor: Colors.grey[800],
                                            highlightColor: Colors.grey[600],
                                            child: Container(
                                              height: constraints.maxHeight,
                                              width: 48.0,
                                              alignment: Alignment.center,
                                              child: IgnorePointer(
                                                child: Checkbox(
                                                  activeColor:
                                                      const Color(0xFFE09321),
                                                  value: s.isChecked,
                                                  onChanged: (bool? val) =>
                                                      _onCheckboxChanged(
                                                          s, val),
                                                ),
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                  // Vertical divider line
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(4),
                                    child: Container(
                                      width: 4.0,
                                      height: 64.0,
                                      color: const Color(0xFF1F1F1F),
                                      margin: const EdgeInsets.symmetric(
                                          horizontal: 0.0),
                                    ),
                                  ),

                                  if (!s.textContent
                                      .toLowerCase()
                                      .contains("shout has been removed"))
                                    GestureDetector(
                                      onTap: () {
                                        Navigator.push(
                                          context,
                                          UserProfileScreen.route(
                                            nickname: s.nicknameLink,
                                          ),
                                        );
                                      },
                                      child: Padding(
                                        padding: const EdgeInsets.only(
                                            left: 10.0, right: 6),
                                        child: AvatarWidget(
                                          imageUrl: s.avatarUrl,
                                          fallbackAsset:
                                              'assets/images/defaultpic.gif',
                                          radius: 24,
                                        ),
                                      ),
                                    ),

                                  Expanded(
                                    child: Container(
                                      padding: const EdgeInsets.all(8),
                                      alignment: Alignment.centerLeft,
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          // Nickname line
                                          if (!s.textContent
                                              .toLowerCase()
                                              .contains(
                                                  "shout has been removed"))
                                            RichText(
                                              text: TextSpan(
                                                children: [
                                                  TextSpan(
                                                    text: s.nickname,
                                                    style: const TextStyle(
                                                      color: Color(0xFFE09321),
                                                      fontSize: 14,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                    recognizer:
                                                        TapGestureRecognizer()
                                                          ..onTap = () {
                                                            Navigator.push(
                                                              context,
                                                              UserProfileScreen
                                                                  .route(
                                                                nickname: s
                                                                    .nicknameLink,
                                                              ),
                                                            );
                                                          },
                                                  ),
                                                  const TextSpan(
                                                    text: " left a shout:",
                                                    style: TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 14,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          // The shout text
                                          ExtendedText(
                                            _preprocessFAEmojis(s.textContent),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 13,
                                            ),
                                            specialTextSpanBuilder:
                                                EmojiSpecialTextSpanBuilder(
                                              onTapLink: (String tappedUrl) {
                                                // Handle link taps
                                              },
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              // The date row
                              GestureDetector(
                                onTap: () {},
                                child: Transform.translate(
                                  offset: const Offset(0, -8),
                                  child: Align(
                                    alignment: Alignment.centerRight,
                                    child: Padding(
                                      padding:
                                          const EdgeInsets.only(right: 8.0),
                                      child: ToggleableDate(
                                        relativeDate: s.postedAgo,
                                        absoluteDate: s.postedTitle,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Widget for non-shouts sections.
class NotificationSectionWidget extends StatelessWidget {
  final int sectionIndex;
  const NotificationSectionWidget({Key? key, required this.sectionIndex})
      : super(key: key);

  Future<bool> isSfwModeEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('sfwEnabled') ?? true;
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<FANotificationService>(
      builder: (context, service, child) {
        final section = service.sections[sectionIndex];
        return RefreshIndicator(
          onRefresh: () => FaActivitiesPollingService().triggerNow(
            resetTimer: true,
            source: 'notifications_refresh_indicator',
          ),
          child: section.items.isEmpty
              ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: const [
                    SizedBox(
                      height: 200,
                      child: Center(
                          child: Text('No notifications.',
                              style: TextStyle(color: Colors.grey))),
                    ),
                  ],
                )
              : ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  itemCount: section.items.length,
                  itemBuilder: (context, itemIndex) {
                    final item = section.items[itemIndex];
                    return Column(
                      children: [
                        if (itemIndex == 0)
                          const Divider(
                            height: 4.0,
                            color: Color(0xFF111111),
                            thickness: 4.0,
                          ),
                        Padding(
                          padding: const EdgeInsets.only(left: 0.0),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Material(
                                type: MaterialType.transparency,
                                child: ConstrainedBox(
                                  constraints: (section.title
                                              .toLowerCase()
                                              .contains('favorites') ||
                                          section.title
                                              .toLowerCase()
                                              .contains('submission comments'))
                                      ? const BoxConstraints(
                                          minHeight: 88.0, maxHeight: 88.0)
                                      : const BoxConstraints(
                                          minHeight: 80.0, maxHeight: 80.0),
                                  child: LayoutBuilder(
                                    builder: (context, constraints) {
                                      return InkWell(
                                        onTap: () {
                                          item.isChecked = !item.isChecked;
                                          service.notifyListeners();
                                        },
                                        splashColor: Colors.grey[800],
                                        highlightColor: Colors.grey[600],
                                        child: Container(
                                          height: constraints.maxHeight,
                                          width: 48.0,
                                          alignment: Alignment.center,
                                          child: IgnorePointer(
                                            child: Checkbox(
                                              activeColor:
                                                  const Color(0xFFE09321),
                                              value: item.isChecked,
                                              onChanged: (bool? value) {
                                                if (value != null) {
                                                  item.isChecked = value;
                                                  service.notifyListeners();
                                                }
                                              },
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: Container(
                                  width: 4.0,
                                  height: 64.0,
                                  color: const Color(0xFF1F1F1F),
                                  margin: const EdgeInsets.symmetric(
                                      horizontal: 0.0),
                                ),
                              ),
                              if (section.title
                                  .toLowerCase()
                                  .contains('watches'))
                                GestureDetector(
                                  onTap: () {
                                    debugPrint(
                                        "Opening profile: ${item.linkUsername}");
                                    if (item.linkUsername != null) {
                                      Navigator.push(
                                        context,
                                        UserProfileScreen.route(
                                            nickname: item.linkUsername!),
                                      );
                                    }
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.only(
                                        left: 10.0, right: 0.0),
                                    child: AvatarWidget(
                                      imageUrl: item.avatarUrl,
                                      fallbackAsset:
                                          'assets/images/defaultpic.gif',
                                      radius: 24,
                                    ),
                                  ),
                                ),
                              Expanded(
                                child: GestureDetector(
                                  onTap: () {
                                    if (section.title
                                        .toLowerCase()
                                        .contains('watches')) {
                                      debugPrint(
                                          "Opening profile: ${item.linkUsername}");
                                      if (item.linkUsername != null) {
                                        Navigator.push(
                                          context,
                                          UserProfileScreen.route(
                                              nickname: item.linkUsername!),
                                        );
                                      }
                                    } else if (section.title
                                            .toLowerCase()
                                            .contains('favorites') ||
                                        section.title
                                            .toLowerCase()
                                            .contains('submission comments')) {
                                      if (item.submissionId != null) {
                                        Navigator.push(
                                          context,
                                          OpenPost.route(
                                            uniqueNumber: item.submissionId!,
                                            imageUrl: '',
                                          ),
                                        );
                                      }
                                    } else if (section.title
                                        .toLowerCase()
                                        .contains('journal comments')) {
                                      if (item.journalId != null) {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) => OpenJournal(
                                                uniqueNumber: item.journalId!),
                                          ),
                                        );
                                      }
                                    } else if (section.title
                                        .toLowerCase()
                                        .contains('shouts')) {
                                      final username =
                                          service.currentUsernameFromLink;
                                      debugPrint("shout clicked: $username");

                                      if (username != null) {
                                        Navigator.push(
                                          context,
                                          UserProfileScreen.route(
                                              nickname: username),
                                        );
                                      }
                                    } else if (section.title
                                        .toLowerCase()
                                        .contains('journals')) {
                                      if (item.journalId != null) {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) => OpenJournal(
                                                uniqueNumber: item.journalId!),
                                          ),
                                        );
                                      }
                                    }
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 4),
                                    constraints:
                                        const BoxConstraints(minHeight: 64),
                                    alignment: Alignment.centerLeft,
                                    color: Colors.transparent,
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Transform.translate(
                                          offset: (section.title
                                                      .toLowerCase()
                                                      .contains('favorites') ||
                                                  section.title
                                                      .toLowerCase()
                                                      .contains(
                                                          'submission comments'))
                                              ? const Offset(0, 0)
                                              : const Offset(0, 8),
                                          child: Html(
                                            data: item.content.replaceAll(
                                                RegExp(r'\btitled\b',
                                                    caseSensitive: false),
                                                ''),
                                            style: {
                                              "a[href^='/user']": Style(
                                                textDecoration:
                                                    TextDecoration.none,
                                                color: const Color(0xFFE09321),
                                                fontStyle: FontStyle.normal,
                                              ),
                                              "div.info > span": Style(
                                                color: const Color(0xFFE09321),
                                                fontWeight: FontWeight.normal,
                                              ),
                                              "a[href^='/journal']": Style(
                                                textDecoration:
                                                    TextDecoration.none,
                                                color: Colors.white,
                                                fontStyle: FontStyle.normal,
                                              ),
                                              "a[href^='/view']": Style(
                                                textDecoration:
                                                    TextDecoration.none,
                                                color: Colors.white,
                                                fontStyle: FontStyle.normal,
                                              ),
                                              "em": Style(
                                                  fontStyle: FontStyle.normal),
                                              "i": Style(
                                                  fontStyle: FontStyle.normal),
                                            },
                                            onLinkTap: (String? url,
                                                Map<String, String> attributes,
                                                dom.Element? element) {
                                              if (url != null) {
                                                final uri = Uri.parse(url);
                                                RegExp userRegex = RegExp(
                                                    r'^/user/([^/]+)/?$');
                                                RegExp journalRegex = RegExp(
                                                    r'^/journal/(\d+)/.*$');
                                                RegExp viewRegex =
                                                    RegExp(r'^/view/(\d+)/.*$');
                                                String path = uri.path;
                                                if (userRegex.hasMatch(path)) {
                                                  final username = userRegex
                                                      .firstMatch(path)!
                                                      .group(1)!;
                                                  Navigator.push(
                                                    context,
                                                    UserProfileScreen.route(
                                                        nickname: username),
                                                  );
                                                } else if (journalRegex
                                                    .hasMatch(path)) {
                                                  final journalId = journalRegex
                                                      .firstMatch(path)!
                                                      .group(1)!;
                                                  Navigator.push(
                                                    context,
                                                    MaterialPageRoute(
                                                      builder: (context) =>
                                                          OpenJournal(
                                                              uniqueNumber:
                                                                  journalId),
                                                    ),
                                                  );
                                                } else if (viewRegex
                                                    .hasMatch(path)) {
                                                  final submissionId = viewRegex
                                                      .firstMatch(path)!
                                                      .group(1)!;
                                                  Navigator.push(
                                                    context,
                                                    OpenPost.route(
                                                      uniqueNumber:
                                                          submissionId,
                                                      imageUrl: '',
                                                    ),
                                                  );
                                                }
                                              }
                                            },
                                          ),
                                        ),
                                        const SizedBox(height: 0),
                                        if (!(section.title
                                                .toLowerCase()
                                                .contains('favorites') ||
                                            section.title
                                                .toLowerCase()
                                                .contains(
                                                    'submission comments')))
                                          const SizedBox(height: 0),
                                        if (!(section.title
                                                .toLowerCase()
                                                .contains('favorites') ||
                                            section.title
                                                .toLowerCase()
                                                .contains(
                                                    'submission comments')))
                                          Align(
                                            alignment: Alignment.centerRight,
                                            child: ToggleableDate(
                                              relativeDate: item.date,
                                              absoluteDate: item.fullDate,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              if (section.title
                                      .toLowerCase()
                                      .contains('favorites') ||
                                  section.title
                                      .toLowerCase()
                                      .contains('submission comments'))
                                Builder(
                                  builder: (context) {
                                    final submissionId =
                                        item.submissionId ?? '';
                                    if (submissionId.isEmpty) {
                                      return const SizedBox(
                                          width: 60, height: 60);
                                    }
                                    return Padding(
                                      padding: const EdgeInsets.only(
                                          left: 4.0,
                                          right: 12.0,
                                          top: 4,
                                          bottom: 4),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.end,
                                        children: [
                                          GestureDetector(
                                            onTap: () {
                                              if (item.submissionId != null) {
                                                Navigator.push(
                                                  context,
                                                  OpenPost.route(
                                                    uniqueNumber:
                                                        item.submissionId!,
                                                    imageUrl: '',
                                                  ),
                                                );
                                              }
                                            },
                                            child: FutureBuilder<String?>(
                                              future: FANotificationService
                                                  .fetchSubmissionPreview(
                                                      submissionId),
                                              builder: (context, snapshot) {
                                                return SizedBox(
                                                  width: 56,
                                                  height: 56,
                                                  child: snapshot.hasData &&
                                                          snapshot.data != null
                                                      ? FutureBuilder<bool>(
                                                          future:
                                                              isSfwModeEnabled(),
                                                          builder: (context,
                                                              sfwSnapshot) {
                                                            if (!sfwSnapshot
                                                                .hasData) {
                                                              return Container(
                                                                  color: const Color(
                                                                      0xFF1F1F1F));
                                                            }
                                                            final bool
                                                                sfwEnabled =
                                                                sfwSnapshot
                                                                    .data!;
                                                            return FadeInNetworkImage(
                                                              imageUrl: snapshot
                                                                  .data!,
                                                              fit: BoxFit.cover,
                                                              alignment:
                                                                  Alignment
                                                                      .topCenter,
                                                              placeholder:
                                                                  Container(
                                                                color: const Color(
                                                                    0xFF1F1F1F),
                                                              ),
                                                              errorWidget:
                                                                  Image.asset(
                                                                sfwEnabled
                                                                    ? 'assets/images/nsfw.png'
                                                                    : 'assets/images/defaultpic.gif',
                                                                fit: BoxFit
                                                                    .cover,
                                                                alignment:
                                                                    Alignment
                                                                        .topCenter,
                                                              ),
                                                            );
                                                          },
                                                        )
                                                      : Container(
                                                          color: const Color(
                                                              0xFF1F1F1F)),
                                                );
                                              },
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          SizedBox(
                                            height: 16,
                                            child: ToggleableDate(
                                              relativeDate: item.date,
                                              absoluteDate: item.fullDate,
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
        );
      },
    );
  }
}

/// The main Notifications Screen widget.
class NotificationsScreen extends StatefulWidget {
  final String? initialSection;
  final GlobalKey<DrawerUserControllerState> drawerKey;

  const NotificationsScreen(
      {Key? key, required this.drawerKey, this.initialSection})
      : super(key: key);

  @override
  _NotificationsScreenState createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen>
    with TickerProviderStateMixin {
  TabController? _tabController;
  int _initialTabIndex = 0;
  bool _didAutoRefetch = false;
  bool _isDraggingFromEdge = false;
  double _startDragX = 0.0;
  int _previousSectionCount = 0;
  int _lastTabIndex = -1;

  final GlobalKey<ShoutsSectionWidgetState> _shoutsSectionKey =
      GlobalKey<ShoutsSectionWidgetState>();

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  void _showNotificationSettingsDialog(FANotificationService service) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Notification Counter Settings'),
          content: Consumer<NotificationSettingsProvider>(
            builder: (context, settings, child) {
              return SizedBox(
                width: 300,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SwitchListTile(
                        activeThumbColor: const Color(0xFFE09321),
                        title: const Text('Watchers'),
                        value: settings.watchersEnabled,
                        onChanged: (bool value) {
                          settings.setWatchersEnabled(value);
                        },
                      ),
                      SwitchListTile(
                        activeThumbColor: const Color(0xFFE09321),
                        title: const Text('Journals'),
                        value: settings.journalsEnabled,
                        onChanged: (bool value) {
                          settings.setJournalsEnabled(value);
                        },
                      ),
                      SwitchListTile(
                        activeThumbColor: const Color(0xFFE09321),
                        title: const Text('Comments'),
                        subtitle: const Text('(includes journal + submission)'),
                        value: settings.commentsEnabled,
                        onChanged: (bool value) {
                          settings.setCommentsEnabled(value);
                        },
                      ),
                      SwitchListTile(
                        activeThumbColor: const Color(0xFFE09321),
                        title: const Text('Favorites'),
                        value: settings.favoritesEnabled,
                        onChanged: (bool value) {
                          settings.setFavoritesEnabled(value);
                        },
                      ),
                      SwitchListTile(
                        activeThumbColor: const Color(0xFFE09321),
                        title: const Text('Shouts'),
                        value: settings.shoutsEnabled,
                        onChanged: (bool value) {
                          settings.setShoutsEnabled(value);
                        },
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  void _initializeTabController(
      int sectionCount, FANotificationService service) {
    _tabController?.dispose();
    _initialTabIndex = 0;
    if (widget.initialSection != null) {
      int desiredIndex = service.sections.indexWhere(
        (section) => section.title
            .toLowerCase()
            .contains(widget.initialSection!.toLowerCase()),
      );
      if (desiredIndex != -1) {
        _initialTabIndex = desiredIndex;
      }
    }
    if (_initialTabIndex >= sectionCount) {
      _initialTabIndex = sectionCount > 0 ? sectionCount - 1 : 0;
    }
    _tabController = TabController(
        length: sectionCount, vsync: this, initialIndex: _initialTabIndex);
    _lastTabIndex = _tabController!.index;
    _tabController!.addListener(() {
      if (!mounted) return;
      final idx = _tabController!.index;
      if (idx != _lastTabIndex) {
        _lastTabIndex = idx;
        setState(() {});
      }
    });
    _previousSectionCount = sectionCount;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<FANotificationService>(
      builder: (context, service, child) {
        final isLoading = service.isLoading;
        final hasFetched = service.hasFetched;
        final sections = service.sections;
        if (isLoading || !hasFetched) {
          return Scaffold(
            appBar: AppBar(
              title: const Text('Notifications'),
              centerTitle: true,
              backgroundColor: Colors.black,
              actions: [
                IconButton(
                  icon: const Icon(Icons.block, color: Color(0xFFE09321)),
                  onPressed: null,
                ),
                IconButton(
                  icon: const Icon(Icons.settings),
                  onPressed: () {
                    _showNotificationSettingsDialog(service);
                  },
                ),
              ],
            ),
            body: const Center(
                child: PulsatingLoadingIndicator(
                    size: 88.0, assetPath: 'assets/icons/fathemed.png')),
          );
        }
        if (sections.isEmpty) {
          if (!_didAutoRefetch) {
            _didAutoRefetch = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              FaActivitiesPollingService().triggerNow(
                resetTimer: false,
                source: 'notifications_empty_autorefresh',
              );
            });
          }
          return Scaffold(
            appBar: AppBar(
              title: const Text('Notifications'),
              centerTitle: true,
              backgroundColor: Colors.black,
              actions: [
                IconButton(
                  icon: const Icon(Icons.block, color: Color(0xFFE09321)),
                  onPressed: () async {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('No notifications to remove.')),
                    );
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.settings),
                  onPressed: () {
                    _showNotificationSettingsDialog(service);
                  },
                ),
              ],
            ),
            body: RefreshIndicator(
              onRefresh: () => FaActivitiesPollingService().triggerNow(
                resetTimer: true,
                source: 'notifications_empty_refresh_indicator',
              ),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(
                      height: 200,
                      child: Center(child: Text('No notifications.'))),
                ],
              ),
            ),
          );
        }
        if (sections.length != _previousSectionCount) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _initializeTabController(sections.length, service);
          });
        }
        if (_tabController == null ||
            _tabController!.length != sections.length) {
          return const Scaffold(body: SizedBox.shrink());
        }
        return Scaffold(
          appBar: AppBar(
            title: const Text('Notifications'),
            centerTitle: true,
            backgroundColor: Colors.black,
            actions: [
              IconButton(
                icon: const Icon(Icons.block, color: Color(0xFFE09321)),
                tooltip: 'Remove all notifications',
                onPressed: () async {
                  bool confirm = await showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Confirm'),
                      content: const Text(
                          'Are you sure you want to remove ALL notifications?'),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.of(ctx).pop(false),
                            child: const Text('Cancel')),
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(true),
                          style:
                              TextButton.styleFrom(foregroundColor: Colors.red),
                          child: const Text('Confirm'),
                        ),
                      ],
                    ),
                  );
                  if (confirm) {
                    await service.removeAllNotifications();
                  }
                },
              ),
              IconButton(
                icon: const Icon(Icons.settings),
                onPressed: () {
                  _showNotificationSettingsDialog(service);
                },
              ),
            ],
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(kToolbarHeight + 8),
              child: Column(
                children: [
                  const Divider(
                      height: 4.0, color: Color(0xFF111111), thickness: 4.0),
                  const Divider(
                      height: 3.4, color: Colors.black, thickness: 4.0),
                  Container(
                    decoration: const BoxDecoration(color: Color(0xFF111111)),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 0.0),
                      child: Consumer<FANotificationService>(
                        builder: (context, service, child) {
                          return TabBar(
                            controller: _tabController,
                            isScrollable: true,
                            indicator: const UnderlineTabIndicator(
                              borderSide: BorderSide(
                                  color: Color(0xFFE09321), width: 3.4),
                              insets: EdgeInsets.symmetric(horizontal: -6.0),
                            ),
                            labelStyle: const TextStyle(
                                fontSize: 17.0, fontWeight: FontWeight.bold),
                            unselectedLabelStyle:
                                const TextStyle(fontSize: 15.0),
                            tabAlignment: TabAlignment.start,
                            dividerColor: Colors.black,
                            dividerHeight: 3.7,
                            tabs: sections.map((section) {
                              // Determine the typeKey based on section title
                              String? typeKey;
                              final titleLower = section.title.toLowerCase();
                              if (titleLower.contains('watch')) {
                                typeKey = 'W';
                              } else if (titleLower.contains('favorite')) {
                                typeKey = 'F';
                              } else if (titleLower.contains('journal') &&
                                  !titleLower.contains('comment')) {
                                typeKey = 'J';
                              }

                              // Get count from messageBarCounts if W/F/J, else use section.items.length
                              int rawCount = 0;
                              if (typeKey != null &&
                                  service.messageBarCounts
                                      .containsKey(typeKey)) {
                                rawCount = service.messageBarCounts[typeKey]!;
                              } else {
                                rawCount = section.items.length;
                              }

                              // Apply "30+" rule for Comments and Shouts
                              String displayText;
                              if (titleLower.contains('comment') ||
                                  titleLower.contains('shout')) {
                                displayText =
                                    rawCount >= 30 ? '30+' : '$rawCount';
                              } else {
                                displayText = '$rawCount';
                              }

                              return Tab(
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(section.title),
                                      const SizedBox(width: 4),
                                      if (rawCount > 0)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFE09321),
                                            borderRadius:
                                                BorderRadius.circular(12),
                                          ),
                                          child: Text(
                                            displayText,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              );
                            }).toList(),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          body: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 0.0),
                child: Column(
                  children: [
                    const Divider(
                        height: 4.0, color: Color(0xFF111111), thickness: 4.0),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 0.0, vertical: 2.0),
                      child: Row(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () {
                                final currentTabIndex =
                                    _tabController?.index ?? 0;
                                if (sections[currentTabIndex]
                                    .title
                                    .toLowerCase()
                                    .contains('shouts')) {
                                  _shoutsSectionKey.currentState
                                      ?.toggleSelectAll();
                                } else {
                                  service.toggleSelectAll(currentTabIndex);
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF1F1F1F),
                                padding: const EdgeInsets.symmetric(
                                    vertical: 11, horizontal: 8),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(4)),
                              ),
                              child: const FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.center,
                                  child: Text('Select All')),
                            ),
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () async {
                                final currentTabIndex =
                                    _tabController?.index ?? 0;
                                if (sections[currentTabIndex]
                                    .title
                                    .toLowerCase()
                                    .contains('shouts')) {
                                  await _shoutsSectionKey.currentState
                                      ?.removeSelected();
                                } else {
                                  await service.removeSelected(currentTabIndex);
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF1F1F1F),
                                padding: const EdgeInsets.symmetric(
                                    vertical: 11, horizontal: 8),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(4)),
                              ),
                              child: const FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.center,
                                  child: Text('Remove Selected')),
                            ),
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () async {
                                final currentTabIndex =
                                    _tabController?.index ?? 0;
                                bool confirm = await showDialog(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: const Text('Confirm Nuke'),
                                    content: const Text(
                                        'Are you sure you want to nuke all items in this section?'),
                                    actions: [
                                      TextButton(
                                          onPressed: () =>
                                              Navigator.of(ctx).pop(false),
                                          child: const Text('Cancel')),
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.of(ctx).pop(true),
                                        style: TextButton.styleFrom(
                                            foregroundColor: Colors.red),
                                        child: const Text('Confirm'),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirm) {
                                  if (sections[currentTabIndex]
                                      .title
                                      .toLowerCase()
                                      .contains('shouts')) {
                                    await _shoutsSectionKey.currentState
                                        ?.nukeSection();
                                  } else {
                                    await service.nukeSection(currentTabIndex);
                                    await service.fetchNotifications();
                                  }
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFE09321),
                                padding: const EdgeInsets.symmetric(
                                    vertical: 11, horizontal: 8),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(4)),
                              ),
                              child: const FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.center,
                                  child: Text('Nuke')),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: NotificationListener<OverscrollNotification>(
                        onNotification: (OverscrollNotification notification) {
                          if (_tabController?.index == 0 &&
                              notification.overscroll < 0 &&
                              notification.metrics.axis == Axis.horizontal) {
                            widget.drawerKey.currentState?.openDrawer();
                            return true;
                          }
                          return false;
                        },
                        child: TabBarView(
                          controller: _tabController,
                          children: List.generate(
                            sections.length,
                            (index) {
                              final section = sections[index];
                              if (section.title
                                  .toLowerCase()
                                  .contains('shouts')) {
                                return ShoutsSectionWidget(
                                  key: _shoutsSectionKey,
                                  service: service,
                                  isActive:
                                      (_tabController?.index ?? 0) == index,
                                );
                              } else {
                                return NotificationSectionWidget(
                                    sectionIndex: index);
                              }
                            },
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: 19,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onHorizontalDragStart: (details) {
                    if (details.globalPosition.dx <= 62.0) {
                      _isDraggingFromEdge = true;
                      _startDragX = details.globalPosition.dx;
                    }
                  },
                  onHorizontalDragUpdate: (details) {
                    if (_isDraggingFromEdge) {
                      final drawerWidth =
                          widget.drawerKey.currentState?.widget.drawerWidth ??
                              250.0;
                      final currentOffset = widget.drawerKey.currentState
                              ?.scrollController?.offset ??
                          drawerWidth;
                      double newOffset = currentOffset - details.delta.dx;
                      if (newOffset < 0) newOffset = 0;
                      if (newOffset > drawerWidth) newOffset = drawerWidth;
                      widget.drawerKey.currentState
                          ?.setDrawerPosition(newOffset);
                    }
                  },
                  onHorizontalDragEnd: (details) {
                    if (_isDraggingFromEdge) {
                      _isDraggingFromEdge = false;
                      final drawerWidth =
                          widget.drawerKey.currentState?.widget.drawerWidth ??
                              250.0;
                      final currentOffset = widget.drawerKey.currentState
                              ?.scrollController?.offset ??
                          drawerWidth;
                      final threshold = drawerWidth / 2;
                      if (currentOffset < threshold) {
                        widget.drawerKey.currentState?.openDrawer();
                      } else {
                        widget.drawerKey.currentState?.closeDrawer();
                      }
                    }
                  },
                  child: Container(color: Colors.transparent),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class FadeInNetworkImage extends StatefulWidget {
  final String imageUrl;
  final BoxFit fit;
  final Alignment alignment;
  final Duration duration;
  final Widget placeholder;
  final Widget errorWidget;

  const FadeInNetworkImage({
    Key? key,
    required this.imageUrl,
    required this.placeholder,
    required this.errorWidget,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
    this.duration = const Duration(milliseconds: 250),
  }) : super(key: key);

  @override
  State<FadeInNetworkImage> createState() => _FadeInNetworkImageState();
}

class _FadeInNetworkImageState extends State<FadeInNetworkImage> {
  bool _visible = false;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Placeholder is always visible
        widget.placeholder,

        // Image fades in smoothly
        Image.network(
          widget.imageUrl,
          fit: widget.fit,
          alignment: widget.alignment,
          frameBuilder: (context, child, frame, _) {
            if (frame != null && !_visible) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) setState(() => _visible = true);
              });
            }

            return AnimatedOpacity(
              opacity: _visible ? 1.0 : 0.0,
              duration: widget.duration,
              curve: Curves.easeOut,
              child: child,
            );
          },
          errorBuilder: (_, __, ___) => widget.errorWidget,
        ),
      ],
    );
  }
}

class _AvatarFadeInImage extends StatefulWidget {
  final String imageUrl;
  final String fallbackAsset;

  const _AvatarFadeInImage({
    required this.imageUrl,
    required this.fallbackAsset,
  });

  @override
  State<_AvatarFadeInImage> createState() => _AvatarFadeInImageState();
}

class _AvatarFadeInImageState extends State<_AvatarFadeInImage> {
  bool _visible = false;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Placeholder (always visible)
        Image.asset(
          widget.fallbackAsset,
          fit: BoxFit.cover,
        ),

        // Real image fades in on top
        Image.network(
          widget.imageUrl,
          fit: BoxFit.cover,
          frameBuilder: (context, child, frame, _) {
            if (frame != null && !_visible) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  setState(() => _visible = true);
                }
              });
            }

            return AnimatedOpacity(
              opacity: _visible ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              child: child,
            );
          },
          errorBuilder: (context, error, stackTrace) {
            return Image.asset(
              widget.fallbackAsset,
              fit: BoxFit.cover,
            );
          },
        ),
      ],
    );
  }
}
