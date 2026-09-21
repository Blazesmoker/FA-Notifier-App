import 'package:material_ui/material_ui.dart';
import 'package:fanotifier/shared/widgets/fa_network_image.dart';

Widget buildSubmissionAuthorHeader({
  required String profileImageUrl,
  required String username,
  required String? currentUsername,
  required List<String> iconBeforeUrls,
  required List<String> iconAfterUrls,
  required bool watchLinksLoading,
  required bool watchRequestInFlight,
  required bool isWatching,
  required VoidCallback onAuthorTap,
  required Future<void> Function() onWatchPressed,
}) {
  return Padding(
    padding: const EdgeInsets.all(8.0),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: GestureDetector(
            onTap: onAuthorTap,
            child: Container(
              padding: const EdgeInsets.only(right: 6.0),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: const BoxDecoration(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.zero,
                    ),
                    child: FaNetworkImage(
                      profileImageUrl,
                      fit: BoxFit.cover,
                      alignment: Alignment.center,

                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) {
                          return child;
                        }
                        return const Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        );
                      },

                      errorBuilder: (context, error, stackTrace) {
                        return Image.asset(
                          'assets/images/defaultpic.gif',
                          fit: BoxFit.cover,
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ...iconBeforeUrls.map(
                            (url) => Padding(
                              padding: const EdgeInsets.only(right: 4.0),
                              child: FaNetworkImage(
                                url,
                                width: 20,
                                height: 20,
                                errorBuilder: (context, error, stackTrace) =>
                                    const Icon(Icons.error, size: 20),
                              ),
                            ),
                          ),
                          Text(
                            username,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          ...iconAfterUrls.map(
                            (url) => Padding(
                              padding: const EdgeInsets.only(left: 4.0),
                              child: FaNetworkImage(
                                url,
                                width: 20,
                                height: 20,
                                errorBuilder: (context, error, stackTrace) =>
                                    const Icon(Icons.error, size: 20),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (!(currentUsername != null && currentUsername == username))
          SizedBox(
            width: 94,
            height: 24,
            child: (watchLinksLoading || watchRequestInFlight)
                ? const Center(
                    child: SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFFE09321),
                      ),
                    ),
                  )
                : ElevatedButton(
                    onPressed: () => onWatchPressed(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isWatching
                          ? Colors.black
                          : const Color(0xFFE09321),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(2),
                      ),
                      side: const BorderSide(color: Color(0xFFE09321)),
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        isWatching ? "-Watch" : "+Watch",
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
          ),
      ],
    ),
  );
}

Widget buildSubmissionImage({
  required String imageUrl,
  required double? imageWidth,
  required double? imageHeight,
}) {
  return ClipRect(
    child: LayoutBuilder(
      builder: (context, constraints) {
        final aspectRatio = (imageWidth != null && imageHeight != null)
            ? imageWidth / imageHeight
            : 16 / 9;
        return AspectRatio(
          aspectRatio: aspectRatio,
          child: FaNetworkImage(
            imageUrl,
            fit: BoxFit.contain,
            loadingBuilder:
                (
                  BuildContext context,
                  Widget child,
                  ImageChunkEvent? loadingProgress,
                ) {
                  if (loadingProgress == null) {
                    return child;
                  }
                  return Container(
                    color: Colors.black,
                    child: Center(
                      child: CircularProgressIndicator(
                        value: loadingProgress.expectedTotalBytes != null
                            ? loadingProgress.cumulativeBytesLoaded /
                                  (loadingProgress.expectedTotalBytes ?? 1)
                            : null,
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          Color(0xFFE09321),
                        ),
                      ),
                    ),
                  );
                },
            errorBuilder: (context, error, stackTrace) {
              return Container(
                color: Colors.black,
                child: const Center(
                  child: Icon(Icons.error_outline, color: Colors.red, size: 40),
                ),
              );
            },
          ),
        );
      },
    ),
  );
}
