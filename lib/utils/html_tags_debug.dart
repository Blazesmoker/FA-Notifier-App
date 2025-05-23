import 'package:flutter/cupertino.dart';
import 'package:html/dom.dart' as dom;

dom.Element? logQuery(dom.Document document, String selector) {
  final element = document.querySelector(selector);
  if (element == null) {
    debugPrint("DEBUG: Selector '$selector' not found.");
  } else {
    debugPrint("DEBUG: Selector '$selector' found: ${element.outerHtml}");
  }
  return element;
}

List<dom.Element> logQueryAll(dom.Document document, String selector) {
  final elements = document.querySelectorAll(selector);
  if (elements.isEmpty) {
    debugPrint("DEBUG: No elements found for selector '$selector'.");
  } else {
    debugPrint("DEBUG: Found ${elements.length} elements for selector '$selector'.");
    for (var el in elements) {
      debugPrint("Element: ${el.outerHtml}");
    }
  }
  return elements;
}
