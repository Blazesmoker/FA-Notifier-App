import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:fanotifier/features/auth/presentation/cloudflare_check_screen.dart';
import 'package:fanotifier/features/search/domain/search_filter_date_range.dart';
import 'package:fanotifier/features/search/domain/search_filter_options.dart';
import 'package:fanotifier/features/search/domain/search_repository.dart';
import 'package:fanotifier/shared/fa/cloudflare_challenge_exception.dart';
import 'package:fanotifier/shared/fa/domain/fa_filter_options.dart';
import 'package:fanotifier/shared/fa/domain/fa_page_settings.dart';
import 'package:fanotifier/shared/utils/content_rating_filters.dart';
import 'package:fanotifier/shared/utils/string_extensions.dart';
import 'package:fanotifier/shared/widgets/pulsating_loading_indicator.dart';
import 'package:fanotifier/shared/widgets/fa_pagination_filter_fields.dart';

class SearchFiltersScreen extends StatefulWidget {
  final Map<String, String> selectedSearchFilters;
  final bool sfwEnabled;

  const SearchFiltersScreen({
    required this.selectedSearchFilters,
    required this.sfwEnabled,
    super.key,
  });

  @override
  State<SearchFiltersScreen> createState() => _SearchFiltersScreenState();
}

class _SearchFiltersScreenState extends State<SearchFiltersScreen> {
  final Color _applyButtonColor = const Color(0xFFE09321);

  late Map<String, String> currentSearchFilters;
  late final TextEditingController _pageController;
  final _paginationFormKey = GlobalKey<FormState>();
  DateTime? fromDate;
  DateTime? toDate;
  FaFilterOptions? _filterOptions;
  StreamSubscription<FaFilterOptions>? _filterSubscription;
  bool _isLoadingFilters = true;
  bool _filterLoadFailed = false;

  @override
  void initState() {
    super.initState();
    currentSearchFilters = ContentRatingFilters.normalizeSearchFilters(
      widget.selectedSearchFilters,
      sfwEnabled: widget.sfwEnabled,
    );
    _pageController = TextEditingController(
      text: currentSearchFilters[FaPageSettings.pageKey],
    );

    if (currentSearchFilters['mode'] == null ||
        currentSearchFilters['mode']!.isEmpty) {
      currentSearchFilters['mode'] = 'extended';
    }

    if (currentSearchFilters['range'] == 'manual') {
      fromDate = parseSearchFilterDate(currentSearchFilters['range_from']);
      toDate = parseSearchFilterDate(currentSearchFilters['range_to']);
    }
    final repository = context.read<SearchRepository>();
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
    _filterOptions = options;
    _updateCurrentFilters();
    _isLoadingFilters = false;
    _filterLoadFailed = false;
  }

  void _updateCurrentFilters() {
    final options = _filterOptions;
    if (options == null) return;
    for (final name in [
      SearchFilterGroups.orderBy,
      SearchFilterGroups.orderDirection,
      SearchFilterGroups.range,
      SearchFilterGroups.mode,
      SearchFilterGroups.perPage,
    ]) {
      final choices = options[name];
      if (!choices.any((option) => option.value == currentSearchFilters[name])) {
        currentSearchFilters[name] = choices.first.value;
      }
    }
    for (final option in options[SearchFilterGroups.gender]) {
      currentSearchFilters[option.field] ??= '0';
    }
    for (final option in options[SearchFilterGroups.type]) {
      currentSearchFilters[option.field] ??= option.value;
    }
    for (final option in options[SearchFilterGroups.rating]) {
      currentSearchFilters[option.field] ??=
          widget.sfwEnabled ? '0' : option.value;
    }
  }

  Future<void> _fetchFilterData({int remainingRecoveries = 1}) async {
    final repository = context.read<SearchRepository>();
    setState(() {
      _isLoadingFilters = true;
      _filterLoadFailed = false;
    });
    try {
      final options = await repository.fetchFilterOptions(
        selectedFilters: Map<String, String>.from(currentSearchFilters),
        sfwEnabled: widget.sfwEnabled,
      );
      if (!mounted || !_isLoadingFilters) return;
      setState(() => _acceptFilterOptions(options));
    } on CloudflareChallengeException catch (error) {
      if (!mounted) return;
      if (remainingRecoveries > 0 && ModalRoute.of(context)?.isCurrent == true) {
        final result = await CloudflareCheckScreen.show(
          context,
          initialUrl: error.initialUrl ?? 'https://www.furaffinity.net/search/',
          asDialog: true,
        );
        if (!mounted) return;
        if (result?.passed == true) {
          await _fetchFilterData(remainingRecoveries: remainingRecoveries - 1);
          return;
        }
      }
      _showFilterLoadError();
    } catch (_) {
      _showFilterLoadError();
    }
  }

  void _showFilterLoadError() {
    if (!mounted || _filterOptions != null) return;
    setState(() {
      _isLoadingFilters = false;
      _filterLoadFailed = true;
    });
  }

  @override
  void dispose() {
    _filterSubscription?.cancel();
    _pageController.dispose();
    super.dispose();
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
                  if (fromDate != null &&
                      toDate != null &&
                      fromDate!.isAfter(toDate!)) {
                    await showDialog(
                      context: dialogContext,
                      builder: (errorContext) {
                        return AlertDialog(
                          title: Text('Invalid Date Range'),
                          content:
                              Text('"From" date cannot be after "To" date.'),
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

      if (!mounted) return;
      if (fieldToEdit == null) {
        finishedEditing = true;
      } else {
        DateTime initialDate =
            (fieldToEdit == 'from' ? fromDate : toDate) ?? DateTime.now();

        await Future.delayed(Duration.zero);

        if (!mounted) return;
        final pickedDate = await showDatePicker(
          context: context,
          initialDate: initialDate,
          firstDate: DateTime(1900),
          lastDate: DateTime.now(),
        );

        if (!mounted) return;
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

    currentSearchFilters['range_from'] = formatSearchFilterDate(fromDate);
    currentSearchFilters['range_to'] = formatSearchFilterDate(toDate);
  }

  Widget _buildDateFieldChooser(
      String label, DateTime? date, BuildContext context, String fieldKey) {
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
                contentPadding:
                    EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    formatSearchFilterDatePickerLabel(date),
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

  void _applyFilters() {
    final page = FaPageSettings.positiveInteger(_pageController.text);
    if (_paginationFormKey.currentState?.validate() != true || page == null) {
      return;
    }
    currentSearchFilters[FaPageSettings.pageKey] = page.toString();
    Navigator.pop(context, currentSearchFilters);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingFilters || _filterLoadFailed) {
      return Scaffold(
        appBar: AppBar(title: const Text('Search Filters')),
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
                          'Could not load Search filters. Please try again.',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        TextButton(
                          onPressed: _fetchFilterData,
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
        title: Text('Search Filters'),
        actions: [
          IconButton(
            icon: Icon(Icons.check),
            onPressed: _applyFilters,
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _buildSortCriteria(),
              const SizedBox(height: 20),
              FaPaginationFilterFields(
                formKey: _paginationFormKey,
                pageController: _pageController,
                resultsPerPage:
                    currentSearchFilters[FaPageSettings.perPageKey]!,
                resultsPerPageOptions:
                    _filterOptions![SearchFilterGroups.perPage],
                onResultsPerPageChanged: (value) {
                  setState(() {
                    currentSearchFilters[FaPageSettings.perPageKey] = value;
                  });
                },
              ),
              const SizedBox(height: 20),
              _buildSortByRange(),
              const SizedBox(height: 20),
              _buildGenderFilter(),
              const SizedBox(height: 20),
              _buildSortByRating(),
              const SizedBox(height: 20),
              _buildSortByType(),
              const SizedBox(height: 20),
              _buildSortByKeywords(),
              const SizedBox(height: 40),
              _buildAdditionalText(),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: _buildApplyResetButtons(),
      ),
    );
  }

  Widget _buildSortCriteria() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Sort Criteria',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            DropdownButton<String>(
              value: currentSearchFilters['order-by'],
              onChanged: (String? newValue) {
                setState(() {
                  currentSearchFilters['order-by'] = newValue!;
                });
              },
              items: _filterOptions![SearchFilterGroups.orderBy].map((option) {
                return DropdownMenuItem<String>(
                  value: option.value,
                  child: Text(option.label.capitalize()),
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
              items: _filterOptions![SearchFilterGroups.orderDirection]
                  .map((option) => DropdownMenuItem<String>(
                        value: option.value,
                        child: Text(option.label.capitalize()),
                      ))
                  .toList(),
            ),
            Text(' order'),
          ],
        ),
      ],
    );
  }

  Widget _buildGenderFilter() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Gender Filter',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12.0,
          runSpacing: 4.0,
          children: _filterOptions![SearchFilterGroups.gender]
              .map((option) => _buildCheckboxOption(
                    option.label,
                    option.field,
                    option.value,
                  ))
              .toList(),
        ),
      ],
    );
  }

  Widget _buildSortByRange() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Sort by Range',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        SizedBox(height: 8),
        RadioGroup<String>(
          groupValue: currentSearchFilters['range'],
          onChanged: (String? newValue) => _handleRadioChanged(
            'range',
            newValue,
          ),
          child: Wrap(
            spacing: 12.0,
            runSpacing: 8.0,
            children: _filterOptions![SearchFilterGroups.range]
                .map((option) => _buildRadioOption(
                      option.label,
                      option.field,
                      option.value,
                    ))
                .toList(),
          ),
        ),
        if (currentSearchFilters['range'] == 'manual') ...[
          SizedBox(height: 10),
          Row(
            children: [
              Text(
                'From: ${formatSearchFilterDateLabel(fromDate)}',
                style: TextStyle(fontSize: 14),
              ),
              SizedBox(width: 20),
              Text(
                'To: ${formatSearchFilterDateLabel(toDate)}',
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
        Text('Sort by Rating',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        Wrap(
          spacing: 8.0,
          children: _filterOptions![SearchFilterGroups.rating]
              .map((option) => _buildCheckboxOption(
                    option.label,
                    option.field,
                    option.value,
                  ))
              .toList(),
        ),
      ],
    );
  }

  Widget _buildSortByType() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Sort by Type',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        Wrap(
          spacing: 8.0,
          children: _filterOptions![SearchFilterGroups.type]
              .map((option) => _buildCheckboxOption(
                    option.label,
                    option.field,
                    option.value,
                  ))
              .toList(),
        ),
      ],
    );
  }

  Widget _buildSortByKeywords() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Sort by Matching Keywords',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        RadioGroup<String>(
          groupValue: currentSearchFilters['mode'],
          onChanged: (String? newValue) => _handleRadioChanged(
            'mode',
            newValue,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: _filterOptions![SearchFilterGroups.mode]
                .map((option) => _buildRadioOption(
                      option.label,
                      option.field,
                      option.value,
                    ))
                .toList(),
          ),
        ),
      ],
    );
  }

  void _handleRadioChanged(String filterKey, String? newValue) {
    if (newValue == null) return;
    setState(() {
      currentSearchFilters[filterKey] = newValue;
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
  }

  Widget _buildRadioOption(String label, String filterKey, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Radio<String>(
          activeColor: _applyButtonColor,
          value: value,
        ),
        Flexible(
          child: Text(
            label,
            style: TextStyle(
              color: currentSearchFilters[filterKey] == value
                  ? _applyButtonColor
                  : Colors.white,
            ),
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
        Flexible(
          child: Text(
            label,
            style: TextStyle(
              color: currentSearchFilters[filterKey] == value
                  ? _applyButtonColor
                  : Colors.white,
            ),
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
                      currentSearchFilters =
                          ContentRatingFilters.defaultSearchFilters(
                        sfwEnabled: widget.sfwEnabled,
                      );
                      _pageController.text =
                          currentSearchFilters[FaPageSettings.pageKey]!;
                      fromDate = null;
                      toDate = null;
                      currentSearchFilters['range'] = '5years';
                      currentSearchFilters['range_from'] = '';
                      currentSearchFilters['range_to'] = '';
                      _updateCurrentFilters();
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
