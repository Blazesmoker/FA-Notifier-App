import 'package:material_ui/material_ui.dart';
import 'package:fanotifier/shared/widgets/pulsating_loading_indicator.dart';

Widget buildMessageDetailLoading() {
  return const Center(
    child: PulsatingLoadingIndicator(
      size: 108.0,
      assetPath: 'assets/icons/fathemed.png',
    ),
  );
}

Widget buildMessageDetailError(String errorMessage) {
  return Center(
    child: Text(
      errorMessage,
      style: const TextStyle(color: Colors.red, fontSize: 16),
      textAlign: TextAlign.center,
    ),
  );
}
