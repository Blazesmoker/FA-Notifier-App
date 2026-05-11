import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_switch/flutter_switch.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:FANotifier/features/drawer/data/app_update_service.dart';
import 'package:FANotifier/features/profile/domain/user_profile.dart';
import 'package:FANotifier/features/notifications/domain/notifications.dart';
import 'package:FANotifier/features/search/presentation/find_source_screen.dart';
import 'package:FANotifier/features/settings/presentation/settings_screen.dart';
import 'package:FANotifier/features/profile/presentation/user_profile_screen.dart';
import 'package:FANotifier/features/notifications/data/fa_notification_service.dart';
import 'package:FANotifier/features/drawer/domain/drawer_list.dart';
import 'package:FANotifier/features/drawer/domain/drawer_index.dart';
import 'package:FANotifier/shared/widgets/PulsatingLoadingIndicator.dart';
import 'package:FANotifier/shared/widgets/StarBurstAnimation.dart';
import 'package:FANotifier/features/notifications/presentation/notification_badge.dart';
import 'dart:async';
import 'package:FANotifier/app/app_theme.dart';
import 'package:FANotifier/shared/utils/fa_link_handler.dart';
import 'package:provider/provider.dart';

class HomeDrawer extends StatefulWidget {
  const HomeDrawer({
    Key? key,
    this.screenIndex,
    this.iconAnimationController,
    this.callBackIndex,
    required this.onLogout,
    required this.userProfile,
    required this.onNoteCounterTap,
    required this.onNotesCountChanged,
    required this.onNotificationsUpdated,
    required this.onBadgeTap,
  }) : super(key: key);

  final AnimationController? iconAnimationController;
  final DrawerIndex? screenIndex;
  final Function(DrawerIndex)? callBackIndex;
  final Function onLogout;
  final UserProfile? userProfile;
  final VoidCallback onNoteCounterTap;
  final Function(int) onNotesCountChanged;
  final Function(Notifications) onNotificationsUpdated;
  final Function(String) onBadgeTap;

  @override
  _HomeDrawerState createState() => _HomeDrawerState();
}

class _HomeDrawerState extends State<HomeDrawer> {
  List<DrawerList>? drawerList;

  Notifications _notifications = Notifications(
    submissions: '0',
    watches: '0',
    journals: '0',
    notes: '0',
    comments: '0',
    favorites: '0',
    registeredUsersOnline: '0',
  );

  FANotificationService? _faNotificationService;
  bool _sfwEnabled = true;
  static const String NsfwConfirmationDisabled = 'nsfwConfirmationDisabled';

  GlobalKey _kofiKey = GlobalKey();
  List<Offset>? _starOrigins;

  Timer? _kofiTimer;
  bool _isCooldownActive = false;

  String? _latestGithubVersion;
  String? _currentAppVersion;
  bool _updateAvailable = false;

  @override
  void initState() {
    super.initState();
    setDrawerListArray();
    _loadSfwEnabled();
    _faNotificationService =
        Provider.of<FANotificationService>(context, listen: false);
    _faNotificationService?.addListener(_onFaNotificationServiceChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _onFaNotificationServiceChanged();
    });
    _checkForUpdate();
  }

  @override
  void dispose() {
    _faNotificationService?.removeListener(_onFaNotificationServiceChanged);
    _faNotificationService = null;
    _kofiTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkForUpdate() async {
    final updateInfo = await fetchLatestAppUpdateInfo();
    if (!mounted || updateInfo == null) return;

    setState(() {
      _currentAppVersion = updateInfo.currentVersion;
      _latestGithubVersion = updateInfo.latestVersion;
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
        index: DrawerIndex.Upload,
        labelName: 'Upload Submission',
        icon: const Icon(Icons.upload),
      ),
      DrawerList(
        index: DrawerIndex.Help,
        labelName: 'Find Source',
        icon: const Icon(Icons.image_search),
      ),
      DrawerList(
        index: DrawerIndex.Help,
        labelName: 'Open Link',
        icon: const Icon(Icons.open_in_browser),
      ),
      DrawerList(
        index: DrawerIndex.Help,
        labelName: 'Settings',
        icon: const Icon(Icons.settings),
      ),
      DrawerList(
        index: DrawerIndex.Help,
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

      const url = 'https://ko-fi.com/fanotifier';
      launchUrlString(url, mode: LaunchMode.externalApplication);
    });
  }

  Widget inkwell(DrawerList listData) {
    final isKoFi = listData.labelName == 'Support us on Ko-Fi!';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        splashColor: isKoFi ? Colors.transparent : Colors.grey.withOpacity(0.1),
        highlightColor: isKoFi ? Colors.transparent : Colors.transparent,
        splashFactory: isKoFi ? NoSplash.splashFactory : null,
        onTap: () {
          if (listData.labelName == 'Settings') {
            navigationtoScreen(listData.index!);
          } else if (listData.labelName == 'Open Link') {
            _showOpenLinkDialog(context);
          } else if (listData.labelName == 'Support us on Ko-Fi!') {
          } else if (listData.labelName == 'Find Source') {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const FindSourceScreen()),
            );
          } else {
            navigationtoScreen(listData.index!);
          }
        },
        child: Stack(
          children: <Widget>[
            if (listData.labelName == 'Support us on Ko-Fi!')
              GestureDetector(
                key: _kofiKey,
                behavior: HitTestBehavior.opaque,
                onTapDown: (TapDownDetails details) {
                  _onKofiPressed(details.globalPosition);
                },
                child: Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(
                      left: 8, right: 16, top: 9, bottom: 9),
                  padding: const EdgeInsets.only(
                      left: 8, right: 16, top: 9, bottom: 9),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.max,
                        children: [
                          SizedBox(
                            width: 24,
                            height: 24,
                            child: Image.asset(listData.imageName),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            listData.labelName,
                            style: const TextStyle(
                              fontWeight: FontWeight.w500,
                              fontSize: 16,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                      if (showStars && _starOrigins != null)
                        Positioned.fill(
                          child: StarBurstAnimation(
                            origins: _starOrigins!,
                            onCompleted: () {
                              setState(() {
                                showStars = false;
                                _starOrigins = null;
                              });
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              )
            else
              Container(
                height: 54.0,
                alignment: Alignment.centerLeft,
                child: Row(
                  children: <Widget>[
                    const SizedBox(width: 6.0, height: 46.0),
                    const Padding(padding: EdgeInsets.all(4.0)),
                    listData.isAssetsImage
                        ? SizedBox(
                            width: 24,
                            height: 24,
                            child: Image.asset(
                              listData.imageName,
                              color: widget.screenIndex == listData.index
                                  ? Colors.white
                                  : Colors.grey.shade300,
                            ),
                          )
                        : Icon(
                            listData.icon?.icon,
                            color: widget.screenIndex == listData.index
                                ? Colors.grey
                                : Colors.grey,
                          ),
                    const Padding(padding: EdgeInsets.all(4.0)),
                    Text(
                      listData.labelName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w500,
                        fontSize: 16,
                        color: Colors.white,
                      ),
                      textAlign: TextAlign.left,
                    ),
                  ],
                ),
              ),
            if (widget.screenIndex == listData.index &&
                listData.labelName != 'Support us on Ko-Fi!')
              AnimatedBuilder(
                animation: widget.iconAnimationController!,
                builder: (BuildContext context, Widget? child) {
                  final drawerContentWidth =
                      MediaQuery.sizeOf(context).width * 0.75 - 64;
                  return Transform(
                    transform: Matrix4.translationValues(
                      drawerContentWidth *
                          (1.0 - widget.iconAnimationController!.value - 1.0),
                      0.0,
                      0.0,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: Container(
                        width: drawerContentWidth,
                        height: 46,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: const BorderRadius.only(
                            topRight: Radius.circular(28),
                            bottomRight: Radius.circular(28),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  void _showOpenLinkDialog(BuildContext context) {
    final TextEditingController _controller = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Open Link'),
          content: TextField(
            controller: _controller,
            decoration: const InputDecoration(labelText: 'Enter link'),
          ),
          actions: [
            TextButton(
              style: TextButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
              ),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              style: TextButton.styleFrom(
                backgroundColor: const Color(0xFFE09321),
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                final String url = _controller.text.trim();
                if (url.isNotEmpty) {
                  // Close dialog first, then handle the link
                  Navigator.of(context).pop();

                  _handleFALink(context, url);
                } else {
                  Navigator.of(context).pop();
                }
              },
              child: const Text('Ok'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _handleFALink(BuildContext context, String url) async {
    try {
      String cleanUrl = url.trim();
      if (!cleanUrl.startsWith('http://') && !cleanUrl.startsWith('https://')) {
        cleanUrl = 'https://$cleanUrl';
      }
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
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _sfwEnabled = prefs.getBool('sfwEnabled') ?? true;
    });
  }

  Future<void> _saveSfwEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('sfwEnabled', _sfwEnabled);
  }

  Future<void> _showNsfwConfirmationDialog() async {
    bool currentSfw = _sfwEnabled;
    String targetMode = currentSfw ? "NSFW" : "SFW";
    Color yesColor = Colors.white;
    String dialogMessage = "Are you sure you want to enable $targetMode mode?";
    bool _dontAskAgain = false;

    final result = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return Dialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16.0)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Confirm Mode Switch",
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    Text(dialogMessage, style: const TextStyle(fontSize: 16)),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () =>
                              Navigator.of(dialogContext).pop(false),
                          style: TextButton.styleFrom(
                              backgroundColor: Colors.white),
                          child: const Text("No",
                              style: TextStyle(color: Colors.black)),
                        ),
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: () {
                            Navigator.of(dialogContext).pop(true);
                          },
                          style: TextButton.styleFrom(
                              backgroundColor: const Color(0xFFE09321)),
                          child: Text("Yes", style: TextStyle(color: yesColor)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Compact checkbox layout
                    Row(
                      children: [
                        CheckboxTheme(
                          data: CheckboxThemeData(
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            side:
                                const BorderSide(width: 1, color: Colors.white),
                            fillColor: WidgetStateProperty.resolveWith<Color>(
                                (Set<WidgetState> states) {
                              if (states.contains(WidgetState.selected)) {
                                return const Color(0xFFE09321);
                              }
                              return Colors.transparent;
                            }),
                            checkColor: WidgetStateProperty.all(Colors.white),
                          ),
                          child: Checkbox(
                            value: _dontAskAgain,
                            onChanged: (bool? value) {
                              setStateDialog(() {
                                _dontAskAgain = value ?? false;
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 1),
                        const Text("Don't ask anymore",
                            style: TextStyle(fontSize: 14)),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (result == true) {
      if (_dontAskAgain) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(NsfwConfirmationDisabled, true);
      }
      await _toggleNsfwMode();
    }
  }

  Future<void> navigationtoScreen(DrawerIndex indexScreen) async {
    if (indexScreen == DrawerIndex.Help) {
      Navigator.push(
        context,
        MaterialPageRoute(
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
            widget.callBackIndex!(DrawerIndex.Submissions);
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
            widget.callBackIndex!(DrawerIndex.Notifications);
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
            widget.callBackIndex!(DrawerIndex.Notifications);
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
            widget.callBackIndex!(DrawerIndex.Notifications);
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
            widget.callBackIndex!(DrawerIndex.Notifications);
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
            widget.callBackIndex!(DrawerIndex.Notes);
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
              // User Profile Section with avatar
              Container(
                width: double.infinity,
                padding: const EdgeInsets.only(top: 0.0),
                color: Color(0xFF111111),
                child: Container(
                  padding: const EdgeInsets.only(
                      right: 0.0, left: 0.0, top: 4.0, bottom: 4.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: <Widget>[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // Avatar widget
                          GestureDetector(
                            onTap: () {
                              if (widget.userProfile != null &&
                                  widget.userProfile!.profileImageUrl
                                      .isNotEmpty) {
                                final String imageUrl =
                                    widget.userProfile!.profileImageUrl;
                                final String filename =
                                    imageUrl.split('/').last;
                                final String nickname = filename.contains('.')
                                    ? filename.substring(
                                        0, filename.lastIndexOf('.'))
                                    : filename;
                                final String lowercaseNickname =
                                    nickname.toLowerCase();
                                debugPrint(
                                    "Extracted nickname: $lowercaseNickname");
                                Navigator.push(
                                  context,
                                  UserProfileScreen.route(
                                    nickname: lowercaseNickname,
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
                            child: widget.userProfile != null &&
                                    widget
                                        .userProfile!.profileImageUrl.isNotEmpty
                                ? AnimatedBuilder(
                                    animation: widget.iconAnimationController!,
                                    builder:
                                        (BuildContext context, Widget? child) {
                                      return ScaleTransition(
                                        scale: AlwaysStoppedAnimation<double>(
                                          1.0 -
                                              (widget.iconAnimationController!
                                                      .value) *
                                                  0.2,
                                        ),
                                        child: RotationTransition(
                                          turns: const AlwaysStoppedAnimation<
                                              double>(0.0),
                                          child: Container(
                                            height: 110,
                                            width: 110,
                                            decoration: BoxDecoration(
                                              borderRadius:
                                                  BorderRadius.circular(12.0),
                                              boxShadow: <BoxShadow>[
                                                BoxShadow(
                                                  color: AppTheme.grey
                                                      .withOpacity(0.0),
                                                  offset:
                                                      const Offset(2.0, 4.0),
                                                  blurRadius: 8,
                                                ),
                                              ],
                                            ),
                                            child: Image.network(
                                              widget
                                                  .userProfile!.profileImageUrl,
                                              fit: BoxFit.cover,
                                              loadingBuilder: (context, child,
                                                  loadingProgress) {
                                                if (loadingProgress == null) {
                                                  return child;
                                                }
                                                return const Center(
                                                  child:
                                                      PulsatingLoadingIndicator(
                                                    size: 58.0,
                                                    assetPath:
                                                        'assets/icons/fathemed.png',
                                                  ),
                                                );
                                              },
                                              errorBuilder:
                                                  (context, error, stackTrace) {
                                                if (error
                                                    .toString()
                                                    .contains('404')) {
                                                  return Image.asset(
                                                    'assets/images/defaultpic.gif',
                                                    fit: BoxFit.cover,
                                                  );
                                                } else {
                                                  return const Icon(
                                                    Icons.person,
                                                    size: 60,
                                                    color: Colors.white,
                                                  );
                                                }
                                              },
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  )
                                : ClipRRect(
                                    borderRadius: const BorderRadius.all(
                                      Radius.circular(60.0),
                                    ),
                                    child: Image.asset(
                                      'assets/images/defaultpic.gif',
                                      width: 120,
                                      height: 120,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      const Divider(
                        height: 4.0,
                        color: Colors.black,
                        thickness: 4.0,
                      ),
                      const SizedBox(height: 8),
                      // Username
                      Text(
                        widget.userProfile?.username ?? 'Username',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                          fontSize: 19,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Divider(
                        height: 3.0,
                        color: Colors.black,
                        thickness: 3.0,
                      ),
                      const SizedBox(height: 6),
                      // Notifications Row
                      Container(
                        color: Colors.black,
                        padding: const EdgeInsets.symmetric(
                            vertical: 8, horizontal: 16.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: badgesWithSpacing,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Drawer Items
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
                              return Padding(
                                padding: const EdgeInsets.fromLTRB(
                                    16.0, 14.0, 16.0, 4.0),
                                child: Center(
                                  child: ConstrainedBox(
                                    constraints:
                                        const BoxConstraints(maxWidth: 200),
                                    child: Material(
                                      color: const Color(0xFF3ACD3E),
                                      borderRadius: BorderRadius.circular(26),
                                      clipBehavior: Clip.antiAlias,
                                      child: InkWell(
                                        onTap: () => launchUrlString(
                                          'https://t.me/+xTEmmXoDW5tkMGFi',
                                          mode: LaunchMode.externalApplication,
                                        ),
                                        child: const SizedBox(
                                          height: 44,
                                          child: Center(
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                Icon(Icons.cached,
                                                    color: Colors.white),
                                                SizedBox(width: 6),
                                                Text(
                                                  'Update Available!',
                                                  style: TextStyle(
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.w600,
                                                    fontSize: 16,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }

                            final int drawerIndex =
                                showUpdateButton ? index - 1 : index;
                            return inkwell(drawerList![drawerIndex]);
                          },
                        ),
                      ),

                      // NSFW Toggle
                      Padding(
                        padding: const EdgeInsets.only(
                          bottom: 10.0,
                          top: 6.0,
                          right: 16.0,
                          left: 16.0,
                        ),
                        child: Row(
                          children: [
                            FlutterSwitch(
                              width: 68.0,
                              height: 30.0,
                              toggleSize: 20.0,
                              value: !_sfwEnabled,
                              borderRadius: 18.0,
                              padding: 3,
                              activeText: 'NSFW',
                              inactiveText: ' SFW',
                              valueFontSize: 11.6,
                              activeTextColor: Colors.black,
                              activeToggleColor: Colors.black,
                              inactiveTextColor: Colors.white,
                              activeColor: const Color(0xFFE09321),
                              inactiveColor: const Color(0xFF111111),
                              showOnOff: true,
                              onToggle: (val) async {
                                final prefs =
                                    await SharedPreferences.getInstance();
                                bool confirmationDisabled =
                                    prefs.getBool(NsfwConfirmationDisabled) ??
                                        false;
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

                      const Divider(
                        height: 1.0,
                        color: Color(0xFF111111),
                        thickness: 3.0,
                      ),

                      Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: 8.0,
                          horizontal: 16.0,
                        ),
                        child: Text(
                          'Registered users online: ${_notifications.registeredUsersOnline}',
                          style: const TextStyle(
                              fontSize: 14, color: Colors.white),
                          textAlign: TextAlign.left,
                        ),
                      ),

                      SizedBox(height: MediaQuery.paddingOf(context).bottom),
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
