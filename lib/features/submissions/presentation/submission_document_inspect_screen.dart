import 'package:material_ui/material_ui.dart';

import 'package:fanotifier/core/analytics/app_screen.dart';
import 'package:fanotifier/features/submissions/domain/submission_attachment.dart';
import 'package:fanotifier/features/submissions/presentation/widgets/submission_document_viewer.dart';

class SubmissionDocumentInspectScreen extends StatelessWidget {
  const SubmissionDocumentInspectScreen({
    super.key,
    required this.attachment,
  });

  final SubmissionAttachment attachment;

  static Route<void> route(SubmissionAttachment attachment) {
    return PageRouteBuilder<void>(
      settings: const AnalyticsRouteSettings(AppScreens.documentViewer),
      opaque: true,
      barrierColor: Colors.black,
      reverseTransitionDuration: Duration.zero,
      pageBuilder: (context, animation, secondaryAnimation) {
        return FadeTransition(
          opacity: animation,
          child: SubmissionDocumentInspectScreen(
            attachment: attachment,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(
          attachment.fileName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SubmissionDocumentViewer(
              attachment: attachment,
              routeDetached: false,
              inspectionMode: true,
              viewportHeight: constraints.maxHeight,
            );
          },
        ),
      ),
    );
  }
}
