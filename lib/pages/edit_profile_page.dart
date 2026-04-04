import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class EditProfilePage extends StatefulWidget {
  final String currentUsername;
  final String currentBio;
  final String currentProfileImage;

  const EditProfilePage({
    super.key,
    required this.currentUsername,
    required this.currentBio,
    required this.currentProfileImage,
  });

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  late TextEditingController _usernameCtrl;
  late TextEditingController _bioCtrl;

  XFile? _pickedImage;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _usernameCtrl = TextEditingController(text: widget.currentUsername);
    _bioCtrl = TextEditingController(text: widget.currentBio);
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _bioCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ImageProvider? avatarImage = _pickedImage != null
        ? FileImage(File(_pickedImage!.path))
        : widget.currentProfileImage.isNotEmpty
        ? NetworkImage(widget.currentProfileImage)
        : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Profile'),
        actions: [
          TextButton(
            onPressed: _isSaving
                ? null
                : () async {
                    final username = _usernameCtrl.text.trim();
                    if (username.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Username cannot be empty.'),
                        ),
                      );
                      return;
                    }

                    setState(() => _isSaving = true);

                    try {
                      final uid = FirebaseAuth.instance.currentUser!.uid;
                      String profileImageUrl = widget.currentProfileImage;

                      // ── upload new photo if one was picked ────────
                      if (_pickedImage != null) {
                        final ref = FirebaseStorage.instance
                            .ref()
                            .child('profile_pictures')
                            .child('$uid.jpg');
                        await ref.putFile(File(_pickedImage!.path));
                        profileImageUrl = await ref.getDownloadURL();
                      }

                      // ── save to users collection ──────────────────
                      await FirebaseFirestore.instance
                          .collection('users')
                          .doc(uid)
                          .update({
                            'username': username,
                            'bio': _bioCtrl.text.trim(),
                            'profileImage': profileImageUrl,
                          });

                      // ── update profileImage & username on all existing posts ──
                      final postsSnapshot = await FirebaseFirestore.instance
                          .collection('posts')
                          .where('uid', isEqualTo: uid)
                          .get();

                      final batch = FirebaseFirestore.instance.batch();
                      for (final doc in postsSnapshot.docs) {
                        batch.update(doc.reference, {
                          'profileImage': profileImageUrl,
                          'username': username,
                        });
                      }
                      await batch.commit();

                      if (!mounted) return;
                      Navigator.pop(context, true);
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Save failed: $e')),
                      );
                    } finally {
                      if (mounted) setState(() => _isSaving = false);
                    }
                  },
            child: _isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text(
                    'Save',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
          ),
        ],
      ),

      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // ── Avatar + change photo button ───────────────────────
            Center(
              child: Stack(
                children: [
                  CircleAvatar(
                    radius: 55,
                    backgroundImage: avatarImage,
                    child: avatarImage == null
                        ? const Icon(Icons.person, size: 55)
                        : null,
                  ),
                  Positioned(
                    bottom: 2,
                    right: 2,
                    child: GestureDetector(
                      onTap: () async {
                        final XFile? file = await ImagePicker().pickImage(
                          source: ImageSource.gallery,
                        );
                        if (file != null) {
                          setState(() => _pickedImage = file);
                        }
                      },
                      child: const CircleAvatar(
                        radius: 16,
                        child: Icon(Icons.edit, size: 16),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // ── Username field ─────────────────────────────────────
            TextField(
              controller: _usernameCtrl,
              decoration: const InputDecoration(
                labelText: 'Username',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.person_outline),
              ),
            ),

            const SizedBox(height: 16),

            // ── Bio field ──────────────────────────────────────────
            TextField(
              controller: _bioCtrl,
              maxLines: 3,
              maxLength: 150,
              decoration: const InputDecoration(
                labelText: 'Bio',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.info_outline),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
