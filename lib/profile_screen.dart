import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'theme.dart';
import 'cloudinary_service.dart';
import 'firestore_helper.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final nameController = TextEditingController();
  bool loading = true;
  bool loadError = false;
  bool isUploadingPhoto = false;
  DateTime? memberSince;
  String? photoUrl;

  DocumentReference get _profileDoc {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    return FirebaseFirestore.instance.collection('profiles').doc(uid);
  }

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final doc = await _profileDoc.get();
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        nameController.text = data['displayName'] ?? '';
        photoUrl = data['photoUrl'];
        if (data['memberSince'] != null) {
          memberSince = (data['memberSince'] as Timestamp).toDate();
        }
      }
      memberSince ??= FirebaseAuth.instance.currentUser?.metadata.creationTime;
    } catch (e) {
      debugPrint('Profile load error: $e');
      if (mounted) setState(() => loadError = true);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _saveName() async {
    final name = nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red.shade700,
          content: const Text('Name cannot be empty.', style: TextStyle(color: Colors.white)),
        ),
      );
      return;
    }

    await safeFirestoreWrite(
      context: context,
      operation: () => _profileDoc.set({
        'displayName': name,
        'memberSince': memberSince != null ? Timestamp.fromDate(memberSince!) : Timestamp.now(),
      }, SetOptions(merge: true)),
      successMessage: 'Profile updated',
    );
  }

  Future<void> _uploadPhoto() async {
    setState(() => isUploadingPhoto = true);
    try {
      final url = await CloudinaryService.pickAndUpload();
      if (url == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: Colors.red.shade700,
              content: const Text('Photo upload failed. Please try again.', style: TextStyle(color: Colors.white)),
            ),
          );
        }
        return;
      }
      final success = await safeFirestoreWrite(
        context: context,
        operation: () => _profileDoc.set({'photoUrl': url}, SetOptions(merge: true)),
      );
      if (success && mounted) setState(() => photoUrl = url);
    } finally {
      if (mounted) setState(() => isUploadingPhoto = false);
    }
  }

  Future<void> _removePhoto() async {
    final success = await safeFirestoreWrite(
      context: context,
      operation: () => _profileDoc.set({'photoUrl': null}, SetOptions(merge: true)),
    );
    if (success && mounted) setState(() => photoUrl = null);
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.gold));
    }

    final user = FirebaseAuth.instance.currentUser;
    final initial = nameController.text.isNotEmpty
        ? nameController.text.trim()[0].toUpperCase()
        : (user?.email?.isNotEmpty == true ? user!.email![0].toUpperCase() : '?');

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: AppColors.parchment),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                const Text('Profile',
                    style: TextStyle(color: AppColors.parchment, fontSize: 22, fontWeight: FontWeight.w600)),
              ],
            ),
            if (loadError) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  "Couldn't load your saved profile. Check your connection.",
                  style: TextStyle(color: Colors.red, fontSize: 12),
                ),
              ),
            ],
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: AppColors.parchment, borderRadius: BorderRadius.circular(12)),
              child: Column(
                children: [
                  Stack(
                    children: [
                      CircleAvatar(
                        radius: 48,
                        backgroundColor: AppColors.gold,
                        backgroundImage: photoUrl != null ? NetworkImage(photoUrl!) : null,
                        child: photoUrl == null
                            ? Text(initial, style: const TextStyle(color: AppColors.ink, fontSize: 32, fontWeight: FontWeight.bold))
                            : null,
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: GestureDetector(
                          onTap: isUploadingPhoto ? null : _uploadPhoto,
                          child: CircleAvatar(
                            radius: 16,
                            backgroundColor: AppColors.ink,
                            child: isUploadingPhoto
                                ? const SizedBox(
                                width: 14, height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.gold))
                                : const Icon(Icons.camera_alt, size: 16, color: AppColors.parchment),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (photoUrl != null) ...[
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: _removePhoto,
                      icon: const Icon(Icons.delete_outline, size: 16, color: Colors.red),
                      label: const Text('Remove photo', style: TextStyle(color: Colors.red, fontSize: 12)),
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: 'Display Name', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 8),
                  Text(user?.email ?? '', style: const TextStyle(color: AppColors.sage)),
                  const SizedBox(height: 4),
                  if (memberSince != null)
                    Text(
                      'Member since ${memberSince!.day}/${memberSince!.month}/${memberSince!.year}',
                      style: const TextStyle(color: AppColors.sage, fontSize: 12),
                    ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: AppColors.gold),
                      onPressed: _saveName,
                      child: const Text('Save', style: TextStyle(color: AppColors.ink)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    nameController.dispose();
    super.dispose();
  }
}