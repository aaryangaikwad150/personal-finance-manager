import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'theme.dart';
import 'transaction_helpers.dart';
import 'currency_widgets.dart';
import 'workspace.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  String filter = 'All';

  @override
  void initState() {
    super.initState();
    Workspace.current.addListener(_onWorkspaceChanged);
    Workspace.currentMember.addListener(_onWorkspaceChanged);
  }

  void _onWorkspaceChanged() {
    if (mounted) setState(() {});
  }

  CollectionReference get _userTransactions {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    return FirebaseFirestore.instance
        .collection('transactions')
        .doc('$uid${Workspace.suffix()}')
        .collection('items');
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(
              width: double.infinity,
              child: Text(
                'Transaction History',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.parchment, fontSize: 22, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(color: AppColors.parchment, borderRadius: BorderRadius.circular(8)),
                child: DropdownButton<String>(
                  value: filter,
                  underline: const SizedBox(),
                  items: ['All', ...categories].map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                  onChanged: (val) => setState(() => filter = val!),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: _userTransactions.orderBy('date', descending: true).snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator(color: AppColors.gold));
                  }
                  final allDocs = snapshot.data!.docs;
                  final docs = filter == 'All'
                      ? allDocs
                      : allDocs.where((d) => (d.data() as Map<String, dynamic>)['category'] == filter).toList();

                  double total = 0;
                  for (final d in allDocs) {
                    total += ((d.data() as Map<String, dynamic>)['amount'] as num).toDouble();
                  }
                  double filteredTotal = 0;
                  for (final d in docs) {
                    filteredTotal += ((d.data() as Map<String, dynamic>)['amount'] as num).toDouble();
                  }
                  final rate = total == 0 ? 0.0 : (filteredTotal / total) * 100;

                  if (docs.isEmpty) {
                    return const Center(child: Text('No matching transactions', style: TextStyle(color: AppColors.sage)));
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(color: AppColors.parchment, borderRadius: BorderRadius.circular(10)),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('${filter == 'All' ? 'Total' : filter} spent',
                                style: const TextStyle(color: AppColors.ink, fontWeight: FontWeight.w600)),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CurrencyAmount(
                                  amountInInr: filteredTotal,
                                  style: const TextStyle(color: AppColors.ink, fontWeight: FontWeight.bold),
                                ),
                                Text('  •  ${rate.toStringAsFixed(1)}% of total',
                                    style: const TextStyle(color: AppColors.ink, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: ListView.builder(
                          itemCount: docs.length,
                          itemBuilder: (context, index) {
                            final data = docs[index].data() as Map<String, dynamic>;
                            final date = (data['date'] as Timestamp).toDate();
                            return Card(
                              color: AppColors.parchment,
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              child: ListTile(
                                title: Text(data['category'] ?? '', style: const TextStyle(color: AppColors.ink)),
                                subtitle: Text(
                                  '${data['note'] ?? ''}\n${formatDate(date)}',
                                  style: const TextStyle(color: AppColors.sage),
                                ),
                                isThreeLine: true,
                                trailing: CurrencyAmount(
                                  amountInInr: (data['amount'] as num).toDouble(),
                                  style: const TextStyle(color: AppColors.ink, fontWeight: FontWeight.bold),
                                ),
                                onTap: () => showEditTransactionDialog(
                                  context: context,
                                  collection: _userTransactions,
                                  docId: docs[index].id,
                                  data: data,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    Workspace.current.removeListener(_onWorkspaceChanged);
    Workspace.currentMember.removeListener(_onWorkspaceChanged);
    super.dispose();
  }
}