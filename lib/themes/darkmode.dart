import 'package:flutter/material.dart';

ThemeData darkMode = ThemeData(
  colorScheme: ColorScheme.dark(
    primary: Colors.grey.shade500,
    secondary: const Color(0xFF1E1E1E),
    tertiary: const Color(0xFF121212),
    inversePrimary: Colors.grey.shade300,
  ),
  scaffoldBackgroundColor: const Color(0xFF121212), // very dark base
  appBarTheme: const AppBarTheme(
    backgroundColor: Color(0xFF121212),
    foregroundColor: Colors.white,
    elevation: 0,
  ),
  bottomNavigationBarTheme: const BottomNavigationBarThemeData(
    backgroundColor: Color(0xFF121212),
    selectedItemColor: Colors.white,
    unselectedItemColor: Colors.grey,
  ),
  cardTheme: const CardThemeData(
    color: Color(0xFF1E1E1E), // slightly lighter than scaffold
    elevation: 0,
    margin: EdgeInsets.symmetric(vertical: 8, horizontal: 0),
  ),
  iconTheme: const IconThemeData(color: Colors.white),
  dividerColor: Colors.grey.shade800,
  textTheme: const TextTheme(
    bodyMedium: TextStyle(color: Colors.white),
    bodySmall: TextStyle(color: Colors.grey),
  ),
);
