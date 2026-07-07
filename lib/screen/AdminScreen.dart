import 'package:flutter/material.dart';
import 'package:meorder_ppos/lib/EnvConfig.dart';
import 'package:meorder_ppos/screen/SignInScreen.dart';
import 'package:meorder_ppos/services/SyncService.dart';
import 'dart:io';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:meorder_ppos/services/GeneralServices.dart';
import 'package:meorder_ppos/screen/PurchaseScreen.dart';

class AdminScreen extends StatefulWidget {
  final EnvConfig config;
  const AdminScreen({super.key, required this.config});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  late EnvConfig _config;
  String _activeSection = 'User'; // 'User' or 'Branch'
  bool _isKitchen = false;

  bool get isThai => _config.language == 'th';

  @override
  void initState() {
    super.initState();
    _config = widget.config;
    _isKitchen = _config.isKitchen ?? false;
    _loadPermissions();
  }

  Map<String, String?>? foPurchaseOrder;

  Future<void> _loadPermissions() async {
    final roleID = _config.UserRole;
    if (roleID != null) {
      final perm = await GeneralServices.getRoleTransactionPermissionList(roleID, 'FO_PURCHASE_ORDER');
      if (mounted) {
        setState(() {
          foPurchaseOrder = perm;
        });
      }
    }
  }

  Future<void> _updateConfig(EnvConfig newConfig) async {
    setState(() {
      _config = newConfig;
    });

    try {
      final directory = await getApplicationDocumentsDirectory();
      final filePath = '${directory.path}/branch.json';
      final file = File(filePath);

      if (await file.exists()) {
        final content = await file.readAsString();
        final branchData = jsonDecode(content);
        
        branchData['UserID'] = newConfig.UserID;
        branchData['UserRole'] = newConfig.UserRole;
        branchData['isKitchen'] = newConfig.isKitchen;
        
        await file.writeAsString(jsonEncode(branchData));
      }
    } catch (e) {
      debugPrint("Error updating config: $e");
    }
  }

  void _signOut() async {
    await _updateConfig(_config.copyWith(UserID: '', UserRole: ''));
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (context) => SignInScreen(config: _config),
      ),
      (Route<dynamic> route) => false,
    );
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return '-';
    try {
      DateTime dt = DateTime.parse(dateStr);
      int year = isThai ? dt.year + 543 : dt.year;
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/$year';
    } catch (_) {
      return dateStr;
    }
  }

  Widget _buildTopHeader() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.black),
              onPressed: () => Navigator.pop(context),
            ),
            Expanded(
              child: Text(
                isThai ? 'แอดมิน' : 'Admin',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
            ),
            IconButton(
              icon: Icon(Icons.person, color: _activeSection == 'User' ? Colors.blue : Colors.black),
              onPressed: () { setState(() { _activeSection = 'User'; }); },
            ),
            IconButton(
              icon: Icon(Icons.info, color: _activeSection == 'Branch' ? Colors.blue : Colors.black),
              onPressed: () { setState(() { _activeSection = 'Branch'; }); },
            ),
            if (foPurchaseOrder != null && foPurchaseOrder!['PermissionLevel'] != 'No')
              IconButton(
                icon: const Icon(Icons.shopping_cart, color: Colors.black),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => PurchaseScreen(config: _config),
                    ),
                  );
                },
              ),
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.black),
              onPressed: () async {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(isThai ? 'กำลังซิงค์...' : 'Syncing...')),
                );
                bool success = await SyncService.syncMaster(_config);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(success ? (isThai ? 'ซิงค์สำเร็จ' : 'Sync Success') : (isThai ? 'ซิงค์ล้มเหลว' : 'Sync Failed'))),
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUserSection() {
    return Column(
      children: [
        ListTile(
          title: Text(isThai ? 'รหัสผู้ใช้' : 'User ID'),
          subtitle: Text(_config.UserID ?? '-'),
        ),
        const Divider(),
        ListTile(
          title: Text(isThai ? 'บทบาท' : 'User Role'),
          subtitle: Text(_config.UserRole ?? '-'),
        ),
        const Divider(),
        const SizedBox(height: 20),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
          ),
          onPressed: _signOut,
          child: Text(isThai ? 'ออกจากระบบ' : 'Sign Out', style: const TextStyle(fontSize: 16)),
        ),
      ],
    );
  }

  Widget _buildBranchInfoSection() {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        _buildInfoRow(isThai ? 'ชื่อร้าน' : 'ShopName', _config.ShopName),
        _buildInfoRow(isThai ? 'เลขประจำตัวผู้เสียภาษี' : 'TaxID', _config.TaxID),
        _buildInfoRow(isThai ? 'สาขา' : 'BranchName', _config.BranchName),
        _buildInfoRow(isThai ? 'ที่อยู่' : 'Address', _config.Address),
        _buildInfoRow(isThai ? 'โทรศัพท์' : 'Telephone', _config.Telephone),
        _buildInfoRow(isThai ? 'รุ่นเครื่องพิมพ์' : 'PrinterModel', _config.PrinterModel),
        _buildInfoRow(isThai ? 'ประเภทการเชื่อมต่อ' : 'ConnectType', _config.ConnectType),
        _buildInfoRow(isThai ? 'ที่อยู่เครื่องพิมพ์' : 'PrinterAddress', _config.PrinterAddress),
        _buildInfoRow(isThai ? 'วันหมดอายุ' : 'ExpireDate', _formatDate(_config.ExpireDate)),
        _buildInfoRow(isThai ? 'อัพเดทล่าสุด' : 'LastUpdated', _formatDate(_config.LastUpdated)),
        _buildInfoRow(isThai ? 'รหัสจุดขาย' : 'PosID', _config.PosID),
        const Divider(),
        SwitchListTile(
          title: Text(isThai ? 'พิมพ์ใบสั่งอาหาร' : 'Print Kitchen Order'),
          value: _isKitchen,
          onChanged: (val) async {
            setState(() { _isKitchen = val; });
            await _updateConfig(_config.copyWith(isKitchen: val));
          },
        ),
      ],
    );
  }

  Widget _buildInfoRow(String label, String? value) {
    return Column(
      children: [
        ListTile(
          title: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text(value ?? '-'),
        ),
        const Divider(height: 1),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: Column(
        children: [
          _buildTopHeader(),
          Expanded(
            child: _activeSection == 'User' 
                ? _buildUserSection() 
                : _buildBranchInfoSection(),
          ),
        ],
      ),
    );
  }
}
