import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

Future<void> downloadCsv(String content, String filename) async {
  final directory = await getTemporaryDirectory();
  final file = File('${directory.path}/$filename');
  await file.writeAsString(content);

  await Share.shareXFiles(
    [XFile(file.path)],
    subject: 'Personal Finance Manager export',
    text: 'Your exported transactions from Personal Finance Manager',
  );
}