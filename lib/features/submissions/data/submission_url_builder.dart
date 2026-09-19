const submissionFaOrigin = 'https://www.furaffinity.net';
const submissionTagBlockingUrl = '$submissionFaOrigin/route/tag_blocking';
const submissionControlsUrl =
    '$submissionFaOrigin/controls/submissions/';
const submissionTroubleTicketsUrl =
    '$submissionFaOrigin/controls/troubletickets/';

String buildSubmissionViewUrl(String submissionId) {
  return '$submissionFaOrigin/view/$submissionId/';
}

String buildSubmissionUserUrl(String username) {
  return '$submissionFaOrigin/user/$username/';
}

String buildSubmissionAbsolutePath(String path) {
  return '$submissionFaOrigin$path';
}

String buildSubmissionChangeInfoUrl(String submissionId) {
  return '$submissionFaOrigin/controls/submissions/changeinfo/$submissionId/';
}

String buildSubmissionChangeThumbnailUrl(String submissionId) {
  return '$submissionFaOrigin/controls/submissions/changethumbnail/$submissionId/';
}

String buildSubmissionChangeSubmissionUrl(String submissionId) {
  return '$submissionFaOrigin/controls/submissions/changesubmission/$submissionId/';
}
