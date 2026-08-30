import 'package:dio/dio.dart';

Map<String, dynamic> buildSelectedNotificationRemovalFields(
  String title,
  Iterable<String> ids,
) {
  final titleLower = title.toLowerCase();
  final itemIds = ids.toList();
  if (titleLower.contains('shouts')) {
    return {
      'remove-shouts': 'Remove Selected Shouts',
      'shouts': itemIds,
    };
  }
  if (titleLower.contains('watches')) {
    return {
      'remove-watches': 'Remove Selected Watches',
      'watches': itemIds,
    };
  }
  if (titleLower.contains('submission comments')) {
    return {
      'remove-submission-comments': 'Remove Selected Comments',
      'comments-submissions': itemIds,
    };
  }
  if (titleLower.contains('journal comments')) {
    return {
      'remove-journal-comments': 'Remove Selected Comments',
      'comments-journals': itemIds,
    };
  }
  if (titleLower.contains('favorites')) {
    return {
      'remove-favorites': 'Remove Selected Favorites',
      'favorites': itemIds,
    };
  }
  if (titleLower.contains('journals')) {
    return {
      'remove-journals': 'Remove Selected Journals',
      'journals': itemIds,
    };
  }
  return {};
}

Map<String, dynamic> buildNotificationNukeFields(String title) {
  final titleLower = title.toLowerCase();
  if (titleLower.contains('watches')) {
    return {'nuke-watches': 'Nuke Watches'};
  }
  if (titleLower.contains('submission comments')) {
    return {'nuke-submission-comments': 'Nuke Submission Comments'};
  }
  if (titleLower.contains('journal comments')) {
    return {'nuke-journal-comments': 'Nuke Journal Comments'};
  }
  if (titleLower.contains('shouts')) {
    return {'nuke-shouts': 'Nuke Shouts'};
  }
  if (titleLower.contains('favorites')) {
    return {'nuke-favorites': 'Nuke Favorites'};
  }
  if (titleLower.contains('journals')) {
    return {'nuke-journals': 'Nuke Journals'};
  }
  return {};
}

FormData buildNotificationFormData(Map<String, dynamic> fields) {
  final formData = FormData();
  fields.forEach((key, value) {
    if (value is List) {
      for (final item in value) {
        formData.fields.add(MapEntry('$key[]', item));
      }
    } else {
      formData.fields.add(MapEntry(key, value));
    }
  });
  return formData;
}

String buildNotificationUrlEncodedBody(Map<String, dynamic> fields) {
  final queryParameters = <String, dynamic>{};
  fields.forEach((key, value) {
    if (value is List) {
      queryParameters['$key[]'] =
          value.map((item) => item.toString()).toList();
    } else {
      queryParameters[key] = value.toString();
    }
  });
  return Uri(queryParameters: queryParameters).query;
}
