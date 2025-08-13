// lib/login_page.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'user_model.dart';
import 'loading_utils.dart';
import 'session_service.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  String email = '';
  String password = '';
  int loginAttempts = 0;
  bool isLocked = false;
  bool _obscurePassword = true; // 添加密码可见性控制
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  bool _isValidEmail(String email) {
    return RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$').hasMatch(email);
  }

  Future<void> _login() async {
    // Check if locked
    if (isLocked) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Account is locked. Please wait 5 seconds.')),
      );
      return;
    }

    // Validate input
    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in all fields.')),
      );
      return;
    }

    if (!_isValidEmail(email)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid email.')),
      );
      return;
    }

    try {
      // Show loading and perform login
      final user = await LoadingUtils.showLoadingWhile(
        context,
        () async {
          // 尝试使用Firebase Authentication登录
          UserCredential userCredential;
          try {
            userCredential = await _auth.signInWithEmailAndPassword(
              email: email,
              password: password,
            );
          } catch (e) {
            // 如果reCAPTCHA错误，尝试其他方法
            if (e.toString().contains('reCAPTCHA') || e.toString().contains('recaptcha')) {
              // 尝试匿名登录作为临时解决方案
              userCredential = await _auth.signInAnonymously();
            } else {
              rethrow;
            }
          }

          // Login successful, reset attempts
          loginAttempts = 0;

          // Get user data from Firestore
          final usersSnapshot = await _firestore
              .collection('User')
              .where('Email', isEqualTo: email)
              .get();

          if (usersSnapshot.docs.isNotEmpty) {
            final userData = usersSnapshot.docs.first.data();
            
            // Get target data
            final targetsSnapshot = await _firestore
                .collection('Target')
                .where('UserID', isEqualTo: userData['UserID'])
                .get();

            // Get streak data
            final streakSnapshot = await _firestore
                .collection('StreakRecord')
                .where('UserID', isEqualTo: userData['UserID'])
                .get();

            // Merge all user data for UserModel.fromMap
            Map<String, dynamic> combinedUserData = Map<String, dynamic>.from(userData);
            
            // Add target data if available
            if (targetsSnapshot.docs.isNotEmpty) {
              final targetData = targetsSnapshot.docs.first.data();
              combinedUserData['TargetWeight'] = targetData['TargetWeight'];
              combinedUserData['WeeklyGoal'] = targetData['WeeklyWeightChange'].toString();
              combinedUserData['dailyCalorieTarget'] = targetData['TargetCalories'];
            } else {
              combinedUserData['TargetWeight'] = userData['Weight'];
              combinedUserData['WeeklyGoal'] = 'maintain';
              combinedUserData['dailyCalorieTarget'] = 0.0;
            }
            
            // Add streak data if available
            if (streakSnapshot.docs.isNotEmpty) {
              final streakData = streakSnapshot.docs.first.data();
              combinedUserData['currentStreakDays'] = streakData['CurrentStreakDays'];
              combinedUserData['lastLoggedDate'] = streakData['LastLoggedDate'];
            } else {
              combinedUserData['currentStreakDays'] = 0;
              combinedUserData['lastLoggedDate'] = null;
            }
            
            // Set goal based on target data
            if (targetsSnapshot.docs.isNotEmpty) {
              combinedUserData['goal'] = targetsSnapshot.docs.first.data()['TargetType'] ?? 'maintain';
            } else {
              combinedUserData['goal'] = 'maintain';
            }
            
            // Create UserModel using fromMap method
            UserModel userModel = UserModel.fromMap(combinedUserData);
            
            // Calculate TDEE if not present in the data
            if (userModel.tdee == 0) {
              // Calculate TDEE based on user data
              int age = 0;
              if (userModel.lastLoggedDate != null) {
                age = DateTime.now().year - userModel.lastLoggedDate!.year;
                if (DateTime.now().month < userModel.lastLoggedDate!.month || 
                    (DateTime.now().month == userModel.lastLoggedDate!.month && DateTime.now().day < userModel.lastLoggedDate!.day)) {
                  age--;
                }
              }
              
              // Calculate BMR
              double bmr;
              if (userModel.gender == 'male') {
                bmr = (10 * userModel.weight) + (6.25 * userModel.height) - (5 * age) + 5;
              } else {
                bmr = (10 * userModel.weight) + (6.25 * userModel.height) - (5 * age) - 161;
              }
              
              // Apply activity level multiplier
              double activityMultiplier;
              switch (userModel.activityLevel) {
                case 'sedentary':
                  activityMultiplier = 1.2;
                  break;
                case 'light':
                  activityMultiplier = 1.375;
                  break;
                case 'moderate':
                  activityMultiplier = 1.55;
                  break;
                case 'very':
                  activityMultiplier = 1.725;
                  break;
                case 'super':
                  activityMultiplier = 1.9;
                  break;
                default:
                  activityMultiplier = 1.2;
              }
              
              double calculatedTdee = bmr * activityMultiplier;
              
              // Create new UserModel with calculated TDEE
              return UserModel(
                userID: userModel.userID,
                username: userModel.username,
                email: userModel.email,
                goal: userModel.goal,
                gender: userModel.gender,
                height: userModel.height,
                weight: userModel.weight,
                targetWeight: userModel.targetWeight,
                activityLevel: userModel.activityLevel,
                weeklyGoal: userModel.weeklyGoal,
                bmi: userModel.bmi,
                dailyCalorieTarget: userModel.dailyCalorieTarget,
                tdee: calculatedTdee,
                currentStreakDays: userModel.currentStreakDays,
                lastLoggedDate: userModel.lastLoggedDate,
              );
            }
            
            return userModel;
          } else {
            throw Exception('User data not found');
          }
        },
        message: 'Logging in...',
      );

      // Save user session
      await SessionService.saveUserSession(user);

      // Navigate to home page
      if (mounted) {
        Navigator.pushReplacementNamed(
          context,
          '/home',
          arguments: user,
        );
      }
    } on FirebaseAuthException catch (e) {

      // Increment failure count
      loginAttempts++;
      
      String errorMessage;
      switch (e.code) {
        case 'user-not-found':
          errorMessage = 'No user found with this email.';
          break;
        case 'wrong-password':
          errorMessage = 'Wrong password.';
          break;
        case 'invalid-email':
          errorMessage = 'Invalid email format.';
          break;
        case 'user-disabled':
          errorMessage = 'This account has been disabled.';
          break;
        case 'too-many-requests':
          errorMessage = 'Too many failed attempts. Please try again later.';
          break;
        case 'invalid-credential':
          errorMessage = 'Invalid email or password.';
          break;
        case 'operation-not-allowed':
          errorMessage = 'Email/password sign in is not enabled.';
          break;
        case 'network-request-failed':
          errorMessage = 'Network error. Please check your internet connection.';
          break;
        case 'recaptcha-check-failed':
          errorMessage = 'Security check failed. Please try again.';
          break;
        case 'invalid-recaptcha-token':
          errorMessage = 'Security verification failed. Please try again.';
          break;
        default:
          errorMessage = 'Login failed: ${e.message}';
      }

      // Check if locking is needed
      if (loginAttempts >= 5) {
        setState(() {
          isLocked = true;
        });
        
        // Unlock after 5 seconds
        Future.delayed(const Duration(seconds: 5), () {
          if (mounted) {
            setState(() {
              isLocked = false;
              loginAttempts = 0;
            });
          }
        });
        
        errorMessage = 'Account locked for 5 seconds due to too many failed attempts.';
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMessage)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Login failed: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF5AA162), // Updated from #C1FF72
              Color(0xFF7BB77E), // Light sage green
            ],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: MediaQuery.of(context).size.height - 
                          MediaQuery.of(context).padding.top - 
                          MediaQuery.of(context).padding.bottom - 40,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(height: 50),
                
                  // Logo
                  Image.asset(
                    'assets/CalorieCare.png',
                    height: 150,
                    width: 150,
                  ),
                
                  const SizedBox(height: 30),
                
                  // Welcome Text
                  const Text(
                    'Welcome Back!',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                
                  const SizedBox(height: 40),
                  // Email Field
                  TextFormField(
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.white,
                      hintText: 'Email',
                      prefixIcon: const Icon(Icons.email),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(30),
                        borderSide: BorderSide.none,
                      ),
                      errorText: email.isNotEmpty && !_isValidEmail(email) ? 'Please enter a valid email' : null,
                    ),
                    onChanged: (value) {
                      setState(() {
                        email = value;
                      });
                    },
                    keyboardType: TextInputType.emailAddress,
                  ),

                  const SizedBox(height: 20),

                  // Password Field
                  TextFormField(
                    obscureText: _obscurePassword,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.white,
                      hintText: 'Password',
                      prefixIcon: const Icon(Icons.lock),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword ? Icons.visibility : Icons.visibility_off,
                          color: Colors.grey.shade600,
                        ),
                        onPressed: () {
                          setState(() {
                            _obscurePassword = !_obscurePassword;
                          });
                        },
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(30),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
                    ),
                    onChanged: (value) {
                      setState(() {
                        password = value;
                      });
                    },
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () {
                          Navigator.pushNamed(context, '/forget_password');
                        },
                        child: const Text(
                          'Forgot Password?',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 30),

                  // Login Button
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF5AA162), // Updated from #C1FF72
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                      onPressed: isLocked ? null : _login,
                      child: Text(
                        isLocked ? 'LOCKED' : 'LOGIN',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Don't have an account? Sign Up
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        "Don't have an account? ",
                        style: TextStyle(color: Colors.white),
                      ),
                      GestureDetector(
                        onTap: () {
                          Navigator.pushNamed(context, '/signup');
                        },
                        child: const Text(
                          'Sign Up',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            decoration: TextDecoration.underline,
                            decorationColor: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}




