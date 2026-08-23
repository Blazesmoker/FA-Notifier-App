import 'package:fanotifier/features/settings/data/fur_affinity_contacts_parser.dart';
import 'package:fanotifier/features/settings/data/fur_affinity_settings_parser.dart';
import 'package:fanotifier/features/settings/data/fur_affinity_profile_management_parser.dart';
import 'package:fanotifier/features/settings/data/fur_affinity_settings_remote_data_source.dart';
import 'package:fanotifier/features/settings/domain/fur_affinity_contacts_models.dart';
import 'package:fanotifier/features/settings/domain/fur_affinity_settings_models.dart';
import 'package:fanotifier/features/settings/domain/fur_affinity_profile_management_models.dart';
import 'package:fanotifier/features/settings/domain/fur_affinity_settings_repository.dart';

class FurAffinitySettingsRepositoryImpl
    implements FurAffinitySettingsRepository {
  const FurAffinitySettingsRepositoryImpl({
    FurAffinitySettingsRemoteDataSource? remoteDataSource,
  }) : _remoteDataSource = remoteDataSource ??
            const FurAffinitySettingsRemoteDataSource();

  static final Uri _accountUri =
      Uri.parse('https://www.furaffinity.net$faAccountSettingsPath');
  static final Uri _globalSiteUri =
      Uri.parse('https://www.furaffinity.net$faGlobalSiteSettingsPath');
  static final Uri _userUri =
      Uri.parse('https://www.furaffinity.net$faUserSettingsPath');
  static final Uri _passwordResetUri =
      Uri.parse('https://www.furaffinity.net$faPasswordResetPath');
  static final Uri _contactsUri =
      Uri.parse('https://www.furaffinity.net$faContactsPath');
  static final Uri _profileInfoUri =
      Uri.parse('https://www.furaffinity.net$faProfileInfoPath');
  static final Uri _profileBannerUri =
      Uri.parse('https://www.furaffinity.net$faProfileBannerPath');
  static final Uri _avatarUri =
      Uri.parse('https://www.furaffinity.net$faAvatarManagementPath');

  final FurAffinitySettingsRemoteDataSource _remoteDataSource;

  @override
  Future<FaSettingsFormSnapshot> loadAccountSettings() {
    return _load(_accountUri, faAccountSettingsPath);
  }

  @override
  Future<FaSettingsFormSnapshot> loadGlobalSiteSettings() {
    return _load(_globalSiteUri, faGlobalSiteSettingsPath);
  }

  @override
  Future<FaSettingsFormSnapshot> loadUserSettings() {
    return _load(_userUri, faUserSettingsPath);
  }

  @override
  Future<FaContactsFormSnapshot> loadContacts() async {
    final response = await _remoteDataSource.getAuthenticated(_contactsUri);
    if (response.statusCode != 200) {
      throw FaSettingsRequestException(
        'Fur Affinity returned HTTP ${response.statusCode}.',
        statusCode: response.statusCode,
      );
    }
    try {
      return parseFaContactsForm(response.body);
    } on FaSettingsRequestException catch (error) {
      throw FaSettingsRequestException(
        error.message,
        statusCode: response.statusCode,
      );
    }
  }

  @override
  Future<FaProfileInfoSnapshot> loadProfileInfo() async {
    return FaProfileInfoSnapshot(
      await _load(_profileInfoUri, faProfileInfoPath),
    );
  }

  @override
  Future<FaProfileBannerSnapshot> loadProfileBanner() async {
    final response = await _remoteDataSource.getAuthenticated(_profileBannerUri);
    _requireOk(response);
    return parseFaProfileBanner(response.body);
  }

  @override
  Future<FaAvatarManagementSnapshot> loadAvatarManagement() async {
    final response = await _remoteDataSource.getAuthenticated(_avatarUri);
    _requireOk(response);
    return parseFaAvatarManagement(response.body);
  }

  @override
  Future<FaSettingsMutationResult> saveAccountSettings({
    required FaSettingsFormSnapshot form,
    required Map<String, String?> values,
    required String currentPassword,
  }) {
    final payload = form.buildPayload(values)
      ..['do'] = 'update'
      ..['oldpassword'] = currentPassword
      ..remove('save_settings');
    return _saveSettings(
      uri: form.actionUri,
      referer: _accountUri,
      expectedPath: faAccountSettingsPath,
      payload: payload,
      submittedValues: values,
      ignoredConfirmationFields: const <String>{
        'newpassword',
        'newpassword2',
        'oldpassword',
      },
    );
  }

  @override
  Future<FaSettingsMutationResult> saveGlobalSiteSettings({
    required FaSettingsFormSnapshot form,
    required Map<String, String?> values,
  }) {
    final payload = form.buildPayload(values)
      ..['do'] = 'update'
      ..['save_settings'] = 'Save Settings';
    return _saveSettings(
      uri: form.actionUri,
      referer: _globalSiteUri,
      expectedPath: faGlobalSiteSettingsPath,
      payload: payload,
      submittedValues: values,
    );
  }

  @override
  Future<FaSettingsMutationResult> saveUserSettings({
    required FaSettingsFormSnapshot form,
    required Map<String, String?> values,
  }) {
    final payload = form.buildPayload(values)
      ..['do'] = 'update'
      ..['save_settings'] = 'Save Settings';
    return _saveSettings(
      uri: form.actionUri,
      referer: _userUri,
      expectedPath: faUserSettingsPath,
      payload: payload,
      submittedValues: values,
    );
  }

  @override
  Future<FaSettingsMutationResult> saveContacts({
    required FaContactsFormSnapshot form,
    required Map<String, String?> values,
  }) {
    final payload = form.form.buildPayload(values)..['do'] = 'update';
    return _saveSettings(
      uri: form.form.actionUri,
      referer: _contactsUri,
      expectedPath: faContactsPath,
      payload: payload,
      submittedValues: values,
    );
  }

  @override
  Future<FaSettingsMutationResult> saveProfileInfo({
    required FaProfileInfoSnapshot form,
    required Map<String, String?> values,
  }) {
    final payload = form.form.buildPayload(values)..['do'] = 'update';
    return _saveSettings(
      uri: form.form.actionUri,
      referer: _profileInfoUri,
      expectedPath: faProfileInfoPath,
      payload: payload,
      submittedValues: values,
      acceptOkWithoutConfirmation: true,
    );
  }

  @override
  Future<FaSettingsMutationResult> uploadProfileBanner({
    required FaProfileBannerSnapshot form,
    required FaUploadFile file,
  }) async {
    try {
      final response = await _remoteDataSource.postMultipartAuthenticated(
        form.actionUri,
        referer: _profileBannerUri,
        fields: form.payload,
        fileField: 'profile_banner',
        file: file,
      );
      return _mutationResult(response);
    } catch (error) {
      return FaSettingsMutationResult(success: false, message: '$error');
    }
  }

  @override
  Future<FaSettingsMutationResult> removeProfileBanner(
    FaProfileBannerSnapshot form,
  ) async {
    final actionUri = form.removeActionUri;
    final host = actionUri?.host.toLowerCase();
    final path = actionUri == null
        ? ''
        : actionUri.path.endsWith('/')
            ? actionUri.path
            : '${actionUri.path}/';
    if (actionUri == null ||
        actionUri.scheme != 'https' ||
        (host != 'www.furaffinity.net' && host != 'furaffinity.net') ||
        path != faProfileBannerPath ||
        !form.removePayload.containsKey('action-remove')) {
      return const FaSettingsMutationResult(
        success: false,
        message: 'Fur Affinity did not provide a valid banner removal action.',
      );
    }
    try {
      final response = await _remoteDataSource.postAuthenticated(
        actionUri,
        referer: _profileBannerUri,
        body: form.removePayload,
      );
      return _mutationResult(response);
    } catch (error) {
      return FaSettingsMutationResult(success: false, message: '$error');
    }
  }

  @override
  Future<FaSettingsMutationResult> uploadAvatar({
    required FaAvatarManagementSnapshot form,
    required FaUploadFile file,
  }) async {
    try {
      final response = await _remoteDataSource.postMultipartAuthenticated(
        form.actionUri,
        referer: _avatarUri,
        fields: form.payload,
        fileField: 'avatarfile',
        file: file,
      );
      return _mutationResult(response);
    } catch (error) {
      return FaSettingsMutationResult(success: false, message: '$error');
    }
  }

  @override
  Future<FaSettingsMutationResult> chooseAvatar(Uri uri) {
    return _avatarAction(uri);
  }

  @override
  Future<FaSettingsMutationResult> removeAvatar(Uri uri) {
    return _avatarAction(uri);
  }

  Future<FaSettingsMutationResult> _avatarAction(Uri uri) async {
    if (!_isSafeAvatarAction(uri)) {
      return const FaSettingsMutationResult(
        success: false,
        message: 'Fur Affinity returned an unsafe avatar action.',
      );
    }
    try {
      final response = await _remoteDataSource.sendAuthenticatedWithoutRedirect(
        uri,
        referer: _avatarUri,
      );
      return _mutationResult(response);
    } catch (error) {
      return FaSettingsMutationResult(success: false, message: '$error');
    }
  }

  @override
  Future<FaSettingsMutationResult> sendPasswordRecoveryCode({
    required String username,
    required String email,
  }) {
    return _postPasswordReset(<String, String>{
      'send': 'send',
      'retrname': username,
      'retremail': email,
      'action': 'send_code',
    });
  }

  @override
  Future<FaSettingsMutationResult> resetPassword({
    required String username,
    required String email,
    required String verificationCode,
    required String newPassword,
    required String confirmedPassword,
  }) {
    return _postPasswordReset(<String, String>{
      'send': 'send',
      'retrname_final': username,
      'retremail_final': email,
      'vercode_final': verificationCode,
      'newpw': newPassword,
      'newpwverify': confirmedPassword,
      'action': 'reset_password',
    });
  }

  Future<FaSettingsFormSnapshot> _load(Uri uri, String expectedPath) async {
    final response = await _remoteDataSource.getAuthenticated(uri);
    if (response.statusCode != 200) {
      throw FaSettingsRequestException(
        'Fur Affinity returned HTTP ${response.statusCode}.',
        statusCode: response.statusCode,
      );
    }
    try {
      return parseFaSettingsForm(
        response.body,
        expectedPath: expectedPath,
      );
    } on FaSettingsRequestException catch (error) {
      throw FaSettingsRequestException(
        error.message,
        statusCode: response.statusCode,
      );
    }
  }

  void _requireOk(FaSettingsHttpResponse response) {
    if (response.statusCode != 200) {
      throw FaSettingsRequestException(
        'Fur Affinity returned HTTP ${response.statusCode}.',
        statusCode: response.statusCode,
      );
    }
  }

  FaSettingsMutationResult _mutationResult(FaSettingsHttpResponse response) {
    if (response.statusCode == 302) {
      return const FaSettingsMutationResult(success: true, statusCode: 302);
    }
    final message = extractFaSettingsResponseMessage(response.body);
    final statusSuccess = response.statusCode >= 200 && response.statusCode < 300;
    return FaSettingsMutationResult(
      success: statusSuccess &&
          !isFaSettingsFailureMessage(message) &&
          isFaSettingsSuccessMessage(message),
      statusCode: response.statusCode,
      message: message ??
          (statusSuccess
              ? 'Fur Affinity did not confirm that the action succeeded.'
              : 'Fur Affinity returned HTTP ${response.statusCode}.'),
    );
  }

  bool _isSafeAvatarAction(Uri uri) {
    final host = uri.host.toLowerCase();
    if (uri.scheme != 'https' ||
        (host != 'www.furaffinity.net' && host != 'furaffinity.net') ||
        (uri.hasPort && uri.port != 443)) {
      return false;
    }
    return uri.path.startsWith('/avatar/chooseuseravatar/') ||
        uri.path.startsWith('/avatar/deleteavatar/');
  }

  Future<FaSettingsMutationResult> _saveSettings({
    required Uri uri,
    required Uri referer,
    required String expectedPath,
    required Map<String, String> payload,
    required Map<String, String?> submittedValues,
    Set<String> ignoredConfirmationFields = const <String>{},
    bool acceptOkWithoutConfirmation = false,
  }) async {
    try {
      final response = await _remoteDataSource.postAuthenticated(
        uri,
        referer: referer,
        body: payload,
      );
      if (response.statusCode == 302) {
        return const FaSettingsMutationResult(
          success: true,
          statusCode: 302,
        );
      }
      if (acceptOkWithoutConfirmation && response.statusCode == 200) {
        return const FaSettingsMutationResult(
          success: true,
          statusCode: 200,
        );
      }
      final message = extractFaSettingsResponseMessage(response.body);
      final returnedForm = tryParseFaSettingsForm(
        response.body,
        expectedPath: expectedPath,
      );
      final statusSuccess =
          response.statusCode >= 200 && response.statusCode < 300;
      final messageFailure = isFaSettingsFailureMessage(message);
      final messageSuccess = isFaSettingsSuccessMessage(message);
      final valuesConfirmed = returnedForm == null ||
          _formConfirmsValues(
            returnedForm,
            submittedValues,
            ignoredConfirmationFields,
          );
      final responseConfirmed =
          returnedForm != null || messageSuccess;
      return FaSettingsMutationResult(
        success: statusSuccess &&
            !messageFailure &&
            valuesConfirmed &&
            responseConfirmed,
        statusCode: response.statusCode,
        message: message ??
            (valuesConfirmed
                ? null
                : 'Fur Affinity did not confirm the submitted values.'),
        returnedForm: returnedForm,
      );
    } on FaSettingsRequestException catch (error) {
      return FaSettingsMutationResult(
        success: false,
        statusCode: error.statusCode,
        message: error.message,
      );
    } catch (error) {
      return FaSettingsMutationResult(
        success: false,
        message: error.toString(),
      );
    }
  }

  Future<FaSettingsMutationResult> _postPasswordReset(
    Map<String, String> payload,
  ) async {
    try {
      final response = await _remoteDataSource.postPasswordReset(
        _passwordResetUri,
        body: payload,
      );
      final message = extractFaSettingsResponseMessage(response.body);
      final redirectSuccess = response.statusCode == 302;
      final statusSuccess =
          (response.statusCode >= 200 && response.statusCode < 300) ||
              redirectSuccess;
      final messageFailure = isFaSettingsFailureMessage(message);
      final messageSuccess = isFaSettingsSuccessMessage(message);
      return FaSettingsMutationResult(
        success: statusSuccess &&
            !messageFailure &&
            (redirectSuccess || messageSuccess),
        statusCode: response.statusCode,
        message: message ??
            (redirectSuccess
                ? null
                : 'Fur Affinity did not confirm that the request succeeded.'),
      );
    } on FaSettingsRequestException catch (error) {
      return FaSettingsMutationResult(
        success: false,
        statusCode: error.statusCode,
        message: error.message,
      );
    } catch (error) {
      return FaSettingsMutationResult(
        success: false,
        message: error.toString(),
      );
    }
  }

  bool _formConfirmsValues(
    FaSettingsFormSnapshot form,
    Map<String, String?> submittedValues,
    Set<String> ignoredFields,
  ) {
    for (final entry in submittedValues.entries) {
      if (ignoredFields.contains(entry.key)) continue;
      final field = form.field(entry.key);
      if (field == null || !field.enabled) continue;
      if (field.type == 'checkbox') {
        if (field.checked != (entry.value != null)) return false;
      } else if (entry.value != null && field.value != entry.value) {
        return false;
      }
    }
    return true;
  }
}
