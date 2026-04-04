import 'package:app_minimal/post/post.dart';
import 'package:app_minimal/post/user_posts_feed_page.dart';
import 'package:app_minimal/pages/upload_page.dart';
import 'package:app_minimal/pages/profile_page.dart';
import 'package:app_minimal/pages/notifications_page.dart';
import 'package:app_minimal/pages/edit_profile_page.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int currentIndex = 0;
  int _uploadKey = 0;
  String _currentUsername = '';
  String _currentBio = '';
  String _currentProfileImage = '';

  final GlobalKey<NavigatorState> _homeNavKey = GlobalKey<NavigatorState>();
  final GlobalKey<NavigatorState> _uploadNavKey = GlobalKey<NavigatorState>();

  // Type-safe key using the public mixin — no access to private state needed
  final GlobalKey<ProfilePageReloadMixin> _profileKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _fetchUserData();
  }

  Future<void> _fetchUserData() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();

    if (mounted) {
      setState(() {
        _currentUsername = doc.data()?['username'] ?? 'Profile';
        _currentBio = doc.data()?['bio'] ?? '';
        _currentProfileImage = doc.data()?['profileImage'] ?? '';
      });
    }
  }

  bool _handlePop() {
    if (currentIndex == 0 && (_homeNavKey.currentState?.canPop() ?? false)) {
      _homeNavKey.currentState!.pop();
      return false;
    }
    if (currentIndex == 1 && (_uploadNavKey.currentState?.canPop() ?? false)) {
      _uploadNavKey.currentState!.pop();
      return false;
    }
    return true;
  }

  String get _appBarTitle {
    if (currentIndex == 0) return 'Instagram';
    if (currentIndex == 2) return _currentUsername;
    return '';
  }

  void _showSettingsSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit Profile'),
              onTap: () async {
                Navigator.pop(context);
                final updated = await Navigator.push<bool>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => EditProfilePage(
                      currentUsername: _currentUsername,
                      currentBio: _currentBio,
                      currentProfileImage: _currentProfileImage,
                    ),
                  ),
                );
                if (updated == true) {
                  await _fetchUserData();
                  // Tells ProfilePage to re-fetch its own bio + profile image
                  _profileKey.currentState?.reload();
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text('Logout', style: TextStyle(color: Colors.red)),
              onTap: () async {
                Navigator.pop(context);
                await FirebaseAuth.instance.signOut();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<bool> _userExists(String uid) async {
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();
    if (!doc.exists) {
      final userPosts = await FirebaseFirestore.instance
          .collection('posts')
          .where('uid', isEqualTo: uid)
          .get();
      final batch = FirebaseFirestore.instance.batch();
      for (final post in userPosts.docs) {
        batch.delete(post.reference);
      }
      final allPosts = await FirebaseFirestore.instance
          .collection('posts')
          .get();
      for (final post in allPosts.docs) {
        final likes = List<dynamic>.from(post.data()['likes'] ?? []);
        if (likes.contains(uid)) {
          batch.update(post.reference, {
            'likes': FieldValue.arrayRemove([uid]),
          });
        }
      }
      await batch.commit();
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (didPop) return;
        _handlePop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_appBarTitle),
          actions: [
            if (currentIndex == 2)
              IconButton(
                icon: const Icon(Icons.settings_outlined),
                onPressed: _showSettingsSheet,
              )
            else
              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('notifications')
                    .where('toUid', isEqualTo: currentUid)
                    .where('isRead', isEqualTo: false)
                    .snapshots(),
                builder: (context, snapshot) {
                  final hasUnread =
                      snapshot.hasData && snapshot.data!.docs.isNotEmpty;
                  return Stack(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.notifications_outlined),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const NotificationsPage(),
                            ),
                          );
                        },
                      ),
                      if (hasUnread)
                        Positioned(
                          right: 8,
                          top: 8,
                          child: Container(
                            width: 9,
                            height: 9,
                            decoration: const BoxDecoration(
                              color: Colors.red,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
          ],
        ),

        body: IndexedStack(
          index: currentIndex,
          children: [
            // TAB 1 — HOME FEED
            Navigator(
              key: _homeNavKey,
              onGenerateRoute: (_) => MaterialPageRoute(
                builder: (_) => StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('posts')
                      .orderBy('createdAt', descending: true)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return const Center(child: Text('Something went wrong'));
                    }
                    final posts = snapshot.data!.docs;
                    if (posts.isEmpty) {
                      return const Center(child: Text('No posts yet'));
                    }
                    return FutureBuilder<List<QueryDocumentSnapshot>>(
                      future:
                          Future.wait(
                            posts.map((post) async {
                              final uid = post['uid'] ?? '';
                              final exists = await _userExists(uid);
                              return exists ? post : null;
                            }),
                          ).then(
                            (list) => list
                                .whereType<QueryDocumentSnapshot>()
                                .toList(),
                          ),
                      builder: (context, filteredSnapshot) {
                        if (!filteredSnapshot.hasData) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        final filteredPosts = filteredSnapshot.data!;
                        if (filteredPosts.isEmpty) {
                          return const Center(child: Text('No posts yet'));
                        }
                        return ListView.builder(
                          itemCount: filteredPosts.length,
                          itemBuilder: (context, index) {
                            final post = filteredPosts[index];
                            return Post(
                              postId: post.id,
                              username: post['username'] ?? '',
                              profileImage: post['profileImage'] ?? '',
                              imageUrl: post['imageUrl'] ?? '',
                              caption: post['caption'] ?? '',
                              isVideo: post['isVideo'] ?? false,
                              likes: post['likes'] ?? [],
                              uid: post['uid'] ?? '',
                            );
                          },
                        );
                      },
                    );
                  },
                ),
              ),
            ),

            // TAB 2 — UPLOAD
            Navigator(
              key: _uploadNavKey,
              onGenerateRoute: (_) => MaterialPageRoute(
                builder: (_) => UploadPage(
                  key: ValueKey(_uploadKey),
                  onUploadSuccess: () => setState(() => currentIndex = 0),
                ),
              ),
            ),

            // TAB 3 — PROFILE
            ProfilePage(
              key: _profileKey,
              onUsernameChanged: (newUsername) {
                setState(() => _currentUsername = newUsername);
              },
              onPostTap: (index, posts) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => UserPostsFeedPage(
                      posts: posts,
                      initialIndex: index,
                      uid: FirebaseAuth.instance.currentUser!.uid,
                    ),
                  ),
                );
              },
            ),
          ],
        ),

        bottomNavigationBar: BottomNavigationBar(
          currentIndex: currentIndex,
          onTap: (index) {
            if (index == 0 && currentIndex == 0) {
              _homeNavKey.currentState!.popUntil((route) => route.isFirst);
            }
            if (index == 1 && currentIndex == 1) {
              _uploadNavKey.currentState!.popUntil((route) => route.isFirst);
            }
            if (currentIndex == 1 && index != 1) {
              setState(() => _uploadKey++);
            }
            setState(() => currentIndex = index);
          },
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.home), label: ''),
            BottomNavigationBarItem(
              icon: Icon(Icons.add_box_outlined),
              label: '',
            ),
            BottomNavigationBarItem(icon: Icon(Icons.person), label: ''),
          ],
        ),
      ),
    );
  }
}
