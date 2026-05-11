bool isWideProfileImage(Map<String, dynamic> image) {
  final w = image['width'] as double;
  final h = image['height'] as double;
  return (w / h) > 1.5;
}

void appendProfileImagesIntoRows({
  required List<Map<String, dynamic>> newImages,
  required List<List<Map<String, dynamic>>> imageRows,
  required List<Map<String, dynamic>> normalImagesQueue,
}) {
  for (final image in newImages) {
    if (isWideProfileImage(image)) {
      if (normalImagesQueue.isNotEmpty) {
        imageRows.add([normalImagesQueue.removeAt(0), image]);
      } else {
        imageRows.add([image]);
      }
    } else {
      normalImagesQueue.add(image);
    }
  }

  while (normalImagesQueue.length >= 2) {
    imageRows.add([
      normalImagesQueue.removeAt(0),
      normalImagesQueue.removeAt(0),
    ]);
  }

  if (normalImagesQueue.isNotEmpty) {
    imageRows.add([normalImagesQueue.removeAt(0)]);
  }
}
