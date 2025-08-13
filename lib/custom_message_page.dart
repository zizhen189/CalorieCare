import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'notification_service.dart';

class CustomMessagePage extends StatefulWidget {
  final Map<String, dynamic> supervisor;
  final String currentUserId;

  const CustomMessagePage({
    Key? key,
    required this.supervisor,
    required this.currentUserId,
  }) : super(key: key);

  @override
  State<CustomMessagePage> createState() => _CustomMessagePageState();
}

class _CustomMessagePageState extends State<CustomMessagePage> {
  final TextEditingController _messageController = TextEditingController();
  final NotificationService _notificationService = NotificationService();
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _initializeNotifications();
    _loadCurrentMessage();
  }

  Future<void> _initializeNotifications() async {
    await _notificationService.initialize();
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentMessage() async {
    try {
      final supervisionId = widget.supervisor['supervisionId'];
      
      // Get current custom message from SupervisionList
      final supervisionListQuery = await FirebaseFirestore.instance
          .collection('SupervisionList')
          .where('SupervisionID', isEqualTo: supervisionId)
          .where('UserID', isEqualTo: widget.currentUserId)
          .get();

      if (supervisionListQuery.docs.isNotEmpty) {
        final data = supervisionListQuery.docs.first.data();
        final customMessage = data['CustomMessage'] ?? '';
        
        setState(() {
          _messageController.text = customMessage;
          _isLoading = false;
        });
      } else {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error loading custom message: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _saveCustomMessage() async {
    if (_isSaving) return;

    setState(() {
      _isSaving = true;
    });

    try {
      final supervisionId = widget.supervisor['supervisionId'];
      final newMessage = _messageController.text.trim();
      
      // Update custom message in SupervisionList
      final supervisionListQuery = await FirebaseFirestore.instance
          .collection('SupervisionList')
          .where('SupervisionID', isEqualTo: supervisionId)
          .where('UserID', isEqualTo: widget.currentUserId)
          .get();

      if (supervisionListQuery.docs.isNotEmpty) {
        await supervisionListQuery.docs.first.reference.update({
          'CustomMessage': newMessage,
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Custom message saved!')),
        );
      }
    } catch (e) {
      print('Error saving custom message: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving message: $e')),
      );
    } finally {
      setState(() {
        _isSaving = false;
      });
    }
  }

  Future<void> _sendCustomMessage() async {
    try {
      // Get recipient user ID from SupervisionList (the other user in the supervision)
      final supervisionListQuery = await FirebaseFirestore.instance
          .collection('SupervisionList')
          .where('SupervisionID', isEqualTo: widget.supervisor['supervisionId'])
          .get();
      
      if (supervisionListQuery.docs.isEmpty) return;
      
      // Find the other user in the supervision (not the current user)
      String? recipientUserId;
      for (var doc in supervisionListQuery.docs) {
        final userData = doc.data();
        final userId = userData['UserID'];
        if (userId != widget.currentUserId) {
          recipientUserId = userId;
          break;
        }
      }
      
      if (recipientUserId == null) {
        print('Could not find recipient user ID');
        return;
      }
      
      // Update CustomMessage for the recipient user
      final customMessage = _messageController.text.trim();
      final messageToSend = customMessage.isNotEmpty 
          ? customMessage
          : '${widget.supervisor['name']} is waiting for you to log your meals today! 🍽️';
      
      // Find and update the sender's record in SupervisionList
      for (var doc in supervisionListQuery.docs) {
        final userData = doc.data();
        final userId = userData['UserID'];
        if (userId == widget.currentUserId) {
          await doc.reference.update({
            'CustomMessage': messageToSend,
          });
          break;
        }
      }
      
      // Send RTDB notification
      await _notificationService.sendCustomMessage(
        receiverId: recipientUserId,
        message: messageToSend,
        senderId: widget.currentUserId,
        senderName: widget.supervisor['name'] ?? 'Supervisor',
      );
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Message sent successfully!'),
          backgroundColor: Colors.green,
        ),
      );
      
      // Return to previous page after sending
      Navigator.pop(context);
    } catch (e) {
      print('Error sending custom message: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error sending message: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }



  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Remind ${widget.supervisor['name']}',
          style: const TextStyle(
            color: Colors.black,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Supervisor info
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8F5E9),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade400, width: 1),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: Colors.white,
                            backgroundImage: AssetImage(
                              widget.supervisor['gender']?.toLowerCase() == 'male' 
                                  ? 'assets/Male.png' 
                                  : 'assets/Female.png',
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.supervisor['name'],
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                ),
                                const Text(
                                  'Has not logged meals today',
                                  style: TextStyle(color: Colors.grey, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                          Image.asset(
                            'assets/Notlog.png',
                            width: 28,
                            height: 28,
                          ),
                        ],
                      ),
                    ),
                    
                    const SizedBox(height: 32),
                    
                    // Custom message section
                    const Text(
                      'Custom Reminder Message',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF5AA162),
                      ),
                    ),
                    
                    const SizedBox(height: 8),
                    
                    const Text(
                      'Write a personalized message to remind them to log their meals:',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey,
                      ),
                    ),
                    
                    const SizedBox(height: 16),
                    
                    // Message input field
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: TextField(
                        controller: _messageController,
                        maxLines: 4,
                        maxLength: 200,
                        decoration: const InputDecoration(
                          hintText: 'Don\'t forget to log your meals today! 🍽️',
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.all(16),
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 16),
                    
                    // Preset messages
                    const Text(
                      'Quick Messages:',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey,
                      ),
                    ),
                    
                    const SizedBox(height: 8),
                    
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildQuickMessage('Hey! Don\'t forget to log your meals today! 🍽️'),
                        _buildQuickMessage('Remember to track your food intake! 📱'),
                        _buildQuickMessage('Time to log those delicious meals! 😋'),
                        _buildQuickMessage('Your health journey needs you to log today! 💪'),
                      ],
                    ),
                    
                    const SizedBox(height: 40), // Add some bottom padding
                  ],
                ),
              ),
            ),
            
            // Action buttons - fixed at bottom
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isSaving ? null : _saveCustomMessage,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        side: const BorderSide(color: Color(0xFF5AA162)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                      child: _isSaving
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text(
                              'Save Message',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF5AA162),
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                                              onPressed: _isSaving ? null : _sendCustomMessage,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF5AA162),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                        elevation: 0,
                      ),
                      child: _isSaving
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Text(
                              'Send Reminder',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickMessage(String message) {
    return GestureDetector(
      onTap: () {
        _messageController.text = message;
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFE8F5E9),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF5AA162).withOpacity(0.3)),
        ),
        child: Text(
          message,
          style: const TextStyle(
            fontSize: 12,
            color: Color(0xFF5AA162),
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
} 

