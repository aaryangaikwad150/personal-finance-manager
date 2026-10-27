import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'theme.dart';
import 'currency_widgets.dart';
import 'workspace.dart';
import 'firestore_helper.dart';
import 'confirm_dialog.dart';

const _months = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December'
];

class IncomeScreen extends StatefulWidget {
  const IncomeScreen({super.key});

  @override
  State<IncomeScreen> createState() => _IncomeScreenState();
}

class _IncomeScreenState extends State<IncomeScreen> {
  final amountController = TextEditingController();
  final sourceController = TextEditingController();
  DateTime selectedDate = DateTime.now();
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

  CollectionReference get _income {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    return FirebaseFirestore.instance
        .collection('income')
        .doc('$uid${Workspace.suffix()}')
        .collection('items');
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(DateTime.now().year + 1),
    );
    if (picked != null) setState(() => selectedDate = picked);
  }

  Future<void> _addIncome() async {
    final amount = double.tryParse(amountController.text);
    if (amount == null || amount <= 0 || sourceController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red.shade700,
          content: const Text('Please enter a valid amount and source.', style: TextStyle(color: Colors.white)),
        ),
      );
      return;
    }

    setState(() => isSaving = true);

    final success = await safeFirestoreWrite(
      context: context,
      operation: () => _income.add({
        'amount': amount,
        'source': sourceController.text.trim(),
        'date': Timestamp.fromDate(selectedDate),
      }),
    );

    if (!mounted) return;

    if (success) {
      amountController.clear();
      sourceController.clear();
      setState(() {
        selectedDate = DateTime.now();
        isSaving = false;
      });
    } else {
      setState(() => isSaving = false);
    }
  }

  Future<void> _editIncome(String docId, Map<String, dynamic> data) async {
    final editAmount = TextEditingController(text: (data['amount'] as num).toString());
    final editSource = TextEditingController(text: data['source'] ?? '');
    DateTime editDate = (data['date'] as Timestamp).toDate();

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: AppColors.parchment,
              title: const Text('Edit Income', style: TextStyle(color: AppColors.ink)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: editAmount,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Amount', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: editSource,
                    decoration: const InputDecoration(labelText: 'Source', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${editDate.day} ${_months[editDate.month - 1]} ${editDate.year}',
                          style: const TextStyle(color: AppColors.ink),
                        ),
                      ),
                      TextButton(
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: editDate,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(DateTime.now().year + 1),
                          );
                          if (picked != null) setDialogState(() => editDate = picked);
                        },
                        child: const Text('Change date', style: TextStyle(color: AppColors.sage)),
                      ),
                    ],
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
                    final newAmount = double.tryParse(editAmount.text);
                    if (newAmount == null || newAmount <= 0) return;
                    final success = await safeFirestoreWrite(
                      context: context,
                      operation: () => _income.doc(docId).update({
                        'amount': newAmount,
                        'source': editSource.text.trim(),
                        'date': Timestamp.fromDate(editDate),
                      }),
                    );
                    if (success && context.mounted) Navigator.pop(context);
                  },
                  child: const Text('Save', style: TextStyle(color: AppColors.ink)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // NEW: confirmation added before deleting income. The undo snackbar
  // remains as a second safety net after confirming.
  Future<void> _deleteIncome(Map<String, dynamic> data, String id) async {
    final confirmed = await showConfirmDialog(
      context: context,
      title: 'Delete income entry?',
      message: '${data['source'] ?? 'This'} • ₹${(data['amount'] as num).toStringAsFixed(2)} will be deleted. '
          'You can still undo right after.',
      confirmLabel: 'Delete',
      isDestructive: true,
    );
    if (!confirmed) return;
    if (!mounted) return;

    final success = await safeFirestoreWrite(
      context: context,
      operation: () => _income.doc(id).delete(),
    );

    if (!mounted || !success) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppColors.ink,
        content: Text(
          'Deleted ${data['source']} • ₹${(data['amount'] as num).toStringAsFixed(2)}',
          style: const TextStyle(color: AppColors.parchment),
        ),
        action: SnackBarAction(
          label: 'UNDO',
          textColor: AppColors.gold,
          onPressed: () async {
            await safeFirestoreWrite(context: context, operation: () => _income.doc(id).set(data));
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
            const Text('Income',
                style: TextStyle(color: AppColors.parchment, fontSize: 22, fontWeight: FontWeight.w600)),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: AppColors.parchment, borderRadius: BorderRadius.circular(12)),
              child: Column(
                children: [
                  TextField(
                    controller: amountController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Amount', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: sourceController,
                    decoration: const InputDecoration(labelText: 'Source (Salary, Freelance, etc.)', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Date: ${selectedDate.day} ${_months[selectedDate.month - 1]} ${selectedDate.year}',
                          style: const TextStyle(color: AppColors.ink),
                        ),
                      ),
                      TextButton(
                        onPressed: _pickDate,
                        child: const Text('Change', style: TextStyle(color: AppColors.sage)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 42,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: AppColors.gold),
                      onPressed: isSaving ? null : _addIncome,
                      child: isSaving
                          ? const CircularProgressIndicator(color: AppColors.ink)
                          : const Text('Add Income', style: TextStyle(color: AppColors.ink)),
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
                stream: _income.orderBy('date', descending: true).snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return const Center(
                      child: Text('Could not load income. Check your connection.',
                          style: TextStyle(color: AppColors.sage)),
                    );
                  }
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator(color: AppColors.gold));
                  }
                  final docs = snapshot.data?.docs ?? [];
                  if (docs.isEmpty) {
                    return const Center(child: Text('No income logged yet', style: TextStyle(color: AppColors.sage)));
                  }

                  final Map<String, List<QueryDocumentSnapshot>> grouped = {};
                  final Map<String, double> monthTotals = {};
                  for (final doc in docs) {
                    final data = doc.data() as Map<String, dynamic>;
                    final date = (data['date'] as Timestamp).toDate();
                    final key = '${_months[date.month - 1]} ${date.year}';
                    grouped.putIfAbsent(key, () => []).add(doc);
                    monthTotals[key] = (monthTotals[key] ?? 0) + (data['amount'] as num).toDouble();
                  }

                  return ListView(
                    children: grouped.entries.map((entry) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 8, bottom: 6),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(entry.key,
                                    style: const TextStyle(color: AppColors.gold, fontWeight: FontWeight.w600)),
                                CurrencyAmount(
                                  amountInInr: monthTotals[entry.key]!,
                                  style: const TextStyle(color: AppColors.parchment, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                          ...entry.value.map((doc) {
                            final data = doc.data() as Map<String, dynamic>;
                            return Card(
                              color: AppColors.parchment,
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              child: ListTile(
                                title: Text(data['source'] ?? '', style: const TextStyle(color: AppColors.ink)),
                                trailing: CurrencyAmount(
                                  amountInInr: (data['amount'] as num).toDouble(),
                                  style: const TextStyle(color: AppColors.ink, fontWeight: FontWeight.bold),
                                ),
                                onTap: () => _editIncome(doc.id, data),
                                onLongPress: () => _deleteIncome(data, doc.id),
                              ),
                            );
                          }),
                        ],
                      );
                    }).toList(),
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
    amountController.dispose();
    sourceController.dispose();
    super.dispose();
  }
}