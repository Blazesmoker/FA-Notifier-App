import 'package:flutter/material.dart';
import 'package:flutter_switch/flutter_switch.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:url_launcher/url_launcher_string.dart';
import '../model/user_profile.dart';
import '../model/notifications.dart';
import '../screens/openjournal.dart';
import '../screens/openpost.dart';
import '../screens/settings_screen.dart';
import '../screens/user_profile_screen.dart';
import '../services/fa_service.dart';
import '../model/drawer_list.dart';
import '../enums/drawer_index.dart';
import '../services/notification_refresh_service.dart';
import '../services/notification_service.dart';
import '../utils/notification_counts.dart';
import '../widgets/PulsatingLoadingIndicator.dart';
import '../widgets/StarBurstAnimation.dart';
import '../widgets/notification_badge.dart';
import 'dart:async';
import '../app_theme.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../providers/notification_settings_provider.dart';

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

class _HomeDrawerState extends State<HomeDrawer> with WidgetsBindingObserver {
  List<DrawerList>? drawerList;

  // Notifications data
  Notifications _notifications = Notifications(
    submissions: '0',
    watches: '0',
    journals: '0',
    notes: '0',
    comments: '0',
    favorites: '0',
    registeredUsersOnline: '0',
  );

  static const String kPreviousSumKey = 'previousSumOfNotifications';
  final FaService _faService = FaService();
  Timer? _timer;
  int _previousSumOfNotifications = 0;
  bool _sfwEnabled = true;
  static const String NsfwConfirmationDisabled = 'nsfwConfirmationDisabled';

  int _previousTotalSumOfNotifications = 0;
  static const String kPreviousTotalSumKey = 'previousTotalSumOfNotifications';

  GlobalKey _kofiKey = GlobalKey();
  List<Offset>? _starOrigins;

  Timer? _kofiTimer;
  bool _isCooldownActive = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    setDrawerListArray();
    _loadPreviousSum();
    _startTimer();
    fetchNotifications();
    _loadSfwEnabled();
    NotificationRefreshService().onRefresh.listen((_) {
      fetchNotifications();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _kofiTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      _startTimer();
      fetchNotifications();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _timer?.cancel();
      _kofiTimer?.cancel();
      _timer = null;
    }
  }

  void _startTimer() {
    if (_timer == null || !_timer!.isActive) {
      _timer = Timer.periodic(
        const Duration(seconds: 120),
        (Timer t) => fetchNotifications(),
      );
    }
  }

  Future<void> fetchNotifications() async {
    try {
      Notifications? notifications = await _faService.fetchNotifications();

      if (mounted) {
        setState(() {
          _notifications = notifications != null
              ? Notifications(
                  submissions: notifications.submissions.replaceAll(',', ''),
                  watches: notifications.watches.replaceAll(',', ''),
                  journals: notifications.journals.replaceAll(',', ''),
                  notes: notifications.notes.replaceAll(',', ''),
                  comments: notifications.comments.replaceAll(',', ''),
                  favorites: notifications.favorites.replaceAll(',', ''),
                  registeredUsersOnline:
                      notifications.registeredUsersOnline.replaceAll(',', ''),
                )
              : Notifications(
                  submissions: '0',
                  watches: '0',
                  journals: '0',
                  notes: '0',
                  comments: '0',
                  favorites: '0',
                  registeredUsersOnline: '0',
                );
        });

        int actualNotesCount = int.tryParse(_notifications.notes) ?? 0;
        widget.onNotesCountChanged(actualNotesCount);
        widget.onNotificationsUpdated(_notifications);

        print(
          'Drawer: Notifications - '
          'Submissions: ${_notifications.submissions}, '
          'Watches: ${_notifications.watches}, '
          'Journals: ${_notifications.journals}, '
          'Notes: ${_notifications.notes}, '
          'Comments: ${_notifications.comments}, '
          'Favorites: ${_notifications.favorites}, '
          'RegisteredUsersOnline: ${_notifications.registeredUsersOnline}',
        );

        final settings =
            Provider.of<NotificationSettingsProvider>(context, listen: false);
        final int submissionsCount = settings.drawerSubmissionsEnabled
            ? (int.tryParse(_notifications.submissions) ?? 0)
            : 0;
        final int watchesCount = settings.drawerWatchesEnabled
            ? (int.tryParse(_notifications.watches) ?? 0)
            : 0;
        final int commentsCount = settings.drawerCommentsEnabled
            ? (int.tryParse(_notifications.comments) ?? 0)
            : 0;
        final int favoritesCount = settings.drawerFavoritesEnabled
            ? (int.tryParse(_notifications.favorites) ?? 0)
            : 0;
        final int journalsCount = settings.drawerJournalsEnabled
            ? (int.tryParse(_notifications.journals) ?? 0)
            : 0;
        final int filteredNotesCount = settings.drawerNotesEnabled
            ? (int.tryParse(_notifications.notes) ?? 0)
            : 0;

        final int newSum = submissionsCount +
            watchesCount +
            commentsCount +
            favoritesCount +
            journalsCount +
            filteredNotesCount;

        if (newSum != _previousSumOfNotifications) {
          final NotificationCounts filteredCounts = NotificationCounts(
            submissions: submissionsCount,
            watches: watchesCount,
            comments: commentsCount,
            favorites: favoritesCount,
            journals: journalsCount,
            notes: filteredNotesCount,
          );

          final String messageBody = _buildNotificationMessage(filteredCounts);

          if (messageBody.isNotEmpty) {
            final NotificationService notificationService =
                NotificationService();
            await notificationService.showNotification(
              999999,
              'New FA Activity',
              messageBody,
              'activity_fa_activity',
              'activities',
            );

            print(
                '[HomeDrawer] Sent new activities notification: $messageBody');
            _previousSumOfNotifications = newSum;
            await _saveCurrentSum(newSum);
          }
        }

        if (newSum <= _previousSumOfNotifications) {
          _previousSumOfNotifications = newSum;
          await _saveCurrentSum(newSum);
        }
      }
    } catch (e) {
      print('Error fetching notifications: $e');
    }
  }

  Future<void> _loadPreviousSum() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _previousSumOfNotifications = prefs.getInt(kPreviousSumKey) ?? 0;
    });
  }

  Future<void> _saveCurrentSum(int sum) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(kPreviousSumKey, sum);
  }

  String _buildNotificationMessage(NotificationCounts diff) {
    List<String> parts = [];
    if (diff.submissions > 0) parts.add('${diff.submissions}S');
    if (diff.watches > 0) parts.add('${diff.watches}W');
    if (diff.comments > 0) parts.add('${diff.comments}C');
    if (diff.favorites > 0) parts.add('${diff.favorites}F');
    if (diff.journals > 0) parts.add('${diff.journals}J');
    if (diff.notes > 0) parts.add('${diff.notes}N');
    return parts.join(' | ');
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
        labelName: 'Settings',
        icon: const Icon(Icons.settings),
      ),
      DrawerList(
        index: DrawerIndex.Help,
        labelName: 'Open Link',
        icon: const Icon(Icons.open_in_browser),
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
            /*launchUrlString(
              'https://ko-fi.com/fanotifier',
              mode: LaunchMode.externalApplication,
            );
             */
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
                padding: const EdgeInsets.symmetric(vertical: 8.0),
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
                  return Transform(
                    transform: Matrix4.translationValues(
                      (MediaQuery.of(context).size.width * 0.75 - 64) *
                          (1.0 - widget.iconAnimationController!.value - 1.0),
                      0.0,
                      0.0,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: Container(
                        width: MediaQuery.of(context).size.width * 0.75 - 64,
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

      // Add protocol if missing
      if (!cleanUrl.startsWith('http://') && !cleanUrl.startsWith('https://')) {
        cleanUrl = 'https://$cleanUrl';
      }

      print('Processing URL: $cleanUrl');

      final Uri uri = Uri.parse(cleanUrl);
      String urlToMatch = uri.toString();

      if (urlToMatch.endsWith('/')) {
        urlToMatch = urlToMatch.substring(0, urlToMatch.length - 1);
      }

      print('URL to match: $urlToMatch');

      if (!context.mounted) {
        print('Context not mounted, cannot navigate');
        return;
      }

      // 1. Gallery Folder Link:
      final RegExp galleryFolderRegex = RegExp(
        r'^https?://(?:www\.)?furaffinity\.net/gallery/([a-zA-Z0-9\-_.~]+)/folder/(\d+)/([a-zA-Z0-9\-_.~]+)/?$',
      );
      final Match? galleryMatch = galleryFolderRegex.firstMatch(urlToMatch);
      if (galleryMatch != null) {
        print('Matched gallery folder link');
        final String tappedUsername = galleryMatch.group(1)!;
        final String folderNumber = galleryMatch.group(2)!;
        final String folderName = galleryMatch.group(3)!;
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

      // 2. User Link:
      final RegExp userRegex = RegExp(
        r'^https?://(?:www\.)?furaffinity\.net/user/([a-zA-Z0-9\-_.~]+)/?$',
      );
      final Match? userMatch = userRegex.firstMatch(urlToMatch);
      if (userMatch != null) {
        print('Matched user link');
        final String tappedUsername = userMatch.group(1)!;
        print('Navigating to user: $tappedUsername');

        await Navigator.push(
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

      // 4. Submission/View Link:
      final RegExp viewRegex = RegExp(
        r'^https?://(?:www\.)?(?:furaffinity|fxfuraffinity)\.net/view/(\d+)(?:/.*)?(?:#.*)?$',
      );
      final Match? viewMatch = viewRegex.firstMatch(urlToMatch);
      if (viewMatch != null) {
        print('Matched submission link');
        final String submissionId = viewMatch.group(1)!;

        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) =>
                OpenPost(uniqueNumber: submissionId, imageUrl: ''),
          ),
        );
        return;
      }

      // 5. Fallback: open externally
      print('No pattern matched, opening externally: $cleanUrl');
      await launchUrlString(cleanUrl, mode: LaunchMode.externalApplication);
    } catch (e) {
      print('Error handling FA link: $e');
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

    return Container(
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
                                widget
                                    .userProfile!.profileImageUrl.isNotEmpty) {
                              final String imageUrl =
                                  widget.userProfile!.profileImageUrl;
                              final String filename = imageUrl.split('/').last;
                              final String nickname = filename.contains('.')
                                  ? filename.substring(
                                      0, filename.lastIndexOf('.'))
                                  : filename;
                              final String lowercaseNickname =
                                  nickname.toLowerCase();
                              print("Extracted nickname: $lowercaseNickname");
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => UserProfileScreen(
                                    nickname: lowercaseNickname,
                                  ),
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
                                  widget.userProfile!.profileImageUrl.isNotEmpty
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
                                                offset: const Offset(2.0, 4.0),
                                                blurRadius: 8,
                                              ),
                                            ],
                                          ),
                                          child: CachedNetworkImage(
                                            imageUrl: widget
                                                .userProfile!.profileImageUrl,
                                            fit: BoxFit.cover,
                                            placeholder: (context, url) =>
                                                const Center(
                                              child: Center(
                                                child:
                                                    PulsatingLoadingIndicator(
                                                  size: 58.0,
                                                  assetPath:
                                                      'assets/icons/fathemed.png',
                                                ),
                                              ),
                                            ),
                                            errorWidget: (context, url, error) {
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
                        padding: const EdgeInsets.all(0.0),
                        itemCount: drawerList?.length,
                        itemBuilder: (BuildContext context, int index) {
                          return inkwell(drawerList![index]);
                        },
                      ),
                    ),
                    // NSFW Toggle
                    Padding(
                      padding: const EdgeInsets.only(
                          bottom: 12.0, top: 11.0, right: 16.0, left: 16.0),
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
                            activeColor: Color(0xFFE09321),
                            inactiveColor: Color(0xFF111111),
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
                          vertical: 8.0, horizontal: 16.0),
                      child: Text(
                        'Registered users online: ${_notifications.registeredUsersOnline}',
                        style:
                            const TextStyle(fontSize: 14, color: Colors.white),
                        textAlign: TextAlign.left,
                      ),
                    ),
                    SizedBox(height: MediaQuery.of(context).padding.bottom),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
