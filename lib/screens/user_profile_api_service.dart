import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as dom;

import '../network.dart';
import '../model/shout.dart';
import '../model/user_link.dart';

class UserProfileParsed {
  UserProfileParsed({
    required this.profileBannerUrl,
    required this.profileImageUrl,
    required this.profileDisplayName,
    required this.profileUserNamePart,
    required this.symbolUsername,
    required this.username,
    required this.userTitle,
    required this.registrationDate,
    required this.userDescription,
    required this.hasRealUserProfile,
    required this.isClassicMarkup,
    required this.acceptingTrades,
    required this.acceptingCommissions,
    required this.userIconBeforeUrls,
    required this.userIconAfterUrls,
    required this.views,
    required this.submissions,
    required this.favs,
    required this.commentsEarned,
    required this.commentsMade,
    required this.journals,
    required this.featuredImageUrl,
    required this.featuredImageTitle,
    required this.featuredPostNumber,
    required this.userProfileImageUrl,
    required this.userProfilePostNumber,
    required this.userProfileTexts,
    required this.contactInformationLinks,
    required this.recentWatchers,
    required this.recentWatchersCount,
    required this.recentlyWatched,
    required this.recentlyWatchedCount,
    required this.shouts,
    required this.shoutPaginationKey,
    required this.currentShoutPage,
    required this.totalShoutPages,
    required this.watchLink,
    required this.unwatchLink,
    required this.blockLink,
    required this.unblockLink,
    required this.isWatching,
    required this.isBlocked,
    required this.isOwnProfile,
  });

  String? profileBannerUrl;
  String? profileImageUrl;
  String? profileDisplayName;
  String? profileUserNamePart;
  String? symbolUsername;
  String username;
  String? userTitle;
  String? registrationDate;
  String? userDescription;
  bool hasRealUserProfile;
  bool isClassicMarkup;
  bool acceptingTrades;
  bool acceptingCommissions;
  List<String> userIconBeforeUrls;
  List<String> userIconAfterUrls;
  int? views;
  int? submissions;
  int? favs;
  int? commentsEarned;
  int? commentsMade;
  int? journals;
  String? featuredImageUrl;
  String? featuredImageTitle;
  String? featuredPostNumber;
  String? userProfileImageUrl;
  String? userProfilePostNumber;
  String? userProfileTexts;
  List<Map<String, String>> contactInformationLinks;
  List<UserLink> recentWatchers;
  int recentWatchersCount;
  List<UserLink> recentlyWatched;
  int recentlyWatchedCount;
  List<Shout> shouts;
  String? shoutPaginationKey;
  int currentShoutPage;
  int totalShoutPages;
  String? watchLink;
  String? unwatchLink;
  String? blockLink;
  String? unblockLink;
  bool isWatching;
  bool isBlocked;
  bool isOwnProfile;
}

class UserProfileFetchPayload {
  final String sanitizedUsername;
  final String htmlBody;
  final String sfwValue;

  UserProfileFetchPayload({
    required this.sanitizedUsername,
    required this.htmlBody,
    required this.sfwValue,
  });
}

class ShoutPagePayload {
  final String body;
  final int nextPage;

  ShoutPagePayload({
    required this.body,
    required this.nextPage,
  });
}

class UserProfileApiService {
  UserProfileApiService(this._secureStorage);

  final FlutterSecureStorage _secureStorage;
  final RegExp _usernameSanitizeRegex = RegExp(r'[^a-zA-Z0-9\\-_.~]');

  String _sanitizeUsername(String username) {
    return username.replaceAll(_usernameSanitizeRegex, '').toLowerCase();
  }

  Future<UserProfileFetchPayload> fetchProfile({
    required String nickname,
    required bool sfwEnabled,
  }) async {
    final cookieA = await _secureStorage.read(key: 'fa_cookie_a');
    final cookieB = await _secureStorage.read(key: 'fa_cookie_b');

    if (cookieA == null || cookieB == null) {
      throw StateError('No cookies found. User might not be logged in.');
    }

    final sanitizedUsername = _sanitizeUsername(nickname);
    final sfwValue = sfwEnabled ? '1' : '0';
    final profileUrl = 'https://www.furaffinity.net/user/$sanitizedUsername/';

    final response = await httpClient.get(
      Uri.parse(profileUrl),
      headers: {
        'Cookie': 'a=$cookieA; b=$cookieB; sfw=$sfwValue',
        'User-Agent': 'Mozilla/5.0 (compatible; YourApp/1.0)',
      },
    );

    if (response.statusCode != 200) {
      throw HttpException(
        'Failed to fetch profile: ${response.statusCode}',
        uri: Uri.parse(profileUrl),
      );
    }

    final decodedBody = utf8.decode(response.bodyBytes, allowMalformed: true);

    return UserProfileFetchPayload(
      sanitizedUsername: sanitizedUsername,
      htmlBody: decodedBody,
      sfwValue: sfwValue,
    );
  }

  Future<ShoutPagePayload?> fetchShoutPage({
    required String sanitizedUsername,
    required String? shoutPaginationKey,
    required int nextPage,
    required bool sfwEnabled,
  }) async {
    if (shoutPaginationKey == null || shoutPaginationKey.isEmpty) {
      return null;
    }

    final cookieA = await _secureStorage.read(key: 'fa_cookie_a');
    final cookieB = await _secureStorage.read(key: 'fa_cookie_b');
    if (cookieA == null || cookieB == null) {
      throw StateError('No cookies found. User might not be logged in.');
    }

    final sfwValue = sfwEnabled ? '1' : '0';
    final url = 'https://www.furaffinity.net/user/$sanitizedUsername/';

    final response = await http.post(
      Uri.parse(url),
      headers: {
        'Cookie': 'a=$cookieA; b=$cookieB; sfw=$sfwValue',
        'Content-Type': 'application/x-www-form-urlencoded',
        'User-Agent': 'Mozilla/5.0 (compatible; YourApp/1.0)',
        'Referer': 'https://www.furaffinity.net/user/$sanitizedUsername/',
        'X-Requested-With': 'XMLHttpRequest',
      },
      body: {
        'action': 'shout_pagination',
        'key': shoutPaginationKey,
        'shout_page': nextPage.toString(),
      },
    );

    if (response.statusCode != 200) {
      throw HttpException(
        'Failed to load shouts page: ${response.statusCode}',
        uri: Uri.parse(url),
      );
    }

    final decodedBody = utf8.decode(response.bodyBytes, allowMalformed: true);
    return ShoutPagePayload(body: decodedBody, nextPage: nextPage);
  }

  /// Parse additional shouts returned from a pagination call.
  /// Expects the FA JSON payload that includes HTML fragments.
  List<Shout> parseAdditionalShoutsJson(
    String jsonBody,
    Set<String> existingShoutIds,
  ) {
    final List<Shout> newShouts = [];
    try {
      final Map<String, dynamic> jsonData = json.decode(jsonBody);
      if (!jsonData.containsKey('shouts')) return newShouts;

      final shoutsList = jsonData['shouts'] as List<dynamic>;
      for (var shoutData in shoutsList) {
        // Extract shout ID from anchor_id if available
        String shoutId = shoutData['anchor_id'] ?? '';
        if (shoutId.startsWith('shout-')) {
          shoutId = shoutId.substring('shout-'.length);
        }

        // Skip duplicates
        if (shoutId.isNotEmpty && existingShoutIds.contains(shoutId)) {
          continue;
        }

        // Parse the HTML content from JSON to extract username and other details
        String avatarUrl = shoutData['avatar_url'] ?? '';
        if (avatarUrl.startsWith('//')) {
          avatarUrl = 'https:$avatarUrl';
        }

        // Parse the display name HTML
        String displayNameHtml = shoutData['shout_display_name_with_icons'] ?? '';
        final displayNameDoc = html_parser.parse(displayNameHtml);

        final displayNameElem = displayNameDoc.querySelector('.js-displayName');
        final userNameElem = displayNameDoc.querySelector('a.c-usernameBlock__userName span');
        final symbolElem = displayNameDoc.querySelector('.c-usernameBlock__symbol');

        String displayName = displayNameElem?.text.trim() ?? 'Unknown';
        String userNamePart = userNameElem?.text.trim() ?? '';
        String symbol = symbolElem?.text.trim() ?? "~";

        // Process username
        final usernameWithoutSymbol = userNamePart.replaceFirst(symbol, '').trim();
        String cmtUsername = (usernameWithoutSymbol.isEmpty ||
                displayName.toLowerCase() == usernameWithoutSymbol.toLowerCase())
            ? displayName
            : '$displayName\n@$usernameWithoutSymbol';

        // Extract profile nickname from HTML
        String profileNickname = 'Unknown';
        final profileLink = displayNameDoc.querySelector('a[href*="/user/"]');
        if (profileLink != null) {
          String? href = profileLink.attributes['href'];
          if (href != null) {
            profileNickname = href.split('/').where((part) => part.isNotEmpty).last;
          }
        }

        // Extract date from thisdate HTML
        String relativeDate = 'Unknown date';
        String fullDate = 'Unknown date';
        String dateHtml = shoutData['thisdate'] ?? '';
        if (dateHtml.isNotEmpty) {
          final dateDoc = html_parser.parse(dateHtml);
          final dateElem = dateDoc.querySelector('span.popup_date');
          if (dateElem != null) {
            relativeDate = dateElem.text.trim();
            fullDate = dateElem.attributes['title']?.trim() ?? relativeDate;
          }
        }

        // Get message text
        String text = shoutData['message'] ?? '';

        // Extract icon URLs from display name HTML
        List<String> shoutIconBeforeUrls = [];
        List<String> shoutIconAfterUrls = [];

        final beforeIcons = displayNameDoc.querySelectorAll('usericon-block-before img');
        shoutIconBeforeUrls = beforeIcons.map((imgElem) {
          String? src = imgElem.attributes['src'];
          if (src != null) {
            if (src.startsWith('//')) return 'https:$src';
            if (src.startsWith('/')) return 'https://www.furaffinity.net$src';
            return src;
          }
          return '';
        }).where((src) => src.isNotEmpty).toList();

        final afterIcons = displayNameDoc.querySelectorAll('usericon-block-after img');
        shoutIconAfterUrls = afterIcons.map((imgElem) {
          String? src = imgElem.attributes['src'];
          if (src != null) {
            if (src.startsWith('//')) return 'https:$src';
            if (src.startsWith('/')) return 'https://www.furaffinity.net$src';
            return src;
          }
          return '';
        }).where((src) => src.isNotEmpty).toList();

        newShouts.add(Shout(
          id: shoutId,
          avatarUrl: avatarUrl,
          username: cmtUsername,
          profileNickname: profileNickname,
          date: relativeDate,
          text: text,
          popupDateFull: fullDate,
          popupDateRelative: relativeDate,
          iconBeforeUrls: shoutIconBeforeUrls,
          iconAfterUrls: shoutIconAfterUrls,
          symbol: symbol,
        ));
      }
    } catch (_) {
      // Ignore parsing errors; caller can handle empty results.
    }

    return newShouts;
  }

  UserProfileParsed parseUserProfile(String htmlBody) {
    final document = html_parser.parse(htmlBody);

    bool localHasRealUserProfile = true;

    String? userProfileImageUrl;
    String? userProfilePostNumber;
    String? userProfileTexts;

    // Profile banner
    String? profileBannerUrl;
    final bannerElem = document.querySelector('site-banner picture source[media="(min-width: 800px)"]')
        ?? document.querySelector('site-banner img')
        ?? document.querySelector('source[media="(min-width: 800px)"]');
    if (bannerElem != null) {
      String bannerUrl = bannerElem.attributes['srcset'] ?? bannerElem.attributes['src'] ?? '';
      if (bannerUrl.startsWith('/themes/beta/img/banners/logo/')) {
        profileBannerUrl = 'https://www.furaffinity.net$bannerUrl';
      } else if (bannerUrl.startsWith('//')) {
        profileBannerUrl = 'https:$bannerUrl';
      } else if (bannerUrl.startsWith('http://') || bannerUrl.startsWith('https://')) {
        profileBannerUrl = bannerUrl;
      } else {
        profileBannerUrl = 'https://www.furaffinity.net$bannerUrl';
      }
    } else {
      profileBannerUrl = 'https://d.furaffinity.net/media/banners/modern/fa-banner-summer.jpg';
    }

    // Profile picture (avatar)
    String? profileImageUrl;
    final profilePicElem = document.querySelector('userpage-nav-avatar img')
        ?? document.querySelector('img.avatar');
    profileImageUrl = profilePicElem != null
        ? (profilePicElem.attributes['src']?.replaceFirst('//', 'https://'))
        : null;

    // Username/display
    final displayNameElem = document.querySelector('a.c-usernameBlock__displayName .js-displayName')
        ?? document.querySelector('a.js-displayName-block .js-displayName');
    final displayName = displayNameElem?.text.trim() ?? 'Unknown User';

    final userNameElem = document.querySelector('a.c-usernameBlock__userName span')
        ?? document.querySelector('a.js-userName-block span');
    final symbolElem = document.querySelector('a.c-usernameBlock__userName span .c-usernameBlock__symbol')
        ?? document.querySelector('a.js-userName-block span .c-usernameBlock__symbol');

    String symbolText = symbolElem?.text.trim() ?? '';
    String fullUserName = userNameElem?.text.trim() ?? '';
    String nicknameWithoutSymbol = fullUserName;
    if (symbolText.isNotEmpty) {
      nicknameWithoutSymbol = fullUserName.replaceFirst(symbolText, '').trim();
    }
    final symbolUsername = symbolText.isNotEmpty ? '$symbolText $nicknameWithoutSymbol' : fullUserName;
    final username = displayName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9\\-_.~]'), '');

    // Icons
    List<String> userIconBeforeUrls = [];
    List<String> userIconAfterUrls = [];
    final usernameContainer = document.querySelector('.c-usernameBlock') ?? document.querySelector('div.c-usernameBlock');
    final iconBeforeElems = usernameContainer?.querySelectorAll('usericon-block-before img');
    if (iconBeforeElems != null && iconBeforeElems.isNotEmpty) {
      userIconBeforeUrls = iconBeforeElems.map((imgElem) {
        String? src = imgElem.attributes['src'];
        if (src != null) {
          if (src.startsWith('//')) return 'https:$src';
          if (src.startsWith('/')) return 'https://www.furaffinity.net$src';
          return src;
        }
        return '';
      }).where((src) => src.isNotEmpty).toList();
    }
    final iconAfterElems = usernameContainer?.querySelectorAll('usericon-block-after img');
    if (iconAfterElems != null && iconAfterElems.isNotEmpty) {
      userIconAfterUrls = iconAfterElems.map((imgElem) {
        String? src = imgElem.attributes['src'];
        if (src != null) {
          if (src.startsWith('//')) return 'https:$src';
          if (src.startsWith('/')) return 'https://www.furaffinity.net$src';
          return src;
        }
        return '';
      }).where((src) => src.isNotEmpty).toList();
    }

    // User title & registration date
    String? userTitle;
    String? registrationDate;
    final userTitleElem = document.querySelector('span.user-title');
    if (userTitleElem != null) {
      String fullText = userTitleElem.text.trim();
      final regExp = RegExp(r'Registered:\\s*(.+)$');
      final regMatch = regExp.firstMatch(fullText);
      if (regMatch != null) {
        registrationDate = regMatch.group(1)!.trim();
        userTitle = fullText.substring(0, regMatch.start).trim();
        if (userTitle.endsWith("|")) {
          userTitle = userTitle.substring(0, userTitle.length - 1).trim();
        }
      } else {
        userTitle = fullText;
        registrationDate = "";
      }
    } else {
      final classicHtml = document.body?.innerHtml ?? "";
      final userTitleMatch = RegExp(r'<b>\\s*User Title:\\s*<\\/b>\\s*([^<]+)').firstMatch(classicHtml);
      final registeredMatch = RegExp(r'<b>\\s*Registered Since:\\s*<\\/b>\\s*([^<]+)').firstMatch(classicHtml);
      userTitle = userTitleMatch?.group(1)?.trim() ?? "";
      registrationDate = registeredMatch?.group(1)?.trim() ?? 'N/A';
    }

    // Description
    String? userDescription;
    bool hasRealUserProfile = true;
    final sectionElem = document.querySelector('section.userpage-layout-profile') ?? document.querySelector('td.ldot');
    if (sectionElem != null) {
      if (sectionElem.localName == 'section') {
        userDescription = sectionElem.outerHtml.trim();
      } else if (sectionElem.localName == 'td') {
        String classicHtml = sectionElem.innerHtml;
        const headerMarker = '<b>Artist Profile:</b><br>';
        final splitIndex = classicHtml.indexOf(headerMarker);
        if (splitIndex != -1) {
          userDescription = classicHtml.substring(splitIndex + headerMarker.length).trim();
        } else {
          userDescription = classicHtml.trim();
        }
      }

      if (userDescription != null && userDescription.contains('<i>Not Available...</i>')) {
        hasRealUserProfile = false;
      }
    } else {
      userDescription = 'No description available.';
      hasRealUserProfile = false;
    }

    // Stats
    int? views;
    int? submissions;
    int? favs;
    int? commentsEarned;
    int? commentsMade;
    int? journals;
    dom.Element? statsSection = document.querySelector('.userpage-section-right .section-body');
    String statsText = "";
    if (statsSection != null) {
      statsText = statsSection.text.trim();
    } else {
      dom.Element? classicStatsTable;
      for (dom.Element table in document.querySelectorAll('table')) {
        var firstRow = table.querySelector('tr');
        if (firstRow != null) {
          var firstCell = firstRow.querySelector('td');
          if (firstCell != null && firstCell.text.trim() == 'Statistics') {
            classicStatsTable = table;
            break;
          }
        }
      }
      if (classicStatsTable != null) {
        var statsCell = classicStatsTable.querySelector('tr:nth-child(2) td[align=\"left\"]');
        statsText = statsCell?.text.trim() ?? "";
      }
    }

    int? _extract(String label) {
      final regex = RegExp('$label\\\\s*(\\\\d+)');
      final match = regex.firstMatch(statsText);
      if (match != null && match.groupCount > 0) {
        return int.tryParse(match.group(1)!);
      }
      return null;
    }

    if (statsText.isNotEmpty) {
      views = _extract('Views:') ?? _extract('Page Visits:') ?? 0;
      submissions = _extract('Submissions:') ?? 0;
      favs = _extract('Favs:') ?? _extract('Favorites:') ?? 0;
      commentsEarned = _extract('Comments Earned:') ?? _extract('Comments Received:') ?? 0;
      commentsMade = _extract('Comments Made:') ?? _extract('Comments Given:') ?? 0;
      journals = _extract('Journals:') ?? 0;
    } else {
      views = 0;
      submissions = 0;
      favs = 0;
      commentsEarned = 0;
      commentsMade = 0;
      journals = 0;
    }

    // Modern / classic flags
    bool isClassicMarkup = document.body != null &&
        document.body!.attributes['data-static-path'] == '/themes/classic';

    // Featured submission
    String? featuredImageUrl;
    String? featuredImageTitle;
    String? featuredPostNumber;
    final featuredSectionHeader = document.querySelector('.userpage-section-left .section-header h2');
    if (featuredSectionHeader != null && featuredSectionHeader.text.trim() == 'Featured Submission') {
      final featuredSection = featuredSectionHeader.parent?.parent;
      if (featuredSection != null) {
        final imageElem = featuredSection.querySelector('.section-body .aligncenter.preview_img a img');
        if (imageElem != null) {
          String? imageSrc = imageElem.attributes['src'];
          if (imageSrc != null) {
            if (imageSrc.startsWith('//')) {
              featuredImageUrl = 'https:$imageSrc';
            } else if (imageSrc.startsWith('http://') || imageSrc.startsWith('https://')) {
              featuredImageUrl = imageSrc;
            } else {
              featuredImageUrl = imageSrc;
            }
          }
        }
        final linkElem = featuredSection.querySelector('.section-body .aligncenter.preview_img a');
        if (linkElem != null) {
          String? href = linkElem.attributes['href'];
          if (href != null) {
            final hrefParts = href.split('/');
            featuredPostNumber = hrefParts.length > 2 ? hrefParts[2] : 'N/A';
          }
        }
        final titleElem = featuredSection.querySelector('.userpage-featured-title h2 a');
        featuredImageTitle = titleElem != null && titleElem.text.trim().isNotEmpty
            ? titleElem.text.trim()
            : null;
      }
    }

    // Contact info
    List<Map<String, String>> contactInformationLinks = [];
    dom.Element? contactInfoSection = document.querySelector('#userpage-contact');
    if (contactInfoSection != null) {
      final contactItems = contactInfoSection.querySelectorAll('.user-contact-item');
      for (var item in contactItems) {
        final labelElement = item.querySelector('.user-contact-user-info .highlight');
        final valueElement = item.querySelector('.user-contact-user-info a');
        String? label = labelElement?.text.trim();
        if (label != null && label.endsWith(':')) {
          label = label.substring(0, label.length - 1);
        }
        String? href = valueElement?.attributes['href'];
        String value = valueElement?.text.trim() ?? 'N/A';
        if (label != null && href != null) {
          if (valueElement!.children.isNotEmpty && valueElement.children.first.localName == 'i') {
            value = valueElement.children.first.text.trim();
          }
          if (value.isNotEmpty && value != 'N/A') {
            contactInformationLinks.add({'label': label, 'value': value, 'href': href});
          }
        }
      }
    }

    // Recent watchers (minimal: counts only; links left as empty)
    List<UserLink> recentWatchers = [];
    int recentWatchersCount = 0;
    dom.Element? recentWatchersSection = document.querySelector('section.userpage-left-column.watched-by-block');
    if (recentWatchersSection != null) {
      final viewListLink = recentWatchersSection.querySelector('.section-header .floatright h3 a');
      if (viewListLink != null) {
        final linkText = viewListLink.text.trim();
        final countMatch = RegExp(r'Watched by (\\d+)').firstMatch(linkText);
        if (countMatch != null && countMatch.groupCount >= 1) {
          recentWatchersCount = int.tryParse(countMatch.group(1)!) ?? 0;
        }
      }
    }

    // Recently watched (minimal: counts only)
    List<UserLink> recentlyWatched = [];
    int recentlyWatchedCount = 0;
    dom.Element? recentlyWatchedSection = document.querySelector('section.userpage-left-column.is-watching-block');
    if (recentlyWatchedSection != null) {
      final viewListLink = recentlyWatchedSection.querySelector('.section-header .floatright h3 a');
      if (viewListLink != null) {
        final linkText = viewListLink.text.trim();
        final countMatch = RegExp(r'Watching (\\d+)').firstMatch(linkText);
        if (countMatch != null && countMatch.groupCount >= 1) {
          recentlyWatchedCount = int.tryParse(countMatch.group(1)!) ?? 0;
        }
      }
    }

    // Shouts (initial page)
    List<Shout> shouts = [];
    String? shoutPaginationKey;
    int currentShoutPage = 1;
    int totalShoutPages = 1;

    dom.Element? shoutsSection = document.querySelector('.userpage-section-right.no-border');
    if (shoutsSection != null) {
      final shoutContainers = shoutsSection.querySelectorAll('div.comment_container');
      for (var container in shoutContainers) {
        final avatarElem = container.querySelector('img.comment_useravatar');
        String avatarUrl = avatarElem != null
            ? (avatarElem.attributes['src']!.startsWith('//')
                ? 'https:${avatarElem.attributes['src']!}'
                : avatarElem.attributes['src']!)
            : 'assets/images/defaultpic.gif';

        final displayNameElem = container.querySelector('a.c-usernameBlock__displayName .js-displayName');
        final userNameElem = container.querySelector('a.c-usernameBlock__userName .js-userName-block span');
        final displayNameShout = displayNameElem?.text.trim() ?? 'Unknown';
        final userNamePartShout = userNameElem?.text.trim() ?? '';

        final symbolElemShout = container.querySelector('a.c-usernameBlock__userName .c-usernameBlock__symbol');
        final symbolShout = symbolElemShout?.text.trim() ?? "~";

        final usernameWithoutSymbol = userNamePartShout.replaceFirst(symbolShout, '').trim();
        String cmtUsername = (usernameWithoutSymbol.isEmpty ||
                displayNameShout.toLowerCase() == usernameWithoutSymbol.toLowerCase())
            ? displayNameShout
            : '$displayNameShout\\n@$usernameWithoutSymbol';

        final usernameLink = container.querySelector('div.avatar a');
        String? profileNickname = usernameLink?.attributes['href'] != null
            ? usernameLink!.attributes['href']!.split('/').where((part) => part.isNotEmpty).last
            : 'Unknown';

        final dateElem = container.querySelector('span.popup_date');
        String relativeDate = dateElem?.text.trim() ?? 'Unknown date';
        String fullDate = dateElem?.attributes['title']?.trim() ?? relativeDate;

        final textElem = container.querySelector('comment-user-text.comment_text');
        String text = textElem?.innerHtml.trim() ?? '';

        String shoutId = '';
        final anchor = container.querySelector('a.comment_anchor[id^=\"shout-\"]');
        if (anchor != null) {
          final idAttr = anchor.attributes['id'] ?? '';
          if (idAttr.startsWith('shout-')) {
            shoutId = idAttr.substring('shout-'.length);
          }
        }

        List<String> shoutIconBeforeUrls = [];
        List<String> shoutIconAfterUrls = [];
        final shoutUsernameContainer = container.querySelector('.c-usernameBlock');
        if (shoutUsernameContainer != null) {
          final beforeIcons = shoutUsernameContainer.querySelectorAll('usericon-block-before img');
          shoutIconBeforeUrls = beforeIcons.map((imgElem) {
            String? src = imgElem.attributes['src'];
            if (src != null) {
              if (src.startsWith('//')) return 'https:$src';
              if (src.startsWith('/')) return 'https://www.furaffinity.net$src';
              return src;
            }
            return '';
          }).where((src) => src.isNotEmpty).toList();

          final afterIcons = shoutUsernameContainer.querySelectorAll('usericon-block-after img');
          shoutIconAfterUrls = afterIcons.map((imgElem) {
            String? src = imgElem.attributes['src'];
            if (src != null) {
              if (src.startsWith('//')) return 'https:$src';
              if (src.startsWith('/')) return 'https://www.furaffinity.net$src';
              return src;
            }
            return '';
          }).where((src) => src.isNotEmpty).toList();
        }

        shouts.add(Shout(
          id: shoutId,
          avatarUrl: avatarUrl,
          username: cmtUsername,
          profileNickname: profileNickname ?? 'Unknown',
          date: relativeDate,
          text: text,
          popupDateFull: fullDate,
          popupDateRelative: relativeDate,
          iconBeforeUrls: shoutIconBeforeUrls,
          iconAfterUrls: shoutIconAfterUrls,
          symbol: symbolShout,
        ));
      }

      dom.Element? shoutPaginationForm = document.querySelector('form.c-shoutPaginationForm');
      if (shoutPaginationForm != null) {
        final keyInput = shoutPaginationForm.querySelector('input[name=\"key\"]');
        shoutPaginationKey = keyInput?.attributes['value'];

        final pageSelect = shoutPaginationForm.querySelector('select[name=\"shout_page\"]');
        if (pageSelect != null) {
          final options = pageSelect.querySelectorAll('option');
          if (options.isNotEmpty) {
            totalShoutPages = options.length;
          }
          final selectedOption = pageSelect.querySelector('option[selected]');
          if (selectedOption != null) {
            currentShoutPage = int.tryParse(selectedOption.attributes['value'] ?? '1') ?? 1;
          }
        }
      }
    }

    // Watch/unwatch/block/unblock links detection
    var watchLinkElement = document.querySelector('a.button.standard.go[href^=\"/watch/\"]')
        ?? document.querySelector('a[href^=\"/watch/\"]');

    var unwatchLinkElement = document.querySelector('a.button.standard.stop[href^=\"/unwatch/\"]')
        ?? document.querySelector('a[href^=\"/unwatch/\"]');

    var blockLinkElement = document.querySelector('a.button.standard.stop[href^=\"/block/\"]')
        ?? document.querySelector('form[action^=\"/block/\"]');
    String? computedBlockLink;
    if (blockLinkElement != null) {
      if (blockLinkElement.localName == 'form') {
        final keyElem = blockLinkElement.querySelector('input[name=\"key\"]')
            ?? blockLinkElement.querySelector('button[name=\"key\"]');
        final keyValue = keyElem?.attributes['value'] ?? '';
        if (keyValue.isNotEmpty) {
          computedBlockLink = 'https://www.furaffinity.net/block/$username/?key=$keyValue';
        }
      } else {
        computedBlockLink = blockLinkElement.attributes['href'];
      }
    }

    var unblockLinkElement = document.querySelector('a.button.standard.stop[href^=\"/unblock/\"]')
        ?? document.querySelector('form[action^=\"/unblock/\"]');
    String? computedUnblockLink;
    if (unblockLinkElement != null) {
      if (unblockLinkElement.localName == 'form') {
        final keyElem = unblockLinkElement.querySelector('input[name=\"key\"]')
            ?? unblockLinkElement.querySelector('button[name=\"key\"]');
        final keyValue = keyElem?.attributes['value'] ?? '';
        if (keyValue.isNotEmpty) {
          computedUnblockLink = 'https://www.furaffinity.net/unblock/$username/?key=$keyValue';
        }
      } else {
        computedUnblockLink = unblockLinkElement.attributes['href'];
      }
    }

    bool isOwnProfile = watchLinkElement == null &&
        unwatchLinkElement == null &&
        blockLinkElement == null &&
        unblockLinkElement == null;

    return UserProfileParsed(
      profileBannerUrl: profileBannerUrl,
      profileImageUrl: profileImageUrl,
      profileDisplayName: displayName,
      profileUserNamePart: nicknameWithoutSymbol,
      symbolUsername: symbolUsername,
      username: username,
      userTitle: userTitle,
      registrationDate: registrationDate,
      userDescription: userDescription,
      hasRealUserProfile: hasRealUserProfile,
      isClassicMarkup: isClassicMarkup,
      acceptingTrades: isClassicMarkup && htmlBody.contains('option-yes') && htmlBody.toLowerCase().contains('trades'),
      acceptingCommissions: isClassicMarkup && htmlBody.contains('option-yes') && htmlBody.toLowerCase().contains('commissions'),
      userIconBeforeUrls: userIconBeforeUrls,
      userIconAfterUrls: userIconAfterUrls,
      views: views,
      submissions: submissions,
      favs: favs,
      commentsEarned: commentsEarned,
      commentsMade: commentsMade,
      journals: journals,
      featuredImageUrl: featuredImageUrl,
      featuredImageTitle: featuredImageTitle,
      featuredPostNumber: featuredPostNumber,
      userProfileImageUrl: userProfileImageUrl,
      userProfilePostNumber: userProfilePostNumber,
      userProfileTexts: null,
      contactInformationLinks: contactInformationLinks,
      recentWatchers: recentWatchers,
      recentWatchersCount: recentWatchersCount,
      recentlyWatched: recentlyWatched,
      recentlyWatchedCount: recentlyWatchedCount,
      shouts: shouts,
      shoutPaginationKey: shoutPaginationKey,
      currentShoutPage: currentShoutPage,
      totalShoutPages: totalShoutPages,
      watchLink: watchLinkElement?.attributes['href'],
      unwatchLink: unwatchLinkElement?.attributes['href'],
      blockLink: computedBlockLink,
      unblockLink: computedUnblockLink,
      isWatching: unwatchLinkElement != null,
      isBlocked: computedUnblockLink != null,
      isOwnProfile: isOwnProfile,
    );
  }
}

