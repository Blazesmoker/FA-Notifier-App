import 'package:fanotifier/shared/fa/domain/fa_session_access.dart';
import 'package:provider/provider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fanotifier/features/submissions/data/submission_attachment_html_builder.dart';
import 'package:fanotifier/features/submissions/presentation/widgets/submission_attachment_styles.dart';
import 'package:fanotifier/shared/navigation/detachable_webview_route_registry.dart';

class SubmissionAudioPlayer extends StatefulWidget {
  const SubmissionAudioPlayer({
    super.key,
    required this.url,
    required this.routeDetached,
  });

  final String url;
  final bool routeDetached;

  @override
  State<SubmissionAudioPlayer> createState() => _SubmissionAudioPlayerState();
}

class _SubmissionAudioPlayerState extends State<SubmissionAudioPlayer> {
  static const double _height = 70.0;
  static const List<double> _playbackRates = <double>[
    0.25,
    0.5,
    0.75,
    1.0,
    1.25,
    1.5,
    1.75,
    2.0,
  ];

  InAppWebViewController? _controller;
  double _playbackRate = 1.0;

  @override
  void didUpdateWidget(covariant SubmissionAudioPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url || widget.routeDetached) {
      _controller = null;
    }
    if (oldWidget.url != widget.url) {
      _playbackRate = 1.0;
    }
  }

  Future<void> _setPlaybackRate(double value) async {
    if (!mounted || widget.routeDetached) {
      return;
    }
    setState(() => _playbackRate = value);
    await _applyPlaybackRate();
  }

  Future<void> _applyPlaybackRate() async {
    final controller = _controller;
    if (controller == null || widget.routeDetached) {
      return;
    }
    try {
      await controller.evaluateJavascript(
        source: buildSubmissionAudioPlaybackRateScript(_playbackRate),
      );
    } catch (_) {
      return;
    }
  }

  Future<void> _showSpeedMenu(BuildContext buttonContext) async {
    final button = buttonContext.findRenderObject() as RenderBox;
    final overlay = Overlay.of(buttonContext).context.findRenderObject()
        as RenderBox;
    final origin = button.localToGlobal(
      Offset(0, button.size.height),
      ancestor: overlay,
    );
    final position = RelativeRect.fromRect(
      Rect.fromLTWH(origin.dx, origin.dy, button.size.width, 0),
      Offset.zero & overlay.size,
    );
    final selected = await DetachableWebViewRouteRegistry.withoutRouteDetach(
      () => showMenu<double>(
        context: buttonContext,
        position: position,
        items: <PopupMenuEntry<double>>[
          const PopupMenuItem<double>(
            enabled: false,
            child: Text('Playback speed'),
          ),
          for (final rate in _playbackRates)
            PopupMenuItem<double>(
              value: rate,
              child: Row(
                children: <Widget>[
                  SizedBox(
                    width: 28.0,
                    child: rate == _playbackRate
                        ? const Icon(Icons.check, size: 18.0)
                        : null,
                  ),
                  Text(rate == 1.0 ? 'Normal (1×)' : '$rate×'),
                ],
              ),
            ),
        ],
      ),
    );
    if (!mounted || selected == null || widget.routeDetached) {
      return;
    }
    await _setPlaybackRate(selected);
  }

  Widget _buildSpeedMenu() {
    return SizedBox(
      width: 44.0,
      child: Builder(
        builder: (buttonContext) => IconButton(
          tooltip: 'Playback speed',
          icon: const Icon(Icons.more_vert),
          onPressed: () => _showSpeedMenu(buttonContext),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final useAppSpeedMenu = defaultTargetPlatform == TargetPlatform.android;
    if (widget.routeDetached) {
      return const ColoredBox(
        color: attachmentSurfaceColor,
        child: SizedBox(
          width: double.infinity,
          height: _height,
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(7.0),
      child: ColoredBox(
        color: attachmentSurfaceColor,
        child: SizedBox(
          width: double.infinity,
          height: _height,
          child: Row(
            children: <Widget>[
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0),
                  child: InAppWebView(
                    key: ValueKey<String>(widget.url),
                    gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
                      Factory<OneSequenceGestureRecognizer>(
                        () => HorizontalDragGestureRecognizer(),
                      ),
                    },
                    initialData: InAppWebViewInitialData(
                      data: buildSubmissionAudioHtml(
                        widget.url,
                        nativePlaybackSpeedEnabled: !useAppSpeedMenu,
                        playbackRate: _playbackRate,
                      ),
                      baseUrl: WebUri('https://www.furaffinity.net'),
                      encoding: 'utf-8',
                      mimeType: 'text/html',
                    ),
                    initialSettings: InAppWebViewSettings(
                      userAgent: context.read<FaSessionAccess>().userAgent,
                      javaScriptEnabled: true,
                      mediaPlaybackRequiresUserGesture: true,
                      allowsInlineMediaPlayback: true,
                      disableVerticalScroll: false,
                      disableHorizontalScroll: false,
                      verticalScrollBarEnabled: false,
                      horizontalScrollBarEnabled: false,
                      supportZoom: false,
                      useHybridComposition: false,
                      transparentBackground: true,
                    ),
                    onWebViewCreated: (controller) {
                      _controller = controller;
                    },
                    onLoadStop: (controller, url) async {
                      if (!mounted || widget.routeDetached || !useAppSpeedMenu) {
                        return;
                      }
                      await _applyPlaybackRate();
                    },
                  ),
                ),
              ),
              if (useAppSpeedMenu) _buildSpeedMenu(),
            ],
          ),
        ),
      ),
    );
  }
}
