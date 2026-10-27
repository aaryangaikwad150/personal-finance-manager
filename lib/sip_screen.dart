import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'theme.dart';
import 'currency_widgets.dart';
import 'workspace.dart';
import 'firestore_helper.dart';
import 'currency_helper.dart';
import 'currency_settings.dart';
import 'confirm_dialog.dart';

class SipScreen extends StatefulWidget {
  const SipScreen({super.key});

  @override
  State<SipScreen> createState() => _SipScreenState();
}

class _SipScreenState extends State<SipScreen> {
  final fundController = TextEditingController();
  final amountController = TextEditingController();
  bool isSaving = false;

  @override
  void initState() {
    super.initState();
    Workspace.current.addListener(_onWorkspaceChanged);
    Workspace.currentMember.addListener(_onWorkspaceChanged);
  }

  void _onWorkspaceChanged() {
    if (mounted) setState(() {});
  }

  CollectionReference get _userSips {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    return FirebaseFirestore.instance
        .collection('investments')
        .doc('$uid${Workspace.suffix()}')
        .collection('sips');
  }

  Future<void> _addSip() async {
    final enteredAmount = double.tryParse(amountController.text);
    if (fundController.text.trim().isEmpty || enteredAmount == null || enteredAmount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red.shade700,
          content: const Text('Please enter a fund name and valid amount.', style: TextStyle(color: Colors.white)),
        ),
      );
      return;
    }

    setState(() => isSaving = true);

    final currentCurrency = await getCurrentCurrency();
    final amountInInr = await CurrencyHelper.toInr(enteredAmount, currentCurrency);

    final success = await safeFirestoreWrite(
      context: context,
      operation: () => _userSips.add({
        'fundName': fundController.text.trim(),
        'monthlyAmount': amountInInr,
        'startDate': Timestamp.now(),
      }),
    );

    if (!mounted) return;

    if (success) {
      fundController.clear();
      amountController.clear();
      setState(() => isSaving = false);
    } else {
      setState(() => isSaving = false);
    }
  }

  Future<void> _editSip(String docId, Map<String, dynamic> data) async {
    final currentCurrency = await getCurrentCurrency();
    final storedAmountInr = (data['monthlyAmount'] as num).toDouble();
    final displayAmount = await CurrencyHelper.convert(storedAmountInr, currentCurrency);

    final editFund = TextEditingController(text: data['fundName'] ?? '');
    final editAmount = TextEditingController(text: displayAmount.toStringAsFixed(2));

    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.parchment,
        title: const Text('Edit SIP', style: TextStyle(color: AppColors.ink)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: editFund,
              decoration: const InputDecoration(labelText: 'Fund Name', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: editAmount,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Monthly SIP Amount (${CurrencyHelper.symbolFor(currentCurrency)})',
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: AppColors.sage)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.gold),
            onPressed: () async {
              final newEnteredAmount = double.tryParse(editAmount.text);
              if (newEnteredAmount == null || newEnteredAmount <= 0 || editFund.text.trim().isEmpty) return;

              final newAmountInInr = await CurrencyHelper.toInr(newEnteredAmount, currentCurrency);

              final success = await safeFirestoreWrite(
                context: context,
                operation: () => _userSips.doc(docId).update({
                  'fundName': editFund.text.trim(),
                  'monthlyAmount': newAmountInInr,
                }),
              );
              if (success && context.mounted) Navigator.pop(context);
            },
            child: const Text('Save', style: TextStyle(color: AppColors.ink)),
          ),
        ],
      ),
    );
  }

  // NEW: confirmation added before deleting a SIP. The undo snackbar
  // remains as a second safety net after confirming.
  Future<void> _deleteSip(Map<String, dynamic> data, String id) async {
    final confirmed = await showConfirmDialog(
      context: context,
      title: 'Delete SIP?',
      message: '${data['fundName'] ?? 'This'} will be deleted. You can still undo right after.',
      confirmLabel: 'Delete',
      isDestructive: true,
    );
    if (!confirmed) return;
    if (!mounted) return;

    final success = await safeFirestoreWrite(
      context: context,
      operation: () => _userSips.doc(id).delete(),
    );

    if (!mounted || !success) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppColors.ink,
        content: Text(
          'Deleted ${data['fundName']} SIP',
          style: const TextStyle(color: AppColors.parchment),
        ),
        action: SnackBarAction(
          label: 'UNDO',
          textColor: AppColors.gold,
          onPressed: () async {
            await safeFirestoreWrite(context: context, operation: () => _userSips.doc(id).set(data));
          },
        ),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Text('SIP Investments',
                style: TextStyle(color: AppColors.parchment, fontSize: 22, fontWeight: FontWeight.w600)),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: AppColors.parchment, borderRadius: BorderRadius.circular(12)),
              child: Column(
                children: [
                  TextField(
                    controller: fundController,
                    decoration: const InputDecoration(labelText: 'Fund Name', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: amountController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Monthly SIP Amount', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 42,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: AppColors.gold),
                      onPressed: isSaving ? null : _addSip,
                      child: isSaving
                          ? const CircularProgressIndicator(color: AppColors.ink)
                          : const Text('Add SIP', style: TextStyle(color: AppColors.ink)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('Tap to edit • Long-press to delete (undo available)',
                  style: TextStyle(color: AppColors.sage, fontSize: 12)),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: _userSips.orderBy('startDate', descending: true).snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return const Center(
                      child: Text('Could not load SIPs. Check your connection.',
                          style: TextStyle(color: AppColors.sage)),
                    );
                  }
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator(color: AppColors.gold));
                  }
                  final docs = snapshot.data!.docs;
                  if (docs.isEmpty) {
                    return const Center(child: Text('No SIPs added yet', style: TextStyle(color: AppColors.sage)));
                  }
                  return ListView.builder(
                    itemCount: docs.length,
                    itemBuilder: (context, index) {
                      final data = docs[index].data() as Map<String, dynamic>;
                      return Card(
                        color: AppColors.parchment,
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        child: ListTile(
                          title: Text(data['fundName'] ?? '', style: const TextStyle(color: AppColors.ink)),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CurrencyAmount(
                                amountInInr: (data['monthlyAmount'] as num).toDouble(),
                                style: const TextStyle(color: AppColors.ink, fontWeight: FontWeight.bold),
                              ),
                              const Text('/mo', style: TextStyle(color: AppColors.ink, fontWeight: FontWeight.bold)),
                            ],
                          ),
                          onTap: () => _editSip(docs[index].id, data),
                          onLongPress: () => _deleteSip(data, docs[index].id),
                        ),
                      );
                    },
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
    fundController.dispose();
    amountController.dispose();
    super.dispose();
  }
}