import 'package:mobile_app/core/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../services/notification_service.dart';

class CreateOrderScreen extends StatefulWidget {
  final String companyId;
  final Map<String, dynamic>? orderToEdit;

  CreateOrderScreen({super.key, required this.companyId, this.orderToEdit});

  @override
  State<CreateOrderScreen> createState() => _CreateOrderScreenState();
}

class _CreateOrderScreenState extends State<CreateOrderScreen> {
  final _formKey = GlobalKey<FormState>();
  final _supabase = Supabase.instance.client;

  // Form Fields
  final _clientNameController = TextEditingController();
  final _venueAddressController = TextEditingController();
  final _totalController = TextEditingController();

  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;

  String _paymentStatus = 'pending';
  String _orderType = 'direct'; // 'direct' or 'middleman'

  // Middleman dropdown
  List<Map<String, dynamic>> _middleMen = [];
  Map<String, dynamic>? _selectedMiddleMan;

  // Menu Item Selection
  List<Map<String, dynamic>> _availableMenuItems = [];
  final List<Map<String, dynamic>> _selectedItems = [];
  List<String> _units = ['kgs', 'litres', 'boxes', 'units'];

  bool _isLoading = false;
  bool _isFetchingMenu = true;

  @override
  void initState() {
    super.initState();
    _fetchMenuItems();
    _fetchUnits();
    _fetchMiddleMen();
    
    if (widget.orderToEdit != null) {
      _clientNameController.text = widget.orderToEdit!['client_name'] ?? '';
      _venueAddressController.text = widget.orderToEdit!['venue_address'] ?? '';
      _totalController.text = widget.orderToEdit!['total_value']?.toString() ?? '';
      _paymentStatus = widget.orderToEdit!['payment_status'] ?? 'pending';
      
      final dt = DateTime.tryParse(widget.orderToEdit!['event_date'] ?? '');
      if (dt != null) {
        _selectedDate = dt.toLocal();
        _selectedTime = TimeOfDay.fromDateTime(_selectedDate!);
      }

      final middlemanTag = widget.orderToEdit!['middleman_tag'] as String?;
      if (middlemanTag != null && middlemanTag.isNotEmpty) {
        _orderType = 'middleman';
      }

      final menuItems = widget.orderToEdit!['menu_items'] as List<dynamic>? ?? [];
      for (var item in menuItems) {
         _selectedItems.add({
           'id': item['id'] ?? item['name'],
           'name': item['name'],
           'quantity': item['quantity'],
           'quantity_type': item['quantity_type'] ?? 'fixed',
         });
      }
    }
  }

  Future<void> _fetchMiddleMen() async {
    try {
      final data = await _supabase
          .from('middle_men')
          .select('id, name, phone_number, total_balance')
          .eq('company_id', widget.companyId)
          .order('name');
      if (mounted) {
        setState(() {
          _middleMen = List<Map<String, dynamic>>.from(data);
          
          if (widget.orderToEdit != null && widget.orderToEdit!['middleman_tag'] != null) {
            final tag = widget.orderToEdit!['middleman_tag'] as String;
            final regExp = RegExp(r'\((.*?)\)');
            final match = regExp.firstMatch(tag);
            final phone = match?.group(1)?.replaceAll(RegExp(r'[^\d+]'), '') ?? '';
            
            try {
              _selectedMiddleMan = _middleMen.firstWhere(
                (m) => m['phone_number'].toString().replaceAll(RegExp(r'[^\d+]'), '') == phone
              );
            } catch (_) {}
          }
        });
      }
    } catch (e) {
      debugPrint('Error fetching middle men: $e');
    }
  }

  Future<void> _fetchUnits() async {
    try {
      final data = await _supabase
          .from('inventory_units')
          .select('name')
          .eq('company_id', widget.companyId);
      final dbUnits = (data as List).map((e) => e['name'] as String).toList();
      setState(() {
        _units = {
          ...['kgs', 'litres', 'boxes', 'units'],
          ...dbUnits,
        }.toList();
      });
    } catch (e) {
      debugPrint('Error fetching units: $e');
    }
  }

  @override
  void dispose() {
    _clientNameController.dispose();
    _venueAddressController.dispose();
    _totalController.dispose();
    super.dispose();
  }

  Future<void> _fetchMenuItems() async {
    try {
      final data = await _supabase
          .from('inventory_items')
          .select('id, name, category')
          .eq('company_id', widget.companyId)
          .order('name');

      if (mounted) {
        setState(() {
          _availableMenuItems = List<Map<String, dynamic>>.from(data);
          _isFetchingMenu = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching inventory: $e');
      if (mounted) setState(() => _isFetchingMenu = false);
    }
  }

  Future<void> _pickDateAndTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(Duration(days: 365 * 2)),
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: ColorScheme.dark(
              primary: AppTheme.pendingAmber,
              onPrimary: Colors.black,
              surface: AppTheme.background,
              onSurface: AppTheme.titleColor,
            ),
          ),
          child: child!,
        );
      },
    );

    if (date != null && mounted) {
      final time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.now(),
        builder: (context, child) {
          return Theme(
            data: ThemeData.dark().copyWith(
              colorScheme: ColorScheme.dark(
                primary: AppTheme.pendingAmber,
                onPrimary: Colors.black,
                surface: AppTheme.background,
                onSurface: AppTheme.titleColor,
              ),
            ),
            child: child!,
          );
        },
      );
      if (time != null) {
        setState(() {
          _selectedDate = date;
          _selectedTime = time;
        });
      }
    }
  }

  Future<void> _showQuickAddItemDialog(
    Function(void Function()) setSheetState,
  ) async {
    final nameCtrl = TextEditingController();
    final qtyCtrl = TextEditingController();
    String selectedCategory = 'Produce';
    String selectedUnit = 'kgs';

    final categories = [
      'Produce',
      'Meat & Poultry',
      'Dairy',
      'Dry Goods',
      'Beverages',
      'Equipment',
      'Other',
    ];

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppTheme.background,
          title: Text(
            'Quick Add Item',
            style: TextStyle(color: AppTheme.titleColor),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  style: TextStyle(color: AppTheme.titleColor),
                  decoration: InputDecoration(
                    labelText: 'Item Name',
                    labelStyle: TextStyle(color: AppTheme.labelColor),
                  ),
                ),
                TextField(
                  controller: qtyCtrl,
                  keyboardType: TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  style: TextStyle(color: AppTheme.titleColor),
                  decoration: InputDecoration(
                    labelText: 'Initial Quantity',
                    labelStyle: TextStyle(color: AppTheme.labelColor),
                  ),
                ),
                DropdownButtonFormField<String>(
                  initialValue: selectedCategory,
                  dropdownColor: AppTheme.background,
                  items: categories
                      .map(
                        (c) => DropdownMenuItem(
                          value: c,
                          child: Text(
                            c,
                            style: TextStyle(color: AppTheme.titleColor),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (val) =>
                      setDialogState(() => selectedCategory = val!),
                  decoration: InputDecoration(
                    labelText: 'Category',
                    labelStyle: TextStyle(color: AppTheme.labelColor),
                  ),
                ),
                DropdownButtonFormField<String>(
                  initialValue: selectedUnit,
                  dropdownColor: AppTheme.background,
                  items: _units
                      .map(
                        (u) => DropdownMenuItem(
                          value: u,
                          child: Text(
                            u,
                            style: TextStyle(color: AppTheme.titleColor),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (val) => setDialogState(() => selectedUnit = val!),
                  decoration: InputDecoration(
                    labelText: 'Unit',
                    labelStyle: TextStyle(color: AppTheme.labelColor),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (nameCtrl.text.isEmpty) return;
                try {
                  final newItem = await _supabase
                      .from('inventory_items')
                      .insert({
                        'company_id': widget.companyId,
                        'name': nameCtrl.text.trim(),
                        'category': selectedCategory,
                        'quantity': double.tryParse(qtyCtrl.text) ?? 0,
                        'unit': selectedUnit,
                      })
                      .select()
                      .single();

                  setState(() {
                    _availableMenuItems.add(newItem);
                    _availableMenuItems.sort(
                      (a, b) => a['name'].compareTo(b['name']),
                    );
                    _selectedItems.add({
                      'id': newItem['id'],
                      'name': newItem['name'],
                      'quantity': 1,
                      'quantity_type': 'fixed',
                    });
                  });
                  setSheetState(() {});
                  if (mounted) Navigator.pop(context);
                } catch (e) {
                  debugPrint('Error quick adding item: $e');
                }
              },
              child: Text('Save & Select'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showAddMiddleManDialog() async {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    bool isSaving = false;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppTheme.background,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(
            'Add New Middleman',
            style: TextStyle(color: AppTheme.titleColor, fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ElevatedButton.icon(
                onPressed: () async {
                  if (kIsWeb) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Contact import is only available on mobile devices.',
                        ),
                        backgroundColor: AppTheme.pendingAmber,
                      ),
                    );
                    return;
                  }
                  try {
                    bool permissionGranted =
                        await Permission.contacts.isGranted;
                    if (!permissionGranted) {
                      permissionGranted = await Permission.contacts
                          .request()
                          .isGranted;
                    }

                    if (permissionGranted) {
                      final Contact? contact =
                          await FlutterContacts.openExternalPick();
                      if (contact != null) {
                        final fullContact = await FlutterContacts.getContact(
                          contact.id,
                        );
                        if (fullContact != null) {
                          setDialogState(() {
                            nameCtrl.text = fullContact.displayName;
                            if (fullContact.phones.isNotEmpty) {
                              // Sanitize phone number (remove spaces, etc.)
                              String phone = fullContact.phones.first.number;
                              phoneCtrl.text = phone.replaceAll(
                                RegExp(r'\s+'),
                                '',
                              );
                            }
                          });
                        }
                      }
                    } else {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Contact permission denied. Please enable it in settings.',
                            ),
                            backgroundColor: AppTheme.errorRed,
                          ),
                        );
                      }
                    }
                  } catch (e) {
                    debugPrint('Error picking contact: $e');
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Could not import contact: $e')),
                      );
                    }
                  }
                },
                icon: Icon(Icons.contact_phone, size: 18),
                label: Text('Import from Contacts'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.pendingAmber.withOpacity(0.1),
                  foregroundColor: AppTheme.pendingAmber,
                  elevation: 0,
                  minimumSize: Size(double.infinity, 45),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              SizedBox(height: 16),
              TextField(
                controller: nameCtrl,
                style: TextStyle(color: AppTheme.titleColor),
                decoration: InputDecoration(
                  labelText: 'Middleman Name',
                  labelStyle: TextStyle(color: AppTheme.labelColor),
                  prefixIcon: Icon(
                    Icons.person,
                    color: AppTheme.pendingAmber,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppTheme.borderColor),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppTheme.pendingAmber),
                  ),
                ),
              ),
              SizedBox(height: 12),
              TextField(
                controller: phoneCtrl,
                style: TextStyle(color: AppTheme.titleColor),
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: 'Phone Number',
                  labelStyle: TextStyle(color: AppTheme.labelColor),
                  prefixIcon: Icon(
                    Icons.phone,
                    color: AppTheme.pendingAmber,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppTheme.borderColor),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppTheme.pendingAmber),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'Cancel',
                style: TextStyle(color: AppTheme.labelColor),
              ),
            ),
            ElevatedButton(
              onPressed: isSaving
                  ? null
                  : () async {
                      if (nameCtrl.text.isEmpty || phoneCtrl.text.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Please fill all fields'),
                          ),
                        );
                        return;
                      }
                      setDialogState(() => isSaving = true);
                      try {
                        final res = await _supabase
                            .from('middle_men')
                            .insert({
                              'company_id': widget.companyId,
                              'name': nameCtrl.text.trim(),
                              'phone_number': phoneCtrl.text.trim(),
                              'total_balance': 0,
                            })
                            .select()
                            .single();

                        if (mounted) {
                          setState(() {
                            // Local update for instant feedback
                            final man = Map<String, dynamic>.from(res);
                            _middleMen.add(man);
                            _middleMen.sort(
                              (a, b) => (a['name'] as String).compareTo(
                                b['name'] as String,
                              ),
                            );
                            _selectedMiddleMan = man;
                          });
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Middleman added successfully'),
                              backgroundColor: AppTheme.activeEmerald,
                            ),
                          );
                        }
                      } catch (e) {
                        debugPrint('Error adding middleman: $e');
                        if (mounted) {
                          ScaffoldMessenger.of(
                            context,
                          ).showSnackBar(SnackBar(content: Text('Error: $e')));
                        }
                      } finally {
                        if (mounted) setDialogState(() => isSaving = false);
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.pendingAmber,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: isSaving
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.black,
                      ),
                    )
                  : Text('Save & Select'),
            ),
          ],
        ),
      ),
    );
  }

  void _showItemSelectorBottomSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.background,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return FractionallySizedBox(
              heightFactor: 0.8,
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Select Menu Items',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.titleColor,
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () =>
                              _showQuickAddItemDialog(setSheetState),
                          icon: Icon(
                            Icons.add_circle_outline,
                            color: AppTheme.pendingAmber,
                          ),
                          label: Text(
                            'Create New',
                            style: TextStyle(color: AppTheme.pendingAmber),
                          ),
                        ),
                      ],
                    ),
                    Divider(color: AppTheme.borderColor),
                    Expanded(
                      child: _availableMenuItems.isEmpty
                          ? Center(
                              child: Text(
                                "No items configured yet.",
                                style: TextStyle(color: AppTheme.labelColor),
                              ),
                            )
                          : ListView.builder(
                              itemCount: _availableMenuItems.length,
                              itemBuilder: (context, index) {
                                final item = _availableMenuItems[index];
                                final isSelected = _selectedItems.any(
                                  (e) => e['id'] == item['id'],
                                );

                                return ListTile(
                                  title: Text(
                                    item['name'],
                                    style: TextStyle(color: AppTheme.titleColor),
                                  ),
                                  trailing: isSelected
                                      ? Icon(
                                          Icons.check_circle,
                                          color: AppTheme.pendingAmber,
                                        )
                                      : Icon(
                                          Icons.circle_outlined,
                                          color: AppTheme.borderColor,
                                        ),
                                  onTap: () {
                                    setState(() {
                                      if (isSelected) {
                                        _selectedItems.removeWhere(
                                          (e) => e['id'] == item['id'],
                                        );
                                      } else {
                                        _selectedItems.add({
                                          'id': item['id'],
                                          'name': item['name'],
                                          'quantity': 1,
                                          'quantity_type': 'fixed',
                                        });
                                      }
                                    });
                                    setSheetState(() {});
                                  },
                                );
                              },
                            ),
                    ),
                    SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.pendingAmber,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: () => Navigator.pop(context),
                        child: Text(
                          'Done',
                          style: TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _toast(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: AppTheme.pendingAmber),
      );
    }
  }

  Future<void> _submitOrder() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedDate == null || _selectedTime == null) {
      _toast('Please select an Event Date & Time');
      return;
    }
    if (_selectedItems.isEmpty) {
      _toast('Please select at least one Menu Item');
      return;
    }
    if (_orderType == 'middleman' && _selectedMiddleMan == null) {
      _toast('Please select a middleman');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final eventDateTime = DateTime(
        _selectedDate!.year,
        _selectedDate!.month,
        _selectedDate!.day,
        _selectedTime!.hour,
        _selectedTime!.minute,
      ).toUtc().toIso8601String();

      final totalValue = double.tryParse(_totalController.text) ?? 0.0;

      final menuItemsJson = _selectedItems
          .map(
            (item) => {
              'name': item['name'],
              'quantity': item['quantity'],
              'quantity_type': item['quantity_type'] ?? 'fixed',
            },
          )
          .toList();

      String? middlemanTag;
      if (_orderType == 'middleman' && _selectedMiddleMan != null) {
        final name = _selectedMiddleMan?['name'] ?? 'Unknown';
        final phone = _selectedMiddleMan?['phone_number'] ?? '';
        middlemanTag = '$name ($phone)';
      }

      final isEdit = widget.orderToEdit != null;
      
      final orderData = {
        'company_id': widget.companyId,
        'client_name': _clientNameController.text.trim(),
        'venue_address': _venueAddressController.text.trim(),
        'event_date': eventDateTime,
        'menu_items': menuItemsJson,
        'middleman_tag': middlemanTag,
        'total_value': totalValue,
        'payment_status': _paymentStatus,
        'is_khata_saved': _orderType == 'middleman' && _selectedMiddleMan != null,
      };

      if (!isEdit) {
        orderData['order_status'] = 'upcoming';
        await _supabase.from('orders').insert(orderData);
      } else {
        await _supabase.from('orders').update(orderData).eq('id', widget.orderToEdit!['id']);
      }

      // 🔹 Schedule Multi-Tier Reminder Notifications
      try {
        final eventDate = DateTime.parse(eventDateTime);
        final now = DateTime.now().toUtc();
        final user = _supabase.auth.currentUser;
        
        if (user != null) {
          final clientName = _clientNameController.text.trim();
          final formattedTime = DateFormat('h:mm a').format(eventDate.toLocal());

          // 1. Standard Reminder (6 hours before)
          final reminder6h = eventDate.subtract(Duration(hours: 6));
          if (reminder6h.isAfter(now)) {
            NotificationService.sendNotification(
              playerIds: [user.id], // Owner/Creator
              title: 'Catering Ops: Upcoming Order! ⏰',
              message: 'Reminder: Order for $clientName is scheduled for $formattedTime.',
              data: {'type': 'order_reminder'},
              color: 'FFFF9800', // Orange
              sendAfter: reminder6h,
            );
          }

          // 2. Emergency Reminder (2 hours before)
          final reminder2h = eventDate.subtract(Duration(hours: 2));
          if (reminder2h.isAfter(now)) {
            NotificationService.sendNotification(
              playerIds: [user.id],
              title: '🚨 EMERGENCY: Order Starting Soon! 🚨',
              message: 'URGENT: Order for $clientName starts in 2 hours ($formattedTime)!',
              data: {'type': 'order_reminder'},
              color: 'FFF44336', // Red
              sendAfter: reminder2h,
            );
          }
        }
      } catch (e) {
        debugPrint('Error scheduling reminders: $e');
      }

      // Handle Khata balance updates
      if (!isEdit) {
        if (_orderType == 'middleman' &&
            _selectedMiddleMan != null &&
            _paymentStatus == 'pending') {
          final manId = _selectedMiddleMan?['id'];
          final currentBalance =
              (_selectedMiddleMan?['total_balance'] as num?)?.toDouble() ?? 0.0;
          if (manId != null) {
            await _supabase
                .from('middle_men')
                .update({'total_balance': currentBalance + totalValue})
                .eq('id', manId);
          }
        }
      } else {
        final oldOrder = widget.orderToEdit!;
        final wasKhataSaved = oldOrder['is_khata_saved'] == true;
        final oldManTag = oldOrder['middleman_tag'] as String?;
        final oldTotal = (oldOrder['total_value'] as num?)?.toDouble() ?? 0.0;
        
        // Reverse old balance
        if (wasKhataSaved && oldManTag != null) {
          final regExp = RegExp(r'\((.*?)\)');
          final match = regExp.firstMatch(oldManTag);
          final oldPhone = match?.group(1)?.replaceAll(RegExp(r'[^\d+]'), '') ?? '';
          final oldManRes = await _supabase.from('middle_men').select().eq('company_id', widget.companyId).eq('phone_number', oldPhone).maybeSingle();
          if (oldManRes != null) {
            final oldCurrentBalance = (oldManRes['total_balance'] as num?)?.toDouble() ?? 0.0;
            await _supabase.from('middle_men').update({'total_balance': oldCurrentBalance - oldTotal}).eq('id', oldManRes['id']);
          }
        }

        // Apply new balance
        if (_orderType == 'middleman' && _selectedMiddleMan != null && _paymentStatus == 'pending') {
          final manId = _selectedMiddleMan!['id'];
          final manRes = await _supabase.from('middle_men').select().eq('id', manId).maybeSingle();
          if (manRes != null) {
            final currentBalance = (manRes['total_balance'] as num?)?.toDouble() ?? 0.0;
            await _supabase.from('middle_men').update({'total_balance': currentBalance + totalValue}).eq('id', manId);
          }
        }
      }

      _toast(isEdit ? 'Order updated successfully!' : 'Order created successfully!');
      if (mounted) Navigator.pop(context);
    } catch (e) {
      _toast('Error creating order: $e');
      setState(() => _isLoading = false);
    }
  }

  String get _formattedDateTime {
    if (_selectedDate == null || _selectedTime == null) {
      return 'Select Date & Time';
    }
    final dt = DateTime(
      _selectedDate!.year,
      _selectedDate!.month,
      _selectedDate!.day,
      _selectedTime!.hour,
      _selectedTime!.minute,
    );
    return DateFormat('MMM dd, yyyy - h:mm a').format(dt);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(
          widget.orderToEdit != null ? 'Edit Order' : 'Create Order',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isFetchingMenu
          ? Center(
              child: CircularProgressIndicator(color: AppTheme.pendingAmber),
            )
          : Form(
              key: _formKey,
              child: ListView(
                padding: EdgeInsets.all(24),
                children: [
                  // Client Name
                  TextFormField(
                    controller: _clientNameController,
                    style: TextStyle(color: AppTheme.titleColor),
                    decoration: InputDecoration(
                      labelText: 'Client / Event Name',
                      labelStyle: TextStyle(color: AppTheme.labelColor),
                      prefixIcon: Icon(
                        Icons.person_outline,
                        color: AppTheme.pendingAmber,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: AppTheme.borderColor),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(
                          color: AppTheme.pendingAmber,
                        ),
                      ),
                    ),
                    validator: (v) => v == null || v.isEmpty
                        ? 'Client name is required'
                        : null,
                  ),
                  SizedBox(height: 20),

                  // Venue Address
                  TextFormField(
                    controller: _venueAddressController,
                    style: TextStyle(color: AppTheme.titleColor),
                    decoration: InputDecoration(
                      labelText: 'Venue Address (for Maps)',
                      labelStyle: TextStyle(color: AppTheme.labelColor),
                      prefixIcon: Icon(
                        Icons.location_on_outlined,
                        color: AppTheme.pendingAmber,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: AppTheme.borderColor),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(
                          color: AppTheme.pendingAmber,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: 20),

                  // Date & Time Picker
                  InkWell(
                    onTap: _pickDateAndTime,
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 20,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.titleColor.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppTheme.borderColor),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.calendar_today,
                            color: AppTheme.pendingAmber,
                          ),
                          SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Event Date & Time',
                                  style: TextStyle(
                                    color: AppTheme.titleColor.withOpacity(0.5),
                                    fontSize: 12,
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  _formattedDateTime,
                                  style: TextStyle(
                                    color: AppTheme.titleColor,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.arrow_forward_ios,
                            color: AppTheme.borderColor,
                            size: 16,
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(height: 24),

                  // Menu Items Section
                  // Menu Items Section header
                  Text(
                    'Menu Items',
                    style: TextStyle(
                      color: AppTheme.titleColor,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 12),

                  // Big tap target to select items
                  if (_selectedItems.isEmpty)
                    GestureDetector(
                      onTap: _showItemSelectorBottomSheet,
                      child: Container(
                        width: double.infinity,
                        padding: EdgeInsets.symmetric(vertical: 24),
                        decoration: BoxDecoration(
                          color: AppTheme.pendingAmber.withOpacity(0.07),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: AppTheme.pendingAmber.withOpacity(0.5),
                            width: 1.5,
                          ),
                        ),
                        child: Column(
                          children: [
                            Icon(
                              Icons.restaurant_menu,
                              color: AppTheme.pendingAmber,
                              size: 36,
                            ),
                            SizedBox(height: 8),
                            Text(
                              'Tap to Select Menu Items',
                              style: TextStyle(
                                color: AppTheme.pendingAmber,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Choose from your inventory',
                              style: TextStyle(
                                color: AppTheme.labelColor,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    Column(
                      children: [
                        Container(
                          padding: EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppTheme.titleColor.withOpacity(0.04),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: AppTheme.pendingAmber.withOpacity(0.3),
                            ),
                          ),
                          child: Column(
                            children: _selectedItems.map((item) {
                              return Container(
                                margin: EdgeInsets.only(bottom: 12),
                                padding: EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: AppTheme.titleColor.withOpacity(0.05),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: AppTheme.borderColor),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.restaurant_menu,
                                          color: AppTheme.pendingAmber,
                                          size: 16,
                                        ),
                                        SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            item['name'],
                                            style: TextStyle(
                                              color: AppTheme.titleColor,
                                              fontSize: 15,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                        IconButton(
                                          icon: Icon(
                                            Icons.close,
                                            color: AppTheme.borderColor,
                                            size: 18,
                                          ),
                                          onPressed: () => setState(
                                            () => _selectedItems.removeWhere(
                                              (e) => e['id'] == item['id'],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    SizedBox(height: 8),
                                    Row(
                                      children: [
                                        // Toggle
                                        ToggleButtons(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          isSelected: [
                                            (item['quantity_type'] ??
                                                    'fixed') ==
                                                'fixed',
                                            (item['quantity_type'] ??
                                                    'fixed') ==
                                                'persons',
                                          ],
                                          onPressed: (idx) {
                                            setState(() {
                                              item['quantity_type'] = idx == 0
                                                  ? 'fixed'
                                                  : 'persons';
                                            });
                                          },
                                          fillColor: AppTheme.pendingAmber.withOpacity(0.2),
                                          selectedColor: AppTheme.pendingAmber,
                                          color: AppTheme.labelColor,
                                          constraints: BoxConstraints(
                                            minHeight: 32,
                                            minWidth: 60,
                                          ),
                                          children: [
                                            Text(
                                              'Qty',
                                              style: TextStyle(fontSize: 12),
                                            ),
                                            Text(
                                              'Persons',
                                              style: TextStyle(fontSize: 12),
                                            ),
                                          ],
                                        ),
                                        SizedBox(width: 12),
                                        // Text Input for Value
                                        Expanded(
                                          child: SizedBox(
                                            height: 40,
                                            child: TextFormField(
                                              initialValue: item['quantity']
                                                  .toString(),
                                              keyboardType:
                                                  TextInputType.numberWithOptions(
                                                    decimal: true,
                                                  ),
                                              style: TextStyle(
                                                color: AppTheme.titleColor,
                                                fontSize: 14,
                                              ),
                                              decoration: InputDecoration(
                                                hintText: 'Enter amount...',
                                                hintStyle: TextStyle(
                                                  color: AppTheme.borderColor,
                                                  fontSize: 12,
                                                ),
                                                contentPadding:
                                                    EdgeInsets.symmetric(
                                                      horizontal: 12,
                                                      vertical: 0,
                                                    ),
                                                filled: true,
                                                fillColor: AppTheme.titleColor.withOpacity(0.05),
                                                border: OutlineInputBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                  borderSide: BorderSide.none,
                                                ),
                                              ),
                                              onChanged: (val) {
                                                final numVal =
                                                    double.tryParse(val) ?? 0;
                                                setState(
                                                  () =>
                                                      item['quantity'] = numVal,
                                                );
                                              },
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                        SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _showItemSelectorBottomSheet,
                            icon: Icon(
                              Icons.add,
                              color: AppTheme.pendingAmber,
                              size: 16,
                            ),
                            label: Text(
                              'Add More Items',
                              style: TextStyle(color: AppTheme.pendingAmber),
                            ),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(
                                color: AppTheme.pendingAmber,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  SizedBox(height: 24),

                  // Order Type — Direct or Middleman segmented bar
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Order Type',
                        style: TextStyle(
                          color: AppTheme.labelColor,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 10),
                      Container(
                        decoration: BoxDecoration(
                          color: AppTheme.titleColor.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppTheme.borderColor),
                        ),
                        child: Row(
                          children: [
                            // Direct Customer
                            Expanded(
                              child: GestureDetector(
                                onTap: () =>
                                    setState(() => _orderType = 'direct'),
                                child: AnimatedContainer(
                                  duration: Duration(milliseconds: 200),
                                  padding: EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _orderType == 'direct'
                                        ? AppTheme.pendingAmber.withOpacity(0.18)
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.horizontal(
                                      left: Radius.circular(13),
                                    ),
                                    border: _orderType == 'direct'
                                        ? Border.all(
                                            color: AppTheme.pendingAmber,
                                            width: 1.5,
                                          )
                                        : null,
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.person,
                                        color: _orderType == 'direct'
                                            ? AppTheme.pendingAmber
                                            : AppTheme.borderColor,
                                        size: 18,
                                      ),
                                      SizedBox(width: 8),
                                      Flexible(
                                        child: Text(
                                          'Direct Customer',
                                          style: TextStyle(
                                            color: _orderType == 'direct'
                                                ? AppTheme.pendingAmber
                                                : AppTheme.labelColor,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            // Middleman
                            Expanded(
                              child: GestureDetector(
                                onTap: () =>
                                    setState(() => _orderType = 'middleman'),
                                child: AnimatedContainer(
                                  duration: Duration(milliseconds: 200),
                                  padding: EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _orderType == 'middleman'
                                        ? Color(
                                            0xFFD4A237,
                                          ).withOpacity(0.15)
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.horizontal(
                                      right: Radius.circular(13),
                                    ),
                                    border: _orderType == 'middleman'
                                        ? Border.all(
                                            color: Color(0xFFD4A237),
                                            width: 1.5,
                                          )
                                        : null,
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.people,
                                        color: _orderType == 'middleman'
                                            ? Color(0xFFD4A237)
                                            : AppTheme.borderColor,
                                        size: 18,
                                      ),
                                      SizedBox(width: 8),
                                      Flexible(
                                        child: Text(
                                          'Middleman',
                                          style: TextStyle(
                                            color: _orderType == 'middleman'
                                                ? Color(0xFFD4A237)
                                                : AppTheme.labelColor,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 20),

                  // Middleman fields — only shown when Middleman is selected
                  if (_orderType == 'middleman') ...[
                    _middleMen.isEmpty
                        ? Container(
                            padding: EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: AppTheme.pendingAmber.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: AppTheme.pendingAmber.withOpacity(0.3),
                              ),
                            ),
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      Icons.warning_amber_rounded,
                                      color: AppTheme.pendingAmber,
                                      size: 18,
                                    ),
                                    SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        'No middlemen added yet.',
                                        style: TextStyle(
                                          color: AppTheme.pendingAmber,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(height: 12),
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    onPressed: _showAddMiddleManDialog,
                                    icon: Icon(Icons.add, size: 16),
                                    label: Text(
                                      'Add Your First Middleman',
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppTheme.pendingAmber,
                                      foregroundColor: Colors.black,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          )
                        : Row(
                            children: [
                              Expanded(
                                child:
                                    DropdownButtonFormField<
                                      Map<String, dynamic>
                                    >(
                                      dropdownColor: AppTheme.background,
                                      initialValue: _selectedMiddleMan,
                                      hint: Text(
                                        'Select Middleman',
                                        style: TextStyle(color: AppTheme.labelColor),
                                      ),
                                      items: _middleMen.map((man) {
                                        return DropdownMenuItem(
                                          value: man,
                                          child: Text(
                                            '${man['name']} (${man['phone_number']})',
                                            style: TextStyle(
                                              color: AppTheme.titleColor,
                                            ),
                                          ),
                                        );
                                      }).toList(),
                                      onChanged: (val) => setState(
                                        () => _selectedMiddleMan = val,
                                      ),
                                      decoration: InputDecoration(
                                        prefixIcon: Icon(
                                          Icons.person_outline,
                                          color: Color(0xFFD4A237),
                                        ),
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                          borderSide: BorderSide(
                                            color: Color(0xFFD4A237),
                                            width: 1.2,
                                          ),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                          borderSide: BorderSide(
                                            color: Color(0xFFD4A237),
                                            width: 2,
                                          ),
                                        ),
                                      ),
                                      validator: (_) =>
                                          _orderType == 'middleman' &&
                                              _selectedMiddleMan == null
                                          ? 'Please select a middleman'
                                          : null,
                                    ),
                              ),
                              SizedBox(width: 8),
                              SizedBox(
                                height: 56,
                                child: ElevatedButton(
                                  onPressed: _showAddMiddleManDialog,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Color(
                                      0xFFD4A237,
                                    ).withOpacity(0.1),
                                    foregroundColor: Color(0xFFD4A237),
                                    elevation: 0,
                                    side: BorderSide(
                                      color: Color(0xFFD4A237),
                                      width: 1.2,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                  ),
                                  child: Icon(Icons.add),
                                ),
                              ),
                            ],
                          ),
                    if (_selectedMiddleMan != null)
                      Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.amber.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.account_balance_wallet_outlined,
                                color: Colors.amber,
                                size: 16,
                              ),
                              SizedBox(width: 8),
                              Text(
                                'Current Khata: ₹${(_selectedMiddleMan?['total_balance'] as num?)?.toStringAsFixed(0) ?? '0'}',
                                style: TextStyle(
                                  color: Colors.amber,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    SizedBox(height: 8),
                    if (_paymentStatus == 'pending' &&
                        _selectedMiddleMan != null)
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.activeEmerald.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: AppTheme.activeEmerald.withOpacity(0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.auto_awesome,
                              color: AppTheme.activeEmerald,
                              size: 16,
                            ),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Will auto-add to Khata (pending payment)',
                                style: TextStyle(
                                  color: AppTheme.activeEmerald,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                  SizedBox(height: 20),

                  // Total Value
                  TextFormField(
                    controller: _totalController,
                    style: TextStyle(
                      color: AppTheme.titleColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Total Order Value',
                      labelStyle: TextStyle(color: AppTheme.labelColor),
                      prefixText: '₹ ',
                      prefixStyle: TextStyle(
                        color: AppTheme.activeEmerald,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: AppTheme.borderColor),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: AppTheme.activeEmerald),
                      ),
                    ),
                    validator: (v) =>
                        v == null || v.isEmpty ? 'Total is required' : null,
                  ),
                  SizedBox(height: 24),

                  // Payment Status — segmented bar
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Payment Status',
                        style: TextStyle(
                          color: AppTheme.labelColor,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 10),
                      Container(
                        decoration: BoxDecoration(
                          color: AppTheme.titleColor.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppTheme.borderColor),
                        ),
                        child: Row(
                          children: [
                            // PAID option
                            Expanded(
                              child: GestureDetector(
                                onTap: () =>
                                    setState(() => _paymentStatus = 'paid'),
                                child: AnimatedContainer(
                                  duration: Duration(milliseconds: 200),
                                  padding: EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _paymentStatus == 'paid'
                                        ? AppTheme.activeEmerald.withOpacity(0.2)
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.horizontal(
                                      left: Radius.circular(13),
                                    ),
                                    border: _paymentStatus == 'paid'
                                        ? Border.all(
                                            color: AppTheme.activeEmerald,
                                            width: 1.5,
                                          )
                                        : null,
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.check_circle,
                                        color: _paymentStatus == 'paid'
                                            ? AppTheme.activeEmerald
                                            : AppTheme.borderColor,
                                        size: 18,
                                      ),
                                      SizedBox(width: 8),
                                      Text(
                                        'Paid',
                                        style: TextStyle(
                                          color: _paymentStatus == 'paid'
                                              ? AppTheme.activeEmerald
                                              : AppTheme.labelColor,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            // PENDING option
                            Expanded(
                              child: GestureDetector(
                                onTap: () =>
                                    setState(() => _paymentStatus = 'pending'),
                                child: AnimatedContainer(
                                  duration: Duration(milliseconds: 200),
                                  padding: EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _paymentStatus == 'pending'
                                        ? AppTheme.pendingAmber.withOpacity(0.15)
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.horizontal(
                                      right: Radius.circular(13),
                                    ),
                                    border: _paymentStatus == 'pending'
                                        ? Border.all(
                                            color: AppTheme.pendingAmber,
                                            width: 1.5,
                                          )
                                        : null,
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.pending_actions,
                                        color: _paymentStatus == 'pending'
                                            ? AppTheme.pendingAmber
                                            : AppTheme.borderColor,
                                        size: 18,
                                      ),
                                      SizedBox(width: 8),
                                      Text(
                                        'Pending',
                                        style: TextStyle(
                                          color: _paymentStatus == 'pending'
                                              ? AppTheme.pendingAmber
                                              : AppTheme.labelColor,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  SizedBox(height: 40),

                  // Submit Button
                  SizedBox(
                    height: 56,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.pendingAmber,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      onPressed: _isLoading ? null : _submitOrder,
                      child: _isLoading
                          ? CircularProgressIndicator(color: Colors.black)
                          : Text(
                              widget.orderToEdit != null ? 'Save Changes' : 'Create Order',
                              style: TextStyle(
                                color: Colors.black,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),
                  SizedBox(height: 40),
                ],
              ),
            ),
    );
  }
}
