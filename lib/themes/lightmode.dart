import 'package:flutter/material.dart';

ThemeData lightMode = ThemeData(
  colorScheme: ColorScheme.light(
    primary: Colors.grey.shade500,
    secondary: Colors.grey.shade200,
    tertiary: Colors.white,
    inversePrimary: Colors.grey.shade900,
  ),
  scaffoldBackgroundColor: Colors.white, // light grey base
  appBarTheme: const AppBarTheme(
    backgroundColor: Colors.white,
    foregroundColor: Colors.black,
    elevation: 0,
  ),
  bottomNavigationBarTheme: const BottomNavigationBarThemeData(
    backgroundColor: Colors.white,
    selectedItemColor: Colors.black,
    unselectedItemColor: Colors.grey,
  ),
  cardTheme: const CardThemeData(
    color: Colors.white, // slightly lighter than scaffold
    elevation: 0,
    margin: EdgeInsets.symmetric(vertical: 8, horizontal: 0),
  ),
  iconTheme: const IconThemeData(color: Colors.black),
  dividerColor: Colors.grey,
  textTheme: const TextTheme(
    bodyMedium: TextStyle(color: Colors.black),
    bodySmall: TextStyle(color: Colors.grey),
  ),
);
