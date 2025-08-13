import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

class LoadingUtils {
  static bool _isLoading = false;

  /// 显示加载对话框
  static void showLoading(BuildContext context, {String? message}) {
    if (_isLoading) return; // 防止重复显示
    
    _isLoading = true;
    showDialog(
      context: context,
      barrierDismissible: false, // 防止用户点击外部关闭
      builder: (BuildContext context) {
        return PopScope(
          canPop: false, // 防止用户返回键关闭
          child: Center(
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: 130, // 进一步减小宽度
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Lottie 动画
                  SizedBox(
                    height: 90,
                    width: 90,
                    child: Lottie.asset(
                      'assets/loading.json',
                      fit: BoxFit.contain,
                    ),
                  ),
                  const SizedBox(height: 6),
                  // 加载文字
                  Text(
                    message ?? 'Loading...',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF5AA162),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// 隐藏加载对话框
  static void hideLoading(BuildContext context) {
    if (_isLoading) {
      _isLoading = false;
      Navigator.of(context, rootNavigator: true).pop();
    }
  }

  /// 显示加载对话框并执行异步操作
  static Future<T> showLoadingWhile<T>(
    BuildContext context,
    Future<T> Function() operation, {
    String? message,
  }) async {
    showLoading(context, message: message);
    try {
      final result = await operation();
      hideLoading(context);
      return result;
    } catch (e) {
      hideLoading(context);
      rethrow;
    }
  }
} 