import 'package:flutter/services.dart';

class AndroidImeAnimationFrame {
  const AndroidImeAnimationFrame({
    required this.bottom,
    required this.isAnimating,
    required this.isClosing,
  });

  final double bottom;
  final bool isAnimating;
  final bool isClosing;

  factory AndroidImeAnimationFrame.fromPlatform(Object? value) {
    final data = value as Map<Object?, Object?>;
    return AndroidImeAnimationFrame(
      bottom: (data['bottom'] as num).toDouble(),
      isAnimating: data['isAnimating'] == true,
      isClosing: data['isClosing'] == true,
    );
  }
}

class AndroidImeAnimation {
  const AndroidImeAnimation._();

  static const EventChannel _channel = EventChannel('app.ime_animation');
  static Stream<AndroidImeAnimationFrame>? _frames;

  static Stream<AndroidImeAnimationFrame> get frames {
    return _frames ??= _channel.receiveBroadcastStream().map(
          AndroidImeAnimationFrame.fromPlatform,
        );
  }
}
