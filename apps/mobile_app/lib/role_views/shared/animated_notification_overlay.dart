import 'package:mobile_app/core/app_theme.dart';
import 'package:flutter/material.dart';

class AnimatedNotificationOverlay {
  static OverlayEntry? _currentEntry;

  static void show({
    required BuildContext context,
    required String title,
    required String message,
    IconData icon = Icons.notifications_active,
    Color? color,
  }) {
    color ??= AppTheme.pendingAmber;
    _currentEntry?.remove();
    _currentEntry = null;

    final overlay = Overlay.of(context);
    
    _currentEntry = OverlayEntry(
      builder: (context) => _NotificationToast(
        title: title,
        message: message,
        icon: icon,
        color: color!,
        onDismiss: () {
          _currentEntry?.remove();
          _currentEntry = null;
        },
      ),
    );

    overlay.insert(_currentEntry!);
  }
}

class _NotificationToast extends StatefulWidget {
  final String title;
  final String message;
  final IconData icon;
  final Color color;
  final VoidCallback onDismiss;

  _NotificationToast({
    required this.title,
    required this.message,
    required this.icon,
    required this.color,
    required this.onDismiss,
  });

  @override
  _NotificationToastState createState() => _NotificationToastState();
}

class _NotificationToastState extends State<_NotificationToast> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _offsetAnimation;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 800),
    );

    _offsetAnimation = Tween<Offset>(
      begin: Offset(0, -1.5),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.elasticOut,
    ));

    _opacityAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Interval(0.0, 0.5, curve: Curves.easeIn),
    ));

    _controller.forward();

    // Auto dismiss after 6 seconds
    Future.delayed(Duration(seconds: 6), () {
      if (mounted) {
        _controller.reverse().then((_) => widget.onDismiss());
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 16,
      left: 16,
      right: 16,
      child: SlideTransition(
        position: _offsetAnimation,
        child: FadeTransition(
          opacity: _opacityAnimation,
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.background, // Matches app theme
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: widget.color.withOpacity(0.3)),
                boxShadow: [
                  BoxShadow(
                    color: widget.color.withOpacity(0.15),
                    blurRadius: 20,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Row(
                children: [
                   Container(
                    padding: EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: widget.color.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(widget.icon, color: widget.color, size: 24),
                  ),
                  SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          style: TextStyle(
                            color: AppTheme.titleColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          widget.message,
                          style: TextStyle(
                            color: AppTheme.titleColor.withOpacity(0.7),
                            fontSize: 12,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: AppTheme.borderColor, size: 18),
                    onPressed: () {
                      _controller.reverse().then((_) => widget.onDismiss());
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
