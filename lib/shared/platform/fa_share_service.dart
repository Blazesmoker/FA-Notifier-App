import 'package:share_plus/share_plus.dart';

class FaShareService {
  const FaShareService();

  void shareText({
    required String text,
    required String subject,
  }) {
    SharePlus.instance.share(
      ShareParams(
        text: text,
        subject: subject,
      ),
    );
  }
}
