import 'package:mobile_app/core/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:geolocator/geolocator.dart';
import 'staff_management_screen.dart';
import 'join_requests_screen.dart';
import '../../features/inventory/inventory_list_screen.dart';
import '../../features/orders/orders_tab.dart';
import '../../features/ledger/screens/kaatha_screen.dart';
import '../../services/notification_service.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import '../shared/settings_screen.dart';
import '../shared/animated_notification_overlay.dart';
import '../shared/expandable_notification_item.dart';
import 'package:intl/intl.dart';
import '../../features/orders/order_details_screen.dart';

class OwnerView extends StatefulWidget {
  const OwnerView({super.key});

  @override
  State<OwnerView> createState() => _OwnerViewState();
}

class _OwnerViewState extends State<OwnerView> {
  final supabase = Supabase.instance.client;
  bool _loading = true;
  String? _companyId;
  String? _ownerName;
  String? _companyName;
  int _pendingCount = 0;
  int _selectedIndex = 0;
  RealtimeChannel? _requestSubscription;
  RealtimeChannel? _notificationSubscription;
  RealtimeChannel? _ordersSubscription;
  int _unreadNotificationsCount = 0;
  final _audioPlayer = AudioPlayer();

  @override
  void dispose() {
    _requestSubscription?.unsubscribe();
    _notificationSubscription?.unsubscribe();
    _ordersSubscription?.unsubscribe();
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // 🔹 Handle Deep Linking (Target Tab)
    if (NotificationService.targetTab != 0) {
      _selectedIndex = NotificationService.targetTab;
      NotificationService.targetTab = 0; // Reset
    }
    _fetchOwnerProfile();
  }

  Future<void> _fetchOwnerProfile() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    try {
      final res = await supabase
          .from('profiles')
          .select('full_name, company_id')
          .eq('id', user.id)
          .maybeSingle();

      if (res == null) {
        if (mounted) setState(() => _loading = false);
        return;
      }

      if (mounted) {
        setState(() {
          _ownerName = res['full_name'];
          _companyId = res['company_id'];
          _loading = false;
        });

        if (_companyId != null) {
          _fetchCompanyName();
          _fetchRequestCount();
          _setupRequestRealtime();
          _fetchNotificationsCount();
          _setupNotificationRealtime();
          _setupOrdersRealtime();
          _fetchDashboardOrders();

          // Login user to OneSignal
          NotificationService.login(user.id);
          OneSignal.User.addTags({
            'company_id': _companyId!,
            'role': 'owner',
            'full_name': _ownerName ?? 'Owner',
          });
        }
      }
    } catch (e) {
      debugPrint('Error fetching owner profile: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _fetchCompanyName() async {
    if (_companyId == null) return;
    try {
      final res = await supabase
          .from('companies')
          .select('name')
          .eq('id', _companyId!)
          .maybeSingle();
      if (res != null && mounted) {
        setState(() => _companyName = res['name']);
      }
    } catch (_) {}
  }

  Future<void> _fetchRequestCount() async {
    if (_companyId == null) return;
    try {
      final res = await supabase
          .from('company_join_requests')
          .select('id')
          .eq('status', 'pending')
          .eq('company_id', _companyId!);
      if (mounted) setState(() => _pendingCount = res.length);
    } catch (_) {}
  }

  Future<void> _fetchNotificationsCount() async {
    if (_companyId == null) return;
    try {
      final res = await supabase
          .from('notifications')
          .select('id')
          .eq('is_read', false);
      if (mounted) setState(() => _unreadNotificationsCount = res.length);
    } catch (_) {}
  }

  void _setupNotificationRealtime() {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    _notificationSubscription = supabase
        .channel('public:notifications')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'owner_id',
            value: user.id,
          ),
          callback: (payload) {
            if (mounted) {
              setState(() {
                _unreadNotificationsCount++;
              });
              _audioPlayer.play(AssetSource('sounds/notification.mp3')).catchError((_) {});
              _showNotificationAlert(payload.newRecord['title'], payload.newRecord['message']);
            }
          },
        )
        .subscribe();
  }

  void _setupOrdersRealtime() {
    if (_companyId == null) return;

    _ordersSubscription?.unsubscribe();
    _ordersSubscription = supabase
        .channel('public:orders_owner')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'orders',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'company_id',
            value: _companyId!,
          ),
          callback: (payload) {
            if (mounted) {
              _fetchDashboardOrders();
            }
          },
        )
        .subscribe();
  }

  void _showNotificationAlert(String title, String message) {
    AnimatedNotificationOverlay.show(
      context: context,
      title: title,
      message: message,
      icon: Icons.notifications_active,
      color: AppTheme.primaryAction,
    );
  }

  void _showNotificationsSheet() {
    setState(() => _unreadNotificationsCount = 0);
    // Mark all as read
    supabase
        .from('notifications')
        .update({'is_read': true})
        .eq('is_read', false)
        .then((_) {});

    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Notifications',
                  style: TextStyle(
                    color: AppTheme.titleColor,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, color: AppTheme.labelColor),
                ),
              ],
            ),
            const Divider(color: AppTheme.borderColor),
            Expanded(
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: supabase
                    .from('notifications')
                    .select()
                    .order('created_at', ascending: false)
                    .limit(20),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final notifications = snapshot.data ?? [];
                  if (notifications.isEmpty) {
                    return const Center(
                      child: Text('No notifications', style: TextStyle(color: AppTheme.labelColor)),
                    );
                  }
                  return ListView.builder(
                    itemCount: notifications.length,
                    itemBuilder: (context, index) {
                      return ExpandableNotificationItem(
                        notification: notifications[index],
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _toast(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  Future<void> _shareLocationToMiddleman() async {
    try {
      final res = await supabase
          .from('middle_men')
          .select('name, phone_number')
          .eq('company_id', _companyId!);
      
      if ((res as List).isEmpty) {
        _toast('No middlemen found to share location with');
        return;
      }

      final middleMen = List<Map<String, dynamic>>.from(res);
      
      if (!mounted) return;

      final selectedMid = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: AppTheme.background,
          title: const Text('Share Location With...', style: TextStyle(color: AppTheme.titleColor)),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: middleMen.length,
              itemBuilder: (context, index) {
                final mid = middleMen[index];
                return ListTile(
                  title: Text(mid['name'] ?? '', style: const TextStyle(color: AppTheme.titleColor)),
                  subtitle: Text(mid['phone_number'] ?? '', style: const TextStyle(color: AppTheme.labelColor)),
                  onTap: () => Navigator.pop(context, mid),
                );
              },
            ),
          ),
        ),
      );

      if (selectedMid != null) {
        await _performLocationSharing(selectedMid['phone_number']);
      }
    } catch (e) {
      _toast('Error: $e');
    }
  }

  Future<void> _performLocationSharing(String phone) async {
    final phoneNumber = phone.replaceAll(RegExp(r'[^\d+]'), '');
    if (phoneNumber.isEmpty) {
      _toast('Invalid phone number');
      return;
    }

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _toast('Location services are disabled');
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _toast('Location permissions are denied');
          return;
        }
      }

      _toast('Getting location...');
      Position position = await Geolocator.getCurrentPosition();
      
      final String googleMapsUrl = 'https://www.google.com/maps/search/?api=1&query=${position.latitude},${position.longitude}';
      final String message = Uri.encodeComponent('Hi, I am the owner. Here is my current location: $googleMapsUrl');
      final Uri whatsappUrl = Uri.parse('whatsapp://send?phone=$phoneNumber&text=$message');

      if (await canLaunchUrl(whatsappUrl)) {
        await launchUrl(whatsappUrl);
      } else {
        final Uri webWhatsapp = Uri.parse('https://wa.me/$phoneNumber?text=$message');
        await launchUrl(webWhatsapp, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      _toast('Error sharing location: $e');
    }
  }

  List<Map<String, dynamic>> _onGoingOrders = [];
  List<Map<String, dynamic>> _upcomingOrders = [];

  Future<void> _fetchDashboardOrders() async {
    if (_companyId == null) return;
    try {
      final ongoingRes = await supabase
          .from('orders')
          .select('*, profiles!orders_delivery_staff_id_fkey(full_name, last_latitude, last_longitude)')
          .eq('company_id', _companyId!)
          .eq('order_status', 'upcoming')
          .not('delivery_staff_id', 'is', null)
          .order('event_date', ascending: true);

      final upcomingRes = await supabase
          .from('orders')
          .select('*')
          .eq('company_id', _companyId!)
          .eq('order_status', 'upcoming')
          .filter('delivery_staff_id', 'is', null)
          .order('event_date', ascending: true);

      if (mounted) {
        setState(() {
          _onGoingOrders = List<Map<String, dynamic>>.from(ongoingRes);
          _upcomingOrders = List<Map<String, dynamic>>.from(upcomingRes);
        });
      }
    } catch (e) {
      debugPrint('Error fetching dashboard orders: $e');
    }
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return 'No Date';
    try {
      final date = DateTime.parse(dateStr).toLocal();
      return DateFormat('MMM dd, hh:mm a').format(date);
    } catch (_) {
      return dateStr;
    }
  }

  Widget _buildOrderList(String title, bool isOngoing, List<Map<String, dynamic>> orders) {
     final badgeText = isOngoing ? '${orders.length} Active' : '${orders.length} Pending';
     final badgeColor = isOngoing ? AppTheme.activeEmerald : AppTheme.pendingAmber;
     
     return Container(
        margin: const EdgeInsets.only(bottom: 24),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: badgeColor.withOpacity(0.03),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: badgeColor.withOpacity(0.15), width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
             Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: AppTheme.titleColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: badgeColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      badgeText,
                      style: TextStyle(
                        color: badgeColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      )
                    )
                  )
                ],
              ),
              const SizedBox(height: 12),
              if (orders.isEmpty)
                 Padding(
                   padding: const EdgeInsets.symmetric(vertical: 20),
                   child: Center(child: Text('No $title orders.', style: const TextStyle(color: AppTheme.labelColor))),
                 )
              else
                 Container(
                   constraints: const BoxConstraints(maxHeight: 280),
                   child: ListView.builder(
                     shrinkWrap: true,
                     physics: const BouncingScrollPhysics(),
                     itemCount: orders.length,
                     itemBuilder: (context, index) {
                        final order = orders[index];
                        final orderIdStr = order['id']?.toString() ?? 'N/A';
                        final shortId = orderIdStr.length > 4 ? orderIdStr.substring(0,4).toUpperCase() : orderIdStr;
                        
                        return InkWell(
                          onTap: () {
                             Navigator.push(context, MaterialPageRoute(builder: (context) => OrderDetailsScreen(order: order, companyId: _companyId!)));
                          },
                          child: Container(
                             margin: const EdgeInsets.only(bottom: 12),
                             decoration: BoxDecoration(
                               color: AppTheme.cardColor,
                               borderRadius: BorderRadius.circular(16),
                               border: Border.all(color: AppTheme.borderColor),
                               boxShadow: [
                                 BoxShadow(
                                   color: AppTheme.titleColor.withOpacity(0.03),
                                   blurRadius: 10,
                                   offset: const Offset(0, 4),
                                 ),
                               ]
                             ),
                             child: ClipRRect(
                               borderRadius: BorderRadius.circular(16),
                               child: Container(
                                 decoration: BoxDecoration(
                                   border: Border(left: BorderSide(color: badgeColor, width: 6)),
                                 ),
                                 padding: const EdgeInsets.all(16),
                                 child: Column(
                                   crossAxisAlignment: CrossAxisAlignment.start,
                                   children: [
                                      if (isOngoing) ...[
                                          Row(
                                            children: [
                                              Container(
                                                width: 8, height: 8,
                                                decoration: BoxDecoration(color: badgeColor, shape: BoxShape.circle),
                                              ),
                                              const SizedBox(width: 8),
                                              Text('ORD-$shortId', style: const TextStyle(color: AppTheme.labelColor, fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                                              const Spacer(),
                                              const Icon(Icons.expand_more, color: AppTheme.labelColor, size: 20),
                                            ]
                                          ),
                                          const SizedBox(height: 8),
                                          Text(order['client_name'] ?? 'Unknown Client', style: const TextStyle(color: AppTheme.titleColor, fontWeight: FontWeight.bold, fontSize: 18)),
                                          const SizedBox(height: 8),
                                          Row(
                                            children: [
                                              const Icon(Icons.badge_outlined, color: AppTheme.labelColor, size: 16),
                                              const SizedBox(width: 6),
                                              Text('Staff: ${order['profiles']?['full_name'] ?? 'Assigning...'}', style: const TextStyle(color: AppTheme.labelColor, fontSize: 14)),
                                            ]
                                          )
                                      ] else ...[
                                          Row(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text('${_formatDate(order['event_date'])}', style: const TextStyle(color: AppTheme.labelColor, fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                                                    const SizedBox(height: 4),
                                                    Text(order['client_name'] ?? 'Unknown Client', style: const TextStyle(color: AppTheme.titleColor, fontWeight: FontWeight.bold, fontSize: 18)),
                                                  ]
                                                ),
                                              ),
                                              const Icon(Icons.chevron_right, color: AppTheme.labelColor, size: 20),
                                            ]
                                          )
                                      ]
                                   ]
                                 )
                               )
                             )
                          )
                        );
                     }
                   ),
                 )
          ]
        )
     );
  }

  void _setupRequestRealtime() {
    _requestSubscription?.unsubscribe();
    if (_companyId == null) return;

    // NOTE: No column filter here — UPDATE events from Supabase are silently
    // dropped when a column filter is used unless REPLICA IDENTITY FULL is set.
    // We filter by company_id inside the callback instead.
    _requestSubscription = supabase
        .channel('owner_requests_${_companyId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'company_join_requests',
          callback: (payload) {
            // Filter by company_id in callback
            final record = payload.newRecord.isNotEmpty
                ? payload.newRecord
                : payload.oldRecord;
            final recordCompanyId = record['company_id'];
            if (recordCompanyId != null && recordCompanyId != _companyId)
              return;

            if (payload.eventType == PostgresChangeEvent.insert) {
              // Play sound from any tab
              _audioPlayer.play(AssetSource('sounds/notification.mp3'));
            }
            _fetchRequestCount();
          },
        )
        .subscribe();
  }



  Widget _buildDashboardTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Welcome Back,',
            style: TextStyle(
              color: AppTheme.titleColor.withOpacity(0.6),
              fontSize: 16,
            ),
          ),
          Text(
            _companyName ?? 'Dashboard',
            style: const TextStyle(
              color: AppTheme.titleColor,
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Owner: ${_ownerName ?? '...'}',
            style: TextStyle(
              color: AppTheme.titleColor.withOpacity(0.5),
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 30),

          _buildOrderList('On-Going', true, _onGoingOrders),
          _buildOrderList('Up-Coming', false, _upcomingOrders),


          // Inventory Action
          InkWell(
            onTap: () {
              if (_companyId != null) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => InventoryListScreen(
                      companyId: _companyId!,
                      isOwner: true,
                    ),
                  ),
                );
              }
            },
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppTheme.primaryAction.withOpacity(0.15),
                    AppTheme.primaryAction.withOpacity(0.05),
                  ],
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppTheme.primaryAction.withOpacity(0.2)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryAction.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.inventory_2_outlined,
                      color: AppTheme.primaryAction,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Manage Menu',
                          style: TextStyle(
                            color: AppTheme.titleColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          'Track food items and recipes',
                          style: TextStyle(color: AppTheme.labelColor, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.arrow_forward_ios_rounded,
                    color: AppTheme.borderColor,
                    size: 16,
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 30),

          const SizedBox(height: 30),

          // Manage Middlemen Action
          InkWell(
            onTap: () {
              if (_companyId != null) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => KaathaScreen(companyId: _companyId!),
                  ),
                );
              }
            },
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppTheme.activeEmerald.withOpacity(0.15),
                    AppTheme.activeEmerald.withOpacity(0.05),
                  ],
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppTheme.activeEmerald.withOpacity(0.2)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.activeEmerald.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.account_balance_wallet_outlined,
                      color: AppTheme.activeEmerald,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Manage Middlemen',
                          style: TextStyle(
                            color: AppTheme.titleColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          'Khata ledger & middleman accounts',
                          style: TextStyle(color: AppTheme.labelColor, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.arrow_forward_ios_rounded,
                    color: AppTheme.borderColor,
                    size: 16,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: AppTheme.background,
        body: Center(
          child: CircularProgressIndicator(color: AppTheme.pendingAmber),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Owner Dashboard',
          style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.titleColor),
        ),
        automaticallyImplyLeading: false,
        actions: [
          Stack(
            children: [
              IconButton(
                onPressed: _showNotificationsSheet,
                icon: const Icon(Icons.notifications_none, color: AppTheme.titleColor),
              ),
              if (_unreadNotificationsCount > 0)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: AppTheme.errorRed,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 14,
                      minHeight: 14,
                    ),
                    child: Text(
                      '$_unreadNotificationsCount',
                      style: const TextStyle(
                        color: AppTheme.titleColor,
                        fontSize: 8,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
          IconButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => SettingsScreen(
                    companyId: _companyId,
                    companyName: _companyName,
                    role: 'owner',
                    fullName: _ownerName,
                  ),
                ),
              );
            },
            icon: const Icon(Icons.settings_outlined, color: AppTheme.labelColor),
          ),
        ],
      ),
      body: _selectedIndex == 0
          ? _buildDashboardTab()
          : _selectedIndex == 1
          ? OrdersTab(companyId: _companyId ?? '')
          : _selectedIndex == 2
          ? JoinRequestsScreen(
              key: ValueKey(_pendingCount),
              onRequestHandled: _fetchRequestCount,
            )
          : StaffManagementScreen(companyId: _companyId ?? ''),
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: AppTheme.background,
        selectedItemColor: AppTheme.pendingAmber,
        unselectedItemColor: AppTheme.labelColor,
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        type: BottomNavigationBarType.fixed,
        items: [
          const BottomNavigationBarItem(
            icon: Icon(Icons.dashboard_outlined),
            activeIcon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.assignment_outlined),
            activeIcon: Icon(Icons.assignment),
            label: 'Orders',
          ),
          BottomNavigationBarItem(
            icon: Badge(
              isLabelVisible: _pendingCount > 0,
              label: Text('$_pendingCount'),
              backgroundColor: AppTheme.errorRed,
              child: const Icon(Icons.person_add_outlined),
            ),
            activeIcon: Badge(
              isLabelVisible: _pendingCount > 0,
              label: Text('$_pendingCount'),
              backgroundColor: AppTheme.errorRed,
              child: const Icon(Icons.person_add),
            ),
            label: 'Requests',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.people_alt_outlined),
            activeIcon: Icon(Icons.people_alt),
            label: 'Staff',
          ),
        ],
      ),
    );
  }
}
