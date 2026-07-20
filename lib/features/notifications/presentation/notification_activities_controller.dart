import 'package:fanotifier/shared/fa/domain/fa_activities_polling_port.dart';
import 'package:fanotifier/features/notifications/presentation/fa_notification_service.dart';
import 'package:fanotifier/features/notifications/domain/fa_notification_models.dart';
import 'package:fanotifier/features/notifications/domain/notification_section_kind.dart';
import 'package:fanotifier/features/notifications/presentation/notification_tab_badge_value.dart';

class NotificationActivitiesController {
  NotificationActivitiesController(
    this._service, {
    required FaActivitiesPollingPort pollingService,
  }) : _pollingService = pollingService;

  FANotificationService _service;
  final FaActivitiesPollingPort _pollingService;
  bool _didAutoRefetch = false;

  bool get hasFetched => _service.hasFetched;
  List<NotificationSection> get sections => _service.sections;
  bool get showInitialLoading => !hasFetched && sections.isEmpty;
  String? get currentUsernameFromLink => _service.currentUsernameFromLink;

  void updateService(FANotificationService service) {
    _service = service;
  }

  Future<void> loadOnFirstOpen() async {
    if (hasFetched) return;
    await _pollingService.triggerNow(
      resetTimer: false,
      source: 'notifications_first_open',
    );
  }

  Future<void> refresh({required String source}) {
    return _pollingService.triggerNow(
      resetTimer: true,
      source: source,
    );
  }

  void triggerEmptyAutoRefresh() {
    if (_didAutoRefetch) return;
    _didAutoRefetch = true;
    _pollingService.triggerNow(
      resetTimer: false,
      source: 'notifications_empty_autorefresh',
    );
  }

  int initialTabIndex(String? initialSection) {
    if (initialSection == null) return 0;
    final index = notificationSectionIndexForInitialTitle(
      sections.map((section) => section.title),
      initialSection,
    );
    return index == -1 ? 0 : index;
  }

  String? sectionTitleAt(int? index) {
    if (index == null || sections.isEmpty) return null;
    if (index < 0 || index >= sections.length) return null;
    return sections[index].title;
  }

  bool isShoutsSection(int index) {
    return isShoutsNotificationSectionTitle(sections[index].title);
  }

  NotificationTabBadgeValue badgeValueFor(NotificationSection section) {
    return notificationTabBadgeValue(
      sectionTitle: section.title,
      itemCount: section.items.length,
      messageBarCounts: _service.messageBarCounts,
    );
  }

  void setScreenVisible(bool isVisible, {int? activeIndex}) {
    _pollingService.setNotificationsScreenVisible(
      isVisible,
      activeSectionTitle: sectionTitleAt(activeIndex),
    );
  }

  void setActiveSection(int? index) {
    _pollingService.setNotificationsScreenActiveSection(sectionTitleAt(index));
  }

  void setItemChecked(NotificationItem item, bool checked) {
    _service.setItemChecked(item, checked);
  }

  void toggleSelectAll(int sectionIndex) {
    _service.toggleSelectAll(sectionIndex);
  }

  Future<void> removeSelected(int sectionIndex) {
    return _service.removeSelected(sectionIndex);
  }

  Future<void> nukeSection(int sectionIndex) async {
    await _service.nukeSection(sectionIndex);
    await _service.fetchNotifications();
  }

  Future<void> removeAll() {
    return _service.removeAllNotifications();
  }
}
