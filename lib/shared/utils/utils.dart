import 'package:flutter/material.dart';

void showAppSnackBar(
  BuildContext context,
  String text, {
  Color? backgroundColor,
  int durationSeconds = 2,
}) {
  final snackBar = SnackBar(
    content: Text(text),
    backgroundColor: backgroundColor,
    duration: Duration(seconds: durationSeconds),
  );
  ScaffoldMessenger.of(context).showSnackBar(snackBar);
}
