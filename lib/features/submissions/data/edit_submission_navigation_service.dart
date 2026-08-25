class EditSubmissionNavigationService {
  const EditSubmissionNavigationService();

  bool isUpdateSubmissionUrl(String url) {
    return url.contains('changesubmission') ||
        url.contains('changethumbnail');
  }

  String? updateFileInputName(String url) {
    if (url.contains('changethumbnail')) return 'newthumbnail';
    if (url.contains('changesubmission')) return 'newsubmission';
    return null;
  }

  bool isSubmissionViewUrl(String url) {
    return url.startsWith('https://www.furaffinity.net/view/');
  }
}
