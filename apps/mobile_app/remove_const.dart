import 'dart:io';

void main() {
  final dir = Directory('lib');
  final files = dir.listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'));
  
  int totalModified = 0;

  for (final file in files) {
    String content = file.readAsStringSync();
    String original = content;

    // Use replaceAllMapped to extract group 1 correctly
    content = content.replaceAllMapped(
      RegExp(r'const\s+(TextStyle\s*\([^)]*AppTheme\.[^)]*\))', multiLine: true),
      (Match m) => m.group(1)!
    );
    content = content.replaceAllMapped(
      RegExp(r'const\s+(Icon\s*\([^)]*AppTheme\.[^)]*\))', multiLine: true),
      (Match m) => m.group(1)!
    );
    content = content.replaceAllMapped(
      RegExp(r'const\s+(BorderSide\s*\([^)]*AppTheme\.[^)]*\))', multiLine: true),
      (Match m) => m.group(1)!
    );
    content = content.replaceAllMapped(
      RegExp(r'const\s+(Divider\s*\([^)]*AppTheme\.[^)]*\))', multiLine: true),
      (Match m) => m.group(1)!
    );
    content = content.replaceAllMapped(
      RegExp(r'const\s+(CircularProgressIndicator\s*\([^)]*AppTheme\.[^)]*\))', multiLine: true),
      (Match m) => m.group(1)!
    );
    
    // Fallback cleanup
    content = content.replaceAll('const AppTheme.', 'AppTheme.');

    if (content != original) {
      file.writeAsStringSync(content);
      totalModified++;
      print('Fixed consts in ${file.path}');
    }
  }
  
  print('Total files modified: $totalModified');
}
