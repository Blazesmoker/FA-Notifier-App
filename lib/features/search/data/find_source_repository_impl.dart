import 'dart:io';

import 'package:fanotifier/features/search/data/find_source_image_input_service.dart';
import 'package:fanotifier/features/search/data/find_source_service.dart';
import 'package:fanotifier/features/search/domain/find_source_models.dart';
import 'package:fanotifier/features/search/domain/find_source_repository.dart';

class FindSourceRepositoryImpl implements FindSourceRepository {
  FindSourceRepositoryImpl({
    FindSourceImageInputService imageInputService =
        const FindSourceImageInputService(),
    FindSourceService? service,
  })  : _imageInputService = imageInputService,
        _service = service ?? FindSourceService();

  final FindSourceImageInputService _imageInputService;
  final FindSourceService _service;

  @override
  Future<String?> pickImagePath() {
    return _imageInputService.pickImagePath();
  }

  @override
  Future<String> hashImagePath(String imagePath) {
    return _imageInputService.hashImage(File(imagePath));
  }

  @override
  Future<FindSourceSearchResult> searchSources(String imagePath) {
    return _service.searchSources(File(imagePath));
  }
}
