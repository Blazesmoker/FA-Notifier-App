import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import 'package:fanotifier/app/navigation/app_fa_link_navigator.dart';
import 'package:fanotifier/app/lifecycle/fa_activities_polling_service.dart';
import 'package:fanotifier/core/preferences/thumbnail_display_settings_provider.dart';
import 'package:fanotifier/core/preferences/privacy_settings_provider.dart';
import 'package:fanotifier/core/preferences/translator_settings_provider.dart';
import 'package:fanotifier/core/notifications/domain/local_notification_gateway.dart';
import 'package:fanotifier/core/timezone/data/fa_timezone_repository.dart';
import 'package:fanotifier/core/timezone/presentation/timezone_provider.dart';
import 'package:fanotifier/features/auth/auth_feature.dart';
import 'package:fanotifier/features/auth/domain/cloudflare_check_gateway.dart';
import 'package:fanotifier/features/auth/domain/startup_cloudflare_checker.dart';
import 'package:fanotifier/features/browse/browse_feature.dart';
import 'package:fanotifier/features/browse/domain/browse_repository.dart';
import 'package:fanotifier/features/home/domain/home_login_webview_support.dart';
import 'package:fanotifier/features/home/domain/home_profile_repository.dart';
import 'package:fanotifier/features/home/domain/home_session_repository.dart';
import 'package:fanotifier/features/home/domain/home_start_screen_preference_repository.dart';
import 'package:fanotifier/features/home/home_feature.dart';
import 'package:fanotifier/features/image_tools/domain/image_optimizer_repository.dart';
import 'package:fanotifier/features/image_tools/image_tools_feature.dart';
import 'package:fanotifier/features/notifications/notifications_feature.dart';
import 'package:fanotifier/shared/fa/domain/fa_activities_polling_port.dart';
import 'package:fanotifier/features/notifications/domain/notification_refresh_port.dart';
import 'package:fanotifier/features/notifications/domain/notification_platform_settings_repository.dart';
import 'package:fanotifier/features/notifications/presentation/fa_notification_service.dart';
import 'package:fanotifier/features/notifications/presentation/notification_navigation_provider.dart';
import 'package:fanotifier/features/notifications/presentation/notification_settings_provider.dart';
import 'package:fanotifier/features/comments/comments_feature.dart';
import 'package:fanotifier/features/comments/domain/comment_edit_repository.dart';
import 'package:fanotifier/features/comments/presentation/comment_settings_provider.dart';
import 'package:fanotifier/shared/fa/domain/submission_comment_repository.dart';
import 'package:fanotifier/features/drawer/domain/app_update_repository.dart';
import 'package:fanotifier/features/drawer/domain/nsfw_confirmation_repository.dart';
import 'package:fanotifier/features/drawer/drawer_feature.dart';
import 'package:fanotifier/features/journals/domain/create_journal_repository.dart';
import 'package:fanotifier/features/journals/domain/openjournal_repository.dart';
import 'package:fanotifier/features/journals/journals_feature.dart';
import 'package:fanotifier/features/notes/domain/new_message_repository.dart';
import 'package:fanotifier/features/notes/domain/note_message_repository.dart';
import 'package:fanotifier/features/notes/domain/note_reply_repository.dart';
import 'package:fanotifier/features/notes/domain/note_reply_webview_gateway.dart';
import 'package:fanotifier/features/notes/domain/note_submission_preview_repository.dart';
import 'package:fanotifier/features/notes/domain/notes_repository.dart';
import 'package:fanotifier/features/notes/domain/notes_refresh_port.dart';
import 'package:fanotifier/features/notes/domain/notes_trash_repository.dart';
import 'package:fanotifier/features/notes/notes_feature.dart';
import 'package:fanotifier/features/notes/presentation/note_image_preview_settings_provider.dart';
import 'package:fanotifier/features/profile/profile_feature.dart';
import 'package:fanotifier/features/profile/domain/profile_favorites_repository.dart';
import 'package:fanotifier/features/profile/domain/profile_gallery_repository.dart';
import 'package:fanotifier/features/profile/domain/profile_journals_repository.dart';
import 'package:fanotifier/features/profile/domain/profile_media_export_repository.dart';
import 'package:fanotifier/features/profile/domain/profile_scraps_repository.dart';
import 'package:fanotifier/features/profile/domain/profile_shout_repository.dart';
import 'package:fanotifier/features/profile/domain/profile_shout_text_repository.dart';
import 'package:fanotifier/features/profile/domain/user_description_repository.dart';
import 'package:fanotifier/features/search/domain/find_source_repository.dart';
import 'package:fanotifier/features/search/domain/search_repository.dart';
import 'package:fanotifier/features/search/search_feature.dart';
import 'package:fanotifier/features/submissions/presentation/submission_favorite_state_controller.dart';
import 'package:fanotifier/features/settings/domain/app_icon_repository.dart';
import 'package:fanotifier/features/settings/domain/fur_affinity_settings_repository.dart';
import 'package:fanotifier/features/settings/domain/settings_app_info_repository.dart';
import 'package:fanotifier/features/settings/domain/tag_blocklist_repository.dart';
import 'package:fanotifier/features/settings/domain/watchlist_repository.dart';
import 'package:fanotifier/features/settings/settings_feature.dart';
import 'package:fanotifier/features/submissions/domain/edit_submission_page_repository.dart';
import 'package:fanotifier/features/submissions/domain/finalize_submission_repository.dart';
import 'package:fanotifier/features/submissions/domain/openpost_repository.dart';
import 'package:fanotifier/features/submissions/domain/submission_description_repository.dart';
import 'package:fanotifier/features/submissions/domain/submission_favorite_repository.dart';
import 'package:fanotifier/features/submissions/domain/submission_folder_color_repository.dart';
import 'package:fanotifier/features/submissions/domain/submission_management_repository.dart';
import 'package:fanotifier/features/submissions/domain/submissions_repository.dart';
import 'package:fanotifier/features/submissions/submissions_feature.dart';
import 'package:fanotifier/features/upload/domain/submission_template_repository.dart';
import 'package:fanotifier/features/upload/domain/upload_file_picker_gateway.dart';
import 'package:fanotifier/features/upload/domain/upload_navigation_repository.dart';
import 'package:fanotifier/features/upload/domain/upload_permission_gateway.dart';
import 'package:fanotifier/features/upload/domain/upload_webview_script_repository.dart';
import 'package:fanotifier/features/upload/domain/upload_webview_session_gateway.dart';
import 'package:fanotifier/features/upload/upload_feature.dart';
import 'package:fanotifier/shared/navigation/fa_link_handler.dart';

class AppProviders extends StatelessWidget {
  const AppProviders({
    super.key,
    required this.timezoneProvider,
    required this.child,
  });

  final TimezoneProvider timezoneProvider;
  final Widget child;

  static TimezoneProvider createTimezoneProvider() {
    return TimezoneProvider(
      repository: const FaTimezoneRepository(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<FaLinkNavigator>(
          create: (_) => const AppFaLinkNavigator(),
        ),
        Provider<StartupCloudflareChecker>(
          create: (_) => AuthFeature.createStartupCloudflareChecker(),
        ),
        Provider<CloudflareCheckGateway>(
          create: (_) => AuthFeature.createCloudflareCheckGateway(),
        ),
        Provider<AppUpdateRepository>(
          create: (_) => DrawerFeature.createAppUpdateRepository(),
        ),
        Provider<NsfwConfirmationRepository>(
          create: (_) => DrawerFeature.createNsfwConfirmationRepository(),
        ),
        Provider<AppIconRepository>(
          create: (_) => SettingsFeature.createAppIconRepository(),
        ),
        Provider<SettingsAppInfoRepository>(
          create: (_) => SettingsFeature.createAppInfoRepository(),
        ),
        Provider<FurAffinitySettingsRepository>(
          create: (_) =>
              SettingsFeature.createFurAffinitySettingsRepository(),
        ),
        Provider<ImageOptimizerRepository>(
          create: (_) => ImageToolsFeature.createRepository(),
        ),
        Provider<TagBlocklistRepository>(
          create: (_) => SettingsFeature.createTagBlocklistRepository(),
        ),
        Provider<WatchlistRepository>(
          create: (_) => SettingsFeature.createWatchlistRepository(),
        ),
        Provider<HomeSessionRepository>(
          create: (_) => HomeFeature.createSessionRepository(),
        ),
        Provider<HomeProfileRepository>(
          create: (_) => HomeFeature.createProfileRepository(),
        ),
        Provider<HomeLoginWebViewSupport>(
          create: (_) => HomeFeature.createLoginWebViewSupport(),
        ),
        Provider<HomeStartScreenPreferenceRepository>(
          create: (_) =>
              HomeFeature.createStartScreenPreferenceRepository(),
        ),
        Provider<FaActivitiesPollingPort>.value(
          value: FaActivitiesPollingService(),
        ),
        Provider<NotificationRefreshPort>.value(
          value: NotificationsFeature.refreshPort,
        ),
        Provider<NotificationPlatformSettingsRepository>(
          create: (_) =>
              NotificationsFeature.createPlatformSettingsRepository(),
        ),
        Provider<NotesRefreshPort>.value(
          value: NotesFeature.refreshPort,
        ),
        Provider<LocalNotificationGateway>.value(
          value: NotificationsFeature.localNotificationGateway,
        ),
        ProfileFeature.repositoryProvider(),
        Provider<ProfileShoutRepositoryFactory>(
          create: (_) => ProfileFeature.createShoutRepository,
        ),
        Provider<ProfileScrapsRepository>(
          create: (_) => ProfileFeature.createScrapsRepository(),
        ),
        Provider<ProfileFavoritesRepository>(
          create: (_) => ProfileFeature.createFavoritesRepository(),
        ),
        Provider<ProfileGalleryRepository>(
          create: (_) => ProfileFeature.createGalleryRepository(),
        ),
        Provider<ProfileJournalsRepository>(
          create: (_) => ProfileFeature.createJournalsRepository(),
        ),
        Provider<ProfileMediaExportRepository>(
          create: (_) => ProfileFeature.createMediaExportRepository(),
        ),
        Provider<UserDescriptionRepository>(
          create: (_) => ProfileFeature.createUserDescriptionRepository(),
        ),
        Provider<ProfileShoutTextRepository>(
          create: (_) => ProfileFeature.createShoutTextRepository(),
        ),
        Provider<BrowseRepository>(
          create: (_) => BrowseFeature.createRepository(),
        ),
        Provider<SearchRepository>(
          create: (_) => SearchFeature.createRepository(),
        ),
        Provider<FindSourceRepository>(
          create: (_) => SearchFeature.createFindSourceRepository(),
        ),
        Provider<SubmissionFavoriteRepository>(
          create: (_) => SubmissionsFeature.createFavoriteRepository(),
        ),
        ChangeNotifierProvider<SubmissionFavoriteStateController>(
          create: (context) => SubmissionFavoriteStateController(
            repository: context.read<SubmissionFavoriteRepository>(),
          ),
        ),
        Provider<SubmissionsRepository>(
          create: (_) => SubmissionsFeature.createSubmissionsRepository(),
        ),
        Provider<SubmissionManagementRepository>(
          create: (_) => SubmissionsFeature.createManagementRepository(),
        ),
        Provider<SubmissionFolderColorRepository>(
          create: (_) => SubmissionsFeature.createFolderColorRepository(),
        ),
        Provider<SubmissionDescriptionRepository>(
          create: (_) => SubmissionsFeature.createDescriptionRepository(),
        ),
        Provider<FinalizeSubmissionRepositoryFactory>(
          create: (_) => SubmissionsFeature.createFinalizeRepository,
        ),
        Provider<EditSubmissionPageRepository>(
          create: (_) => SubmissionsFeature.createEditPageRepository(),
        ),
        Provider<UploadFilePickerGateway>(
          create: (_) => UploadFeature.createFilePickerGateway(),
        ),
        Provider<UploadPermissionGateway>(
          create: (_) => UploadFeature.createPermissionGateway(),
        ),
        Provider<UploadNavigationRepository>(
          create: (_) => UploadFeature.createNavigationRepository(),
        ),
        Provider<SubmissionTemplateRepository>(
          create: (_) => UploadFeature.createTemplateRepository(),
        ),
        Provider<UploadWebViewScriptRepository>(
          create: (_) => UploadFeature.createWebViewScriptRepository(),
        ),
        Provider<UploadWebViewSessionGateway>(
          create: (_) => UploadFeature.createWebViewSessionGateway(),
        ),
        Provider<OpenJournalRepository>(
          create: (_) => JournalsFeature.createOpenJournalRepository(),
        ),
        Provider<CreateJournalRepository>(
          create: (_) => JournalsFeature.createCreateJournalRepository(),
        ),
        Provider<NotesRepositoryFactory>(
          create: (context) => () => NotesFeature.createRepository(
            refreshPort: context.read<NotesRefreshPort>(),
            activitiesPollingPort:
                context.read<FaActivitiesPollingPort>(),
            notificationGateway:
                context.read<LocalNotificationGateway>(),
          ),
        ),
        Provider<NewMessageRepositoryFactory>(
          create: (_) => NotesFeature.createNewMessageRepository,
        ),
        Provider<NoteMessageRepositoryFactory>(
          create: (_) => NotesFeature.createNoteMessageRepository,
        ),
        Provider<NotesTrashRepositoryFactory>(
          create: (_) => NotesFeature.createNotesTrashRepository,
        ),
        Provider<NoteReplyRepositoryFactory>(
          create: (_) => NotesFeature.createNoteReplyRepository,
        ),
        Provider<NoteReplyWebViewGateway>(
          create: (_) => NotesFeature.createNoteReplyWebViewGateway(),
        ),
        Provider<SubmissionCommentRepository>(
          create: (_) =>
              CommentsFeature.createSubmissionCommentRepository(),
        ),
        Provider<CommentEditRepositoryFactory>(
          create: (_) => CommentsFeature.createCommentEditRepository,
        ),
        Provider<OpenPostRepository>(
          create: (context) => SubmissionsFeature.createOpenPostRepository(
            submissionCommentRepository:
                context.read<SubmissionCommentRepository>(),
          ),
        ),
        Provider<NoteSubmissionPreviewRepository>(
          create: (context) => NotesFeature.createSubmissionPreviewRepository(
            openPostRepository: context.read<OpenPostRepository>(),
          ),
        ),
        ChangeNotifierProvider<TimezoneProvider>.value(
          value: timezoneProvider,
        ),
        ChangeNotifierProvider<NotificationNavigationProvider>(
          create: (_) => NotificationNavigationProvider(),
        ),
        ChangeNotifierProvider<NotificationSettingsProvider>(
          create: (_) => NotificationsFeature.createSettingsProvider(),
        ),
        ChangeNotifierProvider<ThumbnailDisplaySettingsProvider>(
          create: (_) => ThumbnailDisplaySettingsProvider(),
        ),
        ChangeNotifierProvider<TranslatorSettingsProvider>(
          create: (_) => TranslatorSettingsProvider(),
        ),
        ChangeNotifierProvider<PrivacySettingsProvider>(
          create: (_) => PrivacySettingsProvider(),
        ),
        ChangeNotifierProvider<NoteImagePreviewSettingsProvider>(
          create: (_) => NoteImagePreviewSettingsProvider(),
        ),
        ChangeNotifierProvider<CommentSettingsProvider>(
          create: (_) => CommentSettingsProvider(),
        ),
        ChangeNotifierProvider<FANotificationService>(
          create: (_) => NotificationsFeature.createNotificationService(),
        ),
      ],
      child: child,
    );
  }
}
