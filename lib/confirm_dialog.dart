import 'package:flutter/material.dart';
import 'theme.dart';

/// Shows a simple Yes/No confirmation dialog and returns true if the user
/// confirmed, false otherwise (including if they dismissed it by tapping
/// outside). Used everywhere an action is destructive or hard to undo.
///
/// Usage:
///   final confirmed = await showConfirmDialog(
///     context: context,
///     title: 'Log out?',
///     message: 'You will need to sign in again to access your data.',
///   );
///   if (!confirmed) return;
Future<bool> showConfirmDialog({
  required BuildContext context,
  required String title,
  required String message,
  String confirmLabel = 'Yes',
  String cancelLabel = 'Cancel',
  bool isDestructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: AppColors.parchment,
      title: Text(title, style: const TextStyle(color: AppColors.ink)),
      content: Text(message, style: const TextStyle(color: AppColors.sage)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(cancelLabel, style: const TextStyle(color: AppColors.sage)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: isDestructive ? Colors.red : AppColors.gold,
          ),
          onPressed: () => Navigator.pop(context, true),
          child: Text(
            confirmLabel,
            style: TextStyle(color: isDestructive ? Colors.white : AppColors.ink),
          ),
        ),
      ],
    ),
  );
  return result ?? false;
}