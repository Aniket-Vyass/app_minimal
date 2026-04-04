import 'package:app_minimal/post/post.dart';
import 'package:flutter/material.dart';

class UserPostsFeedPage extends StatelessWidget {
  final String uid;
  final int initialIndex;
  final List<Map<String, dynamic>> posts;

  const UserPostsFeedPage({
    super.key,
    required this.uid,
    required this.initialIndex,
    required this.posts,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Posts')),
      body: PageView.builder(
        scrollDirection: Axis.vertical,
        controller: PageController(initialPage: initialIndex),
        itemCount: posts.length,
        itemBuilder: (context, index) {
          final data = posts[index];

          return SingleChildScrollView(
            child: Post(
              postId: data['id'] ?? '',
              uid: data['uid'] ?? '',
              username: data['username'] ?? '',
              profileImage: data['profileImage'] ?? '',
              imageUrl: data['imageUrl'] ?? '',
              caption: data['caption'] ?? '',
              isVideo: data['isVideo'] ?? false,
              likes: data['likes'] ?? [],
            ),
          );
        },
      ),
    );
  }
}
