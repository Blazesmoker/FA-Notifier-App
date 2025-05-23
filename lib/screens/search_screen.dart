// lib/hotel_booking/search_screen.dart

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'fasearchimage.dart';
import 'search_filters_screen.dart';

class SearchScreen extends StatefulWidget {
  final Map<String, String> searchFilters;
  final Function(Map<String, String>) onFilterUpdated;

  const SearchScreen({
    required this.searchFilters,
    required this.onFilterUpdated,
    Key? key,
  }) : super(key: key);

  @override
  _SearchScreenState createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;
  String _currentSearchQuery = '';

  @override
  void initState() {
    super.initState();

  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    if (_searchDebounce?.isActive ?? false) _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(seconds: 1), () {
      if (query.trim().isNotEmpty) {
        setState(() {
          _currentSearchQuery = query.trim();
        });
      } else {
        setState(() {
          _currentSearchQuery = '';
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const SizedBox(width: 48),
            Expanded(
              flex: 8,
              child: Container(
                decoration: BoxDecoration(
                  color: Color(0xFF2C2C2C),
                  borderRadius: BorderRadius.circular(8.0),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          hintText: 'Search...',
                          hintStyle: TextStyle(color: Colors.grey),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(horizontal: 16.0),
                        ),
                        onChanged: _onSearchChanged,
                      ),

                    ),
                    IconButton(
                      icon: const Icon(Icons.search),
                      onPressed: () {
                        String query = _searchController.text.trim();
                        if (query.isNotEmpty) {
                          setState(() {
                            _currentSearchQuery = query;
                          });
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Please enter a search query.')),
                          );
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.filter_list),
              onPressed: () async {
                final updatedSearchFilters =
                await Navigator.push<Map<String, String>>(
                  context,
                  MaterialPageRoute(
                    builder: (context) => SearchFiltersScreen(
                      selectedSearchFilters: widget.searchFilters,
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
                        'rating-general': [
                          {'label': 'General', 'value': '1'},
                        ],
                        'rating-mature': [
                          {'label': 'Mature', 'value': '1'},
                        ],
                        'rating-adult': [
                          {'label': 'Adult', 'value': '1'},
                        ],
                        'type-art': [
                          {'label': 'Art', 'value': '1'},
                        ],
                        'type-music': [
                          {'label': 'Music', 'value': '1'},
                        ],
                        'type-flash': [
                          {'label': 'Flash', 'value': '1'},
                        ],
                        'type-story': [
                          {'label': 'Story', 'value': '1'},
                        ],
                        'type-photo': [
                          {'label': 'Photo', 'value': '1'},
                        ],
                        'type-poetry': [
                          {'label': 'Poetry', 'value': '1'},
                        ],
                      },
                    ),
                  ),
                );
                if (updatedSearchFilters != null) {
                  widget.onFilterUpdated(updatedSearchFilters);
                }
              },
            ),
          ],
        ),
        centerTitle: false,
      ),
      body: _currentSearchQuery.isEmpty
          ? const Center(
        child: Text('Enter a search query and apply filters.'),
      )
          : FASearchImage(
        selectedFilters: widget.searchFilters,
        searchQuery: _currentSearchQuery,
      ),
    );
  }
}
