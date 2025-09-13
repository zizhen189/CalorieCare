import 'package:flutter/material.dart';
import 'package:caloriecare/auto_adjustment_service.dart';
import 'package:caloriecare/calorie_adjustment_service.dart';
import 'package:caloriecare/session_service.dart';
import 'package:caloriecare/user_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AutoAdjustmentDebugPage extends StatefulWidget {
  const AutoAdjustmentDebugPage({super.key});

  @override
  State<AutoAdjustmentDebugPage> createState() => _AutoAdjustmentDebugPageState();
}

class _AutoAdjustmentDebugPageState extends State<AutoAdjustmentDebugPage> {
  final AutoAdjustmentService _autoAdjustmentService = AutoAdjustmentService();
  final CalorieAdjustmentService _adjustmentService = CalorieAdjustmentService();
  
  Map<String, dynamic>? _debugInfo;
  bool _isLoading = false;
  String? _currentUserId;

  @override
  void initState() {
    super.initState();
    _loadDebugInfo();
  }

  Future<void> _loadDebugInfo() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // 获取当前用户
      UserModel? currentUser = await SessionService.getUserSession();
      if (currentUser == null) {
        setState(() {
          _debugInfo = {'error': 'No user session found'};
          _isLoading = false;
        });
        return;
      }

      _currentUserId = currentUser.userID;

      // 获取调试信息
      final debugInfo = await _autoAdjustmentService.debugAutoAdjustmentStatus(currentUser.userID);
      
      // 获取更多详细信息
      final prefs = await SharedPreferences.getInstance();
      final autoAdjustmentKey = 'auto_adjustment_enabled_${currentUser.userID}';
      final isEnabledInPrefs = prefs.getBool(autoAdjustmentKey);
      
      // 检查今天的调整记录
      final hasAdjustedToday = await _adjustmentService.hasAdjustedToday(currentUser.userID);
      
      // 获取调整历史
      final adjustmentHistory = await _adjustmentService.getAdjustmentHistory(currentUser.userID, limit: 5);

      setState(() {
        _debugInfo = {
          ...debugInfo,
          'userId': currentUser.userID,
          'isEnabledInPrefs': isEnabledInPrefs,
          'hasAdjustedToday': hasAdjustedToday,
          'adjustmentHistory': adjustmentHistory,
          'timestamp': DateTime.now().toIso8601String(),
        };
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _debugInfo = {'error': e.toString()};
        _isLoading = false;
      });
    }
  }

  Future<void> _testAutoAdjustment() async {
    if (_currentUserId == null) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final result = await _autoAdjustmentService.executeNow(_currentUserId!);
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Test result: ${result['success'] ? 'Success' : result['reason']}'),
          backgroundColor: result['success'] ? Colors.green : Colors.red,
        ),
      );
      
      // 重新加载调试信息
      await _loadDebugInfo();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Test error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }

    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _toggleAutoAdjustment() async {
    if (_currentUserId == null) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final currentStatus = _debugInfo?['isEnabled'] ?? false;
      final newStatus = !currentStatus;
      
      await _adjustmentService.setAutoAdjustmentEnabled(_currentUserId!, newStatus);
      
      if (newStatus) {
        await _autoAdjustmentService.startAutoAdjustment(_currentUserId!);
      } else {
        _autoAdjustmentService.stopAutoAdjustment();
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Auto adjustment ${newStatus ? 'enabled' : 'disabled'}'),
          backgroundColor: Colors.green,
        ),
      );
      
      // 重新加载调试信息
      await _loadDebugInfo();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }

    setState(() {
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Auto Adjustment Debug'),
        backgroundColor: const Color(0xFF5AA162),
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _debugInfo == null
              ? const Center(child: Text('No debug info available'))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 基本信息
                      _buildInfoCard('Basic Info', {
                        'User ID': _debugInfo!['userId'] ?? 'N/A',
                        'Is Enabled': _debugInfo!['isEnabled'] ?? 'N/A',
                        'Is Enabled in Prefs': _debugInfo!['isEnabledInPrefs'] ?? 'N/A',
                        'Service Running': _debugInfo!['isRunning'] ?? 'N/A',
                        'Current User ID': _debugInfo!['currentUserId'] ?? 'N/A',
                        'Has Adjusted Today': _debugInfo!['hasAdjustedToday'] ?? 'N/A',
                        'Timestamp': _debugInfo!['timestamp'] ?? 'N/A',
                      }),
                      
                      const SizedBox(height: 16),
                      
                      // 调整历史
                      if (_debugInfo!['adjustmentHistory'] != null)
                        _buildAdjustmentHistoryCard(),
                      
                      const SizedBox(height: 16),
                      
                      // 操作按钮
                      _buildActionButtons(),
                      
                      const SizedBox(height: 16),
                      
                      // 错误信息
                      if (_debugInfo!['error'] != null)
                        _buildErrorCard(),
                    ],
                  ),
                ),
    );
  }

  Widget _buildInfoCard(String title, Map<String, dynamic> info) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            ...info.entries.map((entry) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 120,
                    child: Text(
                      '${entry.key}:',
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      entry.value.toString(),
                      style: TextStyle(
                        color: entry.key == 'Is Enabled' || entry.key == 'Service Running'
                            ? (entry.value == true ? Colors.green : Colors.red)
                            : null,
                      ),
                    ),
                  ),
                ],
              ),
            )),
          ],
        ),
      ),
    );
  }

  Widget _buildAdjustmentHistoryCard() {
    final history = _debugInfo!['adjustmentHistory'] as List<dynamic>;
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Recent Adjustments',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            if (history.isEmpty)
              const Text('No adjustments found')
            else
              ...history.map((adjustment) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text('${adjustment['AdjustDate'] ?? 'N/A'}'),
                    ),
                    Text('${adjustment['PreviousTargetCalories'] ?? 'N/A'} → ${adjustment['AdjustTargetCalories'] ?? 'N/A'}'),
                  ],
                ),
              )),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Actions',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _testAutoAdjustment,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Test Auto Adjustment'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _toggleAutoAdjustment,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _debugInfo?['isEnabled'] == true ? Colors.red : Colors.green,
                      foregroundColor: Colors.white,
                    ),
                    child: Text(_debugInfo?['isEnabled'] == true ? 'Disable' : 'Enable'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _loadDebugInfo,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.grey,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Refresh Info'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorCard() {
    return Card(
      color: Colors.red.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Error',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.red,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _debugInfo!['error'].toString(),
              style: const TextStyle(color: Colors.red),
            ),
          ],
        ),
      ),
    );
  }
}
