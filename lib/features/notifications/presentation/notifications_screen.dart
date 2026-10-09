import 'package:fanotifier/shared/widgets/fa_session_recovery_scope.dart';
import 'dart:async';
import 'package:flutter/foundation.dart' show ValueListenable, listEquals;
import 'package:fanotifier/app/navigation/app_navigation.dart';
import 'package:fanotifier/core/logging/fa_ads_logging.dart';
import 'package:fanotifier/features/ads/domain/fa_ad_models.dart';
import 'package:fanotifier/features/ads/domain/fa_ads_repository.dart';
import 'package:fanotifier/features/ads/presentation/fa_ad_panel.dart';
import 'package:fanotifier/features/ads/presentation/fa_ad_panel_controller.dart';
import 'package:fanotifier/features/ads/presentation/fa_ad_section_controller.dart';
import 'package:fanotifier/shared/navigation/fa_link_handler.dart';
import 'package:fanotifier/features/drawer/presentation/home_drawer_shell.dart';
import 'package:fanotifier/features/notifications/presentation/fa_notifications_controller.dart';
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
import 'package:fanotifier/shared/widgets/scroll_return_controller.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:visibility_detector/visibility_detector.dart';

class NotificationsScreen extends StatefulWidget {
  final String? initialSection;
  final GlobalKey<HomeDrawerShellState> drawerKey;
  final ScrollReturnActionPort? scrollActionPort;
  final bool isActive;
  final bool sfwEnabled;
  final ValueListenable<bool> sessionClosing;

  const NotificationsScreen({
    super.key,
    required this.drawerKey,
    required this.isActive,
    required this.sfwEnabled,
    required this.sessionClosing,
    this.initialSection,
    this.scrollActionPort,
  });

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen>
    with TickerProviderStateMixin, RouteAware, WidgetsBindingObserver {
  TabController? _tabController;
  int _initialTabIndex = 0;
  bool _isDraggingFromEdge = false;
  List<String> _tabSectionTitles = const [];
  bool _tabSynchronizationScheduled = false;
  int _lastTabIndex = -1;
  late NotificationActivitiesController _activitiesController;
  late FaActivitiesPollingPort _activitiesPollingPort;
  bool _activitiesControllerInitialized = false;
  late final FaAdPanelController _ads;
  final GlobalKey _adViewportKey = GlobalKey();
  FaNotificationsController? _notificationsService;
  ModalRoute<dynamic>? _route;
  int _lastAdPageRevision = -1;
  int _adConfigurationPageRevision = -1;
  int _adRenewalPageRevision = -1;
  bool _adsSyncScheduled = false;
  bool _renewAdsPending = false;
  bool _routeVisible = true;
  bool _screenVisible = false;
  bool _appResumed = true;
  bool _contentExcursion = false;
  bool _adExcursion = false;
  bool _adHandoff = false;
  bool _adTapPending = false;
  VoidCallback? _pendingRemovalAdRenewal;
  final Map<String, ScrollReturnController> _scrollReturns = {};
  final List<ScrollReturnController> _retiredScrollReturns = [];
  String? _removalSectionTitle;
  bool _confirmationPending = false;
  int _nextRemoval = 0;
  int _actionSessionGeneration = 0;
  NotificationRemovalButtonPhase _removeSelectedPhase =
      NotificationRemovalButtonPhase.idle;
  NotificationRemovalButtonPhase _nukeSectionPhase =
      NotificationRemovalButtonPhase.idle;
  NotificationRemovalButtonPhase _removeAllPhase =
      NotificationRemovalButtonPhase.idle;

  static const Duration _removalSuccessDuration =
      Duration(milliseconds: 1050);

  bool get _destructiveActionBusy =>
      _confirmationPending ||
      _removeSelectedPhase != NotificationRemovalButtonPhase.idle ||
      _nukeSectionPhase != NotificationRemovalButtonPhase.idle ||
      _removeAllPhase != NotificationRemovalButtonPhase.idle;

  final GlobalKey<ShoutsSectionWidgetState> _shoutsSectionKey =
      GlobalKey<ShoutsSectionWidgetState>();

  @override
  void initState() {
    super.initState();
    _ads = FaAdPanelController(
      repository: context.read<FaAdsRepository>(),
      placements: const {FaAdPlacement.headerMiddle},
    );
    widget.sessionClosing.addListener(_sessionClosingChanged);
    _appResumed = WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    widget.scrollActionPort?.bind(_scrollFromNavigation, _cancelNavigationScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_loadOnFirstOpen());
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final service = Provider.of<FaNotificationsController>(context, listen: false);
    if (!identical(service, _notificationsService)) {
      _notificationsService?.removeListener(_onNotificationsChanged);
      _notificationsService = service;
      _lastAdPageRevision = -1;
      _adConfigurationPageRevision = -1;
      _adRenewalPageRevision = -1;
      service.addListener(_onNotificationsChanged);
    }
    if (!_activitiesControllerInitialized) {
      _activitiesPollingPort = context.read<FaActivitiesPollingPort>();
      _activitiesController = NotificationActivitiesController(
        service,
        pollingService: _activitiesPollingPort,
        onRefreshed: _onScreenRefreshed,
      );
      _activitiesControllerInitialized = true;
    }
    final route = ModalRoute.of(context);
    if (route != _route) {
      if (_route != null) routeObserver.unsubscribe(this);
      _route = route;
      if (route != null) {
        routeObserver.subscribe(this, route);
        _routeVisible = route.isCurrent;
      }
    }
    _updateAdActivity();
    _scheduleAdsSynchronization();
  }

  @override
  void didUpdateWidget(covariant NotificationsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sessionClosing != widget.sessionClosing) {
      oldWidget.sessionClosing.removeListener(_sessionClosingChanged);
      widget.sessionClosing.addListener(_sessionClosingChanged);
      _sessionClosingChanged();
    }
    if (oldWidget.scrollActionPort != widget.scrollActionPort) {
      oldWidget.scrollActionPort?.unbind(_scrollFromNavigation);
      widget.scrollActionPort?.bind(_scrollFromNavigation, _cancelNavigationScroll);
    }
    if (oldWidget.sfwEnabled != widget.sfwEnabled) {
      _ads.clear();
      _scheduleAdsSynchronization();
      unawaited(_ensurePageMode(force: true));
    } else if (!oldWidget.isActive && widget.isActive) {
      unawaited(_ensurePageMode());
    }
    _updateAdActivity();
  }

  @override
  void dispose() {
    _pendingRemovalAdRenewal = null;
    widget.sessionClosing.removeListener(_sessionClosingChanged);
    _notificationsService?.removeListener(_onNotificationsChanged);
    routeObserver.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    _ads.dispose();
    widget.scrollActionPort?.unbind(_scrollFromNavigation);
    for (final scrollReturn in [..._scrollReturns.values, ..._retiredScrollReturns]) {
      scrollReturn.dispose();
      scrollReturn.scrollController.dispose();
    }
    _scrollReturns.clear();
    _retiredScrollReturns.clear();
    _tabController?.dispose();
    _activitiesController.setScreenVisible(false);
    super.dispose();
  }

  Future<void> _loadOnFirstOpen() async {
    await _activitiesController.loadOnFirstOpen();
    if (!mounted) return;
    await _ensurePageMode();
    _scheduleAdsSynchronization();
  }

  Future<void> _ensurePageMode({bool force = false}) async {
    if (!mounted || !widget.isActive || widget.sessionClosing.value) return;
    final service = _notificationsService;
    if (service == null || service.documentSfwEnabled == widget.sfwEnabled) return;
    if (!force &&
        (service.documentSfwEnabled == null ||
            service.isLoading ||
            service.errorMessage != null)) {
      return;
    }
    await service.fetchNotifications(sfwEnabled: widget.sfwEnabled);
    if (mounted) _scheduleAdsSynchronization();
  }

  void _onNotificationsChanged() {
    final service = _notificationsService;
    if (!mounted ||
        service == null ||
        _lastAdPageRevision == service.adPageRevision) {
      return;
    }
    _lastAdPageRevision = service.adPageRevision;
    if (service.adPageMetadata == null) _ads.clear();
    _scheduleAdsSynchronization();
  }

  void _scheduleAdsSynchronization({bool renew = false}) {
    _renewAdsPending = _renewAdsPending || renew;
    if (_adsSyncScheduled || !mounted) return;
    _adsSyncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _adsSyncScheduled = false;
      if (!mounted) return;
      if (widget.sessionClosing.value) {
        _renewAdsPending = false;
        _ads.clear();
        return;
      }
      final service = _notificationsService;
      final renew = _renewAdsPending;
      _renewAdsPending = false;
      final previous = _ads.section;
      _ads.synchronize(
        page: service?.adPageMetadata,
        viewportWidth: MediaQuery.sizeOf(context).width,
        sfwEnabled: widget.sfwEnabled,
        renew: renew,
      );
      if (!identical(previous, _ads.section) && _ads.section != null) {
        _adConfigurationPageRevision = service?.adPageRevision ?? -1;
      }
      unawaited(_ensurePageMode());
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  Future<void> _onScreenRefreshed(int previousPageRevision) async {
    final service = _notificationsService;
    if (!mounted ||
        service?.errorMessage != null ||
        service?.documentSfwEnabled != widget.sfwEnabled) {
      return;
    }
    if (service == null || _adRenewalPageRevision == service.adPageRevision) return;
    _adRenewalPageRevision = service.adPageRevision;
    final renew = _adConfigurationPageRevision <= previousPageRevision;
    _scheduleAdsSynchronization(renew: renew);
    FaAdsLog.event(FaAdsLogCategory.lifecycle, 'notifications_screen_refreshed',
        checks: {'adRenewalRequested': renew, 'fromBackgroundPolling': false,
          'freshConfigurationAlreadyCreated': !renew});
  }

  _NotificationRemovalAdContext _captureRemovalAdContext() {
    final section = _ads.section;
    return _NotificationRemovalAdContext(
      number: ++_nextRemoval,
      service: _notificationsService,
      section: section,
      delivery: section?.deliveryGeneration,
      pageRevision: _notificationsService?.adPageRevision ?? -1,
      sfwEnabled: widget.sfwEnabled,
      sessionGeneration: _actionSessionGeneration,
    );
  }

  void _renewAdAfterRemoval(
    _NotificationRemovalAdContext previous,
    _NotificationRemovalAction action,
  ) {
    final service = _notificationsService;
    if (!mounted ||
        widget.sessionClosing.value ||
        previous.sessionGeneration != _actionSessionGeneration ||
        !identical(service, previous.service) ||
        service?.errorMessage != null ||
        widget.sfwEnabled != previous.sfwEnabled ||
        service?.documentSfwEnabled != widget.sfwEnabled) {
      return;
    }
    if (_adTapPending) {
      _pendingRemovalAdRenewal = () => _renewAdAfterRemoval(previous, action);
      return;
    }
    final section = _ads.section;
    final freshDelivery = !identical(section, previous.section) ||
        section?.deliveryGeneration != previous.delivery ||
        _adConfigurationPageRevision > previous.pageRevision;
    _scheduleAdsSynchronization(renew: !freshDelivery);
    FaAdsLog.event(
      FaAdsLogCategory.lifecycle,
      'notifications_removal_succeeded',
      section: section?.sectionNumber,
      delivery: section?.deliveryGeneration,
      counts: {'operation': previous.number},
      checks: {
        'removeSelected': action == _NotificationRemovalAction.selected,
        'sectionNuke': action == _NotificationRemovalAction.section,
        'allNuke': action == _NotificationRemovalAction.all,
        'adRenewalRequested': !freshDelivery,
        'freshDeliveryAlreadyCreated': freshDelivery,
      },
    );
  }

  void _contentOpened() => _contentExcursion = true;

  @override
  void didPushNext() {
    _routeVisible = false;
    _updateAdActivity();
  }

  @override
  void didPopNext() {
    _routeVisible = true;
    _adHandoff = false;
    if (_contentExcursion && !_adExcursion) {
      _scheduleAdsSynchronization(renew: true);
      FaAdsLog.event(FaAdsLogCategory.lifecycle, 'notifications_content_return',
          checks: {'adRenewalRequested': true});
    } else if (_adExcursion) {
      FaAdsLog.event(FaAdsLogCategory.lifecycle, 'notifications_ad_return_retained',
          checks: {'deliveryRetained': true, 'repeatImpression': false});
    }
    _contentExcursion = false;
    _adExcursion = false;
    _updateAdActivity();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appResumed = state == AppLifecycleState.resumed;
    if (_appResumed && _adHandoff && _routeVisible) {
      _adHandoff = false;
      _adExcursion = false;
      FaAdsLog.event(FaAdsLogCategory.lifecycle, 'notifications_ad_return_retained',
          checks: {'deliveryRetained': true, 'repeatImpression': false});
    }
    _updateAdActivity();
  }

  void _sessionClosingChanged() {
    if (widget.sessionClosing.value) {
      _actionSessionGeneration++;
      _pendingRemovalAdRenewal = null;
      _ads.setActive(false);
      _ads.clear();
      _renewAdsPending = false;
    } else {
      _scheduleAdsSynchronization();
    }
    _updateAdActivity();
  }

  void _updateAdActivity() => _ads.setActive(!widget.sessionClosing.value && widget.isActive &&
      _screenVisible && _routeVisible && _appResumed && !_adHandoff);

  Future<void> _openAd(FaAdSectionController section, FaAdSlotController slot) async {
    if (_adTapPending || !_ads.active.value || !identical(_ads.section, section)) return;
    _adTapPending = true;
    try {
      final destination = await section.click(slot);
      if (destination == null ||
          !mounted ||
          !_ads.active.value ||
          !identical(_ads.section, section)) {
        return;
      }
      _contentExcursion = false;
      _adExcursion = true;
      _adHandoff = true;
      _updateAdActivity();
      final disposition = await handleFAAdDestination(context, destination);
      if (!mounted) return;
      FaAdsLog.event(FaAdsLogCategory.click, 'destination_handed_off',
          section: section.sectionNumber, slot: slot.definition.placement.name,
          checks: {'internal': disposition == FaAdLinkDisposition.internal,
            'external': disposition == FaAdLinkDisposition.external,
            'opened': disposition != FaAdLinkDisposition.failed,
            'confirmationSkippedForAd': true, 'trackingUrlOpenedTwice': false});
      if (disposition == FaAdLinkDisposition.failed ||
          (disposition == FaAdLinkDisposition.external && _appResumed && _routeVisible)) {
        _adHandoff = false;
        _adExcursion = false;
        _updateAdActivity();
      }
    } catch (_) {
      if (!mounted) return;
      _adHandoff = false;
      _adExcursion = false;
      _updateAdActivity();
      FaAdsLog.event(FaAdsLogCategory.click, 'handoff_failed');
    } finally {
      _adTapPending = false;
      final pendingRenewal = _pendingRemovalAdRenewal;
      _pendingRemovalAdRenewal = null;
      pendingRenewal?.call();
    }
  }

  PreferredSizeWidget? _buildAdHeader({TabBar? tabs}) {
    const dividerHeight = 4.0;
    const tabSpacingHeight = 3.4;
    final panel = FaAdPanel(
      controller: _ads,
      viewportKey: _adViewportKey,
      fillAvailableWidth: true,
      onTap: _openAd,
    );
    final adHeight = panel.heightFor(MediaQuery.sizeOf(context).width);
    if (adHeight == 0 && tabs == null) return null;
    final height = dividerHeight +
        (tabs == null ? 0 : tabSpacingHeight + tabs.preferredSize.height);
    return PreferredSize(
      preferredSize: Size.fromHeight(adHeight + height),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          panel,
          const Divider(
            height: dividerHeight,
            thickness: 4,
            color: Color(0xFF111111),
          ),
          if (tabs != null) ...[
            const Divider(
              height: tabSpacingHeight,
              thickness: 4,
              color: Colors.black,
            ),
            Container(
              decoration: const BoxDecoration(color: Color(0xFF111111)),
              child: tabs,
            ),
          ],
        ],
      ),
    );
  }

  void _syncActiveNotificationSection() {
    _activitiesController.setActiveSection(_selectedSectionIndex);
  }

  String? get _selectedSectionTitle {
    final index = _tabController?.index;
    if (index == null || index < 0 || index >= _tabSectionTitles.length) {
      return null;
    }
    return _tabSectionTitles[index];
  }

  int? get _selectedSectionIndex {
    final title = _selectedSectionTitle;
    if (title == null) return null;
    final index = _activitiesController.sections.indexWhere(
      (section) => section.title == title,
    );
    return index < 0 ? null : index;
  }

  int? _activeSectionIndex(String sectionTitle, {bool requireSettled = true}) {
    final tabs = _tabController;
    if (!mounted ||
        !widget.isActive ||
        widget.sessionClosing.value ||
        !_routeVisible ||
        !_appResumed ||
        tabs == null ||
        (requireSettled &&
            (tabs.indexIsChanging || tabs.offset.abs() > 0.001)) ||
        _selectedSectionTitle != sectionTitle ||
        !listEquals(
          _tabSectionTitles,
          _activitiesController.sections.map((section) => section.title).toList(),
        )) {
      return null;
    }
    return _selectedSectionIndex;
  }

  ScrollReturnController? get _currentScrollReturn {
    if (!_activitiesControllerInitialized) return null;
    final title = _selectedSectionTitle;
    return title == null ? null : _scrollReturns[title];
  }

  void _synchronizeScrollReturns() {
    final sections = _activitiesController.sections;
    final titles = sections.map((section) => section.title).toSet();
    for (final title in _scrollReturns.keys.toList(growable: false)) {
      if (titles.contains(title)) continue;
      final scrollReturn = _scrollReturns.remove(title)!;
      scrollReturn.reset();
      _retiredScrollReturns.add(scrollReturn);
    }
    if (_retiredScrollReturns.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final retired = _retiredScrollReturns.toList(growable: false);
        _retiredScrollReturns.clear();
        for (final scrollReturn in retired) {
          scrollReturn.dispose();
          scrollReturn.scrollController.dispose();
        }
      });
    }
    for (final section in sections) {
      final scrollReturn = _scrollReturns.putIfAbsent(
        section.title,
        () => ScrollReturnController(scrollController: ScrollController()),
      );
      if (!isShoutsNotificationSectionTitle(section.title)) {
        scrollReturn.updateContent(section.items.map((item) => item.id));
      }
    }
  }

  Future<void> _scrollFromNavigation(
    ValueChanged<ScrollReturnDirection> onStarted,
  ) async {
    final tabs = _tabController;
    if (tabs == null || tabs.indexIsChanging || tabs.offset.abs() > 0.001) return;
    await _currentScrollReturn?.perform(
      onStarted: onStarted,
      animate: !MediaQuery.disableAnimationsOf(context),
    );
  }

  void _cancelNavigationScroll() {
    for (final scrollReturn in _scrollReturns.values) {
      scrollReturn.cancelMovement();
    }
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

  void _scheduleTabSynchronization() {
    final titles = _activitiesController.sections
        .map((section) => section.title)
        .toList(growable: false);
    if (_tabSynchronizationScheduled || listEquals(titles, _tabSectionTitles)) {
      return;
    }
    _tabSynchronizationScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tabSynchronizationScheduled = false;
      if (!mounted) return;
      _initializeTabController();
    });
  }

  void _initializeTabController() {
    _cancelNavigationScroll();
    final previousTitle = _selectedSectionTitle;
    final previousIndex = _tabController?.index ?? 0;
    final titles = _activitiesController.sections
        .map((section) => section.title)
        .toList(growable: false);
    _tabController?.dispose();
    _tabController = null;
    _tabSectionTitles = titles;
    if (titles.isEmpty) {
      _lastTabIndex = -1;
      _syncActiveNotificationSection();
      setState(() {});
      return;
    }
    final retainedIndex = titles.indexOf(previousTitle ?? '');
    _initialTabIndex = retainedIndex >= 0
        ? retainedIndex
        : previousTitle == null
            ? _activitiesController.initialTabIndex(widget.initialSection)
            : previousIndex.clamp(0, titles.length - 1).toInt();
    _tabController = TabController(
        length: titles.length, vsync: this, initialIndex: _initialTabIndex);
    _lastTabIndex = _tabController!.index;
    _syncActiveNotificationSection();
    appAnalytics.logScreen(
      AppScreens.notificationSection(titles[_lastTabIndex]),
    );
    _tabController!.addListener(_onTabChanged);
    setState(() {});
  }

  void _onTabChanged() {
    if (!mounted || _tabController == null) return;
    final titles = _activitiesController.sections
        .map((section) => section.title)
        .toList(growable: false);
    if (!listEquals(titles, _tabSectionTitles)) {
      _scheduleTabSynchronization();
      return;
    }
    final index = _tabController!.index;
    if (index != _lastTabIndex) {
      _cancelNavigationScroll();
      _lastTabIndex = index;
      _syncActiveNotificationSection();
      appAnalytics.logScreen(AppScreens.notificationSection(titles[index]));
    }
    setState(() {});
  }

  void _toggleSelectAll(String sectionTitle) {
    if (_destructiveActionBusy || _activitiesController.sections.isEmpty) {
      return;
    }
    final currentTabIndex = _activeSectionIndex(sectionTitle);
    if (currentTabIndex == null) return;
    if (_activitiesController.isShoutsSection(currentTabIndex)) {
      _shoutsSectionKey.currentState?.toggleSelectAll();
    } else {
      _activitiesController.toggleSelectAll(currentTabIndex);
    }
  }

  Future<void> _removeSelected(String sectionTitle) async {
    if (_destructiveActionBusy || _activitiesController.sections.isEmpty) {
      return;
    }
    final currentTabIndex = _activeSectionIndex(sectionTitle);
    if (currentTabIndex == null) return;
    final adContext = _captureRemovalAdContext();

    setState(() {
      _removalSectionTitle = sectionTitle;
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
        _renewAdAfterRemoval(adContext, _NotificationRemovalAction.selected);
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
          _removalSectionTitle = null;
        });
        return;
      case NotificationRemovalOutcome.nothingSelected:
        setState(() {
          _removeSelectedPhase = NotificationRemovalButtonPhase.idle;
          _removalSectionTitle = null;
        });
        _showRemovalMessage('Select at least one notification first.');
        return;
      case NotificationRemovalOutcome.failed:
        setState(() {
          _removeSelectedPhase = NotificationRemovalButtonPhase.idle;
          _removalSectionTitle = null;
        });
        _showRemovalMessage(
          'Could not remove the selected notifications. Please try again later.',
        );
        return;
      case NotificationRemovalOutcome.indeterminate:
        setState(() {
          _removeSelectedPhase = NotificationRemovalButtonPhase.idle;
          _removalSectionTitle = null;
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

  Future<bool> _confirmRemoval({
    required String title,
    required String message,
  }) async {
    final sessionGeneration = _actionSessionGeneration;
    setState(() {
      _confirmationPending = true;
    });
    try {
      final confirmed = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text(title),
              content: Text(message),
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
      return confirmed && sessionGeneration == _actionSessionGeneration;
    } finally {
      if (mounted) {
        setState(() {
          _confirmationPending = false;
        });
      }
    }
  }

  Future<void> _nukeCurrentSection(String sectionTitle) async {
    if (_destructiveActionBusy || _activitiesController.sections.isEmpty) {
      return;
    }
    if (_activeSectionIndex(sectionTitle) == null) return;
    final confirm = await _confirmRemoval(
      title: 'Confirm Nuke',
      message: 'Are you sure you want to nuke all items in this section?',
    );
    if (!confirm || !mounted || _destructiveActionBusy) return;
    final currentTabIndex = _activeSectionIndex(sectionTitle);
    if (currentTabIndex == null) return;
    final adContext = _captureRemovalAdContext();
    setState(() {
      _removalSectionTitle = sectionTitle;
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
        _renewAdAfterRemoval(adContext, _NotificationRemovalAction.section);
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
          _removalSectionTitle = null;
        });
        return;
      case NotificationRemovalOutcome.nothingSelected:
        setState(() {
          _nukeSectionPhase = NotificationRemovalButtonPhase.idle;
          _removalSectionTitle = null;
        });
        _showRemovalMessage('No notifications to remove.');
        return;
      case NotificationRemovalOutcome.failed:
        setState(() {
          _nukeSectionPhase = NotificationRemovalButtonPhase.idle;
          _removalSectionTitle = null;
        });
        _showRemovalMessage(
          'Could not remove the notifications in this section. Please try again later.',
        );
        return;
      case NotificationRemovalOutcome.indeterminate:
        setState(() {
          _nukeSectionPhase = NotificationRemovalButtonPhase.idle;
          _removalSectionTitle = null;
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
    final confirm = await _confirmRemoval(
      title: 'Confirm',
      message: 'Are you sure you want to remove ALL notifications?',
    );
    if (!confirm ||
        !mounted ||
        _destructiveActionBusy ||
        !widget.isActive ||
        widget.sessionClosing.value ||
        !_routeVisible ||
        !_appResumed) {
      return;
    }
    final adContext = _captureRemovalAdContext();
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
        _renewAdAfterRemoval(adContext, _NotificationRemovalAction.all);
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

  Widget _buildBulkActionRow({required String sectionTitle}) {
    final actionsEnabled = !_destructiveActionBusy &&
        _activeSectionIndex(sectionTitle, requireSettled: false) != null;
    final ownsAction = sectionTitle == _removalSectionTitle;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 0.0, vertical: 2.0),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton(
              onPressed: actionsEnabled
                  ? () => _toggleSelectAll(sectionTitle)
                  : null,
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
              onPressed: actionsEnabled
                  ? () => _removeSelected(sectionTitle)
                  : null,
              style: _bulkActionButtonStyle(const Color(0xFF1F1F1F)),
              child: NotificationRemovalButtonContent(
                phase: ownsAction
                    ? _removeSelectedPhase
                    : NotificationRemovalButtonPhase.idle,
              ),
            ),
          ),
          const SizedBox(width: 5),
          Expanded(
            child: ElevatedButton(
              onPressed: actionsEnabled
                  ? () => _nukeCurrentSection(sectionTitle)
                  : null,
              style: _bulkActionButtonStyle(const Color(0xFFE09321)),
              child: NotificationActionButtonContent(
                phase: ownsAction
                    ? _nukeSectionPhase
                    : NotificationRemovalButtonPhase.idle,
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
    return FaSessionRecoveryScope(
      needsRecovery: () => context.read<FaNotificationsController>().errorMessage != null,
      isBusy: () => context.read<FaNotificationsController>().isLoading || _destructiveActionBusy,
      onRecover: () => _activitiesController.refresh(source: 'cloudflare_recovery'),
      child: SizedBox(
        key: _adViewportKey,
        child: ListenableBuilder(
          listenable: _ads,
          builder: (context, _) => _buildContent(context),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    return VisibilityDetector(
      key: const Key('notifications_screen_visibility'),
      onVisibilityChanged: (info) {
        _screenVisible = info.visibleFraction > 0.01;
        _updateAdActivity();
        if (info.visibleFraction <= 0.01) _cancelNavigationScroll();
        _activitiesController.setScreenVisible(
          info.visibleFraction > 0.01,
          activeIndex: _selectedSectionIndex,
        );
      },
      child: Consumer<FaNotificationsController>(
        builder: (context, service, child) {
          _activitiesController.updateService(service);
          _synchronizeScrollReturns();
          final sections = _activitiesController.sections;
          _scheduleTabSynchronization();
          final showInitialLoading =
              _activitiesController.showInitialLoading;
          if (showInitialLoading) {
            return Scaffold(
              appBar: AppBar(
                bottom: _buildAdHeader(),
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
              if (!mounted) {
                return;
              }
              _activitiesController.triggerEmptyAutoRefresh();
            });
            return Scaffold(
              appBar: AppBar(
                bottom: _buildAdHeader(),
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
                    _buildBulkActionRow(sectionTitle: _removalSectionTitle ?? ''),
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
          if (_tabController == null ||
              !listEquals(
                _tabSectionTitles,
                sections.map((section) => section.title).toList(),
              )) {
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
            bottom: _buildAdHeader(
              tabs: TabBar(
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
                    Expanded(
                      child: NotificationListener<ScrollNotification>(
                        onNotification: (ScrollNotification notification) {
                          if (notification.metrics.axis == Axis.horizontal &&
                              notification is ScrollStartNotification &&
                              notification.dragDetails != null) {
                            _cancelNavigationScroll();
                          }
                          _currentScrollReturn?.handleScrollNotification(notification);
                          if (notification is OverscrollNotification &&
                              _tabController?.index == 0 &&
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
                                  scrollReturn: _scrollReturns[section.title]!,
                                  actions: _buildBulkActionRow(
                                    sectionTitle: section.title,
                                  ),
                                  service: service,
                                  pollingService: _activitiesPollingPort,
                                  onRefreshed: _onScreenRefreshed,
                                  onContentOpened: _contentOpened,
                                  isActive:
                                      (_tabController?.index ?? 0) == index,
                                );
                              } else {
                                return NotificationSectionWidget(
                                  key: ValueKey('notification-${section.title}'),
                                  sectionIndex: index,
                                  scrollReturn: _scrollReturns[section.title]!,
                                  actions: _buildBulkActionRow(
                                    sectionTitle: section.title,
                                  ),
                                  controller: _activitiesController,
                                  onContentOpened: _contentOpened,
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
                width: 25,
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
                  child: const SizedBox.expand(),
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

enum _NotificationRemovalAction { selected, section, all }

class _NotificationRemovalAdContext {
  const _NotificationRemovalAdContext({
    required this.number,
    required this.service,
    required this.section,
    required this.delivery,
    required this.pageRevision,
    required this.sfwEnabled,
    required this.sessionGeneration,
  });

  final int number;
  final FaNotificationsController? service;
  final FaAdSectionController? section;
  final int? delivery;
  final int pageRevision;
  final bool sfwEnabled;
  final int sessionGeneration;
}
