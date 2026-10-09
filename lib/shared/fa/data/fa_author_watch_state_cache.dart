import 'package:fanotifier/core/fa/fa_media_auth.dart';
import 'package:fanotifier/shared/fa/domain/fa_author_watch_state_store.dart';
import 'package:fanotifier/shared/fa/fa_username.dart';

class FaAuthorWatchStateCache implements FaAuthorWatchStateStore {
  FaAuthorWatchStateCache() {
    FaMediaAuth.changes.addListener(_synchronizeSession);
  }

  final Map<String, FaAuthorWatchState> _states = {};
  int _sessionRevision = -1;
  int _revision = 0;

  @override
  void dispose() {
    FaMediaAuth.changes.removeListener(_synchronizeSession);
    _states.clear();
  }

  @override
  int get revision {
    _synchronizeSession();
    return _revision;
  }

  void _synchronizeSession() {
    final sessionRevision = FaMediaAuth.changes.value;
    if (_sessionRevision != sessionRevision) {
      _states.clear();
      _sessionRevision = sessionRevision;
      _revision++;
    }
  }

  @override
  FaAuthorWatchState? read(String username) {
    _synchronizeSession();
    return _states[sanitizeFAUsername(username)];
  }

  @override
  void write(
    String username,
    FaAuthorWatchState state, {
    required int expectedRevision,
  }) {
    if (expectedRevision != revision || !state.hasCurrentAction) {
      return;
    }
    final key = sanitizeFAUsername(username);
    if (key.isEmpty) {
      return;
    }
    _states[key] = state;
  }

  @override
  void invalidate(String username) {
    _synchronizeSession();
    _states.remove(sanitizeFAUsername(username));
    _revision++;
  }
}
