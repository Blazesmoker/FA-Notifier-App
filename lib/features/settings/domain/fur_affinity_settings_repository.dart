import 'package:fanotifier/features/settings/domain/fur_affinity_contacts_models.dart';
import 'package:fanotifier/features/settings/domain/fur_affinity_settings_models.dart';

abstract interface class FurAffinitySettingsRepository {
  Future<FaSettingsFormSnapshot> loadAccountSettings();

  Future<FaSettingsFormSnapshot> loadGlobalSiteSettings();

  Future<FaSettingsFormSnapshot> loadUserSettings();

  Future<FaContactsFormSnapshot> loadContacts();

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
