import 'package:flutter/material.dart';
import 'password_reset_service.dart';
import 'oob_code_verification_page.dart';

class ForgetPasswordPage extends StatefulWidget {
  const ForgetPasswordPage({super.key});

  @override
  State<ForgetPasswordPage> createState() => _ForgetPasswordPageState();
}

class _ForgetPasswordPageState extends State<ForgetPasswordPage> {
  String email = '';
  bool _isLoading = false;
  String _errorMessage = '';
  final PasswordResetService _passwordResetService = PasswordResetService();

  bool _isValidEmail(String email) {
    return RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$').hasMatch(email);
  }

  Future<void> _sendResetCode() async {
    if (email.isEmpty || !_isValidEmail(email)) {
      setState(() {
        _errorMessage = 'Please enter a valid email address';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      // 使用安全的Firebase OOB Code方案
      final result = await _passwordResetService.sendFirebaseResetCodeSafe(email);
      
      if (result['success']) {
        if (mounted) {
          // 显示成功消息
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.white),
                  SizedBox(width: 8),
                  Expanded(child: Text('Verification code sent to $email')),
                ],
              ),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 4),
            ),
          );
          
          // 等待一下让用户看到成功消息
          await Future.delayed(Duration(milliseconds: 500));
          
          // 跳转到OOB Code验证页面
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => OobCodeVerificationPage(email: email),
            ),
          );
        }
      } else {
        setState(() {
          _errorMessage = result['error'] ?? 'Failed to send verification code';
        });
      }
    } catch (e) {
      print('Error in _sendResetCode: $e');
      setState(() {
        _errorMessage = 'An unexpected error occurred. Please check your connection and try again.';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF5AA162), // Updated from #C1FF72
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Reset Password',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF5AA162), // Updated primary
              Color(0xFF7BB77E), // Light sage green
            ],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView( // 添加滚动容器
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: MediaQuery.of(context).size.height - 
                          MediaQuery.of(context).padding.top - 
                          MediaQuery.of(context).padding.bottom - 40,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 40),
                  
                  // Icon
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.lock_reset,
                        size: 60,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 30),
                  
                  // Title
                  const Center(
                    child: Text(
                      'Forgot Password?',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 10),
                  
                  // Subtitle
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 20),
                      child: Text(
                        'Enter your email address and we\'ll send you a verification code to reset your password.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 40),
                  
                  // Email input field
                  TextFormField(
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.white,
                      hintText: 'Enter your email',
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
                        _errorMessage = '';
                      });
                    },
                    keyboardType: TextInputType.emailAddress,
                  ),
                  
                  if (_errorMessage.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      _errorMessage,
                      style: const TextStyle(
                        color: Colors.red,
                        fontSize: 14,
                      ),
                    ),
                  ],
                  
                  const SizedBox(height: 30),
                  
                  // Send Code Button
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF5AA162), // Updated
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                      onPressed: _isLoading ? null : _sendResetCode,
                      child: _isLoading
                          ? const CircularProgressIndicator(
                              color: Color(0xFF5AA162), // Updated
                            )
                          : const Text(
                              'SEND VERIFICATION CODE',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),
                  
                  const SizedBox(height: 20), // 底部留白
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
} 






