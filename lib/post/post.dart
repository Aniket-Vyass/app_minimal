import 'package:app_minimal/pages/other_users_profile_page.dart';
import 'package:app_minimal/post/comment_sheet.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:visibility_detector/visibility_detector.dart';

class Post extends StatefulWidget {
  final String postId;
  final String uid;
  final String username;
  final String profileImage;
  final String imageUrl;
  final String caption;
  final bool isVideo;
  final List<dynamic> likes;

  const Post({
    super.key,
    required this.postId,
    required this.uid,
    required this.username,
    required this.profileImage,
    required this.imageUrl,
    required this.caption,
    this.isVideo = false,
    this.likes = const [],
  });

  @override
  State<Post> createState() => _PostState();
}

class _PostState extends State<Post> {
  VideoPlayerController? _videoController;
  bool _videoInitialized = false;
  bool _videoError = false;
  bool _isMuted = false;

  String _liveProfileImage = '';
  String _liveUsername = '';
  String _liveCaption = '';
  List<dynamic> _filteredLikes = [];

  String get _currentUid => FirebaseAuth.instance.currentUser?.uid ?? '';
  bool get _isLiked => _filteredLikes.contains(_currentUid);
  bool get _isOwner => _currentUid == widget.uid;

  @override
  void initState() {
    super.initState();
    _liveProfileImage = widget.profileImage;
    _liveUsername = widget.username;
    _liveCaption = widget.caption;
    _filteredLikes = List.from(widget.likes);
    _fetchLiveProfile();
    _filterDeletedLikes();

    if (widget.isVideo && widget.imageUrl.isNotEmpty) {
      _initVideo();
    }
  }

  Future<void> _initVideo() async {
    try {
      _videoController = VideoPlayerController.networkUrl(
        Uri.parse(widget.imageUrl),
      );
      await _videoController!.initialize().timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw Exception('Video load timed out'),
      );
      if (mounted) {
        setState(() => _videoInitialized = true);
        _videoController!.setLooping(true);
        _videoController!.setVolume(1);
      }
    } catch (e) {
      if (mounted) setState(() => _videoError = true);
      _videoController?.dispose();
      _videoController = null;
    }
  }

  Future<void> _fetchLiveProfile() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.uid)
          .get();
      if (mounted && doc.exists) {
        setState(() {
          _liveProfileImage = doc.data()?['profileImage'] ?? '';
          _liveUsername = doc.data()?['username'] ?? widget.username;
        });
      }
    } catch (_) {}
  }

  Future<void> _filterDeletedLikes() async {
    final likes = List<dynamic>.from(widget.likes);
    final List<dynamic> toRemove = [];
    for (final uid in likes) {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      if (!doc.exists) toRemove.add(uid);
    }
    if (toRemove.isNotEmpty) {
      await FirebaseFirestore.instance
          .collection('posts')
          .doc(widget.postId)
          .update({'likes': FieldValue.arrayRemove(toRemove)});
      if (mounted) {
        setState(() {
          _filteredLikes.removeWhere((uid) => toRemove.contains(uid));
        });
      }
    }
  }

  void _openUserProfile() {
    if (_isOwner) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => OtherUserProfilePage(uid: widget.uid)),
    );
  }

  void _openComments() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) =>
          CommentsSheet(postId: widget.postId, postOwnerUid: widget.uid),
    );
  }

  void _toggleMute() {
    setState(() {
      _isMuted = !_isMuted;
      _videoController?.setVolume(_isMuted ? 0 : 1);
    });
  }

  void _showPostOptions() {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit caption'),
              onTap: () {
                Navigator.pop(context);
                _editCaption();
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text(
                'Delete post',
                style: TextStyle(color: Colors.red),
              ),
              onTap: () {
                Navigator.pop(context);
                _deletePost();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editCaption() async {
    final controller = TextEditingController(text: _liveCaption);
    final newCaption = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Edit caption'),
        content: TextField(
          controller: controller,
          maxLines: 4,
          decoration: const InputDecoration(hintText: 'Write a caption...'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (newCaption == null || newCaption == _liveCaption) return;

    await FirebaseFirestore.instance
        .collection('posts')
        .doc(widget.postId)
        .update({'caption': newCaption});

    if (mounted) setState(() => _liveCaption = newCaption);
  }

  Future<void> _deletePost() async {
    final confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete post?'),
        content: const Text('This will permanently delete your post.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await FirebaseFirestore.instance
          .collection('posts')
          .doc(widget.postId)
          .delete();

      if (widget.imageUrl.isNotEmpty) {
        try {
          await FirebaseStorage.instance.refFromURL(widget.imageUrl).delete();
        } catch (_) {}
      }

      final notifSnapshot = await FirebaseFirestore.instance
          .collection('notifications')
          .where('postId', isEqualTo: widget.postId)
          .get();
      final batch = FirebaseFirestore.instance.batch();
      for (final doc in notifSnapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Delete failed: $e')));
      }
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 20, horizontal: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // HEADER
          ListTile(
            leading: GestureDetector(
              onTap: _openUserProfile,
              child: CircleAvatar(
                backgroundImage: _liveProfileImage.isNotEmpty
                    ? NetworkImage(_liveProfileImage)
                    : null,
                child: _liveProfileImage.isEmpty
                    ? const Icon(Icons.person)
                    : null,
              ),
            ),
            title: GestureDetector(
              onTap: _openUserProfile,
              child: Text(
                _liveUsername,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            trailing: _isOwner
                ? IconButton(
                    icon: const Icon(Icons.more_vert),
                    onPressed: _showPostOptions,
                  )
                : null,
          ),

          // MEDIA
          widget.isVideo ? _buildVideo() : _buildImage(),

          const SizedBox(height: 4),

          // ACTIONS ROW
          Row(
            children: [
              IconButton(
                icon: Icon(
                  _isLiked ? Icons.favorite : Icons.favorite_border,
                  color: _isLiked ? Colors.red : null,
                ),
                onPressed: () async {
                  final ref = FirebaseFirestore.instance
                      .collection('posts')
                      .doc(widget.postId);
                  if (_isLiked) {
                    await ref.update({
                      'likes': FieldValue.arrayRemove([_currentUid]),
                    });
                    if (mounted) {
                      setState(() => _filteredLikes.remove(_currentUid));
                    }
                  } else {
                    await ref.update({
                      'likes': FieldValue.arrayUnion([_currentUid]),
                    });
                    if (mounted) {
                      setState(() => _filteredLikes.add(_currentUid));
                    }
                    if (_currentUid != widget.uid) {
                      final userDoc = await FirebaseFirestore.instance
                          .collection('users')
                          .doc(_currentUid)
                          .get();
                      final fromUsername =
                          userDoc.data()?['username'] ?? 'Someone';
                      await FirebaseFirestore.instance
                          .collection('notifications')
                          .add({
                            'toUid': widget.uid,
                            'fromUid': _currentUid,
                            'fromUsername': fromUsername,
                            'type': 'like',
                            'postId': widget.postId,
                            'isRead': false,
                            'createdAt': FieldValue.serverTimestamp(),
                          });
                    }
                  }
                },
              ),

              if (_filteredLikes.isNotEmpty)
                GestureDetector(
                  onTap: () {
                    final likes = _filteredLikes;
                    showModalBottomSheet(
                      context: context,
                      builder: (_) => FutureBuilder<QuerySnapshot>(
                        future: FirebaseFirestore.instance
                            .collection('users')
                            .where(
                              FieldPath.documentId,
                              whereIn: likes.length > 10
                                  ? likes.sublist(0, 10)
                                  : likes,
                            )
                            .get(),
                        builder: (context, snapshot) {
                          if (!snapshot.hasData) {
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          }
                          final users = snapshot.data!.docs;
                          if (users.isEmpty) {
                            return const Center(child: Text("No likes yet"));
                          }
                          return ListView.builder(
                            itemCount: users.length,
                            itemBuilder: (context, index) {
                              final user =
                                  users[index].data() as Map<String, dynamic>;
                              final pic = user['profileImage'] ?? '';
                              final likerUid = users[index].id;
                              return ListTile(
                                onTap: () {
                                  Navigator.pop(context);
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          OtherUserProfilePage(uid: likerUid),
                                    ),
                                  );
                                },
                                title: Row(
                                  children: [
                                    CircleAvatar(
                                      backgroundImage: pic.isNotEmpty
                                          ? NetworkImage(pic)
                                          : null,
                                      child: pic.isEmpty
                                          ? const Icon(Icons.person)
                                          : null,
                                    ),
                                    const SizedBox(width: 10),
                                    Text(user['username'] ?? 'user'),
                                    const Spacer(),
                                    const Icon(
                                      Icons.favorite,
                                      color: Colors.red,
                                      size: 20,
                                    ),
                                  ],
                                ),
                              );
                            },
                          );
                        },
                      ),
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Text(
                      '${_filteredLikes.length}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),

              IconButton(
                onPressed: _openComments,
                icon: const Icon(Icons.comment_outlined),
              ),

              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('posts')
                    .doc(widget.postId)
                    .collection('comments')
                    .snapshots(),
                builder: (context, snapshot) {
                  final count = snapshot.data?.docs.length ?? 0;
                  if (count == 0) return const SizedBox.shrink();
                  return GestureDetector(
                    onTap: _openComments,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Text(
                        '$count',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),

          if (_liveCaption.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: RichText(
                text: TextSpan(
                  style: DefaultTextStyle.of(context).style,
                  children: [
                    TextSpan(
                      text: '$_liveUsername  ',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    TextSpan(text: _liveCaption),
                  ],
                ),
              ),
            ),

          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('posts')
                .doc(widget.postId)
                .collection('comments')
                .orderBy('createdAt', descending: true)
                .limit(1)
                .snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return const SizedBox.shrink();
              }
              final latest =
                  snapshot.data!.docs.first.data() as Map<String, dynamic>;
              final commentUsername = latest['username'] ?? 'user';
              final commentText = latest['text'] ?? '';

              return GestureDetector(
                onTap: _openComments,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Comments',
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                      const SizedBox(height: 2),
                      StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance
                            .collection('posts')
                            .doc(widget.postId)
                            .collection('comments')
                            .snapshots(),
                        builder: (context, countSnapshot) {
                          final count = countSnapshot.data?.docs.length ?? 0;
                          if (count <= 1) return const SizedBox.shrink();
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                              'View all $count comments',
                              style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 13,
                              ),
                            ),
                          );
                        },
                      ),
                      RichText(
                        text: TextSpan(
                          style: DefaultTextStyle.of(context).style,
                          children: [
                            TextSpan(
                              text: '$commentUsername  ',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            TextSpan(text: commentText),
                          ],
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),

          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _buildImage() {
    if (widget.imageUrl.isEmpty) {
      return const SizedBox(
        height: 400,
        child: Center(child: Icon(Icons.broken_image, size: 60)),
      );
    }
    return Image.network(
      widget.imageUrl,
      width: double.infinity,
      height: 400,
      fit: BoxFit.cover,
    );
  }

  Widget _buildVideo() {
    if (_videoError) {
      return const SizedBox(
        height: 400,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.broken_image, size: 60, color: Colors.grey),
              SizedBox(height: 8),
              Text(
                'Could not load video',
                style: TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    if (!_videoInitialized || _videoController == null) {
      return const SizedBox(
        height: 400,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return VisibilityDetector(
      key: Key('video-${widget.postId}'),
      onVisibilityChanged: (info) {
        if (!mounted || _videoController == null) return;
        if (info.visibleFraction > 0.5) {
          _videoController!.play();
        } else {
          _videoController!.pause();
        }
      },
      child: GestureDetector(
        onTap: () {
          setState(() {
            _videoController!.value.isPlaying
                ? _videoController!.pause()
                : _videoController!.play();
          });
        },
        child: Stack(
          alignment: Alignment.center,
          children: [
            AspectRatio(
              aspectRatio: _videoController!.value.aspectRatio,
              child: VideoPlayer(_videoController!),
            ),
            Positioned(
              bottom: 10,
              right: 10,
              child: GestureDetector(
                onTap: _toggleMute,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: const BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _isMuted ? Icons.volume_off : Icons.volume_up,
                    color: Colors.white,
                    size: 18,
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
