import 'dart:io';

void main() {
  final dir = Directory('lib');
  final files = dir.listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'));

  for (final file in files) {
    String content = file.readAsStringSync();
    bool modified = false;

    if (content.contains('const AppTheme.')) {
      content = content.replaceAll('const AppTheme.', 'AppTheme.');
      modified = true;
    }
    
    // Also check for `const [AppTheme.` which is valid, but let's be careful. Actually `const AppTheme.` is almost always invalid because AppTheme is a class.
    // Wait, `const [AppTheme.background]` is valid if the list is const. But in dart, `const` applies to the list. `[AppTheme.background]` is valid if `AppTheme.background` is const.

    if (modified) {
      file.writeAsStringSync(content);
      print('Fixed ${file.path}');
    }
  }
}
