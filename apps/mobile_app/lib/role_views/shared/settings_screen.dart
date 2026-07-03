import 'package:mobile_app/core/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/notification_service.dart';
import '../../services/theme_service.dart';

class SettingsScreen extends StatefulWidget {
  final String? companyId;
  final String? companyName;
  final String role; // 'owner' or 'staff'
  final String? fullName;

  SettingsScreen({
    super.key,
    this.companyId,
    this.companyName,
    required this.role,
    this.fullName,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final supabase = Supabase.instance.client;
  bool _isLoading = false;
  bool _showId = false;

  Future<void> _copyCompanyId() async {
    if (widget.companyId != null) {
      try {
        await Clipboard.setData(ClipboardData(text: widget.companyId!));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Company ID copied to clipboard!'),
              backgroundColor: AppTheme.pendingAmber,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Browser blocked auto-copy. Please long-press the ID to copy!',
              ),
              backgroundColor: AppTheme.errorRed,
              duration: Duration(seconds: 4),
            ),
          );
        }
      }
    }
  }

  Future<void> _logout() async {
    setState(() => _isLoading = true);
    final user = supabase.auth.currentUser;
    if (user != null) {
      try {
        await supabase
            .from('profiles')
            .update({'is_online': false})
            .eq('id', user.id);
      } catch (_) {}
    }
    await supabase.auth.signOut();
    if (mounted) Navigator.pushReplacementNamed(context, '/login');
  }

  Future<void> _leaveCompany() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.background,
        title: Text('Leave Company', style: TextStyle(color: AppTheme.titleColor)),
        content: Text(
          'Are you sure you want to leave this company? You will need a new invite code to join again.',
          style: TextStyle(color: AppTheme.labelColor),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: TextStyle(color: AppTheme.labelColor)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.errorRed),
            child: Text('Leave', style: TextStyle(color: AppTheme.titleColor)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);

    try {
      final user = supabase.auth.currentUser;
      if (user == null || widget.companyId == null) return;

      // 1. Get Owner ID before leaving
      final companyRes = await supabase
          .from('companies')
          .select('owner_id')
          .eq('id', widget.companyId!)
          .maybeSingle();
      
      final ownerId = companyRes?['owner_id'];

      // 2. Update Profile
      await supabase
          .from('profiles')
          .update({'company_id': null})
          .eq('id', user.id);

      // 3. Send Notification (Unified method handles DB logging and Push)
      if (ownerId != null) {
        await NotificationService.sendNotification(
          playerIds: [ownerId],
          title: 'Staff Member Left 👤',
          message: '${widget.fullName ?? 'A staff member'} has left your team.',
          data: {'type': 'staff_left'},
          color: 'FFFF5722',
          companyId: widget.companyId,
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Left company successfully'), backgroundColor: AppTheme.activeEmerald),
        );
        Navigator.pushReplacementNamed(context, '/dashboard');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.errorRed),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('Settings', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: _isLoading 
        ? Center(child: CircularProgressIndicator(color: AppTheme.pendingAmber))
        : SingleChildScrollView(
            padding: EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Profile Section
                Container(
                  padding: EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppTheme.titleColor.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppTheme.borderColor),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 30,
                        backgroundColor: AppTheme.pendingAmber.withOpacity(0.2),
                        child: Text(
                          (widget.fullName ?? 'U')[0].toUpperCase(),
                          style: TextStyle(color: AppTheme.pendingAmber, fontSize: 24, fontWeight: FontWeight.bold),
                        ),
                      ),
                      SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.fullName ?? 'User',
                              style: TextStyle(color: AppTheme.titleColor, fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                            Text(
                              widget.role.toUpperCase(),
                              style: TextStyle(color: AppTheme.titleColor.withOpacity(0.5), fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 32),
                
                // Company ID Card (Only for owner)
                if (widget.role == 'owner' && widget.companyId != null) ...[
                  Container(
                    padding: EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: AppTheme.titleColor.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: AppTheme.borderColor),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.business,
                              color: AppTheme.pendingAmber,
                              size: 20,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'MY COMPANY ID',
                              style: TextStyle(
                                color: AppTheme.titleColor.withOpacity(0.5),
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 16),
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 16,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: SelectableText(
                                  !_showId && widget.companyId != null
                                      ? '•' * 12
                                      : (widget.companyId ?? 'Generating...'),
                                  style: TextStyle(
                                    color: AppTheme.labelColor,
                                    fontFamily: 'monospace',
                                    fontSize: 14,
                                    letterSpacing: 2,
                                  ),
                                  maxLines: 1,
                                ),
                              ),
                              SizedBox(width: 10),
                              IconButton(
                                icon: Icon(
                                  _showId
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                  color: AppTheme.labelColor,
                                  size: 20,
                                ),
                                onPressed: () => setState(() => _showId = !_showId),
                                padding: EdgeInsets.zero,
                                constraints: BoxConstraints(),
                              ),
                              SizedBox(width: 15),
                              InkWell(
                                onTap: _copyCompanyId,
                                child: Container(
                                  padding: EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: AppTheme.pendingAmber.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(
                                    Icons.copy_rounded,
                                    color: AppTheme.pendingAmber,
                                    size: 20,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: 12),
                        Text(
                          'Share this ID with your staff so they can join your workspace.',
                          style: TextStyle(
                            color: AppTheme.titleColor.withOpacity(0.4),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 32),
                ],
                
                // Appearance
                Text(
                  'Appearance',
                  style: TextStyle(color: AppTheme.labelColor, fontSize: 14, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 16),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryAction.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.primaryAction.withOpacity(0.1)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'App Theme',
                              style: TextStyle(color: AppTheme.titleColor, fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                            Text(
                              'Select your preferred visual style',
                              style: TextStyle(color: AppTheme.titleColor.withOpacity(0.5), fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                      Theme(
                        data: Theme.of(context).copyWith(
                          splashColor: AppTheme.primaryAction.withOpacity(0.1),
                          highlightColor: AppTheme.primaryAction.withOpacity(0.1),
                        ),
                        child: PopupMenuButton<bool>(
                          initialValue: ThemeService.isLegacy,
                          onSelected: (val) {
                            ThemeService.toggleTheme(val);
                            setState(() {});
                          },
                          color: AppTheme.cardColor,
                          elevation: 8,
                          shadowColor: AppTheme.titleColor.withOpacity(0.2),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                            side: BorderSide(color: AppTheme.borderColor),
                          ),
                          offset: Offset(0, 50),
                          child: Container(
                            padding: EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppTheme.cardColor,
                              shape: BoxShape.circle,
                              border: Border.all(color: AppTheme.borderColor),
                              boxShadow: [
                                BoxShadow(
                                  color: AppTheme.titleColor.withOpacity(0.05),
                                  blurRadius: 8,
                                  offset: Offset(0, 2),
                                )
                              ]
                            ),
                            child: Icon(
                              Icons.palette_outlined,
                              color: AppTheme.primaryAction,
                              size: 22,
                            ),
                          ),
                          itemBuilder: (context) => [
                            PopupMenuItem(
                              value: false,
                              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              child: Row(
                                children: [
                                  Container(
                                    padding: EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: !ThemeService.isLegacy ? AppTheme.primaryAction.withOpacity(0.1) : Colors.transparent,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.auto_awesome, 
                                      color: !ThemeService.isLegacy ? AppTheme.primaryAction : AppTheme.labelColor, 
                                      size: 20
                                    ),
                                  ),
                                  SizedBox(width: 12),
                                  Text(
                                    'Modern', 
                                    style: TextStyle(
                                      color: !ThemeService.isLegacy ? AppTheme.primaryAction : AppTheme.titleColor, 
                                      fontWeight: FontWeight.bold
                                    )
                                  ),
                                ],
                              ),
                            ),
                            PopupMenuItem(
                              value: true,
                              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              child: Row(
                                children: [
                                  Container(
                                    padding: EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: ThemeService.isLegacy ? AppTheme.primaryAction.withOpacity(0.1) : Colors.transparent,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.token_outlined, 
                                      color: ThemeService.isLegacy ? AppTheme.primaryAction : AppTheme.labelColor, 
                                      size: 20
                                    ),
                                  ),
                                  SizedBox(width: 12),
                                  Text(
                                    'Legacy', 
                                    style: TextStyle(
                                      color: ThemeService.isLegacy ? AppTheme.primaryAction : AppTheme.titleColor, 
                                      fontWeight: FontWeight.bold
                                    )
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 32),
                
                // Account Actions
                Text(
                  'Account Actions',
                  style: TextStyle(color: AppTheme.labelColor, fontSize: 14, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 16),

                // Leave Company (Only for Staff who are in a company)
                if (widget.role == 'staff' && widget.companyId != null)
                  _buildSettingTile(
                    icon: Icons.exit_to_app,
                    title: 'Leave Company',
                    subtitle: 'Disconnect from your current team',
                    color: AppTheme.errorRed,
                    onTap: _leaveCompany,
                  ),

                SizedBox(height: 12),

                // Logout
                _buildSettingTile(
                  icon: Icons.logout,
                  title: 'Logout',
                  subtitle: 'Sign out of your account',
                  color: AppTheme.pendingAmber,
                  onTap: _logout,
                ),

                SizedBox(height: 32),
                Divider(color: AppTheme.borderColor),
                SizedBox(height: 24),
                
                // Troubleshooting
                Text(
                  'Troubleshooting',
                  style: TextStyle(color: AppTheme.labelColor, fontSize: 14, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 16),
                _buildSettingTile(
                  icon: Icons.notifications_active_outlined,
                  title: 'Test Notification',
                  subtitle: 'Check if push notifications reach this device',
                  color: AppTheme.primaryAction,
                  onTap: () async {
                    final user = Supabase.instance.client.auth.currentUser;
                    if (user == null) return;
                    
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Triggering test...'), duration: Duration(seconds: 1)),
                    );
                    
                    final result = await NotificationService.sendToSelf(user.id);
                    if (result == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('✅ Test triggered successfully!'), backgroundColor: AppTheme.activeEmerald),
                      );
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('❌ Error: $result'), backgroundColor: AppTheme.errorRed),
                      );
                    }
                  },
                ),

                SizedBox(height: 16),
                _buildSettingTile(
                  icon: Icons.code_rounded,
                  title: 'Meet Our Developers',
                  subtitle: 'The minds behind Catering Ops',
                  color: Colors.purpleAccent,
                  onTap: () => Navigator.pushNamed(context, '/meet-developers'),
                ),

                SizedBox(height: 40),
                Center(
                  child: Text(
                    'Catering Ops v1.0.0',
                    style: TextStyle(color: AppTheme.titleColor.withOpacity(0.3), fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
    );
  }

  Widget _buildSettingTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.1)),
        ),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(color: AppTheme.titleColor, fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(color: AppTheme.titleColor.withOpacity(0.5), fontSize: 13),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios_rounded, color: AppTheme.borderColor, size: 16),
          ],
        ),
      ),
    );
  }
}
