import 'dart:io';

void main() async {
  print('Running flutter analyze...');
  final result = await Process.run('flutter', ['analyze'], runInShell: true);
  
  final lines = result.stdout.toString().split('\n');
  final stderrLines = result.stderr.toString().split('\n');
  lines.addAll(stderrLines);

  int fixedCount = 0;

  for (final line in lines) {
    // Look for lines like:
    // error - Invalid constant value - lib\role_views\staff\staff_view.dart:1015:36 - invalid_constant
    if (line.contains('invalid_constant') && line.contains(' - ')) {
      try {
        final parts = line.split(' - ');
        // parts[0] = "  error"
        // parts[1] = "Invalid constant value"
        // parts[2] = "lib\role_views\staff\staff_view.dart:1015:36"
        final pathParts = parts[2].trim().split(':');
        if (pathParts.length >= 3) {
          final filePath = pathParts[0];
          final lineNumber = int.parse(pathParts[1]);
          final columnNumber = int.parse(pathParts[2]);

          final file = File(filePath);
          if (file.existsSync()) {
            final fileLines = file.readAsLinesSync();
            final targetLineIdx = lineNumber - 1;
            
            if (targetLineIdx >= 0 && targetLineIdx < fileLines.length) {
              String l = fileLines[targetLineIdx];
              // The error column points to the start of the invalid const expression, e.g. "const Padding("
              // Sometimes it points to the word 'const' itself, sometimes the widget name.
              // Just replace the LAST occurrence of 'const ' before the column, or ANY 'const ' on that line.
              if (l.contains('const ')) {
                // simple fix: remove all 'const ' from the line
                fileLines[targetLineIdx] = l.replaceAll('const ', '');
                file.writeAsStringSync(fileLines.join('\n') + '\n');
                fixedCount++;
                print('Fixed $filePath:$lineNumber');
              } else {
                // If the word 'const' isn't on this line, check the previous line
                if (targetLineIdx > 0 && fileLines[targetLineIdx - 1].contains('const ')) {
                  fileLines[targetLineIdx - 1] = fileLines[targetLineIdx - 1].replaceAll('const ', '');
                  file.writeAsStringSync(fileLines.join('\n') + '\n');
                  fixedCount++;
                  print('Fixed (prev line) $filePath:${lineNumber-1}');
                } else if (targetLineIdx > 1 && fileLines[targetLineIdx - 2].contains('const ')) {
                   fileLines[targetLineIdx - 2] = fileLines[targetLineIdx - 2].replaceAll('const ', '');
                  file.writeAsStringSync(fileLines.join('\n') + '\n');
                  fixedCount++;
                  print('Fixed (prev line) $filePath:${lineNumber-2}');
                }
              }
            }
          }
        }
      } catch (e) {
        // ignore parsing errors
      }
    }
  }
  
  print('Total fixes applied: $fixedCount');
}
