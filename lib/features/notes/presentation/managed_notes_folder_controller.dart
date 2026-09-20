import 'dart:collection';
import 'package:flutter/foundation.dart';
import 'package:fanotifier/features/notes/domain/managed_notes_repository.dart';
import 'package:fanotifier/features/notes/domain/message_model.dart';
import 'package:fanotifier/features/notes/domain/note_management.dart';

class ManagedNotesFolderController {
  ManagedNotesFolderController({
    required this._repository,
    required this._folder,
    required this._isMounted,
    required this._updateState,
    required this._showSnackBar,
  });

  final ManagedNotesRepository _repository;
  final NotesFolder Function() _folder;
  final bool Function() _isMounted;
  final void Function(VoidCallback) _updateState;
  final void Function(String, {required bool success}) _showSnackBar;
  static const int selectAllRateLimitSeconds = 1;

  bool _isLoading = true;
  bool _isLoadingMore = false;
  String _errorMessage = '';
  List<Message> _messages = [];
  bool _isFetchingMore = false;
  int _currentPage = 1;
  bool _hasMore = true;

  bool _selectionMode = false;
  final Set<String> _selectedIds = {};
  bool _isSelectAllInProgress = false;
  int _selectAllProgressPage = 0;
  bool _selectAllCancelled = false;
  bool _isMutating = false;

  bool get isLoading => _isLoading;
  bool get isLoadingMore => _isLoadingMore;
  String get errorMessage => _errorMessage;
  bool get isFetchingMore => _isFetchingMore;
  int get currentPage => _currentPage;
  bool get hasMore => _hasMore;
  bool get selectionMode => _selectionMode;
  bool get isSelectAllInProgress => _isSelectAllInProgress;
  int get selectAllProgressPage => _selectAllProgressPage;
  bool get selectAllCancelled => _selectAllCancelled;
  bool get isMutating => _isMutating;
  List<Message> get messages => UnmodifiableListView(_messages);
  Set<String> get selectedIds => UnmodifiableSetView(_selectedIds);

  Future<void> fetchFolder({int page = 1, bool clearOld = false}) async {
    if (page == 1 && _isMounted()) {
      _updateState(() {
        if (clearOld) _messages.clear();
        _isLoading = true;
        _errorMessage = '';
        _hasMore = true;
      });
    }

    try {
      final newMessages = await _repository.fetchFolderPage(
        folder: _folder(),
        page: page,
      );
      if (!_isMounted()) return;
      _updateState(() {
        if (page == 1) {
          _messages = newMessages;
        } else {
          _messages.addAll(newMessages);
        }
        _isLoading = false;
        if (newMessages.isEmpty) _hasMore = false;
      });
    } catch (e) {
      if (!_isMounted()) return;
      _updateState(() {
        _errorMessage = '$e';
        _isLoading = false;
        _hasMore = false;
      });
    }
  }

  Future<void> loadMore() async {
    _isFetchingMore = true;
    if (_isMounted()) {
      _updateState(() {
        _isLoadingMore = true;
        _currentPage++;
      });
    }
    try {
      await fetchFolder(page: _currentPage);
    } finally {
      _isFetchingMore = false;
      if (_isMounted()) _updateState(() => _isLoadingMore = false);
    }
  }

  void enterSelectionModeAndSelect(Message message) {
    if (_isMutating) return;
    _updateState(() {
      _selectionMode = true;
      _selectedIds.add(message.id);
    });
  }

  void toggleSelection(Message message) {
    if (_isMutating) return;
    _updateState(() {
      if (_selectedIds.contains(message.id)) {
        _selectedIds.remove(message.id);
        if (_selectedIds.isEmpty) _selectionMode = false;
      } else {
        _selectedIds.add(message.id);
      }
    });
  }

  void selectAllLoaded() {
    if (_isSelectAllInProgress || _isMutating) return;
    _updateState(() {
      final loadedIds = _messages.map((message) => message.id).toSet();
      final allLoadedSelected = loadedIds.isNotEmpty &&
          loadedIds.every(_selectedIds.contains);
      if (allLoadedSelected) {
        _selectedIds.removeAll(loadedIds);
      } else {
        _selectedIds.addAll(loadedIds);
      }
    });
  }

  Future<void> selectAllPages() async {
    if (_isSelectAllInProgress || _isMutating || _isFetchingMore) return;
    _updateState(() {
      _isSelectAllInProgress = true;
      _selectionMode = true;
      _selectedIds.clear();
      _selectAllProgressPage = 0;
      _selectAllCancelled = false;
    });

    final loadedIds = _messages.map((message) => message.id).toSet();
    var page = 1;
    while (_isMounted() && !_selectAllCancelled) {
      _updateState(() => _selectAllProgressPage = page);
      List<Message> messages;
      try {
        messages = await _repository.fetchFolderPage(
          folder: _folder(),
          page: page,
        );
      } catch (e) {
        if (_isMounted()) {
          _updateState(() => _isSelectAllInProgress = false);
          _showSnackBar('Failed to fetch page $page.', success: false);
        }
        return;
      }

      if (messages.isEmpty) {
        if (_isMounted()) _updateState(() => _hasMore = false);
        break;
      }
      if (!_isMounted()) return;
      _updateState(() {
        for (final message in messages) {
          _selectedIds.add(message.id);
          if (loadedIds.add(message.id)) _messages.add(message);
        }
        if (page > _currentPage) _currentPage = page;
      });
      page++;
      await Future.delayed(
        const Duration(seconds: selectAllRateLimitSeconds),
      );
    }

    if (_isMounted()) _updateState(() => _isSelectAllInProgress = false);
  }

  void cancelSelectAll() {
    _selectAllCancelled = true;
  }

  void exitSelectionMode() {
    if (_isSelectAllInProgress || _isMutating) return;
    _updateState(() {
      _selectionMode = false;
      _selectedIds.clear();
    });
  }

  void resetPagination() {
    _currentPage = 1;
    _hasMore = true;
  }

  Future<void> applyAction({
    required List<String> ids,
    required NoteManagementAction action,
    required String successMessage,
    required String unknownMessage,
    required String failureMessage,
  }) async {
    _updateState(() => _isMutating = true);
    try {
      await _repository.applyAction(
        ids: ids,
        sourceFolder: _folder(),
        action: action,
      );
      if (!_isMounted()) return;
      _updateState(() {
        _selectionMode = false;
        _selectedIds.clear();
        _currentPage = 1;
        _hasMore = true;
      });
      await fetchFolder(page: 1);
      if (_isMounted()) _showSnackBar(successMessage, success: true);
    } on NoteManagementOutcomeUnknownException {
      if (_isMounted()) _showSnackBar(unknownMessage, success: false);
    } catch (e) {
      if (_isMounted()) _showSnackBar(failureMessage, success: false);
    } finally {
      if (_isMounted()) _updateState(() => _isMutating = false);
    }
  }
}
