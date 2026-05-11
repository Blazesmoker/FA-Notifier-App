abstract interface class DetachableWebViewRouteOwner {
  bool get routeWebViewDetached;

  void setRouteWebViewDetached(bool detached);
}

class DetachableWebViewRouteRegistry {
  static final List<DetachableWebViewRouteOwner> _owners =
      <DetachableWebViewRouteOwner>[];

  static void register(DetachableWebViewRouteOwner owner) {
    _owners.remove(owner);
    _owners.add(owner);
  }

  static void unregister(DetachableWebViewRouteOwner owner) {
    _owners.remove(owner);
  }

  static DetachableWebViewRouteOwner? previousOf(
    DetachableWebViewRouteOwner owner,
  ) {
    final currentIndex = _owners.indexOf(owner);
    if (currentIndex <= 0) {
      return null;
    }
    return _owners[currentIndex - 1];
  }
}
