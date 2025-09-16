import 'package:caloriecare/user_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:caloriecare/invitation_notification_service.dart';
import 'package:caloriecare/fcm_invitation_service.dart';
import 'package:caloriecare/global_notification_manager.dart';

class InviteSupervisorPage extends StatefulWidget {
  final UserModel currentUser;

  const InviteSupervisorPage({Key? key, required this.currentUser}) : super(key: key);

  @override
  _InviteSupervisorPageState createState() => _InviteSupervisorPageState();
}

class _InviteSupervisorPageState extends State<InviteSupervisorPage> {
  final TextEditingController _searchController = TextEditingController();
  List<UserModel> _searchResults = [];
  bool _isLoading = false;
  String _searchQuery = '';
  final GlobalNotificationManager _globalNotificationManager = GlobalNotificationManager();
  final InvitationNotificationService _invitationService = InvitationNotificationService();

  Future<void> _searchUsers(String query) async {
    setState(() {
      _isLoading = true;
      _searchQuery = query;
    });

    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
        _isLoading = false;
      });
      return;
    }

    try {
      print('Searching for: $query'); // Debug print
      
      // First, let's check if there are any users in the database at all
      QuerySnapshot allUsersSnapshot = await FirebaseFirestore.instance
          .collection('User')
          .limit(5)
          .get();
      print('Total users in database (first 5): ${allUsersSnapshot.docs.length}'); // Debug print
      for (var doc in allUsersSnapshot.docs) {
        print('User data: ${doc.data()}'); // Debug print
      }
      
      // Search by username (case-sensitive "starts with")
      QuerySnapshot usernameSnapshot = await FirebaseFirestore.instance
          .collection('User')
          .where('UserName', isGreaterThanOrEqualTo: query)
          .where('UserName', isLessThanOrEqualTo: '$query\uf8ff')
          .get();
      print('Username search results: ${usernameSnapshot.docs.length}'); // Debug print
      
      // Also search by username case-insensitive (convert to lowercase)
      QuerySnapshot usernameLowerSnapshot = await FirebaseFirestore.instance
          .collection('User')
          .where('UserName', isGreaterThanOrEqualTo: query.toLowerCase())
          .where('UserName', isLessThanOrEqualTo: '${query.toLowerCase()}\uf8ff')
          .get();
      print('Username lowercase search results: ${usernameLowerSnapshot.docs.length}'); // Debug print

      // Search by userID (exact match)
      QuerySnapshot useridSnapshot = await FirebaseFirestore.instance
          .collection('User')
          .where('UserID', isEqualTo: query)
          .get();
      print('UserID search results: ${useridSnapshot.docs.length}'); // Debug print
      
      // Search by email (partial match - starts with)
      QuerySnapshot emailSnapshot = await FirebaseFirestore.instance
          .collection('User')
          .where('Email', isGreaterThanOrEqualTo: query)
          .where('Email', isLessThanOrEqualTo: '$query\uf8ff')
          .get();
      print('Email search results: ${emailSnapshot.docs.length}'); // Debug print
      
      // Also search by email case-insensitive (convert to lowercase)
      QuerySnapshot emailLowerSnapshot = await FirebaseFirestore.instance
          .collection('User')
          .where('Email', isGreaterThanOrEqualTo: query.toLowerCase())
          .where('Email', isLessThanOrEqualTo: '${query.toLowerCase()}\uf8ff')
          .get();
      print('Email lowercase search results: ${emailLowerSnapshot.docs.length}'); // Debug print

      // Get current user's blacklist
      final blacklistQuery = await FirebaseFirestore.instance
          .collection('Blacklist')
          .where('UserID', isEqualTo: widget.currentUser.userID)
          .get();
      
      final blockedUserIds = blacklistQuery.docs
          .map((doc) => doc['BlockedUserID'] as String)
          .toSet();
      print('Blocked users: $blockedUserIds'); // Debug print

      // Get current user's existing supervision relationships
      final supervisionQuery = await FirebaseFirestore.instance
          .collection('SupervisionList')
          .where('UserID', isEqualTo: widget.currentUser.userID)
          .get();
      
      final supervisionIds = supervisionQuery.docs
          .map((doc) => doc['SupervisionID'] as String)
          .toSet();
      print('Supervision IDs: $supervisionIds'); // Debug print

      // Get all users involved in these supervision relationships
      // BUT only include users with ACCEPTED or PENDING supervision relationships
      // Allow REJECTED users to be searchable again
      final Set<String> supervisionUserIds = <String>{};
      if (supervisionIds.isNotEmpty) {
        // First, get the status of each supervision
        final supervisionStatusQuery = await FirebaseFirestore.instance
            .collection('Supervision')
            .where('SupervisionID', whereIn: supervisionIds.toList())
            .get();
        
        final Map<String, String> supervisionStatusMap = {};
        for (var doc in supervisionStatusQuery.docs) {
          supervisionStatusMap[doc['SupervisionID']] = doc['Status'];
        }
        
        // Only include users from ACCEPTED or PENDING supervisions
        // Allow REJECTED users to be searchable again
        for (String supervisionId in supervisionIds) {
          final status = supervisionStatusMap[supervisionId];
          if (status == 'accepted' || status == 'pending') {
            final supervisionDetailsQuery = await FirebaseFirestore.instance
                .collection('SupervisionList')
                .where('SupervisionID', isEqualTo: supervisionId)
                .get();
            
            for (var doc in supervisionDetailsQuery.docs) {
              final userId = doc['UserID'] as String;
              if (userId != widget.currentUser.userID) {
                supervisionUserIds.add(userId);
              }
            }
          }
        }
      }
      print('Users with active supervision relationships (accepted/pending): $supervisionUserIds'); // Debug print

      final Map<String, UserModel> usersMap = {};
      
      // Process all search results
      for (var snapshot in [usernameSnapshot, usernameLowerSnapshot, useridSnapshot, emailSnapshot, emailLowerSnapshot]) {
        for (var doc in snapshot.docs) {
          try {
            final data = doc.data() as Map<String, dynamic>;
            print('Processing user data: $data'); // Debug print
            final user = UserModel.fromMap(data);
            
            // Filter out: current user, blocked users, and users with existing supervision relationships
            if (user.userID != widget.currentUser.userID && 
                !blockedUserIds.contains(user.userID) && 
                !supervisionUserIds.contains(user.userID)) {
              usersMap[user.userID] = user;
              print('Added user to results: ${user.username}'); // Debug print
            } else {
              if (blockedUserIds.contains(user.userID)) {
                print('Skipped blocked user: ${user.username}'); // Debug print
              } else if (supervisionUserIds.contains(user.userID)) {
                print('Skipped user with existing supervision relationship: ${user.username}'); // Debug print
              }
            }
          } catch (e) {
            print("Error processing search result: $e");
          }
        }
      }

      print('Total users found: ${usersMap.length}'); // Debug print
      setState(() {
        _searchResults = usersMap.values.toList();
        _isLoading = false;
      });
      
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      print("Error searching users: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('An error occurred while searching: $e')),
      );
    }
  }

  Future<void> _sendInvitation(UserModel invitedUser) async {
    final db = FirebaseFirestore.instance;
    final currentUser = widget.currentUser;

    try {
      // 0. Check if current user is blacklisted by the invited user
      final blacklistQuery = await db
          .collection('Blacklist')
          .where('UserID', isEqualTo: invitedUser.userID)
          .where('BlockedUserID', isEqualTo: currentUser.userID)
          .get();
      
      if (blacklistQuery.docs.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('You cannot send invitations to ${invitedUser.username}. You have been blocked.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
      // 1. Check if a supervision already exists between the two users
      final existingSupervisionQuery = await db
          .collection('SupervisionList')
          .where('UserID', isEqualTo: currentUser.userID)
          .get();

      List<String> supervisionIds = existingSupervisionQuery.docs.map((doc) => doc['SupervisionID'] as String).toList();
      if(supervisionIds.isNotEmpty) {
        final checkPartnerQuery = await db
            .collection('SupervisionList')
            .where('SupervisionID', whereIn: supervisionIds)
            .where('UserID', isEqualTo: invitedUser.userID)
            .get();

        if (checkPartnerQuery.docs.isNotEmpty) {
          // Get the supervision IDs that involve both users
          final bothUsersSupervisionIds = checkPartnerQuery.docs.map((doc) => doc['SupervisionID'] as String).toList();
          
          // Check the status of these supervisions
          final supervisionStatusQuery = await db
              .collection('Supervision')
              .where('SupervisionID', whereIn: bothUsersSupervisionIds)
              .get();
          
          for (var supervisionDoc in supervisionStatusQuery.docs) {
            final status = supervisionDoc['Status'];
            
            if (status == 'accepted') {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('You already have an active supervision relationship with ${invitedUser.username}.')),
              );
              return;
            } else if (status == 'pending') {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('You already have a pending invitation with ${invitedUser.username}.')),
              );
              return;
            } else if (status == 'rejected') {
              // Remove the rejected supervision records to allow new invitation
              print('Removing rejected supervision records for reinvitation...');
              
              // Delete the supervision record
              await supervisionDoc.reference.delete();
              
              // Delete the supervision list records
              final supervisionListToDelete = await db
                  .collection('SupervisionList')
                  .where('SupervisionID', isEqualTo: supervisionDoc['SupervisionID'])
                  .get();
              
              WriteBatch deleteBatch = db.batch();
              for (var doc in supervisionListToDelete.docs) {
                deleteBatch.delete(doc.reference);
              }
              await deleteBatch.commit();
              
              print('Declined supervision records cleaned up. Proceeding with new invitation...');
              break; // Continue with creating new invitation
            }
          }
        }
      }
      
      // 3. Generate new SupervisionID
      final supervisionQuery = await db.collection('Supervision')
          .orderBy('SupervisionID', descending: true)
          .limit(1)
          .get();
      
      String newSupervisionId;
      if (supervisionQuery.docs.isEmpty) {
        newSupervisionId = 'S00001';
      } else {
        final lastId = supervisionQuery.docs.first['SupervisionID'] as String;
        final lastNumber = int.parse(lastId.substring(1));
        newSupervisionId = 'S${(lastNumber + 1).toString().padLeft(5, '0')}';
      }

      // 4. Create supervision record with pending status (simplified)
      await db.collection('Supervision').add({
        'SupervisionID': newSupervisionId,
        'CurrentStreakDays': 0,
        'LastLoggedDate': null,
        'Status': 'pending',
      });

      // 5. Create two entries in SupervisionList (simplified)
      WriteBatch batch = db.batch();
      
      final supervisionListRef1 = db.collection('SupervisionList').doc();
      batch.set(supervisionListRef1, {
        'SupervisionID': newSupervisionId,
        'UserID': currentUser.userID,
        'CustomMessage': null,
      });

      final supervisionListRef2 = db.collection('SupervisionList').doc();
      batch.set(supervisionListRef2, {
        'SupervisionID': newSupervisionId,
        'UserID': invitedUser.userID,
        'CustomMessage': null,
      });

      await batch.commit();

      // 使用全局通知管理器发送邀请通知
      print('=== SENDING INVITATION VIA GLOBAL MANAGER ===');
      print('From: ${currentUser.username} (${currentUser.userID})');
      print('To: ${invitedUser.username} (${invitedUser.userID})');
      print('SupervisionID: $newSupervisionId');
      
      // 发送RTDB邀请通知（可靠性最高）
      await _globalNotificationManager.sendRTDBNotification(
        receiverId: invitedUser.userID,
        type: 'invitation',
        data: {
          'title': 'Supervisor Invitation',
          'message': '${currentUser.username} invites you to become mutual supervisors',
          'inviterId': currentUser.userID,
          'inviterName': currentUser.username,
          'supervisionId': newSupervisionId,
          'timestamp': DateTime.now().toIso8601String(),
        },
      );
      
      print('=== INVITATION SENT SUCCESSFULLY ===');

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Invitation sent to ${invitedUser.username}! They will receive a notification on their homepage.')),
      );
      Navigator.of(context).pop();
    } catch (e) {
      print('Error sending invitation: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error sending invitation: $e')),
      );
    }
  }
  
  void _showBlacklistDialog(UserModel userToBlock) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.block, color: Colors.red.shade600),
              const SizedBox(width: 8),
              const Text('Block User'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Are you sure you want to block ${userToBlock.username}?'),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.warning, color: Colors.orange.shade700, size: 16),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            'What happens when you block:',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.orange.shade700,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '• They cannot send you supervision invitations\n'
                      '• You will not see them in search results\n'
                      '• Any existing supervision will be terminated',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.orange.shade700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                await _blockUser(userToBlock);
                Navigator.of(context).pop();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('Block'),
            ),
          ],
        );
      },
    );
  }
  
  Future<String> _generateBlockID() async {
    final db = FirebaseFirestore.instance;
    try {
      QuerySnapshot snapshot = await db
          .collection('Blacklist')
          .get();

      if (snapshot.docs.isEmpty) {
        return 'B00001';
      }

      // 在内存中排序，找到最大的BlockID
      final blockIds = snapshot.docs
          .map((doc) {
            final data = doc.data();
            if (data != null && data is Map<String, dynamic>) {
              return data['BlockID'] as String?;
            }
            return null;
          })
          .where((id) => id != null)
          .cast<String>()
          .toList();
      
      if (blockIds.isEmpty) {
        return 'B00001';
      }
      
      blockIds.sort((a, b) => b.compareTo(a)); // 降序
      String lastBlockID = blockIds.first;
      int lastNumber = int.parse(lastBlockID.substring(1));
      int newNumber = lastNumber + 1;
      return 'B${newNumber.toString().padLeft(5, '0')}';
    } catch (e) {
      print('Error generating block ID: $e');
      return 'B00001';
    }
  }

  Future<void> _blockUser(UserModel userToBlock) async {
    final db = FirebaseFirestore.instance;
    final currentUser = widget.currentUser;
    
    try {
      // Check if already blocked
      final existingBlockQuery = await db
          .collection('Blacklist')
          .where('UserID', isEqualTo: currentUser.userID)
          .where('BlockedUserID', isEqualTo: userToBlock.userID)
          .get();
      
      if (existingBlockQuery.docs.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${userToBlock.username} is already blocked.')),
        );
        return;
      }
      
      // Generate BlockID
      final blockId = await _generateBlockID();
      
      // Add to blacklist
      await db.collection('Blacklist').add({
        'BlockID': blockId,
        'UserID': currentUser.userID,
        'BlockedUserID': userToBlock.userID,
        'BlockedUsername': userToBlock.username,
        'BlockedEmail': userToBlock.email,
      });
      
      // Remove any existing supervision relationships
      await _terminateSupervisionRelationship(currentUser.userID, userToBlock.userID);
      
      // Remove from search results
      setState(() {
        _searchResults.removeWhere((user) => user.userID == userToBlock.userID);
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${userToBlock.username} has been blocked.'),
          backgroundColor: Colors.red,
        ),
      );
    } catch (e) {
      print('Error blocking user: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error blocking user: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
  
  Future<void> _terminateSupervisionRelationship(String userId1, String userId2) async {
    final db = FirebaseFirestore.instance;
    
    try {
      // Find all supervision IDs involving both users
      final user1SupervisionQuery = await db
          .collection('SupervisionList')
          .where('UserID', isEqualTo: userId1)
          .get();
      
      final user1SupervisionIds = user1SupervisionQuery.docs
          .map((doc) => doc['SupervisionID'] as String)
          .toList();
      
      if (user1SupervisionIds.isNotEmpty) {
        final user2SupervisionQuery = await db
            .collection('SupervisionList')
            .where('SupervisionID', whereIn: user1SupervisionIds)
            .where('UserID', isEqualTo: userId2)
            .get();
        
        final sharedSupervisionIds = user2SupervisionQuery.docs
            .map((doc) => doc['SupervisionID'] as String)
            .toList();
        
        if (sharedSupervisionIds.isNotEmpty) {
          // Delete supervision records
          for (String supervisionId in sharedSupervisionIds) {
            final supervisionQuery = await db
                .collection('Supervision')
                .where('SupervisionID', isEqualTo: supervisionId)
                .get();
            
            WriteBatch batch = db.batch();
            
            // Delete supervision record
            for (var doc in supervisionQuery.docs) {
              batch.delete(doc.reference);
            }
            
            // Delete supervision list records
            final supervisionListQuery = await db
                .collection('SupervisionList')
                .where('SupervisionID', isEqualTo: supervisionId)
                .get();
            
            for (var doc in supervisionListQuery.docs) {
              batch.delete(doc.reference);
            }
            
            await batch.commit();
          }
          
          print('Terminated supervision relationships: $sharedSupervisionIds');
        }
      }
    } catch (e) {
      print('Error terminating supervision relationship: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FFFE),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: const Color(0xFF5AA162),
        foregroundColor: Colors.white,
        title: const Text(
          'Invite Supervisor',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF5AA162),
                Color(0xFF7BB77E),
              ],
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          // Enhanced search section with gradient background
          Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFF7BB77E),
                  Color(0xFFF8FFFE),
                ],
                stops: [0.0, 0.8],
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header text
                  const Text(
                    'Find Your Supervisor',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Search by username or email to connect',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.white.withOpacity(0.9),
                    ),
                  ),
                  const SizedBox(height: 20),
                  
                  // Enhanced search field
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 20,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Enter username or email...',
                        hintStyle: TextStyle(
                          color: Colors.grey.shade500,
                          fontSize: 16,
                        ),
                        prefixIcon: Container(
                          padding: const EdgeInsets.all(12),
                          child: Icon(
                            Icons.search_rounded,
                            color: _searchController.text.isNotEmpty 
                              ? const Color(0xFF5AA162) 
                              : Colors.grey.shade400,
                            size: 24,
                          ),
                        ),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? Container(
                                margin: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: IconButton(
                                  icon: Icon(
                                    Icons.clear_rounded,
                                    color: Colors.grey.shade600,
                                    size: 20,
                                  ),
                                  onPressed: () {
                                    _searchController.clear();
                                    _searchUsers('');
                                  },
                                ),
                              )
                            : null,
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 18,
                        ),
                      ),
                      style: const TextStyle(
                        fontSize: 16,
                        color: Colors.black87,
                      ),
                      onChanged: _searchUsers,
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          // Results section
          Expanded(
            child: _buildResultsSection(),
          ),
        ],
      ),
    );
  }

  Widget _buildResultsSection() {
    if (_isLoading) {
      return _buildLoadingState();
    }
    
    if (_searchQuery.isNotEmpty && _searchResults.isEmpty) {
      return _buildEmptyState();
    }
    
    if (_searchResults.isEmpty) {
      return _buildInitialState();
    }
    
    return _buildSearchResults();
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF5AA162).withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF5AA162)),
                strokeWidth: 2.5,
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Searching...',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF5AA162),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return SingleChildScrollView(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.grey.shade200,
                    width: 2,
                  ),
                ),
                child: Icon(
                  Icons.person_search_rounded,
                  size: 36,
                  color: Colors.grey.shade400,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'No users found',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Try searching with a different username or email',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade600,
                  height: 1.2,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF5AA162).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: const Color(0xFF5AA162).withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.lightbulb_outline_rounded,
                      color: const Color(0xFF5AA162),
                      size: 16,
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        'Check spelling',
                        style: TextStyle(
                          fontSize: 11,
                          color: const Color(0xFF5AA162),
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInitialState() {
    return SingleChildScrollView(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      const Color(0xFF5AA162).withOpacity(0.1),
                      const Color(0xFF7BB77E).withOpacity(0.1),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: const Color(0xFF5AA162).withOpacity(0.3),
                    width: 2,
                  ),
                ),
                child: const Icon(
                  Icons.people_outline_rounded,
                  size: 36,
                  color: Color(0xFF5AA162),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Start Your Search',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Enter a username or email above to find supervisors',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade600,
                  height: 1.2,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchResults() {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        final user = _searchResults[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 20,
                offset: const Offset(0, 4),
              ),
            ],
            border: Border.all(
              color: Colors.grey.shade100,
              width: 1,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16), // Reduced from 20
            child: Row(
              children: [
                // Smaller avatar
                Container(
                  width: 48, // Reduced from 60
                  height: 48, // Reduced from 60
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0xFF5AA162),
                        Color(0xFF7BB77E),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(14), // Reduced from 18
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF5AA162).withOpacity(0.3),
                        blurRadius: 8, // Reduced from 12
                        offset: const Offset(0, 2), // Reduced from 4
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(2), // Reduced from 3
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12), // Reduced from 15
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12), // Reduced from 15
                        child: Image.asset(
                          user.gender.toLowerCase() == 'male' 
                              ? 'assets/Male.png' 
                              : 'assets/Female.png',
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ),
                ),
                
                const SizedBox(width: 12), // Reduced from 16
                
                // User info - more flexible
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min, // Added to prevent overflow
                    children: [
                      Text(
                        user.username,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16, // Reduced from 18
                          color: Colors.black87,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6, // Reduced from 8
                          vertical: 2, // Reduced from 4
                        ),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(6), // Reduced from 8
                        ),
                        child: Text(
                          user.email,
                          style: TextStyle(
                            fontSize: 12, // Reduced from 14
                            color: Colors.grey.shade600,
                          ),
                          maxLines: 2, // Allow 2 lines for email
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(width: 8), // Reduced from 12
                
                // Action buttons
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Blacklist button
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => _showBlacklistDialog(user),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            child: Icon(
                              Icons.block,
                              color: Colors.grey.shade600,
                              size: 16,
                            ),
                          ),
                        ),
                      ),
                    ),
                    
                    const SizedBox(width: 8),
                    
                    // Invite button
                    Container(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Color(0xFF5AA162),
                            Color(0xFF7BB77E),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(12), // Reduced from 14
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF5AA162).withOpacity(0.3), // Reduced opacity
                            blurRadius: 8, // Reduced from 12
                            offset: const Offset(0, 2), // Reduced from 4
                          ),
                        ],
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => _sendInvitation(user),
                          borderRadius: BorderRadius.circular(12), // Reduced from 14
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16, // Reduced from 20
                              vertical: 10, // Reduced from 12
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.person_add_rounded,
                                  color: Colors.white,
                                  size: 16, // Reduced from 18
                                ),
                                const SizedBox(width: 4), // Reduced from 6
                                const Text(
                                  'Invite',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14, // Reduced from 16
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
              ],
            ),
          ),
        );
      },
    );
  }
}




