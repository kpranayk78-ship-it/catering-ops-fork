import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/app_theme.dart';
import 'create_order_screen.dart';

class OrderDetailsScreen extends StatelessWidget {
  final Map<String, dynamic> order;
  final String companyId;

  OrderDetailsScreen({super.key, required this.order, required this.companyId});

  String _formatDate(String? dateStr) {
    if (dateStr == null) return 'No Date';
    try {
      final date = DateTime.parse(dateStr).toLocal();
      return DateFormat('EEEE, MMM dd, yyyy - h:mm a').format(date);
    } catch (_) {
      return dateStr;
    }
  }

  Future<void> _shareToWhatsApp(BuildContext context) async {
    final clientName = order['client_name'] ?? 'Client';
    final date = _formatDate(order['event_date']);
    final address = order['venue_address'] ?? 'Not provided';
    final staffName = order['profiles']?['full_name'] ?? 'Not Assigned';
    
    final message = '''
*Order Details*
Client: $clientName
Date: $date
Venue: $address
Assigned Staff: $staffName
''';
    final encodedMsg = Uri.encodeComponent(message);
    final url = Uri.parse('whatsapp://send?text=$encodedMsg');
    
    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url);
      } else {
        final webUrl = Uri.parse('https://wa.me/?text=$encodedMsg');
        await launchUrl(webUrl, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open WhatsApp')),
        );
      }
    }
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 16.0),
      child: Row(
        children: [
          Icon(icon, color: AppTheme.primaryAction, size: 20),
          SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              color: AppTheme.primaryAction,
              fontSize: 16,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, {bool highlight = false}) {
    return Padding(
      padding: EdgeInsets.only(bottom: 12.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(
                color: AppTheme.labelColor,
                fontSize: 14,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: highlight ? AppTheme.primaryAction : AppTheme.titleColor,
                fontSize: 15,
                fontWeight: highlight ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final clientName = order['client_name'] ?? 'Unknown Client';
    
    // Parse menu items
    List<dynamic> menuItems = [];
    if (order['menu_items'] != null) {
      try {
        if (order['menu_items'] is String) {
          menuItems = jsonDecode(order['menu_items']);
        } else if (order['menu_items'] is List) {
          menuItems = order['menu_items'];
        }
      } catch (e) {
        debugPrint('Error parsing menu items: $e');
      }
    }

    final staffName = order['profiles']?['full_name'] ?? 'Not Assigned';

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text('Order Details'),
        backgroundColor: AppTheme.cardColor,
        foregroundColor: AppTheme.titleColor,
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(Icons.edit, color: AppTheme.primaryAction),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => CreateOrderScreen(
                    companyId: companyId,
                    orderToEdit: order,
                  ),
                ),
              );
            },
          ),
        ],
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(1.0),
          child: Container(
            color: AppTheme.borderColor,
            height: 1.0,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Client Header Card
            Container(
              padding: EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppTheme.cardColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.borderColor),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.titleColor.withOpacity(0.02),
                    blurRadius: 10,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    clientName,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.titleColor,
                    ),
                  ),
                  SizedBox(height: 12),
                  _buildDetailRow('Event Date', _formatDate(order['event_date'])),
                  if (order['venue_address'] != null && order['venue_address'].toString().isNotEmpty)
                    _buildDetailRow('Venue', order['venue_address']),
                  _buildDetailRow('Status', (order['order_status'] ?? 'Unknown').toString().toUpperCase()),
                  _buildDetailRow('Payment', (order['payment_status'] ?? 'Unknown').toString().toUpperCase()),
                ],
              ),
            ),
            
            SizedBox(height: 12),

            _buildSectionHeader('Staff & Logistics', Icons.local_shipping),
            Container(
              padding: EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppTheme.cardColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.borderColor),
              ),
              child: Column(
                children: [
                  _buildDetailRow('Assigned Staff', staffName, highlight: staffName != 'Not Assigned'),
                  if (order['middleman_tag'] != null && order['middleman_tag'].toString().isNotEmpty)
                    _buildDetailRow('Middleman', order['middleman_tag']),
                  if (order['guest_count'] != null)
                    _buildDetailRow('Guest Count', order['guest_count'].toString()),
                  if (order['event_duration'] != null && order['event_duration'].toString().isNotEmpty)
                    _buildDetailRow('Duration', order['event_duration']),
                  if (order['event_type'] != null && order['event_type'].toString().isNotEmpty)
                    _buildDetailRow('Event Type', order['event_type']),
                    
                  // WhatsApp Share Button
                  InkWell(
                    onTap: () => _shareToWhatsApp(context),
                    child: Container(
                      width: double.infinity,
                      margin: EdgeInsets.only(top: 16),
                      padding: EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: Color(0xFFE8F5E9),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Color(0xFFA5D6A7)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.message, color: Color(0xFF2E7D32), size: 18),
                          SizedBox(width: 8),
                          Text(
                            'Share Details via WhatsApp',
                            style: TextStyle(color: Color(0xFF2E7D32), fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            if (menuItems.isNotEmpty) ...[
              SizedBox(height: 12),
              _buildSectionHeader('Menu Items', Icons.restaurant_menu),
              Container(
                decoration: BoxDecoration(
                  color: AppTheme.cardColor,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.borderColor),
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: NeverScrollableScrollPhysics(),
                  itemCount: menuItems.length,
                  separatorBuilder: (context, index) => Divider(height: 1, color: AppTheme.borderColor),
                  itemBuilder: (context, index) {
                    final item = menuItems[index];
                    final qtyType = item['quantity_type'] == 'kg' ? 'kg' : 'units';
                    return Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              item['name'] ?? 'Unknown Item',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.titleColor,
                              ),
                            ),
                          ),
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryAction.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '${item['quantity']} $qtyType',
                              style: TextStyle(
                                color: AppTheme.primaryAction,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],

            if (order['special_instructions'] != null && order['special_instructions'].toString().isNotEmpty) ...[
              SizedBox(height: 12),
              _buildSectionHeader('Special Instructions', Icons.info_outline),
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppTheme.pendingAmber.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.pendingAmber.withOpacity(0.2)),
                ),
                child: Text(
                  order['special_instructions'],
                  style: TextStyle(
                    fontSize: 15,
                    color: AppTheme.titleColor,
                    height: 1.5,
                  ),
                ),
              ),
            ],

            SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}

