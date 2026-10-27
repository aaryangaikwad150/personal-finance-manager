import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'currency_helper.dart';

class CurrencyAmount extends StatelessWidget {
  final double amountInInr;
  final TextStyle? style;

  const CurrencyAmount({super.key, required this.amountInInr, this.style});

  DocumentReference get _settingsDoc {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    return FirebaseFirestore.instance.collection('settings').doc(uid);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: _settingsDoc.snapshots(),
      builder: (context, snapshot) {
        String currency = 'INR';
        if (snapshot.hasData && snapshot.data!.exists) {
          final data = snapshot.data!.data() as Map<String, dynamic>;
          currency = data['currency'] ?? 'INR';
        }

        if (currency == 'INR') {
          return Text('₹${amountInInr.toStringAsFixed(2)}', style: style);
        }

        return FutureBuilder<String>(
          future: CurrencyHelper.format(amountInInr, currency),
          builder: (context, snap) {
            if (!snap.hasData) {
              return Text('₹${amountInInr.toStringAsFixed(2)}', style: style);
            }
            return Text(snap.data!, style: style);
          },
        );
      },
    );
  }
}