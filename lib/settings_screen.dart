import 'csv_export_stub.dart'
if (dart.library.html) 'csv_export_web.dart'
if (dart.library.io) 'csv_export_io.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'theme.dart';
import 'firestore_helper.dart';
import 'workspace.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final newCategoryController = TextEditingController();
  String currency = 'INR';
  List<String> customCategories = ['Food', 'Transport', 'Bills', 'Shopping', 'Health', 'Other'];
  bool loading = true;
  bool loadError = false;

  DocumentReference get _settingsDoc {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    return FirebaseFirestore.instance.collection('settings').doc(uid);
  }

  // FIXED: now scoped to the active workspace, same pattern as every
  // other screen (dashboard, budget, debt, sip, income, transactions).
  // Previously this always pointed at the personal space only, so
  // "Export CSV" and "Clear all transactions" silently ignored
  // whichever family member the user was actually viewing.
  CollectionReference get _transactions {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    return FirebaseFirestore.instance
        .collection('transactions')
        .doc('$uid${Workspace.suffix()}')
        .collection('items');
  }

  // NEW: human-readable label for whichever space is currently active,
  // used in dialogs, snackbars, and the exported filename so it's
  // obvious which data is being touched.
  String get _spaceLabel =>
      Workspace.current.value == 'family' ? Workspace.currentMember.value : 'your personal';

  @override
  void initState() {
    super.initState();
    _loadSettings();
    // NEW: rebuild this screen when workspace changes, so any
    // space-dependent labels stay accurate without navigating away
    Workspace.current.addListener(_onWorkspaceChanged);
    Workspace.currentMember.addListener(_onWorkspaceChanged);
  }

  void _onWorkspaceChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadSettings() async {
    try {
      final doc = await _settingsDoc.get();
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        setState(() {
          currency = data['currency'] ?? 'INR';
          customCategories = List<String>.from(data['categories'] ?? customCategories);
        });
      }
    } catch (e) {
      debugPrint('Settings load error: $e');
      if (mounted) setState(() => loadError = true);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _saveCurrency(String value) async {
    final previous = currency;
    setState(() => currency = value);
    final success = await safeFirestoreWrite(
      context: context,
      operation: () => _settingsDoc.set({'currency': value}, SetOptions(merge: true)),
    );
    if (!success && mounted) setState(() => currency = previous);
  }

  Future<void> _addCategory() async {
    final name = newCategoryController.text.trim();
    if (name.isEmpty || customCategories.contains(name)) return;

    final updated = [...customCategories, name];
    final success = await safeFirestoreWrite(
      context: context,
      operation: () => _settingsDoc.set({'categories': updated}, SetOptions(merge: true)),
    );
    if (success && mounted) {
      setState(() => customCategories = updated);
      newCategoryController.clear();
    }
  }

  Future<void> _removeCategory(String name) async {
    final updated = customCategories.where((c) => c != name).toList();
    final success = await safeFirestoreWrite(
      context: context,
      operation: () => _settingsDoc.set({'categories': updated}, SetOptions(merge: true)),
    );
    if (success && mounted) setState(() => customCategories = updated);
  }

  Future<void> _changePassword() async {
    final controller = TextEditingController();
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.parchment,
        title: const Text('Change password', style: TextStyle(color: AppColors.ink)),
        content: TextField(
          controller: controller,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'New password', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: AppColors.sage)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.gold),
            onPressed: () async {
              if (controller.text.length < 6) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Password must be at least 6 characters.')),
                );
                return;
              }
              final navigator = Navigator.of(context);
              final messenger = ScaffoldMessenger.of(context);
              final success = await safeAuthCall(
                context: context,
                operation: () => FirebaseAuth.instance.currentUser!.updatePassword(controller.text),
              );
              if (success) {
                navigator.pop();
                messenger.showSnackBar(const SnackBar(content: Text('Password updated')));
              }
            },
            child: const Text('Save', style: TextStyle(color: AppColors.ink)),
          ),
        ],
      ),
    );
  }

  Future<void> _exportCsv() async {
    try {
      final snapshot = await _transactions.orderBy('date', descending: true).get();
      final buffer = StringBuffer('Date,Category,Amount,Note\n');
      for (final doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final date = (data['date'] as Timestamp).toDate().toIso8601String().split('T').first;
        final note = (data['note'] ?? '').toString().replaceAll(',', ';');
        buffer.writeln('$date,${data['category']},${data['amount']},$note');
      }

      // FIXED: filename now reflects which space was exported, so
      // repeated exports across family members don't all collide
      // into the same "transactions.csv" and silently overwrite
      // each other on disk.
      final safeName = _spaceLabel.replaceAll(' ', '_').replaceAll('(', '').replaceAll(')', '');
      await downloadCsv(buffer.toString(), 'transactions_$safeName.csv');

      if (mounted) {
        showAutoDismissSnackBar(
          context,
          const SnackBar(content: Text('CSV export ready')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red.shade700,
            content: const Text('Export failed. Check your connection and try again.',
                style: TextStyle(color: Colors.white)),
          ),
        );
      }
    }
  }

  Future<void> _clearAllTransactions() async {
    // NEW: dialog now names the exact space about to be cleared,
    // since this is now correctly scoped and could be a family
    // member's data instead of the user's own.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.parchment,
        title: Text('Clear all $_spaceLabel transactions?', style: const TextStyle(color: AppColors.ink)),
        content: const Text('This deletes every transaction permanently. This cannot be undone.',
            style: TextStyle(color: AppColors.sage)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: AppColors.sage)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete all', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final snapshot = await _transactions.get();
      int failCount = 0;
      for (final doc in snapshot.docs) {
        try {
          await doc.reference.delete();
        } catch (_) {
          failCount++;
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(failCount > 0
                ? 'Cleared $_spaceLabel transactions, but $failCount failed to delete. Check your connection and retry.'
                : 'All $_spaceLabel transactions cleared'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red.shade700,
            content: const Text("Couldn't clear transactions. Check your connection and try again.",
                style: TextStyle(color: Colors.white)),
          ),
        );
      }
    }
  }

  // NEW: deletes every document in a collection, batched to stay
  // under Firestore's 500-writes-per-batch limit. Used by
  // _deleteAccount to wipe out a user's data across every
  // collection and every workspace before the auth user is removed.
  Future<void> _deleteCollection(CollectionReference collection) async {
    const batchSize = 400;
    while (true) {
      final snapshot = await collection.limit(batchSize).get();
      if (snapshot.docs.isEmpty) break;

      final batch = FirebaseFirestore.instance.batch();
      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();

      if (snapshot.docs.length < batchSize) break;
    }
  }

  // FIXED: previously this only called FirebaseAuth's delete(),
  // leaving every Firestore document (transactions, income, budgets,
  // debts, SIPs, settings, profile) orphaned under a uid nobody
  // could ever log back into. Now it actually cleans up Firestore
  // first, with an explicit choice about whether family member
  // ledgers should be wiped too, since those live under the same uid.
  Future<void> _deleteAccount() async {
    bool deleteFamilyData = false;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: AppColors.parchment,
              title: const Text('Delete account?', style: TextStyle(color: AppColors.ink)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'This permanently deletes your account and cannot be undone.',
                    style: TextStyle(color: AppColors.sage),
                  ),
                  const SizedBox(height: 16),
                  CheckboxListTile(
                    value: deleteFamilyData,
                    onChanged: (val) => setDialogState(() => deleteFamilyData = val ?? false),
                    activeColor: Colors.red,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: const Text(
                      'Also delete family member data',
                      style: TextStyle(color: AppColors.ink, fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                    subtitle: const Text(
                      'Deletes ledgers for Wife, Son, Mom, and all other family spaces too. '
                          'Leave unchecked to keep only your personal data.',
                      style: TextStyle(color: AppColors.sage, fontSize: 12),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    deleteFamilyData
                        ? 'Your personal data AND all family member data will be deleted.'
                        : 'Only your personal data will be deleted. Family member data stays in the database.',
                    style: const TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel', style: TextStyle(color: AppColors.sage)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Delete account', style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          },
        );
      },
    );
    if (confirmed != true) return;

    final uid = FirebaseAuth.instance.currentUser!.uid;

    // Build the list of uid suffixes whose data needs wiping.
    // '' always means the personal space.
    final suffixesToDelete = <String>[''];
    if (deleteFamilyData) {
      for (final m in Workspace.familyMembers) {
        final key = m.toLowerCase().replaceAll(' ', '_');
        suffixesToDelete.add('_family_$key');
      }
    }

    final firestore = FirebaseFirestore.instance;
    bool cleanupFailed = false;

    try {
      for (final suffix in suffixesToDelete) {
        final scopedUid = '$uid$suffix';

        await _deleteCollection(firestore.collection('transactions').doc(scopedUid).collection('items'));
        await _deleteCollection(firestore.collection('income').doc(scopedUid).collection('items'));
        await _deleteCollection(firestore.collection('budgets').doc(scopedUid).collection('items'));
        await _deleteCollection(firestore.collection('debts').doc(scopedUid).collection('items'));
        await _deleteCollection(firestore.collection('investments').doc(scopedUid).collection('sips'));
      }

      // These two are top-level docs keyed only by the bare uid,
      // not duplicated per workspace, so they're deleted once.
      await firestore.collection('settings').doc(uid).delete().catchError((_) => null);
      await firestore.collection('profiles').doc(uid).delete().catchError((_) => null);
    } catch (e) {
      cleanupFailed = true;
      debugPrint('Firestore cleanup error during account deletion: $e');
    }

    if (!mounted) return;

    if (cleanupFailed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.orange,
          content: Text(
            "Some data couldn't be cleaned up, but your account will still be deleted.",
            style: TextStyle(color: Colors.white),
          ),
        ),
      );
    }

    await safeAuthCall(
      context: context,
      operation: () => FirebaseAuth.instance.currentUser!.delete(),
    );
  }

  Widget _sectionCard({required String title, required List<Widget> children}) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.parchment, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: AppColors.ink, fontWeight: FontWeight.w600, fontSize: 16)),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.gold));
    }

    final user = FirebaseAuth.instance.currentUser;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(
              width: double.infinity,
              child: Text(
                'Settings',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.parchment, fontSize: 22, fontWeight: FontWeight.w600),
              ),
            ),
            if (loadError) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  "Couldn't load your saved settings. Showing defaults, check your connection.",
                  style: TextStyle(color: Colors.red, fontSize: 12),
                ),
              ),
            ],
            const SizedBox(height: 16),
            Expanded(
              child: ListView(
                children: [
                  _sectionCard(
                    title: 'Account',
                    children: [
                      Text(user?.email ?? '', style: const TextStyle(color: AppColors.sage)),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: _changePassword,
                          child: const Text('Change password', style: TextStyle(color: AppColors.ink)),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.red)),
                          onPressed: _deleteAccount,
                          child: const Text('Delete account', style: TextStyle(color: Colors.red)),
                        ),
                      ),
                    ],
                  ),
                  _sectionCard(
                    title: 'Currency',
                    children: [
                      DropdownButtonFormField<String>(
                        initialValue: currency,
                        decoration: const InputDecoration(border: OutlineInputBorder()),
                        items: const [
                          DropdownMenuItem(value: 'INR', child: Text('₹ Indian Rupee')),
                          DropdownMenuItem(value: 'USD', child: Text('\$ US Dollar')),
                          DropdownMenuItem(value: 'EUR', child: Text('€ Euro')),
                        ],
                        onChanged: (val) => _saveCurrency(val!),
                      ),
                    ],
                  ),
                  _sectionCard(
                    title: 'Categories',
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: customCategories.map((c) {
                          return Chip(
                            label: Text(c),
                            backgroundColor: AppColors.sage.withValues(alpha: 0.2),
                            deleteIcon: const Icon(Icons.close, size: 16),
                            onDeleted: () => _removeCategory(c),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: newCategoryController,
                              decoration: const InputDecoration(labelText: 'New category', border: OutlineInputBorder()),
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: AppColors.gold),
                            onPressed: _addCategory,
                            child: const Icon(Icons.add, color: AppColors.ink),
                          ),
                        ],
                      ),
                    ],
                  ),
                  _sectionCard(
                    title: 'Data',
                    children: [
                      // NEW: makes clear which space export/clear will act on
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Text(
                          'Currently viewing: $_spaceLabel',
                          style: const TextStyle(color: AppColors.sage, fontSize: 12, fontStyle: FontStyle.italic),
                        ),
                      ),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _exportCsv,
                          icon: const Icon(Icons.download, color: AppColors.ink),
                          label: const Text('Export transactions as CSV', style: TextStyle(color: AppColors.ink)),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.red)),
                          onPressed: _clearAllTransactions,
                          icon: const Icon(Icons.delete_forever, color: Colors.red),
                          label: const Text('Clear all transactions', style: TextStyle(color: Colors.red)),
                        ),
                      ),
                    ],
                  ),
                  _sectionCard(
                    title: 'About',
                    children: const [
                      Text('Personal Finance Manager', style: TextStyle(color: AppColors.ink, fontWeight: FontWeight.w600)),
                      SizedBox(height: 4),
                      Text('Version 1.0.0', style: TextStyle(color: AppColors.sage, fontSize: 12)),
                    ],
                  ),
                ],
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
    newCategoryController.dispose();
    super.dispose();
  }
}