import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'theme.dart';
import 'cloudinary_service.dart';
import 'firestore_helper.dart';

const categories = ['Food', 'Transport', 'Bills', 'Shopping', 'Health', 'Other'];

String formatDate(DateTime date) {
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${date.day} ${months[date.month - 1]} ${date.year}';
}

void showReceiptDialog(BuildContext context, String url) {
  showDialog(
    context: context,
    builder: (context) => Dialog(
      backgroundColor: Colors.transparent,
      child: Stack(
        alignment: Alignment.topRight,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(url, fit: BoxFit.contain),
          ),
          IconButton(
            icon: const CircleAvatar(backgroundColor: Colors.black54, child: Icon(Icons.close, color: Colors.white)),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    ),
  );
}

Future<void> showEditTransactionDialog({
  required BuildContext context,
  required CollectionReference collection,
  required String docId,
  required Map<String, dynamic> data,
}) async {
  final amountController = TextEditingController(text: (data['amount'] as num).toString());
  final noteController = TextEditingController(text: data['note'] ?? '');
  String category = data['category'] ?? categories.first;
  String? receiptUrl = data['receiptUrl'];
  bool isUploading = false;

  await showDialog(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setStateDialog) {
          return AlertDialog(
            backgroundColor: AppColors.parchment,
            title: const Text('Edit Transaction', style: TextStyle(color: AppColors.ink)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: amountController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Amount', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: category,
                    decoration: const InputDecoration(border: OutlineInputBorder()),
                    items: categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                    onChanged: (val) => setStateDialog(() => category = val!),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: noteController,
                    decoration: const InputDecoration(labelText: 'Note', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 16),
                  if (receiptUrl != null) ...[
                    GestureDetector(
                      onTap: () => showReceiptDialog(context, receiptUrl!),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(receiptUrl!, height: 100, fit: BoxFit.cover),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        TextButton.icon(
                          onPressed: isUploading
                              ? null
                              : () async {
                            setStateDialog(() => isUploading = true);
                            final url = await CloudinaryService.pickAndUpload();
                            setStateDialog(() {
                              if (url != null) receiptUrl = url;
                              isUploading = false;
                            });
                          },
                          icon: const Icon(Icons.refresh, size: 18, color: AppColors.sage),
                          label: const Text('Replace', style: TextStyle(color: AppColors.sage)),
                        ),
                        TextButton.icon(
                          onPressed: () => setStateDialog(() => receiptUrl = null),
                          icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                          label: const Text('Remove', style: TextStyle(color: Colors.red)),
                        ),
                      ],
                    ),
                  ] else
                    OutlinedButton.icon(
                      onPressed: isUploading
                          ? null
                          : () async {
                        setStateDialog(() => isUploading = true);
                        final url = await CloudinaryService.pickAndUpload();
                        setStateDialog(() {
                          receiptUrl = url;
                          isUploading = false;
                        });
                      },
                      icon: isUploading
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.attach_file, color: AppColors.ink),
                      label: Text(isUploading ? 'Uploading...' : 'Add receipt photo',
                          style: const TextStyle(color: AppColors.ink)),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel', style: TextStyle(color: AppColors.sage)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.gold),
                onPressed: () async {
                  final newAmount = double.tryParse(amountController.text);
                  if (newAmount == null || newAmount <= 0) return;
                  final success = await safeFirestoreWrite(
                    context: context,
                    operation: () => collection.doc(docId).update({
                      'amount': newAmount,
                      'category': category,
                      'note': noteController.text.trim(),
                      'receiptUrl': receiptUrl,
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