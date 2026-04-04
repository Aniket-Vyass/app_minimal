import 'package:app_minimal/wrapper.dart';
import 'package:app_minimal/themes/darkmode.dart';
import 'package:app_minimal/themes/lightmode.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

//App name suggestion: the positive scroll

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      debugShowCheckedModeBanner: false,
      theme: lightMode, // ← your light theme
      darkTheme: darkMode, // ← your dark theme
      themeMode: ThemeMode.system, // follows device setting
      home: const Wrapper(),
    );
  }
}
