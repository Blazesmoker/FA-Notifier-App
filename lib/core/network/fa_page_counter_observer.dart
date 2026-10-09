import 'dart:async';
import 'dart:convert';

import 'package:fanotifier/shared/fa/data/fa_notification_counter_parser.dart';
import 'package:fanotifier/shared/fa/domain/fa_page_counter_observation.dart';

class FaPageCounterRequest {
  const FaPageCounterRequest(
    this.startedAtMilliseconds,
    this.sessionGeneration,
    this.allowNotesList,
  );

  final int startedAtMilliseconds;
  final int sessionGeneration;
  final bool allowNotesList;
}

class FaPageCounterObserver {
  FaPageCounterObserver._();

  static final instance = FaPageCounterObserver._();
  final _controller = StreamController<FaPageCounterObservation>.broadcast();
  int _sessionGeneration = 0;
  bool _active = false;

  Stream<FaPageCounterObservation> get observations => _controller.stream;

  int start() {
    if (!_active) {
      _sessionGeneration++;
    }
    _active = true;
    return _sessionGeneration;
  }

  void stop() {
    _active = false;
    _sessionGeneration++;
  }

  bool _eligible(Uri uri, {bool allowNotesList = false}) {
    if (uri.scheme != 'https' ||
        (uri.host != 'www.furaffinity.net' && uri.host != 'furaffinity.net')) {
      return false;
    }
    final path = uri.path.toLowerCase();
    return (allowNotesList || !RegExp(r'^/msg/pms(?:/\d+)?/?$').hasMatch(path)) &&
        !path.startsWith('/login') && !path.startsWith('/logout');
  }

  FaPageCounterRequest? capture(Uri uri, {bool allowNotesList = false}) {
    if (!_active || !_eligible(uri, allowNotesList: allowNotesList)) {
      return null;
    }
    return FaPageCounterRequest(
      DateTime.now().millisecondsSinceEpoch,
      _sessionGeneration,
      allowNotesList,
    );
  }

  void acceptBytes({
    required FaPageCounterRequest? request,
    required Uri uri,
    required int statusCode,
    required List<int> bytes,
  }) {
    if (request == null || !_active ||
        request.sessionGeneration != _sessionGeneration || statusCode != 200) {
      return;
    }
    final prefix = bytes.length > 131072 ? bytes.sublist(0, 131072) : bytes;
    accept(
      request: request, uri: uri, statusCode: statusCode,
      html: utf8.decode(prefix, allowMalformed: true),
    );
  }

  void accept({
    required FaPageCounterRequest? request,
    required Uri uri,
    required int statusCode,
    required String html,
  }) {
    if (request == null || !_active ||
        request.sessionGeneration != _sessionGeneration ||
        statusCode != 200 || !_eligible(uri, allowNotesList: request.allowNotesList)) {
      return;
    }
    try {
      final prefix = html.length > 131072 ? html.substring(0, 131072) : html;
      final counts = parseFaNotificationCounterHeader(prefix);
      if (counts == null) {
        return;
      }
      _controller.add(FaPageCounterObservation(
        counts: counts,
        startedAtMilliseconds: request.startedAtMilliseconds,
        sessionGeneration: request.sessionGeneration,
      ));
    } catch (_) {}
  }
}
