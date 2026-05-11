class PostShoutResult {
  const PostShoutResult({
    required this.success,
    this.message,
    this.isError = true,
  });

  final bool success;
  final String? message;
  final bool isError;
}
