import 'dart:async';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:fanotifier/features/browse/domain/browse_repository.dart';
import 'package:fanotifier/features/browse/domain/browse_filter_display_names.dart';
import 'package:fanotifier/shared/fa/domain/fa_filter_options.dart';
import 'package:fanotifier/shared/fa/domain/fa_page_settings.dart';
import 'package:fanotifier/shared/utils/content_rating_filters.dart';
import 'package:fanotifier/shared/widgets/pulsating_loading_indicator.dart';
import 'package:fanotifier/shared/widgets/fa_pagination_filter_fields.dart';

class FiltersScreen extends StatefulWidget {
  /// Pass in the currently selected filters.
  final Map<String, String> selectedFilters;
  final bool sfwEnabled;
  final Future<void> Function()? onRetry;

  const FiltersScreen({
    required this.selectedFilters,
    required this.sfwEnabled,
    this.onRetry,
    super.key,
  });

  @override
  State<FiltersScreen> createState() => _FiltersScreenState();
}

class _FiltersScreenState extends State<FiltersScreen> {
  late Map<String, String> currentFilters;
  late final TextEditingController _pageController;
  final _paginationFormKey = GlobalKey<FormState>();
  FaFilterOptions? _filterDefinitions;

  bool _isLoadingFilters = true;
  bool _filterLoadFailed = false;
  StreamSubscription<FaFilterOptions>? _filterSubscription;

  Map<String, List<Map<String, String>>> _filterOptions = {};

  static const Color applyButtonColor = Color(0xFFE09321);

  bool _ratingGeneral = true;
  bool _ratingMature = true;
  bool _ratingAdult = true;

  @override
  void initState() {
    super.initState();

    final selectedFilters = ContentRatingFilters.normalizeBrowseFilters(
      widget.selectedFilters,
      sfwEnabled: widget.sfwEnabled,
    );

    currentFilters = {};
    browseFilterDisplayNames.forEach((internalKey, displayLabel) {
      currentFilters[internalKey] = selectedFilters[displayLabel]!;
    });
    currentFilters[FaPageSettings.perPageKey] =
        selectedFilters[FaPageSettings.perPageKey]!;
    _pageController = TextEditingController(
      text: selectedFilters[FaPageSettings.pageKey],
    );

    _ratingGeneral =
        selectedFilters[ContentRatingFilters.ratingGeneralKey] == '1';
    _ratingMature =
        selectedFilters[ContentRatingFilters.ratingMatureKey] == '1';
    _ratingAdult = selectedFilters[ContentRatingFilters.ratingAdultKey] == '1';

    final repository = context.read<BrowseRepository>();
    _filterSubscription = repository.filterOptionsChanges.listen((options) {
      if (!mounted) return;
      setState(() => _acceptFilterOptions(options));
    });
    final cachedOptions = repository.filterOptions;
    if (cachedOptions != null) {
      _acceptFilterOptions(cachedOptions);
    } else {
      unawaited(_fetchFilterData());
    }
  }

  void _acceptFilterOptions(FaFilterOptions options) {
    _filterDefinitions = options;
    _filterOptions = {
      for (final entry in options.groups.entries)
        entry.key: [
          for (final option in entry.value)
            {'label': option.label, 'value': option.value},
        ],
    };
    _updateCurrentFilters();
    _isLoadingFilters = false;
    _filterLoadFailed = false;
  }

  Future<void> _fetchFilterData({bool retry = false}) async {
    final repository = context.read<BrowseRepository>();
    setState(() {
      _isLoadingFilters = true;
      _filterLoadFailed = false;
    });
    try {
      if (retry && repository.filterOptions == null) {
        await widget.onRetry?.call();
      }
      final options = await repository.fetchFilterOptions();
      if (!mounted || !_isLoadingFilters) return;
      setState(() => _acceptFilterOptions(options));
    } catch (_) {
      if (!mounted || _filterOptions.isNotEmpty) return;
      setState(() {
        _isLoadingFilters = false;
        _filterLoadFailed = true;
      });
    }
  }

  @override
  void dispose() {
    _filterSubscription?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  void _updateCurrentFilters() {
    _filterOptions.forEach((filterName, options) {
      if (options.isEmpty) return;

      final current = currentFilters[filterName];
      final hasMatch = options.any((o) => o['value'] == current);

      if (current == null || current == 'Unknown' || !hasMatch) {
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
    return ContentRatingFilters.normalizeBrowseFilters(
      {
        'Category': currentFilters['cat'] ?? '1',
        'Type': currentFilters['atype'] ?? '1',
        'Species': currentFilters['species'] ?? '1',
        'Gender': currentFilters['gender'] ?? '0',
        FaPageSettings.pageKey: _pageController.text,
        FaPageSettings.perPageKey:
            FaPageSettings.resultsPerPage(currentFilters),
        ContentRatingFilters.ratingGeneralKey: _ratingGeneral ? '1' : '0',
        ContentRatingFilters.ratingMatureKey: _ratingMature ? '1' : '0',
        ContentRatingFilters.ratingAdultKey: _ratingAdult ? '1' : '0',
      },
      sfwEnabled: widget.sfwEnabled,
    );
  }

  void _applyFilters() {
    if (_paginationFormKey.currentState?.validate() != true) {
      return;
    }
    Navigator.pop(context, getMappedFilters());
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingFilters || _filterLoadFailed) {
      return Scaffold(
        appBar: AppBar(title: const Text('Filters')),
        body: SafeArea(
          child: Center(
            child: _isLoadingFilters
                ? const PulsatingLoadingIndicator(
                    size: 108.0,
                    assetPath: 'assets/icons/fathemed.png',
                  )
                : Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Could not load Browse filters. Retry loading the Browse page.',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        TextButton(
                          onPressed: () => _fetchFilterData(retry: true),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Filters'),
        actions: [
          IconButton(
            icon: const Icon(Icons.check, color: applyButtonColor),
            onPressed: _applyFilters,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Expanded(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16.0, vertical: 16.0),
                  child: Column(
                    children: <Widget>[
                      ...browseFilterDisplayNames.entries.map((entry) {
                        return Column(
                          children: [
                            buildFilterButton(context, entry.key, entry.value),
                            const SizedBox(height: 20),
                          ],
                        );
                      }),
                      FaPaginationFilterFields(
                        formKey: _paginationFormKey,
                        pageController: _pageController,
                        resultsPerPage:
                            currentFilters[FaPageSettings.perPageKey]!,
                        resultsPerPageOptions:
                            _filterDefinitions![FaPageSettings.perPageKey],
                        onResultsPerPageChanged: (value) {
                          setState(() {
                            currentFilters[FaPageSettings.perPageKey] = value;
                          });
                        },
                      ),
                      const SizedBox(height: 20),
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
                            final defaults =
                                ContentRatingFilters.defaultBrowseFilters(
                                    sfwEnabled: widget.sfwEnabled);
                            setState(() {
                              currentFilters['cat'] = defaults['Category']!;
                              currentFilters['atype'] = defaults['Type']!;
                              currentFilters['species'] = defaults['Species']!;
                              currentFilters['gender'] = defaults['Gender']!;
                              currentFilters[FaPageSettings.perPageKey] =
                                  defaults[FaPageSettings.perPageKey]!;
                              _pageController.text =
                                  defaults[FaPageSettings.pageKey]!;
                              _updateCurrentFilters();
                              _ratingGeneral = defaults[
                                      ContentRatingFilters.ratingGeneralKey] ==
                                  '1';
                              _ratingMature = defaults[
                                      ContentRatingFilters.ratingMatureKey] ==
                                  '1';
                              _ratingAdult = defaults[
                                      ContentRatingFilters.ratingAdultKey] ==
                                  '1';
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
                          onTap: _applyFilters,
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
      ),
    );
  }

  Widget buildFilterButton(
      BuildContext context, String internalKey, String displayLabel) {
    String selectedValueCode = currentFilters[internalKey] ?? 'Unknown';
    String selectedValueLabel = getFilterLabel(internalKey, selectedValueCode);

    return TextButton(
      onPressed: () {
        _showFilterDialog(context, internalKey, selectedValueCode);
      },
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 24.0),
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
    String dialogTitle = 'Select ${browseFilterDisplayNames[filterType]}';

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
                  child: RadioGroup<String>(
                    groupValue: currentFilters[filterType],
                    onChanged: (String? value) {
                      Navigator.of(context).pop(value);
                    },
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
                        );
                      },
                    ),
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
