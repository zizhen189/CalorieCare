import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'password_reset_service.dart';
import 'password_reset_page.dart';

class TokenVerificationPage extends StatefulWidget {
  final String email;

  const TokenVerificationPage({super.key, required this.email});

  @override
  State<TokenVerificationPage> createState() => _TokenVerificationPageState();
}

class _TokenVerificationPageState extends State<TokenVerificationPage> {
  final List<TextEditingController> _controllers = List.generate(6, (index) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(6, (index) => FocusNode());
  bool _isLoading = false;
  String _errorMessage = '';
  final PasswordResetService _passwordResetService = PasswordResetService();

  @override
  void dispose() {
    for (var controller in _controllers) {
      controller.dispose();
    }
    for (var focusNode in _focusNodes) {
      focusNode.dispose();
    }
    super.dispose();
  }

  Future<void> _verifyToken() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      // 组合所有输入框的值
      String token = _controllers.map((controller) => controller.text).join();
      
      if (token.length != 6) {
        setState(() {
          _errorMessage = 'Please enter a 6-digit code';
          _isLoading = false;
        });
        return;
      }

      // 验证令牌
      final result = await _passwordResetService.verifyToken(token);
      
      if (result['success']) {
        // 令牌验证成功，跳转到密码重置页面
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => PasswordResetPage(
                verificationCode: token, // 传递验证码
                userId: result['userId'],
                email: widget.email,
              ),
            ),
          );
        }
      } else {
        setState(() {
          _errorMessage = result['error'] ?? 'Invalid token';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'An error occurred. Please try again.';
        _isLoading = false;
      });
    }
  }

  Future<void> _resendCode() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final result = await _passwordResetService.generateAndStoreToken(widget.email);
      
      if (result?['success'] == true) {
        // 发送邮件
        final emailSent = await _passwordResetService.sendResetEmail(
          widget.email,
          result!['token'],
        );
        
        if (emailSent) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Verification code sent to your email'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          setState(() {
            _errorMessage = 'Failed to send email. Please try again.';
          });
        }
      } else {
        setState(() {
          _errorMessage = result?['error'] ?? 'Failed to generate token';
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
      backgroundColor: const Color(0xFFC1FF72),
      appBar: AppBar(
        backgroundColor: const Color(0xFFC1FF72),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // CalorieCare Logo and Title
              Column(
                children: [
                  const Text(
                    'CalorieCare',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Image.asset(
                    'assets/Salad.png',
                    height: 100,
                    width: 100,
                  ),
                ],
              ),
              const SizedBox(height: 40),
              const Text(
                'Enter Verification Code',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'We sent a 6-digit code to ${widget.email}',
                style: const TextStyle(
                  fontSize: 16,
                  color: Colors.white70,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 30),
              // 6位数字输入框
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: List.generate(6, (index) {
                  return SizedBox(
                    width: 45,
                    height: 55,
                    child: TextFormField(
                      controller: _controllers[index],
                      focusNode: _focusNodes[index],
                      textAlign: TextAlign.center,
                      keyboardType: TextInputType.number,
                      maxLength: 1,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.white,
                        counterText: '',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      onChanged: (value) {
                        if (value.isNotEmpty && index < 5) {
                          _focusNodes[index + 1].requestFocus();
                        } else if (value.isEmpty && index > 0) {
                          _focusNodes[index - 1].requestFocus();
                        }
                        
                        // 自动验证当所有框都填满时
                        if (index == 5 && value.isNotEmpty) {
                          bool allFilled = _controllers.every((controller) => controller.text.isNotEmpty);
                          if (allFilled) {
                            _verifyToken();
                          }
                        }
                        
                        setState(() {
                          _errorMessage = '';
                        });
                      },
                    ),
                  );
                }),
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
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFFC1FF72),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                  onPressed: _isLoading ? null : _verifyToken,
                  child: _isLoading
                      ? const CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFC1FF72)),
                        )
                      : const Text(
                          'Verify Code',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 20),
              TextButton(
                onPressed: _isLoading ? null : _resendCode,
                child: const Text(
                  'Resend Code',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}