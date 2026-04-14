import 'package:app_minimal/pages/other_users_profile_page.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class CommentsSheet extends StatefulWidget {
  final String postId;
  final String postOwnerUid;

  const CommentsSheet({
    super.key,
    required this.postId,
    required this.postOwnerUid,
  });

  @override
  State<CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<CommentsSheet> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();

  bool _isPosting = false;
  String? _replyingToCommentId;
  String? _replyingToUsername;
  final Set<String> _expandedReplies = {};

  String get _currentUid => FirebaseAuth.instance.currentUser?.uid ?? '';
  bool get _isPostOwner => _currentUid == widget.postOwnerUid;

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _openProfile(String uid) {
    if (uid == _currentUid) return; // don't open own profile
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => OtherUserProfilePage(uid: uid)),
    );
  }

  void _startReply(String commentId, String username) {
    setState(() {
      _replyingToCommentId = commentId;
      _replyingToUsername = username;
      _controller.text = '@$username ';
      _controller.selection = TextSelection.fromPosition(
        TextPosition(offset: _controller.text.length),
      );
    });
    _focusNode.requestFocus();
  }

  void _cancelReply() {
    setState(() {
      _replyingToCommentId = null;
      _replyingToUsername = null;
      _controller.clear();
    });
    _focusNode.unfocus();
  }

  Future<void> _postComment() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    setState(() => _isPosting = true);

    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUid)
          .get();
      final username = userDoc.data()?['username'] ?? 'user';
      final profileImage = userDoc.data()?['profileImage'] ?? '';

      if (_replyingToCommentId != null) {
        await FirebaseFirestore.instance
            .collection('posts')
            .doc(widget.postId)
            .collection('comments')
            .doc(_replyingToCommentId)
            .collection('replies')
            .add({
              'uid': _currentUid,
              'username': username,
              'profileImage': profileImage,
              'text': text,
              'likes': [],
              'createdAt': FieldValue.serverTimestamp(),
            });
        setState(() => _expandedReplies.add(_replyingToCommentId!));
      } else {
        await FirebaseFirestore.instance
            .collection('posts')
            .doc(widget.postId)
            .collection('comments')
            .add({
              'uid': _currentUid,
              'username': username,
              'profileImage': profileImage,
              'text': text,
              'likes': [],
              'createdAt': FieldValue.serverTimestamp(),
            });

        if (_currentUid != widget.postOwnerUid) {
          await FirebaseFirestore.instance.collection('notifications').add({
            'toUid': widget.postOwnerUid,
            'fromUid': _currentUid,
            'fromUsername': username,
            'type': 'comment',
            'postId': widget.postId,
            'text': '$username commented: $text',
            'isRead': false,
            'createdAt': FieldValue.serverTimestamp(),
          });
        }
      }

      _controller.clear();
      setState(() {
        _replyingToCommentId = null;
        _replyingToUsername = null;
      });

      await Future.delayed(const Duration(milliseconds: 300));
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to post: $e')));
      }
    } finally {
      if (mounted) setState(() => _isPosting = false);
    }
  }

  Future<void> _toggleCommentLike(
    String commentId,
    List<dynamic> currentLikes,
  ) async {
    final ref = FirebaseFirestore.instance
        .collection('posts')
        .doc(widget.postId)
        .collection('comments')
        .doc(commentId);
    if (currentLikes.contains(_currentUid)) {
      await ref.update({
        'likes': FieldValue.arrayRemove([_currentUid]),
      });
    } else {
      await ref.update({
        'likes': FieldValue.arrayUnion([_currentUid]),
      });
    }
  }

  Future<void> _toggleReplyLike(
    String commentId,
    String replyId,
    List<dynamic> currentLikes,
  ) async {
    final ref = FirebaseFirestore.instance
        .collection('posts')
        .doc(widget.postId)
        .collection('comments')
        .doc(commentId)
        .collection('replies')
        .doc(replyId);
    if (currentLikes.contains(_currentUid)) {
      await ref.update({
        'likes': FieldValue.arrayRemove([_currentUid]),
      });
    } else {
      await ref.update({
        'likes': FieldValue.arrayUnion([_currentUid]),
      });
    }
  }

  Future<void> _deleteComment(String commentId) async {
    await FirebaseFirestore.instance
        .collection('posts')
        .doc(widget.postId)
        .collection('comments')
        .doc(commentId)
        .delete();
  }

  Future<void> _deleteReply(String commentId, String replyId) async {
    await FirebaseFirestore.instance
        .collection('posts')
        .doc(widget.postId)
        .collection('comments')
        .doc(commentId)
        .collection('replies')
        .doc(replyId)
        .delete();
  }

  void _showDeleteDialog(VoidCallback onConfirm) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        // name it dialogContext
        title: const Text('Delete?'),
        content: const Text('This will permanently delete this.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext), // ✅
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext); // ✅
              onConfirm();
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  String _timeAgo(Timestamp? timestamp) {
    if (timestamp == null) return '';
    final diff = DateTime.now().difference(timestamp.toDate());
    if (diff.inSeconds < 60) return '${diff.inSeconds}s';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return '${(diff.inDays / 7).floor()}w';
  }

  Widget _buildLikeButton({
    required List<dynamic> likes,
    required VoidCallback onTap,
  }) {
    final isLiked = likes.contains(_currentUid);
    return GestureDetector(
      onTap: onTap,
      child: Row(
        children: [
          Icon(
            isLiked ? Icons.favorite : Icons.favorite_border,
            size: 16,
            color: isLiked ? Colors.red : Colors.grey,
          ),
          if (likes.isNotEmpty) ...[
            const SizedBox(width: 3),
            Text(
              '${likes.length}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildComment(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final commentId = doc.id;
    final commentOwnerUid = data['uid'] ?? '';
    final pic = data['profileImage'] ?? '';
    final likes = List<dynamic>.from(data['likes'] ?? []);
    final canDelete = commentOwnerUid == _currentUid || _isPostOwner;
    final isExpanded = _expandedReplies.contains(commentId);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Tappable avatar
              GestureDetector(
                onTap: () => _openProfile(commentOwnerUid),
                child: CircleAvatar(
                  radius: 18,
                  backgroundImage: pic.isNotEmpty ? NetworkImage(pic) : null,
                  child: pic.isEmpty
                      ? const Icon(Icons.person, size: 18)
                      : null,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RichText(
                      text: TextSpan(
                        style: DefaultTextStyle.of(context).style,
                        children: [
                          // Tappable username
                          WidgetSpan(
                            child: GestureDetector(
                              onTap: () => _openProfile(commentOwnerUid),
                              child: Text(
                                '${data['username'] ?? 'user'}  ',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                          TextSpan(text: data['text'] ?? ''),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          _timeAgo(data['createdAt'] as Timestamp?),
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(width: 16),
                        GestureDetector(
                          onTap: () => _startReply(
                            commentId,
                            data['username'] ?? 'user',
                          ),
                          child: const Text(
                            'Reply',
                            style: TextStyle(
                              color: Colors.grey,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Column(
                children: [
                  _buildLikeButton(
                    likes: likes,
                    onTap: () => _toggleCommentLike(commentId, likes),
                  ),
                  if (canDelete)
                    GestureDetector(
                      onTap: () =>
                          _showDeleteDialog(() => _deleteComment(commentId)),
                      child: const Padding(
                        padding: EdgeInsets.only(top: 6),
                        child: Icon(
                          Icons.delete_outline,
                          size: 16,
                          color: Colors.grey,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),

          // Replies
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('posts')
                .doc(widget.postId)
                .collection('comments')
                .doc(commentId)
                .collection('replies')
                .orderBy('createdAt', descending: false)
                .snapshots(),
            builder: (context, snapshot) {
              final replies = snapshot.data?.docs ?? [];
              if (replies.isEmpty) return const SizedBox.shrink();

              return Padding(
                padding: const EdgeInsets.only(left: 46, top: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          if (isExpanded) {
                            _expandedReplies.remove(commentId);
                          } else {
                            _expandedReplies.add(commentId);
                          }
                        });
                      },
                      child: Row(
                        children: [
                          Container(width: 24, height: 1, color: Colors.grey),
                          const SizedBox(width: 8),
                          Text(
                            isExpanded
                                ? 'Hide replies'
                                : 'View ${replies.length} ${replies.length == 1 ? 'reply' : 'replies'}',
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (isExpanded)
                      ...replies.map((replyDoc) {
                        final rd = replyDoc.data() as Map<String, dynamic>;
                        final replyId = replyDoc.id;
                        final rUid = rd['uid'] ?? '';
                        final rPic = rd['profileImage'] ?? '';
                        final rLikes = List<dynamic>.from(rd['likes'] ?? []);
                        final canDeleteReply =
                            rUid == _currentUid || _isPostOwner;

                        return Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              GestureDetector(
                                onTap: () => _openProfile(rUid),
                                child: CircleAvatar(
                                  radius: 14,
                                  backgroundImage: rPic.isNotEmpty
                                      ? NetworkImage(rPic)
                                      : null,
                                  child: rPic.isEmpty
                                      ? const Icon(Icons.person, size: 14)
                                      : null,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    RichText(
                                      text: TextSpan(
                                        style: DefaultTextStyle.of(
                                          context,
                                        ).style,
                                        children: [
                                          WidgetSpan(
                                            child: GestureDetector(
                                              onTap: () => _openProfile(rUid),
                                              child: Text(
                                                '${rd['username'] ?? 'user'}  ',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          ),
                                          TextSpan(text: rd['text'] ?? ''),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        Text(
                                          _timeAgo(
                                            rd['createdAt'] as Timestamp?,
                                          ),
                                          style: const TextStyle(
                                            color: Colors.grey,
                                            fontSize: 12,
                                          ),
                                        ),
                                        const SizedBox(width: 16),
                                        GestureDetector(
                                          onTap: () => _startReply(
                                            commentId,
                                            rd['username'] ?? 'user',
                                          ),
                                          child: const Text(
                                            'Reply',
                                            style: TextStyle(
                                              color: Colors.grey,
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              Column(
                                children: [
                                  _buildLikeButton(
                                    likes: rLikes,
                                    onTap: () => _toggleReplyLike(
                                      commentId,
                                      replyId,
                                      rLikes,
                                    ),
                                  ),
                                  if (canDeleteReply)
                                    GestureDetector(
                                      onTap: () => _showDeleteDialog(
                                        () => _deleteReply(commentId, replyId),
                                      ),
                                      child: const Padding(
                                        padding: EdgeInsets.only(top: 6),
                                        child: Icon(
                                          Icons.delete_outline,
                                          size: 16,
                                          color: Colors.grey,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        );
                      }),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.93,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 10),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade400,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Text(
              'Comments',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const Divider(),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('posts')
                    .doc(widget.postId)
                    .collection('comments')
                    .orderBy('createdAt', descending: false)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final docs = snapshot.data?.docs ?? [];
                  if (docs.isEmpty) {
                    return const Center(
                      child: Text(
                        'No comments yet.\nBe the first to comment!',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey),
                      ),
                    );
                  }
                  return ListView.builder(
                    controller: scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: docs.length,
                    itemBuilder: (context, index) => _buildComment(docs[index]),
                  );
                },
              ),
            ),
            const Divider(height: 1),
            if (_replyingToUsername != null)
              Container(
                color: Theme.of(context).colorScheme.secondary,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                child: Row(
                  children: [
                    Text(
                      'Replying to @$_replyingToUsername',
                      style: const TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: _cancelReply,
                      child: const Icon(
                        Icons.close,
                        size: 18,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
            SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 8,
                  top: 8,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 8,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        focusNode: _focusNode,
                        maxLines: null,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: InputDecoration(
                          hintText: _replyingToUsername != null
                              ? 'Reply to @$_replyingToUsername…'
                              : 'Add a comment…',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide.none,
                          ),
                          filled: true,
                          fillColor: Theme.of(context).colorScheme.secondary,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _isPosting
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : IconButton(
                            icon: const Icon(Icons.send, color: Colors.blue),
                            onPressed: _postComment,
                          ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
