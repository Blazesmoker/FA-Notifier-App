import 'dart:async';
import 'package:fanotifier/features/drawer/presentation/drawer_user_controller.dart';
import 'package:fanotifier/features/notifications/presentation/fa_notification_service.dart';
import 'package:fanotifier/core/analytics/app_analytics.dart';
import 'package:fanotifier/core/analytics/app_screen.dart';
import 'package:fanotifier/shared/fa/domain/fa_activities_polling_port.dart';
import 'package:fanotifier/features/notifications/domain/notification_section_kind.dart';
import 'package:fanotifier/features/notifications/domain/notification_removal_outcome.dart';
import 'package:fanotifier/features/notifications/presentation/notification_activities_controller.dart';
import 'package:fanotifier/features/notifications/presentation/notification_counter_settings_controller.dart';
import 'package:fanotifier/features/notifications/presentation/notification_section_widget.dart';
import 'package:fanotifier/features/notifications/presentation/notification_settings_provider.dart';
import 'package:fanotifier/features/notifications/presentation/notification_shouts_section.dart';
import 'package:fanotifier/features/notifications/presentation/notification_removal_button_content.dart';
import 'package:fanotifier/shared/widgets/pulsating_loading_indicator.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:visibility_detector/visibility_detector.dart';

/// The main Notifications Screen widget.
class NotificationsScreen extends StatefulWidget {
  final String? initialSection;
  final GlobalKey<DrawerUserControllerState> drawerKey;

  const NotificationsScreen(
      {super.key, required this.drawerKey, this.initialSection})
      ;

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen>
    with TickerProviderStateMixin {
  TabController? _tabController;
  int _initialTabIndex = 0;
  bool _isDraggingFromEdge = false;
  int _previousSectionCount = 0;
  int _lastTabIndex = -1;
  late NotificationActivitiesController _activitiesController;
  late FaActivitiesPollingPort _activitiesPollingPort;
  bool _activitiesControllerInitialized = false;
  NotificationRemovalButtonPhase _removeSelectedPhase =
      NotificationRemovalButtonPhase.idle;
  NotificationRemovalButtonPhase _nukeSectionPhase =
      NotificationRemovalButtonPhase.idle;
  NotificationRemovalButtonPhase _removeAllPhase =
      NotificationRemovalButtonPhase.idle;

  static const Duration _removalSuccessDuration =
      Duration(milliseconds: 1050);

  bool get _destructiveActionBusy =>
      _removeSelectedPhase != NotificationRemovalButtonPhase.idle ||
      _nukeSectionPhase != NotificationRemovalButtonPhase.idle ||
      _removeAllPhase != NotificationRemovalButtonPhase.idle;

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
      _activitiesPollingPort = context.read<FaActivitiesPollingPort>();
      _activitiesController = NotificationActivitiesController(
        service,
        pollingService: _activitiesPollingPort,
      );
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
    appAnalytics.logScreen(
      AppScreens.notificationSection(
        _activitiesController.sections[_lastTabIndex].title,
      ),
    );
    _tabController!.addListener(() {
      if (!mounted) return;
      final idx = _tabController!.index;
      if (idx != _lastTabIndex) {
        _lastTabIndex = idx;
        _syncActiveNotificationSection();
        appAnalytics.logScreen(
          AppScreens.notificationSection(
            _activitiesController.sections[idx].title,
          ),
        );
        setState(() {});
      }
    });
    _previousSectionCount = sectionCount;
    setState(() {});
  }

  void _toggleSelectAll() {
    if (_destructiveActionBusy || _activitiesController.sections.isEmpty) {
      return;
    }
    final currentTabIndex = _tabController?.index ?? 0;
    if (currentTabIndex < 0 ||
        currentTabIndex >= _activitiesController.sections.length) {
      return;
    }
    if (_activitiesController.isShoutsSection(currentTabIndex)) {
      _shoutsSectionKey.currentState?.toggleSelectAll();
    } else {
      _activitiesController.toggleSelectAll(currentTabIndex);
    }
  }

  Future<void> _removeSelected() async {
    if (_destructiveActionBusy || _activitiesController.sections.isEmpty) {
      return;
    }
    final currentTabIndex = _tabController?.index ?? 0;
    if (currentTabIndex < 0 ||
        currentTabIndex >= _activitiesController.sections.length) {
      return;
    }

    setState(() {
      _removeSelectedPhase = NotificationRemovalButtonPhase.processing;
    });

    NotificationRemovalOutcome outcome;
    try {
      if (_activitiesController.isShoutsSection(currentTabIndex)) {
        final shoutsState = _shoutsSectionKey.currentState;
        outcome = shoutsState == null
            ? NotificationRemovalOutcome.failed
            : await shoutsState.removeSelected();
      } else {
        outcome =
            await _activitiesController.removeSelected(currentTabIndex);
      }
    } catch (_) {
      outcome = NotificationRemovalOutcome.failed;
    }

    if (!mounted) return;
    switch (outcome) {
      case NotificationRemovalOutcome.success:
        setState(() {
          _removeSelectedPhase = NotificationRemovalButtonPhase.success;
        });
        await Future<void>.delayed(_removalSuccessDuration);
        if (!mounted ||
            _removeSelectedPhase != NotificationRemovalButtonPhase.success) {
          return;
        }
        setState(() {
          _removeSelectedPhase = NotificationRemovalButtonPhase.idle;
        });
        return;
      case NotificationRemovalOutcome.nothingSelected:
        setState(() {
          _removeSelectedPhase = NotificationRemovalButtonPhase.idle;
        });
        _showRemovalMessage('Select at least one notification first.');
        return;
      case NotificationRemovalOutcome.failed:
        setState(() {
          _removeSelectedPhase = NotificationRemovalButtonPhase.idle;
        });
        _showRemovalMessage(
          'Could not remove the selected notifications. Please try again later.',
        );
        return;
      case NotificationRemovalOutcome.indeterminate:
        setState(() {
          _removeSelectedPhase = NotificationRemovalButtonPhase.idle;
        });
        _showRemovalMessage(
          'Could not confirm whether the selected notifications were removed. Refresh notifications before trying again.',
        );
        return;
    }
  }

  void _showRemovalMessage(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade700,
      ),
    );
  }

  Future<void> _nukeCurrentSection() async {
    if (_destructiveActionBusy || _activitiesController.sections.isEmpty) {
      return;
    }
    final currentTabIndex = _tabController?.index ?? 0;
    if (currentTabIndex < 0 ||
        currentTabIndex >= _activitiesController.sections.length) {
      return;
    }
    final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Confirm Nuke'),
            content: const Text(
                'Are you sure you want to nuke all items in this section?'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Cancel')),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('Confirm'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirm || !mounted) return;
    setState(() {
      _nukeSectionPhase = NotificationRemovalButtonPhase.processing;
    });

    NotificationRemovalOutcome outcome;
    try {
      if (_activitiesController.isShoutsSection(currentTabIndex)) {
        final shoutsState = _shoutsSectionKey.currentState;
        outcome = shoutsState == null
            ? NotificationRemovalOutcome.failed
            : await shoutsState.nukeSection();
      } else {
        outcome = await _activitiesController.nukeSection(currentTabIndex);
      }
    } catch (_) {
      outcome = NotificationRemovalOutcome.failed;
    }

    if (!mounted) return;
    switch (outcome) {
      case NotificationRemovalOutcome.success:
        setState(() {
          _nukeSectionPhase = NotificationRemovalButtonPhase.success;
        });
        await Future<void>.delayed(_removalSuccessDuration);
        if (!mounted ||
            _nukeSectionPhase != NotificationRemovalButtonPhase.success) {
          return;
        }
        setState(() {
          _nukeSectionPhase = NotificationRemovalButtonPhase.idle;
        });
        return;
      case NotificationRemovalOutcome.nothingSelected:
        setState(() {
          _nukeSectionPhase = NotificationRemovalButtonPhase.idle;
        });
        _showRemovalMessage('No notifications to remove.');
        return;
      case NotificationRemovalOutcome.failed:
        setState(() {
          _nukeSectionPhase = NotificationRemovalButtonPhase.idle;
        });
        _showRemovalMessage(
          'Could not remove the notifications in this section. Please try again later.',
        );
        return;
      case NotificationRemovalOutcome.indeterminate:
        setState(() {
          _nukeSectionPhase = NotificationRemovalButtonPhase.idle;
        });
        _showRemovalMessage(
          'Could not confirm whether the notifications in this section were removed. Refresh notifications before trying again.',
        );
        return;
    }
  }

  Future<void> _removeAllNotifications() async {
    if (_destructiveActionBusy) return;
    if (_activitiesController.sections.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No notifications to remove.')),
      );
      return;
    }
    final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Confirm'),
            content: const Text(
                'Are you sure you want to remove ALL notifications?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('Confirm'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirm || !mounted) return;
    setState(() {
      _removeAllPhase = NotificationRemovalButtonPhase.processing;
    });

    NotificationRemovalOutcome outcome;
    try {
      outcome = await _activitiesController.removeAll();
    } catch (_) {
      outcome = NotificationRemovalOutcome.failed;
    }

    if (!mounted) return;
    switch (outcome) {
      case NotificationRemovalOutcome.success:
        setState(() {
          _removeAllPhase = NotificationRemovalButtonPhase.success;
        });
        await Future<void>.delayed(_removalSuccessDuration);
        if (!mounted ||
            _removeAllPhase != NotificationRemovalButtonPhase.success) {
          return;
        }
        setState(() {
          _removeAllPhase = NotificationRemovalButtonPhase.idle;
        });
        return;
      case NotificationRemovalOutcome.nothingSelected:
        setState(() {
          _removeAllPhase = NotificationRemovalButtonPhase.idle;
        });
        _showRemovalMessage('No notifications to remove.');
        return;
      case NotificationRemovalOutcome.failed:
        setState(() {
          _removeAllPhase = NotificationRemovalButtonPhase.idle;
        });
        _showRemovalMessage(
          'Could not remove all notifications. Please try again later.',
        );
        return;
      case NotificationRemovalOutcome.indeterminate:
        setState(() {
          _removeAllPhase = NotificationRemovalButtonPhase.idle;
        });
        _showRemovalMessage(
          'Could not confirm whether all notifications were removed. Refresh notifications before trying again.',
        );
        return;
    }
  }

  Widget _buildRemoveAllButton() {
    return IconButton(
      icon: NotificationActionButtonContent(
        phase: _removeAllPhase,
        idleChild: const Icon(Icons.block, color: Color(0xFFE09321)),
      ),
      tooltip: 'Remove all notifications',
      onPressed: _destructiveActionBusy ? null : _removeAllNotifications,
    );
  }

  ButtonStyle _bulkActionButtonStyle(Color backgroundColor) {
    return ElevatedButton.styleFrom(
      backgroundColor: backgroundColor,
      disabledBackgroundColor: backgroundColor,
      foregroundColor: Colors.white,
      disabledForegroundColor: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
    );
  }

  Widget _buildBulkActionRow() {
    final actionsEnabled =
        !_destructiveActionBusy && _activitiesController.sections.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 0.0, vertical: 2.0),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton(
              onPressed: actionsEnabled ? _toggleSelectAll : null,
              style: _bulkActionButtonStyle(const Color(0xFF1F1F1F)),
              child: const FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.center,
                child: Text('Select All'),
              ),
            ),
          ),
          const SizedBox(width: 5),
          Expanded(
            child: ElevatedButton(
              onPressed: actionsEnabled ? _removeSelected : null,
              style: _bulkActionButtonStyle(const Color(0xFF1F1F1F)),
              child: NotificationRemovalButtonContent(
                phase: _removeSelectedPhase,
              ),
            ),
          ),
          const SizedBox(width: 5),
          Expanded(
            child: ElevatedButton(
              onPressed: actionsEnabled ? _nukeCurrentSection : null,
              style: _bulkActionButtonStyle(const Color(0xFFE09321)),
              child: NotificationActionButtonContent(
                phase: _nukeSectionPhase,
                idleChild: const Text('Nuke'),
                processingIndicatorColor: Colors.black,
              ),
            ),
          ),
        ],
      ),
    );
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
                  _buildRemoveAllButton(),
                  IconButton(
                    icon: const Icon(Icons.settings),
                    onPressed: () {
                      _showNotificationSettingsDialog();
                    },
                  ),
                ],
              ),
              body: Column(
                children: [
                  if (_removeSelectedPhase !=
                          NotificationRemovalButtonPhase.idle ||
                      _nukeSectionPhase !=
                          NotificationRemovalButtonPhase.idle)
                    _buildBulkActionRow(),
                  Expanded(
                    child: RefreshIndicator(
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
                              child:
                                  Center(child: Text('No notifications.'))),
                        ],
                      ),
                    ),
                  ),
                ],
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
              _buildRemoveAllButton(),
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
                    _buildBulkActionRow(),
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
                                  pollingService: _activitiesPollingPort,
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
