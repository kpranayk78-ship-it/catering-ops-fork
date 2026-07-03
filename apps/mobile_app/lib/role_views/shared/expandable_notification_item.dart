import 'package:mobile_app/core/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class ExpandableNotificationItem extends StatefulWidget {
  final Map<String, dynamic> notification;

  ExpandableNotificationItem({super.key, required this.notification});

  @override
  State<ExpandableNotificationItem> createState() => _ExpandableNotificationItemState();
}

class _ExpandableNotificationItemState extends State<ExpandableNotificationItem> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final n = widget.notification;
    final title = n['title'] ?? 'No Title';
    final message = n['message'] ?? 'No Message';
    final createdAt = n['created_at'] != null 
        ? DateTime.parse(n['created_at']).toLocal() 
        : DateTime.now();

    return Container(
      margin: EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppTheme.titleColor.withOpacity(0.03),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: (_isExpanded ? AppTheme.primaryAction : AppTheme.titleColor).withOpacity(0.1),
        ),
      ),
      child: InkWell(
        onTap: () => setState(() => _isExpanded = !_isExpanded),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    backgroundColor: AppTheme.primaryAction.withOpacity(0.1),
                    radius: 18,
                    child: Icon(Icons.notifications_outlined, color: AppTheme.primaryAction, size: 20),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            color: AppTheme.titleColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          DateFormat('MMM dd, hh:mm a').format(createdAt),
                          style: TextStyle(color: AppTheme.labelColor, fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    _isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    color: AppTheme.labelColor,
                    size: 20,
                  ),
                ],
              ),
              if (_isExpanded) ...[
                SizedBox(height: 12),
                Divider(color: AppTheme.borderColor, height: 1),
                SizedBox(height: 12),
                Text(
                  message,
                  style: TextStyle(
                    color: AppTheme.labelColor,
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
              ] else ...[
                SizedBox(height: 8),
                Text(
                  message,
                  style: TextStyle(
                    color: AppTheme.labelColor,
                    fontSize: 12,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
