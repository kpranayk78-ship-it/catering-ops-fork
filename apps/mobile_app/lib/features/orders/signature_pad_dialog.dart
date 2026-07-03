import 'package:mobile_app/core/app_theme.dart';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

class SignaturePadDialog extends StatefulWidget {
  final String clientName;
  SignaturePadDialog({super.key, required this.clientName});

  @override
  State<SignaturePadDialog> createState() => _SignaturePadDialogState();
}

class _SignaturePadDialogState extends State<SignaturePadDialog> {
  final List<List<Offset>> _strokes = [];
  List<Offset> _current = [];
  bool _isEmpty = true;
  final GlobalKey _repaintKey = GlobalKey();

  void _onPanStart(DragStartDetails d) {
    setState(() {
      _current = [d.localPosition];
      _isEmpty = false;
    });
  }

  void _onPanUpdate(DragUpdateDetails d) {
    setState(() => _current.add(d.localPosition));
  }

  void _onPanEnd(DragEndDetails _) {
    setState(() {
      _strokes.add(List.from(_current));
      _current = [];
    });
  }

  void _clear() {
    setState(() {
      _strokes.clear();
      _current = [];
      _isEmpty = true;
    });
  }

  Future<Uint8List?> _capture() async {
    try {
      final boundary =
          _repaintKey.currentContext!.findRenderObject()
              as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 4.0);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data?.buffer.asUint8List();
    } catch (e) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppTheme.background,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Row(
              children: [
                Icon(
                  Icons.draw_outlined,
                  color: AppTheme.pendingAmber,
                  size: 22,
                ),
                SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Delivery Confirmation',
                        style: TextStyle(
                          color: AppTheme.titleColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        'Customer: ${widget.clientName}',
                        style: TextStyle(
                          color: AppTheme.labelColor,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: 16),
            Text(
              'Please ask the customer to sign below:',
              style: TextStyle(color: AppTheme.labelColor, fontSize: 13),
            ),
            SizedBox(height: 12),

            // Signature canvas
            Container(
              height: 200,
              decoration: BoxDecoration(
                color: AppTheme.titleColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _isEmpty
                      ? AppTheme.pendingAmber.withOpacity(0.5)
                      : AppTheme.activeEmerald.withOpacity(0.5),
                  width: 2,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: RepaintBoundary(
                  key: _repaintKey,
                  child: GestureDetector(
                    onPanStart: _onPanStart,
                    onPanUpdate: _onPanUpdate,
                    onPanEnd: _onPanEnd,
                    child: Container(
                      color: AppTheme.titleColor,
                      child: CustomPaint(
                        painter: _SignaturePainter(
                          strokes: _strokes,
                          current: _current,
                        ),
                        size: Size.infinite,
                      ),
                    ),
                  ),
                ),
              ),
            ),

            if (_isEmpty)
              Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  '↑ Draw signature here',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppTheme.labelColor, fontSize: 12),
                ),
              ),

            SizedBox(height: 16),

            Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 12,
              children: [
                // Clear
                OutlinedButton.icon(
                  onPressed: _clear,
                  icon: Icon(Icons.refresh, size: 16),
                  label: Text('Clear'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.labelColor,
                    side: BorderSide(color: AppTheme.borderColor),
                    padding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                // Cancel
                TextButton(
                  onPressed: () => Navigator.pop(context, null),
                  child: Text(
                    'Cancel',
                    style: TextStyle(color: AppTheme.labelColor),
                  ),
                ),
                // Submit
                ElevatedButton.icon(
                  onPressed: _isEmpty
                      ? null
                      : () async {
                          final bytes = await _capture();
                          if (bytes != null && context.mounted) {
                            Navigator.pop(context, bytes);
                          }
                        },
                  icon: Icon(Icons.check, size: 16),
                  label: Text('Order Delivered'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.activeEmerald,
                    foregroundColor: Colors.black,
                    disabledBackgroundColor: AppTheme.borderColor,
                    padding: EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SignaturePainter extends CustomPainter {
  final List<List<Offset>> strokes;
  final List<Offset> current;

  _SignaturePainter({required this.strokes, required this.current});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppTheme.background
      ..strokeWidth = 4.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    for (final stroke in strokes) {
      _drawStroke(canvas, stroke, paint);
    }
    _drawStroke(canvas, current, paint);
  }

  void _drawStroke(Canvas canvas, List<Offset> points, Paint paint) {
    if (points.length < 2) return;
    final path = Path()..moveTo(points[0].dx, points[0].dy);
    for (int i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_SignaturePainter old) => true;
}
