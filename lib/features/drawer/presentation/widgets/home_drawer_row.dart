import 'package:material_ui/material_ui.dart';
import '../drawer_list.dart';
import '../../domain/drawer_index.dart';
import 'package:fanotifier/shared/widgets/star_burst_animation.dart';

Widget buildHomeDrawerRow(
  BuildContext context, {
  required DrawerList listData,
  required bool isKoFi,
  required DrawerIndex? selectedDrawerItem,
  required AnimationController? Function() animationController,
  required GlobalKey kofiKey,
  required bool showStars,
  required List<Offset>? starOrigins,
  required VoidCallback onTap,
  required ValueChanged<Offset> onKofiPressed,
  required VoidCallback onStarsCompleted,
}) {
  return Material(
    color: Colors.transparent,
    child: InkWell(
      splashColor: isKoFi
          ? Colors.transparent
          : Colors.grey.withValues(alpha: 0.1),
      highlightColor: isKoFi ? Colors.transparent : Colors.transparent,
      splashFactory: isKoFi ? NoSplash.splashFactory : null,
      onTap: onTap,
      child: Stack(
        children: <Widget>[
          if (listData.labelName == 'Support us on Ko-Fi!')
            GestureDetector(
              key: kofiKey,
              behavior: HitTestBehavior.opaque,
              onTapDown: (TapDownDetails details) {
                onKofiPressed(details.globalPosition);
              },
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.only(
                  left: 8,
                  right: 16,
                  top: 9,
                  bottom: 9,
                ),
                padding: const EdgeInsets.only(
                  left: 8,
                  right: 16,
                  top: 9,
                  bottom: 9,
                ),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.max,
                      children: [
                        SizedBox(
                          width: 24,
                          height: 24,
                          child: Image.asset(listData.imageName),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          listData.labelName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w500,
                            fontSize: 16,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    if (showStars && starOrigins != null)
                      Positioned.fill(
                        child: StarBurstAnimation(
                          origins: starOrigins,
                          onCompleted: onStarsCompleted,
                        ),
                      ),
                  ],
                ),
              ),
            )
          else
            Container(
              height: 54.0,
              alignment: Alignment.centerLeft,
              child: Row(
                children: <Widget>[
                  const SizedBox(width: 6.0, height: 46.0),
                  const Padding(padding: EdgeInsets.all(4.0)),
                  listData.isAssetsImage
                      ? SizedBox(
                          width: 24,
                          height: 24,
                          child: Image.asset(
                            listData.imageName,
                            color: selectedDrawerItem == listData.index
                                ? Colors.white
                                : Colors.grey.shade300,
                          ),
                        )
                      : Icon(
                          listData.icon?.icon,
                          color: selectedDrawerItem == listData.index
                              ? Colors.grey
                              : Colors.grey,
                        ),
                  const Padding(padding: EdgeInsets.all(4.0)),
                  Text(
                    listData.labelName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w500,
                      fontSize: 16,
                      color: Colors.white,
                    ),
                    textAlign: TextAlign.left,
                  ),
                ],
              ),
            ),
          if (selectedDrawerItem == listData.index &&
              listData.labelName != 'Support us on Ko-Fi!')
            AnimatedBuilder(
              animation: animationController()!,
              builder: (BuildContext context, Widget? child) {
                final drawerContentWidth =
                    MediaQuery.sizeOf(context).width * 0.75 - 64;
                return Transform(
                  transform: Matrix4.translationValues(
                    drawerContentWidth *
                        (1.0 - animationController()!.value - 1.0),
                    0.0,
                    0.0,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Container(
                      width: drawerContentWidth,
                      height: 46,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: const BorderRadius.only(
                          topRight: Radius.circular(28),
                          bottomRight: Radius.circular(28),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    ),
  );
}
