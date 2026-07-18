import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:meorder_ppos/lib/EnvConfig.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:isar/isar.dart';
import 'package:uuid/uuid.dart';
import 'package:meorder_ppos/database/IsarModels.dart';
import 'package:meorder_ppos/services/GeneralServices.dart';
import 'package:meorder_ppos/services/SyncService.dart';

class MerchandiseItemScreen extends StatefulWidget {
  final EnvConfig config;
  final Map<String, dynamic> category;

  const MerchandiseItemScreen({super.key, required this.config, required this.category});

  @override
  State<MerchandiseItemScreen> createState() => _MerchandiseItemScreenState();
}

class _MerchandiseItemScreenState extends State<MerchandiseItemScreen> {
  bool get isThai => widget.config.language == 'th';
  List<RoleMasterPermission> _adminMenuList = [];
  bool _isLoading = false;
  List<Map<String, dynamic>> _merchandiseItems = [];
  List<String> _unitNameList = [];
  String _parentName = '';
  String _error = '';

  @override
  void initState() {
    super.initState();
    _loadPermissions();
    _fetchMerchandiseItems();
  }

  Future<void> _loadPermissions() async {
    final roleID = widget.config.UserRole;
    if (roleID != null) {
      final menu = await GeneralServices.getAdminMenuList(roleID, widget.config);
      if (mounted) {
        setState(() {
          _adminMenuList = menu;
        });
      }
    }
  }

  Future<void> _fetchMerchandiseItems() async {
    setState(() {
      _isLoading = true;
      _error = '';
    });

    try {
      final isar = Isar.getInstance()!;
      final items = await isar.merchandiseItemList
          .filter()
          .merchandise_category_IDEqualTo(widget.category['ID'])
          .isActiveEqualTo('Y')
          .findAll();

      final List<Map<String, dynamic>> itemsMap = items.map((e) => {
        'ID': e.id,
        'Barcode': e.barcode,
        'ProductName': e.productName,
        'Price': e.price,
        'UnitName': e.unitName,
        'Tax': e.tax,
        'localPicture': e.localPicture,
      }).toList();

      final Set<String> units = {};
      for (var item in itemsMap) {
        if (item['UnitName'] != null && item['UnitName'].toString().trim().isNotEmpty) {
          units.add(item['UnitName'].toString().trim());
        }
      }

      setState(() {
        _merchandiseItems = itemsMap;
        _parentName = widget.category['CategoryName'] ?? (isThai ? 'สินค้า' : 'Merchandise');
        _unitNameList = ['ขวด', 'ซอง', 'กล่อง', 'กระป๋อง', 'ชิ้น'];
      });
    } catch (e) {
      setState(() {
        _error = 'Error loading data: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _saveMerchandiseItem(Map<String, dynamic> payload) async {
    setState(() {
      _isLoading = true;
      _error = '';
    });

    try {
      final isar = Isar.getInstance()!;
      await isar.writeTxn(() async {
        MerchandiseItem? item;
        final id = payload['ID'];
        if (id != null && id.toString().isNotEmpty) {
          item = await isar.merchandiseItemList.filter().idEqualTo(id).findFirst();
        }
        
        item ??= MerchandiseItem()
          ..id = const Uuid().v4()
          ..isActive = 'Y';
        
        item.barcode = payload['Barcode'];
        item.merchandise_category_ID = payload['merchandise_category_ID'];
        item.productName = payload['ProductName'];
        item.price = double.tryParse(payload['Price'].toString()) ?? 0;
        item.unitName = payload['UnitName'];
        item.tax = payload['Tax'];
        item.localPicture = payload['localPicture'];
        item.isDirty = true;
        item.lastUpdated = DateTime.now().toIso8601String();
        
        debugPrint('_saveMerchandiseItem before save item.id = ${item.id}, item.localPicture = ${item.localPicture}');
        
        await isar.merchandiseItemList.put(item);
        
        final savedId = item.id;
        item = await isar.merchandiseItemList.filter().idEqualTo(savedId).findFirst();

        debugPrint('_saveMerchandiseItem after save item.id = ${item?.id}, item.localPicture = ${item?.localPicture}');
      });

      await SyncService.syncMaster(widget.config);

      await _fetchMerchandiseItems();
    } catch (e) {
      setState(() { _error = 'Error saving data: $e'; });
    } finally {
      if (mounted) setState(() { _isLoading = false; });
    }
  }

  Future<void> _deleteMerchandiseItem(var id) async {
    setState(() {
      _isLoading = true;
      _error = '';
    });

    try {
      final isar = Isar.getInstance()!;
      await isar.writeTxn(() async {
        final item = await isar.merchandiseItemList.filter().idEqualTo(id).findFirst();
        if (item != null) {
          item.isActive = 'N';
          item.isDirty = true;
          item.lastUpdated = DateTime.now().toIso8601String();
          await isar.merchandiseItemList.put(item);
        }
      });

      await SyncService.syncMaster(widget.config);

      await _fetchMerchandiseItems();
    } catch (e) {
      setState(() { _error = 'Error deleting data: $e'; });
    } finally {
      if (mounted) setState(() { _isLoading = false; });
    }
  }

  void _confirmDelete(Map<String, dynamic> item) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(isThai ? 'ยืนยันการลบ' : 'Confirm Delete'),
          content: Text(isThai 
            ? 'คุณต้องการลบสินค้า "${item['ProductName'] ?? item['ID']}" ใช่หรือไม่?' 
            : 'Are you sure you want to delete "${item['ProductName'] ?? item['ID']}"?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(isThai ? 'ยกเลิก' : 'Cancel', style: const TextStyle(color: Colors.grey)),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _deleteMerchandiseItem(item['ID']);
              },
              child: Text(isThai ? 'ลบ' : 'Delete', style: const TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );
  }

  void _openScanner({required Function(String) onScan}) {
    final MobileScannerController scannerController = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return SizedBox(
          height: MediaQuery.of(context).size.height * 0.7,
          child: Column(
            children: [
              AppBar(
                title: Text(isThai ? 'สแกนบาร์โค้ด' : 'Scan Barcode'),
                leading: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
              Expanded(
                child: MobileScanner(
                  controller: scannerController,
                  onDetect: (capture) {
                    final List<Barcode> barcodes = capture.barcodes;
                    if (barcodes.isNotEmpty) {
                      final String code = barcodes.first.rawValue ?? "";
                      if (code.isNotEmpty) {
                        onScan(code);
                        Navigator.pop(context); // Close scanner
                      }
                    }
                  },
                ),
              ),
            ],
          ),
        );
      },
    ).then((_) {
      scannerController.dispose();
    });
  }

  void _showEditDialog({Map<String, dynamic>? item}) {
    final bool isAdd = item == null;
    
    final TextEditingController barcodeController = TextEditingController(text: item?['Barcode']?.toString() ?? '');
    final TextEditingController nameController = TextEditingController(text: item?['ProductName']?.toString() ?? '');
    final TextEditingController priceController = TextEditingController(text: item?['Price']?.toString() ?? '');
    final TextEditingController unitController = TextEditingController(text: item?['UnitName']?.toString() ?? '');
    String? localPicture = item?['localPicture']?.toString();
    
    bool isTax = item?['Tax'] != 'N'; // default checked = V

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {

            return AlertDialog(
              title: Text(isAdd 
                ? (isThai ? 'เพิ่มสินค้า' : 'Add Item') 
                : (isThai ? 'แก้ไขสินค้า' : 'Edit Item')),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [

                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: barcodeController,
                            decoration: const InputDecoration(
                              labelText: 'Barcode',
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.qr_code_scanner),
                          color: Colors.blue,
                          onPressed: () {
                            _openScanner(onScan: (code) {
                              setStateDialog(() {
                                barcodeController.text = code;
                              });
                            });
                          },
                        ),
                      ],
                    ),
                    TextField(
                      controller: nameController,
                      decoration: InputDecoration(
                        labelText: isThai ? 'ชื่อสินค้า' : 'Item Name',
                      ),
                    ),
                    TextField(
                      controller: priceController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: isThai ? 'ราคา' : 'Price',
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: unitController,
                            decoration: InputDecoration(
                              labelText: isThai ? 'หน่วยนับ' : 'Unit',
                            ),
                          ),
                        ),
                        if (_unitNameList.isNotEmpty)
                          PopupMenuButton<String>(
                            icon: const Icon(Icons.arrow_drop_down),
                            onSelected: (String value) {
                              setStateDialog(() {
                                unitController.text = value;
                              });
                            },
                            itemBuilder: (BuildContext context) {
                              return _unitNameList.map((String unit) {
                                return PopupMenuItem<String>(
                                  value: unit,
                                  child: Text(unit),
                                );
                              }).toList();
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Text(isThai ? 'รูปภาพ' : 'Picture'),
                        ),
                        if (localPicture != null && localPicture!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8.0),
                            child: Image.file(
                              File(localPicture!),
                              height: 100,
                            ),
                          ),
                        ElevatedButton(
                          onPressed: () async {
                            final ImagePicker picker = ImagePicker();
                            final XFile? image = await picker.pickImage(source: ImageSource.camera);
                            if (image != null) {
                              setStateDialog(() {
                                localPicture = image.path;
                              });
                            }
                          },
                          child: Text(isThai ? 'ถ่ายรูป' : 'Take Photo'),
                        ),
                      ],
                    ),
                    CheckboxListTile(
                      title: Text(isThai ? 'ภาษี' : 'Tax'),
                      value: isTax,
                      onChanged: (bool? value) {
                        setStateDialog(() {
                          isTax = value ?? true;
                        });
                      },
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(isThai ? 'ยกเลิก' : 'Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final taxValue = isTax ? 'V' : 'N';
                    final payload = {
                      'ID': item?['ID'],
                      'Barcode': barcodeController.text,
                      'merchandise_category_ID': widget.category['ID'],
                      'ProductName': nameController.text,
                      'Price': num.tryParse(priceController.text) ?? 0,
                      'UnitName': unitController.text,
                      'Tax': taxValue,
                      'localPicture': localPicture,
                    };
                    _saveMerchandiseItem(payload);
                    Navigator.pop(context);
                  },
                  child: Text(isThai ? 'บันทึก' : 'Save'),
                ),
              ],
            );
          }
        );
      },
    );
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
                _parentName.isNotEmpty ? _parentName : (isThai ? 'สินค้า' : 'Merchandise Items'),
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
            ),
            GeneralServices.getAdminPopupMenuButton(context, widget.config, _adminMenuList, isThai),
            IconButton(
              icon: const Icon(Icons.add, color: Colors.black),
              onPressed: () => _showEditDialog(),
              tooltip: isThai ? 'เพิ่มสินค้า' : 'Add Item',
            ),
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.black),
              onPressed: _fetchMerchandiseItems,
              tooltip: isThai ? 'รีเฟรช' : 'Refresh',
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
            child: _isLoading && _merchandiseItems.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : Column(
                    children: [
                      if (_error.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Text(_error, style: const TextStyle(color: Colors.red)),
                        ),
                      Expanded(
                        child: RefreshIndicator(
                          onRefresh: _fetchMerchandiseItems,
                          child: _merchandiseItems.isEmpty
                              ? ListView(
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.all(32.0),
                                      child: Center(child: Text(isThai ? 'ไม่มีข้อมูลสินค้า' : 'No Merchandise Items')),
                                    )
                                  ],
                                )
                              : ListView.builder(
                                  itemCount: _merchandiseItems.length,
                                  itemBuilder: (context, index) {
                                    final item = _merchandiseItems[index];
                                    
                                    return Card(
                                      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      child: Column(
                                        children: [
                                          Padding(
                                            padding: const EdgeInsets.all(12.0),
                                            child: Row(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Text(item['ProductName'] ?? '-', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                                      const SizedBox(height: 4),
                                                      Text('Barcode: ${item['Barcode']}'),
                                                    ],
                                                  ),
                                                ),
                                                Column(
                                                  crossAxisAlignment: CrossAxisAlignment.end,
                                                  children: [
                                                    Text('${item['Price']} : ${item['UnitName']}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.end,
                                            children: [
                                              IconButton(
                                                icon: const Icon(Icons.edit, color: Colors.blue),
                                                onPressed: () => _showEditDialog(item: item),
                                              ),
                                              IconButton(
                                                icon: const Icon(Icons.delete, color: Colors.red),
                                                onPressed: () => _confirmDelete(item),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
