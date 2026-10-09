import 'package:material_ui/material_ui.dart';
import 'home_drawer_mode_switch.dart';

List<Widget> buildHomeDrawerFooter(
  BuildContext context, {
  required bool sfwEnabled,
  required String registeredUsersOnline,
  required Future<void> Function(bool) onToggle,
}) {
  return [
    Padding(
      padding: const EdgeInsets.only(
        bottom: 10.0,
        top: 6.0,
        right: 16.0,
        left: 16.0,
      ),
      child: Row(
        children: [
          HomeDrawerModeSwitch(
            value: !sfwEnabled,
            onChanged: onToggle,
          ),
        ],
      ),
    ),

    const Divider(height: 1.0, color: Color(0xFF111111), thickness: 3.0),

    Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
      child: Text(
        'Registered users online: $registeredUsersOnline',
        style: const TextStyle(fontSize: 14, color: Colors.white),
        textAlign: TextAlign.left,
      ),
    ),

    SizedBox(height: MediaQuery.paddingOf(context).bottom),
  ];
}
