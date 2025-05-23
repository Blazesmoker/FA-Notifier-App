import 'package:flutter/material.dart';

class AppTheme {
  AppTheme._();

  // Dark mode color palette
  static const Color background = Colors.black;
  static const Color cardBackground = Color(0xFF1E1E1E);
  static const Color darkGrey = Color(0xFF2C2C2C);
  static const Color nearlyBlack = Color(0xFF101010);
  static const Color white = Color(0xFFFFFFFF);
  static const Color lightGrey = Color(0xFF8D8D8D);
  static const Color grey = Color(0xFF3A3A3A);
  static const Color darkText = Color(0xFFF0F0F0);
  static const Color darkerText = Color(0xFFE0E0E0);
  static const Color dismissibleBackground = Color(0xFF2A2A2A);
  static const Color chipBackground = Color(0xFF3A3A3A);
  static const Color spacer = Color(0xFF242424);
  static const String fontName = 'WorkSans';

  static const TextTheme textTheme = TextTheme(
    headlineLarge: display1,
    headlineMedium: headline,
    headlineSmall: title,
    titleSmall: subtitle,
    bodyMedium: body2,
    bodyLarge: body1,
    bodySmall: caption,
  );

  static const TextStyle display1 = TextStyle(
    fontFamily: fontName,
    fontWeight: FontWeight.bold,
    fontSize: 36,
    letterSpacing: 0.4,
    height: 0.9,
    color: white,
  );

  static const TextStyle headline = TextStyle(
    fontFamily: fontName,
    fontWeight: FontWeight.bold,
    fontSize: 24,
    letterSpacing: 0.27,
    color: white,
  );

  static const TextStyle title = TextStyle(
    fontFamily: fontName,
    fontWeight: FontWeight.bold,
    fontSize: 16,
    letterSpacing: 0.18,
    color: white,
  );

  static const TextStyle subtitle = TextStyle(
    fontFamily: fontName,
    fontWeight: FontWeight.w400,
    fontSize: 14,
    letterSpacing: -0.04,
    color: lightGrey,
  );

  static const TextStyle body2 = TextStyle( ///comments text
    fontFamily: fontName,
    fontWeight: FontWeight.w400,
    fontSize: 14,
    letterSpacing: 0.2,
    color: white,
  );

  static const TextStyle body1 = TextStyle(
    fontFamily: fontName,
    fontWeight: FontWeight.w400,
    fontSize: 16,
    letterSpacing: -0.05,
    color: lightGrey,
  );

  static const TextStyle caption = TextStyle(
    fontFamily: fontName,
    fontWeight: FontWeight.w400,
    fontSize: 12,
    letterSpacing: 0.2,
    color: lightGrey,
  );

  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      primaryColor: darkText,
      cardColor: cardBackground,
      textTheme: textTheme,
      iconTheme: IconThemeData(color: white),
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: white,
        elevation: 0,
      ),
      textSelectionTheme: TextSelectionThemeData(

        selectionHandleColor: Color(0xFFE09321),

          selectionColor: Color(0xFFE09321)
      ),

      colorScheme: ColorScheme.dark(
        primary: darkText,
        onPrimary: white,
        surface: cardBackground,
        background: background,
        onBackground: white,
      ),
    );
  }
}
