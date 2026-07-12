import 'package:FANotifier/features/notifications/data/fa_activities_polling_service.dart';
import 'package:FANotifier/features/notifications/data/fa_notification_service.dart';
import 'package:FANotifier/features/notifications/data/notification_shout_mapper.dart';
import 'package:FANotifier/features/notifications/domain/fa_notification_models.dart';
import 'package:FANotifier/features/notifications/domain/notification_section_kind.dart';

class NotificationShoutsCoordinator {
  const NotificationShoutsCoordinator(this._service);

  final FANotificationService _service;

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
    FaActivitiesPollingService().resetSchedule();
    final fetched = await FANotificationService.fetchMsgCenterShouts();
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

  Future<bool> removeSelected() async {
    final index = _shoutsSectionIndex();
    if (index == -1) return false;
    await _service.removeSelected(index);
    return true;
  }

  Future<bool> nukeSection() async {
    final index = _shoutsSectionIndex();
    if (index == -1) return false;
    await _service.nukeSection(index);
    return true;
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
