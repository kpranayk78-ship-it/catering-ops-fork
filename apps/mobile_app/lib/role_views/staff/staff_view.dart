import 'package:mobile_app/core/app_theme.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:geolocator/geolocator.dart';
import '../../services/notification_service.dart';
import '../../features/inventory/inventory_list_screen.dart';
import '../shared/settings_screen.dart';
import '../../features/orders/signature_pad_dialog.dart';
import '../../services/cache_service.dart';
import '../shared/animated_notification_overlay.dart';
import '../shared/expandable_notification_item.dart';

class StaffView extends StatefulWidget {
  StaffView({super.key});

  @override
  State<StaffView> createState() => _StaffViewState();
}

class _StaffViewState extends State<StaffView> with WidgetsBindingObserver {
  final supabase = Supabase.instance.client;
  bool _loading = true;
  String? _companyId;
  String? _staffName;
  String? _companyName;

  final _companyCodeCtrl = TextEditingController();
  bool _submittingCode = false;

  Map<String, dynamic>? _pendingRequest;
  RealtimeChannel? _requestSubscription;
  RealtimeChannel? _profileSubscription;
  RealtimeChannel? _assignedOrdersSubscription;
  RealtimeChannel? _notificationSubscription;
  int _unreadNotificationsCount = 0;
  final _audioPlayer = AudioPlayer();

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _companyCodeCtrl.dispose();
    _requestSubscription?.unsubscribe();
    _profileSubscription?.unsubscribe();
    _assignedOrdersSubscription?.unsubscribe();
    _notificationSubscription?.unsubscribe();
    _audioPlayer.dispose();
    _countdownTimer?.cancel();
    _locationTimer?.cancel();
    for (final ctrl in _bidControllers.values) {
      ctrl.dispose();
    }
    super.dispose();
  }

  List<Map<String, dynamic>> _assignedOrders = [];
  List<Map<String, dynamic>> _openOrders = [];
  bool _loadingAssignedOrders = false;
  final Set<String> _dismissedOrders = {};
  Timer? _countdownTimer;
  // Persistent bid input controllers keyed by order ID
  final Map<String, TextEditingController> _bidControllers = {};

  TextEditingController _bidControllerFor(String orderId) {
    return _bidControllers.putIfAbsent(orderId, () => TextEditingController());
  }

  Future<void> _openMaps(String address) async {
    final cleanAddress = address.trim();
    if (cleanAddress.isEmpty) return;

    // Smart Link Detection: Check for full URLs or common map domains
    final isUrl = cleanAddress.startsWith('http://') || 
                  cleanAddress.startsWith('https://') ||
                  cleanAddress.contains('maps.app.goo.gl') ||
                  cleanAddress.contains('goo.gl/maps') ||
                  cleanAddress.contains('maps.google.com');

    if (isUrl) {
      // Add protocol if missing
      String urlString = cleanAddress;
      if (!urlString.startsWith('http')) {
        urlString = 'https://$urlString';
      }
      
      final Uri url = Uri.parse(urlString);
      try {
        if (await canLaunchUrl(url)) {
          await launchUrl(url, mode: LaunchMode.externalApplication);
          return;
        }
      } catch (e) {
        debugPrint('Error launching direction URL: $e');
      }
    }

    // Fallback: search-based deep linking for plain text names/addresses
    final encodedAddress = Uri.encodeComponent(cleanAddress);
    final Uri googleMapsWebUrl = Uri.parse('https://www.google.com/maps/search/?api=1&query=$encodedAddress');
    final Uri googleMapsNativeUrl = Uri.parse('google.navigation:q=$encodedAddress');
    final Uri appleMapsNativeUrl = Uri.parse('apple-maps://?daddr=$encodedAddress');

    try {
      if (await canLaunchUrl(googleMapsNativeUrl)) {
        await launchUrl(googleMapsNativeUrl, mode: LaunchMode.externalApplication);
      } else if (await canLaunchUrl(appleMapsNativeUrl)) {
        await launchUrl(appleMapsNativeUrl, mode: LaunchMode.externalApplication);
      } else {
        await launchUrl(googleMapsWebUrl, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      _toast('Could not open Maps: $e');
    }
  }

  Future<void> _shareLocationWithMiddleman(String? middlemanTag) async {
    if (middlemanTag == null || middlemanTag.isEmpty) {
      _toast('No middleman associated with this order');
      return;
    }

    // Extract phone number: "Name (9876543210)" -> "9876543210"
    final regExp = RegExp(r'\((.*?)\)');
    final match = regExp.firstMatch(middlemanTag);
    final phoneNumber = match?.group(1)?.replaceAll(RegExp(r'[^\d+]'), '') ?? '';

    if (phoneNumber.isEmpty) {
      _toast('Could not find middleman phone number');
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

      if (permission == LocationPermission.deniedForever) {
        _toast('Location permissions are permanently denied');
        return;
      }

      _toast('Getting location...');
      Position position = await Geolocator.getCurrentPosition();
      
      final String googleMapsUrl = 'https://www.google.com/maps/search/?api=1&query=${position.latitude},${position.longitude}';
      final String message = Uri.encodeComponent('Hi, I am the delivery staff. Here is my current location: $googleMapsUrl');
      final Uri whatsappUrl = Uri.parse('whatsapp://send?phone=$phoneNumber&text=$message');

      if (await canLaunchUrl(whatsappUrl)) {
        await launchUrl(whatsappUrl);
      } else {
        // Fallback to web link
        final Uri webWhatsapp = Uri.parse('https://wa.me/$phoneNumber?text=$message');
        await launchUrl(webWhatsapp, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      _toast('Error sharing location: $e');
    }
  }

  // 🔹 NEW: Periodic location updates for staff
  Timer? _locationTimer;
  
  Future<void> _updateStaffLocationInDB() async {
    final user = supabase.auth.currentUser;
    if (user == null || _assignedOrders.isEmpty) return;

    // Only update if there's an upcoming order today
    bool hasActiveOrder = _assignedOrders.any((o) => o['order_status'] == 'upcoming');
    if (!hasActiveOrder) return;

    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: Duration(seconds: 10),
      );
      
      await supabase.from('profiles').update({
        'last_latitude': position.latitude,
        'last_longitude': position.longitude,
        'location_updated_at': DateTime.now().toIso8601String(),
      }).eq('id', user.id);
      
      debugPrint('Staff location updated in DB: ${position.latitude}, ${position.longitude}');
    } catch (e) {
      debugPrint('Error updating staff location in DB: $e');
    }
  }

  void _startLocationUpdates() {
    _locationTimer?.cancel();
    // Update every 5 minutes if app is in foreground and there are orders
    _locationTimer = Timer.periodic(Duration(minutes: 5), (_) => _updateStaffLocationInDB());
    // Trigger initial update
    _updateStaffLocationInDB();
  }

  @override
  void initState() {
    super.initState();
    _fetchStaffProfile();
    _fetchRequestStatus();
    _setupRequestRealtime();
    _setupProfileRealtime();
    // NOTE: _fetchAssignedOrders and _setupAssignedOrdersRealtime are called
    // inside _fetchStaffProfile() after _companyId is available.
    _fetchNotificationsCount();
    _setupNotificationRealtime();
    _countdownTimer = Timer.periodic(Duration(seconds: 1), (timer) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // 🔹 Re-sync tags whenever app comes to foreground
      if (_companyId != null) {
        NotificationService.refreshTags(
          companyId: _companyId!,
          role: 'staff',
        );
      }
    }
  }

  Future<void> _fetchNotificationsCount() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    try {
      final res = await supabase
          .from('notifications')
          .select('id')
          .eq('owner_id', user.id) // In this app, notifications table uses owner_id for any recipient
          .eq('is_read', false);
      if (mounted) setState(() => _unreadNotificationsCount = res.length);
    } catch (_) {}
  }

  void _setupNotificationRealtime() {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    _notificationSubscription?.unsubscribe();
    _notificationSubscription = supabase
        .channel('public:notifications:staff')
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
              setState(() => _unreadNotificationsCount++);
              _audioPlayer.play(AssetSource('sounds/notification.mp3')).catchError((_) {});
              _showNotificationAlert(payload.newRecord['title'], payload.newRecord['message']);
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
      color: AppTheme.pendingAmber,
    );
  }

  void _showNotificationsSheet() {
    setState(() => _unreadNotificationsCount = 0);
    final user = supabase.auth.currentUser;
    if (user == null) return;

    // Mark as read
    supabase
        .from('notifications')
        .update({'is_read': true})
        .eq('is_read', false)
        .eq('owner_id', user.id)
        .then((_) {});

    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.background,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Notifications',
                  style: TextStyle(color: AppTheme.titleColor, fontSize: 20, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(Icons.close, color: AppTheme.labelColor),
                ),
              ],
            ),
            Divider(color: AppTheme.borderColor),
            Expanded(
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: supabase
                    .from('notifications')
                    .select()
                    .eq('owner_id', user.id)
                    .order('created_at', ascending: false)
                    .limit(20),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return Center(child: CircularProgressIndicator());
                  }
                  final notifications = snapshot.data ?? [];
                  if (notifications.isEmpty) {
                    return Center(
                      child: Text('No notifications', style: TextStyle(color: AppTheme.labelColor)),
                    );
                  }
                  return ListView.builder(
                    itemCount: notifications.length,
                    itemBuilder: (context, index) => ExpandableNotificationItem(
                      notification: notifications[index],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }


  Future<void> _fetchStaffProfile() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    // 1. Try Loading from Cache
    final cached = CacheService.get('profile_${user.id}');
    if (cached != null && mounted) {
      setState(() {
        _staffName = cached['full_name'];
        _companyId = cached['company_id'];
        _loading = false;
      });
      if (_companyId != null) {
        _fetchCompanyName();
        _fetchAssignedOrders();
      }
    }

    try {
      final res = await supabase
          .from('profiles')
          .select('full_name, company_id')
          .eq('id', user.id)
          .maybeSingle();

      if (mounted && res != null) {
        setState(() {
          _staffName = res['full_name'] ?? 'Staff Member';
          _companyId = res['company_id'];
          _loading = false;
        });

        // 🔹 Log in to OneSignal and refresh tags
        await NotificationService.login(user.id);
        if (_companyId != null) {
          await NotificationService.refreshTags(
            companyId: _companyId!,
            role: 'staff',
          );

          // 🔹 Handle after-effects of having a company
          _fetchCompanyName();
          _fetchAssignedOrders();
          _setupAssignedOrdersRealtime();
          _fetchNotificationsCount();
          _setupNotificationRealtime();
          _startLocationUpdates();
        }

        // 2. Save to Cache
        CacheService.save('profile_${user.id}', res);
      }
    } catch (e) {
      debugPrint('Error fetching staff profile: $e');
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

  Future<void> _fetchRequestStatus() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    try {
      final res = await supabase
          .from('company_join_requests')
          .select('*, companies(name)')
          .eq('staff_id', user.id)
          .eq('status', 'pending')
          .maybeSingle();

      if (mounted) {
        setState(() => _pendingRequest = res);
      }
    } catch (e) {
      debugPrint('Error fetching request status: $e');
    }
  }

  void _setupRequestRealtime() {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    _requestSubscription?.unsubscribe();
    _requestSubscription = supabase
        .channel('public:company_join_requests')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'company_join_requests',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'staff_id',
            value: user.id,
          ),
          callback: (payload) async {
            // Small delay to let DB trigger finish updating profile
            await Future.delayed(Duration(milliseconds: 800));
            _fetchRequestStatus();
            _fetchStaffProfile();
          },
        )
        .subscribe();
  }

  void _setupProfileRealtime() {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    _profileSubscription?.unsubscribe();
    _profileSubscription = supabase
        .channel('public:profiles:current_staff')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'profiles',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: user.id,
          ),
          callback: (payload) async {
            final newData = payload.newRecord;
            final newId = newData['company_id'];

            // 🔹 Case 1: Staff joined a company
            if (newId != null && _companyId == null) {
              _audioPlayer.play(AssetSource('sounds/notification.mp3')).catchError((_) {});
              if (mounted) {
                setState(() {
                  _companyId = newId;
                  _pendingRequest = null; // Clear pending screen immediately
                });
                _fetchCompanyName();
                _fetchAssignedOrders();
              }
            }
            // 🔹 Case 2: Staff was removed from a company
            else if (newId == null && _companyId != null) {
              if (mounted) {
                _showRemovalDialog();
              }
            }

            // Always sync profile and request status just in case
            _fetchStaffProfile();
            _fetchRequestStatus();
          },
        )
        .subscribe();
  }

  Future<void> _joinCompany() async {
    final codeText = _companyCodeCtrl.text.trim();
    if (codeText.isEmpty) {
      _showToast('Please enter a valid Company ID', AppTheme.errorRed);
      return;
    }

    // Basic UUID validation
    final uuidRegex = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
      caseSensitive: false,
    );
    if (!uuidRegex.hasMatch(codeText)) {
      _showToast(
        'Invalid ID format. Please copy the full ID from your owner.',
        AppTheme.errorRed,
      );
      return;
    }

    setState(() => _submittingCode = true);

    try {
      final companyRes = await supabase
          .from('companies')
          .select('id')
          .eq('id', codeText)
          .maybeSingle();

      if (companyRes == null) {
        _showToast('Could not find a company with this ID.', AppTheme.errorRed);
        setState(() => _submittingCode = false);
        return;
      }

      final user = supabase.auth.currentUser;
      if (user != null) {
        await supabase.from('company_join_requests').upsert({
          'staff_id': user.id,
          'company_id': codeText,
          'status': 'pending',
        }, onConflict: 'staff_id, company_id');

        _showToast('Request sent to the owner!', AppTheme.pendingAmber);
        
        // Scenario 1: Notify Owner of join request
        final ownerRes = await supabase
            .from('companies')
            .select('owner_id, name')
            .eq('id', codeText)
            .maybeSingle();
            
        if (ownerRes != null) {
          final ownerId = ownerRes['owner_id'];
          final companyName = ownerRes['name'];
          final res = await NotificationService.sendNotification(
            playerIds: [ownerId],
            title: 'New Staff Request 👤',
            message: '$_staffName wants to join $companyName',
            data: {'type': 'staff_request', 'staff_id': user.id},
            color: 'FFD4A237', // Gold/Amber
          );
          _showToast(res == null ? 'Request Sent' : 'Request sent, but Push failed (Build: 23:00): $res', res == null ? AppTheme.activeEmerald : AppTheme.errorRed);
        }
        
        await _fetchRequestStatus();
      }
    } catch (e) {
      _showToast(
        e.toString().contains('duplicate key')
            ? 'Request already sent'
            : 'Connection error',
        AppTheme.errorRed,
      );
    } finally {
      if (mounted) setState(() => _submittingCode = false);
    }
  }


  void _showToast(String msg, Color color) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: color));
  }

  void _showRemovalDialog() {
    // Stop all company-related subscriptions
    _assignedOrdersSubscription?.unsubscribe();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.background,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: AppTheme.titleColor.withOpacity(0.1)),
        ),
        title: Text(
          'Notice',
          style: TextStyle(color: AppTheme.titleColor, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'You have been removed from the company. Please contact your owner for more information.',
          style: TextStyle(color: AppTheme.labelColor),
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              if (mounted) {
                setState(() {
                  _companyId = null;
                  _companyName = null;
                  _assignedOrders = [];
                });
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.pendingAmber,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(
              'OK',
              style: TextStyle(
                color: AppTheme.titleColor,
                fontWeight: FontWeight.bold,
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
      return Scaffold(
        backgroundColor: AppTheme.background,
        body: Center(
          child: CircularProgressIndicator(color: AppTheme.pendingAmber),
        ),
      );
    }

    if (_companyId == null || _companyId!.isEmpty) {
      if (_pendingRequest != null) return _buildPendingRequestScreen();
      return _buildJoinCompanyScreen();
    }

    return _buildMainDashboard();
  }

  Widget _buildPendingRequestScreen() {
    final companyName =
        (_pendingRequest?['companies'] as Map?)?['name'] ?? 'the Company';
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            onPressed: () async {
              try {
                await supabase
                    .from('company_join_requests')
                    .delete()
                    .eq('id', _pendingRequest!['id']);
                _fetchRequestStatus();
              } catch (_) {}
            },
            icon: Icon(Icons.cancel_outlined, color: AppTheme.labelColor),
          ),
          IconButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => SettingsScreen(
                    role: 'staff',
                    fullName: _staffName,
                  ),
                ),
              );
            },
            icon: Icon(Icons.settings_outlined, color: AppTheme.labelColor),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          _fetchRequestStatus();
          _fetchStaffProfile();
        },
        color: AppTheme.pendingAmber,
        backgroundColor: AppTheme.background,
        child: SingleChildScrollView(
          physics: AlwaysScrollableScrollPhysics(),
          child: Container(
            constraints: BoxConstraints(
              minHeight: MediaQuery.of(context).size.height - 100,
            ),
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.hourglass_empty_rounded,
                      size: 80,
                      color: AppTheme.pendingAmber,
                    ),
                    SizedBox(height: 32),
                    Text(
                      'Request Pending',
                      style: TextStyle(
                        color: AppTheme.titleColor,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 16),
                    Text(
                      'Your request to join "$companyName" is waiting for approval.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppTheme.titleColor.withOpacity(0.6),
                        fontSize: 16,
                      ),
                    ),
                    SizedBox(height: 48),
                    CircularProgressIndicator(color: AppTheme.pendingAmber),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildJoinCompanyScreen() {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => SettingsScreen(
                    role: 'staff',
                    fullName: _staffName,
                  ),
                ),
              );
            },
            icon: Icon(Icons.settings_outlined, color: AppTheme.labelColor),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          _fetchRequestStatus();
          _fetchStaffProfile();
        },
        color: AppTheme.pendingAmber,
        backgroundColor: AppTheme.background,
        child: Center(
          child: SingleChildScrollView(
            physics: AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppTheme.pendingAmber.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.business_center,
                    size: 60,
                    color: AppTheme.pendingAmber,
                  ),
                ),
                SizedBox(height: 32),
                Text(
                  'Join Your Team',
                  style: TextStyle(
                    color: AppTheme.titleColor,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 12),
                Text(
                  'Enter the Company ID provided by your owner to access the dashboard.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppTheme.titleColor.withOpacity(0.5),
                    fontSize: 14,
                  ),
                ),
                SizedBox(height: 48),
                TextField(
                  controller: _companyCodeCtrl,
                  style: TextStyle(
                    color: AppTheme.titleColor,
                    fontFamily: 'monospace',
                  ),
                  decoration: InputDecoration(
                    labelText: 'Company ID',
                    labelStyle: TextStyle(color: AppTheme.labelColor),
                    filled: true,
                    fillColor: AppTheme.titleColor.withOpacity(0.05),
                    prefixIcon: Icon(
                      Icons.vpn_key_outlined,
                      color: AppTheme.pendingAmber,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(color: AppTheme.pendingAmber),
                    ),
                  ),
                ),
                SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 55,
                  child: ElevatedButton(
                    onPressed: _submittingCode ? null : _joinCompany,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.pendingAmber,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: _submittingCode
                        ? SizedBox(
                            height: 24,
                            width: 24,
                            child: CircularProgressIndicator(
                              color: AppTheme.titleColor,
                              strokeWidth: 2,
                            ),
                          )
                        : Text(
                            'JOIN COMPANY',
                            style: TextStyle(
                              color: AppTheme.titleColor,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.2,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMainDashboard() {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Staff Dashboard',
          style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.titleColor),
        ),
        automaticallyImplyLeading: false,
        actions: [
          Stack(
            children: [
              IconButton(
                onPressed: _showNotificationsSheet,
                icon: Icon(Icons.notifications_outlined, color: AppTheme.labelColor),
              ),
              if (_unreadNotificationsCount > 0)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding: EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: AppTheme.errorRed,
                      shape: BoxShape.circle,
                    ),
                    constraints: BoxConstraints(
                      minWidth: 16,
                      minHeight: 16,
                    ),
                    child: Text(
                      '$_unreadNotificationsCount',
                      style: TextStyle(
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
                    role: 'staff',
                    fullName: _staffName,
                  ),
                ),
              );
            },
            icon: Icon(Icons.settings_outlined, color: AppTheme.labelColor),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Hello,',
              style: TextStyle(
                color: AppTheme.titleColor.withOpacity(0.6),
                fontSize: 16,
              ),
            ),
            Text(
              _staffName ?? 'Colleague',
              style: TextStyle(
                color: AppTheme.titleColor,
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 40),
            Container(
              padding: EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppTheme.activeEmerald.withOpacity(0.05),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppTheme.activeEmerald.withOpacity(0.2)),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.check_circle,
                    color: AppTheme.activeEmerald,
                    size: 28,
                  ),
                  SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Connected to Team',
                          style: TextStyle(
                            color: AppTheme.titleColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        Text(
                          _companyName ??
                              'ID: ••••••••${_companyId!.substring(_companyId!.length - 4)}',
                          style: TextStyle(
                            color: AppTheme.titleColor.withOpacity(0.5),
                            fontSize: 12,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 30),

            // Inventory Action
            InkWell(
              onTap: () {
                if (_companyId != null) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => InventoryListScreen(
                        companyId: _companyId!,
                        isOwner: false,
                      ),
                    ),
                  );
                }
              },
              child: Container(
                padding: EdgeInsets.all(20),
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
                      padding: EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryAction.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.inventory_2_outlined,
                        color: AppTheme.primaryAction,
                        size: 24,
                      ),
                    ),
                    SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'View Menu',
                            style: TextStyle(
                              color: AppTheme.titleColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          Text(
                            'Check current food items and recipes',
                            style: TextStyle(
                              color: AppTheme.labelColor,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.arrow_forward_ios_rounded,
                      color: AppTheme.borderColor,
                      size: 16,
                    ),
                  ],
                ),
              ),
            ),

            SizedBox(height: 30),
            SizedBox(height: 30),
            _buildAvailableToClaim(),
            SizedBox(height: 30),
            _buildUpcomingEvents(),
            SizedBox(height: 40),
            
            SizedBox(height: 60),
          ],
        ),
      ),
    );
  }

  Widget _buildAvailableToClaim() {
    final visibleOpenOrders = _openOrders
        .where((o) => !_dismissedOrders.contains(o['id']))
        .toList();

    if (visibleOpenOrders.isEmpty && !_loadingAssignedOrders) {
      return SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Available to Claim',
              style: TextStyle(
                color: AppTheme.titleColor,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.purpleAccent.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.purpleAccent.withOpacity(0.3)),
              ),
              child: Text(
                '${visibleOpenOrders.length} OPEN',
                style: TextStyle(
                  color: Colors.purpleAccent,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: 16),
        if (_loadingAssignedOrders)
          Center(
            child: CircularProgressIndicator(color: AppTheme.pendingAmber),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: NeverScrollableScrollPhysics(),
            itemCount: visibleOpenOrders.length,
            itemBuilder: (context, index) {
              final order = visibleOpenOrders[index];
              return _buildOpenOrderTile(order);
            },
          ),
      ],
    );
  }

  Widget _buildOpenOrderTile(Map<String, dynamic> order) {
    final DateTime eventDate = DateTime.parse(order['event_date']).toLocal();
    final String clientName = order['client_name'] ?? 'Unknown';
    final String displayDate =
        '${eventDate.day}/${eventDate.month}/${eventDate.year} at ${eventDate.hour}:${eventDate.minute.toString().padLeft(2, '0')}';
    final double baseFare = (order['delivery_fare'] as num?)?.toDouble() ?? 0.0;
    final DateTime? biddingEndsAt = order['delivery_bidding_ends_at'] != null
        ? DateTime.parse(order['delivery_bidding_ends_at']).toLocal()
        : null;

    final bidController = _bidControllerFor(order['id']);

    return Container(
      margin: EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.purpleAccent.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.purpleAccent.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  clientName,
                  style: TextStyle(
                    color: AppTheme.titleColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
              Icon(Icons.flash_on, color: Colors.purpleAccent, size: 18),
              SizedBox(width: 8),
              InkWell(
                onTap: () {
                  setState(() {
                    _dismissedOrders.add(order['id']);
                  });
                },
                child: Container(
                  padding: EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: AppTheme.titleColor.withOpacity(0.05),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.close,
                    color: AppTheme.labelColor,
                    size: 16,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.calendar_today, color: AppTheme.labelColor, size: 14),
              SizedBox(width: 8),
              Text(
                displayDate,
                style: TextStyle(color: AppTheme.labelColor, fontSize: 13),
              ),
            ],
          ),
          if (order['venue_address'] != null && order['venue_address'].toString().trim().isNotEmpty) ...[
            SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _openMaps(order['venue_address']),
                icon: Icon(Icons.directions, size: 18),
                label: Text(
                  'Get Directions',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryAction.withOpacity(0.2),
                  foregroundColor: AppTheme.primaryAction,
                  elevation: 0,
                  padding: EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(color: AppTheme.primaryAction.withOpacity(0.5)),
                  ),
                ),
              ),
            ),
          ],
          SizedBox(height: 12),
          Container(
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Base Fare:',
                      style: TextStyle(color: AppTheme.labelColor, fontSize: 12),
                    ),
                    Text(
                      '₹$baseFare',
                      style: TextStyle(
                        color: AppTheme.activeEmerald,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                if (biddingEndsAt != null) ...[
                  SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Ends In:',
                        style: TextStyle(color: AppTheme.labelColor, fontSize: 12),
                      ),
                      Builder(
                        builder: (context) {
                          final now = DateTime.now();
                          if (now.isAfter(biddingEndsAt)) {
                            // Auto-remove expired auction from open list
                            Future.microtask(() {
                              if (mounted) {
                                setState(() {
                                  _dismissedOrders.add(order['id'].toString());
                                });
                              }
                            });
                            return SizedBox.shrink();
                          }
                          final diff = biddingEndsAt.difference(now);
                          return Text(
                            diff.inSeconds < 60
                                ? '${diff.inSeconds}s'
                                : '${diff.inMinutes}m ${diff.inSeconds % 60}s',
                            style: TextStyle(
                              color: AppTheme.pendingAmber,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          SizedBox(height: 12),
          if (biddingEndsAt == null)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _claimDirectDelivery(order['id']),
                icon: Icon(Icons.bolt, color: Colors.black87),
                label: Text(
                  'Fast Claim for ₹${baseFare.toStringAsFixed(0)}',
                  style: TextStyle(
                    color: Colors.black87,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.activeEmerald,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            )
          else
            // Show current bid amount if one exists
            FutureBuilder<Map<String, dynamic>?>(
              future: () async {
              final user = supabase.auth.currentUser;
              if (user == null) return null;
              final res = await supabase
                  .from('delivery_bids')
                  .select('bid_amount')
                  .eq('order_id', order['id'])
                  .eq('staff_id', user.id)
                  .maybeSingle();
              return res;
            }(),
            builder: (context, snapshot) {
              if (!snapshot.hasData || snapshot.data == null) {
                return Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: bidController,
                        keyboardType: TextInputType.number,
                        style: TextStyle(
                          color: AppTheme.titleColor,
                          fontSize: 14,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Your Bid (₹)',
                          hintStyle: TextStyle(
                            color: AppTheme.titleColor.withOpacity(0.2),
                            fontSize: 12,
                          ),
                          filled: true,
                          fillColor: AppTheme.titleColor.withOpacity(0.05),
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () =>
                          _placeBid(order['id'], bidController.text, baseFare),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.purpleAccent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                      child: Text(
                        'BID',
                        style: TextStyle(
                          color: AppTheme.titleColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                );
              }
              final existingBid = (snapshot.data!['bid_amount'] as num)
                  .toDouble();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.activeEmerald.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppTheme.activeEmerald.withOpacity(0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.check_circle_outline,
                          color: AppTheme.activeEmerald,
                          size: 16,
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Your bid: ₹${existingBid.toStringAsFixed(0)}',
                          style: TextStyle(
                            color: AppTheme.activeEmerald,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: bidController,
                          keyboardType: TextInputType.number,
                          style: TextStyle(
                            color: AppTheme.titleColor,
                            fontSize: 14,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Update bid (₹)',
                            hintStyle: TextStyle(
                              color: AppTheme.titleColor.withOpacity(0.2),
                              fontSize: 12,
                            ),
                            filled: true,
                            fillColor: AppTheme.titleColor.withOpacity(0.05),
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                      SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () => _placeBid(
                          order['id'],
                          bidController.text,
                          baseFare,
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.purpleAccent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                        ),
                        child: Text(
                          'UPDATE',
                          style: TextStyle(
                            color: AppTheme.titleColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () => _revokeBid(order['id']),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.errorRed,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                        ),
                        child: Text(
                          'REVOKE',
                          style: TextStyle(
                            color: AppTheme.titleColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _placeBid(
    String orderId,
    String bidText,
    double baseFare,
  ) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    final double? bidAmount = double.tryParse(bidText.trim());
    if (bidAmount == null || bidText.trim().isEmpty) {
      _showToast('Please enter a valid amount', AppTheme.errorRed);
      return;
    }

    if (bidAmount < baseFare) {
      _showToast('Bid must be at least ₹$baseFare', AppTheme.errorRed);
      return;
    }

    try {
      await supabase.from('delivery_bids').upsert({
        'order_id': orderId,
        'staff_id': user.id,
        'bid_amount': bidAmount,
      }, onConflict: 'order_id,staff_id');

      // Notify Owner of the bid
      final orderRes = await supabase
          .from('orders')
          .select('client_name, companies(owner_id)')
          .eq('id', orderId)
          .maybeSingle();
      
      if (orderRes != null && orderRes['companies'] != null) {
        final ownerId = (orderRes['companies'] as Map)['owner_id'];
        final clientName = orderRes['client_name'];
        NotificationService.sendNotification(
          playerIds: [ownerId.toString()],
          title: 'New Bid Received! 🔨',
          message: '$_staffName placed a bid of ₹${bidAmount.toStringAsFixed(0)} for $clientName.',
          data: {'type': 'order_bid', 'order_id': orderId},
          color: 'FF9C27B0', // Purple
        );
      }

      _showToast('Bid placed! ₹${bidAmount.toStringAsFixed(0)}', AppTheme.activeEmerald);
      if (mounted) setState(() {}); // Refresh to show current bid
    } catch (e) {
      _showToast('Error placing bid: $e', AppTheme.errorRed);
    }
  }

  Future<void> _claimDirectDelivery(String orderId) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    try {
      final res = await supabase.rpc(
        'claim_direct_delivery',
        params: {'p_order_id': orderId},
      );

      if (res == true) {
        _showToast('Successfully claimed! ✅', AppTheme.activeEmerald);
        _fetchAssignedOrders();
      } else {
        _showToast('Too slow! Order already claimed.', AppTheme.errorRed);
        if (mounted) {
          setState(() {
            _dismissedOrders.add(orderId);
          });
        }
      }
    } catch (e) {
      _showToast('Error claiming delivery: $e', AppTheme.errorRed);
    }
  }

  Future<void> _revokeBid(String orderId) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    try {
      await supabase
          .from('delivery_bids')
          .delete()
          .eq('order_id', orderId)
          .eq('staff_id', user.id);
      _showToast('Bid revoked', AppTheme.pendingAmber);
      if (mounted) setState(() {}); // Refresh to show bid input again
    } catch (e) {
      _showToast('Error revoking bid: $e', AppTheme.errorRed);
    }
  }

  Future<void> _markAsPicked(Map<String, dynamic> order) async {
    try {
      await supabase
          .from('orders')
          .update({'is_picked': true})
          .eq('id', order['id']);
      _showToast('Order Picked! 🚚', AppTheme.activeEmerald);
      _fetchAssignedOrders();
    } catch (e) {
      _showToast('Error marking as picked: $e', AppTheme.errorRed);
    }
  }


  Future<void> _confirmDelivery(Map<String, dynamic> order) async {
    final clientName = order['client_name'] ?? 'Customer';
    final bytes = await showDialog<dynamic>(
      context: context,
      barrierDismissible: false,
      builder: (_) => SignaturePadDialog(clientName: clientName),
    );
    if (bytes == null || !mounted) return;
    try {
      final base64Sig = base64Encode(bytes as List<int>);
      await supabase
          .from('orders')
          .update({
            'delivery_signature': base64Sig,
            'order_status': 'completed',
          })
          .eq('id', order['id']);

      // Scenario 6: Notify Owner of delivery
      final orderRes = await supabase
          .from('orders')
          .select('client_name, companies(owner_id)')
          .eq('id', order['id'])
          .maybeSingle();

      if (orderRes != null && orderRes['companies'] != null) {
        final ownerId = (orderRes['companies'] as Map)['owner_id'];
        await NotificationService.sendNotification(
          playerIds: [ownerId],
          title: 'Order Delivered! ✅',
          message:
              'Order for ${orderRes['client_name']} has been marked as delivered by $_staffName.',
          data: {'type': 'order_delivered', 'order_id': order['id']},
          color: 'FF4CAF50', // Green
          companyId: _companyId,
        );
      }

      _showToast('Delivery confirmed! ✅', AppTheme.activeEmerald);
      _fetchAssignedOrders();
    } catch (e) {
      _showToast('Error confirming: $e', AppTheme.errorRed);
    }
  }

  Widget _buildUpcomingEvents() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Your Assigned Deliveries',
          style: TextStyle(
            color: AppTheme.titleColor,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        SizedBox(height: 16),
        if (_loadingAssignedOrders)
          Center(
            child: CircularProgressIndicator(color: AppTheme.pendingAmber),
          )
        else if (_assignedOrders.isEmpty)
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(40),
            decoration: BoxDecoration(
              color: AppTheme.pendingAmber.withOpacity(0.02),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: AppTheme.pendingAmber.withOpacity(0.1),
                width: 1,
              ),
            ),
            child: Center(
              child: Column(
                children: [
                  Icon(
                    Icons.assignment_outlined,
                    color: AppTheme.pendingAmber.withOpacity(0.2),
                    size: 48,
                  ),
                  SizedBox(height: 16),
                  Text(
                    'No deliveries assigned to you right now.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppTheme.titleColor.withOpacity(0.3)),
                  ),
                ],
              ),
            ),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: NeverScrollableScrollPhysics(),
            itemCount: _assignedOrders.length,
            itemBuilder: (context, index) {
              final order = _assignedOrders[index];
              return _buildAssignedOrderTile(order);
            },
          ),
      ],
    );
  }

  Widget _buildAssignedOrderTile(Map<String, dynamic> order) {
    final DateTime eventDate = DateTime.parse(order['event_date']).toLocal();
    final String clientName = order['client_name'] ?? 'Unknown';
    // Format date nicely
    final String displayDate =
        '${eventDate.day}/${eventDate.month}/${eventDate.year} at ${eventDate.hour}:${eventDate.minute.toString().padLeft(2, '0')}';
    final double? fare = (order['delivery_fare'] as num?)?.toDouble();

    return Container(
      margin: EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.titleColor.withOpacity(0.03),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  clientName,
                  style: TextStyle(
                    color: AppTheme.titleColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
              if (fare != null)
                Text(
                  '₹$fare',
                  style: TextStyle(
                    color: AppTheme.activeEmerald,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: (order['order_status'] == 'completed')
                      ? AppTheme.activeEmerald.withOpacity(0.1)
                      : AppTheme.pendingAmber.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  (order['order_status'] == 'completed') ? 'Delivered' : 'Upcoming',
                  style: TextStyle(
                    color: (order['order_status'] == 'completed')
                        ? AppTheme.activeEmerald
                        : AppTheme.pendingAmber,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.calendar_today, color: AppTheme.labelColor, size: 14),
              SizedBox(width: 8),
              Text(
                displayDate,
                style: TextStyle(color: AppTheme.labelColor, fontSize: 13),
              ),
            ],
          ),
          if (order['order_status'] != 'completed') ...[
            if (order['venue_address'] != null &&
                order['venue_address'].toString().trim().isNotEmpty) ...[
              SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _openMaps(order['venue_address']),
                  icon: Icon(Icons.directions, size: 18),
                  label: Text(
                    'Get Directions',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryAction.withOpacity(0.2),
                    foregroundColor: AppTheme.primaryAction,
                    elevation: 0,
                    padding: EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: BorderSide(
                          color: AppTheme.primaryAction.withOpacity(0.5)),
                    ),
                  ),
                ),
              ),
            ],
            if (order['middleman_tag'] != null &&
                order['middleman_tag'].toString().contains('(')) ...[
              SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () =>
                      _shareLocationWithMiddleman(order['middleman_tag']),
                  icon: Icon(Icons.share_location, size: 18),
                  label: Text(
                    'Share My Location with Middleman',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.activeEmerald.withOpacity(0.2),
                    foregroundColor: AppTheme.activeEmerald,
                    elevation: 0,
                    padding: EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: BorderSide(
                          color: AppTheme.activeEmerald.withOpacity(0.5)),
                    ),
                  ),
                ),
              ),
            ],
            SizedBox(height: 12),
            Divider(color: AppTheme.borderColor),
            SizedBox(height: 8),
            Text(
              'Order Items:',
              style: TextStyle(color: AppTheme.labelColor, fontSize: 12),
            ),
            SizedBox(height: 4),
            ...(order['menu_items'] as List? ?? []).map((item) {
              return Row(
                children: [
                  Text('• ',
                      style: TextStyle(color: AppTheme.pendingAmber)),
                  Text(
                    '${item['quantity']}x ${item['name']}',
                    style: TextStyle(color: AppTheme.labelColor, fontSize: 13),
                  ),
                ],
              );
            }),
            SizedBox(height: 12),
            if (order['is_picked'] != true && order['delivery_signature'] == null)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _markAsPicked(order),
                  icon: Icon(
                    Icons.local_shipping_outlined,
                    color: Colors.black87,
                    size: 18,
                  ),
                  label: Text(
                    'Mark Order Picked 🚚',
                    style: TextStyle(
                      color: Colors.black87,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.pendingAmber,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: EdgeInsets.symmetric(vertical: 12),
                    elevation: 0,
                  ),
                ),
              ),
            if (order['is_picked'] == true && order['delivery_signature'] == null)
              SizedBox(
                width: double.infinity,
                child: Container(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: AppTheme.activeEmerald.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.activeEmerald.withOpacity(0.5)),
                  ),
                  child: Center(
                    child: Text(
                      '🚚 Order Picked Up',
                      style: TextStyle(
                        color: AppTheme.activeEmerald,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ),
            SizedBox(height: 8),
            if (order['delivery_signature'] == null)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _confirmDelivery(order),
                  icon: Icon(
                    Icons.draw_outlined,
                    color: Colors.black87,
                    size: 18,
                  ),
                  label: Text(
                    'Order Delivered (Get Signature)',
                    style: TextStyle(
                      color: Colors.black87,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.activeEmerald,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: EdgeInsets.symmetric(vertical: 12),
                    elevation: 0,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Future<void> _fetchAssignedOrders() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    // 1. Try Loading from Cache
    final cachedAssigned = CacheService.get('assigned_orders_${user.id}');
    final cachedOpen = _companyId != null ? CacheService.get('open_orders_$_companyId') : null;
    
    if (mounted) {
      setState(() {
        if (cachedAssigned != null) {
          _assignedOrders = (cachedAssigned as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        }
        if (cachedOpen != null) {
          _openOrders = (cachedOpen as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        }
        _loadingAssignedOrders = (cachedAssigned == null && cachedOpen == null);
      });
    }

    try {
      // Always fetch orders assigned to this staff member (upcoming and completed)
      final resAssigned = await supabase
          .from('orders')
          .select()
          .eq('delivery_staff_id', user.id)
          .inFilter('order_status', ['upcoming', 'completed']);

      final assignedList = List<Map<String, dynamic>>.from(resAssigned);
      assignedList.sort((a, b) {
        final aUpcoming = a['order_status'] == 'upcoming';
        final bUpcoming = b['order_status'] == 'upcoming';
        if (aUpcoming && !bUpcoming) return -1;
        if (!aUpcoming && bUpcoming) return 1;
        
        final aDate = DateTime.parse(a['event_date']);
        final bDate = DateTime.parse(b['event_date']);
        if (aUpcoming) {
          return aDate.compareTo(bDate); // soonest upcoming first
        } else {
          return bDate.compareTo(aDate); // most recent completed first
        }
      });

      // Only fetch open (claimable) orders if we know the company
      List<dynamic> resOpen = [];
      if (_companyId != null) {
        resOpen = await supabase
            .from('orders')
            .select()
            .eq('company_id', _companyId!)
            .eq('is_delivery_open', true)
            .eq('order_status', 'upcoming')
            .isFilter('delivery_staff_id', null)
            .order('event_date');
      }

      if (mounted) {
        setState(() {
          _assignedOrders = assignedList;
          _openOrders = List<Map<String, dynamic>>.from(resOpen);
          _loadingAssignedOrders = false;
        });

        // 2. Save to Cache
        CacheService.save('assigned_orders_${user.id}', assignedList);
        if (_companyId != null) {
          CacheService.save('open_orders_$_companyId', resOpen);
        }
      }
    } catch (e) {
      debugPrint('Error fetching assigned/open orders: $e');
      if (mounted) setState(() => _loadingAssignedOrders = false);
    }
  }

  void _setupAssignedOrdersRealtime() {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    _assignedOrdersSubscription?.unsubscribe();
    _assignedOrdersSubscription = supabase
        .channel('staff_orders_${user.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'orders',
          callback: (payload) {
            debugPrint('REALTIME ORDER UPDATE: ${payload.eventType}');
            
            final newRecord = payload.newRecord;
            final oldRecord = payload.oldRecord;
            final isNowOpen = newRecord['is_delivery_open'] == true;
            final wasOpen = oldRecord['is_delivery_open'] == true;

            // 🔔 New auction opened
            if (isNowOpen && !wasOpen) {
              _audioPlayer.play(AssetSource('sounds/notification.mp3'));
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Row(
                      children: [
                        Icon(
                          Icons.local_shipping,
                          color: AppTheme.titleColor,
                          size: 18,
                        ),
                        SizedBox(width: 8),
                        Text('New delivery auction opened! Place your bid.'),
                      ],
                    ),
                    backgroundColor: Colors.deepPurple,
                    duration: Duration(seconds: 5),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            }

            // 🏁 Auction just closed (is_delivery_open went true → false)
            if (wasOpen && !isNowOpen && newRecord.isNotEmpty) {
              final assignedStaffId = newRecord['delivery_staff_id'];
              final clientName = newRecord['client_name'] ?? 'order';
              final orderId = newRecord['id'];

              // Remove from open list immediately
              if (mounted) {
                setState(() {
                  _dismissedOrders.add(orderId.toString());
                });
              }

              final wasAssignedToMe = assignedStaffId == user.id;

              if (wasAssignedToMe) {
                // 🎉 Win notification
                _audioPlayer.play(AssetSource('sounds/notification.mp3'));
                if (mounted) {
                  final fare =
                      (newRecord['delivery_fare'] as num?)?.toStringAsFixed(
                        0,
                      ) ??
                      '?';
                  final eventDate = newRecord['event_date'] != null
                      ? DateTime.parse(newRecord['event_date']).toLocal()
                      : null;
                  final dateStr = eventDate != null
                      ? '${eventDate.day}/${eventDate.month}/${eventDate.year}'
                      : '';
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Row(
                        children: [
                          Icon(
                            Icons.emoji_events,
                            color: Colors.amber,
                            size: 20,
                          ),
                          SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'You got the delivery! 🎉',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.titleColor,
                                  ),
                                ),
                                Text(
                                  '$clientName  •  ₹$fare  •  $dateStr',
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
                      backgroundColor: Color(0xFF1B5E20),
                      duration: Duration(seconds: 7),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              } else {
                // ❌ Not selected notification
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Row(
                        children: [
                          Icon(
                            Icons.cancel_outlined,
                            color: AppTheme.labelColor,
                            size: 18,
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Auction for "$clientName" ended — you were not selected.',
                              style: TextStyle(color: AppTheme.labelColor),
                            ),
                          ),
                        ],
                      ),
                      backgroundColor: Color(0xFF37474F),
                      duration: Duration(seconds: 5),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              }
            }

            _fetchAssignedOrders();
          },
        )
        .subscribe();
  }

  void _toast(String message) {
    _showToast(message, AppTheme.pendingAmber);
  }
}
