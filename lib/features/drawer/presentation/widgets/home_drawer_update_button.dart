import 'package:material_ui/material_ui.dart';

Widget buildHomeDrawerUpdateButton({required VoidCallback onTap}) {
  return Padding(
    padding: const EdgeInsets.fromLTRB(16.0, 14.0, 16.0, 4.0),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 200),
        child: Material(
          color: const Color(0xFFE09321),
          borderRadius: BorderRadius.circular(26),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: const SizedBox(
              height: 44,
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.cached, color: Colors.white),
                    SizedBox(width: 6),
                    Text(
                      'Update Available!',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
