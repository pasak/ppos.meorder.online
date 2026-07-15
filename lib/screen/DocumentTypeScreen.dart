import 'package:flutter/material.dart';
import 'package:meorder_ppos/lib/EnvConfig.dart';
import 'package:meorder_ppos/screen/PPosScreen.dart';
import 'package:meorder_ppos/screen/AdminScreen.dart';
import 'package:meorder_ppos/screen/MerchandiseCategoryScreen.dart';
import 'package:meorder_ppos/screen/MerchandiseStockScreen.dart';
import 'package:meorder_ppos/screen/SupplierScreen.dart';
import 'package:meorder_ppos/screen/SettingValueScreen.dart';

class DocumentTypeScreen extends StatefulWidget {
  final EnvConfig config;
  const DocumentTypeScreen({super.key, required this.config});

  @override
  State<DocumentTypeScreen> createState() => _DocumentTypeScreenState();
}

class _DocumentTypeScreenState extends State<DocumentTypeScreen> {
  bool get isThai => widget.config.language == 'th';

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
                isThai ? 'เอกสาร' : 'Document',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.home, color: Colors.black),
              onPressed: () {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (context) => PPosScreen(config: widget.config)),
                  (Route<dynamic> route) => false,
                );
              },
            ),
            PopupMenuButton<int>(
              icon: const Icon(Icons.menu, color: Colors.black),
              onSelected: (value) {
                if (value == 1) {
                  Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => AdminScreen(config: widget.config)));
                } else if (value == 2) {
                  Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => MerchandiseCategoryScreen(config: widget.config)));
                } else if (value == 3) {
                  Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => MerchandiseStockScreen(config: widget.config)));
                } else if (value == 4) {
                  Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => SupplierScreen(config: widget.config)));
                } else if (value == 5) {
                  Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => SettingValueScreen(config: widget.config)));
                } else if (value == 6) {
                  // Already here
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(value: 1, child: Text(isThai ? 'ข้อมูลสาขา' : 'Branch Info')),
                PopupMenuItem(value: 2, child: Text(isThai ? 'สินค้า' : 'Merchandise')),
                PopupMenuItem(value: 3, child: Text(isThai ? 'สต็อก' : 'Stock')),
                PopupMenuItem(value: 4, child: Text(isThai ? 'ผู้จำหน่าย' : 'Supplier')),
                PopupMenuItem(value: 5, child: Text(isThai ? 'ตั้งค่า' : 'Setting')),
                PopupMenuItem(value: 6, child: Text(isThai ? 'เอกสาร' : 'Document')),
              ],
            ),
          ],
        ),
      ),
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
            child: Center(child: Text(isThai ? 'เอกสาร' : 'Document')),
          ),
        ],
      ),
    );
  }
}
