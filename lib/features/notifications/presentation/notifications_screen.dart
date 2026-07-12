import 'dart:async';
import 'package:FANotifier/features/profile/presentation/user_profile_screen.dart';
import 'package:extended_text/extended_text.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:FANotifier/shared/widgets/fa_network_image.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:provider/provider.dart';
import 'package:html/dom.dart' as dom;
import 'package:FANotifier/core/preferences/sfw_mode_preference.dart';
import 'package:FANotifier/features/notifications/data/fa_notification_service.dart';
import 'package:FANotifier/features/notifications/domain/fa_notification_models.dart';
import 'package:FANotifier/features/notifications/domain/notification_section_kind.dart';
import 'package:FANotifier/features/notifications/data/notification_content_parser.dart';
import 'package:FANotifier/features/notifications/data/notification_settings_provider.dart';
import 'package:FANotifier/features/drawer/presentation/drawer_user_controller.dart';
import 'package:FANotifier/features/profile/domain/profile_section.dart';
import 'package:FANotifier/shared/utils/specialTextSpanBuilder.dart';
import 'package:FANotifier/shared/utils/fa_link_matcher.dart';
import 'package:FANotifier/shared/widgets/PulsatingLoadingIndicator.dart';
import 'package:FANotifier/features/journals/presentation/openjournal.dart';
import 'package:FANotifier/features/submissions/presentation/openpost.dart';
import 'package:FANotifier/features/notifications/presentation/notification_activities_controller.dart';
import 'package:FANotifier/features/notifications/presentation/notification_counter_settings_controller.dart';
import 'package:FANotifier/features/notifications/presentation/notification_shouts_controller.dart';

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
  late final NotificationShoutsController _controller;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _controller = NotificationShoutsController(widget.service);
    _controller.addListener(_onControllerChanged);
    _controller.initialize(isActive: widget.isActive);
  }

  @override
  void didUpdateWidget(covariant ShoutsSectionWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActive != widget.isActive) {
      _controller.updateActive(widget.isActive);
    }
  }

  void _onControllerChanged() {
    if (!mounted) return;
    setState(() {});
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
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    super.dispose();
  }

  /// Called when user taps "Select All"
  Future<void> toggleSelectAll() => _controller.toggleSelectAll();

  /// Called when user taps "Remove Selected"
  Future<void> removeSelected() => _controller.removeSelected();

  /// Called when user taps "Nuke" for the entire "Shouts" section
  Future<void> nukeSection() => _controller.nukeSection();

  /// Called when the checkbox is toggled
  void _onCheckboxChanged(Shout s, bool? val) {
    if (val == null) return;
    _controller.setChecked(s, val);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return RefreshIndicator(
      color: const Color(0xFFE09321),
      backgroundColor: Colors.black,
      onRefresh: _controller.refresh,
      child: Column(
        children: [
          const Divider(height: 4.0, color: Color(0xFF111111), thickness: 4.0),
          Expanded(
            child: FutureBuilder<List<Shout>>(
              future: _controller.shoutsFuture,
              builder: (ctx, snapshot) {
                // If we know we need enrichment, show a loader immediately and don't
                // render the "light" msg/others view (default avatars / empty text),
                // even for a single frame.
                final sig = _controller.lightSignature;
                final shouldBlockLightView =
                    _controller.shouldBlockLightView;

                if (shouldBlockLightView) {
                  // Start enrichment once the tab is actually active (avoid background fetch).
                  if (_controller.scheduleAutoEnrich(sig)) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!mounted) return;
                      _controller.runScheduledAutoEnrich();
                    });
                  }
                  return _buildLoadingList('Loading shouts…');
                }

                if (widget.isActive && _controller.isEnriching) {
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
                final shouts = _controller.acceptSnapshotData(data);

                if (shouts.isEmpty) {
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
                  itemCount: shouts.length,
                  itemBuilder: (ctx2, index) {
                    final s = shouts[index];

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
                                            preprocessFAEmojis(s.textContent),
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
  final NotificationActivitiesController controller;
  final SfwModePreference _sfwModePreference = const SfwModePreference();
  const NotificationSectionWidget({
    Key? key,
    required this.sectionIndex,
    required this.controller,
  })
      : super(key: key);

  Future<bool> isSfwModeEnabled() async {
    return _sfwModePreference.loadSfwEnabled();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<FANotificationService>(
      builder: (context, _, child) {
        final section = controller.sections[sectionIndex];
        return RefreshIndicator(
          color: const Color(0xFFE09321),
          backgroundColor: Colors.black,
          onRefresh: () => controller.refresh(
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
                    final sectionKind =
                        notificationSectionKindFromTitle(section.title);
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
                                  constraints: (sectionKind ==
                                              NotificationSectionKind
                                                  .favorites ||
                                          sectionKind ==
                                              NotificationSectionKind
                                                  .submissionComments)
                                      ? const BoxConstraints(
                                          minHeight: 88.0, maxHeight: 88.0)
                                      : const BoxConstraints(
                                          minHeight: 80.0, maxHeight: 80.0),
                                  child: LayoutBuilder(
                                    builder: (context, constraints) {
                                      return InkWell(
                                        onTap: () {
                                          controller.setItemChecked(
                                            item,
                                            !item.isChecked,
                                          );
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
                                                  controller.setItemChecked(
                                                    item,
                                                    value,
                                                  );
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
                              if (sectionKind ==
                                  NotificationSectionKind.watches)
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
                                    if (sectionKind ==
                                        NotificationSectionKind.watches) {
                                      debugPrint(
                                          "Opening profile: ${item.linkUsername}");
                                      if (item.linkUsername != null) {
                                        Navigator.push(
                                          context,
                                          UserProfileScreen.route(
                                              nickname: item.linkUsername!),
                                        );
                                      }
                                    } else if (sectionKind ==
                                            NotificationSectionKind.favorites ||
                                        sectionKind ==
                                            NotificationSectionKind
                                                .submissionComments) {
                                      if (item.submissionId != null) {
                                        Navigator.push(
                                          context,
                                          OpenPost.route(
                                            uniqueNumber: item.submissionId!,
                                            imageUrl: '',
                                          ),
                                        );
                                      }
                                    } else if (sectionKind ==
                                        NotificationSectionKind
                                            .journalComments) {
                                      if (item.journalId != null) {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) => OpenJournal(
                                                uniqueNumber: item.journalId!),
                                          ),
                                        );
                                      }
                                    } else if (sectionKind ==
                                        NotificationSectionKind.shouts) {
                                      final username =
                                          controller.currentUsernameFromLink;
                                      debugPrint("shout clicked: $username");

                                      if (username != null) {
                                        Navigator.push(
                                          context,
                                          UserProfileScreen.route(
                                              nickname: username),
                                        );
                                      }
                                    } else if (sectionKind ==
                                        NotificationSectionKind.journals) {
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
                                            data: stripNotificationTitledWord(
                                              item.content,
                                            ),
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
                                                final target = matchFALink(url);
                                                switch (target.type) {
                                                  case FALinkTargetType.gallery:
                                                    Navigator.push(
                                                      context,
                                                      UserProfileScreen.route(
                                                        nickname:
                                                            target.username!,
                                                        initialSection:
                                                            ProfileSection
                                                                .Gallery,
                                                      ),
                                                    );
                                                    return;
                                                  case FALinkTargetType
                                                        .galleryFolder:
                                                    final tappedUsername =
                                                        target.username!;
                                                    final folderNumber =
                                                        target.folderNumber!;
                                                    final folderName =
                                                        target.folderName!;
                                                    final folderUrl =
                                                        buildFAGalleryFolderUrl(
                                                      username: tappedUsername,
                                                      folderNumber:
                                                          folderNumber,
                                                      folderName: folderName,
                                                    );
                                                    Navigator.push(
                                                      context,
                                                      UserProfileScreen.route(
                                                        nickname:
                                                            tappedUsername,
                                                        initialSection:
                                                            ProfileSection
                                                                .Gallery,
                                                        initialFolderUrl:
                                                            folderUrl,
                                                        initialFolderName:
                                                            folderName,
                                                      ),
                                                    );
                                                    return;
                                                  case FALinkTargetType.user:
                                                    Navigator.push(
                                                      context,
                                                      UserProfileScreen.route(
                                                        nickname:
                                                            target.username!,
                                                      ),
                                                    );
                                                    return;
                                                  case FALinkTargetType
                                                        .journalUser:
                                                    Navigator.push(
                                                      context,
                                                      UserProfileScreen.route(
                                                        nickname:
                                                            target.username!,
                                                        initialSection:
                                                            ProfileSection
                                                                .Journals,
                                                      ),
                                                    );
                                                    return;
                                                  case FALinkTargetType.journal:
                                                    Navigator.push(
                                                      context,
                                                      MaterialPageRoute(
                                                        builder: (context) =>
                                                            OpenJournal(
                                                          uniqueNumber:
                                                              target.journalId!,
                                                        ),
                                                      ),
                                                    );
                                                    return;
                                                  case FALinkTargetType
                                                        .submission:
                                                    Navigator.push(
                                                      context,
                                                      OpenPost.route(
                                                        uniqueNumber: target
                                                            .submissionId!,
                                                        imageUrl: '',
                                                      ),
                                                    );
                                                    return;
                                                  case FALinkTargetType
                                                        .external:
                                                    return;
                                                }
                                              }
                                            },
                                            extensions: [faHtmlImageExtension()],
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
  bool _isDraggingFromEdge = false;
  int _previousSectionCount = 0;
  int _lastTabIndex = -1;
  late NotificationActivitiesController _activitiesController;
  bool _activitiesControllerInitialized = false;

  final GlobalKey<ShoutsSectionWidgetState> _shoutsSectionKey =
      GlobalKey<ShoutsSectionWidgetState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_activitiesController.loadOnFirstOpen());
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final service = Provider.of<FANotificationService>(context, listen: false);
    if (!_activitiesControllerInitialized) {
      _activitiesController = NotificationActivitiesController(service);
      _activitiesControllerInitialized = true;
    }
  }

  @override
  void dispose() {
    _tabController?.dispose();
    _activitiesController.setScreenVisible(false);
    super.dispose();
  }

  void _syncActiveNotificationSection() {
    _activitiesController.setActiveSection(_tabController?.index);
  }

  void _showNotificationSettingsDialog() {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Notification Counter Settings'),
          content: Consumer<NotificationSettingsProvider>(
            builder: (context, settings, child) {
              final counterSettings =
                  NotificationCounterSettingsController(settings);
              return SizedBox(
                width: 300,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SwitchListTile(
                        activeThumbColor: const Color(0xFFE09321),
                        title: const Text('Watchers'),
                        value: counterSettings.watchersEnabled,
                        onChanged: (bool value) {
                          counterSettings.setWatchersEnabled(value);
                        },
                      ),
                      SwitchListTile(
                        activeThumbColor: const Color(0xFFE09321),
                        title: const Text('Journals'),
                        value: counterSettings.journalsEnabled,
                        onChanged: (bool value) {
                          counterSettings.setJournalsEnabled(value);
                        },
                      ),
                      SwitchListTile(
                        activeThumbColor: const Color(0xFFE09321),
                        title: const Text('Comments'),
                        subtitle: const Text('(includes journal + submission)'),
                        value: counterSettings.commentsEnabled,
                        onChanged: (bool value) {
                          counterSettings.setCommentsEnabled(value);
                        },
                      ),
                      SwitchListTile(
                        activeThumbColor: const Color(0xFFE09321),
                        title: const Text('Favorites'),
                        value: counterSettings.favoritesEnabled,
                        onChanged: (bool value) {
                          counterSettings.setFavoritesEnabled(value);
                        },
                      ),
                      SwitchListTile(
                        activeThumbColor: const Color(0xFFE09321),
                        title: const Text('Shouts'),
                        value: counterSettings.shoutsEnabled,
                        onChanged: (bool value) {
                          counterSettings.setShoutsEnabled(value);
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

  void _initializeTabController(int sectionCount) {
    _tabController?.dispose();
    _initialTabIndex = _activitiesController.initialTabIndex(
      widget.initialSection,
    );
    if (_initialTabIndex >= sectionCount) {
      _initialTabIndex = sectionCount > 0 ? sectionCount - 1 : 0;
    }
    _tabController = TabController(
        length: sectionCount, vsync: this, initialIndex: _initialTabIndex);
    _lastTabIndex = _tabController!.index;
    _syncActiveNotificationSection();
    _tabController!.addListener(() {
      if (!mounted) return;
      final idx = _tabController!.index;
      if (idx != _lastTabIndex) {
        _lastTabIndex = idx;
        _syncActiveNotificationSection();
        setState(() {});
      }
    });
    _previousSectionCount = sectionCount;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return VisibilityDetector(
      key: const Key('notifications_screen_visibility'),
      onVisibilityChanged: (info) {
        _activitiesController.setScreenVisible(
          info.visibleFraction > 0.01,
          activeIndex: _tabController?.index,
        );
      },
      child: Consumer<FANotificationService>(
        builder: (context, service, child) {
          _activitiesController.updateService(service);
          final sections = _activitiesController.sections;
          final showInitialLoading =
              _activitiesController.showInitialLoading;
          if (showInitialLoading) {
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
                      _showNotificationSettingsDialog();
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
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              _activitiesController.setActiveSection(null);
            });
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _activitiesController.triggerEmptyAutoRefresh();
            });
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
                      _showNotificationSettingsDialog();
                    },
                  ),
                ],
              ),
              body: RefreshIndicator(
                color: const Color(0xFFE09321),
                backgroundColor: Colors.black,
                onRefresh: () => _activitiesController.refresh(
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
              _initializeTabController(sections.length);
            });
          }
          if (_tabController == null ||
              _tabController!.length != sections.length) {
            return const Scaffold(body: SizedBox.shrink());
          }
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _syncActiveNotificationSection();
          });
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
                    await _activitiesController.removeAll();
                  }
                },
              ),
              IconButton(
                icon: const Icon(Icons.settings),
                onPressed: () {
                  _showNotificationSettingsDialog();
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
                        builder: (context, _, child) {
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
                              final badgeValue =
                                  _activitiesController.badgeValueFor(section);
                              final rawCount = badgeValue.rawCount;
                              final displayText = badgeValue.displayText;

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
                                if (_activitiesController
                                    .isShoutsSection(currentTabIndex)) {
                                  _shoutsSectionKey.currentState
                                      ?.toggleSelectAll();
                                } else {
                                  _activitiesController
                                      .toggleSelectAll(currentTabIndex);
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
                                if (_activitiesController
                                    .isShoutsSection(currentTabIndex)) {
                                  await _shoutsSectionKey.currentState
                                      ?.removeSelected();
                                } else {
                                  await _activitiesController
                                      .removeSelected(currentTabIndex);
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
                                  if (_activitiesController
                                      .isShoutsSection(currentTabIndex)) {
                                    await _shoutsSectionKey.currentState
                                        ?.nukeSection();
                                  } else {
                                    await _activitiesController
                                        .nukeSection(currentTabIndex);
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
                              if (isShoutsNotificationSectionTitle(
                                  section.title)) {
                                return ShoutsSectionWidget(
                                  key: _shoutsSectionKey,
                                  service: service,
                                  isActive:
                                      (_tabController?.index ?? 0) == index,
                                );
                              } else {
                                return NotificationSectionWidget(
                                  sectionIndex: index,
                                  controller: _activitiesController,
                                );
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
      ),
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
        FaNetworkImage(
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
        FaNetworkImage(
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
