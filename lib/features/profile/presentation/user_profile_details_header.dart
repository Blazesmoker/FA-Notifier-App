import 'package:material_ui/material_ui.dart';

import 'package:fanotifier/core/analytics/app_screen.dart';
import 'package:fanotifier/features/notes/presentation/new_message_screen.dart';
import 'package:fanotifier/features/profile/presentation/user_profile_components.dart';
import 'package:fanotifier/features/profile/presentation/user_profile_controller.dart';
import 'package:fanotifier/features/profile/presentation/user_profile_sliver_helpers.dart';
import 'package:fanotifier/features/settings/domain/time_display_models.dart';
import 'package:fanotifier/shared/utils/time_display_formatter.dart';

Widget buildProfileDetailsHeader({
  required BuildContext context,
  required UserProfileController profileController,
  required MediaQueryData fixedTextScaleMediaQuery,
  required double textLeftPadding,
  required TimeDisplayFormat registrationTimeFormat,
  required ValueNotifier<GlobalKey> profileNameRowKey,
  required Widget Function(GlobalKey) buildHeaderNameRow,
  required ValueNotifier<bool> watchRequestInFlight,
  required VoidCallback onEditProfile,
  required VoidCallback onWatch,
}) {
  return SliverPersistentHeader(
    delegate: FixedSliverPersistentHeaderDelegate(
      height: 160,
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.stretch,
        children: [
          const Divider(
            height: 4.0,
            color: Color(0xFF111111),
            thickness: 3.0,
          ),
          const Divider(
            height: 2.0,
            color: Colors.black,
            thickness: 1.0,
          ),
          Column(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                color: const Color(0xFF111111),
                child: Padding(
                  padding:
                      const EdgeInsets.fromLTRB(
                          8.0, 0.0, 8.0, 8.0),
                  child: Row(
                    crossAxisAlignment:
                        CrossAxisAlignment.center,
                    children: [
                      MediaQuery(
                        data:
                            fixedTextScaleMediaQuery,
                        child: Expanded(
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment
                                    .start,
                            children: [
                              SizedBox(
                                height: 30.0,
                                child: Padding(
                                  padding: EdgeInsets
                                      .only(
                                          left:
                                              textLeftPadding),
                                  child:
                                      FittedBox(
                                    fit: BoxFit
                                        .scaleDown,
                                    alignment:
                                        Alignment
                                            .centerLeft,
                                    child: ValueListenableBuilder<
                                        GlobalKey>(
                                      valueListenable:
                                          profileNameRowKey,
                                      builder: (context,
                                          profileNameRowKey,
                                          child) {
                                        return buildHeaderNameRow(
                                          profileNameRowKey,
                                        );
                                      },
                                    ),
                                  ),
                                ),
                              ),
                              SizedBox(
                                height: 24.0,
                                child: Visibility(
                                  visible: true,
                                  maintainSize:
                                      true,
                                  maintainAnimation:
                                      true,
                                  maintainState:
                                      true,
                                  child: Padding(
                                    padding:
                                        EdgeInsets
                                            .only(
                                      top: 0.0,
                                      left:
                                          textLeftPadding,
                                    ),
                                    child:
                                        FittedBox(
                                      fit: BoxFit
                                          .scaleDown,
                                      alignment:
                                          Alignment
                                              .center,
                                      child: Text(
                                        (profileController
                                                    .userTitle
                                                    ?.isNotEmpty ??
                                                false)
                                            ? profileController
                                                .userTitle!
                                            : " ",
                                        style:
                                            const TextStyle(
                                          color: Colors
                                              .white70,
                                          fontSize:
                                              16.0,
                                        ),
                                        maxLines:
                                            1,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              Padding(
                                padding:
                                    const EdgeInsets
                                        .only(
                                  top: 8.0,
                                  left: 0.0,
                                ),
                                child: FittedBox(
                                  fit: BoxFit
                                      .scaleDown,
                                  alignment: Alignment
                                      .centerLeft,
                                  child: Text(
                                    profileController
                                                .registrationDate !=
                                            null &&
                                            profileController
                                                .registrationDate!
                                                .isNotEmpty
                                        ? 'Joined ${formatTimeInText(
                                            profileController.registrationDate!,
                                            format:
                                                registrationTimeFormat,
                                          )}'
                                        : '',
                                    style:
                                        const TextStyle(
                                      color: Colors
                                          .white70,
                                      fontSize:
                                          14.0,
                                    ),
                                    maxLines: 1,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      if (profileController
                          .isOwnProfile)
                        SizedBox(
                          width: 100,
                          height: 38,
                          child: ElevatedButton(
                            onPressed:
                                onEditProfile,
                            style: ElevatedButton
                                .styleFrom(
                              backgroundColor:
                                  Colors.black,
                              shape:
                                  RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius
                                        .circular(
                                            2),
                              ),
                              side:
                                  const BorderSide(
                                color: Color(
                                    0xFFE09321),
                              ),
                            ),
                            child:
                                const FittedBox(
                              fit: BoxFit
                                  .scaleDown,
                              child: Text(
                                "Edit Profile",
                                style: TextStyle(
                                  color: Colors
                                      .white,
                                ),
                              ),
                            ),
                          ),
                        )
                        else
                        Transform.translate(
                        offset: const Offset(0, 4),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                            SizedBox(
                              width: 100,
                              height: 38,
                              child: ValueListenableBuilder<
                                  bool>(
                                valueListenable:
                                    watchRequestInFlight,
                                builder: (context,
                                    isWatchRequestInFlight,
                                    child) {
                                  return isWatchRequestInFlight
                                      ? const Center(
                                          child:
                                              SizedBox(
                                            width:
                                                18,
                                            height:
                                                18,
                                            child:
                                                CircularProgressIndicator(
                                              strokeWidth:
                                                  2,
                                              color:
                                                  Color(
                                                      0xFFE09321),
                                            ),
                                          ),
                                        )
                                      : ElevatedButton(
                                          onPressed:
                                              onWatch,
                                          style:
                                              ElevatedButton
                                                  .styleFrom(
                                            backgroundColor:
                                                Colors
                                                    .black,
                                            shape:
                                                RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius
                                                      .circular(
                                                          2),
                                            ),
                                            side:
                                                const BorderSide(
                                              color:
                                                  Color(
                                                      0xFFE09321),
                                            ),
                                          ),
                                          child:
                                              FittedBox(
                                            fit: BoxFit
                                                .scaleDown,
                                            child:
                                                Text(
                                              profileController
                                                      .isWatching
                                                  ? "-Watch"
                                                  : "+Watch",
                                              style:
                                                  const TextStyle(
                                                color:
                                                    Colors
                                                        .white,
                                              ),
                                            ),
                                          ),
                                        );
                                },
                              ),
                            ),
                            const SizedBox(
                                height: 5),
                            SizedBox(
                              width: 100,
                              height: 38,
                              child:
                                  ElevatedButton(
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      settings:
                                          const AnalyticsRouteSettings(
                                        AppScreens
                                            .newNote,
                                      ),
                                      builder:
                                          (context) =>
                                              NewMessageScreen(
                                        recipient:
                                            profileController
                                                .sanitizedUsername,
                                      ),
                                    ),
                                  );
                                },
                                style:
                                    ElevatedButton
                                        .styleFrom(
                                  backgroundColor:
                                      const Color(
                                          0xFFE09321),
                                  shape:
                                      RoundedRectangleBorder(
                                    borderRadius:
                                        BorderRadius
                                            .circular(
                                                2),
                                  ),
                                ),
                                child:
                                    const FittedBox(
                                  fit: BoxFit
                                      .scaleDown,
                                  child: Text(
                                    "Note",
                                    style:
                                        TextStyle(
                                      color: Colors
                                          .white,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),),
                    ],
                  ),
                ),
              ),
              const Divider(
                height: 3.0,
                color: Colors.black,
                thickness: 3.0,
              ),
              const Divider(
                height: 4.0,
                color: Color(0xFF111111),
                thickness: 4.0,
              ),
            ],
          ),
          MediaQuery(
            data: fixedTextScaleMediaQuery,
            child: Padding(
              padding:
                  const EdgeInsets.only(top: 8.0),
              child: Table(
                columnWidths: const {
                  0: FlexColumnWidth(1),
                  1: FlexColumnWidth(1),
                  2: FlexColumnWidth(1),
                  3: FlexColumnWidth(1),
                },
                defaultVerticalAlignment:
                    TableCellVerticalAlignment
                        .middle,
                children: [
                  TableRow(
                    children: [
                      ProfileStatItem(
                          count:
                              profileController
                                      .views
                                      ?.toString() ??
                                  '0',
                          label: 'Views'),
                      ProfileStatItem(
                          count: profileController
                                  .submissions
                                  ?.toString() ??
                              '0',
                          label: 'Submissions'),
                      ProfileStatItem(
                          count:
                              profileController
                                      .favs
                                      ?.toString() ??
                                  '0',
                          label: 'Favs'),
                      ProfileStatItem(
                          count:
                              profileController
                                  .recentWatchersCount
                                  .toString(),
                          label: 'Watched'),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
    pinned: false,
  );
}
