import 'package:fanotifier/shared/fa/domain/fa_content_block_data.dart';

class ProfileSubmissionData {
  final String hqUrl;
  final bool isFav;
  final String favUrl;
  final String unfavUrl;
  final FaContentBlockData contentBlock;

  ProfileSubmissionData({
    required this.hqUrl,
    required this.isFav,
    required this.favUrl,
    required this.unfavUrl,
    this.contentBlock = const FaContentBlockData(),
  });
}
