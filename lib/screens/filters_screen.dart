import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import '../widgets/PulsatingLoadingIndicator.dart';

class FiltersScreen extends StatefulWidget {
  /// Pass in the currently selected filters.
  final Map<String, String> selectedFilters;

  const FiltersScreen({
    required this.selectedFilters,
    Key? key,
  }) : super(key: key);

  @override
  _FiltersScreenState createState() => _FiltersScreenState();
}

class _FiltersScreenState extends State<FiltersScreen> {

  late Map<String, String> currentFilters;

  // Tracks if filter options are loading.
  bool _isLoadingFilters = true;

  // Stores the fetched filter options.
  Map<String, List<Map<String, String>>> _filterOptions = {};

  static const Map<String, String> filterDisplayNames = {
    'cat': 'Category',
    'atype': 'Type',
    'species': 'Species',
    'gender': 'Gender',
  };


  static const Color applyButtonColor = Color(0xFFE09321);


  bool _ratingGeneral = true;
  bool _ratingMature = true;
  bool _ratingAdult = true;

  @override
  void initState() {
    super.initState();


    currentFilters = {};
    filterDisplayNames.forEach((internalKey, displayLabel) {
      if (widget.selectedFilters.containsKey(internalKey)) {
        currentFilters[internalKey] = widget.selectedFilters[internalKey]!;
      } else if (widget.selectedFilters.containsKey(displayLabel)) {
        currentFilters[internalKey] = widget.selectedFilters[displayLabel]!;
      } else {
        currentFilters[internalKey] = 'Unknown';
      }
    });


    if (widget.selectedFilters.containsKey('rating-general')) {
      _ratingGeneral = widget.selectedFilters['rating-general'] == '1';
    }
    if (widget.selectedFilters.containsKey('rating-mature')) {
      _ratingMature = widget.selectedFilters['rating-mature'] == '1';
    }
    if (widget.selectedFilters.containsKey('rating-adult')) {
      _ratingAdult = widget.selectedFilters['rating-adult'] == '1';
    }

    // Start fetching filter options.
    _fetchFilterData();
  }

  /// Fetches filter options from the FA browse page.
  Future<void> _fetchFilterData() async {
    setState(() {
      _isLoadingFilters = true;
    });
    try {
      print('Fetching all filters...');
      final response =
      await http.get(Uri.parse('https://www.furaffinity.net/browse/'));
      if (response.statusCode == 200) {
        var document = html_parser.parse(response.body);
        Map<String, List<Map<String, String>>> loadedFilterOptions = {};
        List<String> filterNames = ['cat', 'atype', 'species', 'gender'];
        for (String filterName in filterNames) {
          var selectElement =
          document.querySelector('select[name="$filterName"]');
          if (selectElement != null) {
            var options = selectElement.querySelectorAll('option').map((e) {
              String label = e.text.trim();
              String value = e.attributes['value'] ?? '';
              return {'label': label, 'value': value};
            }).toList();
            loadedFilterOptions[filterName] = options;
            print('$filterName: ${options.length} options fetched.');
          } else {
            print('Select element for "$filterName" not found.');
            loadedFilterOptions[filterName] = [];
          }
        }
        setState(() {
          _filterOptions = loadedFilterOptions;
          _updateCurrentFilters();
          _isLoadingFilters = false;
        });
      } else {
        print('Failed to fetch filters. Status code: ${response.statusCode}');
        setState(() {
          _filterOptions = {
            'cat': [],
            'atype': [],
            'species': [],
            'gender': [],
          };
          _isLoadingFilters = false;
        });
      }
    } catch (e) {
      print('Error fetching filter data: $e');
      setState(() {
        _filterOptions = {
          'cat': [],
          'atype': [],
          'species': [],
          'gender': [],
        };
        _isLoadingFilters = false;
      });
    }
  }


  void _updateCurrentFilters() {
    _filterOptions.forEach((filterName, options) {
      if (options.isNotEmpty &&
          (currentFilters[filterName] == 'Unknown' ||
              currentFilters[filterName] == null)) {
        currentFilters[filterName] = options.first['value']!;
      }
    });
  }


  String getFilterLabel(String filterName, String valueCode) {
    final options = _filterOptions[filterName];
    if (options == null || options.isEmpty || valueCode == 'Unknown') {
      return 'Loading...';
    }
    final match = options.firstWhere(
          (option) => option['value'] == valueCode,
      orElse: () => {'label': 'Unknown'},
    );
    return match['label']!;
  }


  Map<String, String> getMappedFilters() {
    final mapped = <String, String>{};
    filterDisplayNames.forEach((internalKey, displayLabel) {
      mapped[displayLabel] = currentFilters[internalKey] ?? 'Unknown';
    });
    mapped['rating-general'] = _ratingGeneral ? '1' : '0';
    mapped['rating-mature'] = _ratingMature ? '1' : '0';
    mapped['rating-adult'] = _ratingAdult ? '1' : '0';
    return mapped;
  }

  @override
  Widget build(BuildContext context) {
    // While filters are loading, shows a loading indicator.
    if (_isLoadingFilters) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Filters'),
        ),
        body: Center(child: PulsatingLoadingIndicator(size: 108.0, assetPath: 'assets/icons/fathemed.png'))



      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Filters'),
        actions: [
          IconButton(
            icon: const Icon(Icons.check, color: applyButtonColor),
            onPressed: () {
              Navigator.pop(context, getMappedFilters());
            },
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            child: SingleChildScrollView(
              child: Padding(
                padding:
                const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
                child: Column(
                  children: <Widget>[

                    ...filterDisplayNames.entries.map((entry) {
                      return Column(
                        children: [
                          buildFilterButton(
                              context, entry.key, entry.value),
                          const SizedBox(height: 20),
                        ],
                      );
                    }).toList(),

                    const SizedBox(height: 10),
                    Container(
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.only(bottom: 5),
                      child: const Text(
                        'Filter by Rating',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ),

                    buildRatingCheckbox(
                      label: 'General',
                      value: _ratingGeneral,
                      onChanged: (bool? newVal) {
                        setState(() {
                          _ratingGeneral = newVal ?? true;
                        });
                      },
                    ),
                    buildRatingCheckbox(
                      label: 'Mature',
                      value: _ratingMature,
                      onChanged: (bool? newVal) {
                        setState(() {
                          _ratingMature = newVal ?? true;
                        });
                      },
                    ),
                    buildRatingCheckbox(
                      label: 'Adult',
                      value: _ratingAdult,
                      onChanged: (bool? newVal) {
                        setState(() {
                          _ratingAdult = newVal ?? true;
                        });
                      },
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ),
          const Divider(
            height: 3.0,
            color: Colors.black,
            thickness: 3.0,
          ),
          Padding(
            padding:
            const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Row(
              children: [
                // Reset Button
                Expanded(
                  child: Container(
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(24.0),
                      border: Border.all(color: applyButtonColor),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(24.0),
                        onTap: () {
                          setState(() {
                            // Reset standard filters.
                            currentFilters['cat'] = '1';
                            currentFilters['atype'] = '1';
                            currentFilters['species'] = '1';
                            currentFilters['gender'] = '0';
                            // Reset rating filters.
                            _ratingGeneral = true;
                            _ratingMature = true;
                            _ratingAdult = true;
                          });
                          Navigator.pop(context, getMappedFilters());
                        },
                        child: const Center(
                          child: Text(
                            'Reset',
                            style: TextStyle(
                              fontWeight: FontWeight.w500,
                              fontSize: 18,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                // Apply Button
                Expanded(
                  child: Container(
                    height: 48,
                    decoration: BoxDecoration(
                      color: applyButtonColor,
                      borderRadius: BorderRadius.circular(24.0),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(24.0),
                        onTap: () {
                          Navigator.pop(context, getMappedFilters());
                        },
                        child: const Center(
                          child: Text(
                            'Apply',
                            style: TextStyle(
                              fontWeight: FontWeight.w500,
                              fontSize: 18,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }


  Widget buildFilterButton(BuildContext context, String internalKey, String displayLabel) {
    String selectedValueCode = currentFilters[internalKey] ?? 'Unknown';
    String selectedValueLabel = getFilterLabel(internalKey, selectedValueCode);

    return TextButton(
      onPressed: () {
        _showFilterDialog(context, internalKey, selectedValueCode);
      },
      style: TextButton.styleFrom(
        padding:
        const EdgeInsets.symmetric(vertical: 16.0, horizontal: 24.0),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8.0),
          side: const BorderSide(color: applyButtonColor),
        ),
        backgroundColor: Colors.black,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            displayLabel,
            style: const TextStyle(
              fontSize: 16.0,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          Text(
            selectedValueLabel,
            style: const TextStyle(
              fontSize: 16.0,
              fontWeight: FontWeight.w400,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }


  Widget buildRatingCheckbox({
    required String label,
    required bool value,
    required Function(bool?) onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Checkbox(
            activeColor: applyButtonColor,
            value: value,
            onChanged: onChanged,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 16,
              color: value ? applyButtonColor : Colors.white,
            ),
          ),
        ],
      ),
    );
  }


  void _showFilterDialog(
      BuildContext context, String filterType, String selectedValueCode) async {
    String dialogTitle = 'Select ${filterDisplayNames[filterType]}';

    final selectedValue = await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.6,
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(
                    dialogTitle,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 20,
                    ),
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _filterOptions[filterType]?.length ?? 0,
                    itemBuilder: (context, index) {
                      String optionLabel =
                      _filterOptions[filterType]![index]['label']!;
                      String optionValue =
                      _filterOptions[filterType]![index]['value']!;
                      return RadioListTile<String>(
                        title: Text(optionLabel),
                        value: optionValue,
                        groupValue: currentFilters[filterType],
                        onChanged: (String? value) {
                          Navigator.of(context).pop(value);
                        },
                      );
                    },
                  ),
                ),
                const Divider(height: 1),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                    child: const Text('Close'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (selectedValue != null) {
      setState(() {
        currentFilters[filterType] = selectedValue;
      });
    }
  }
}
