import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:caloriecare/homepage.dart';
import 'package:caloriecare/session_service.dart';
import 'user_model.dart'; // Import the user model
import 'supervisor_streak_page.dart';

class StreakPage extends StatefulWidget {
  final int streakDays;
  final bool isNewDay; // To control the animation
  final UserModel? user; // Add user model
  final DateTime? selectedDate; // Add selectedDate parameter

  const StreakPage({
    Key? key,
    required this.streakDays,
    required this.isNewDay,
    this.user, // Make user optional
    this.selectedDate, // Add to constructor
  }) : super(key: key);

  @override
  State<StreakPage> createState() => _StreakPageState();
}

class _StreakPageState extends State<StreakPage> {

  @override
  void initState() {
    super.initState();
    // Remove automatic navigation check - let user manually trigger it
  }

  Future<void> _checkUserAndNavigate() async {
    UserModel? currentUser = widget.user ?? await SessionService.getUserSession();
    if (currentUser == null || currentUser.userID.isEmpty) {
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => HomePage(user: currentUser)),
          (route) => false,
        );
      }
      return;
    }
    final currentUserId = currentUser.userID;

    try {
      final db = FirebaseFirestore.instance;
      // Check for supervision relationships
      final userSupervisionsQuery = await db.collection('SupervisionList')
          .where('UserID', isEqualTo: currentUserId)
          .get();

      if (userSupervisionsQuery.docs.isEmpty) {
        // No supervisor relationships, go to homepage
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => HomePage(user: currentUser)),
        );
        return;
      }

      final supervisionIds = userSupervisionsQuery.docs
          .map((doc) => doc['SupervisionID'] as String)
          .toList();

      // Get accepted supervisions
      final supervisionsQuery = await db.collection('Supervision')
          .where('SupervisionID', whereIn: supervisionIds)
          .where('Status', isEqualTo: 'accepted')
          .get();

      if (supervisionsQuery.docs.isEmpty) {
        // No accepted supervisions, go to homepage
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => HomePage(user: currentUser)),
        );
        return;
      }

      // Get all users in these supervisions
      final allPairsQuery = await db.collection('SupervisionList')
          .where('SupervisionID', whereIn: supervisionIds)
          .get();

      final allUserIds = allPairsQuery.docs
          .map((doc) => doc['UserID'] as String)
          .toSet()
          .toList();

      // Get user data
      final usersMap = <String, Map<String, dynamic>>{};
      for (String userId in allUserIds) {
        final userQuery = await db.collection('User')
            .where('UserID', isEqualTo: userId)
            .get();
        if (userQuery.docs.isNotEmpty) {
          usersMap[userId] = userQuery.docs.first.data();
        }
      }

      // Check today's logs for all users
      final today = DateTime.now();
      final todayStr = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
      final todayLogQuery = await db.collection('LogMeal')
          .where('UserID', whereIn: allUserIds)
          .where('LogDate', isEqualTo: todayStr)
          .get();
      final Set<String> usersLoggedToday = todayLogQuery.docs
          .map((doc) => doc['UserID'] as String)
          .toSet();

      // Build supervisor data
      final List<Map<String, dynamic>> supervisors = [];
      bool allUsersLoggedToday = true;

      for (var supervisionId in supervisionIds) {
        final usersInSupervision = allPairsQuery.docs
            .where((doc) => doc['SupervisionID'] == supervisionId)
            .map((doc) => doc['UserID'] as String)
            .toList();

        final otherUserId = usersInSupervision
            .firstWhere((id) => id != currentUserId, orElse: () => '');

        if (otherUserId.isNotEmpty && usersMap.containsKey(otherUserId)) {
          final otherUserData = usersMap[otherUserId]!;
          final hasLoggedToday = usersLoggedToday.contains(otherUserId);
          
          if (!hasLoggedToday) {
            allUsersLoggedToday = false;
          }

          supervisors.add({
            'supervisionId': supervisionId,
            'name': otherUserData['UserName'] ?? otherUserData['username'] ?? 'Unknown User',
            'gender': otherUserData['Gender'] ?? otherUserData['gender'] ?? 'male',
            'hasLoggedToday': hasLoggedToday,
          });
        }
      }

      // Check if current user also logged today
      final currentUserLoggedToday = usersLoggedToday.contains(currentUserId);
      final bothLoggedToday = allUsersLoggedToday && currentUserLoggedToday;

      if (supervisors.isNotEmpty) {
        // Navigate to supervisor streak page
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => SupervisorStreakPage(
              supervisors: supervisors,
              user: currentUser,
              bothLoggedToday: false, // Add the missing parameter
              selectedDate: widget.selectedDate, // Pass selected date
            ),
          ),
        );
      } else {
        // No supervisors found, go to homepage
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => HomePage(
              user: currentUser,
              initialSelectedDate: widget.selectedDate, // Pass selected date back
            ),
          ),
        );
      }
    } catch (e) {
      print('Error checking supervisor: $e');
      // In case of error, go to homepage
      UserModel? currentUser = widget.user ?? await SessionService.getUserSession();
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => HomePage(
            user: currentUser,
            initialSelectedDate: widget.selectedDate, // Pass selected date back
          ),
        ),
      );
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F6F8), // Light grey-blue background
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
                      const SizedBox(height: 80),
                      const Text(
                        'Your Streak',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF5AA162), // Muted green
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Lottie Streak Animation
                      SizedBox(
                        height: 180,
                        width: 180,
                        child: Lottie.asset(
                          'assets/streak.json',
                          fit: BoxFit.contain,
                          repeat: true, // 正常循环播放
                        ),
                      ),
                      const SizedBox(height: 24),
                      // Streak details card
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8F5E9), // Very light green
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // Animated streak number
                            TweenAnimationBuilder<int>(
                              tween: IntTween(
                                begin: widget.isNewDay && widget.streakDays > 0 ? widget.streakDays - 1 : widget.streakDays,
                                end: widget.streakDays,
                              ),
                              duration: const Duration(milliseconds: 800),
                              builder: (context, value, child) {
                                return Text(
                                  value.toString(),
                                  style: const TextStyle(
                                    fontSize: 36,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF3F8146), // Darker green
                                  ),
                                );
                              },
                            ),
                            const SizedBox(width: 8),
                            // Up arrow, only shown on new day
                            if (widget.isNewDay)
                              const Icon(
                                Icons.arrow_upward,
                                color: Color(0xFF3F8146),
                                size: 28,
                              ),
                            const Spacer(),
                            // Small streak animation
                            SizedBox(
                              height: 40,
                              width: 40,
                              child: Lottie.asset(
                                'assets/streak.json',
                                fit: BoxFit.contain,
                                repeat: true, // 小图标可以循环播放
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        widget.isNewDay ? 'You\'ve kept your streak alive!' : 'You logged again today!',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey[600],
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
                    backgroundColor: const Color(0xFF84b882), // Muted green from image
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                    elevation: 0,
                  ),
                  onPressed: () async {
                    if (mounted) {
                      // Check for supervisor relationships
                      await _checkUserAndNavigate();
                    }
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



