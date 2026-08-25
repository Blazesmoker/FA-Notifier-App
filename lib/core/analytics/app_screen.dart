import 'package:flutter/widgets.dart';

class AppScreen {
  const AppScreen(this.name, this.screenClass);

  final String name;
  final String screenClass;
}

abstract final class AppScreens {
  static const login = AppScreen('Login', 'LoginScreen');
  static const browse = AppScreen('Browse', 'BrowseScreen');
  static const search = AppScreen('Search', 'SearchScreen');
  static const submissions = AppScreen('Submissions', 'SubmissionsScreen');
  static const notifications =
      AppScreen('Notifications', 'NotificationsScreen');
  static const notesInbox = AppScreen('Notes / Inbox', 'NotesInboxScreen');
  static const notesSent = AppScreen('Notes / Sent', 'NotesSentScreen');
  static const submissionDetails =
      AppScreen('Submission Details', 'SubmissionDetailsScreen');
  static const journalDetails =
      AppScreen('Journal Details', 'JournalDetailsScreen');
  static const noteDetails = AppScreen('Note Details', 'NoteDetailsScreen');
  static const newNote = AppScreen('New Note', 'NewNoteScreen');
  static const noteReply = AppScreen('Reply to Note', 'NoteReplyScreen');
  static const notesTrash = AppScreen('Notes / Trash', 'NotesTrashScreen');
  static const profileHome = AppScreen('Profile / Home', 'ProfileHomeScreen');
  static const profileGallery =
      AppScreen('Profile / Gallery', 'ProfileGalleryScreen');
  static const profileScraps =
      AppScreen('Profile / Scraps', 'ProfileScrapsScreen');
  static const profileFavorites =
      AppScreen('Profile / Favorites', 'ProfileFavoritesScreen');
  static const profileJournals =
      AppScreen('Profile / Journals', 'ProfileJournalsScreen');
  static const imageViewer = AppScreen('Image Viewer', 'ImageViewerScreen');
  static const documentViewer =
      AppScreen('Document Viewer', 'DocumentViewerScreen');
  static const uploadSubmission =
      AppScreen('Upload Submission', 'UploadSubmissionScreen');
  static const submissionTemplates =
      AppScreen('Submission Templates', 'SubmissionTemplatesScreen');
  static const finalizeSubmission =
      AppScreen('Finalize Submission', 'FinalizeSubmissionScreen');
  static const editSubmission =
      AppScreen('Edit Submission', 'EditSubmissionScreen');
  static const manageSubmissions =
      AppScreen('Manage Submissions', 'ManageSubmissionsScreen');
  static const manageSubmissionFolders = AppScreen(
    'Manage Submissions / Folders',
    'ManageSubmissionFoldersScreen',
  );
  static const editSubmissionFolder = AppScreen(
    'Manage Submissions / Folder Editor',
    'SubmissionFolderEditorScreen',
  );
  static const createJournal =
      AppScreen('Create Journal', 'CreateJournalScreen');
  static const editJournal = AppScreen('Edit Journal', 'EditJournalScreen');
  static const journalReply =
      AppScreen('Reply to Journal Comment', 'JournalReplyScreen');
  static const editJournalComment =
      AppScreen('Edit Journal Comment', 'EditJournalCommentScreen');
  static const addComment = AppScreen('Add Comment', 'AddCommentScreen');
  static const replyToComment =
      AppScreen('Reply to Comment', 'ReplyToCommentScreen');
  static const editComment = AppScreen('Edit Comment', 'EditCommentScreen');
  static const postShout = AppScreen('Post Shout', 'PostShoutScreen');
  static const browseFilters =
      AppScreen('Browse Filters', 'BrowseFiltersScreen');
  static const searchFilters =
      AppScreen('Search Filters', 'SearchFiltersScreen');
  static const keywordSearch =
      AppScreen('Keyword Search', 'KeywordSearchScreen');
  static const findSource = AppScreen('Find Source', 'FindSourceScreen');
  static const settings = AppScreen('Settings', 'SettingsScreen');
  static const appSettings = AppScreen('App Settings', 'AppSettingsScreen');
  static const furAffinitySettings =
      AppScreen('FurAffinity Settings', 'FurAffinitySettingsScreen');
  static const furAffinityAccountSettings = AppScreen(
    'FurAffinity Settings / Account',
    'FurAffinityAccountSettingsScreen',
  );
  static const furAffinityGlobalSiteSettings = AppScreen(
    'FurAffinity Settings / Global Site',
    'FurAffinityGlobalSiteSettingsScreen',
  );
  static const furAffinityUserSettings = AppScreen(
    'FurAffinity Settings / User',
    'FurAffinityUserSettingsScreen',
  );
  static const furAffinityContactsAndMedia = AppScreen(
    'Profile / Contacts & Social Media',
    'ContactsAndMediaScreen',
  );
  static const furAffinityProfileInfo = AppScreen(
    'Profile / Profile Info',
    'ProfileInfoScreen',
  );
  static const furAffinityProfileBanner = AppScreen(
    'Profile / Profile Banner',
    'ProfileBannerScreen',
  );
  static const furAffinityAvatarManagement = AppScreen(
    'Profile / Avatar Management',
    'AvatarManagementScreen',
  );
  static const furAffinityPasswordReset = AppScreen(
    'FurAffinity Settings / Password Reset',
    'FurAffinityPasswordResetScreen',
  );
  static const notificationSettings =
      AppScreen('Notification Settings', 'NotificationSettingsScreen');
  static const noteSettings = AppScreen('Note Settings', 'NoteSettingsScreen');
  static const commentSettings =
      AppScreen('Comment Settings', 'CommentSettingsScreen');
  static const thumbnailSettings =
      AppScreen('Thumbnail Settings', 'ThumbnailSettingsScreen');
  static const translatorSettings =
      AppScreen('Translator Settings', 'TranslatorSettingsScreen');
  static const appIconSettings =
      AppScreen('App Icon Settings', 'AppIconSettingsScreen');
  static const homeScreenSettings =
      AppScreen('Home Screen Settings', 'HomeScreenSettingsScreen');
  static const tagBlocklist =
      AppScreen('Tag Blocklist', 'TagBlocklistScreen');
  static const viewList = AppScreen('User List', 'UserListScreen');
  static const privacySettings =
      AppScreen('Privacy Settings', 'PrivacySettingsScreen');
  static const privacyConsent =
      AppScreen('Privacy Consent', 'PrivacyConsentScreen');
  static const update = AppScreen('App Update', 'AppUpdateScreen');
  static const cloudflareCheck =
      AppScreen('Security Check', 'SecurityCheckScreen');

  static AppScreen notificationSection(String? title) {
    const known = <String, String>{
      'submission': 'Submissions',
      'watch': 'Watches',
      'comment': 'Comments',
      'favorite': 'Favorites',
      'journal': 'Journals',
      'shout': 'Shouts',
    };
    final normalized = title?.trim().toLowerCase() ?? '';
    final safeTitle = known.entries
        .firstWhere(
          (entry) => normalized.contains(entry.key),
          orElse: () => const MapEntry('notifications', 'Overview'),
        )
        .value;
    return AppScreen(
      'Notifications / $safeTitle',
      'Notifications${safeTitle}Screen',
    );
  }
}

class AnalyticsRouteSettings extends RouteSettings {
  const AnalyticsRouteSettings(this.screen);

  final AppScreen screen;
}
