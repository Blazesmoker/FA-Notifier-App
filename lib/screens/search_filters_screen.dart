// lib/hotel_booking/search_filters_screen.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class SearchFiltersScreen extends StatefulWidget {
  final Map<String, String> selectedSearchFilters;
  final Map<String, List<Map<String, String>>> searchFilterOptions;

  SearchFiltersScreen({
    required this.selectedSearchFilters,
    required this.searchFilterOptions,
    Key? key,
  }) : super(key: key);

  @override
  _SearchFiltersScreenState createState() => _SearchFiltersScreenState();
}

class _SearchFiltersScreenState extends State<SearchFiltersScreen> {

  final Color _applyButtonColor = const Color(0xFFE09321);

  late Map<String, String> currentSearchFilters;
  DateTime? fromDate;
  DateTime? toDate;

  @override
  void initState() {
    super.initState();
    currentSearchFilters = Map<String, String>.from(widget.selectedSearchFilters);


    currentSearchFilters['rating-general'] ??= '1';
    currentSearchFilters['rating-mature'] ??= '1';
    currentSearchFilters['rating-adult'] ??= '1';


    if (currentSearchFilters['mode'] == null || currentSearchFilters['mode']!.isEmpty) {
      currentSearchFilters['mode'] = 'extended';
    }


    if (currentSearchFilters['range'] == 'manual') {
      if (currentSearchFilters['range_from'] != null && currentSearchFilters['range_from']!.isNotEmpty) {
        fromDate = DateFormat('yyyy-MM-dd').parse(currentSearchFilters['range_from']!);
      }
      if (currentSearchFilters['range_to'] != null && currentSearchFilters['range_to']!.isNotEmpty) {
        toDate = DateFormat('yyyy-MM-dd').parse(currentSearchFilters['range_to']!);
      }
    }
  }

  Future<void> _editManualDates() async {
    bool finishedEditing = false;

    while (!finishedEditing) {

      final fieldToEdit = await showDialog<String>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: Text('Select Date Range'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildDateFieldChooser('From', fromDate, dialogContext, 'from'),
                SizedBox(height: 10),
                _buildDateFieldChooser('To', toDate, dialogContext, 'to'),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                },
                child: Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () async {

                  if (fromDate != null && toDate != null && fromDate!.isAfter(toDate!)) {

                    await showDialog(
                      context: dialogContext,
                      builder: (errorContext) {
                        return AlertDialog(
                          title: Text('Invalid Date Range'),
                          content: Text('"From" date cannot be after "To" date.'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(errorContext).pop(),
                              child: Text('OK'),
                            ),
                          ],
                        );
                      },
                    );
                    return;
                  }


                  Navigator.of(dialogContext).pop(null);
                },
                child: Text('Apply'),
              ),
            ],
          );
        },
      );


      if (fieldToEdit == null) {

        finishedEditing = true;
      } else {

        DateTime initialDate = (fieldToEdit == 'from' ? fromDate : toDate) ?? DateTime.now();


        await Future.delayed(Duration.zero);

        final pickedDate = await showDatePicker(
          context: context,
          initialDate: initialDate,
          firstDate: DateTime(1900),
          lastDate: DateTime.now(),
        );

        if (pickedDate != null) {
          setState(() {
            if (fieldToEdit == 'from') {
              fromDate = pickedDate;
            } else {
              toDate = pickedDate;
            }
          });

        }
      }
    }


    currentSearchFilters['range_from'] = fromDate != null ? DateFormat('yyyy-MM-dd').format(fromDate!) : '';
    currentSearchFilters['range_to'] = toDate != null ? DateFormat('yyyy-MM-dd').format(toDate!) : '';
  }

  Widget _buildDateFieldChooser(String label, DateTime? date, BuildContext context, String fieldKey) {
    return Row(
      children: [
        Text(label, style: TextStyle(fontSize: 14)),
        SizedBox(width: 16),
        Expanded(
          child: InkWell(
            onTap: () {

              Navigator.of(context).pop(fieldKey);
            },
            child: InputDecorator(
              decoration: InputDecoration(
                contentPadding: EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    date != null ? DateFormat('dd.MM.yyyy').format(date) : 'Select Date',
                    style: TextStyle(fontSize: 14),
                  ),
                  Icon(Icons.calendar_today, size: 18),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Search Filters'),
        actions: [
          IconButton(
            icon: Icon(Icons.check),
            onPressed: () {
              Navigator.pop(context, currentSearchFilters);
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _buildSortCriteria(),
            SizedBox(height: 20),
            _buildSortByRange(),
            SizedBox(height: 20),
            _buildSortByRating(),
            SizedBox(height: 20),
            _buildSortByType(),
            SizedBox(height: 20),
            _buildSortByKeywords(),
            SizedBox(height: 40),
            _buildAdditionalText(),
          ],
        ),
      ),
      bottomNavigationBar: _buildApplyResetButtons(),
    );
  }

  Widget _buildSortCriteria() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Sort Criteria', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        Row(
          children: [
            DropdownButton<String>(
              value: currentSearchFilters['order-by'],
              onChanged: (String? newValue) {
                setState(() {
                  currentSearchFilters['order-by'] = newValue!;
                });
              },
              items: ['relevancy', 'date', 'popularity'].map((String value) {
                return DropdownMenuItem<String>(
                  value: value,
                  child: Text(value.capitalize()),
                );
              }).toList(),
            ),
            Text(' in '),
            DropdownButton<String>(
              value: currentSearchFilters['order-direction'],
              onChanged: (String? newValue) {
                setState(() {
                  currentSearchFilters['order-direction'] = newValue!;
                });
              },
              items: [
                DropdownMenuItem<String>(
                  value: 'desc',
                  child: Text('Descending'),
                ),
                DropdownMenuItem<String>(
                  value: 'asc',
                  child: Text('Ascending'),
                ),
              ],
            ),
            Text(' order'),
          ],
        ),
      ],
    );
  }

  Widget _buildSortByRange() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Sort by Range', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        SizedBox(height: 8),
        Wrap(
          spacing: 12.0,
          runSpacing: 8.0,
          children: [
            _buildRadioOption('1 Day', 'range', '1day'),
            _buildRadioOption('3 Days', 'range', '3days'),
            _buildRadioOption('7 Days', 'range', '7days'),
            _buildRadioOption('30 Days', 'range', '30days'),
            _buildRadioOption('90 Days', 'range', '90days'),
            _buildRadioOption('1 Year', 'range', '1year'),
            _buildRadioOption('3 Years', 'range', '3years'),
            _buildRadioOption('5 Years', 'range', '5years'),
            _buildRadioOption('All Time', 'range', 'all'),
            _buildRadioOption('Manual', 'range', 'manual'),
          ],
        ),
        if (currentSearchFilters['range'] == 'manual') ...[
          SizedBox(height: 10),
          Row(
            children: [
              Text(
                'From: ${fromDate != null ? DateFormat('dd.MM.yyyy').format(fromDate!) : 'Not set'}',
                style: TextStyle(fontSize: 14),
              ),
              SizedBox(width: 20),
              Text(
                'To: ${toDate != null ? DateFormat('dd.MM.yyyy').format(toDate!) : 'Not set'}',
                style: TextStyle(fontSize: 14),
              ),
              SizedBox(width: 20),
              IconButton(
                icon: Icon(Icons.edit),
                onPressed: _editManualDates,
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildSortByRating() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Sort by Rating', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        Wrap(
          spacing: 8.0,
          children: [
            _buildCheckboxOption('General', 'rating-general', '1'),
            _buildCheckboxOption('Mature', 'rating-mature', '1'),
            _buildCheckboxOption('Adult', 'rating-adult', '1'),
          ],
        ),
      ],
    );
  }

  Widget _buildSortByType() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Sort by Type', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        Wrap(
          spacing: 8.0,
          children: [
            _buildCheckboxOption('Art', 'type-art', '1'),
            _buildCheckboxOption('Music', 'type-music', '1'),
            _buildCheckboxOption('Story', 'type-story', '1'),
            _buildCheckboxOption('Photos', 'type-photo', '1'),
            _buildCheckboxOption('Flash', 'type-flash', '1'),
            _buildCheckboxOption('Poetry', 'type-poetry', '1'),
          ],
        ),
      ],
    );
  }

  Widget _buildSortByKeywords() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Sort by Matching Keywords', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        _buildRadioOption('All of the words', 'mode', 'all'),
        _buildRadioOption('Any of the words', 'mode', 'any'),
        _buildRadioOption('Extended (See "Advanced")', 'mode', 'extended'),
      ],
    );
  }

  Widget _buildRadioOption(String label, String filterKey, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Radio<String>(
          activeColor: _applyButtonColor,
          value: value,
          groupValue: currentSearchFilters[filterKey],
          onChanged: (String? newValue) async {
            setState(() {
              currentSearchFilters[filterKey] = newValue!;
            });
            if (filterKey == 'range' && newValue == 'manual') {

              WidgetsBinding.instance.addPostFrameCallback((_) async {
                await _editManualDates();
              });
            } else if (filterKey == 'range') {
              setState(() {
                fromDate = null;
                toDate = null;
                currentSearchFilters['range_from'] = '';
                currentSearchFilters['range_to'] = '';
              });
            }
          },
        ),
        Text(
          label,
          style: TextStyle(

            color: currentSearchFilters[filterKey] == value ? _applyButtonColor : Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _buildCheckboxOption(String label, String filterKey, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Checkbox(
          activeColor: _applyButtonColor,
          value: currentSearchFilters[filterKey] == value,
          onChanged: (bool? checked) {
            setState(() {
              currentSearchFilters[filterKey] = checked! ? value : '0';
            });
          },
        ),
        Text(
          label,
          style: TextStyle(

            color: currentSearchFilters[filterKey] == value ? _applyButtonColor : Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _buildApplyResetButtons() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Row(
        children: [
          // Reset Button
          Expanded(
            child: Container(
              height: 48,
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(24.0),
                border: Border.all(color: _applyButtonColor),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(24.0),
                  highlightColor: Colors.transparent,
                  onTap: () {
                    setState(() {
                      currentSearchFilters = {
                        'order-by': 'relevancy',
                        'order-direction': 'desc',
                        'range': '5years',
                        'mode': 'extended',
                        'rating-general': '1',
                        'rating-mature': '1',
                        'rating-adult': '1',
                        'type-art': '1',
                        'type-music': '1',
                        'type-story': '1',
                        'type-photo': '1',
                        'type-flash': '1',
                        'type-poetry': '1',
                      };
                      fromDate = null;
                      toDate = null;
                      currentSearchFilters['range'] = '5years';
                      currentSearchFilters['range_from'] = '';
                      currentSearchFilters['range_to'] = '';
                    });
                    Navigator.pop(context, currentSearchFilters);
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
                color: _applyButtonColor,
                borderRadius: BorderRadius.circular(24.0),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(24.0),
                  highlightColor: Colors.transparent,
                  onTap: () {
                    Navigator.pop(context, currentSearchFilters);
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
    );
  }

  Widget _buildAdditionalText() {
    return Text(
      '''
Advanced:

Search understands basic boolean operators:
AND: hello & world
OR : hello | world
NOT: hello -world -or- hello !world
Grouping: (hello world)
Example: ( cat -dog ) | ( cat -mouse )

Capabilities
Field searching: @title hello @message world
Phrase searching: "hello world"
Word proximity searching: "hello world"~10
Quorum matching: "the world is a wonderful place"/3
Example: "hello world" @title "example program"~5 @message python -(php|perl)

Available Fields
@title
@message
@filename
@lower (artist name as it appears in their userpage URL)
@keywords
Example: fender @title fender -dragoneer -ferrox @message -rednef -dragoneer
      ''',
      style: TextStyle(fontSize: 14, color: Colors.white),
    );
  }
}

extension StringExtension on String {
  String capitalize() {
    if (isEmpty) return this;
    return this[0].toUpperCase() + substring(1);
  }
}
