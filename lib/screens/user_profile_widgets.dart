import 'package:FANotifier/screens/shout_widget.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:html/parser.dart' as html_parser;

import '../model/shout.dart';
import '../model/user_link.dart';

class FeaturedSubmissionCard extends StatelessWidget {
  const FeaturedSubmissionCard({
    Key? key,
    required this.imageUrl,
    required this.title,
    required this.postNumber,
    required this.onOpen,
  }) : super(key: key);

  final String imageUrl;
  final String title;
  final String postNumber;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1F1F1F),
          borderRadius: BorderRadius.circular(8.0),
        ),
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Featured Submission',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 8.0),
            GestureDetector(
              onTap: onOpen,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8.0),
                child: CachedNetworkImage(
                  imageUrl: imageUrl,
                  fit: BoxFit.contain,
                  placeholder: (context, url) => const SizedBox(
                    height: 200,
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  errorWidget: (context, url, error) => const SizedBox(
                    height: 200,
                    child: Center(
                      child: Icon(Icons.broken_image, size: 100, color: Colors.redAccent),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8.0),
            Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}

class ShoutsSection extends StatelessWidget {
  const ShoutsSection({
    Key? key,
    required this.sanitizedUsername,
    required this.shouts,
    required this.isOwnProfile,
    required this.onComposeTap,
    required this.onDeleteShout,
  }) : super(key: key);

  final String sanitizedUsername;
  final List<Shout> shouts;
  final bool isOwnProfile;
  final Future<void> Function() onComposeTap;
  final Future<void> Function(int index, Shout shout) onDeleteShout;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF1F1F1F),
              Colors.black,
            ],
            stops: [0.0, 0.06],
          ),
          borderRadius: BorderRadius.circular(8.0),
        ),
        padding: const EdgeInsets.only(top: 16.0, bottom: 64.0, right: 0.0, left: 0.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Text(
              'Shouts',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 0.0),
            Padding(
              padding: const EdgeInsets.fromLTRB(12.0, 12.0, 12.0, 12.0),
              child: GestureDetector(
                onTap: onComposeTap,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
                  decoration: BoxDecoration(
                    color: const Color(0xFF232323),
                    borderRadius: BorderRadius.circular(10.0),
                  ),
                  child: Row(
                    children: const [
                      Expanded(
                        child: Text(
                          'Type here to leave a shout!',
                          style: TextStyle(color: Colors.white54),
                        ),
                      ),
                      Icon(Icons.send, color: Colors.white54),
                    ],
                  ),
                ),
              ),
            ),

            if (shouts.isEmpty)
              const Text(
                'No shouts yet. Be the first to shout!',
                style: TextStyle(color: Colors.white70),
              )
            else
              Column(
                children: [
                  ListView.separated(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: shouts.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 8.0),
                    itemBuilder: (context, index) {
                      final shout = shouts[index];
                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onLongPress: () async {
                          final plainText = html_parser.parse(shout.text).body?.text ?? shout.text;
                          final action = await showDialog<String>(
                            context: context,
                            builder: (context) {
                              final maxHeight = MediaQuery.of(context).size.height * 0.6;
                              return AlertDialog(
                                scrollable: true,
                                titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                                title: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(4.0),
                                      child: Image.network(
                                        shout.avatarUrl,
                                        width: 40,
                                        height: 40,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            shout.username,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          Text(
                                            '${shout.symbol} ${shout.profileNickname}',
                                            style: const TextStyle(
                                                color: Color(0xFFE09321),
                                                fontSize: 14,
                                                fontWeight: FontWeight.normal
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                content: ConstrainedBox(
                                  constraints: BoxConstraints(maxHeight: maxHeight),
                                  child: SingleChildScrollView(
                                    child: Text(
                                      plainText,
                                      style: const TextStyle(color: Colors.white),
                                    ),
                                  ),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(context, 'copy'),
                                    child: const Text('Copy text'),
                                  ),
                                  if (isOwnProfile)
                                    TextButton(
                                      onPressed: () => Navigator.pop(context, 'delete'),
                                      style: TextButton.styleFrom(foregroundColor: Colors.red),
                                      child: const Text("Delete"),
                                    ),
                                ],
                              );
                            },
                          );
                          if (action == 'copy') {
                            await Clipboard.setData(ClipboardData(text: plainText));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Shout text copied'),
                                backgroundColor: Colors.green,
                              ),
                            );
                          } else if (action == 'delete' && isOwnProfile) {
                            await onDeleteShout(index, shout);
                          }
                        },
                        child: ShoutWidget(
                          shout: shout,
                          onDelete: isOwnProfile ? () => onDeleteShout(index, shout) : null,
                        ),
                      );
                    },
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class StatsRow extends StatelessWidget {
  const StatsRow({
    Key? key,
    required this.views,
    required this.submissions,
    required this.favs,
    required this.watched,
  }) : super(key: key);

  final String views;
  final String submissions;
  final String favs;
  final String watched;

  @override
  Widget build(BuildContext context) {
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaleFactor: 1.0),
      child: Padding(
        padding: const EdgeInsets.only(top: 8.0),
        child: Table(
          columnWidths: const {
            0: FlexColumnWidth(1),
            1: FlexColumnWidth(1),
            2: FlexColumnWidth(1),
            3: FlexColumnWidth(1),
          },
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: [
            TableRow(
              children: [
                _buildStatItem(views, 'Views'),
                _buildStatItem(submissions, 'Submissions'),
                _buildStatItem(favs, 'Favs'),
                _buildStatItem(watched, 'Watched'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String count, String label) {
    return Column(
      children: [
        Text(
          count,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 16.0,
          ),
        ),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 12.0),
        ),
      ],
    );
  }
}

class ContactInfoCard extends StatelessWidget {
  const ContactInfoCard({
    Key? key,
    required this.contacts,
    required this.onTapLink,
  }) : super(key: key);

  final List<Map<String, String>> contacts;
  final void Function(String url) onTapLink;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1F1F1F),
          borderRadius: BorderRadius.circular(8.0),
        ),
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Contact Information',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 8.0),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: contacts.map((contact) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4.0),
                  child: Row(
                    children: [
                      Text(
                        '${contact['label']}: ',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16.0,
                        ),
                      ),
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            final href = contact['href'];
                            if (href != null && href.isNotEmpty) {
                              onTapLink(href);
                            }
                          },
                          child: Text(
                            contact['value'] ?? '',
                            style: const TextStyle(
                              color: Color(0xFFE09321),
                              fontSize: 16.0,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

