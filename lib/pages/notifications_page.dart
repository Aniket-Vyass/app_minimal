import 'package:app_minimal/post/post.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  List<QueryDocumentSnapshot> _validDocs = [];
  bool _isFiltering = false;

  String _timeAgo(Timestamp? timestamp) {
    if (timestamp == null) return '';
    final diff = DateTime.now().difference(timestamp.toDate());
    if (diff.inSeconds < 60) return '${diff.inSeconds}s';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return '${(diff.inDays / 7).floor()}w';
  }

  Future<void> _filterAndUpdate(List<QueryDocumentSnapshot> docs) async {
    if (_isFiltering) return;
    _isFiltering = true;

    final validDocs = <QueryDocumentSnapshot>[];
    for (final doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      final postId = data['postId'] ?? '';
      final toUid = data['toUid'] ?? '';
      final fromUid = data['fromUid'] ?? '';

      if (toUid == fromUid) {
        await doc.reference.delete();
        continue;
      }

      if (postId.isEmpty) {
        await doc.reference.delete();
        continue;
      }

      final postDoc = await FirebaseFirestore.instance
          .collection('posts')
          .doc(postId)
          .get();

      if (!postDoc.exists) {
        await doc.reference.delete();
        continue;
      }

      validDocs.add(doc);
    }

    validDocs.sort((a, b) {
      final aTime =
          (a.data() as Map<String, dynamic>)['createdAt'] as Timestamp?;
      final bTime =
          (b.data() as Map<String, dynamic>)['createdAt'] as Timestamp?;
      if (aTime == null || bTime == null) return 0;
      return bTime.compareTo(aTime);
    });

    if (mounted) {
      setState(() {
        _validDocs = validDocs;
        _isFiltering = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(body: Center(child: Text("User not logged in")));
    }

    return Scaffold(
      appBar: AppBar(title: const Text("Notifications")),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('notifications')
            .where('toUid', isEqualTo: user.uid)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              _validDocs.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text(snapshot.error.toString()));
          }

          final docs = snapshot.data?.docs ?? [];

          // Re-filter every time stream emits
          _filterAndUpdate(docs);

          if (_validDocs.isEmpty) {
            return const Center(child: Text("No notifications yet"));
          }

          return ListView.builder(
            itemCount: _validDocs.length,
            itemBuilder: (context, index) {
              final doc = _validDocs[index];
              final data = doc.data() as Map<String, dynamic>;
              final isRead = data['isRead'] ?? false;
              final type = data['type'] ?? 'like';
              final fromUsername = data['fromUsername'] ?? 'Someone';
              final fromUid = data['fromUid'] ?? '';
              final postId = data['postId'] ?? '';
              final createdAt = data['createdAt'] as Timestamp?;

              return FutureBuilder<DocumentSnapshot>(
                future: FirebaseFirestore.instance
                    .collection('users')
                    .doc(fromUid)
                    .get(),
                builder: (context, userSnapshot) {
                  final senderPic =
                      userSnapshot.hasData && userSnapshot.data!.exists
                      ? (userSnapshot.data!.data()
                                as Map<String, dynamic>)['profileImage'] ??
                            ''
                      : '';

                  return InkWell(
                    onTap: () async {
                      await doc.reference.update({'isRead': true});

                      if (postId.isEmpty) {
                        await doc.reference.delete();
                        return;
                      }

                      final postDoc = await FirebaseFirestore.instance
                          .collection('posts')
                          .doc(postId)
                          .get();

                      if (!postDoc.exists) {
                        await doc.reference.delete();
                        return;
                      }

                      final postData = postDoc.data()!;
                      if (context.mounted) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => Scaffold(
                              appBar: AppBar(title: const Text('Post')),
                              body: SingleChildScrollView(
                                child: Post(
                                  postId: postDoc.id,
                                  uid: postData['uid'] ?? '',
                                  username: postData['username'] ?? '',
                                  profileImage: postData['profileImage'] ?? '',
                                  imageUrl: postData['imageUrl'] ?? '',
                                  caption: postData['caption'] ?? '',
                                  isVideo: postData['isVideo'] ?? false,
                                  likes: postData['likes'] ?? [],
                                ),
                              ),
                            ),
                          ),
                        );
                      }
                    },
                    child: Container(
                      color: isRead
                          ? Colors.transparent
                          : Theme.of(
                              context,
                            ).colorScheme.primary.withOpacity(0.08),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 24,
                            backgroundImage: senderPic.isNotEmpty
                                ? NetworkImage(senderPic)
                                : null,
                            child: senderPic.isEmpty
                                ? const Icon(Icons.person)
                                : null,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                RichText(
                                  text: TextSpan(
                                    style: DefaultTextStyle.of(context).style,
                                    children: [
                                      TextSpan(
                                        text: '$fromUsername ',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      TextSpan(
                                        text: type == 'like'
                                            ? 'liked your post.'
                                            : 'commented on your post.',
                                      ),
                                    ],
                                  ),
                                ),
                                if (createdAt != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      _timeAgo(createdAt),
                                      style: const TextStyle(
                                        color: Colors.grey,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(
                            type == 'like' ? Icons.favorite : Icons.comment,
                            color: type == 'like' ? Colors.red : Colors.blue,
                            size: 20,
                          ),
                          if (!isRead)
                            Container(
                              margin: const EdgeInsets.only(left: 8),
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: Colors.blue,
                                shape: BoxShape.circle,
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
