class Shout {
  final String id;
  final String avatarUrl;
  final String username;
  final String profileNickname;
  final String date;
  final String text;
  final String popupDateFull;
  final String popupDateRelative;
  final List<String> iconBeforeUrls;
  final List<String> iconAfterUrls;
  final String? symbol;
  bool selected;

  Shout({
    required this.id,
    required this.avatarUrl,
    required this.username,
    required this.profileNickname,
    required this.date,
    required this.text,
    required this.popupDateFull,
    required this.popupDateRelative,
    this.iconBeforeUrls = const [],
    this.iconAfterUrls = const [],
    this.symbol,
    this.selected = false,
  });
}
