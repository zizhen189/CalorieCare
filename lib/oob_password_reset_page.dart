import 'package:flutter/material.dart';
import 'password_reset_service.dart';
import 'login.dart';

class OobPasswordResetPage extends StatefulWidget {
  final String oobCode;
  final String email;

  const OobPasswordResetPage({
    super.key,
    required this.oobCode,
    required this.email,
  });

  @override
  State<OobPasswordResetPage> createState() => _OobPasswordResetPageState();
}

class _OobPasswordResetPageState extends State<OobPasswordResetPage> {
  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();
  final PasswordResetService _passwordResetService = PasswordResetService();
  bool _isLoading = false;
  String _errorMessage = '';
  bool _obscureNewPassword = true;
  bool _obscureConfirmPassword = true;

  // 添加密码强度检查方法（与注册页面相同）
  String _checkPasswordStrength(String password) {
    if (password.isEmpty) return 'empty';
    
    bool hasUppercase = password.contains(RegExp(r'[A-Z]'));
    bool hasLowercase = password.contains(RegExp(r'[a-z]'));
    bool hasNumber = password.contains(RegExp(r'[0-9]'));
    bool hasMinLength = password.length >= 8;

    if (!hasMinLength) return 'too_short';
    if (!hasUppercase) return 'no_uppercase';
    if (!hasLowercase) return 'no_lowercase';
    if (!hasNumber) return 'no_number';
    
    return 'strong';
  }

  // 获取密码强度提示信息
  String _getPasswordStrengthMessage(String strength) {
    switch (strength) {
      case 'empty':
        return 'Please enter a password';
      case 'too_short':
        return 'Password must be at least 8 characters';
      case 'no_uppercase':
        return 'Password must contain at least one uppercase letter';
      case 'no_lowercase':
        return 'Password must contain at least one lowercase letter';
      case 'no_number':
        return 'Password must contain at least one number';
      case 'strong':
        return 'Password is strong';
      default:
        return 'Please enter a valid password';
    }
  }

  Future<void> _resetPassword() async {
    if (_newPasswordController.text != _confirmPasswordController.text) {
      setState(() {
        _errorMessage = 'Passwords do not match';
      });
      return;
    }

    // 使用新的密码强度验证
    final passwordStrength = _checkPasswordStrength(_newPasswordController.text);
    if (passwordStrength != 'strong') {
      setState(() {
        _errorMessage = _getPasswordStrengthMessage(passwordStrength);
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final result = await _passwordResetService.resetPasswordWithOobCode(
        widget.oobCode,
        _newPasswordController.text,
      );

      if (result['success']) {
        if (mounted) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (BuildContext context) {
              return AlertDialog(
                title: Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.green),
                    SizedBox(width: 8),
                    Text('Success!'),
                  ],
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Your password has been reset successfully!'),
                    SizedBox(height: 16),
                    Text('You can now log in with your new password.'),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      Navigator.pushAndRemoveUntil(
                        context,
                        MaterialPageRoute(builder: (context) => LoginPage()),
                        (route) => false,
                      );
                    },
                    child: Text('Go to Login'),
                  ),
                ],
              );
            },
          );
        }
      } else {
        setState(() {
          _errorMessage = result['error'] ?? 'Failed to reset password';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'An error occurred. Please try again.';
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
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: MediaQuery.of(context).size.height - 
                          MediaQuery.of(context).padding.top - 
                          MediaQuery.of(context).padding.bottom - 40,
              ),
              child: Column(
                children: [
                  const SizedBox(height: 20), // 减少顶部间距
                  
                  // Success Icon
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check_circle_outline,
                      size: 60,
                      color: Colors.white,
                    ),
                  ),
                  
                  const SizedBox(height: 20), // 减少间距
                  
                  // Title
                  const Text(
                    'Create New Password',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  
                  const SizedBox(height: 10),
                  
                  // Subtitle
                  const Text(
                    'Your verification code is valid. Please enter your new password.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                    ),
                  ),
                  
                  const SizedBox(height: 30), // 减少间距
                  
                  // New Password Field
                  TextField(
                    controller: _newPasswordController,
                    obscureText: _obscureNewPassword,
                    decoration: InputDecoration(
                      labelText: 'New Password',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      filled: true,
                      fillColor: Colors.white,
                      suffixIcon: IconButton(
                        icon: Icon(_obscureNewPassword ? Icons.visibility : Icons.visibility_off),
                        onPressed: () {
                          setState(() {
                            _obscureNewPassword = !_obscureNewPassword;
                          });
                        },
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 15), // 减少间距
                  
                  TextField(
                    controller: _confirmPasswordController,
                    obscureText: _obscureConfirmPassword,
                    decoration: InputDecoration(
                      labelText: 'Confirm New Password',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      filled: true,
                      fillColor: Colors.white,
                      suffixIcon: IconButton(
                        icon: Icon(_obscureConfirmPassword ? Icons.visibility : Icons.visibility_off),
                        onPressed: () {
                          setState(() {
                            _obscureConfirmPassword = !_obscureConfirmPassword;
                          });
                        },
                      ),
                    ),
                  ),
                  
                  if (_errorMessage.isNotEmpty) ...[
                    const SizedBox(height: 15),
                    Text(
                      _errorMessage,
                      style: const TextStyle(
                        color: Colors.red,
                        fontSize: 14,
                      ),
                    ),
                  ],
                  
                  const SizedBox(height: 30),
                  
                  // Reset Password Button
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF5AA162),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                      onPressed: _isLoading ? null : _resetPassword,
                      child: _isLoading
                          ? const CircularProgressIndicator(
                              color: Color(0xFF5AA162),
                            )
                          : const Text(
                              'RESET PASSWORD',
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


