class TagBlocklistParseResult {
  const TagBlocklistParseResult({
    required this.blockedTags,
    required this.total,
    required this.nonce,
  });

  final List<String> blockedTags;
  final int? total;
  final String? nonce;
}
