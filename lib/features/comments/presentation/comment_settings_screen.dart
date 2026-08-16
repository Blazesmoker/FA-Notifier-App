import 'package:fanotifier/features/comments/presentation/comment_settings_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class CommentsSettingsScreen extends StatelessWidget {
  const CommentsSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<CommentSettingsProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text('Comments Settings')),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        children: [
          const SizedBox(height: 8),
          const ListTile(
            leading: Icon(Icons.forum_outlined, color: Color(0xFFE09321)),
            title: Text('Comments'),
          ),
          SwitchListTile(
            activeThumbColor: const Color(0xFFE09321),
            value: settings.collapsibleCommentsEnabled,
            onChanged: settings.setCollapsibleComments,
            title: const Text('Collapsible Comments'),
            subtitle: const Text('Tap a comment to collapse or expand it.'),
          ),
        ],
      ),
    );
  }
}
