import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'theme.dart';
import 'workspace.dart';
import 'dashboard_screen.dart';
import 'transactions_screen.dart';
import 'history_screen.dart';
import 'sip_screen.dart';
import 'budget_screen.dart';
import 'settings_screen.dart';
import 'income_screen.dart';
import 'profile_screen.dart';
import 'debt_screen.dart';
import 'ai_assistant_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int selectedIndex = 0;

  final pages = const [
    DashboardScreen(),
    TransactionsScreen(),
    IncomeScreen(),
    HistoryScreen(),
    SipScreen(),
    BudgetScreen(),
    DebtScreen(),
    AiAssistantScreen(),
    SettingsScreen(),
  ];
  final icons = const [
    Icons.dashboard_rounded,
    Icons.add_circle_rounded,
    Icons.account_balance_wallet_rounded,
    Icons.receipt_long_rounded,
    Icons.trending_up_rounded,
    Icons.pie_chart_rounded,
    Icons.trending_down_rounded,
    Icons.auto_awesome,
    Icons.settings_rounded,
  ];
  final labels = const [
    'Dashboard',
    'Add Transaction',
    'Income',
    'History',
    'SIP Investments',
    'Budgets',
    'Debt Planner',
    'AI Assistant',
    'Settings',
  ];

  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.parchment,
        title: const Text('Log out?', style: TextStyle(color: AppColors.ink)),
        content: const Text(
          'Are you sure you want to log out?',
          style: TextStyle(color: AppColors.sage),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: AppColors.sage)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Logout', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await FirebaseAuth.instance.signOut();
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.gold),
        actions: [
          PopupMenuButton<String>(
            offset: const Offset(0, 45),
            icon: const CircleAvatar(
              radius: 18,
              backgroundColor: AppColors.gold,
              child: Icon(Icons.person, color: AppColors.ink),
            ),
            onSelected: (value) async {
              if (value == 'logout') {
                _confirmLogout();
              } else if (value == 'profile') {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => Scaffold(body: AppBackground(child: const ProfileScreen()))),
                );
              } else if (value == 'settings') {
                setState(() => selectedIndex = labels.indexOf('Settings'));
              } else if (value == 'about') {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    backgroundColor: AppColors.parchment,
                    title: const Text('About', style: TextStyle(color: AppColors.ink)),
                    content: const Text(
                      'Personal Finance Manager\nVersion 1.0.0\n\nBuilt with Flutter and Firebase.',
                      style: TextStyle(color: AppColors.sage),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Close', style: TextStyle(color: AppColors.gold)),
                      ),
                    ],
                  ),
                );
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                enabled: false,
                child: Text(user?.email ?? '', style: const TextStyle(fontSize: 12, color: AppColors.sage)),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(value: 'profile', child: Text('Profile')),
              const PopupMenuItem(value: 'settings', child: Text('Settings')),
              const PopupMenuItem(value: 'about', child: Text('About')),
              const PopupMenuDivider(),
              const PopupMenuItem(value: 'logout', child: Text('Logout')),
            ],
          ),
          const SizedBox(width: 12),
        ],
      ),
      drawer: Drawer(
        backgroundColor: AppColors.ink.withValues(alpha: 0.98),
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 8),
              // Own / Family workspace toggle, with member sub-selector when Family is active
              ValueListenableBuilder<String>(
                valueListenable: Workspace.current,
                builder: (context, value, _) {
                  Widget pill(String label, IconData icon, bool selected, VoidCallback onTap) {
                    return InkWell(
                      onTap: onTap,
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                        decoration: BoxDecoration(
                          color: selected ? AppColors.gold.withValues(alpha: 0.2) : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: selected ? AppColors.gold : AppColors.parchment.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(icon, size: 16, color: selected ? AppColors.gold : AppColors.parchment),
                            const SizedBox(width: 6),
                            Text(label,
                                style: TextStyle(
                                    fontSize: 12,
                                    color: selected ? AppColors.gold : AppColors.parchment)),
                          ],
                        ),
                      ),
                    );
                  }

                  return Column(
                    children: [
                      pill('Own', Icons.person, value == 'personal', () => Workspace.setPersonal()),
                      pill('Family', Icons.groups, value == 'family', () => Workspace.setFamily()),
                      if (value == 'family')
                        ValueListenableBuilder<String>(
                          valueListenable: Workspace.currentMember,
                          builder: (context, member, _) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              child: Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: Workspace.familyMembers.map((m) {
                                  final selected = member == m;
                                  return GestureDetector(
                                    onTap: () => Workspace.setMember(m),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: selected ? AppColors.gold : AppColors.parchment.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(m,
                                          style: TextStyle(
                                              fontSize: 10,
                                              color: selected ? AppColors.ink : AppColors.parchment)),
                                    ),
                                  );
                                }).toList(),
                              ),
                            );
                          },
                        ),
                    ],
                  );
                },
              ),
              const Divider(color: AppColors.sage, height: 20, indent: 12, endIndent: 12),
              Expanded(
                child: ListView.builder(
                  itemCount: labels.length,
                  itemBuilder: (context, i) {
                    final selected = selectedIndex == i;
                    return InkWell(
                      onTap: () {
                        setState(() => selectedIndex = i);
                        Navigator.of(context).pop();
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(icons[i], size: 22, color: selected ? AppColors.gold : AppColors.parchment),
                            const SizedBox(width: 14),
                            Flexible(
                              child: Text(
                                labels[i],
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: selected ? AppColors.gold : AppColors.parchment,
                                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
      body: AppBackground(
        child: IndexedStack(
          index: selectedIndex,
          children: pages,
        ),
      ),
    );
  }
}