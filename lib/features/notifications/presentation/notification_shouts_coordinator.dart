import 'package:fanotifier/shared/fa/domain/fa_activities_polling_port.dart';
import 'package:fanotifier/features/notifications/domain/fa_notification_models.dart';
import 'package:fanotifier/features/notifications/domain/notification_section_kind.dart';
import 'package:fanotifier/features/notifications/domain/notification_shout_mapper.dart';
import 'package:fanotifier/features/notifications/presentation/fa_notification_service.dart';
import 'package:fanotifier/features/notifications/domain/notification_removal_outcome.dart';

class NotificationShoutsCoordinator {
  const NotificationShoutsCoordinator(
    this._service,
    this._pollingService,
  );

  final FANotificationService _service;
  final FaActivitiesPollingPort _pollingService;

  List<Shout> currentShouts() {
    return deduplicateNotificationShouts(
      notificationShoutsFromSections(_service.sections),
    );
  }

  bool hasShoutListChanged(List<Shout>? previous, List<Shout> next) {
    return previous == null ||
        previous.length != next.length ||
        (previous.isNotEmpty &&
            next.isNotEmpty &&
            previous.first.id != next.first.id);
  }

  Future<List<Shout>> refresh() async {
    _pollingService.resetSchedule();
    final fetched = await _service.fetchMsgCenterShouts();
    return deduplicateNotificationShouts(fetched);
  }

  void commitRefreshedShouts(List<Shout> shouts) {
    _service.updateShouts(shouts);
  }

  bool toggleSelectAll(List<Shout> localShouts) {
    final index = _shoutsSectionIndex();
    if (index == -1) return false;
    _service.toggleSelectAll(index);
    final items = _service.sections[index].items;
    for (final shout in localShouts) {
      try {
        shout.isChecked =
            items.firstWhere((item) => item.id == shout.id).isChecked;
      } catch (_) {}
    }
    return true;
  }

  Future<NotificationRemovalOutcome> removeSelected() {
    final index = _shoutsSectionIndex();
    if (index == -1) {
      return Future.value(NotificationRemovalOutcome.nothingSelected);
    }
    return _service.removeSelected(index);
  }

  Future<NotificationRemovalOutcome> nukeSection() {
    final index = _shoutsSectionIndex();
    if (index == -1) {
      return Future.value(NotificationRemovalOutcome.nothingSelected);
    }
    return _service.nukeSection(index);
  }

  void setChecked(String id, bool isChecked) {
    _service.setShoutCheckedById(id, isChecked);
  }

  int _shoutsSectionIndex() {
    return _service.sections.indexWhere(
      (section) => isShoutsNotificationSectionTitle(section.title),
    );
  }
}
