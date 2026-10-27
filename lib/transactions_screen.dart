import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'theme.dart';
import 'transaction_helpers.dart';
import 'currency_widgets.dart';
import 'cloudinary_service.dart';
import 'workspace.dart';
import 'firestore_helper.dart';

class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({super.key});

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  final amountController = TextEditingController();
  final noteController = TextEditingController();
  String selectedCategory = 'Food';
  String? receiptUrl;
  bool isSaving = false;
  bool isUploadingReceipt = false;

  bool selectionMode = false;
  final Set<String> selectedIds = {};

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

  Future<void> _attachReceipt() async {
    setState(() => isUploadingReceipt = true);
    try {
      final url = await CloudinaryService.pickAndUpload();
      if (!mounted) return;
      setState(() {
        if (url != null) {
          receiptUrl = url;
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: Colors.red.shade700,
              content: const Text('Receipt upload failed. Please try again.', style: TextStyle(color: Colors.white)),
            ),
          );
        }
      });
      // Open the receipt right after it is attached so the user can confirm it is the right one.
      if (url != null && mounted) {
        showReceiptDialog(context, url);
      }
    } finally {
      if (mounted) setState(() => isUploadingReceipt = false);
    }
  }

  Future<void> _addTransaction() async {
    final amount = double.tryParse(amountController.text);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red.shade700,
          content: const Text('Please enter a valid amount.', style: TextStyle(color: Colors.white)),
        ),
      );
      return;
    }

    setState(() => isSaving = true);

    final savedReceiptUrl = receiptUrl;

    final success = await safeFirestoreWrite(
      context: context,
      operation: () => _userTransactions.add({
        'amount': amount,
        'category': selectedCategory,
        'note': noteController.text.trim(),
        'date': Timestamp.now(),
        'receiptUrl': savedReceiptUrl,
      }),
    );

    if (!mounted) return;

    if (success) {
      amountController.clear();
      noteController.clear();
      setState(() {
        receiptUrl = null;
        isSaving = false;
      });

      if (savedReceiptUrl != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.ink,
            content: const Text('Transaction saved with receipt',
                style: TextStyle(color: AppColors.parchment)),
            action: SnackBarAction(
              label: 'VIEW RECEIPT',
              textColor: AppColors.gold,
              onPressed: () => showReceiptDialog(context, savedReceiptUrl),
            ),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } else {
      setState(() => isSaving = false);
    }
  }

  Future<void> _deleteTransaction(Map<String, dynamic> data, String id) async {
    final success = await safeFirestoreWrite(
      context: context,
      operation: () => _userTransactions.doc(id).delete(),
    );

    if (!mounted || !success) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppColors.ink,
        content: Text(
          'Deleted ${data['category']} • ₹${(data['amount'] as num).toStringAsFixed(2)}',
          style: const TextStyle(color: AppColors.parchment),
        ),
        action: SnackBarAction(
          label: 'UNDO',
          textColor: AppColors.gold,
          onPressed: () async {
            await safeFirestoreWrite(
              context: context,
              operation: () => _userTransactions.doc(id).set(data),
            );
          },
        ),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _toggleSelectionMode() {
    setState(() {
      selectionMode = !selectionMode;
      selectedIds.clear();
    });
  }

  void _toggleSelected(String id) {
    setState(() {
      if (selectedIds.contains(id)) {
        selectedIds.remove(id);
      } else {
        selectedIds.add(id);
      }
    });
  }

  Future<void> _deleteSelected(List<QueryDocumentSnapshot> docs) async {
    final toDelete = docs.where((d) => selectedIds.contains(d.id)).toList();
    if (toDelete.isEmpty) return;

    final backup = <String, Map<String, dynamic>>{
      for (final d in toDelete) d.id: d.data() as Map<String, dynamic>,
    };

    int failCount = 0;
    for (final d in toDelete) {
      final success = await safeFirestoreWrite(
        context: context,
        operation: () => _userTransactions.doc(d.id).delete(),
      );
      if (!success) failCount++;
    }

    final count = toDelete.length - failCount;
    if (!mounted) return;

    setState(() {
      selectionMode = false;
      selectedIds.clear();
    });

    if (count > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.ink,
          content: Text(
            failCount > 0
                ? 'Deleted $count transaction${count > 1 ? 's' : ''} ($failCount failed)'
                : 'Deleted $count transaction${count > 1 ? 's' : ''}',
            style: const TextStyle(color: AppColors.parchment),
          ),
          action: SnackBarAction(
            label: 'UNDO',
            textColor: AppColors.gold,
            onPressed: () async {
              for (final entry in backup.entries) {
                await safeFirestoreWrite(
                  context: context,
                  operation: () => _userTransactions.doc(entry.key).set(entry.value),
                );
              }
            },
          ),
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('Transactions',
                  style: TextStyle(color: AppColors.parchment, fontSize: 22, fontWeight: FontWeight.w600)),
            ),
            if (!selectionMode) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: AppColors.parchment, borderRadius: BorderRadius.circular(12)),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: amountController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'Amount', border: OutlineInputBorder()),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: selectedCategory,
                            decoration: const InputDecoration(border: OutlineInputBorder()),
                            items: categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                            onChanged: (val) => setState(() => selectedCategory = val!),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: noteController,
                      decoration: const InputDecoration(labelText: 'Note', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 10),
                    if (receiptUrl != null)
                      Row(
                        children: [
                          GestureDetector(
                            onTap: () => showReceiptDialog(context, receiptUrl!),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.network(receiptUrl!, height: 50, width: 50, fit: BoxFit.cover),
                            ),
                          ),
                          const SizedBox(width: 10),
                          GestureDetector(
                            onTap: () => showReceiptDialog(context, receiptUrl!),
                            child: const Text('Receipt attached (tap to view)',
                                style: TextStyle(color: AppColors.sage, fontSize: 12)),
                          ),
                          const Spacer(),
                          IconButton(
                            icon: const Icon(Icons.close, size: 18, color: Colors.red),
                            onPressed: () => setState(() => receiptUrl = null),
                          ),
                        ],
                      )
                    else
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: isUploadingReceipt ? null : _attachReceipt,
                          icon: isUploadingReceipt
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.attach_file, size: 18, color: AppColors.sage),
                          label: Text(isUploadingReceipt ? 'Uploading...' : 'Attach receipt photo (optional)',
                              style: const TextStyle(color: AppColors.sage)),
                        ),
                      ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 42,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: AppColors.gold),
                        onPressed: isSaving ? null : _addTransaction,
                        child: isSaving
                            ? const CircularProgressIndicator(color: AppColors.ink)
                            : const Text('Add Transaction', style: TextStyle(color: AppColors.ink)),
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
            ] else
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Tap transactions below to select them',
                      style: TextStyle(color: AppColors.sage, fontSize: 12)),
                ),
              ),
            Expanded(
              child: Stack(
                children: [
                  StreamBuilder<QuerySnapshot>(
                    stream: _userTransactions.orderBy('date', descending: true).snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return const Center(
                          child: Text('Could not load transactions. Check your connection.',
                              style: TextStyle(color: AppColors.sage)),
                        );
                      }
                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator(color: AppColors.gold));
                      }
                      final docs = snapshot.data!.docs;
                      if (docs.isEmpty) {
                        return const Center(child: Text('No transactions yet', style: TextStyle(color: AppColors.sage)));
                      }
                      return ListView.builder(
                        padding: const EdgeInsets.only(right: 44),
                        itemCount: docs.length,
                        itemBuilder: (context, index) {
                          final doc = docs[index];
                          final data = doc.data() as Map<String, dynamic>;
                          final String? url = data['receiptUrl'] as String?;
                          final hasReceipt = url != null && url.isNotEmpty;
                          final isSelected = selectedIds.contains(doc.id);

                          return Card(
                            color: isSelected ? AppColors.gold.withValues(alpha: 0.35) : AppColors.parchment,
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            child: ListTile(
                              leading: selectionMode
                                  ? Checkbox(
                                value: isSelected,
                                activeColor: AppColors.gold,
                                onChanged: (_) => _toggleSelected(doc.id),
                              )
                                  : (hasReceipt
                                  ? GestureDetector(
                                onTap: () => showReceiptDialog(context, url),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: Image.network(url, width: 40, height: 40, fit: BoxFit.cover),
                                ),
                              )
                                  : null),
                              title: Text(data['category'] ?? '', style: const TextStyle(color: AppColors.ink)),
                              subtitle: Text(data['note'] ?? '', style: const TextStyle(color: AppColors.sage)),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (hasReceipt && !selectionMode)
                                    IconButton(
                                      tooltip: 'View receipt',
                                      icon: const Icon(Icons.receipt_long, color: AppColors.gold),
                                      onPressed: () => showReceiptDialog(context, url),
                                    ),
                                  CurrencyAmount(
                                    amountInInr: (data['amount'] as num).toDouble(),
                                    style: const TextStyle(color: AppColors.ink, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                              onTap: selectionMode
                                  ? () => _toggleSelected(doc.id)
                                  : () => showEditTransactionDialog(
                                context: context,
                                collection: _userTransactions,
                                docId: doc.id,
                                data: data,
                              ),
                              onLongPress: selectionMode ? null : () => _deleteTransaction(data, doc.id),
                            ),
                          );
                        },
                      );
                    },
                  ),
                  Positioned(
                    right: 0,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: GestureDetector(
                        onTap: _toggleSelectionMode,
                        child: Container(
                          width: 36,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: AppColors.ink.withValues(alpha: 0.85),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(selectionMode ? Icons.close : Icons.checklist, color: AppColors.gold, size: 20),
                              const SizedBox(height: 4),
                              Text(
                                selectionMode ? 'Cancel' : 'Select',
                                style: const TextStyle(color: AppColors.gold, fontSize: 10),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (selectionMode)
              StreamBuilder<QuerySnapshot>(
                stream: _userTransactions.orderBy('date', descending: true).snapshots(),
                builder: (context, snapshot) {
                  final docs = snapshot.data?.docs ?? [];
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: SizedBox(
                      width: double.infinity,
                      height: 46,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: selectedIds.isEmpty ? AppColors.sage : Colors.red,
                        ),
                        onPressed: selectedIds.isEmpty ? null : () => _deleteSelected(docs),
                        icon: const Icon(Icons.delete, color: Colors.white),
                        label: Text(
                          selectedIds.isEmpty ? 'Select transactions to delete' : 'Delete ${selectedIds.length} selected',
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                    ),
                  );
                },
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
    noteController.dispose();
    super.dispose();
  }
}