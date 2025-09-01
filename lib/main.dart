import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:caloriecare/login.dart';
import 'package:caloriecare/steppersignup.dart';
import 'package:caloriecare/homepage.dart';
import 'package:caloriecare/homepage_enhanced.dart';
import 'package:caloriecare/user_model.dart';
import 'package:caloriecare/forget_password.dart';
import 'package:caloriecare/notification_service.dart';
import 'package:caloriecare/fcm_service.dart';
import 'package:caloriecare/global_notification_manager.dart';
import 'package:caloriecare/session_service.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_fonts/google_fonts.dart';

// 背景消息处理器必须是顶级函数
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  print('=== Background Message Handler ===');
  print('Title: ${message.notification?.title}');
  print('Body: ${message.notification?.body}');
  print('Data: ${message.data}');
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  try {
    // 初始化timezone数据库
    tz.initializeTimeZones();
    
    await Firebase.initializeApp();
    
    // 注册背景消息处理器
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    
    await dotenv.load(fileName: ".env");
    
    // 初始化全局通知管理器（替代原有的通知服务）
    final globalNotificationManager = GlobalNotificationManager();
    await globalNotificationManager.initialize();
    
    print('App initialization completed successfully');
  } catch (e) {
    print('Initialization error: $e');
  }
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CalorieCare',
      theme: ThemeData(
        primaryColor: const Color(0xFF5AA162), // Updated from #C1FF72
        colorScheme: ColorScheme.light(
          primary: const Color(0xFF5AA162), // Updated from #C1FF72
          secondary: const Color(0xFF7BB77E), // Updated secondary
        ),
      ),
      home: const SessionCheckPage(),
      routes: {
        '/login': (context) => const LoginPage(),
        '/signup': (context) => const StepperSignUpPage(),
        '/forget_password': (context) => const ForgetPasswordPage(),
        '/home': (context) => const HomePage(),
        '/enhanced_home': (context) => const EnhancedHomePage(),
      },
      onGenerateRoute: (settings) {
        if (settings.name == '/home') {
          final user = settings.arguments;
          if (user is UserModel) {
            return MaterialPageRoute(
              builder: (context) => HomePage(user: user as UserModel?),
            );
          }
        }
        if (settings.name == '/enhanced_home') {
          final user = settings.arguments;
          if (user is UserModel) {
            return MaterialPageRoute(
              builder: (context) => EnhancedHomePage(user: user as UserModel?),
            );
          }
        }
        return null;
      },
    );
  }
}

class SessionCheckPage extends StatefulWidget {
  const SessionCheckPage({super.key});

  @override
  State<SessionCheckPage> createState() => _SessionCheckPageState();
}

class _SessionCheckPageState extends State<SessionCheckPage> {
  @override
  void initState() {
    super.initState();
    _checkSession();
  }

  Future<void> _checkSession() async {
    final isLoggedIn = await SessionService.isLoggedIn();
    
    if (isLoggedIn) {
      UserModel? sessionUser = await SessionService.getUserSession();
      
      if (sessionUser != null && mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => EnhancedHomePage(user: sessionUser),
          ),
        );
        return;
      }
    }
    
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => const WelcomePage(),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF5AA162), // Updated from #C1FF72
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              'assets/CalorieCare.png',
              height: 200,
              width: 200,
            ),
            const SizedBox(height: 40),
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
            const SizedBox(height: 20),
            const Text(
              'Loading...',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF5AA162), // Updated from #C1FF72
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Logo
            Image.asset(
              'assets/CalorieCare.png',
              height: 200,
              width: 200,
            ),
            const SizedBox(height: 80),

            // Login Button
            CustomButton(
              text: 'Already Have Account',
              icon: Icons.login,
              backgroundColor: Colors.white,
              textColor: const Color(0xFF5AA162), // Updated from #C1FF72
              onPressed: () {
                Navigator.pushNamed(context, '/login');
              },
            ),
            const SizedBox(height: 20),

            // Sign Up Button
            CustomButton(
              text: 'First Use',
              icon: Icons.person_add,
              backgroundColor: const Color(0xFF5AA162).withOpacity(0.3), // Updated
              textColor: Colors.white,
              borderColor: Colors.white,
              onPressed: () {
                Navigator.pushNamed(context, '/signup');
              },
            ),
          ],
        ),
      ),
    );
  }
}

class CustomButton extends StatelessWidget {
  final String text;
  final IconData icon;
  final Color backgroundColor;
  final Color textColor;
  final Color? borderColor;
  final VoidCallback onPressed;

  const CustomButton({
    super.key,
    required this.text,
    required this.icon,
    required this.backgroundColor,
    required this.textColor,
    this.borderColor,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 280,
      height: 50,
      margin: const EdgeInsets.symmetric(horizontal: 20),
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, color: textColor),
        label: Text(
          text,
          style: TextStyle(
            color: textColor,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: backgroundColor,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(25),
            side: borderColor != null 
                ? BorderSide(color: borderColor!, width: 2)
                : BorderSide.none,
          ),
        ),
      ),
    );
  }
}



