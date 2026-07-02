import 'dart:io';

void main() {
  final dir = Directory('lib');
  final files = dir.listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart') && !f.path.contains('app_theme.dart') && !f.path.contains('main.dart'));

  for (final file in files) {
    String content = file.readAsStringSync();
    bool modified = false;

    // Background colors -> AppTheme.background
    final bgRegExp = RegExp(r'Color\(0xFF161626\)|Color\(0xFF1A1A2E\)|Color\(0xFF1E1E2C\)');
    if (bgRegExp.hasMatch(content)) {
      content = content.replaceAll(bgRegExp, 'AppTheme.background');
      modified = true;
    }

    // Card colors -> AppTheme.cardColor
    final cardRegExp = RegExp(r'Color\(0xFF2A2A3E\)|Color\(0xFF2E2E48\)');
    if (cardRegExp.hasMatch(content)) {
      content = content.replaceAll(cardRegExp, 'AppTheme.cardColor');
      modified = true;
    }

    // Colors.orangeAccent -> AppTheme.pendingAmber
    if (content.contains('Colors.orangeAccent')) {
      content = content.replaceAll('Colors.orangeAccent', 'AppTheme.pendingAmber');
      modified = true;
    }
    
    // Colors.orange -> AppTheme.pendingAmber
    if (content.contains('Colors.orange') && !content.contains('Colors.orangeAccent')) {
      content = content.replaceAll(RegExp(r'Colors\.orange(?!Accent)'), 'AppTheme.pendingAmber');
      modified = true;
    }

    // Colors.greenAccent -> AppTheme.activeEmerald
    if (content.contains('Colors.greenAccent')) {
      content = content.replaceAll('Colors.greenAccent', 'AppTheme.activeEmerald');
      modified = true;
    }
    
    // Colors.green -> AppTheme.activeEmerald
    if (content.contains('Colors.green') && !content.contains('Colors.greenAccent')) {
      content = content.replaceAll(RegExp(r'Colors\.green(?!Accent)'), 'AppTheme.activeEmerald');
      modified = true;
    }

    // Colors.blueAccent -> AppTheme.primaryAction
    if (content.contains('Colors.blueAccent')) {
      content = content.replaceAll('Colors.blueAccent', 'AppTheme.primaryAction');
      modified = true;
    }
    
    // Colors.redAccent -> AppTheme.errorRed
    if (content.contains('Colors.redAccent')) {
      content = content.replaceAll('Colors.redAccent', 'AppTheme.errorRed');
      modified = true;
    }
    
    if (content.contains('Colors.red') && !content.contains('Colors.redAccent')) {
      content = content.replaceAll(RegExp(r'Colors\.red(?!Accent)'), 'AppTheme.errorRed');
      modified = true;
    }

    // Text Colors: Colors.white -> AppTheme.titleColor
    if (content.contains('Colors.white')) {
      content = content.replaceAll(RegExp(r'Colors\.white(?![0-9])'), 'AppTheme.titleColor');
      modified = true;
    }
    
    // Labels
    if (content.contains('Colors.white54')) {
      content = content.replaceAll('Colors.white54', 'AppTheme.labelColor');
      modified = true;
    }
    if (content.contains('Colors.white70')) {
      content = content.replaceAll('Colors.white70', 'AppTheme.labelColor');
      modified = true;
    }
    if (content.contains('Colors.white38')) {
      content = content.replaceAll('Colors.white38', 'AppTheme.labelColor');
      modified = true;
    }
    
    // Borders
    final borderRegExp = RegExp(r'Colors\.white(?:24|12|10)');
    if (borderRegExp.hasMatch(content)) {
      content = content.replaceAll(borderRegExp, 'AppTheme.borderColor');
      modified = true;
    }

    // Add import if modified
    if (modified && !content.contains('app_theme.dart')) {
       final importIndex = content.indexOf('import ');
       if (importIndex != -1) {
           content = content.replaceFirst('import ', "import 'package:mobile_app/core/app_theme.dart';\nimport ");
       }
    }

    if (modified) {
      file.writeAsStringSync(content);
      print('Updated ${file.path}');
    }
  }
}
