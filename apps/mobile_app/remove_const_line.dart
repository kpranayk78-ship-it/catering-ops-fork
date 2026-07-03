import 'dart:io';

void main() {
  final dir = Directory('lib');
  final files = dir.listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'));
  
  int totalModified = 0;

  for (final file in files) {
    List<String> lines = file.readAsLinesSync();
    bool modified = false;

    for (int i = 0; i < lines.length; i++) {
      if (lines[i].contains('AppTheme.')) {
        if (lines[i].contains('const ')) {
          lines[i] = lines[i].replaceAll('const ', '');
          modified = true;
        }
      }
      // Also catch parent lines that might have const but AppTheme is on the next line.
      // e.g. 
      // const Padding(
      //   padding: ...,
      //   child: Text(style: TextStyle(color: AppTheme.color))
      // )
      // This is hard to do line-by-line. But let's start with just removing const on the same line.
    }

    if (modified) {
      file.writeAsStringSync('${lines.join('\n')}\n');
      totalModified++;
      print('Fixed consts in ${file.path}');
    }
  }
  
  print('Total files modified: $totalModified');
}
