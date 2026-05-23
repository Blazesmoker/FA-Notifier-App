class FinalizeSubmissionRequest {
  final String key;
  final String category;
  final String theme;
  final String species;
  final String gender;
  final String rating;
  final String title;
  final String description;
  final String keywords;
  final bool lockComments;
  final bool putInScraps;
  final String folderName;

  const FinalizeSubmissionRequest({
    required this.key,
    required this.category,
    required this.theme,
    required this.species,
    required this.gender,
    required this.rating,
    required this.title,
    required this.description,
    required this.keywords,
    required this.lockComments,
    required this.putInScraps,
    required this.folderName,
  });

  Map<String, dynamic> toFormData() {
    return {
      'key': key,
      'cat': category,
      'atype': theme,
      'species': species,
      'gender': gender,
      'rating': rating,
      'title': title,
      'message': description,
      'keywords': keywords,
      'lock_comments': lockComments ? '1' : '0',
      'scrap': putInScraps ? '1' : '0',
      'create_folder_name': folderName,
      'finalize': 'Finalize',
    };
  }
}
