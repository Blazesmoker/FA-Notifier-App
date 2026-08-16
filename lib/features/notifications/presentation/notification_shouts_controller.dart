import 'package:flutter/foundation.dart';
import 'package:fanotifier/features/notifications/presentation/fa_notification_service.dart';
import 'package:fanotifier/shared/fa/domain/fa_activities_polling_port.dart';
import 'package:fanotifier/features/notifications/domain/fa_notification_models.dart';
import 'package:fanotifier/features/notifications/domain/notification_shout_mapper.dart';
import 'package:fanotifier/features/notifications/presentation/notification_shouts_coordinator.dart';

class NotificationShoutsController extends ChangeNotifier {
  NotificationShoutsController(
    this._service,
    FaActivitiesPollingPort pollingService,
  )
      : _coordinator = NotificationShoutsCoordinator(
          _service,
          pollingService,
        ) {
    final cached = _coordinator.currentShouts();
    _shouts = cached;
    _shoutsFuture = Future.value(cached);
  }

  final FANotificationService _service;
  final NotificationShoutsCoordinator _coordinator;

  late Future<List<Shout>> _shoutsFuture;
  List<Shout>? _shouts;
  bool _isActive = false;
  bool _isEnriching = false;
  bool _serviceListenerAttached = false;
  bool _disposed = false;
  String? _enrichRequestedForSignature;
  String? _autoEnrichScheduledForSignature;

  Future<List<Shout>> get shoutsFuture => _shoutsFuture;
  bool get isEnriching => _isEnriching;
  String get lightSignature => _service.shoutsLightSignature;

  bool get shouldBlockLightView {
    final signature = lightSignature;
    return _service.shoutsNeedEnrich &&
        !_isEnriching &&
        signature.isNotEmpty &&
        _enrichRequestedForSignature != signature;
  }

  void initialize({required bool isActive}) {
    _isActive = isActive;
    _service.addListener(_onServiceChanged);
    _serviceListenerAttached = true;
    _maybeAutoEnrich();
  }

  void updateActive(bool isActive) {
    if (_isActive == isActive) return;
    _isActive = isActive;
    _maybeAutoEnrich();
  }

  bool scheduleAutoEnrich(String signature) {
    if (!_isActive || _autoEnrichScheduledForSignature == signature) {
      return false;
    }
    _autoEnrichScheduledForSignature = signature;
    return true;
  }

  void runScheduledAutoEnrich() {
    _autoEnrichScheduledForSignature = null;
    _maybeAutoEnrich();
  }

  List<Shout> acceptSnapshotData(List<Shout> data) {
    final unique = deduplicateNotificationShouts(data);
    _shouts = unique;
    return unique;
  }

  Future<List<Shout>> refresh() async {
    final uniqueShouts = await _coordinator.refresh();
    _shouts = uniqueShouts;
    _shoutsFuture = Future.value(uniqueShouts);
    notifyListeners();
    _coordinator.commitRefreshedShouts(uniqueShouts);
    return uniqueShouts;
  }

  Future<void> toggleSelectAll() async {
    final localShouts = _shouts;
    if (localShouts == null || !_coordinator.toggleSelectAll(localShouts)) {
      return;
    }
    _shouts = localShouts;
    notifyListeners();
  }

  Future<void> removeSelected() async {
    if (!await _coordinator.removeSelected()) return;
    await refresh();
  }

  Future<void> nukeSection() async {
    if (!await _coordinator.nukeSection()) return;
    await refresh();
  }

  void setChecked(Shout shout, bool isChecked) {
    shout.isChecked = isChecked;
    notifyListeners();
    _coordinator.setChecked(shout.id, isChecked);
  }

  void _maybeAutoEnrich() {
    if (!_isActive || !_service.shoutsNeedEnrich) return;

    final signature = _service.shoutsLightSignature;
    if (signature.isNotEmpty &&
        _enrichRequestedForSignature == signature) {
      return;
    }
    _enrichRequestedForSignature = signature;

    _isEnriching = true;
    _shoutsFuture = _service
        .enrichShoutsFromProfileIfNeeded(force: true)
        .then((list) {
      final unique = deduplicateNotificationShouts(list);
      _shouts = unique;
      return unique;
    }).whenComplete(() {
      if (_disposed) return;
      _isEnriching = false;
      notifyListeners();
    });
    notifyListeners();
  }

  void _onServiceChanged() {
    if (_disposed) return;
    final latest = _coordinator.currentShouts();
    if (latest.isEmpty) return;
    final previous = _shouts;
    if (!_coordinator.hasShoutListChanged(previous, latest)) return;
    if (_isActive &&
        _enrichRequestedForSignature == null &&
        _service.shoutsNeedEnrich) {
      _shouts = latest;
      _maybeAutoEnrich();
      return;
    }

    _shouts = latest;
    _shoutsFuture = Future.value(latest);
    notifyListeners();
  }

  @override
  void dispose() {
    if (_serviceListenerAttached) {
      _service.removeListener(_onServiceChanged);
    }
    _disposed = true;
    super.dispose();
  }
}
