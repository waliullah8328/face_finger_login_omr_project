import 'package:flutter/material.dart';

import 'auth/screens/welcome_screen.dart';
import 'auth/user_store.dart';
import 'screens/home_screen.dart';
import 'theme.dart';

void main() {
  runApp(const OmrApp());
}

class OmrApp extends StatelessWidget {
  const OmrApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'বিদ্যাবাড়ি OMR রিডার',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: const AuthGate(),
    );
  }
}

/// Home when someone is logged in on this phone, the welcome (login) screen
/// otherwise.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<UserStore>(
      future: UserStore.instance(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
              body: Center(
                  child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text('${snapshot.error}'))));
        }
        final store = snapshot.data;
        if (store == null) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }
        return store.currentUser != null
            ? const HomeScreen()
            : const WelcomeScreen();
      },
    );
  }
}
