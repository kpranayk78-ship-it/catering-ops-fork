import 'dart:io';

void main() {
  final dir = Directory('lib');
  final files = dir.listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'));

  for (final file in files) {
    if (file.existsSync()) {
      String content = file.readAsStringSync();
      // Remove `const ` or `const\n` or `const\t`
      final newContent = content.replaceAll(RegExp(r'\bconst\s+'), '');
      if (content != newContent) {
        file.writeAsStringSync(newContent);
        print('Stripped const from ${file.path}');
      }
    }
  }
}
