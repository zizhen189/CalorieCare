import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'user_model.dart';
import 'homepage.dart';

class GoalAchievementPage extends StatefulWidget {
  final double achievedWeight;
  final double newTDEE;
  final UserModel? user;

  const GoalAchievementPage({
    Key? key,
    required this.achievedWeight,
    required this.newTDEE,
    this.user,
  }) : super(key: key);

  @override
  State<GoalAchievementPage> createState() => _GoalAchievementPageState();
}

class _GoalAchievementPageState extends State<GoalAchievementPage>
    with TickerProviderStateMixin {
  late AnimationController _fadeController;
  late AnimationController _scaleController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    
    print('=== GOAL ACHIEVEMENT PAGE INIT ===');
    print('Achieved weight: ${widget.achievedWeight}');
    print('New TDEE: ${widget.newTDEE}');
    print('User: ${widget.user?.username}');
    
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );
    
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeInOut,
    ));
    
    _scaleAnimation = Tween<double>(
      begin: 0.5,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _scaleController,
      curve: Curves.elasticOut,
    ));
    
    // Start animations
    _fadeController.forward();
    Future.delayed(const Duration(milliseconds: 300), () {
      _scaleController.forward();
    });
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _scaleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.purple.shade100,
              Colors.blue.shade50,
              Colors.green.shade50,
            ],
          ),
        ),
        child: SafeArea(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        const SizedBox(height: 40),
                        
                        // Celebration Animation
                        ScaleTransition(
                          scale: _scaleAnimation,
                          child: Container(
                            height: 200,
                            width: 200,
                            child: Lottie.asset(
                              'assets/celebration.json',
                              repeat: true,
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                        
                        const SizedBox(height: 30),
                        
                        // Congratulations Text
                        ScaleTransition(
                          scale: _scaleAnimation,
                          child: Column(
                            children: [
                              Text(
                                '🎉 CONGRATULATIONS! 🎉',
                                style: TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.purple.shade700,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              
                              const SizedBox(height: 16),
                              
                              Text(
                                'You\'ve Achieved Your Goal!',
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.blue.shade700,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                        
                        const SizedBox(height: 40),
                        
                        // Achievement Details Card
                        ScaleTransition(
                          scale: _scaleAnimation,
                          child: Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.1),
                                  blurRadius: 20,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                            ),
                            child: Column(
                              children: [
                                // Trophy Icon
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: Colors.amber.shade100,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Icons.emoji_events,
                                    size: 48,
                                    color: Colors.amber.shade700,
                                  ),
                                ),
                                
                                const SizedBox(height: 20),
                                
                                Text(
                                  'Your Achievement',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.grey.shade800,
                                  ),
                                ),
                                
                                const SizedBox(height: 16),
                                
                                // Weight Achievement
                                _buildAchievementRow(
                                  icon: Icons.monitor_weight,
                                  label: 'Target Weight Reached',
                                  value: '${widget.achievedWeight.toStringAsFixed(1)} kg',
                                  color: Colors.green,
                                ),
                                
                                const SizedBox(height: 12),
                                
                                // New Goal
                                _buildAchievementRow(
                                  icon: Icons.flag,
                                  label: 'New Goal',
                                  value: 'Maintain Weight',
                                  color: Colors.blue,
                                ),
                                
                                const SizedBox(height: 12),
                                
                                // New Calorie Target
                                _buildAchievementRow(
                                  icon: Icons.local_fire_department,
                                  label: 'Daily Calorie Target',
                                  value: '${widget.newTDEE.round()} kcal',
                                  color: Colors.orange,
                                ),
                              ],
                            ),
                          ),
                        ),
                        
                        const SizedBox(height: 30),
                        
                        // Motivational Message
                        ScaleTransition(
                          scale: _scaleAnimation,
                          child: Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Colors.green.shade50,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.green.shade200),
                            ),
                            child: Column(
                              children: [
                                Icon(
                                  Icons.favorite,
                                  color: Colors.red.shade400,
                                  size: 32,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'Amazing work! You\'ve successfully reached your target weight. Your goal has been automatically updated to "Maintain Weight" and your daily calorie target has been adjusted to help you maintain this healthy weight.',
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: Colors.green.shade700,
                                    height: 1.5,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        ),
                        
                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
                ),
                
                // Continue Button
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: ScaleTransition(
                    scale: _scaleAnimation,
                    child: SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.of(context).pushAndRemoveUntil(
                            MaterialPageRoute(
                              builder: (context) => HomePage(user: widget.user),
                            ),
                            (route) => false,
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green.shade600,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          elevation: 8,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.home, size: 24),
                            const SizedBox(width: 12),
                            Text(
                              'Continue to Home',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAchievementRow({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade600,
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }
}