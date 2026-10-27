import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Fetches the user's currently selected currency (INR/USD/EUR) once,
/// for use right before saving an amount. Falls back to INR on any error.
Future<String> getCurrentCurrency() async {
  try {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final doc = await FirebaseFirestore.instance.collection('settings').doc(uid).get();
    if (doc.exists) {
      final data = doc.data() as Map<String, dynamic>;
      return data['currency'] ?? 'INR';
    }
  } catch (_) {
    // fall through
  }
  return 'INR';
}