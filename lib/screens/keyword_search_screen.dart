// keyword_search_screen.dart
import 'package:flutter/material.dart';
import 'package:FANotifier/screens/fasearchimage.dart';
import 'search_filters_screen.dart';


class KeywordSearchScreen extends StatefulWidget {
  final String initialKeyword;

  const KeywordSearchScreen({required this.initialKeyword, Key? key}) : super(key: key);

  @override
  _KeywordSearchScreenState createState() => _KeywordSearchScreenState();
}

class _KeywordSearchScreenState extends State<KeywordSearchScreen> {
  late TextEditingController _searchController;
  late String _currentSearchQuery;
  late Map<String, String> _currentSearchFilters;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: widget.initialKeyword);
    _currentSearchQuery = widget.initialKeyword;
    _currentSearchFilters = {
      'order-by': 'relevancy',
      'order-direction': 'desc',
      'range': '5years',
      'mode': 'extended',
      'rating_general': '1',
      'rating_mature': '1',
      'rating_adult': '1',
      'type_art': '1',
      'type_music': '1',
      'type_flash': '1',
      'type_story': '1',
      'type_photo': '1',
      'type_poetry': '1',
    };
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Handles the search action when the user presses the search icon or submits the query.
  void _handleSearch() {
    String newQuery = _searchController.text.trim();
    if (newQuery.isNotEmpty && newQuery != _currentSearchQuery) {
      setState(() {
        _currentSearchQuery = newQuery;
      });
    } else if (newQuery.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a search query.')),
      );
    }
    // If the query is the same, does nothing to prevent unnecessary refreshes.
  }

  /// Handles the filter application and updates the search results accordingly.
  Future<void> _handleFilterApply() async {
    final updatedFilters = await Navigator.push<Map<String, String>>(
      context,
      MaterialPageRoute(
        builder: (context) => SearchFiltersScreen(
          selectedSearchFilters: _currentSearchFilters,
          searchFilterOptions: {
            'order-by': [
              {'label': 'Relevancy', 'value': 'relevancy'},
              {'label': 'Date', 'value': 'date'},
              {'label': 'Popularity', 'value': 'popularity'},
            ],
            'order-direction': [
              {'label': 'Descending', 'value': 'desc'},
              {'label': 'Ascending', 'value': 'asc'},
            ],
            'range': [
              {'label': '1 Day', 'value': '1day'},
              {'label': '3 Days', 'value': '3days'},
              {'label': '7 Days', 'value': '7days'},
              {'label': '30 Days', 'value': '30days'},
              {'label': '90 Days', 'value': '90days'},
              {'label': '1 Year', 'value': '1year'},
              {'label': '3 Years', 'value': '3years'},
              {'label': '5 Years', 'value': '5years'},
              {'label': 'All Time', 'value': 'all'},
              {'label': 'Manual', 'value': 'manual'},
            ],
            'mode': [
              {'label': 'All', 'value': 'all'},
              {'label': 'Any', 'value': 'any'},
              {'label': 'Extended', 'value': 'extended'},
            ],
            'rating_general': [
              {'label': 'General', 'value': '1'},
            ],
            'rating_mature': [
              {'label': 'Mature', 'value': '1'},
            ],
            'rating_adult': [
              {'label': 'Adult', 'value': '1'},
            ],
            'type_art': [
              {'label': 'Art', 'value': '1'},
            ],
            'type_music': [
              {'label': 'Music', 'value': '1'},
            ],
            'type_flash': [
              {'label': 'Flash', 'value': '1'},
            ],
            'type_story': [
              {'label': 'Story', 'value': '1'},
            ],
            'type_photo': [
              {'label': 'Photo', 'value': '1'},
            ],
            'type_poetry': [
              {'label': 'Poetry', 'value': '1'},
            ],
          },
        ),
      ),
    );

    if (updatedFilters != null) {
      setState(() {
        _currentSearchFilters = updatedFilters;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(8.0),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        decoration: const InputDecoration(
                          hintText: 'Search...',
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.only(left: 10.0),
                        ),
                        onSubmitted: (value) => _handleSearch(),
                        maxLines: 1,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.search),
                      onPressed: _handleSearch,
                    ),
                  ],
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.filter_list),
              onPressed: _handleFilterApply,
            ),
          ],
        ),
      ),


      body: FASearchImage(
        selectedFilters: _currentSearchFilters,
        searchQuery: _currentSearchQuery,
      ),
    );
  }
}
