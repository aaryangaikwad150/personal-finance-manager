import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'theme.dart';

/// Shows a SnackBar that reliably disappears after [duration] — no matter
/// what. Flutter's default SnackBar pauses its own dismiss timer while the
/// mouse pointer is hovering over it (intentional on web/desktop, so people
/// have time to read it), which makes it look "stuck" if your cursor happens
/// to be near the bottom of the screen. This forces it to close on schedule
/// regardless of hover state.
ScaffoldFeatureController<SnackBar, SnackBarClosedReason> showAutoDismissSnackBar(
    BuildContext context,
    SnackBar snackBar, {
      Duration? duration,
    }) {
  final messenger = ScaffoldMessenger.of(context);
  final controller = messenger.showSnackBar(snackBar);
  Future.delayed(duration ?? snackBar.duration, () {
    controller.close();
  });
  return controller;
}

/// Wraps any Firestore write (add/set/update/delete) with error handling.
///
/// - Shows a SnackBar if the write fails (permission denied, offline, etc.)
/// - Distinguishes "no internet" from other Firestore errors so the message
///   is actually useful to the user
/// - Returns true on success, false on failure, so callers can decide
///   whether to reset loading state, clear a form, close a dialog, etc.
Future<bool> safeFirestoreWrite({
  required BuildContext context,
  required Future<void> Function() operation,
  String successMessage = '',
}) async {
  try {
    await operation();
    if (successMessage.isNotEmpty && context.mounted) {
      showAutoDismissSnackBar(
        context,
        SnackBar(
          backgroundColor: AppColors.ink,
          content: Text(successMessage, style: const TextStyle(color: AppColors.parchment)),
          duration: const Duration(seconds: 2),
        ),
      );
    }
    return true;
  } on FirebaseException catch (e) {
    if (context.mounted) {
      _showErrorSnackBar(context, _messageForFirebaseException(e));
    }
    return false;
  } catch (e) {
    if (context.mounted) {
      _showErrorSnackBar(context, "Couldn't save. Check your connection and try again.");
    }
    return false;
  }
}

String _messageForFirebaseException(FirebaseException e) {
  switch (e.code) {
    case 'unavailable':
    case 'deadline-exceeded':
      return "You're offline. Changes will sync once you're back online.";
    case 'permission-denied':
      return "You don't have permission to do that. Try logging out and back in.";
    case 'not-found':
      return "That item no longer exists — it may have been deleted elsewhere.";
    case 'resource-exhausted':
      return "Too many requests right now. Please wait a moment and try again.";
    case 'unauthenticated':
      return "Your session expired. Please log in again.";
    default:
      return "Something went wrong saving that. Please try again.";
  }
}

void _showErrorSnackBar(BuildContext context, String message) {
  showAutoDismissSnackBar(
    context,
    SnackBar(
      backgroundColor: Colors.red.shade700,
      content: Text(message, style: const TextStyle(color: Colors.white)),
      duration: const Duration(seconds: 4),
    ),
  );
}

/// Same idea, but for auth calls (signup/login/password change/account
/// deletion) which throw FirebaseAuthException instead of FirebaseException.
Future<bool> safeAuthCall({
  required BuildContext context,
  required Future<void> Function() operation,
}) async {
  try {
    await operation();
    return true;
  } on FirebaseAuthException catch (e) {
    if (context.mounted) {
      _showErrorSnackBar(context, _messageForAuthException(e));
    }
    return false;
  } catch (e) {
    if (context.mounted) {
      _showErrorSnackBar(context, "Couldn't connect. Check your internet and try again.");
    }
    return false;
  }
}

String _messageForAuthException(FirebaseAuthException e) {
  switch (e.code) {
    case 'email-already-in-use':
      return "That email is already registered. Try logging in instead.";
    case 'invalid-email':
      return "That email address doesn't look right.";
    case 'weak-password':
      return "Password is too weak. Use at least 6 characters.";
    case 'user-not-found':
      return "No account found with that email. Try signing up instead.";
    case 'wrong-password':
    case 'invalid-credential':
      return "Incorrect email or password.";
    case 'too-many-requests':
      return "Too many attempts. Please wait a bit and try again.";
    case 'network-request-failed':
      return "No internet connection. Please check your network.";
    case 'requires-recent-login':
      return "For security, please log out and log back in before doing this, then try again.";
    default:
      return e.message ?? "Something went wrong. Please try again.";
  }
}