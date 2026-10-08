import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fanotifier/shared/fa/domain/fa_filter_options.dart';
import 'package:fanotifier/shared/fa/domain/fa_page_settings.dart';

class FaPaginationFilterFields extends StatelessWidget {
  const FaPaginationFilterFields({
    super.key,
    required this.formKey,
    required this.pageController,
    required this.resultsPerPage,
    required this.resultsPerPageOptions,
    required this.onResultsPerPageChanged,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController pageController;
  final String resultsPerPage;
  final List<FaFilterOption> resultsPerPageOptions;
  final ValueChanged<String> onResultsPerPageChanged;

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextFormField(
            controller: pageController,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            autovalidateMode: AutovalidateMode.onUserInteraction,
            decoration: const InputDecoration(
              labelText: 'Page',
              helperText: 'Start loading from this page.',
              helperMaxLines: 3,
              errorMaxLines: 3,
              border: OutlineInputBorder(),
            ),
            validator: (value) {
              if (FaPageSettings.positiveInteger(value) == null) {
                return 'Enter a whole page number of 1 or greater.';
              }
              return null;
            },
          ),
          const SizedBox(height: 20),
          InputDecorator(
            decoration: const InputDecoration(
              labelText: 'Results per page',
              border: OutlineInputBorder(),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: resultsPerPage,
                isDense: true,
                isExpanded: true,
                items: resultsPerPageOptions
                    .map((option) => DropdownMenuItem<String>(
                          value: option.value,
                          child: Text(option.label),
                        ))
                    .toList(),
                onChanged: (value) {
                  if (value != null) {
                    onResultsPerPageChanged(value);
                  }
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
