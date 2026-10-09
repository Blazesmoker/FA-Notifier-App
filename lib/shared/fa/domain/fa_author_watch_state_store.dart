class FaAuthorWatchState {
  const FaAuthorWatchState({
    required this.isWatching,
    this.watchLink,
    this.unwatchLink,
    this.isBlocked,
  });

  final bool isWatching;
  final String? watchLink;
  final String? unwatchLink;
  final bool? isBlocked;

  bool get hasCurrentAction =>
      (isWatching ? unwatchLink : watchLink)?.isNotEmpty ?? false;
}

abstract interface class FaAuthorWatchStateStore {
  void dispose();

  int get revision;

  FaAuthorWatchState? read(String username);

  void write(
    String username,
    FaAuthorWatchState state, {
    required int expectedRevision,
  });

  void invalidate(String username);
}
