import 'package:FANotifier/features/submissions/domain/submission_form_option.dart';

class FinalizeSubmissionOptions {
  final String submissionKey;
  final List<OptionGroup> categoryOptions;
  final List<OptionGroup> themeOptions;
  final List<OptionGroup> speciesOptions;
  final List<OptionGroup> genderOptions;

  const FinalizeSubmissionOptions({
    required this.submissionKey,
    required this.categoryOptions,
    required this.themeOptions,
    required this.speciesOptions,
    required this.genderOptions,
  });
}
