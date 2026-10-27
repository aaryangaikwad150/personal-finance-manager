import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'theme.dart';
import 'currency_widgets.dart';
import 'workspace.dart';
import 'firestore_helper.dart';
import 'confirm_dialog.dart';

class _DebtEntry {
  final String name;
  final double balance;
  final double rate;
  final double minPayment;
  _DebtEntry(this.name, this.balance, this.rate, this.minPayment);
}

class _PlanResult {
  final List<String> order;
  final int months;
  final double totalInterest;
  _PlanResult(this.order, this.months, this.totalInterest);
}

class DebtScreen extends StatefulWidget {
  const DebtScreen({super.key});

  @override
  State<DebtScreen> createState() => _DebtScreenState();
}

class _DebtScreenState extends State<DebtScreen> {
  final nameController = TextEditingController();
  final balanceController = TextEditingController();
  final rateController = TextEditingController();
  final minPaymentController = TextEditingController();
  final extraPaymentController = TextEditingController(text: '0');
  bool isSaving = false;

  _PlanResult? snowballResult;
  _PlanResult? avalancheResult;

  @override
  void initState() {
    super.initState();
    Workspace.current.addListener(_onWorkspaceChanged);
    Workspace.currentMember.addListener(_onWorkspaceChanged);
  }

  void _onWorkspaceChanged() {
    if (mounted) setState(() {});
  }

  CollectionReference get _debts {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    return FirebaseFirestore.instance
        .collection('debts')
        .doc('$uid${Workspace.suffix()}')
        .collection('items');
  }

  Future<void> _addDebt() async {
    final balance = double.tryParse(balanceController.text);
    final rate = double.tryParse(rateController.text);
    final minPayment = double.tryParse(minPaymentController.text);
    if (nameController.text.trim().isEmpty || balance == null || balance <= 0 ||
        rate == null || rate < 0 || minPayment == null || minPayment <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red.shade700,
          content: const Text('Please fill in all debt fields with valid values.', style: TextStyle(color: Colors.white)),
        ),
      );
      return;
    }

    setState(() => isSaving = true);

    final success = await safeFirestoreWrite(
      context: context,
      operation: () => _debts.add({
        'name': nameController.text.trim(),
        'balance': balance,
        'rate': rate,
        'minPayment': minPayment,
      }),
    );

    if (!mounted) return;

    if (success) {
      nameController.clear();
      balanceController.clear();
      rateController.clear();
      minPaymentController.clear();
      setState(() => isSaving = false);
    } else {
      setState(() => isSaving = false);
    }
  }

  Future<void> _editDebt(String docId, Map<String, dynamic> data) async {
    final editName = TextEditingController(text: data['name'] ?? '');
    final editBalance = TextEditingController(text: (data['balance'] as num).toString());
    final editRate = TextEditingController(text: (data['rate'] as num).toString());
    final editMin = TextEditingController(text: (data['minPayment'] as num).toString());

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.parchment,
        title: const Text('Edit Debt', style: TextStyle(color: AppColors.ink)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: editName, decoration: const InputDecoration(labelText: 'Name', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(controller: editBalance, keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Balance', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(controller: editRate, keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Interest rate (% per year)', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(controller: editMin, keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Minimum monthly payment', border: OutlineInputBorder())),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel', style: TextStyle(color: AppColors.sage))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.gold),
            onPressed: () async {
              final balance = double.tryParse(editBalance.text);
              final rate = double.tryParse(editRate.text);
              final minPayment = double.tryParse(editMin.text);
              if (editName.text.trim().isEmpty || balance == null || rate == null || minPayment == null) return;
              final success = await safeFirestoreWrite(
                context: context,
                operation: () => _debts.doc(docId).update({
                  'name': editName.text.trim(),
                  'balance': balance,
                  'rate': rate,
                  'minPayment': minPayment,
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

  // NEW: confirmation added before deleting a debt. The undo snackbar
  // remains as a second safety net after confirming.
  Future<void> _deleteDebt(Map<String, dynamic> data, String id) async {
    final confirmed = await showConfirmDialog(
      context: context,
      title: 'Delete debt?',
      message: '${data['name'] ?? 'This'} (balance ₹${(data['balance'] as num).toStringAsFixed(0)}) will be deleted. '
          'You can still undo right after.',
      confirmLabel: 'Delete',
      isDestructive: true,
    );
    if (!confirmed) return;
    if (!mounted) return;

    final success = await safeFirestoreWrite(
      context: context,
      operation: () => _debts.doc(id).delete(),
    );

    if (!mounted || !success) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppColors.ink,
        content: Text('Deleted ${data['name']}', style: const TextStyle(color: AppColors.parchment)),
        action: SnackBarAction(
          label: 'UNDO',
          textColor: AppColors.gold,
          onPressed: () async {
            await safeFirestoreWrite(context: context, operation: () => _debts.doc(id).set(data));
          },
        ),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  _PlanResult _simulate(List<_DebtEntry> debts, double extraPayment, bool byBalance) {
    final order = [...debts]..sort((a, b) =>
    byBalance ? a.balance.compareTo(b.balance) : b.rate.compareTo(a.rate));
    final orderNames = order.map((d) => d.name).toList();

    final balances = {for (var d in debts) d.name: d.balance};
    final minPayments = {for (var d in debts) d.name: d.minPayment};
    final rates = {for (var d in debts) d.name: d.rate};

    double totalInterest = 0;
    int month = 0;
    const capMonths = 600;

    while (balances.values.any((b) => b > 0.5) && month < capMonths) {
      month++;
      for (final name in orderNames) {
        if (balances[name]! <= 0) continue;
        final interest = balances[name]! * (rates[name]! / 100 / 12);
        balances[name] = balances[name]! + interest;
        totalInterest += interest;
      }

      final target = orderNames.firstWhere((n) => balances[n]! > 0, orElse: () => '');
      double remaining = extraPayment;
      for (final name in orderNames) {
        if (balances[name]! <= 0 || name == target) continue;
        final pay = minPayments[name]! < balances[name]! ? minPayments[name]! : balances[name]!;
        balances[name] = balances[name]! - pay;
      }
      if (target.isNotEmpty) {
        final targetBudget = minPayments[target]! + remaining;
        final pay = targetBudget < balances[target]! ? targetBudget : balances[target]!;
        balances[target] = balances[target]! - pay;
      }
    }

    return _PlanResult(orderNames, month, totalInterest);
  }

  Future<void> _comparePlans(List<_DebtEntry> debts) async {
    final extra = double.tryParse(extraPaymentController.text) ?? 0;
    setState(() {
      snowballResult = _simulate(debts, extra, true);
      avalancheResult = _simulate(debts, extra, false);
    });
  }

  Widget _planCard(String title, _PlanResult? result, Color accent) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(color: AppColors.parchment, borderRadius: BorderRadius.circular(10)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: TextStyle(color: accent, fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 8),
            if (result == null)
              const Text('Tap "Compare Plans" below', style: TextStyle(color: AppColors.sage, fontSize: 12))
            else ...[
              const Text('Pay off order:', style: TextStyle(color: AppColors.sage, fontSize: 11)),
              const SizedBox(height: 4),
              ...result.order.asMap().entries.map(
                    (e) => Text('${e.key + 1}. ${e.value}', style: const TextStyle(color: AppColors.ink, fontSize: 13)),
              ),
              const SizedBox(height: 10),
              Text('Debt-free in ${result.months} months', style: const TextStyle(color: AppColors.ink, fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Row(
                children: [
                  const Text('Total interest: ', style: TextStyle(color: AppColors.ink, fontSize: 13)),
                  CurrencyAmount(amountInInr: result.totalInterest, style: const TextStyle(color: AppColors.ink, fontSize: 13, fontWeight: FontWeight.bold)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Debt Payoff Planner',
                  style: TextStyle(color: AppColors.parchment, fontSize: 22, fontWeight: FontWeight.w600)),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: AppColors.parchment, borderRadius: BorderRadius.circular(12)),
                child: Column(
                  children: [
                    TextField(controller: nameController,
                        decoration: const InputDecoration(labelText: 'Debt name (e.g. Credit Card)', border: OutlineInputBorder())),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(child: TextField(controller: balanceController, keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'Balance', border: OutlineInputBorder()))),
                        const SizedBox(width: 8),
                        Expanded(child: TextField(controller: rateController, keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'Rate (%/yr)', border: OutlineInputBorder()))),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextField(controller: minPaymentController, keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Minimum monthly payment', border: OutlineInputBorder())),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 42,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: AppColors.gold),
                        onPressed: isSaving ? null : _addDebt,
                        child: isSaving
                            ? const CircularProgressIndicator(color: AppColors.ink)
                            : const Text('Add Debt', style: TextStyle(color: AppColors.ink)),
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
              const SizedBox(height: 12),
              SizedBox(
                height: 260,
                child: StreamBuilder<QuerySnapshot>(
                  stream: _debts.snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return const Center(
                        child: Text('Could not load debts. Check your connection.',
                            style: TextStyle(color: AppColors.sage)),
                      );
                    }
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator(color: AppColors.gold));
                    }
                    final docs = snapshot.data!.docs;
                    if (docs.isEmpty) {
                      return const Center(child: Text('No debts added yet', style: TextStyle(color: AppColors.sage)));
                    }
                    return ListView.builder(
                      itemCount: docs.length,
                      itemBuilder: (context, index) {
                        final data = docs[index].data() as Map<String, dynamic>;
                        return Card(
                          color: AppColors.parchment,
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          child: ListTile(
                            title: Text(data['name'] ?? '', style: const TextStyle(color: AppColors.ink)),
                            subtitle: Text('${data['rate']}%/yr • min ₹${(data['minPayment'] as num).toStringAsFixed(0)}/mo',
                                style: const TextStyle(color: AppColors.sage)),
                            trailing: CurrencyAmount(
                              amountInInr: (data['balance'] as num).toDouble(),
                              style: const TextStyle(color: AppColors.ink, fontWeight: FontWeight.bold),
                            ),
                            onTap: () => _editDebt(docs[index].id, data),
                            onLongPress: () => _deleteDebt(data, docs[index].id),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: extraPaymentController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Extra monthly payment (beyond minimums)',
                        border: OutlineInputBorder(),
                        filled: true,
                        fillColor: AppColors.parchment,
                        contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 22),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  StreamBuilder<QuerySnapshot>(
                    stream: _debts.snapshots(),
                    builder: (context, snapshot) {
                      final docs = snapshot.data?.docs ?? [];
                      final debts = docs.map((d) {
                        final data = d.data() as Map<String, dynamic>;
                        return _DebtEntry(data['name'], (data['balance'] as num).toDouble(),
                            (data['rate'] as num).toDouble(), (data['minPayment'] as num).toDouble());
                      }).toList();
                      return SizedBox(
                        height: 48,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: AppColors.gold),
                          onPressed: debts.isEmpty ? null : () => _comparePlans(debts),
                          child: const Text('Compare Plans', style: TextStyle(color: AppColors.ink)),
                        ),
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _planCard('Snowball (smallest first)', snowballResult, Colors.orange.shade700),
                    _planCard('Avalanche (highest rate first)', avalancheResult, Colors.green.shade700),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    Workspace.current.removeListener(_onWorkspaceChanged);
    Workspace.currentMember.removeListener(_onWorkspaceChanged);
    nameController.dispose();
    balanceController.dispose();
    rateController.dispose();
    minPaymentController.dispose();
    extraPaymentController.dispose();
    super.dispose();
  }
}