import 'package:mobile_app/core/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class JoinRequestsScreen extends StatefulWidget {
  const JoinRequestsScreen({super.key});

  @override
  State<JoinRequestsScreen> createState() => _JoinRequestsScreenState();
}

class _JoinRequestsScreenState extends State<JoinRequestsScreen> {
  final supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _requests = [];
  bool _loading = true;
  String? _companyId;

  @override
  void initState() {
    super.initState();
    _fetchRequests();
  }

  Future<void> _fetchRequests() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    try {
      // 1. Get owner's company_id
      final profileRes = await supabase
          .from('profiles')
          .select('company_id')
          .eq('id', user.id)
          .maybeSingle();

      _companyId = profileRes?['company_id'];
      if (_companyId == null) {
        if (mounted) setState(() => _loading = false);
        return;
      }

      // 2. Fetch pending requests with staff profile info
      final res = await supabase
          .from('company_join_requests')
          .select('*, profiles(*)')
          .eq('company_id', _companyId!)
          .eq('status', 'pending')
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          _requests = List<Map<String, dynamic>>.from(res);
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching requests: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _handleRequest(String requestId, String status) async {
    try {
      await supabase
          .from('company_join_requests')
          .update({'status': status})
          .eq('id', requestId);

      _toast(status == 'accepted' ? 'Staff accepted!' : 'Request rejected.');
      _fetchRequests();
    } catch (e) {
      _toast('Error: ${e.toString()}');
    }
  }

  void _toast(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: AppTheme.pendingAmber),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Text(
          'Join Requests',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.pendingAmber),
            )
          : _requests.isEmpty
          ? _buildEmptyState()
          : ListView.builder(
              padding: const EdgeInsets.all(24),
              itemCount: _requests.length,
              itemBuilder: (context, index) {
                final req = _requests[index];
                final profilesRaw = req['profiles'];
                Map<String, dynamic> profile;

                if (profilesRaw is List && profilesRaw.isNotEmpty) {
                  profile = profilesRaw.first as Map<String, dynamic>;
                } else if (profilesRaw is Map) {
                  profile = Map<String, dynamic>.from(profilesRaw);
                } else {
                  profile = {
                    'full_name': 'Unknown',
                    'phone': 'N/A',
                    'email': 'N/A',
                  };
                }

                return _buildRequestCard(req['id'], profile);
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
            Icons.person_add_disabled_outlined,
            size: 64,
            color: AppTheme.titleColor.withOpacity(0.1),
          ),
          const SizedBox(height: 16),
          Text(
            'No pending requests',
            style: TextStyle(
              color: AppTheme.titleColor.withOpacity(0.3),
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRequestCard(String requestId, Map<String, dynamic> profile) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
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
              CircleAvatar(
                backgroundColor: AppTheme.pendingAmber.withOpacity(0.1),
                child: Text(
                  (profile['full_name'] as String?)?[0].toUpperCase() ?? 'S',
                  style: const TextStyle(
                    color: AppTheme.pendingAmber,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile['full_name'] ?? 'Unknown',
                      style: const TextStyle(
                        color: AppTheme.titleColor,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Staff Member',
                      style: TextStyle(
                        color: AppTheme.titleColor.withOpacity(0.5),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _buildInfoRow(Icons.phone_outlined, profile['phone'] ?? 'No phone'),
          const SizedBox(height: 8),
          _buildInfoRow(Icons.email_outlined, profile['email'] ?? 'No email'),
          const SizedBox(height: 32),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _handleRequest(requestId, 'rejected'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.errorRed,
                    side: const BorderSide(color: AppTheme.errorRed),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text(
                    'REJECT',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => _handleRequest(requestId, 'accepted'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.activeEmerald,
                    foregroundColor: AppTheme.background,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text(
                    'ACCEPT',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.white30),
        const SizedBox(width: 12),
        Text(text, style: const TextStyle(color: AppTheme.labelColor, fontSize: 14)),
      ],
    );
  }
}
