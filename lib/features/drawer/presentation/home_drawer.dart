import 'widgets/home_drawer_row.dart';
import 'widgets/home_drawer_dialogs.dart';
import 'widgets/home_drawer_profile_header.dart';
import 'widgets/home_drawer_update_button.dart';
import 'widgets/home_drawer_footer.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:fanotifier/features/drawer/domain/app_update_repository.dart';
import 'package:fanotifier/features/drawer/domain/nsfw_confirmation_repository.dart';
import 'package:fanotifier/core/preferences/sfw_mode_preference.dart';
import 'package:fanotifier/shared/fa/domain/user_profile.dart';
import 'package:fanotifier/shared/fa/domain/notifications.dart';
import 'package:fanotifier/features/search/presentation/find_source_screen.dart';
import 'package:fanotifier/core/analytics/app_screen.dart';
import 'package:fanotifier/features/settings/presentation/settings_screen.dart';
import 'package:fanotifier/features/profile/presentation/user_profile_screen.dart';
import 'package:fanotifier/features/notifications/presentation/fa_notifications_controller.dart';
import 'package:fanotifier/features/drawer/presentation/drawer_list.dart';
import 'package:fanotifier/features/drawer/domain/drawer_index.dart';
import 'package:fanotifier/core/links/app_external_links.dart';
import 'package:fanotifier/features/notifications/presentation/notification_badge.dart';
import 'dart:async';
import 'package:fanotifier/shared/theme/app_theme.dart';
import 'package:fanotifier/shared/navigation/fa_link_handler.dart';
import 'package:provider/provider.dart';

class HomeDrawer extends StatefulWidget {
  const HomeDrawer({
    super.key,
    this.selectedDrawerItem,
    this.iconAnimationController,
    this.callBackIndex,
    required this.onLogout,
    required this.userProfile,
    required this.onNoteCounterTap,
    required this.onNotesCountChanged,
    required this.onNotificationsUpdated,
    required this.onBadgeTap,
    required this.onUserProfileChanged,
    this.isUserProfileLoading = false,
  });

  final AnimationController? iconAnimationController;
  final DrawerIndex? selectedDrawerItem;
  final Function(DrawerIndex)? callBackIndex;
  final Function onLogout;
  final UserProfile? userProfile;
  final VoidCallback onNoteCounterTap;
  final Function(int) onNotesCountChanged;
  final Function(Notifications) onNotificationsUpdated;
  final Function(String) onBadgeTap;
  final VoidCallback onUserProfileChanged;
  final bool isUserProfileLoading;

  @override
  State<HomeDrawer> createState() => _HomeDrawerState();
}

class _HomeDrawerState extends State<HomeDrawer> {
  List<DrawerList>? drawerList;
  int _avatarRevision = 0;

  Notifications _notifications = Notifications(
    submissions: '0',
    watches: '0',
    journals: '0',
    notes: '0',
    comments: '0',
    favorites: '0',
    registeredUsersOnline: '0',
  );

  FaNotificationsController? _faNotificationService;
  final SfwModePreference _sfwModePreference = SfwModePreference();
  late final AppUpdateRepository _appUpdateRepository;
  late final NsfwConfirmationRepository _nsfwConfirmationRepository;
  bool _sfwEnabled = true;

  final GlobalKey _kofiKey = GlobalKey();
  List<Offset>? _starOrigins;

  Timer? _kofiTimer;
  bool _isCooldownActive = false;

  bool _updateAvailable = false;

  @override
  void initState() {
    super.initState();
    _appUpdateRepository = context.read<AppUpdateRepository>();
    _nsfwConfirmationRepository =
        context.read<NsfwConfirmationRepository>();
    setDrawerListArray();
    _loadSfwEnabled();
    _faNotificationService =
        Provider.of<FaNotificationsController>(context, listen: false);
    _faNotificationService?.addListener(_onFaNotificationServiceChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _onFaNotificationServiceChanged();
    });
    _checkForUpdate();
  }

  @override
  void didUpdateWidget(HomeDrawer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.userProfile, widget.userProfile)) {
      _avatarRevision++;
    }
  }

  @override
  void dispose() {
    _faNotificationService?.removeListener(_onFaNotificationServiceChanged);
    _faNotificationService = null;
    _kofiTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkForUpdate() async {
    final updateInfo = await _appUpdateRepository.fetchLatest();
    if (!mounted || updateInfo == null) return;

    setState(() {
      _updateAvailable = updateInfo.updateAvailable;
    });
  }

  void _onFaNotificationServiceChanged() {
    final svc = _faNotificationService;
    if (svc == null) return;
    final next = svc.latestTopBarNotifications;

    final bool changed = _notifications.submissions != next.submissions ||
        _notifications.watches != next.watches ||
        _notifications.journals != next.journals ||
        _notifications.notes != next.notes ||
        _notifications.comments != next.comments ||
        _notifications.favorites != next.favorites ||
        _notifications.registeredUsersOnline != next.registeredUsersOnline;

    if (!changed) return;

    if (mounted) {
      setState(() {
        _notifications = next;
      });
    }

    final int actualNotesCount = int.tryParse(next.notes) ?? 0;
    widget.onNotesCountChanged(actualNotesCount);
    widget.onNotificationsUpdated(next);
  }

  void setDrawerListArray() {
    drawerList = <DrawerList>[
      DrawerList(
        index: DrawerIndex.upload,
        labelName: 'Upload Submission',
        icon: const Icon(Icons.upload),
      ),
      DrawerList(
        index: DrawerIndex.help,
        labelName: 'Find Source',
        icon: const Icon(Icons.image_search),
      ),
      DrawerList(
        index: DrawerIndex.help,
        labelName: 'Open Link',
        icon: const Icon(Icons.open_in_browser),
      ),
      DrawerList(
        index: DrawerIndex.help,
        labelName: 'Settings',
        icon: const Icon(Icons.settings),
      ),
      DrawerList(
        index: DrawerIndex.help,
        labelName: 'Support us on Ko-Fi!',
        isAssetsImage: true,
        imageName: 'assets/images/kofi_symbol.png',
      ),
    ];
  }

  bool showStars = false;

  void _onKofiPressed(Offset globalTapPosition) {
    // Ignore if in cooldown
    if (_isCooldownActive) return;

    final renderBox = _kofiKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox != null) {
      final localPosition = renderBox.globalToLocal(globalTapPosition);

      setState(() {
        _starOrigins = [localPosition];
        showStars = true;
      });
    }

    _isCooldownActive = true;

    // Schedule link opening and reset
    _kofiTimer = Timer(const Duration(milliseconds: 1400), () {
      if (mounted) {
        setState(() {
          showStars = false;
          _starOrigins = null;
          _isCooldownActive = false;
        });
      }

      const url = AppExternalLinks.koFiUrl;
      launchUrlString(url, mode: LaunchMode.externalApplication);
    });
  }

  Widget inkwell(DrawerList listData) {
    final isKoFi = listData.labelName == 'Support us on Ko-Fi!';
    return buildHomeDrawerRow(
      context,
      listData: listData,
      isKoFi: isKoFi,
      selectedDrawerItem: widget.selectedDrawerItem,
      animationController: () => widget.iconAnimationController,
      kofiKey: _kofiKey,
      showStars: showStars,
      starOrigins: _starOrigins,
      onKofiPressed: _onKofiPressed,
      onStarsCompleted: () {
        setState(() {
          showStars = false;
          _starOrigins = null;
        });
      },
      onTap: () {
        if (listData.labelName == 'Settings') {
          navigationtoScreen(listData.index!);
        } else if (listData.labelName == 'Open Link') {
          _showOpenLinkDialog(context);
        } else if (listData.labelName == 'Support us on Ko-Fi!') {
        } else if (listData.labelName == 'Find Source') {
          Navigator.push(
            context,
            MaterialPageRoute(
              settings: const AnalyticsRouteSettings(AppScreens.findSource),
              builder: (context) => const FindSourceScreen(),
            ),
          );
        } else {
          navigationtoScreen(listData.index!);
        }
      },
    );
  }

  void _showOpenLinkDialog(BuildContext context) {
    final TextEditingController controller = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return buildDrawerOpenLinkDialog(
          context,
          controller: controller,
          onOpen: _handleFALink,
        );
      },
    );
  }

  Future<void> _handleFALink(BuildContext context, String url) async {
    try {
      final cleanUrl = normalizeInputUrl(url);
      debugPrint('Processing URL: $cleanUrl');
      if (!context.mounted) {
        debugPrint('Context not mounted, cannot navigate');
        return;
      }
      await handleFALink(context, cleanUrl);
    } catch (e) {
      debugPrint('Error handling FA link: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error opening link: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _loadSfwEnabled() async {
    final sfwEnabled = await _sfwModePreference.loadSfwEnabled();
    setState(() {
      _sfwEnabled = sfwEnabled;
    });
  }

  Future<void> _saveSfwEnabled() async {
    await _sfwModePreference.saveSfwEnabled(_sfwEnabled);
  }

  Future<void> _showNsfwConfirmationDialog() async {
    bool currentSfw = _sfwEnabled;
    String targetMode = currentSfw ? "NSFW" : "SFW";
    Color yesColor = Colors.white;
    String dialogMessage = "Are you sure you want to enable $targetMode mode?";
    bool dontAskAgain = false;

    final result = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return buildDrawerModeConfirmationDialog(
              dialogContext,
              dialogMessage: dialogMessage,
              yesColor: yesColor,
              dontAskAgain: dontAskAgain,
              onChanged: (bool? value) {
                setStateDialog(() {
                  dontAskAgain = value ?? false;
                });
              },
            );
          },
        );
      },
    );

    if (!mounted) return;
    if (result == true) {
      if (dontAskAgain) {
        await _nsfwConfirmationRepository.saveDisabled(true);
      }
      await _toggleNsfwMode();
    }
  }

  Future<void> navigationtoScreen(DrawerIndex indexScreen) async {
    if (indexScreen == DrawerIndex.help) {
      Navigator.push(
        context,
        MaterialPageRoute(
          settings: const AnalyticsRouteSettings(AppScreens.settings),
          builder: (context) => SettingsScreen(
            onLogout: widget.onLogout, // Pass the logout callback to Settings
          ),
        ),
      );
      return;
    }

    if (widget.callBackIndex != null) {
      widget.callBackIndex!(indexScreen);
    }
  }

  Future<void> _toggleNsfwMode() async {
    setState(() {
      _sfwEnabled = !_sfwEnabled;
    });
    await _saveSfwEnabled();
    await Future.delayed(const Duration(seconds: 1));
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    final int submissionsCount = int.tryParse(_notifications.submissions) ?? 0;
    final int watchesCount = int.tryParse(_notifications.watches) ?? 0;
    final int commentsCount = int.tryParse(_notifications.comments) ?? 0;
    final int favoritesCount = int.tryParse(_notifications.favorites) ?? 0;
    final int journalsCount = int.tryParse(_notifications.journals) ?? 0;
    final int notesCount = int.tryParse(_notifications.notes) ?? 0;

    final List<Widget> badgeWidgets = [];
    if (submissionsCount > 0) {
      badgeWidgets.add(
        GestureDetector(
          onTap: () {
            widget.onBadgeTap('Submissions');
            widget.callBackIndex!(DrawerIndex.submissions);
          },
          child: NotificationBadge(
            count: _notifications.submissions,
            label: 'S',
          ),
        ),
      );
    }
    if (watchesCount > 0) {
      badgeWidgets.add(
        GestureDetector(
          onTap: () {
            widget.onBadgeTap('Watches');
            widget.callBackIndex!(DrawerIndex.notifications);
          },
          child: NotificationBadge(
            count: _notifications.watches,
            label: 'W',
          ),
        ),
      );
    }
    if (commentsCount > 0) {
      badgeWidgets.add(
        GestureDetector(
          onTap: () {
            widget.onBadgeTap('Comments');
            widget.callBackIndex!(DrawerIndex.notifications);
          },
          child: NotificationBadge(
            count: _notifications.comments,
            label: 'C',
          ),
        ),
      );
    }
    if (favoritesCount > 0) {
      badgeWidgets.add(
        GestureDetector(
          onTap: () {
            widget.onBadgeTap('Favorites');
            widget.callBackIndex!(DrawerIndex.notifications);
          },
          child: NotificationBadge(
            count: _notifications.favorites,
            label: 'F',
          ),
        ),
      );
    }
    if (journalsCount > 0) {
      badgeWidgets.add(
        GestureDetector(
          onTap: () {
            widget.onBadgeTap('Journals');
            widget.callBackIndex!(DrawerIndex.notifications);
          },
          child: NotificationBadge(
            count: _notifications.journals,
            label: 'J',
          ),
        ),
      );
    }
    if (notesCount > 0) {
      badgeWidgets.add(
        GestureDetector(
          onTap: () {
            widget.onBadgeTap('Notes');
            widget.callBackIndex!(DrawerIndex.notes);
          },
          child: NotificationBadge(
            count: _notifications.notes,
            label: 'N',
          ),
        ),
      );
    }

    final List<Widget> badgesWithSpacing = [];
    for (int i = 0; i < badgeWidgets.length; i++) {
      if (i != 0) {
        badgesWithSpacing.add(const SizedBox(width: 8));
      }
      badgesWithSpacing.add(
        Flexible(
          child: badgeWidgets[i],
        ),
      );
    }

    const bool kForceShowUpdateButton = false;
    final bool showUpdateButton =
        _updateAvailable || (kDebugMode && kForceShowUpdateButton);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        systemNavigationBarColor: Colors.black, // ✅ black navbar
        systemNavigationBarIconBrightness: Brightness.light,
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
      child: Container(
        color: Color(0xFF111111),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisAlignment: MainAxisAlignment.start,
            children: <Widget>[
              buildHomeDrawerProfileHeader(
                userProfile: widget.userProfile,
                isUserProfileLoading: widget.isUserProfileLoading,
                animationController: () => widget.iconAnimationController,
                avatarRevision: _avatarRevision,
                badgesWithSpacing: badgesWithSpacing,
                onProfileTap: () {
                  final profile = widget.userProfile;
                  final lowercaseNickname = profile == null
                      ? null
                      : userProfileRouteNickname(profile);
                  if (lowercaseNickname != null) {
                    debugPrint("Extracted nickname: $lowercaseNickname");
                    Navigator.push(
                      context,
                      UserProfileScreen.route(
                        nickname: lowercaseNickname,
                        onProfileChanged: widget.onUserProfileChanged,
                      ),
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('User profile not available'),
                      ),
                    );
                  }
                },
              ),
              Expanded(
                child: Container(
                  color: AppTheme.background,
                  child: Column(
                    children: [
                      Expanded(
                        child: ListView.builder(
                          physics: const BouncingScrollPhysics(),
                          padding: EdgeInsets.zero,
                          itemCount:
                              drawerList!.length + (showUpdateButton ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (showUpdateButton && index == 0) {
                              return buildHomeDrawerUpdateButton(
                                onTap: () => launchUrlString(
                                  AppExternalLinks.telegramUrl,
                                  mode: LaunchMode.externalApplication,
                                ),
                              );
                            }

                            final int drawerIndex =
                                showUpdateButton ? index - 1 : index;
                            return inkwell(drawerList![drawerIndex]);
                          },
                        ),
                      ),

                      ...buildHomeDrawerFooter(
                        context,
                        sfwEnabled: _sfwEnabled,
                        registeredUsersOnline:
                            _notifications.registeredUsersOnline,
                        onToggle: (val) async {
                          bool confirmationDisabled =
                              await _nsfwConfirmationRepository.loadDisabled();
                          if (confirmationDisabled) {
                            await _toggleNsfwMode();
                          } else {
                            await _showNsfwConfirmationDialog();
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
