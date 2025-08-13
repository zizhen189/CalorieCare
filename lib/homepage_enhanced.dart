import 'package:flutter/material.dart';
import 'package:caloriecare/user_model.dart';
import 'package:caloriecare/homepage.dart';

class EnhancedHomePage extends StatelessWidget {
  final UserModel? user;

  const EnhancedHomePage({super.key, this.user});

  @override
  Widget build(BuildContext context) {
    // For now, just redirect to the regular HomePage
    // You can enhance this later with additional features
    return HomePage(user: user);
  }
}
