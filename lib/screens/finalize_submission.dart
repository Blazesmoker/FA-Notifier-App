// lib/finalize_submission.dart

import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as dom;
import 'package:shared_preferences/shared_preferences.dart';

class FinalizeSubmissionScreen extends StatefulWidget {
  final String submissionKey;
  final String submissionType;


  const FinalizeSubmissionScreen({
    Key? key,
    required this.submissionKey,
    required this.submissionType,

  }) : super(key: key);

  @override
  _FinalizeSubmissionScreenState createState() =>
      _FinalizeSubmissionScreenState();
}

class _FinalizeSubmissionScreenState extends State<FinalizeSubmissionScreen> {
  final _formKey = GlobalKey<FormState>();

  // Form Fields
  String _category = '1'; // Default to 'All'
  String _theme = '1'; // Default to 'All'
  String _species = '1'; // Default to 'Unspecified / Any'
  String _gender = '0'; // Default to 'Any'
  String _rating = '0'; // General
  String _title = '';
  String _description = '';
  String _keywords = '';
  bool _lockComments = false;
  bool _putInScraps = false;
  String _folderName = '';
  String? _submissionKeyUpload;

  bool _isFinalizing = false;
  String _errorMessage = '';

  final Dio _dio = Dio();
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  final CookieJar _cookieJar = CookieJar();

  // Option Groups
  List<OptionGroup> _categoryOptions = [];
  List<OptionGroup> _themeOptions = [];
  List<OptionGroup> _speciesOptions = [];
  List<OptionGroup> _genderOptions = [];

  bool _isLoadingOptions = true;

  @override
  void initState() {
    super.initState();
    _initializeDio();
    _loadCookies().then((_) {
      _fetchOptions();
    });
  }

  void _initializeDio() {
    _dio.options.headers['User-Agent'] =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36';
    _dio.options.headers['Accept'] =
    'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8';
    _dio.options.headers['Accept-Encoding'] = 'gzip, deflate, br, zstd';
    _dio.options.headers['Accept-Language'] = 'en-US,en;q=0.9';
    _dio.options.followRedirects = true;
    _dio.options.validateStatus = (status) {
      return status != null && (status >= 200 && status < 400);
    };


    _dio.interceptors.add(CookieManager(_cookieJar));
  }

  Future<void> _loadCookies() async {
    try {

      String? cookieA = await _secureStorage.read(key: 'fa_cookie_a');
      String? cookieB = await _secureStorage.read(key: 'fa_cookie_b');
      String? trackingConsent = await _secureStorage.read(key: '_tracking_consent');
      String? shopifyY = await _secureStorage.read(key: '_shopify_y');
      String? cc = await _secureStorage.read(key: 'cc');
      String? n = await _secureStorage.read(key: 'n');
      String? sz = await _secureStorage.read(key: 'sz');
      String? folder = await _secureStorage.read(key: 'folder');


      final prefs = await SharedPreferences.getInstance();
      bool sfwEnabled = prefs.getBool('sfwEnabled') ?? true;

      String sfwValue = sfwEnabled ? '1' : '0';


      List<Cookie> cookies = [];

      if (cookieA != null) cookies.add(Cookie('a', cookieA));
      if (cookieB != null) cookies.add(Cookie('b', cookieB));
      if (trackingConsent != null) cookies.add(Cookie('_tracking_consent', trackingConsent));
      if (shopifyY != null) cookies.add(Cookie('_shopify_y', shopifyY));
      if (cc != null) cookies.add(Cookie('cc', cc));
      if (n != null) cookies.add(Cookie('n', n));
      if (sz != null) cookies.add(Cookie('sz', sz));
      if (folder != null) cookies.add(Cookie('folder', folder));
      cookies.add(Cookie('sfw', sfwValue));


      Uri uri = Uri.parse('https://www.furaffinity.net');
      await _cookieJar.saveFromResponse(uri, cookies);

      List<Cookie> savedCookies = await _cookieJar.loadForRequest(uri);
      for (var cookie in savedCookies) {
        print("${cookie.name}");
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error loading cookies: $e';
        _isLoadingOptions = false;
      });
      print("Error in _loadCookies: $e");
    }
  }

  /// Parses the submission key from the HTML document.
  String _parseSubmissionKey(dom.Document document) {
    final formElement = document.querySelector('form#myform');

    if (formElement == null) {
      throw Exception('Finalize Submission form (id="myform") not found.');
    }

    final keyElement = formElement.querySelector('input[name="key"]');

    if (keyElement != null) {
      String parsedKey = keyElement.attributes['value'] ?? '';
      if (parsedKey.isEmpty) {
        throw Exception('Finalize Submission key value is empty.');
      }
      print("Parsed Finalize Submission Key: $parsedKey");
      return parsedKey;
    } else {
      throw Exception('Finalize Submission key input not found within the form.');
    }
  }

  Future<void> _saveToFile(String fileName, String content) async {
    try {
      final directory = await Directory.systemTemp.createTemp('request_logs');
      final file = File('${directory.path}/$fileName');
      await file.writeAsString(content, mode: FileMode.append);
      print('Saved request body to file: ${file.path}');
    } catch (e) {
      print('Error saving to file: $e');
    }
  }

  /// Fetches and parses options from the Fur Affinity submission finalization page.
  Future<void> _fetchOptions() async {
    setState(() {
      _isLoadingOptions = true;
    });

    try {
      final response = await _dio.get('https://www.furaffinity.net/submit/finalize/');

      print("GET /submit/finalize/ Status Code: ${response.statusCode}");

      await _saveToFile(
        'fetch_options_get.txt',
        'Request: GET /submit/finalize/\nResponse: ${response.data}\nTimestamp: ${DateTime.now()}\n\n',
      );

      if (response.data is String && response.data.length > 1000) {
        print("Response snippet: ${response.data.substring(0, 1000)}");
      } else {
        print("Response data: ${response.data}");
      }

      if (response.statusCode == 200 || response.statusCode == 302) {
        dom.Document document = html_parser.parse(response.data);


        if (document.querySelector('form[name="login"]') != null) {
          throw Exception('Not authenticated. Please check your login status.');
        }


        String submissionKey = _parseSubmissionKey(document);
        setState(() {
          _submissionKeyUpload = submissionKey;
        });
        print("Finalized Submission Key: $_submissionKeyUpload");
        // Parse Category
        _categoryOptions = _parseSelectOptions(document, 'cat');

        // Remove 'All' from specific groups if present
        _removeDefaultAllFromGroup(_categoryOptions, ['Visual Art']);

        // Inserting own 'All' at the top
        _categoryOptions.insert(
          0,
          OptionGroup(
            label: '',
            options: [
              Option(label: 'All', value: '1', isDefault: true),
            ],
          ),
        );

        // Parse Theme
        _themeOptions = _parseSelectOptions(document, 'atype');

        // Remove 'All' from specific groups if present
        _removeDefaultAllFromGroup(_themeOptions, ['General Things']);

        // Inserting own 'All' at the top
        _themeOptions.insert(
          0,
          OptionGroup(
            label: '',
            options: [
              Option(label: 'All', value: '1', isDefault: true),
            ],
          ),
        );

        // Parse Species
        _speciesOptions = _parseSelectOptions(document, 'species');

        // Parse Gender
        _genderOptions = _parseSelectOptions(document, 'gender');

        setState(() {
          _isLoadingOptions = false;
        });
      } else {
        throw Exception(
            'Failed to load submission finalization page. Status code: ${response.statusCode}');
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error fetching options: $e';
        _isLoadingOptions = false;
      });
      print("Error in _fetchOptions: $e");
    }
  }

  /// Removes the first 'All' option from specified groups if it exists.
  void _removeDefaultAllFromGroup(List<OptionGroup> groups, List<String> targetGroupLabels) {
    for (var group in groups) {
      if (targetGroupLabels.contains(group.label)) {
        if (group.options.isNotEmpty && group.options[0].label.toLowerCase() == 'all') {
          group.options.removeAt(0);
          print("Removed 'All' from group: ${group.label}");
        }
      }
    }
  }

  /// Parses a <select> element by its name and returns a list of OptionGroups.
  List<OptionGroup> _parseSelectOptions(dom.Document document, String selectName) {
    List<OptionGroup> optionGroups = [];
    dom.Element? selectElement = document.querySelector('select[name="$selectName"]');

    if (selectElement == null) {
      print('Select element with name="$selectName" not found.');
      return optionGroups;
    }


    List<Option> directOptions = selectElement.children
        .where((element) => element.localName == 'option')
        .map((option) {
      return Option(
        label: option.text.trim(),
        value: option.attributes['value'] ?? '',
        isDefault: option.attributes.containsKey('selected'),
      );
    }).toList();

    if (directOptions.isNotEmpty) {
      optionGroups.add(OptionGroup(label: '', options: directOptions));
    }


    List<dom.Element> optgroups = selectElement.querySelectorAll('optgroup');
    for (var optgroup in optgroups) {
      String groupLabel = optgroup.attributes['label'] ?? '';
      List<Option> options = optgroup.querySelectorAll('option').map((option) {
        return Option(
          label: option.text.trim(),
          value: option.attributes['value'] ?? '',
          isDefault: option.attributes.containsKey('selected'),
        );
      }).toList();
      optionGroups.add(OptionGroup(label: groupLabel, options: options));
    }

    return optionGroups;
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
      Map<String, dynamic> data = {
        'key': _submissionKeyUpload,
        'cat': _category,
        'atype': _theme,
        'species': _species,
        'gender': _gender,
        'rating': _rating,
        'title': _title,
        'message': _description,
        'keywords': _keywords,
        'lock_comments': _lockComments ? '1' : '0',
        'scrap': _putInScraps ? '1' : '0',
        'create_folder_name': _folderName,
        'finalize': 'Finalize',
      };

      print("Finalizing submission with key: ${data['key']}");
      print("Finalizing submission with data: $data");

      await _saveToFile(
        'finalize_submission_post.txt',
        'Request Data: $data\nTimestamp: ${DateTime.now()}\n\n',
      );

      // Send POST request
      final response = await _dio.post(
        'https://www.furaffinity.net/submit/finalize/',
        data: data,
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          headers: {
            'Referer': 'https://www.furaffinity.net/submit/finalize/',
          },
          followRedirects: false,
          validateStatus: (status) {
            return status != null && (status >= 200 && status < 400);
          },
        ),
      );

      print("POST /submit/finalize/ Status Code: ${response.statusCode}");
      print("Response Headers: ${response.headers.map}");


      String responseBody = '';
      if (response.data is String) {
        responseBody = response.data;
        int chunkSize = 1000;
        for (int i = 0; i < responseBody.length; i += chunkSize) {
          int end = (i + chunkSize < responseBody.length)
              ? i + chunkSize
              : responseBody.length;
          print("Response Body Chunk: ${responseBody.substring(i, end)}");
        }
      } else {
        print("Response Data: ${response.data}");
      }

      if (response.statusCode == 302) {
        String? location = response.headers.value('location');
        print("Redirect Location: $location");

        if (location != null && location.contains('?upload-successful')) {
          // Upload was successful
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Submission uploaded successfully!'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 3),
            ),
          );
          Navigator.pop(context);
        } else {
          throw Exception('Upload failed: Unexpected redirect location.');
        }
      } else if (response.statusCode == 200) {
        // Parsing the response body to check for success indicators
        if (responseBody.contains('?upload-successful')) {
          // Success indicated in the response body
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Submission uploaded successfully!'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 3),
            ),
          );
          Navigator.pop(context);
        } else {
          String errorMessage = _extractErrorMessage(responseBody);
          throw Exception('Upload failed: $errorMessage');
        }
      } else {
        throw Exception("Upload failed with status code: ${response.statusCode}");
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error finalizing submission: $e';
      });
      print("Error in _finalizeSubmission: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error finalizing submission: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    } finally {
      setState(() {
        _isFinalizing = false;
      });
    }
  }

  /// Extracts an error message from the response body.

  String _extractErrorMessage(String responseBody) {
    dom.Document document = html_parser.parse(responseBody);
    final errorElements = document.querySelectorAll('.error, .error-message, .alert-danger');
    if (errorElements.isNotEmpty) {
      return errorElements.map((e) => e.text.trim()).join(' ');
    }
    return 'Unknown error occurred.';
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
              RadioListTile<String>(
                title: const Text('General'),
                value: '0',
                groupValue: _rating,
                onChanged: (value) {
                  setState(() {
                    _rating = value!;
                  });
                },
              ),
              RadioListTile<String>(
                title: const Text('Mature'),
                value: '2',
                groupValue: _rating,
                onChanged: (value) {
                  setState(() {
                    _rating = value!;
                  });
                },
              ),
              RadioListTile<String>(
                title: const Text('Adult'),
                value: '1',
                groupValue: _rating,
                onChanged: (value) {
                  setState(() {
                    _rating = value!;
                  });
                },
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
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16.0),
                  textStyle: const TextStyle(fontSize: 18),
                  backgroundColor: Colors.blue,
                ),
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

class OptionGroup {
  final String label;
  final List<Option> options;

  OptionGroup({required this.label, required this.options});
}

class Option {
  final String label;
  final String value;
  final bool isDefault;

  Option({required this.label, required this.value, this.isDefault = false});
}
