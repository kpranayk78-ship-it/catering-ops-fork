import 'dart:convert';
import 'package:mobile_app/core/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'add_inventory_item_screen.dart';
import '../../services/cache_service.dart';

class InventoryListScreen extends StatefulWidget {
  final String companyId;
  final bool isOwner;

  const InventoryListScreen({
    super.key,
    required this.companyId,
    required this.isOwner,
  });

  @override
  State<InventoryListScreen> createState() => _InventoryListScreenState();
}

class _InventoryListScreenState extends State<InventoryListScreen> {
  final supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  RealtimeChannel? _subscription;
  RealtimeChannel? _ordersSubscription;
  Map<String, double> _requiredQuantities = {};

  @override
  void initState() {
    super.initState();
    _fetchInventory();
    _setupRealtime();
  }

  void _setupRealtime() {
    _subscription = supabase
        .channel('public:inventory_items')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'inventory_items',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'company_id',
            value: widget.companyId,
          ),
          callback: (payload) => _fetchInventory(),
        )
        .subscribe();
        
    _ordersSubscription = supabase
        .channel('public:orders_for_inventory')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'orders',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'company_id',
            value: widget.companyId,
          ),
          callback: (payload) => _fetchInventory(),
        )
        .subscribe();
  }

  @override
  void dispose() {
    _subscription?.unsubscribe();
    _ordersSubscription?.unsubscribe();
    super.dispose();
  }

  Future<void> _fetchInventory() async {
    // 1. Try loading from Cache
    final cached = CacheService.get('inventory_${widget.companyId}');
    if (cached != null && mounted) {
      setState(() {
        _items = (cached as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _loading = false;
      });
    }

    try {
      final data = await supabase
          .from('inventory_items')
          .select()
          .eq('company_id', widget.companyId)
          .order('category', ascending: true)
          .order('name', ascending: true);

      final ordersData = await supabase
          .from('orders')
          .select('menu_items, order_status')
          .eq('company_id', widget.companyId);
          
      Map<String, double> required = {};
      for (var order in ordersData) {
        if (order['order_status'] == 'completed' || order['order_status'] == 'cancelled') continue;
        
        if (order['menu_items'] != null) {
          List<dynamic> menuItems = [];
          try {
            if (order['menu_items'] is String) {
              menuItems = jsonDecode(order['menu_items']);
            } else if (order['menu_items'] is List) {
              menuItems = order['menu_items'];
            }
          } catch (e) {
            debugPrint('Error parsing menu items: $e');
          }
          
          for (var item in menuItems) {
            final name = (item['name'] ?? '').toString().trim().toLowerCase();
            final qty = (item['quantity'] as num?)?.toDouble() ?? 0.0;
            required[name] = (required[name] ?? 0.0) + qty;
          }
        }
      }

      if (mounted) {
        setState(() {
          _items = List<Map<String, dynamic>>.from(data);
          _requiredQuantities = required;
          _loading = false;
        });

        // 2. Save to Cache
        CacheService.save('inventory_${widget.companyId}', data);
      }
    } catch (e) {
      debugPrint('Error fetching inventory: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _deleteItem(String id) async {
    try {
      await supabase.from('inventory_items').delete().eq('id', id);
      if (mounted) {
        setState(() {
          _items.removeWhere((item) => item['id'] == id);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Item deleted'),
            backgroundColor: AppTheme.pendingAmber,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting item: $e'),
            backgroundColor: AppTheme.errorRed,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Menu',
          style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.titleColor),
        ),
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new,
            size: 20,
            color: AppTheme.titleColor,
          ),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      floatingActionButton: widget.isOwner
          ? FloatingActionButton.extended(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) =>
                        AddInventoryItemScreen(companyId: widget.companyId),
                  ),
                );
              },
              backgroundColor: AppTheme.pendingAmber,
              icon: const Icon(Icons.add, color: AppTheme.titleColor),
              label: const Text(
                'Add Item',
                style: TextStyle(
                  color: AppTheme.titleColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            )
          : null,
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.pendingAmber),
            )
          : _items.isEmpty
          ? _buildEmptyState()
          : GridView.builder(
              padding: const EdgeInsets.all(24),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 0.65,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
              ),
              itemCount: _items.length,
              itemBuilder: (context, index) {
                final item = _items[index];
                return _buildInventoryCard(item);
              },
            ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.inventory_2_outlined,
            color: AppTheme.titleColor.withOpacity(0.1),
            size: 80,
          ),
          const SizedBox(height: 16),
          Text(
            'Menu is empty',
            style: TextStyle(
              color: AppTheme.titleColor.withOpacity(0.5),
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 8),
          if (widget.isOwner)
            Text(
              'Tap "Add Item" to start adding menu items.',
              style: TextStyle(
                color: AppTheme.titleColor.withOpacity(0.3),
                fontSize: 14,
              ),
            ),
        ],
      ),
    );
  }

  IconData _getIconForCategory(String category) {
    switch (category.toLowerCase()) {
      case 'produce':
        return Icons.eco_outlined;
      case 'meat & poultry':
        return Icons.set_meal_outlined;
      case 'dairy':
        return Icons.water_drop_outlined;
      case 'beverages':
        return Icons.local_drink_outlined;
      case 'equipment':
        return Icons.blender_outlined;
      case 'dry goods':
        return Icons.kitchen_outlined;
      default:
        return Icons.fastfood_outlined;
    }
  }

  Widget _buildInventoryCard(Map<String, dynamic> item) {
    final String? imageUrl = item['image_url'];
    final String category = item['category'] ?? 'Other';
    final IconData categoryIcon = _getIconForCategory(category);

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.titleColor.withOpacity(0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.borderColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Image Section
              Expanded(
                flex: 5,
                child: Container(
                  color: Colors.black26,
                  child: imageUrl != null && imageUrl.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: imageUrl,
                          fit: BoxFit.cover,
                          placeholder: (context, url) => const Center(
                            child: CircularProgressIndicator(
                              color: AppTheme.pendingAmber,
                              strokeWidth: 2,
                            ),
                          ),
                          errorWidget: (context, url, error) => Icon(
                            categoryIcon,
                            color: AppTheme.borderColor,
                            size: 40,
                          ),
                        )
                      : Icon(categoryIcon, color: AppTheme.borderColor, size: 40),
                ),
              ),
              // Details Section
              Expanded(
                flex: 4,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              item['name'] ?? 'Unknown Item',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppTheme.titleColor,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.3,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.primaryAction.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                item['category']?.toUpperCase() ??
                                    'UNCATEGORIZED',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppTheme.primaryAction,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.8,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Builder(
                        builder: (context) {
                          final itemName = (item['name'] ?? '').toString().trim().toLowerCase();
                          final requiredQty = _requiredQuantities[itemName] ?? 0.0;
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${requiredQty == requiredQty.toInt() ? requiredQty.toInt() : requiredQty} ${item['unit']}',
                                style: const TextStyle(
                                  color: AppTheme.pendingAmber,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const Text(
                                'Required',
                                style: TextStyle(
                                  color: AppTheme.labelColor,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          );
                        }
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          // Delete button for owners
          if (widget.isOwner)
            Positioned(
              top: 8,
              right: 8,
              child: InkWell(
                onTap: () {
                  showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      backgroundColor: AppTheme.background,
                      title: const Text(
                        'Delete Item?',
                        style: TextStyle(color: AppTheme.titleColor),
                      ),
                      content: Text(
                        'Are you sure you want to remove ${item['name']} from inventory?',
                        style: const TextStyle(color: AppTheme.labelColor),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text(
                            'CANCEL',
                            style: TextStyle(color: AppTheme.labelColor),
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            Navigator.pop(ctx);
                            _deleteItem(item['id']);
                          },
                          child: const Text(
                            'DELETE',
                            style: TextStyle(color: AppTheme.errorRed),
                          ),
                        ),
                      ],
                    ),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.5),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.delete_outline,
                    color: AppTheme.labelColor,
                    size: 18,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
