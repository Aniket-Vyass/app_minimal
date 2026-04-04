import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

class UploadPage extends StatefulWidget {
  final VoidCallback? onUploadSuccess;
  const UploadPage({super.key, this.onUploadSuccess});

  @override
  State<UploadPage> createState() => _UploadPageState();
}

class _UploadPageState extends State<UploadPage> {
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _captionController = TextEditingController();

  XFile? _selectedFile;
  bool _isVideo = false;
  bool _isUploading = false;
  VideoPlayerController? _videoController;

  @override
  void dispose() {
    _captionController.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  Future<void> _pickFromGallery(bool video) async {
    final XFile? file = video
        ? await _picker.pickVideo(
            source: ImageSource.gallery,
            maxDuration: const Duration(seconds: 60),
          )
        : await _picker.pickImage(source: ImageSource.gallery);

    if (file == null) return;
    await _setFile(file, isVideo: video);
  }

  Future<void> _captureFromCamera(bool video) async {
    final XFile? file = video
        ? await _picker.pickVideo(
            source: ImageSource.camera,
            maxDuration: const Duration(seconds: 60),
          )
        : await _picker.pickImage(source: ImageSource.camera);

    if (file == null) return;
    await _setFile(file, isVideo: video);
  }

  Future<void> _setFile(XFile file, {required bool isVideo}) async {
    if (isVideo) {
      final controller = VideoPlayerController.file(File(file.path));
      await controller.initialize();
      final duration = controller.value.duration;
      await controller.dispose();

      if (duration.inSeconds > 60) {
        _showSnack('Video must be 60 seconds or less.');
        return;
      }

      _videoController?.dispose();
      final previewController = VideoPlayerController.file(File(file.path));
      await previewController.initialize();
      previewController.setLooping(true);

      setState(() {
        _selectedFile = file;
        _isVideo = true;
        _videoController = previewController;
      });

      previewController.play();
    } else {
      // ── open image cropper before setting the file ───────────
      final croppedFile = await ImageCropper().cropImage(
        sourcePath: file.path,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Adjust Photo',
            toolbarColor: Theme.of(context).appBarTheme.backgroundColor,
            toolbarWidgetColor: Colors.white,
            initAspectRatio: CropAspectRatioPreset.square,
            lockAspectRatio: false,
            aspectRatioPresets: [
              CropAspectRatioPreset.square,
              CropAspectRatioPreset.ratio4x3,
              CropAspectRatioPreset.ratio16x9,
              CropAspectRatioPreset.original,
            ],
          ),
          IOSUiSettings(
            title: 'Adjust Photo',
            aspectRatioPresets: [
              CropAspectRatioPreset.square,
              CropAspectRatioPreset.ratio4x3,
              CropAspectRatioPreset.ratio16x9,
              CropAspectRatioPreset.original,
            ],
          ),
        ],
      );

      // user cancelled the cropper
      if (croppedFile == null) return;

      _videoController?.dispose();
      setState(() {
        _selectedFile = XFile(croppedFile.path);
        _isVideo = false;
        _videoController = null;
      });
    }
  }

  void _showPickerOptions({required bool video}) {
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
              leading: const Icon(Icons.photo_library),
              title: Text(
                video ? 'Pick video from gallery' : 'Pick from gallery',
              ),
              onTap: () {
                Navigator.pop(context);
                _pickFromGallery(video);
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: Text(video ? 'Record a video' : 'Take a photo'),
              onTap: () {
                Navigator.pop(context);
                _captureFromCamera(video);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _upload() async {
    if (_selectedFile == null) {
      _showSnack('Please select an image or video first.');
      return;
    }

    setState(() => _isUploading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        _showSnack('You must be logged in to upload.');
        setState(() => _isUploading = false);
        return;
      }

      final fileName =
          '${user.uid}_${DateTime.now().millisecondsSinceEpoch}.${_isVideo ? 'mp4' : 'jpg'}';
      final ref = FirebaseStorage.instance
          .ref()
          .child(_isVideo ? 'videos' : 'posts')
          .child(fileName);

      await ref.putFile(File(_selectedFile!.path));
      final downloadUrl = await ref.getDownloadURL();

      String thumbnailUrl = '';
      if (_isVideo) {
        final Uint8List? thumbnailBytes = await VideoThumbnail.thumbnailData(
          video: _selectedFile!.path,
          imageFormat: ImageFormat.JPEG,
          quality: 75,
        );

        if (thumbnailBytes != null) {
          final thumbFileName =
              '${user.uid}_${DateTime.now().millisecondsSinceEpoch}_thumb.jpg';
          final thumbRef = FirebaseStorage.instance
              .ref()
              .child('thumbnails')
              .child(thumbFileName);

          await thumbRef.putData(thumbnailBytes);
          thumbnailUrl = await thumbRef.getDownloadURL();
        }
      }

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get(const GetOptions(source: Source.server));
      final username = userDoc.data()?['username'] ?? user.email ?? 'user';
      final profileImage = userDoc.data()?['profileImage'] ?? '';

      await FirebaseFirestore.instance.collection('posts').add({
        'uid': user.uid,
        'username': username,
        'profileImage': profileImage,
        'imageUrl': downloadUrl,
        'thumbnailUrl': thumbnailUrl,
        'isVideo': _isVideo,
        'caption': _captionController.text.trim(),
        'createdAt': FieldValue.serverTimestamp(),
        'likes': [],
      });

      if (!mounted) return;
      widget.onUploadSuccess?.call();
    } catch (e) {
      _showSnack('Upload failed: $e');
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('New Post'),
        actions: [
          TextButton(
            onPressed: _isUploading ? null : _upload,
            child: const Text(
              'Share',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
        ],
      ),
      body: _isUploading
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Uploading…'),
                ],
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _selectedFile == null
                      ? _buildMediaPlaceholder()
                      : _isVideo
                      ? _buildVideoPreview()
                      : _buildImagePreview(),

                  const SizedBox(height: 20),

                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.image),
                          label: const Text('Photo'),
                          onPressed: () => _showPickerOptions(video: false),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.videocam),
                          label: const Text('Video ≤60s'),
                          onPressed: () => _showPickerOptions(video: true),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  TextField(
                    controller: _captionController,
                    maxLines: 4,
                    maxLength: 300,
                    decoration: const InputDecoration(
                      labelText: 'Write a caption…',
                      alignLabelWithHint: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildMediaPlaceholder() {
    return Container(
      height: 300,
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[400]!),
      ),
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.add_photo_alternate_outlined,
              size: 60,
              color: Colors.grey,
            ),
            SizedBox(height: 8),
            Text(
              'Select a photo or video',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImagePreview() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.file(
        File(_selectedFile!.path),
        height: 300,
        width: double.infinity,
        fit: BoxFit.cover,
      ),
    );
  }

  Widget _buildVideoPreview() {
    final controller = _videoController!;
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: AspectRatio(
            aspectRatio: controller.value.aspectRatio,
            child: VideoPlayer(controller),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              icon: Icon(
                controller.value.isPlaying ? Icons.pause : Icons.play_arrow,
              ),
              onPressed: () {
                setState(() {
                  controller.value.isPlaying
                      ? controller.pause()
                      : controller.play();
                });
              },
            ),
            Text(
              '${controller.value.duration.inSeconds}s',
              style: const TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ],
    );
  }
}
