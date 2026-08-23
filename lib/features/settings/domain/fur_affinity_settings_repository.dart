import 'package:fanotifier/features/settings/domain/fur_affinity_contacts_models.dart';
import 'package:fanotifier/features/settings/domain/fur_affinity_settings_models.dart';
import 'package:fanotifier/features/settings/domain/fur_affinity_profile_management_models.dart';

abstract interface class FurAffinitySettingsRepository {
  Future<FaSettingsFormSnapshot> loadAccountSettings();

  Future<FaSettingsFormSnapshot> loadGlobalSiteSettings();

  Future<FaSettingsFormSnapshot> loadUserSettings();

  Future<FaContactsFormSnapshot> loadContacts();

  Future<FaProfileInfoSnapshot> loadProfileInfo();

  Future<FaProfileBannerSnapshot> loadProfileBanner();

  Future<FaAvatarManagementSnapshot> loadAvatarManagement();

  Future<FaSettingsMutationResult> saveAccountSettings({
    required FaSettingsFormSnapshot form,
    required Map<String, String?> values,
    required String currentPassword,
  });

  Future<FaSettingsMutationResult> saveGlobalSiteSettings({
    required FaSettingsFormSnapshot form,
    required Map<String, String?> values,
  });

  Future<FaSettingsMutationResult> saveUserSettings({
    required FaSettingsFormSnapshot form,
    required Map<String, String?> values,
  });

  Future<FaSettingsMutationResult> saveContacts({
    required FaContactsFormSnapshot form,
    required Map<String, String?> values,
  });

  Future<FaSettingsMutationResult> saveProfileInfo({
    required FaProfileInfoSnapshot form,
    required Map<String, String?> values,
  });

  Future<FaSettingsMutationResult> uploadProfileBanner({
    required FaProfileBannerSnapshot form,
    required FaUploadFile file,
  });

  Future<FaSettingsMutationResult> removeProfileBanner(
    FaProfileBannerSnapshot form,
  );

  Future<FaSettingsMutationResult> uploadAvatar({
    required FaAvatarManagementSnapshot form,
    required FaUploadFile file,
  });

  Future<FaSettingsMutationResult> chooseAvatar(Uri uri);

  Future<FaSettingsMutationResult> removeAvatar(Uri uri);

  Future<FaSettingsMutationResult> sendPasswordRecoveryCode({
    required String username,
    required String email,
  });

  Future<FaSettingsMutationResult> resetPassword({
    required String username,
    required String email,
    required String verificationCode,
    required String newPassword,
    required String confirmedPassword,
  });
}
