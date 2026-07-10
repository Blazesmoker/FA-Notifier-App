class UploadSelectedFile {
  const UploadSelectedFile({
    required this.fileName,
    required this.base64Data,
    required this.extension,
  });

  final String fileName;
  final String base64Data;
  final String extension;
}
