import 'package:app_minimal/post/post.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class OtherUserProfilePage extends StatefulWidget {
  final String uid;

  const OtherUserProfilePage({super.key, required this.uid});

  @override
  State<OtherUserProfilePage> createState() => _OtherUserProfilePageState();
}

class _OtherUserProfilePageState extends State<OtherUserProfilePage> {
  String username = '';
  String profileImage = '';
  String bio = '';

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(widget.uid)
        .get();
    if (mounted && doc.exists) {
      setState(() {
        username = doc.data()?['username'] ?? '';
        profileImage = doc.data()?['profileImage'] ?? '';
        bio = doc.data()?['bio'] ?? '';
      });
    }
  }

  void _openPostFeed(
    BuildContext context,
    List<Map<String, dynamic>> posts,
    int startIndex,
  ) {
    final controller = ScrollController(
      initialScrollOffset: startIndex * 600.0, // approximate post height
    );

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text(username)),
          body: ListView.builder(
            controller: controller,
            itemCount: posts.length,
            itemBuilder: (context, index) {
              final post = posts[index];
              final postId = post['id'] as String;
              return Post(
                postId: postId,
                uid: post['uid'] ?? '',
                username: post['username'] ?? '',
                profileImage: post['profileImage'] ?? '',
                imageUrl: post['imageUrl'] ?? '',
                caption: post['caption'] ?? '',
                isVideo: post['isVideo'] ?? false,
                likes: post['likes'] ?? [],
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(username.isEmpty ? 'Profile' : username)),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('posts')
            .where('uid', isEqualTo: widget.uid)
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

          posts.sort((a, b) {
            final aTime = a['createdAt'] as Timestamp?;
            final bTime = b['createdAt'] as Timestamp?;
            if (aTime == null || bTime == null) return 0;
            return bTime.compareTo(aTime);
          });

          final postCount = posts.length.toString();
          final imagePosts = posts.where((p) => p['isVideo'] == false).toList();
          final videoPosts = posts.where((p) => p['isVideo'] == true).toList();

          return DefaultTabController(
            length: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Avatar + stats ───────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      CircleAvatar(
                        radius: 45,
                        backgroundImage: profileImage.isNotEmpty
                            ? NetworkImage(profileImage)
                            : null,
                        child: profileImage.isEmpty
                            ? const Icon(Icons.person, size: 45)
                            : null,
                      ),
                      const SizedBox(width: 24),
                      Expanded(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _statColumn('Posts', postCount),
                            _statColumn('Followers', '0'),
                            _statColumn('Following', '0'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // ── Username ─────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    username,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),

                // ── Bio ──────────────────────────────────────────
                if (bio.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    child: Text(bio, style: const TextStyle(fontSize: 14)),
                  ),

                const SizedBox(height: 12),

                // ── Tab bar ──────────────────────────────────────
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

  Widget _statColumn(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 13)),
      ],
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
          onTap: () => _openPostFeed(context, allPostsInTab, index),
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
