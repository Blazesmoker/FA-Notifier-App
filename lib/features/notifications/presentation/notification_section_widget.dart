import 'package:fanotifier/core/preferences/sfw_mode_preference.dart';
import 'package:fanotifier/features/journals/presentation/openjournal.dart';
import 'package:fanotifier/features/notifications/presentation/fa_notification_service.dart';
import 'package:fanotifier/features/notifications/domain/notification_message_formatter.dart';
import 'package:fanotifier/features/notifications/domain/notification_section_kind.dart';
import 'package:fanotifier/features/notifications/presentation/notification_activities_controller.dart';
import 'package:fanotifier/features/notifications/presentation/notification_shouts_section.dart';
import 'package:fanotifier/features/profile/domain/profile_section.dart';
import 'package:fanotifier/features/profile/presentation/user_profile_screen.dart';
import 'package:fanotifier/features/submissions/presentation/openpost.dart';
import 'package:fanotifier/shared/utils/fa_link_matcher.dart';
import 'package:fanotifier/shared/widgets/fa_network_image.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:html/dom.dart' as dom;
import 'package:provider/provider.dart';

/// Widget for non-shouts sections.
class NotificationSectionWidget extends StatelessWidget {
  final int sectionIndex;
  final NotificationActivitiesController controller;
  final SfwModePreference _sfwModePreference = const SfwModePreference();
  const NotificationSectionWidget({
    super.key,
    required this.sectionIndex,
    required this.controller,
  })
      ;

  Future<bool> isSfwModeEnabled() async {
    return _sfwModePreference.loadSfwEnabled();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<FANotificationService>(
      builder: (context, service, child) {
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
                                                                .gallery,
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
                                                                .gallery,
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
                                                                .journals,
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
                                              future: service
                                                  .fetchSubmissionPreview(
                                                submissionId,
                                              ),
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

class FadeInNetworkImage extends StatefulWidget {
  final String imageUrl;
  final BoxFit fit;
  final Alignment alignment;
  final Duration duration;
  final Widget placeholder;
  final Widget errorWidget;

  const FadeInNetworkImage({
    super.key,
    required this.imageUrl,
    required this.placeholder,
    required this.errorWidget,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
    this.duration = const Duration(milliseconds: 250),
  });

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
          errorBuilder: (_, _, _) => widget.errorWidget,
        ),
      ],
    );
  }
}
