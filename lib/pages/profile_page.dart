import 'package:app_minimal/post/user_posts_feed_page.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// Public interface so HomePage can call reload() via GlobalKey
/// without needing access to the private _ProfilePageState class.
mixin ProfilePageReloadMixin on State<ProfilePage> {
  Future<void> reload();
}

class ProfilePage extends StatefulWidget {
  final void Function(int index, dynamic posts) onPostTap;
  final void Function(String username)? onUsernameChanged;

  const ProfilePage({
    super.key,
    required this.onPostTap,
    this.onUsernameChanged,
  });

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> with ProfilePageReloadMixin {
  String username = '';
  String profileImage = '';
  String bio = '';

  @override
  Future<void> reload() => loadUserData();

  @override
  void initState() {
    super.initState();
    loadUserData();
  }

  Future<void> loadUserData() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();

    if (mounted) {
      final newUsername = doc.data()?['username'] ?? 'Profile';
      setState(() {
        username = newUsername;
        profileImage = doc.data()?['profileImage'] ?? '';
        bio = doc.data()?['bio'] ?? '';
      });
      widget.onUsernameChanged?.call(newUsername);
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const SizedBox.shrink();

    return Scaffold(
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('posts')
            .where('uid', isEqualTo: uid)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data?.docs ?? [];

          final posts = docs.map((doc) {
            return {'id': doc.id, ...doc.data() as Map<String, dynamic>};
          }).toList();

          // Sort client-side — no composite index required
          posts.sort((a, b) {
            final aTime = a['createdAt'] as Timestamp?;
            final bTime = b['createdAt'] as Timestamp?;
            if (aTime == null || bTime == null) return 0;
            return bTime.compareTo(aTime);
          });

          final imagePosts = posts.where((p) => p['isVideo'] == false).toList();
          final videoPosts = posts.where((p) => p['isVideo'] == true).toList();

          return DefaultTabController(
            length: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 24),

                // ── Profile picture ────────────────────────────────
                CircleAvatar(
                  radius: 52,
                  backgroundImage: profileImage.isNotEmpty
                      ? NetworkImage(profileImage)
                      : null,
                  child: profileImage.isEmpty
                      ? const Icon(Icons.person, size: 52)
                      : null,
                ),

                const SizedBox(height: 12),

                // ── Username ───────────────────────────────────────
                Text(
                  username,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),

                // ── Bio ────────────────────────────────────────────
                if (bio.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 6,
                    ),
                    child: Text(
                      bio,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),

                const SizedBox(height: 12),

                // ── Posts count ────────────────────────────────────
                Column(
                  children: [
                    Text(
                      '${posts.length}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text('Posts', style: TextStyle(fontSize: 13)),
                  ],
                ),

                const SizedBox(height: 16),

                // ── Tab bar ────────────────────────────────────────
                const TabBar(
                  tabs: [
                    Tab(icon: Icon(Icons.grid_on)),
                    Tab(icon: Icon(Icons.image)),
                    Tab(icon: Icon(Icons.video_collection)),
                  ],
                ),

                Expanded(
                  child: TabBarView(
                    children: [
                      _buildGrid(context, posts, posts, showVideoIcon: true),
                      _buildGrid(context, imagePosts, imagePosts),
                      _buildGrid(
                        context,
                        videoPosts,
                        videoPosts,
                        showVideoIcon: true,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildGrid(
    BuildContext context,
    List<Map<String, dynamic>> items,
    List<Map<String, dynamic>> allPostsInTab, {
    bool showVideoIcon = false,
  }) {
    if (items.isEmpty) {
      return const Center(child: Text('No posts yet'));
    }

    return GridView.builder(
      padding: const EdgeInsets.all(2),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 2,
        mainAxisSpacing: 2,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final post = items[index];
        final isVideo = post['isVideo'] ?? false;
        final url = isVideo
            ? post['thumbnailUrl'] ?? ''
            : post['imageUrl'] ?? '';

        return GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => UserPostsFeedPage(
                  uid: FirebaseAuth.instance.currentUser!.uid,
                  initialIndex: index,
                  posts: allPostsInTab,
                ),
              ),
            );
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              url.isNotEmpty
                  ? Image.network(url, fit: BoxFit.cover)
                  : Container(color: Colors.grey),
              if (showVideoIcon && isVideo)
                const Positioned(
                  top: 6,
                  right: 6,
                  child: Icon(Icons.play_circle_fill, color: Colors.white),
                ),
            ],
          ),
        );
      },
    );
  }
}
