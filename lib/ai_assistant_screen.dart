import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'theme.dart';
import 'gemini_service.dart';
import 'workspace.dart';
import 'firestore_helper.dart';
import 'transaction_helpers.dart';

class _AiResponse {
  final String reply;
  final Map<String, dynamic>? action;
  _AiResponse(this.reply, this.action);
}

class AiAssistantScreen extends StatefulWidget {
  const AiAssistantScreen({super.key});

  @override
  State<AiAssistantScreen> createState() => _AiAssistantScreenState();
}

class _AiAssistantScreenState extends State<AiAssistantScreen> {
  final questionController = TextEditingController();
  bool isAsking = false;

  @override
  void initState() {
    super.initState();
    Workspace.current.addListener(_onWorkspaceChanged);
    Workspace.currentMember.addListener(_onWorkspaceChanged);
  }

  void _onWorkspaceChanged() {
    if (mounted) setState(() {});
  }

  String get _speakerLabel => Workspace.isFamily ? Workspace.currentMember.value : 'You';

  String get _spaceId {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    return '$uid${Workspace.suffix()}';
  }

  CollectionReference<Map<String, dynamic>> _messagesFor(String spaceId) {
    return FirebaseFirestore.instance.collection('chats').doc(spaceId).collection('messages');
  }

  CollectionReference<Map<String, dynamic>> get _messages => _messagesFor(_spaceId);

  CollectionReference<Map<String, dynamic>> _items(String collection, String spaceId) {
    return FirebaseFirestore.instance.collection(collection).doc(spaceId).collection('items');
  }

  // ---------------------------------------------------------------------------
  // Context for the AI (active space only)
  // ---------------------------------------------------------------------------

  Future<String> _buildContextForSpace(String label, String spaceId) async {
    final now = DateTime.now();
    final db = FirebaseFirestore.instance;

    final txSnap = await _items('transactions', spaceId).get();
    final incomeSnap = await _items('income', spaceId).get();
    final budgetSnap = await _items('budgets', spaceId).get();
    final sipSnap = await db.collection('investments').doc(spaceId).collection('sips').get();
    final debtSnap = await _items('debts', spaceId).get();

    double totalIncome = 0;
    for (final doc in incomeSnap.docs) {
      final data = doc.data();
      final date = (data['date'] as Timestamp).toDate();
      if (date.month == now.month && date.year == now.year) {
        totalIncome += (data['amount'] as num).toDouble();
      }
    }

    double totalExpense = 0;
    final categoryTotals = <String, double>{};
    final txRows = <MapEntry<DateTime, String>>[];
    for (final doc in txSnap.docs) {
      final data = doc.data();
      final date = (data['date'] as Timestamp).toDate();
      final amount = (data['amount'] as num).toDouble();
      final cat = data['category'] ?? 'Other';
      final note = (data['note'] ?? '').toString();
      txRows.add(MapEntry(
        date,
        '- ${formatDate(date)} | $cat | ₹${amount.toStringAsFixed(0)}${note.isEmpty ? '' : ' | $note'}',
      ));
      if (date.month == now.month && date.year == now.year) {
        totalExpense += amount;
        categoryTotals[cat] = (categoryTotals[cat] ?? 0) + amount;
      }
    }
    txRows.sort((a, b) => b.key.compareTo(a.key));
    final recentLines = txRows.take(40).map((e) => e.value).join('\n');

    final budgetLines = <String>[];
    for (final doc in budgetSnap.docs) {
      final data = doc.data();
      final category = data['category'];
      final limit = (data['limit'] as num).toDouble();
      final spent = categoryTotals[category] ?? 0;
      budgetLines.add('$category limit ₹${limit.toStringAsFixed(0)} (spent ₹${spent.toStringAsFixed(0)})');
    }

    double totalMonthlySip = 0;
    final sipLines = <String>[];
    for (final doc in sipSnap.docs) {
      final data = doc.data();
      final amount = (data['monthlyAmount'] as num).toDouble();
      totalMonthlySip += amount;
      sipLines.add('${data['fundName']} (₹${amount.toStringAsFixed(0)}/mo)');
    }

    double totalDebt = 0;
    final debtLines = <String>[];
    for (final doc in debtSnap.docs) {
      final data = doc.data();
      final balance = (data['balance'] as num).toDouble();
      totalDebt += balance;
      debtLines.add('${data['name']} ₹${balance.toStringAsFixed(0)} at ${data['rate']}%/yr');
    }

    final categoryText =
    categoryTotals.entries.map((e) => '${e.key}: ₹${e.value.toStringAsFixed(0)}').join(', ');

    return '--- $label ---\n'
        'Today: ${formatDate(now)}\n'
        'Income this month: ₹${totalIncome.toStringAsFixed(0)}\n'
        'Expenses this month: ₹${totalExpense.toStringAsFixed(0)}${categoryText.isEmpty ? '' : ' ($categoryText)'}\n'
        'Budgets: ${budgetLines.isEmpty ? 'none set' : budgetLines.join('; ')}\n'
        'SIP investments: ${sipLines.isEmpty ? 'none' : '${sipLines.join(', ')} | total ₹${totalMonthlySip.toStringAsFixed(0)}/mo'}\n'
        'Debts: ${debtLines.isEmpty ? 'none' : '${debtLines.join(', ')} | total balance ₹${totalDebt.toStringAsFixed(0)}'}\n'
        'Recent expenses (newest first):\n${recentLines.isEmpty ? 'none' : recentLines}';
  }

  // ---------------------------------------------------------------------------
  // Prompt and response parsing
  // ---------------------------------------------------------------------------

  String _wrapPrompt(String userText) {
    return '''
You are the assistant inside a personal finance app. The user can ask questions or give commands.
Respond with ONLY one JSON object and nothing else (no markdown, no code fences):
{"reply": "short friendly message", "action": null}
or
{"reply": "short message describing what you are about to do", "action": {...}}

Allowed action objects:
{"type":"add_expense","amount":200,"category":"Food","note":"lunch","date":"2026-10-25"}
{"type":"add_income","amount":50000,"source":"Salary","date":"2026-10-25"}
{"type":"delete_expense","category":"Bills","amount":200,"note_contains":"","all":false}
{"type":"set_budget","category":"Food","limit":5000}
{"type":"remove_budget","category":"Food"}

Rules:
- Valid categories: ${categories.join(', ')}. Use Other if unsure.
- Amounts are plain numbers in rupees.
- "date" is optional, format YYYY-MM-DD. The default is today.
- For delete_expense, include only the fields the user mentioned. Set "all" to true only if the user asks to delete every matching expense.
- If the message is a question, answer it from the finance data and use "action": null.
- If a command is missing a required detail (for example the amount), ask for it in "reply" and use "action": null.
- Never say an action is already done. The app asks the user to confirm first.
- You can only perform the actions listed above. For anything else, explain politely.

User message: $userText
''';
  }

  _AiResponse _parse(String raw) {
    try {
      final start = raw.indexOf('{');
      final end = raw.lastIndexOf('}');
      if (start == -1 || end <= start) return _AiResponse(raw.trim(), null);
      final map = jsonDecode(raw.substring(start, end + 1)) as Map<String, dynamic>;
      final reply = (map['reply'] ?? '').toString().trim();
      final action = map['action'];
      return _AiResponse(
        reply.isEmpty ? 'Okay.' : reply,
        action is Map<String, dynamic> ? action : null,
      );
    } catch (_) {
      return _AiResponse(raw.trim(), null);
    }
  }

  // ---------------------------------------------------------------------------
  // Asking
  // ---------------------------------------------------------------------------

  Future<void> _ask() async {
    final question = questionController.text.trim();
    if (question.isEmpty || isAsking) return;

    // Lock in the active space now, so everything goes to the right person
    // even if the sidebar is switched while waiting.
    final spaceId = _spaceId;
    final label = _speakerLabel;
    final chat = _messagesFor(spaceId);

    setState(() => isAsking = true);
    questionController.clear();

    try {
      final financeContext = await _buildContextForSpace(label, spaceId);
      final raw = await GeminiService.askQuestion(_wrapPrompt(question), financeContext);
      final parsed = _parse(raw);

      await chat.add({
        'question': question,
        'answer': parsed.reply,
        'createdAt': Timestamp.now(),
      });

      if (parsed.action != null && mounted) {
        await _runAction(spaceId, chat, parsed.action!);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red.shade700,
            content: const Text("Couldn't get an answer. Check your connection and try again.",
                style: TextStyle(color: Colors.white)),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => isAsking = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  double? _num(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '');
  }

  String _normCategory(dynamic c) {
    final text = (c ?? '').toString().trim().toLowerCase();
    for (final cat in categories) {
      if (cat.toLowerCase() == text) return cat;
    }
    return 'Other';
  }

  DateTime _date(dynamic v) {
    final parsed = DateTime.tryParse((v ?? '').toString());
    return parsed ?? DateTime.now();
  }

  Future<void> _postResult(CollectionReference<Map<String, dynamic>> chat, String text) {
    return chat.add({'question': '', 'answer': text, 'createdAt': Timestamp.now()});
  }

  Future<bool> _confirm(String title, String message, {bool danger = false}) async {
    if (!mounted) return false;
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.parchment,
        title: Text(title, style: const TextStyle(color: AppColors.ink)),
        content: Text(message, style: const TextStyle(color: AppColors.ink)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: AppColors.sage)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: danger ? Colors.red : AppColors.gold),
            onPressed: () => Navigator.pop(context, true),
            child: Text('Confirm', style: TextStyle(color: danger ? Colors.white : AppColors.ink)),
          ),
        ],
      ),
    );
    return result == true;
  }

  Future<void> _runAction(
      String spaceId,
      CollectionReference<Map<String, dynamic>> chat,
      Map<String, dynamic> action,
      ) async {
    final type = (action['type'] ?? '').toString();

    switch (type) {
      case 'add_expense':
        await _addExpense(spaceId, chat, action);
        break;
      case 'add_income':
        await _addIncome(spaceId, chat, action);
        break;
      case 'delete_expense':
        await _deleteExpense(spaceId, chat, action);
        break;
      case 'set_budget':
        await _setBudget(spaceId, chat, action);
        break;
      case 'remove_budget':
        await _removeBudget(spaceId, chat, action);
        break;
      default:
        await _postResult(chat, "I can't do that action yet.");
    }
  }

  Future<void> _addExpense(
      String spaceId, CollectionReference<Map<String, dynamic>> chat, Map<String, dynamic> a) async {
    final amount = _num(a['amount']);
    if (amount == null || amount <= 0) {
      await _postResult(chat, 'I could not read the amount. Please say it again.');
      return;
    }
    final category = _normCategory(a['category']);
    final note = (a['note'] ?? '').toString().trim();
    final date = _date(a['date']);

    final ok = await _confirm(
      'Add expense?',
      '₹${amount.toStringAsFixed(2)} in $category${note.isEmpty ? '' : ' ($note)'} on ${formatDate(date)}',
    );
    if (!ok || !mounted) {
      await _postResult(chat, 'Cancelled. Nothing was added.');
      return;
    }

    final success = await safeFirestoreWrite(
      context: context,
      operation: () => _items('transactions', spaceId).add({
        'amount': amount,
        'category': category,
        'note': note,
        'date': Timestamp.fromDate(date),
        'receiptUrl': null,
      }),
    );
    await _postResult(
      chat,
      success
          ? 'Done. Added ₹${amount.toStringAsFixed(2)} to $category.'
          : 'That did not save. Please try again.',
    );
  }

  Future<void> _addIncome(
      String spaceId, CollectionReference<Map<String, dynamic>> chat, Map<String, dynamic> a) async {
    final amount = _num(a['amount']);
    if (amount == null || amount <= 0) {
      await _postResult(chat, 'I could not read the amount. Please say it again.');
      return;
    }
    final source = (a['source'] ?? '').toString().trim().isEmpty ? 'Income' : a['source'].toString().trim();
    final date = _date(a['date']);

    final ok = await _confirm(
      'Add income?',
      '₹${amount.toStringAsFixed(2)} from $source on ${formatDate(date)}',
    );
    if (!ok || !mounted) {
      await _postResult(chat, 'Cancelled. Nothing was added.');
      return;
    }

    final success = await safeFirestoreWrite(
      context: context,
      operation: () => _items('income', spaceId).add({
        'amount': amount,
        'source': source,
        'date': Timestamp.fromDate(date),
      }),
    );
    await _postResult(
      chat,
      success
          ? 'Done. Added ₹${amount.toStringAsFixed(2)} income from $source.'
          : 'That did not save. Please try again.',
    );
  }

  Future<void> _deleteExpense(
      String spaceId, CollectionReference<Map<String, dynamic>> chat, Map<String, dynamic> a) async {
    final wantCategory = (a['category'] ?? '').toString().trim().toLowerCase();
    final wantAmount = _num(a['amount']);
    final wantNote = (a['note_contains'] ?? '').toString().trim().toLowerCase();
    final deleteAll = a['all'] == true;

    final snap = await _items('transactions', spaceId).get();
    var matches = snap.docs.where((d) {
      final data = d.data();
      if (wantCategory.isNotEmpty && (data['category'] ?? '').toString().toLowerCase() != wantCategory) {
        return false;
      }
      if (wantAmount != null && ((data['amount'] as num).toDouble() - wantAmount).abs() > 0.01) {
        return false;
      }
      if (wantNote.isNotEmpty && !(data['note'] ?? '').toString().toLowerCase().contains(wantNote)) {
        return false;
      }
      return true;
    }).toList();

    if (matches.isEmpty) {
      await _postResult(chat, 'I could not find a matching transaction.');
      return;
    }

    matches.sort((x, y) => (y.data()['date'] as Timestamp).compareTo(x.data()['date'] as Timestamp));
    if (!deleteAll) matches = [matches.first];

    final lines = matches.take(6).map((d) {
      final data = d.data();
      final date = (data['date'] as Timestamp).toDate();
      return '${formatDate(date)} | ${data['category']} | ₹${(data['amount'] as num).toStringAsFixed(2)}';
    }).join('\n');
    final extra = matches.length > 6 ? '\n...and ${matches.length - 6} more' : '';

    final ok = await _confirm(
      'Delete ${matches.length} transaction${matches.length > 1 ? 's' : ''}?',
      '$lines$extra',
      danger: true,
    );
    if (!ok || !mounted) {
      await _postResult(chat, 'Cancelled. Nothing was deleted.');
      return;
    }

    final backup = <String, Map<String, dynamic>>{for (final d in matches) d.id: d.data()};
    int deleted = 0;
    for (final d in matches) {
      if (!mounted) break;
      final success = await safeFirestoreWrite(context: context, operation: () => d.reference.delete());
      if (success) deleted++;
    }

    await _postResult(chat, 'Done. Deleted $deleted transaction${deleted == 1 ? '' : 's'}.');

    if (!mounted || deleted == 0) return;

    // Swap out any snackbar already on screen, then show a short one that
    // always closes on time, even if the mouse is hovering over it.
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    showAutoDismissSnackBar(
      context,
      SnackBar(
        backgroundColor: AppColors.ink,
        content: Text('Deleted $deleted transaction${deleted == 1 ? '' : 's'}',
            style: const TextStyle(color: AppColors.parchment)),
        action: SnackBarAction(
          label: 'UNDO',
          textColor: AppColors.gold,
          onPressed: () async {
            for (final entry in backup.entries) {
              await _items('transactions', spaceId).doc(entry.key).set(entry.value);
            }
            await _postResult(chat, 'Undone. Restored $deleted transaction${deleted == 1 ? '' : 's'}.');
          },
        ),
        duration: const Duration(seconds: 4),
      ),
      duration: const Duration(seconds: 4),
    );
  }

  Future<void> _setBudget(
      String spaceId, CollectionReference<Map<String, dynamic>> chat, Map<String, dynamic> a) async {
    final limit = _num(a['limit']);
    if (limit == null || limit <= 0) {
      await _postResult(chat, 'I could not read the budget amount. Please say it again.');
      return;
    }
    final category = _normCategory(a['category']);

    final ok = await _confirm('Set budget?', '$category monthly limit: ₹${limit.toStringAsFixed(0)}');
    if (!ok || !mounted) {
      await _postResult(chat, 'Cancelled. Budget unchanged.');
      return;
    }

    final success = await safeFirestoreWrite(
      context: context,
      operation: () => _items('budgets', spaceId).doc(category).set({'category': category, 'limit': limit}),
    );
    await _postResult(
      chat,
      success
          ? 'Done. $category budget is now ₹${limit.toStringAsFixed(0)} per month.'
          : 'That did not save. Please try again.',
    );
  }

  Future<void> _removeBudget(
      String spaceId, CollectionReference<Map<String, dynamic>> chat, Map<String, dynamic> a) async {
    final category = _normCategory(a['category']);

    final ok = await _confirm('Remove budget?', 'Remove the $category monthly limit?', danger: true);
    if (!ok || !mounted) {
      await _postResult(chat, 'Cancelled. Budget unchanged.');
      return;
    }

    final success = await safeFirestoreWrite(
      context: context,
      operation: () => _items('budgets', spaceId).doc(category).delete(),
    );
    await _postResult(
      chat,
      success ? 'Done. Removed the $category budget.' : 'That did not work. Please try again.',
    );
  }

  // ---------------------------------------------------------------------------
  // Clear chat
  // ---------------------------------------------------------------------------

  Future<void> _clearChat() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.parchment,
        title: Text('Clear $_speakerLabel chat?', style: const TextStyle(color: AppColors.ink)),
        content: const Text('This deletes the AI chat history for this person only.',
            style: TextStyle(color: AppColors.sage)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: AppColors.sage)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    await safeFirestoreWrite(
      context: context,
      operation: () async {
        final snap = await _messages.get();
        for (final doc in snap.docs) {
          await doc.reference.delete();
        }
      },
    );
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.auto_awesome, color: AppColors.gold),
                const SizedBox(width: 8),
                const Text('AI Assistant',
                    style: TextStyle(color: AppColors.parchment, fontSize: 22, fontWeight: FontWeight.w600)),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.only(right: 56),
                  child: TextButton.icon(
                    onPressed: _clearChat,
                    icon: const Icon(Icons.delete_outline, size: 18, color: AppColors.sage),
                    label: const Text('Clear chat', style: TextStyle(color: AppColors.sage, fontSize: 12)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              Workspace.isFamily
                  ? 'Private chat for ${Workspace.currentMember.value}. Only their finances are used.'
                  : 'Your private chat. Only your finances are used.',
              style: const TextStyle(color: AppColors.sage, fontSize: 12),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                key: ValueKey(_spaceId),
                stream: _messages.orderBy('createdAt', descending: true).snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    debugPrint('Chat load error: ${snapshot.error}');
                    return const Center(
                      child: Text('Could not load chat. Check your connection.',
                          style: TextStyle(color: AppColors.sage)),
                    );
                  }
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator(color: AppColors.gold));
                  }

                  final docs = snapshot.data?.docs ?? [];
                  if (docs.isEmpty) {
                    return const Center(
                      child: Text(
                        'Ask a question or give a command:\n'
                            '"How much did I spend this month?"\n'
                            '"Add 250 for lunch"\n'
                            '"Delete the bills transaction of 200 rs"\n'
                            '"Set food budget to 6000"',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.sage),
                      ),
                    );
                  }

                  return ListView.builder(
                    reverse: true,
                    itemCount: docs.length,
                    itemBuilder: (context, index) {
                      final data = docs[index].data() as Map<String, dynamic>;
                      final question = (data['question'] ?? '').toString();
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (question.isNotEmpty) ...[
                              Align(
                                alignment: Alignment.centerRight,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: AppColors.gold,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(question, style: const TextStyle(color: AppColors.ink)),
                                ),
                              ),
                              const SizedBox(height: 8),
                            ],
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: AppColors.parchment,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text((data['answer'] ?? '').toString(),
                                  style: const TextStyle(color: AppColors.ink)),
                            ),
                          ],
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
                    controller: questionController,
                    decoration: InputDecoration(
                      hintText: Workspace.isFamily
                          ? 'Ask or command for ${Workspace.currentMember.value}...'
                          : 'Ask a question or give a command...',
                      filled: true,
                      fillColor: AppColors.parchment,
                      border: const OutlineInputBorder(borderSide: BorderSide.none),
                    ),
                    onSubmitted: (_) => _ask(),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.gold),
                    onPressed: isAsking ? null : _ask,
                    child: isAsking
                        ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(color: AppColors.ink, strokeWidth: 2))
                        : const Icon(Icons.send, color: AppColors.ink),
                  ),
                ),
              ],
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
    questionController.dispose();
    super.dispose();
  }
}