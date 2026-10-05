
import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:fanotifier/features/search/presentation/search_results_grid.dart';
import 'package:fanotifier/features/search/presentation/search_filters_screen.dart';
import 'package:fanotifier/core/analytics/app_screen.dart';
import 'package:fanotifier/shared/widgets/scroll_return_controller.dart';

class SearchScreen extends StatefulWidget {
  final Map<String, String> searchFilters;
  final bool sfwEnabled;
  final ScrollReturnActionPort? scrollActionPort;
  final Function(Map<String, String>) onFilterUpdated;

  const SearchScreen({
    required this.searchFilters,
    required this.sfwEnabled,
    required this.onFilterUpdated,
    this.scrollActionPort,
    super.key,
  });

  @override
  SearchScreenState createState() => SearchScreenState();
}

class SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;
  String _currentSearchQuery = '';
  final GlobalKey<SearchResultsGridState> _resultsKey =
      GlobalKey<SearchResultsGridState>();

  @override
  void initState() {
    super.initState();
    widget.scrollActionPort?.bind(_scrollFromNavigation, _cancelNavigationScroll);
  }

  @override
  void didUpdateWidget(covariant SearchScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scrollActionPort != widget.scrollActionPort) {
      oldWidget.scrollActionPort?.unbind(_scrollFromNavigation);
      widget.scrollActionPort?.bind(_scrollFromNavigation, _cancelNavigationScroll);
    }
  }

  @override
  void dispose() {
    widget.scrollActionPort?.unbind(_scrollFromNavigation);
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

  Future<void> scrollToTop() async {
    await _resultsKey.currentState?.scrollToTop();
  }

  Future<void> _scrollFromNavigation(
    ValueChanged<ScrollReturnDirection> onStarted,
  ) async {
    await _resultsKey.currentState?.scrollFromNavigation(onStarted);
  }

  void _cancelNavigationScroll() {
    _resultsKey.currentState?.cancelNavigationScroll();
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
                height: 46,
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
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 16.0,
                            vertical: 0.0,
                          ),
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
                            const SnackBar(
                                content: Text('Please enter a search query.')),
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
                    settings:
                        const AnalyticsRouteSettings(AppScreens.searchFilters),
                    builder: (context) => SearchFiltersScreen(
                      selectedSearchFilters: widget.searchFilters,
                      sfwEnabled: widget.sfwEnabled,
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
          : SearchResultsGrid(
              key: _resultsKey,
              selectedFilters: widget.searchFilters,
              searchQuery: _currentSearchQuery,
            ),
    );
  }
}
