import 'package:fanotifier/features/notifications/presentation/fa_notification_service.dart';
import 'package:fanotifier/shared/fa/domain/fa_activities_polling_port.dart';
import 'package:fanotifier/features/notifications/domain/fa_notification_models.dart';
import 'package:fanotifier/features/notifications/presentation/notification_shouts_controller.dart';
import 'package:fanotifier/features/profile/presentation/user_profile_screen.dart';
import 'package:fanotifier/shared/utils/special_text_span_builder.dart';
import 'package:fanotifier/shared/widgets/fa_network_image.dart';
import 'package:extended_text/extended_text.dart';
import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';

/// A widget that toggles between relative and absolute date formats when tapped.
class ToggleableDate extends StatefulWidget {
  final String relativeDate;
  final String absoluteDate;

  const ToggleableDate({
    super.key,
    required this.relativeDate,
    required this.absoluteDate,
  });

  @override
  State<ToggleableDate> createState() => _ToggleableDateState();
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
    super.key,
    required this.imageUrl,
    required this.fallbackAsset,
    this.radius = 24,
  });

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
  final FaActivitiesPollingPort pollingService;
  final bool isActive;

  const ShoutsSectionWidget({
    super.key,
    required this.service,
    required this.pollingService,
    required this.isActive,
  });

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
    _controller = NotificationShoutsController(
      widget.service,
      widget.pollingService,
    );
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
