class EditSubmissionNavigationService {
  const EditSubmissionNavigationService();

  bool isUpdateSubmissionUrl(String url) {
    return url.contains('changesubmission');
  }

  bool isSubmissionViewUrl(String url) {
    return url.startsWith('https://www.furaffinity.net/view/');
  }
}
