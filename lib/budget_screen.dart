import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'theme.dart';
import 'transaction_helpers.dart';
import 'currency_widgets.dart';
import 'workspace.dart';
import 'firestore_helper.dart';
import 'currency_helper.dart';
import 'currency_settings.dart';

class BudgetScreen extends StatefulWidget {
  const BudgetScreen({super.key});

  @override
  State<BudgetScreen> createState() => _BudgetScreenState();
}

class _BudgetScreenState extends State<BudgetScreen> {
  @override
  void initState() {
    super.initState();
    Workspace.current.addListener(_onWorkspaceChanged);
    Workspace.currentMember.addListener(_onWorkspaceChanged);
  }

  void _onWorkspaceChanged() {
    if (mounted) setState(() {});
  }

  CollectionReference get _budgets {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    return FirebaseFirestore.instance
        .collection('budgets')
        .doc('$uid${Workspace.suffix()}')
        .collection('items');
  }

  CollectionReference get _transactions {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    return FirebaseFirestore.instance
        .collection('transactions')
        .doc('$uid${Workspace.suffix()}')
        .collection('items');
  }

  Future<void> _setLimit(String category, double? currentLimitInr) async {
    // FIXED: same currency conversion issue as every other data-entry
    // screen. Budget limits are money amounts, stored in INR, but were
    // being typed and saved raw in whatever currency is selected in
    // Settings. Pre-fill the field converted into the display currency,
    // and convert back to INR before saving.
    final currentCurrency = await getCurrentCurrency();
    final displayLimit = currentLimitInr != null
        ? await CurrencyHelper.convert(currentLimitInr, currentCurrency)
        : null;

    final controller = TextEditingController(text: displayLimit?.toStringAsFixed(0) ?? '');

    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.parchment,
        title: Text('$category budget', style: const TextStyle(color: AppColors.ink)),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: 'Monthly limit (${CurrencyHelper.symbolFor(currentCurrency)})',
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          if (currentLimitInr != null)
            TextButton(
              onPressed: () async {
                final success = await safeFirestoreWrite(
                  context: context,
                  operation: () => _budgets.doc(category).delete(),
                );
                if (success && context.mounted) Navigator.pop(context);
              },
              child: const Text('Remove limit', style: TextStyle(color: Colors.red)),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: AppColors.sage)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.gold),
            onPressed: () async {
              final enteredLimit = double.tryParse(controller.text);
              if (enteredLimit == null || enteredLimit <= 0) return;

              // FIXED: convert the typed limit back to INR before saving,
              // matching how balances/amounts are stored everywhere else.
              final limitInInr = await CurrencyHelper.toInr(enteredLimit, currentCurrency);

              final success = await safeFirestoreWrite(
                context: context,
                operation: () => _budgets.doc(category).set({'category': category, 'limit': limitInInr}),
              );
              if (success && context.mounted) Navigator.pop(context);
            },
            child: const Text('Save', style: TextStyle(color: AppColors.ink)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(
              width: double.infinity,
              child: Text(
                'Budgets',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.parchment, fontSize: 22, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 4),
            const Text('Tap a category to set its monthly limit',
                style: TextStyle(color: AppColors.sage, fontSize: 12)),
            const SizedBox(height: 16),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: _budgets.snapshots(),
                builder: (context, budgetSnapshot) {
                  if (budgetSnapshot.hasError) {
                    return const Center(
                      child: Text('Could not load budgets. Check your connection.',
                          style: TextStyle(color: AppColors.sage)),
                    );
                  }

                  final budgetLimits = <String, double>{};
                  if (budgetSnapshot.hasData) {
                    for (final doc in budgetSnapshot.data!.docs) {
                      final data = doc.data() as Map<String, dynamic>;
                      budgetLimits[data['category']] = (data['limit'] as num).toDouble();
                    }
                  }

                  return StreamBuilder<QuerySnapshot>(
                    stream: _transactions.snapshots(),
                    builder: (context, txSnapshot) {
                      if (txSnapshot.hasError) {
                        return const Center(
                          child: Text('Could not load transactions. Check your connection.',
                              style: TextStyle(color: AppColors.sage)),
                        );
                      }
                      if (!txSnapshot.hasData) {
                        return const Center(child: CircularProgressIndicator(color: AppColors.gold));
                      }

                      final spentByCategory = <String, double>{};
                      for (final doc in txSnapshot.data!.docs) {
                        final data = doc.data() as Map<String, dynamic>;
                        final date = (data['date'] as Timestamp).toDate();
                        if (date.month == now.month && date.year == now.year) {
                          final cat = data['category'] ?? 'Other';
                          final amount = (data['amount'] as num).toDouble();
                          spentByCategory[cat] = (spentByCategory[cat] ?? 0) + amount;
                        }
                      }

                      return ListView(
                        children: categories.map((category) {
                          final limit = budgetLimits[category];
                          final spent = spentByCategory[category] ?? 0;
                          final hasLimit = limit != null && limit > 0;
                          final ratio = hasLimit ? (spent / limit).clamp(0.0, 1.5) : 0.0;
                          final isOver = hasLimit && spent > limit;
                          final textColor = isOver ? Colors.red : AppColors.ink;

                          return InkWell(
                            onTap: () => _setLimit(category, limit),
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: AppColors.parchment,
                                borderRadius: BorderRadius.circular(10),
                                border: isOver ? Border.all(color: Colors.red, width: 1.5) : null,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(category, style: const TextStyle(color: AppColors.ink, fontWeight: FontWeight.w600)),
                                      hasLimit
                                          ? Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          CurrencyAmount(
                                              amountInInr: spent,
                                              style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
                                          Text(' / ', style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
                                          CurrencyAmount(
                                              amountInInr: limit,
                                              style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
                                        ],
                                      )
                                          : Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          CurrencyAmount(
                                              amountInInr: spent,
                                              style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
                                          Text(' • no limit set',
                                              style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
                                        ],
                                      ),
                                    ],
                                  ),
                                  if (hasLimit) ...[
                                    const SizedBox(height: 8),
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(6),
                                      child: LinearProgressIndicator(
                                        value: ratio > 1 ? 1 : ratio,
                                        minHeight: 8,
                                        backgroundColor: AppColors.sage.withValues(alpha:0.25),
                                        valueColor: AlwaysStoppedAnimation(isOver ? Colors.red : AppColors.gold),
                                      ),
                                    ),
                                    if (isOver) ...[
                                      const SizedBox(height: 6),
                                      Row(
                                        children: [
                                          const Text('Over budget by ',
                                              style: TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.w600)),
                                          CurrencyAmount(
                                            amountInInr: spent - limit,
                                            style: const TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.w600),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ],
                                ],
                              ),
                            ),
                          );
                        }).toList(),
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
    super.dispose();
  }
}