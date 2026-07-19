import 'package:html/parser.dart' as html_parser;

import 'package:FANotifier/features/notes/domain/note_message_models.dart';
import 'package:FANotifier/shared/fa/user_submitted_html_linkifier.dart';

NoteMessageDetails parseNoteMessageDetails(String decodedBody, String messageLink) {
  final document = html_parser.parse(decodedBody);

  final isClassic = document.querySelector(
        'body[data-static-path="/themes/classic"][id="pageid-messagecenter-pms-view"]',
      ) !=
      null;

  late final String messageId;
  late final int pageNumber;
  if (isClassic) {
    final match = RegExp(r'/viewmessage/(\d+)/').firstMatch(messageLink);
    if (match != null) {
      messageId = match.group(1)!;
      pageNumber = 1;
    } else {
      throw Exception("Message ID could not be extracted from classic URL.");
    }
  } else {
    final match = RegExp(r'/msg/pms/(\d+)/(\d+)/').firstMatch(messageLink);
    if (match != null) {
      pageNumber = int.parse(match.group(1)!);
      messageId = match.group(2)!;
    } else {
      throw Exception("Message ID could not be extracted from modern URL.");
    }
  }

  if (messageId.isEmpty) {
    throw Exception("Message ID could not be extracted.");
  }

  document
      .querySelectorAll('.noteWarningMessage.noteWarningMessage--scam')
      .forEach((e) => e.remove());

  String? tempSenderLink = document
          .querySelector('.message-center-note-information .addresses a')
          ?.attributes['href'] ??
      document
          .querySelector('div.message-center-note-information.addresses a')
          ?.attributes['href'];
  tempSenderLink ??= document
      .querySelector(
        'td.noteContent.alt1 span[style*="color: #999999"] '
        '.c-usernameBlock a[href^="/user/"]',
      )
      ?.attributes['href'];

  String? tempRecipientLink;
  final addressBlocks = document.querySelectorAll(
    '.message-center-note-information .addresses .c-usernameBlock',
  );
  if (addressBlocks.length > 1) {
    tempRecipientLink =
        addressBlocks[1].querySelector('a[href^="/user/"]')?.attributes['href'];
  }
  if (tempRecipientLink == null || tempRecipientLink.isEmpty) {
    final classicRecipientBlocks = document.querySelectorAll(
      'span[style*="color: #999999"] .c-usernameBlock',
    );
    if (classicRecipientBlocks.length > 1) {
      tempRecipientLink = classicRecipientBlocks[1]
          .querySelector('a[href^="/user/"]')
          ?.attributes['href'];
    }
  }

  final subject = document.querySelector('#message h2')?.text.trim() ??
      document.querySelector('td.cat font b')?.text.trim() ??
      'No subject';

  final sender = document
          .querySelector('.message-center-note-information .addresses a')
          ?.text
          .trim() ??
      document
          .querySelector(
            'a.c-usernameBlock__displayName.js-displayName-block span.js-displayName',
          )
          ?.text
          .trim() ??
      'Unknown sender';

  late final String recipient;
  if (isClassic) {
    final classicRecipientBlocks = document.querySelectorAll(
      'span[style*="color: #999999"] .c-usernameBlock',
    );
    if (classicRecipientBlocks.length > 1) {
      recipient = classicRecipientBlocks[1]
              .querySelector('span.js-displayName')
              ?.text
              .trim() ??
          'Unknown recipient';
    } else {
      recipient = 'Unknown recipient';
    }
  } else {
    final addresses = document.querySelectorAll(
      '.message-center-note-information .addresses .c-usernameBlock',
    );
    if (addresses.length > 1) {
      recipient = addresses[1]
              .querySelector('.c-usernameBlock__displayName')
              ?.text
              .trim() ??
          'Unknown recipient';
    } else {
      recipient = 'Unknown recipient';
    }
  }

  final sentDate =
      document.querySelector('.popup_date')?.attributes['title'] ?? 'Unknown date';

  final avatarUrl = document
          .querySelector('.message-center-note-information.avatar img')
          ?.attributes['src'] ??
      '';

  late final String senderLink;
  late final String senderUsername;
  if (tempSenderLink != null && tempSenderLink.isNotEmpty) {
    senderLink = tempSenderLink;
    senderUsername = Uri.parse(tempSenderLink).pathSegments.length >= 2
        ? Uri.parse(tempSenderLink).pathSegments[1]
        : 'Unknown';
  } else {
    senderLink = '';
    senderUsername = 'Unknown';
  }

  late final String recipientLink;
  late final String recipientUsername;
  if (tempRecipientLink != null && tempRecipientLink.isNotEmpty) {
    recipientLink = tempRecipientLink;
    recipientUsername = Uri.parse(tempRecipientLink).pathSegments.length >= 2
        ? Uri.parse(tempRecipientLink).pathSegments[1]
        : '';
  } else {
    recipientLink = '';
    recipientUsername = '';
  }

  final modernElem = document.querySelector('.section-body .user-submitted-links');
  final classicElem = document.querySelector('td.noteContent.alt1');

  String? modernHtml;
  String? classicHtml;
  if (modernElem != null) {
    modernHtml = modernElem.innerHtml;
  }
  if (classicElem != null) {
    classicElem.querySelector('span[style*="color: #999999"]')?.remove();
    classicHtml = classicElem.innerHtml;
  }

  final rawHtml = modernHtml ?? classicHtml;
  String messageContent;
  String messageContentHtml;
  if (rawHtml == null || rawHtml.isEmpty) {
    messageContent = 'No content';
    messageContentHtml = '';
  } else {
    final innerDoc = html_parser.parse(rawHtml);
    innerDoc.querySelectorAll('a.auto_link_shortened').forEach((anchor) {
      final fullLink = anchor.attributes['title'] ?? anchor.attributes['href'];
      if (fullLink != null) {
        anchor.innerHtml = fullLink;
      }
    });
    final updatedText = innerDoc.body?.text.trim() ?? '';
    messageContent = updatedText.isNotEmpty ? updatedText : 'No content';
    var fixedHtml = innerDoc.body?.innerHtml ?? rawHtml;
    fixedHtml = fixedHtml.replaceAllMapped(
      RegExp(r'src="(//[^"]+)"|href="(//[^"]+)"'),
      (m) {
        final url = m.group(1) ?? m.group(2);
        return url != null ? m[0]!.replaceFirst('//', 'https://') : m[0]!;
      },
    );
    fixedHtml = linkifyBareWebUrlsInHtml(fixedHtml);
    messageContentHtml = fixedHtml;
  }

  return NoteMessageDetails(
    isClassic: isClassic,
    messageId: messageId,
    pageNumber: pageNumber,
    subject: subject,
    sender: sender,
    recipient: recipient,
    sentDate: sentDate,
    avatarUrl: avatarUrl,
    messageContent: messageContent,
    messageContentHtml: messageContentHtml,
    senderLink: senderLink,
    senderUsername: senderUsername,
    recipientLink: recipientLink,
    recipientUsername: recipientUsername,
  );
}
