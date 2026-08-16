// lib/finalize_submission.dart

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:fanotifier/features/submissions/domain/finalize_submission_repository.dart';
import 'package:fanotifier/features/submissions/domain/finalize_submission_request.dart';
import 'package:fanotifier/features/submissions/domain/submission_form_option.dart';
import 'package:fanotifier/features/submissions/domain/finalize_submission_defaults.dart';

class FinalizeSubmissionScreen extends StatefulWidget {
  final String submissionKey;
  final String submissionType;
  final FinalizeSubmissionRepository? repository;


  const FinalizeSubmissionScreen({
    super.key,
    required this.submissionKey,
    required this.submissionType,
    this.repository,

  });

  @override
  State<FinalizeSubmissionScreen> createState() =>
      _FinalizeSubmissionScreenState();
}

class _FinalizeSubmissionScreenState extends State<FinalizeSubmissionScreen> {
  final _formKey = GlobalKey<FormState>();

  // Form Fields
  String _category = FinalizeSubmissionDefaults.category;
  String _theme = FinalizeSubmissionDefaults.theme;
  String _species = FinalizeSubmissionDefaults.species;
  String _gender = FinalizeSubmissionDefaults.gender;
  String _rating = FinalizeSubmissionDefaults.rating;
  String _title = '';
  String _description = '';
  String _keywords = '';
  bool _lockComments = false;
  bool _putInScraps = false;
  String _folderName = '';
  String? _submissionKeyUpload;

  bool _isFinalizing = false;
  String _errorMessage = '';

  late final FinalizeSubmissionRepository _finalizeSubmissionRepository;

  // Option Groups
  List<OptionGroup> _categoryOptions = [];
  List<OptionGroup> _themeOptions = [];
  List<OptionGroup> _speciesOptions = [];
  List<OptionGroup> _genderOptions = [];

  bool _isLoadingOptions = true;

  @override
  void initState() {
    super.initState();
    _finalizeSubmissionRepository = widget.repository ??
        context.read<FinalizeSubmissionRepositoryFactory>()();
    _fetchOptions();
  }

  /// Fetches and parses options from the Fur Affinity submission finalization page.
  Future<void> _fetchOptions() async {
    setState(() {
      _isLoadingOptions = true;
    });

    try {
      final parsed = await _finalizeSubmissionRepository.fetchOptions();
      if (!mounted) return;
      final submissionKey = parsed.submissionKey;
      setState(() {
        _submissionKeyUpload = submissionKey;
      });
      debugPrint("Finalized Submission Key: $_submissionKeyUpload");
      _categoryOptions = parsed.categoryOptions;
      _themeOptions = parsed.themeOptions;
      _speciesOptions = parsed.speciesOptions;
      _genderOptions = parsed.genderOptions;

      setState(() {
        _isLoadingOptions = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Error fetching options: $e';
        _isLoadingOptions = false;
      });
      debugPrint("Error in _fetchOptions: $e");
    }
  }

  /// Handles the finalization of the submission.
  Future<void> _finalizeSubmission() async {
    if (!_formKey.currentState!.validate()) {
      // Form validation failed
      return;
    }

    if (_submissionKeyUpload == null || _submissionKeyUpload!.isEmpty) {
      setState(() {
        _errorMessage = 'Submission key is missing.';
      });
      return;
    }

    setState(() {
      _isFinalizing = true;
      _errorMessage = '';
    });

    try {
      await _finalizeSubmissionRepository.finalizeSubmission(
        FinalizeSubmissionRequest(
          key: _submissionKeyUpload!,
          category: _category,
          theme: _theme,
          species: _species,
          gender: _gender,
          rating: _rating,
          title: _title,
          description: _description,
          keywords: _keywords,
          lockComments: _lockComments,
          putInScraps: _putInScraps,
          folderName: _folderName,
        ),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Submission uploaded successfully!'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 3),
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Error finalizing submission: $e';
      });
      debugPrint("Error in _finalizeSubmission: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error finalizing submission: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isFinalizing = false;
        });
      }
    }
  }


  void _openSelectionDialog(
      {required String title,
        required List<OptionGroup> groups,
        required Function(String) onSelected}) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: groups.length,
              itemBuilder: (BuildContext context, int index) {
                OptionGroup group = groups[index];
                return group.label.isNotEmpty
                    ? ExpansionTile(
                  title: Text(
                    group.label,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  children: group.options.map((Option option) {
                    return ListTile(
                      title: Text(
                        option.label,
                        style: option.isDefault
                            ? const TextStyle(fontWeight: FontWeight.bold)
                            : null,
                      ),
                      trailing: option.isDefault
                          ? const Text(
                        '(Default)',
                        style: TextStyle(
                            fontStyle: FontStyle.italic,
                            color: Colors.grey),
                      )
                          : null,
                      onTap: () {
                        onSelected(option.value);
                        Navigator.pop(context);
                      },
                    );
                  }).toList(),
                )
                    : Column(
                  children: group.options.map((Option option) {
                    return ListTile(
                      title: Text(
                        option.label,
                        style: option.isDefault
                            ? const TextStyle(fontWeight: FontWeight.bold)
                            : null,
                      ),
                      trailing: option.isDefault
                          ? const Text(
                        '(Default)',
                        style: TextStyle(
                            fontStyle: FontStyle.italic,
                            color: Colors.grey),
                      )
                          : null,
                      onTap: () {
                        onSelected(option.value);
                        Navigator.pop(context);
                      },
                    );
                  }).toList(),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  /// Retrieves the selected label based on the current value.
  String _getSelectedLabel(List<OptionGroup> groups, String value) {
    for (var group in groups) {
      for (var option in group.options) {
        if (option.value == value) {
          return option.label;
        }
      }
    }
    return 'Select';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Finalize Submission'),
      ),
      body: _isLoadingOptions
          ? const Center(child: CircularProgressIndicator())
          : Padding(
        padding: const EdgeInsets.all(16.0),
        child: _isFinalizing
            ? const Center(child: CircularProgressIndicator())
            : Form(
          key: _formKey,
          child: ListView(
            children: [
              ElevatedButton(
                onPressed: () {
                  _openSelectionDialog(
                    title: 'Select Category',
                    groups: _categoryOptions,
                    onSelected: (value) {
                      setState(() {
                        _category = value;
                      });
                    },
                  );
                },
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Category'),
                    Text(_getSelectedLabel(_categoryOptions, _category)),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              ElevatedButton(
                onPressed: () {
                  _openSelectionDialog(
                    title: 'Select Theme',
                    groups: _themeOptions,
                    onSelected: (value) {
                      setState(() {
                        _theme = value;
                      });
                    },
                  );
                },
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Theme'),
                    Text(_getSelectedLabel(_themeOptions, _theme)),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              ElevatedButton(
                onPressed: () {
                  _openSelectionDialog(
                    title: 'Select Species',
                    groups: _speciesOptions,
                    onSelected: (value) {
                      setState(() {
                        _species = value;
                      });
                    },
                  );
                },
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Species'),
                    Text(_getSelectedLabel(_speciesOptions, _species)),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              ElevatedButton(
                onPressed: () {
                  _openSelectionDialog(
                    title: 'Select Gender',
                    groups: _genderOptions,
                    onSelected: (value) {
                      setState(() {
                        _gender = value;
                      });
                    },
                  );
                },
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Gender'),
                    Text(_getSelectedLabel(_genderOptions, _gender)),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              const Text(
                'Submission Rating',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              RadioGroup<String>(
                groupValue: _rating,
                onChanged: (String? value) {
                  if (value == null) return;
                  setState(() {
                    _rating = value;
                  });
                },
                child: const Column(
                  children: [
                    RadioListTile<String>(
                      title: Text('General'),
                      value: '0',
                    ),
                    RadioListTile<String>(
                      title: Text('Mature'),
                      value: '2',
                    ),
                    RadioListTile<String>(
                      title: Text('Adult'),
                      value: '1',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              TextFormField(
                decoration: const InputDecoration(
                  labelText: 'Title',
                  border: OutlineInputBorder(),
                ),
                maxLength: 60,
                onChanged: (value) {
                  _title = value;
                },
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter a title';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 10),

              TextFormField(
                decoration: const InputDecoration(
                  labelText: 'Submission Description',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                  helperText:
                  'Please provide a detailed description of your submission.',
                  helperMaxLines: 3,
                ),
                minLines: 3,
                maxLines: null,
                keyboardType: TextInputType.multiline,
                onChanged: (value) {
                  _description = value;
                },
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter a description';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 10),

              TextFormField(
                decoration: const InputDecoration(
                  labelText: 'Keywords (250)',
                  border: OutlineInputBorder(),
                  helperText:
                  'Separate keywords using spaces (e.g. "fox lion transformation"). Keywords help users find your submission in the search engine. Per site policy, keywords must be related directly to the content of your submission. Misleading or abusive keywords are not permitted.',
                  helperMaxLines: 6,
                ),
                maxLength: 250,
                maxLines: null,
                onChanged: (value) {
                  _keywords = value;
                },
              ),
              const SizedBox(height: 10),

              const Text(
                'Submission Options',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              CheckboxListTile(
                title: const Text('Disable Comments'),
                value: _lockComments,
                onChanged: (bool? value) {
                  setState(() {
                    _lockComments = value ?? false;
                  });
                },
              ),
              CheckboxListTile(
                title: const Text('Put in Scraps'),
                value: _putInScraps,
                onChanged: (bool? value) {
                  setState(() {
                    _putInScraps = value ?? false;
                  });
                },
              ),
              const SizedBox(height: 20),

              TextFormField(
                decoration: const InputDecoration(
                  labelText: 'Assign to a New Folder',
                  border: OutlineInputBorder(),
                  helperText:
                  'Folders have more options than just a name. Please visit the folder management control panel later to specify them and organize the folders in groups and order.',
                  helperMaxLines: 3,
                ),
                onChanged: (value) {
                  _folderName = value;
                },
              ),
              const SizedBox(height: 20),

              ElevatedButton(
                onPressed: _isFinalizing ? null : _finalizeSubmission,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16.0),
                  textStyle: const TextStyle(fontSize: 18),
                  backgroundColor: Colors.blue,
                ),
                child: _isFinalizing
                    ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    strokeWidth: 2.0,
                  ),
                )
                    : const Text('Finalize'),
              ),

              if (_errorMessage.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 20),
                  child: Text(
                    _errorMessage,
                    style: const TextStyle(color: Colors.red, fontSize: 16),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
