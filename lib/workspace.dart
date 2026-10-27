import 'package:flutter/foundation.dart';

/// Tracks which data space is active.
/// 'personal' = your own data (unchanged, original path).
/// 'family' + a selected member = a separate ledger per family member,
/// all still under YOUR single login, nobody else logs in.
class Workspace {
  static final ValueNotifier<String> current = ValueNotifier<String>('personal');
  static final ValueNotifier<String> currentMember = ValueNotifier<String>('Wife');

  static const List<String> familyMembers = [
    'Wife', 'Son', 'Mom', 'Dad', 'Grandfather', 'Grandmother', 'Brother','Sister'
  ];

  ///Appended to the user's uid to build the Firestore path.
  static String suffix() {
    if (current.value != 'family') return '';
    final memberKey = currentMember.value.toLowerCase().replaceAll(' ', '_');
    return '_family_$memberKey';
  }

  static bool get isFamily => current.value == 'family';
  static void setPersonal() => current.value = 'personal';
  static void setFamily() => current.value = 'family';
  static void setMember(String member) => currentMember.value = member;
  /// Returns every space that exists: personal + each family member,
  /// as (label, suffix) pairs, for building a full-household picture.
  static List<MapEntry<String, String>> allSpaces() {
    final list = <MapEntry<String, String>>[const MapEntry('You (Personal)', '')];
    for (final m in familyMembers) {
      final key = m.toLowerCase().replaceAll(' ', '_');
      list.add(MapEntry(m, '_family_$key'));
    }
    return list;
  }
}