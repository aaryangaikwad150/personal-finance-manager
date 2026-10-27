import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'theme.dart';
import 'currency_widgets.dart';
import 'workspace.dart';

const _months = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December'
];

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  DateTime selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);

  @override
  void initState() {
    super.initState();
    Workspace.current.addListener(_onWorkspaceChanged);
    Workspace.currentMember.addListener(_onWorkspaceChanged);
  }

  void _onWorkspaceChanged() {
    if (mounted) setState(() {});
  }

  CollectionReference get _transactions {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    return FirebaseFirestore.instance
        .collection('transactions')
        .doc('$uid${Workspace.suffix()}')
        .collection('items');
  }

  CollectionReference get _income {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    return FirebaseFirestore.instance
        .collection('income')
        .doc('$uid${Workspace.suffix()}')
        .collection('items');
  }

  CollectionReference get _budgets {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    return FirebaseFirestore.instance
        .collection('budgets')
        .doc('$uid${Workspace.suffix()}')
        .collection('items');
  }

  void _changeMonth(int offset) {
    setState(() {
      selectedMonth = DateTime(selectedMonth.year, selectedMonth.month + offset);
    });
  }

  bool _isSameMonth(DateTime date) =>
      date.year == selectedMonth.year && date.month == selectedMonth.month;

  Widget _statCard(String label, double value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(color: AppColors.parchment, borderRadius: BorderRadius.circular(10)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: AppColors.sage, fontSize: 12)),
            const SizedBox(height: 6),
            CurrencyAmount(
              amountInInr: value,
              style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    debugPrint('DashboardScreen build() called');
    final isCurrentMonth = _isSameMonth(DateTime.now());

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(
              width: double.infinity,
              child: Text(
                'Dashboard',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.parchment, fontSize: 22, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left, color: AppColors.parchment),
                  onPressed: () => _changeMonth(-1),
                ),
                Text('${_months[selectedMonth.month - 1]} ${selectedMonth.year}',
                    style: const TextStyle(color: AppColors.gold, fontWeight: FontWeight.w600, fontSize: 16)),
                IconButton(
                  icon: const Icon(Icons.chevron_right, color: AppColors.parchment),
                  onPressed: isCurrentMonth ? null : () => _changeMonth(1),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: _income.snapshots(),
                builder: (context, incomeSnapshot) {
                  return StreamBuilder<QuerySnapshot>(
                    stream: _transactions.snapshots(),
                    builder: (context, txSnapshot) {
                      return StreamBuilder<QuerySnapshot>(
                        stream: _budgets.snapshots(),
                        builder: (context, budgetSnapshot) {
                          if (incomeSnapshot.connectionState == ConnectionState.waiting ||
                              txSnapshot.connectionState == ConnectionState.waiting ||
                              budgetSnapshot.connectionState == ConnectionState.waiting) {
                            return const Center(child: CircularProgressIndicator(color: AppColors.gold));
                          }

                          double totalIncome = 0;
                          for (final doc in incomeSnapshot.data?.docs ?? []) {
                            final data = doc.data() as Map<String, dynamic>;
                            final date = (data['date'] as Timestamp).toDate();
                            if (_isSameMonth(date)) totalIncome += (data['amount'] as num).toDouble();
                          }

                          double totalExpense = 0;
                          final categoryTotals = <String, double>{};
                          for (final doc in txSnapshot.data?.docs ?? []) {
                            final data = doc.data() as Map<String, dynamic>;
                            final date = (data['date'] as Timestamp).toDate();
                            if (_isSameMonth(date)) {
                              final amount = (data['amount'] as num).toDouble();
                              totalExpense += amount;
                              final cat = data['category'] ?? 'Other';
                              categoryTotals[cat] = (categoryTotals[cat] ?? 0) + amount;
                            }
                          }

                          final net = totalIncome - totalExpense;
                          final savingsRate = totalIncome == 0 ? null : (net / totalIncome) * 100;

                          int budgetsSet = 0;
                          int budgetsOnTrack = 0;
                          for (final doc in budgetSnapshot.data?.docs ?? []) {
                            final data = doc.data() as Map<String, dynamic>;
                            final category = data['category'];
                            final limit = (data['limit'] as num).toDouble();
                            if (limit <= 0) continue;
                            budgetsSet++;
                            final spent = categoryTotals[category] ?? 0;
                            if (spent <= limit) budgetsOnTrack++;
                          }

                          return SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    _statCard('Income', totalIncome, AppColors.ink),
                                    _statCard('Expenses', totalExpense, AppColors.ink),
                                    _statCard('Net Savings', net, net >= 0 ? Colors.green.shade700 : Colors.red),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(
                                      child: Container(
                                        padding: const EdgeInsets.all(14),
                                        margin: const EdgeInsets.symmetric(horizontal: 4),
                                        decoration: BoxDecoration(
                                            color: AppColors.parchment, borderRadius: BorderRadius.circular(10)),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            const Text('Savings rate',
                                                style: TextStyle(color: AppColors.sage, fontSize: 12)),
                                            const SizedBox(height: 6),
                                            Text(
                                              savingsRate == null ? 'No income logged' : '${savingsRate.toStringAsFixed(1)}%',
                                              style: const TextStyle(
                                                  color: AppColors.ink, fontSize: 18, fontWeight: FontWeight.bold),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: Container(
                                        padding: const EdgeInsets.all(14),
                                        margin: const EdgeInsets.symmetric(horizontal: 4),
                                        decoration: BoxDecoration(
                                            color: AppColors.parchment, borderRadius: BorderRadius.circular(10)),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            const Text('Budget adherence',
                                                style: TextStyle(color: AppColors.sage, fontSize: 12)),
                                            const SizedBox(height: 6),
                                            Text(
                                              budgetsSet == 0 ? 'No budgets set' : '$budgetsOnTrack / $budgetsSet on track',
                                              style: const TextStyle(
                                                  color: AppColors.ink, fontSize: 18, fontWeight: FontWeight.bold),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 20),
                                const Text('By Category',
                                    style: TextStyle(color: AppColors.parchment, fontWeight: FontWeight.w600)),
                                const SizedBox(height: 12),
                                categoryTotals.isEmpty
                                    ? const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 20),
                                  child: Center(
                                    child: Text('No expenses this month',
                                        style: TextStyle(color: AppColors.sage)),
                                  ),
                                )
                                    : Column(
                                  children: categoryTotals.entries.map((entry) {
                                    final ratio = totalExpense == 0
                                        ? 0.0
                                        : (entry.value / totalExpense).clamp(0.0, 1.0);
                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 10),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Text(entry.key, style: const TextStyle(color: AppColors.parchment)),
                                              CurrencyAmount(
                                                amountInInr: entry.value,
                                                style: const TextStyle(
                                                    color: AppColors.gold, fontWeight: FontWeight.bold),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 6),
                                          ClipRRect(
                                            borderRadius: BorderRadius.circular(4),
                                            child: LinearProgressIndicator(
                                              value: ratio,
                                              minHeight: 6,
                                              backgroundColor: AppColors.sage.withValues(alpha: 0.25),
                                              valueColor: const AlwaysStoppedAnimation(AppColors.gold),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ],
                            ),
                          );
                        },
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