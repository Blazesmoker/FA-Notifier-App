const openPostFaOrigin = 'https://www.furaffinity.net';
const openPostTagBlockingUrl = '$openPostFaOrigin/route/tag_blocking';
const openPostSubmissionControlsUrl =
    '$openPostFaOrigin/controls/submissions/';
const openPostTroubleTicketsUrl =
    '$openPostFaOrigin/controls/troubletickets/';

String buildSubmissionViewUrl(String submissionId) {
  return '$openPostFaOrigin/view/$submissionId/';
}

String buildOpenPostUserUrl(String username) {
  return '$openPostFaOrigin/user/$username/';
}

String buildOpenPostAbsolutePath(String path) {
  return '$openPostFaOrigin$path';
}

String buildOpenPostChangeInfoUrl(String submissionId) {
  return '$openPostFaOrigin/controls/submissions/changeinfo/$submissionId/';
}

String buildOpenPostChangeThumbnailUrl(String submissionId) {
  return '$openPostFaOrigin/controls/submissions/changethumbnail/$submissionId/';
}

String buildOpenPostChangeSubmissionUrl(String submissionId) {
  return '$openPostFaOrigin/controls/submissions/changesubmission/$submissionId/';
}
