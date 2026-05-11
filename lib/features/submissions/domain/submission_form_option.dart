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
