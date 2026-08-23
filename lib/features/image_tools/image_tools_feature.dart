import 'package:fanotifier/features/image_tools/data/image_optimizer_repository_impl.dart';
import 'package:fanotifier/features/image_tools/domain/image_optimizer_repository.dart';

class ImageToolsFeature {
  const ImageToolsFeature._();

  static ImageOptimizerRepository createRepository() {
    return ImageOptimizerRepositoryImpl();
  }
}
