import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fanotifier/features/submissions/data/submission_attachment_html_builder.dart';
import 'package:fanotifier/features/submissions/presentation/widgets/submission_attachment_styles.dart';

class SubmissionAudioPlayer extends StatelessWidget {
  const SubmissionAudioPlayer({
    super.key,
    required this.url,
    required this.routeDetached,
  });

  static const double _height = 112.0;

  final String url;
  final bool routeDetached;

  @override
  Widget build(BuildContext context) {
    if (routeDetached) {
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
          child: InAppWebView(
            key: ValueKey<String>(url),
            gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
              Factory<OneSequenceGestureRecognizer>(
                () => HorizontalDragGestureRecognizer(),
              ),
            },
            initialData: InAppWebViewInitialData(
              data: buildSubmissionAudioHtml(url),
              baseUrl: WebUri('https://www.furaffinity.net'),
              encoding: 'utf-8',
              mimeType: 'text/html',
            ),
            initialSettings: InAppWebViewSettings(
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
          ),
        ),
      ),
    );
  }

}
