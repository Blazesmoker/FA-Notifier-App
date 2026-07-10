class Shout {
  final String id;
  final String nickname;
  final String nicknameLink;
  final String postedTitle;
  final String avatarUrl;
  final String postedAgo;
  final String textContent;
  bool isChecked;
  final bool isRemoved;

  Shout({
    required this.id,
    required this.nickname,
    required this.nicknameLink,
    required this.postedTitle,
    required this.avatarUrl,
    required this.postedAgo,
    required this.textContent,
    required this.isRemoved,
    this.isChecked = false,
  });

  @override
  String toString() {
    return 'Shout(id=$id, nickname=$nickname, postedTitle=$postedTitle, removed=$isRemoved, text="$textContent")';
  }
}

class NotificationItem {
  final String id;
  final String content;
  final String? username;
  final String? linkUsername;
  final String? submissionId;
  final String? journalId;
  final String? url;
  String? avatarUrl;
  final String date;
  final String fullDate;
  bool isChecked;

  NotificationItem({
    required this.id,
    required this.content,
    this.username,
    this.linkUsername,
    this.submissionId,
    this.journalId,
    this.url,
    this.avatarUrl,
    required this.date,
    required this.fullDate,
    this.isChecked = false,
  });
}

class NotificationSection {
  final String title;
  final String formAction;
  List<NotificationItem> items;

  NotificationSection({
    required this.title,
    required this.formAction,
    required this.items,
  });
}
