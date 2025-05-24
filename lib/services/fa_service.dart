// lib/services/fa_service.dart

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import '../model/user_profile.dart';
import '../model/notifications.dart';

class FaService {
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  /// Fetches the user profile information (display name and profile picture).
  Future<UserProfile?> fetchUserProfile({ BuildContext? context }) async {
    String? cookieA = await _secureStorage.read(key: 'fa_cookie_a');
    String? cookieB = await _secureStorage.read(key: 'fa_cookie_b');
    String? cfClearance = await _secureStorage.read(key: 'fa_cookie_cf_clearance');

    print('[FaService] fetchUserProfile: cookieA=$cookieA, cookieB=$cookieB, cf_clearance=$cfClearance');

    if (cookieA == null || cookieB == null) {
      print('[FaService] No cookies found. User might not be logged in.');
      return null;
    }


    String cookiesHeader = 'a=$cookieA; b=$cookieB';
    if (cfClearance != null && cfClearance.isNotEmpty) {
      cookiesHeader += '; cf_clearance=$cfClearance';
    }

    const String url = 'https://www.furaffinity.net/';
    print('[FaService] Making HTTP GET request to $url with cookies: $cookiesHeader');

    final response = await http.get(
      Uri.parse(url),
      headers: {
        'Cookie': cookiesHeader,
        'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/95.0.4638.69 Safari/537.36',
      },
    );

    print('[FaService] Response received: statusCode=${response.statusCode}');
    print('[FaService] Response body snippet: ${response.body.substring(0, 100)}');

    if (response.statusCode == 200) {
      final document = html_parser.parse(response.body);

      final bool isClassic = (document.querySelector('body')
          ?.attributes['data-static-path']
          ?.contains('classic')) ??
          false;

      final myUsernameAnchor = document.querySelector('a#my-username');
      if (myUsernameAnchor != null) {
        String displayName;
        if (!isClassic) {

          myUsernameAnchor.querySelectorAll('span.hideondesktop').forEach((element) {
            element.remove();
          });
          displayName = myUsernameAnchor.text.trim();
        } else {
          displayName = myUsernameAnchor.text.trim();
        }

        String? profileImageUrl;
        if (!isClassic) {
          final avatarImg = document.querySelector(
            'div.floatleft.hideonmobile > a[href^="/user/"] img.loggedin_user_avatar.avatar',
          );
          profileImageUrl =
              avatarImg?.attributes['src']?.replaceFirst('//', 'https://');
        } else {
          final profilePath = myUsernameAnchor.attributes['href'];
          if (profilePath != null) {
            final String profileUrl = profilePath.startsWith('http')
                ? profilePath
                : 'https://www.furaffinity.net$profilePath';
            print('[FaService] Fetching classic profile page: $profileUrl');
            final profileResponse = await http.get(
              Uri.parse(profileUrl),
              headers: {
                'Cookie': cookiesHeader,
                'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
                    '(KHTML, like Gecko) Chrome/95.0.4638.69 Safari/537.36',
              },
            );
            print('[FaService] Classic profile page response: ${profileResponse.statusCode}');
            if (profileResponse.statusCode == 200) {
              final profileDoc = html_parser.parse(profileResponse.body);
              final avatarElement = profileDoc.querySelector('img.avatar');
              profileImageUrl = avatarElement?.attributes['src'];
              if (profileImageUrl != null && profileImageUrl.startsWith('//')) {
                profileImageUrl = 'https:' + profileImageUrl;
              }
            } else {
              print('[FaService] Failed to load user profile page: ${profileResponse.statusCode}');
            }
          }
        }

        if (displayName.isNotEmpty && profileImageUrl != null) {
          print('[FaService] Parsed user profile: $displayName, avatar: $profileImageUrl');
          return UserProfile(username: displayName, profileImageUrl: profileImageUrl);
        }
      }
      print('[FaService] Could not parse user profile.');
      return null;
    } else if (response.statusCode == 403 && response.body.contains('Just a moment')) {
      print('[FaService] 403 with Cloudflare challenge for user profile.');
      // No human verification dialog or retry logic, simply return null.
      return null;
    } else {
      print('[FaService] fetchUserProfile received unexpected status code: ${response.statusCode}');
      print('URL: $url');
      print('Body: ${response.body.substring(0, 100)}');
    }
    return null;
  }



  /// Fetches the user's notifications and the number of registered users online.
  Future<Notifications?> fetchNotifications({ BuildContext? context }) async {
    final cookieKeys = ['a', 'b', 'cc', 'cf_clearance', 'folder', 'nodesc', 'sz', 'sfw'];
    String cookies = '';
    for (var key in cookieKeys) {
      final val = await _secureStorage.read(key: 'fa_cookie_$key');
      if (val != null && val.isNotEmpty) {
        cookies += '$key=$val; ';
      }
    }

    if (cookies.isEmpty) {
      print('[FaService] No cookies => not logged in.');
      return null;
    }

    print('[FaService] Sending notifications request with cookies: $cookies');

    const String notificationsUrl = 'https://www.furaffinity.net/';
    final response = await http.get(
      Uri.parse(notificationsUrl),
      headers: {
        'Cookie': cookies,
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/95.0.4638.69 Safari/537.36',
      },
    );

    print('[FaService] fetchNotifications => ${response.statusCode}');
    print('[FaService] Response snippet: ${response.body.substring(0, 100)}');

    if (response.statusCode == 200) {
      final doc = html_parser.parse(response.body);
      bool isClassic = (doc.querySelector('body')?.attributes['data-static-path']?.contains('classic')) ?? false;

      String submissions = '0';
      String watches = '0';
      String journals = '0';
      String notes = '0';
      String comments = '0';
      String favorites = '0';



      if (isClassic) {
        final notifContainer = doc.querySelector('li.noblock');
        if (notifContainer != null) {
          final links = notifContainer.querySelectorAll('a.notification-container');
          for (var link in links) {
            final title = link.attributes['title'] ?? '';
            final count = _extractNumber(title);
            if (title.contains('Submission')) submissions = count;
            else if (title.contains('Watch')) watches = count;
            else if (title.contains('Journal')) journals = count;
            else if (title.contains('Note')) notes = count;
            else if (title.contains('Comment')) comments = count;
            else if (title.contains('Favorite')) favorites = count;
          }
        }
      } else {
        final messageBar = doc.querySelector('li.message-bar-desktop');
        if (messageBar != null) {
          final links = messageBar.querySelectorAll('a.notification-container.inline');
          for (var link in links) {
            final title = link.attributes['title'] ?? '';
            final count = _extractNumber(title);
            if (title.contains('Submission')) submissions = count;
            else if (title.contains('Watch')) watches = count;
            else if (title.contains('Journal')) journals = count;
            else if (title.contains('Note')) notes = count;
            else if (title.contains('Comment')) comments = count;
            else if (title.contains('Favorite')) favorites = count;
          }
        }
      }

      // Extract the number of registered users online
      String registeredUsersOnline = '0';
      if (isClassic) {
        final center = doc.querySelector('div.footer center');
        if (center != null) {
          final text = center.text;
          final match = RegExp(r'(\d+)\s+registered').firstMatch(text);
          if (match != null) {
            registeredUsersOnline = match.group(1)?.replaceAll(',', '') ?? '0';
          }
        }
      } else {
        final statsDiv = doc.querySelector('div.online-stats');
        if (statsDiv != null) {
          final text = statsDiv.text;
          final match = RegExp(r'(\d+)\s+registered').firstMatch(text);
          if (match != null) {
            registeredUsersOnline = match.group(1)?.replaceAll(',', '') ?? '0';
          }
        }
      }

      print('[FaService] Notifications parsed: sub=$submissions, watch=$watches, journal=$journals, note=$notes, comment=$comments, fav=$favorites, online=$registeredUsersOnline');
      return Notifications(
        submissions: submissions,
        watches: watches,
        journals: journals,
        notes: notes,
        comments: comments,
        favorites: favorites,
        registeredUsersOnline: registeredUsersOnline,
      );
    } else if (response.statusCode == 403 && response.body.contains('Just a moment')) {
      print('[FaService] 403 with Cloudflare challenge for notifications.');

      return null;
    } else {
      print('[FaService] fetchNotifications => ${response.statusCode}');
      print('URL: $notificationsUrl');
      print('Body: ${response.body.substring(0, 100)}');
    }

    return null;
  }

  /// Helper method to extract a number from a given text.
  String _extractNumber(String text) {
    final Match? match = RegExp(r'\d+').firstMatch(text);
    return match?.group(0) ?? '0'; // Extracts "1000" from "1000 Favorite Notifications"
  }
}
