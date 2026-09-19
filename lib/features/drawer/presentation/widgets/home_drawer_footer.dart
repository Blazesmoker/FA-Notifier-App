import 'package:material_ui/material_ui.dart';
import 'package:flutter_switch/flutter_switch.dart';

List<Widget> buildHomeDrawerFooter(
  BuildContext context, {
  required bool sfwEnabled,
  required String registeredUsersOnline,
  required ValueChanged<bool> onToggle,
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
          FlutterSwitch(
            width: 68.0,
            height: 30.0,
            toggleSize: 20.0,
            value: !sfwEnabled,
            borderRadius: 18.0,
            padding: 3,
            activeText: 'NSFW',
            inactiveText: ' SFW',
            valueFontSize: 11.6,
            activeTextColor: Colors.black,
            activeToggleColor: Colors.black,
            inactiveTextColor: Colors.white,
            activeColor: const Color(0xFFE09321),
            inactiveColor: const Color(0xFF111111),
            showOnOff: true,
            onToggle: onToggle,
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
