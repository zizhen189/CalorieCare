
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:caloriecare/user_model.dart';
import 'package:caloriecare/homepage.dart';
import 'package:caloriecare/session_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'streak_service.dart'; // Added import for StreakService
import 'custom_message_page.dart'; // Added import for CustomMessagePage
import 'invite_supervisor_page.dart'; // Added import for InviteSupervisorPage

class SupervisorStreakPage extends StatefulWidget {
  final List<Map<String, dynamic>> supervisors;
  final UserModel? user;
  final bool bothLoggedToday;
  final DateTime? selectedDate; // Add selectedDate parameter

  const SupervisorStreakPage({
    Key? key,
    required this.supervisors,
    this.user,
    required this.bothLoggedToday,
    this.selectedDate, // Add to constructor
  }) : super(key: key);

  @override
  _SupervisorStreakPageState createState() => _SupervisorStreakPageState();
}

class _SupervisorStreakPageState extends State<SupervisorStreakPage> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  Map<String, int> _supervisorStreaks = {}; // Store streaks for each supervision
  bool _isLoading = true;
  bool _currentUserLoggedToday = false; // Add this field

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _loadSupervisions();
    _checkCurrentUserLoggedToday(); // Add this call
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // Add this method to check if current user logged today
  Future<void> _checkCurrentUserLoggedToday() async {
    try {
      UserModel? currentUser = widget.user ?? await SessionService.getUserSession();
      if (currentUser == null) return;

      final today = DateTime.now();
      final todayStr = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
      
      final todayLogQuery = await FirebaseFirestore.instance
          .collection('LogMeal')
          .where('UserID', isEqualTo: currentUser.userID)
          .where('LogDate', isEqualTo: todayStr)
          .get();

      setState(() {
        _currentUserLoggedToday = todayLogQuery.docs.isNotEmpty;
      });
    } catch (e) {
      print('Error checking current user log status: $e');
    }
  }

  Future<void> _loadSupervisions() async {
    try {
      UserModel? currentUser = widget.user ?? await SessionService.getUserSession();
      if (currentUser == null) {
        setState(() {
          _isLoading = false;
        });
        return;
      }

      final db = FirebaseFirestore.instance;
      final currentUserId = currentUser.userID ?? '';

      Map<String, int> streaks = {};
      List<Map<String, dynamic>> validSupervisors = [];
      
      // Load supervision data for each supervisor and filter out rejected ones
      for (var supervisor in widget.supervisors) {
        final supervisionId = supervisor['supervisionId'];
        
        // Get supervision data directly from Supervision collection
        // Only get accepted supervisions to filter out rejected ones
        final supervisionQuery = await db
            .collection('Supervision')
            .where('SupervisionID', isEqualTo: supervisionId)
            .where('Status', isEqualTo: 'accepted')
            .get();

        if (supervisionQuery.docs.isNotEmpty) {
          final supervisionData = supervisionQuery.docs.first.data();
          final currentStreakDays = supervisionData['CurrentStreakDays'] ?? 0;
          
          // Use Supervision's LastLoggedDate for streak display
          final lastLoggedDate = supervisionData['LastLoggedDate'];
          
          // Store the supervision data
          streaks[supervisionId] = currentStreakDays;
          supervisor['currentStreakDays'] = currentStreakDays;
          supervisor['lastLoggedDate'] = lastLoggedDate;
          
          // Only add to valid supervisors if status is accepted
          validSupervisors.add(supervisor);
        } else {
          // If no accepted supervision record found, skip this supervisor
          print('Skipping rejected supervision: $supervisionId');
          continue;
        }
      }

      // Update the supervisors list to only include accepted ones
      widget.supervisors.clear();
      widget.supervisors.addAll(validSupervisors);

      setState(() {
        _supervisorStreaks = streaks;
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading supervisor streak: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  bool _isLastLoggedDateToday(dynamic lastLoggedDate) {
    if (lastLoggedDate == null) {
      return false;
    }
    final now = DateTime.now();
    
    DateTime lastLogged;
    if (lastLoggedDate is Timestamp) {
      lastLogged = lastLoggedDate.toDate();
    } else if (lastLoggedDate is String) {
      // Parse string date format "yyyy-MM-dd"
      try {
        lastLogged = DateTime.parse(lastLoggedDate);
      } catch (e) {
        return false;
      }
    } else if (lastLoggedDate is DateTime) {
      lastLogged = lastLoggedDate;
    } else {
      return false;
    }
    
    return lastLogged.year == now.year &&
           lastLogged.month == now.month &&
           lastLogged.day == now.day;
  }

  bool _allSupervisorsLogged() {
    if (widget.supervisors.isEmpty) return false;
    // Check if all supervisors have active streaks and logged today
    return widget.supervisors.every((s) => 
      (s['currentStreakDays'] ?? 0) > 0 && 
      _isLastLoggedDateToday(s['lastLoggedDate'])
    );
  }

  String _getStatusMessage() {
    if (widget.supervisors.isEmpty) {
      return 'No supervisors found.';
    }
    
    final activeSupervisorsToday = widget.supervisors.where((s) => 
      (s['currentStreakDays'] ?? 0) > 0 && 
      _isLastLoggedDateToday(s['lastLoggedDate'])
    ).length;
    final totalSupervisors = widget.supervisors.length;
    
    if (activeSupervisorsToday == totalSupervisors) {
      return 'Great! All supervisors logged today!';
    } else if (activeSupervisorsToday == 0) {
      return 'Waiting for supervisors to log today...';
    } else {
      return '$activeSupervisorsToday of $totalSupervisors supervisors logged today.';
    }
  }

  void _showCustomMessageDialog(Map<String, dynamic> supervisor) {
    // Navigate to custom message page instead of showing dialog
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CustomMessagePage(
          supervisor: supervisor,
          currentUserId: widget.user?.userID ?? '',
        ),
      ),
    );
  }

  Future<void> _sendCustomMessage(Map<String, dynamic> supervisor) async {
    try {
      final supervisionId = supervisor['supervisionId'];
      final message = supervisor['customMessage'] ?? '';
      
      // Generate notification ID
      final notificationId = await _generateNotificationId();
      
      // Get current user info
      UserModel? currentUser = widget.user ?? await SessionService.getUserSession();
      if (currentUser == null) return;
      
      // Get supervisor user ID from supervision
      final supervisionQuery = await FirebaseFirestore.instance
          .collection('Supervision')
          .where('SupervisionID', isEqualTo: supervisionId)
          .get();
      
      if (supervisionQuery.docs.isEmpty) return;
      
      final supervisionData = supervisionQuery.docs.first.data();
      final supervisorUserId = supervisionData['SupervisorID'];
      
      // Store notification in Firebase
      await FirebaseFirestore.instance.collection('Notifications').add({
        'notificationId': notificationId,
        'title': 'Meal Reminder from ${currentUser.firstName}',
        'message': message.isNotEmpty ? message : "Don't forget to log your meals today! 🍽️",
        'senderUserId': currentUser.userID,
        'recipientUserId': supervisorUserId,
        'supervisionId': supervisionId,
        'createdAt': FieldValue.serverTimestamp(),
        'isRead': false,
        'type': 'meal_reminder',
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Message sent successfully!')),
      );
    } catch (e) {
      print('Error sending message: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error sending message: $e')),
      );
    }
  }

  // Generate unique notification ID
  Future<String> _generateNotificationId() async {
    final notificationQuery = await FirebaseFirestore.instance
        .collection('Notifications')
        .orderBy('notificationId', descending: true)
        .limit(1)
        .get();
    
    if (notificationQuery.docs.isEmpty) {
      return 'N00001';
    }
    
    final lastNotificationId = notificationQuery.docs.first['notificationId'];
    final lastNumber = int.parse(lastNotificationId.substring(1));
    final newNumber = lastNumber + 1;
    return 'N${newNumber.toString().padLeft(5, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF3F6F8),
      body: SafeArea(
        child: Column(
          children: [
            // Scrollable content
            Expanded(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.start,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const SizedBox(height: 120),
                      const Text(
                        'Your Supervisor Streak',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF5AA162),
                        ),
                      ),
                      const SizedBox(height: 16),
                      
                      // Show supervisors - centered layout
                      if (widget.supervisors.isNotEmpty)
                        Column(
                          children: [
                            ...widget.supervisors.map((supervisor) => 
                              Container(
                                margin: const EdgeInsets.symmetric(vertical: 8),
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE8F5E9),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.grey.shade400, width: 1),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    CircleAvatar(
                                      backgroundColor: Colors.white,
                                      backgroundImage: AssetImage(
                                        supervisor['gender']?.toLowerCase() == 'male' 
                                            ? 'assets/Male.png' 
                                            : 'assets/Female.png',
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Text(
                                        supervisor['name'],
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    // Show supervisor streak number and fire icon
                                    Builder(
                                      builder: (context) {
                                        final currentStreakDays = supervisor['currentStreakDays'] ?? 0;
                                        final lastLoggedDate = supervisor['lastLoggedDate'];
                                        final isToday = _isLastLoggedDateToday(lastLoggedDate);
                                        final hasStreak = currentStreakDays > 0;
                                        final shouldShowRed = lastLoggedDate != null && isToday && hasStreak;
                                        // Show notification button only if:
                                        // 1. Current user has logged today AND supervisor hasn't logged today (U1 can remind U2)
                                        // 2. OR both users haven't logged today (mutual reminder)
                                        final needsReminder = ((_currentUserLoggedToday && !isToday) || 
                                                              (!_currentUserLoggedToday && !isToday));
                                        
                                        return Row(
                                          children: [
                                            Image.asset(
                                              shouldShowRed ? 'assets/Logged.png' : 'assets/Notlog.png',
                                              width: 28,
                                              height: 28,
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              '$currentStreakDays',
                                              style: TextStyle(
                                                color: shouldShowRed ? Colors.red : Colors.grey,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 24,
                                              ),
                                            ),
                                            // Add notification button based on mutual logging status
                                            if (needsReminder) ...[
                                              const SizedBox(width: 12),
                                              GestureDetector(
                                                onTap: () => _showCustomMessageDialog(supervisor),
                                                child: Container(
                                                  padding: const EdgeInsets.all(6),
                                                  decoration: BoxDecoration(
                                                    color: const Color(0xFF5AA162),
                                                    borderRadius: BorderRadius.circular(20),
                                                  ),
                                                  child: const Icon(
                                                    Icons.notifications,
                                                    color: Colors.white,
                                                    size: 20,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ],
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      
                      const SizedBox(height: 24),
                      
                      // Status message
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8F5E9),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              height: 40,
                              width: 40,
                              child: _allSupervisorsLogged() 
                                  ? Image.asset('assets/Logged.png', fit: BoxFit.contain)
                                  : Image.asset('assets/Notlog.png', fit: BoxFit.contain),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Text(
                                _getStatusMessage(),
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey[700],
                                  fontWeight: FontWeight.w500,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                            if (_allSupervisorsLogged())
                              const Icon(
                                Icons.check_circle,
                                color: Color(0xFF5AA162),
                                size: 28,
                              ),
                          ],
                        ),
                      ),
                      
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
            ),
            
            // Fixed Continue button at bottom
            Padding(
              padding: const EdgeInsets.all(32.0),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF84b882),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                    elevation: 0,
                  ),
                  onPressed: () {
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(
                        builder: (context) => HomePage(
                          user: widget.user,
                          initialSelectedDate: widget.selectedDate, // Preserve selected date
                        ),
                      ),
                    );
                  },
                  child: const Text(
                    'Continue',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
} 











