import 'package:flutter/material.dart';
import 'package:isar/isar.dart';
import 'package:meorder_ppos/lib/EnvConfig.dart';
import 'package:meorder_ppos/database/IsarModels.dart';
import 'package:meorder_ppos/services/GeneralServices.dart';
import 'package:meorder_ppos/services/InventoryServices.dart';
import 'package:meorder_ppos/services/SyncService.dart';
import 'package:meorder_ppos/screen/PPosScreen.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:uuid/uuid.dart';

class PurchaseScreen extends StatefulWidget {
  final EnvConfig config;
  const PurchaseScreen({super.key, required this.config});

  @override
  State<PurchaseScreen> createState() => _PurchaseScreenState();
}

class _PurchaseScreenState extends State<PurchaseScreen> {
  late EnvConfig _config;
  bool get isThai => _config.language == 'th';
  Isar isar = Isar.getInstance()!;

  bool poCreate = false;
  bool poIssue = false;
  bool poReceive = false;
  bool poFull = false;

  String _currentSection = 'List'; // 'List', 'Add', 'Detail'
  List<Map<String, dynamic>> _categoriesNode = [];

  DateTime _fromDate = DateTime.now().subtract(const Duration(days: 7));
  DateTime _toDate = DateTime.now();

  final Map<String, bool> _status = {
    'Created': true,
    'Issued': true,
    'Received': false,
    'Cancelled': false,
  };

  Map<String, String> get statusText => {
    'Created': isThai ? 'สร้าง' : 'Create',
    'Issued': isThai ? 'สั่งซื้อ' : 'Issue',
    'Received': isThai ? 'รับ' : 'Receive',
    'Cancelled': isThai ? 'ยกเลิก' : 'Cancel',
  };

  List<PurchaseOrder> _poList = [];

  // AddSection states
  String? _selectedSupplierID;
  final TextEditingController _docNumberController = TextEditingController();
  final TextEditingController _remarkController = TextEditingController();
  String _vatType = 'Included';
  String _paymentType = 'Cash';
  
  List<Supplier> _supplierList = [];
  List<PurchaseOrderItem> _currentPoItems = [];
  
  // Footer totals
  final TextEditingController _sumAmountController = TextEditingController(text: '0.0');
  final TextEditingController _vatAmountController = TextEditingController(text: '0.0');
  final TextEditingController _totalAmountController = TextEditingController(text: '0.0');
  final TextEditingController _paidAmountController = TextEditingController(text: '0.0');

  // AddItemSection states
  bool _showAddItem = false;
  final TextEditingController _searchController = TextEditingController();
  List<MerchandiseItem> _searchResult = [];

  MerchandiseItem? _selectedItem;
  MerchandisePack? _selectedPack;
  String _selectedItemName = '';
  int _selectedUP = 0;
  List<Map<String, dynamic>> _unitPackList = [];

  final TextEditingController _orderQuantityController = TextEditingController();
  final TextEditingController _receivedQuantityController = TextEditingController();
  final TextEditingController _unitPriceController = TextEditingController();
  final TextEditingController _itemAmountController = TextEditingController();

  Map<String, String> _settingValue = {};
  int _vatPercent = 7;

  @override
  void initState() {
    super.initState();
    _config = widget.config;
    _loadPermissionsAndData();
    _loadCategories();
  }

  Future<void> _loadPermissionsAndData() async {
    final roleID = _config.UserRole;
    if (roleID != null) {
      final perm = await GeneralServices.getRoleTransactionPermissionList(roleID, 'FO_PURCHASE_ORDER');
      final level = perm?['PermissionLevel'];
      
      setState(() {
        poCreate = level == 'Create' || level == 'Full';
        poIssue = level == 'Issue' || level == 'Full';
        poReceive = level == 'Receive' || level == 'Full';
        poFull = level == 'Full';
      });
    }
    
    final isar = Isar.getInstance()!;
    final suppliers = await isar.supplierList.where().filter().isActiveEqualTo('Y').findAll();
    
    final settings = await isar.settingValueList.where().filter().anyOf([
      'FOC_PRICE_TYPE', 'FOC_VAT_PERCENT', 'FOC_CALC_UNIT_COST'
    ], (q, String id) => q.setting_IDEqualTo(id)).findAll();

    Map<String, String> settingVal = {
      'FOC_PRICE_TYPE': 'PriceNon', 
      'FOC_VAT_PERCENT': '7',
      'FOC_CALC_UNIT_COST': 'Average'
    };

    for (var sv in settings) {
      if (sv.setting_ID != null && sv.value != null) {
        settingVal[sv.setting_ID!] = sv.value!;
      }
    }

    int vatPct = int.tryParse(settingVal['FOC_VAT_PERCENT'] ?? '7') ?? 7;

    setState(() {
      _supplierList = suppliers;
      _settingValue = settingVal;
      _vatPercent = vatPct;
    });

    await _handleSearchList();
    await _loadCategories();
  }

  Future<List<Map<String, dynamic>>> _getChildrenRecursive(String parentType, String parentID) async {
    final isar = Isar.getInstance()!;
    final children = await isar.merchandiseCategoryList
        .where()
        .filter()
        .parentTypeEqualTo(parentType)
        .and()
        .parentIDEqualTo(parentID)
        .and()
        .isActiveEqualTo('Y')
        .findAll();

    final result = await Future.wait(children.map((child) async {
      final sub = await _getChildrenRecursive('merchandise_category', child.id ?? '');
      return {
        'ID': child.id,
        'ParentType': child.parentType,
        'ParentID': child.parentID,
        'CategoryName': child.categoryName,
        'Sub': sub,
      };
    }));

    return result;
  }

  Future<void> _loadCategories() async {
    final nodes = await _getChildrenRecursive('shop', _config.shop_ID ?? '');
    if (mounted) {
      setState(() {
        _categoriesNode = nodes;
      });
    }
  }

  Future<void> _handleSearchList() async {
    final isar = Isar.getInstance()!;
    final statusList = _status.entries.where((e) => e.value).map((e) => e.key).toList();
    
    // Format dates to ISO strings for comparison
    final fromDateStr = DateFormat('yyyy-MM-dd').format(_fromDate) + 'T00:00:00.000';
    final toDateStr = DateFormat('yyyy-MM-dd').format(_toDate) + 'T23:59:59.999';

    final allPOs = await isar.purchaseOrderList.where().findAll();
    debugPrint('all purchaseOrderList length: ${allPOs.length}');
    for (var po in allPOs) {
      debugPrint('PO ID: ${po.id}, status: ${po.status}, lastUpdated: ${po.lastUpdated}');
    }

    final result = await isar.purchaseOrderList
        .filter()
        .lastUpdatedBetween(fromDateStr, toDateStr)
        .findAll();
        
    debugPrint('result length: ${result.length} (from: $fromDateStr, to: $toDateStr)');
    for (var po in result) {
      debugPrint('Result PO id: ${po.id}, status: ${po.status}, lastUpdated: ${po.lastUpdated}');
    }

    final filteredResult = result.where((po) => statusList.contains(po.status)).toList();
    debugPrint('filteredResult length: ${filteredResult.length} (status filter: $statusList)');

    setState(() {
      _poList = filteredResult;
    });
  }

  String _formatNumber(double? val) {
    if (val == null) return '';
    return val % 1 == 0 ? val.toInt().toString() : val.toString();
  }

  Future<void> _selectDate(BuildContext context, bool isFrom) async {
    final initialDate = isFrom ? _fromDate : _toDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2101),
    );
    if (picked != null) {
      setState(() {
        if (isFrom) {
          _fromDate = picked;
        } else {
          _toDate = picked;
        }
      });
      _handleSearchList();
    }
  }

  Widget _buildListSection() {
    return Column(
      children: [
        // Row 1: Dates
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => _selectDate(context, true),
                  child: AbsorbPointer(
                    child: TextField(
                      decoration: InputDecoration(
                        labelText: isThai ? 'ตั้งแต่วันที่' : 'From Date',
                        border: const OutlineInputBorder(),
                        suffixIcon: const Icon(Icons.calendar_today),
                      ),
                      controller: TextEditingController(text: DateFormat('yyyy-MM-dd').format(_fromDate)),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: GestureDetector(
                  onTap: () => _selectDate(context, false),
                  child: AbsorbPointer(
                    child: TextField(
                      decoration: InputDecoration(
                        labelText: isThai ? 'ถึงวันที่' : 'To Date',
                        border: const OutlineInputBorder(),
                        suffixIcon: const Icon(Icons.calendar_today),
                      ),
                      controller: TextEditingController(text: DateFormat('yyyy-MM-dd').format(_toDate)),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        // Row 2: Status Toggles
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
          child: Row(
            children: _status.keys.map((statusKey) {
              final isSelected = _status[statusKey] ?? false;
              return Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: ChoiceChip(
                  label: Text(statusText[statusKey] ?? statusKey),
                  selected: isSelected,
                  onSelected: (bool selected) {
                    setState(() {
                      _status[statusKey] = selected;
                    });
                    _handleSearchList();
                  },
                ),
              );
            }).toList(),
          ),
        ),
        const Divider(),
        // List of Purchase Orders
        Expanded(
          child: ListView.builder(
            itemCount: _poList.length,
            itemBuilder: (context, index) {
              final po = _poList[index];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: ListTile(
                  title: Text(po.code ?? '-'),
                  subtitle: Text(statusText[po.status] ?? po.status ?? ''),
                  trailing: IconButton(
                    icon: const Icon(Icons.search),
                    onPressed: () {
                      setState(() {
                        _currentSection = 'Detail';
                      });
                    },
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildAddSection() {
    if (_showAddItem) {
      return _buildAddItemSection();
    }

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Row 0: Header
                Container(
                  padding: const EdgeInsets.all(16),
                  color: Colors.grey[200],
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    isThai ? 'เพิ่ม' : 'Add',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),
                // Row 1: Supplier & Document Number
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(isThai ? 'ผู้ขาย' : 'Supplier'),
                          const SizedBox(height: 8),
                          DropdownButtonFormField<String>(
                            value: _selectedSupplierID,
                            decoration: const InputDecoration(border: OutlineInputBorder()),
                            items: _supplierList.map((supplier) {
                              return DropdownMenuItem(
                                value: supplier.id,
                                child: Text(isThai ? (supplier.thaiName ?? '') : (supplier.englishName ?? '')),
                              );
                            }).toList(),
                            onChanged: (val) {
                              setState(() {
                                _selectedSupplierID = val;
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(isThai ? 'หมายเลขเอกสาร' : 'Document Number'),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _docNumberController,
                            decoration: const InputDecoration(border: OutlineInputBorder()),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Row 3: Vat Type & Payment Type
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(isThai ? 'ประเภทภาษีมูลค่าเพิ่ม' : 'Vat Type'),
                          const SizedBox(height: 8),
                          DropdownButtonFormField<String>(
                            value: _vatType,
                            decoration: const InputDecoration(border: OutlineInputBorder()),
                            items: [
                              DropdownMenuItem(value: 'Non', child: Text(isThai ? 'ไม่มี' : 'Non')),
                              DropdownMenuItem(value: 'Included', child: Text(isThai ? 'รวม' : 'Included')),
                              DropdownMenuItem(value: 'Excluded', child: Text(isThai ? 'ไม่รวม' : 'Excluded')),
                            ],
                            onChanged: (val) {
                              setState(() {
                                _vatType = val ?? 'Excluded';
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(isThai ? 'ประเภทการชำระเงิน' : 'Payment Type'),
                          const SizedBox(height: 8),
                          DropdownButtonFormField<String>(
                            value: _paymentType,
                            decoration: const InputDecoration(border: OutlineInputBorder()),
                            items: [
                              DropdownMenuItem(value: 'Cash', child: Text(isThai ? 'เงินสด' : 'Cash')),
                              DropdownMenuItem(value: 'MoneyTransfer', child: Text(isThai ? 'โอนเงิน' : 'Money Transfer')),
                            ],
                            onChanged: (val) {
                              setState(() {
                                _paymentType = val ?? 'Cash';
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                // Middle section: Item list
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _currentPoItems.length,
                  itemBuilder: (context, index) {
                    final item = _currentPoItems[index];
                    return FutureBuilder<Map<String, dynamic>>(
                      future: _getPoItemDetails(item),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) return const CircularProgressIndicator();
                        final details = snapshot.data!;
                        return Card(
                          child: ListTile(
                            title: Text(details['productName'] ?? ''),
                            subtitle: Text('${_formatNumber(item.receivedQuantity)} ${details['unitName']} @${_formatNumber(item.unitPrice)}'),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _formatNumber(item.itemAmount),
                                  style: const TextStyle(color: Colors.blue, fontSize: 20), // Reduced from 40 for fit
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete, color: Colors.red),
                                  onPressed: () => _confirmDeleteItem(index),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
                const SizedBox(height: 16),
                // Add Item Button
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _showAddItem = true;
                      _searchResult = [];
                      _searchController.clear();
                    });
                  },
                  child: Text(isThai ? 'เพิ่มรายการ' : 'Add Item'),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _remarkController,
                  decoration: InputDecoration(
                    labelText: isThai ? 'หมายเหตุ' : 'Remark',
                    border: const OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
              ],
            ),
          ),
        ),
        // Footer fixed bottom
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.grey[200],
          child: Column(
            children: [
              // Row 1
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _sumAmountController,
                      decoration: InputDecoration(
                        labelText: isThai ? 'รวม' : 'Sum Amount',
                        border: const OutlineInputBorder(),
                      ),
                      onChanged: _updateTotalAmount,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _vatAmountController,
                      decoration: InputDecoration(
                        labelText: isThai ? 'ภาษีมูลค่าเพิ่ม' : 'Vat Amount',
                        border: const OutlineInputBorder(),
                      ),
                      onChanged: _updateTotalAmount,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Row 2
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _totalAmountController,
                      decoration: InputDecoration(
                        labelText: isThai ? 'รวมทั้งหมด' : 'Total Amount',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _paidAmountController,
                      decoration: InputDecoration(
                        labelText: isThai ? 'จำนวนเงินที่จ่าย' : 'Paid Amount',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Row 3
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: _status.keys.map((statusKey) {
                  return ElevatedButton(
                    onPressed: () => _processOrder(statusKey),
                    child: Text(statusText[statusKey] ?? statusKey),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<Map<String, dynamic>> _getPoItemDetails(PurchaseOrderItem item) async {
    final isar = Isar.getInstance()!;
    String productName = '';
    String unitName = '';

    if (item.stockType == 'merchandise_item') {
      final mi = await isar.merchandiseItemList.where().filter().idEqualTo(item.stockID ?? '').findFirst();
      productName = mi?.productName ?? '';
      unitName = mi?.unitName ?? '';
    } else {
      final mp = await isar.merchandisePackList.where().filter().idEqualTo(item.stockID ?? '').findFirst();
      if (mp != null) {
        final mi = await isar.merchandiseItemList.where().filter().idEqualTo(mp.merchandise_item_ID ?? '').findFirst();
        productName = mi?.productName ?? '';
        unitName = mp.packName ?? '';
      }
    }
    return {'productName': productName, 'unitName': unitName};
  }

  void _confirmDeleteItem(int index) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isThai ? 'ยืนยันการลบ' : 'Confirm Delete'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(isThai ? 'ยกเลิก' : 'Cancel'),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                _currentPoItems.removeAt(index);
                _recalculateTotals();
              });
              Navigator.pop(context);
            },
            child: Text(isThai ? 'ตกลง' : 'OK'),
          ),
        ],
      ),
    );
  }

  void _updateTotalAmount(String _) {
    // Logic to update totals manually if needed
  }

  void _recalculateTotals() {
    double sum = 0.0;
    for (var item in _currentPoItems) {
      sum += (item.itemAmount ?? 0.0);
    }
    
    double vatAmt = 0.0;
    double totalAmt = sum;

    if (_vatType == 'Non') {
      vatAmt = 0.0;
    } else if (_vatType == 'Included') {
      vatAmt = sum * _vatPercent / (_vatPercent + 100);
      sum -= vatAmt;
    } else { // Excluded
      vatAmt = sum * _vatPercent / 100;
      totalAmt += vatAmt;
    }

    _sumAmountController.text = sum.toStringAsFixed(2);
    _vatAmountController.text = vatAmt.toStringAsFixed(2);
    _totalAmountController.text = totalAmt.toStringAsFixed(2);
  }

  Future<void> _processOrder(String status) async {
    bool isDebug = true;
    String code = await GeneralServices.getDocumentCode('PURCHASE_ORDER');
    String poID = const Uuid().v4();
    
    final po = PurchaseOrder()
      ..id = poID
      ..code = code
      ..storeType = 'shop_branch'
      ..storeID = _config.shop_branch_ID
      ..supplier_ID = _selectedSupplierID
      ..supplierDocumentNumber = _docNumberController.text
      ..vatType = _vatType
      ..sumAmount = double.tryParse(_sumAmountController.text) ?? 0.0
      ..vatAmount = double.tryParse(_vatAmountController.text) ?? 0.0
      ..totalAmount = double.tryParse(_totalAmountController.text) ?? 0.0
      ..paidAmount = double.tryParse(_paidAmountController.text) ?? 0.0
      ..status = status
      ..paymentType = _paymentType
      ..lastUpdated = DateTime.now().toIso8601String()
      ..isDirty = true;

    final poLog = PurchaseOrderLog()
      ..id = const Uuid().v4()
      ..purchase_order_ID = poID
      ..status = status
      ..remark = _remarkController.text
      ..shop_user_ID = int.tryParse(_config.UserID ?? '0') ?? 0
      ..lastUpdated = DateTime.now().toIso8601String()
      ..isDirty = true;

    await isar.writeTxn(() async {
      await isar.purchaseOrderList.put(po);
      await isar.purchaseOrderLogList.put(poLog);

      if (isDebug) { 
        debugPrint('save PurchaseOrder ID: ${po.id}, code: ${po.code}, status: ${po.status}');
      }
      
      for (var item in _currentPoItems) {
        item.purchase_order_ID = poID;
        item.status = status;
        item.lastUpdated = DateTime.now().toIso8601String();
        item.isDirty = true;
        await isar.purchaseOrderItemList.put(item);

        if (isDebug) { 
          debugPrint('save PurchaseOrderItem seq: ${item.seq}, receivedQuantity: ${item.receivedQuantity}, unitCost: ${item.unitCost}, itemAmount: ${item.itemAmount}');
        }
      }
    });

    if (status == 'Received') {
      await InventoryServices.receivedPoIncreaseStock(poID);
    }

    await SyncService.syncPurchaseOrder(_config!);
    
    setState(() {
      _currentSection = 'List';
      _currentPoItems.clear();
      _docNumberController.clear();
      _remarkController.clear();
    });
    await _handleSearchList();
  }

  // --- AddItemSection implementation ---

  Widget _buildAddItemSection() {
    return Column(
      children: [
        // Row 1: Search & Scanner
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.category),
                onPressed: () => _showCategorySection(),
              ),
              Expanded(
                child: TextField(
                  controller: _searchController,
                  onChanged: _handleSearch,
                  decoration: const InputDecoration(
                    hintText: 'Search...',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.qr_code_scanner),
                onPressed: () => _openScanner(onScan: _handleScanCode),
              ),
            ],
          ),
        ),
        // Search Results
        if (_searchResult.isNotEmpty)
          Expanded(
            child: ListView.builder(
              itemCount: _searchResult.length,
              itemBuilder: (context, index) {
                final item = _searchResult[index];
                return ListTile(
                  title: Text(item.productName ?? ''),
                  subtitle: Text('Price: ${_formatNumber(item.price)}'),
                  onTap: () => _addToItem(item, null),
                );
              },
            ),
          ),
        // Item form if selected
        if (_selectedItem != null) ...[
          // Row 2
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(
              _selectedItemName,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          // Row 3
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
            child: Wrap(
              spacing: 8.0,
              children: _unitPackList.map((up) {
                final pack = up['pack'];
                final int level = pack?.level ?? 0;
                final bool isSelected = _selectedUP == level;
                return ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isSelected ? Colors.blue : Colors.grey[300],
                    foregroundColor: isSelected ? Colors.white : Colors.black,
                  ),
                  onPressed: () => _addToItem(_selectedItem!, pack),
                  child: Text(up['name'] ?? ''),
                );
              }).toList(),
            ),
          ),
          // Row 4
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _orderQuantityController,
                    decoration: InputDecoration(
                      labelText: isThai ? 'จำนวนที่สั่ง' : 'Order Quantity',
                      border: const OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: _changeOrderQuantity,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _receivedQuantityController,
                    decoration: InputDecoration(
                      labelText: isThai ? 'จำนวนที่ได้รับ' : 'Received Quantity',
                      border: const OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: _changeUnitPrice,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // Row 4
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _unitPriceController,
                    decoration: InputDecoration(
                      labelText: isThai ? 'ราคาต่อหน่วย' : 'Unit Price',
                      border: const OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: _changeUnitPrice,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _itemAmountController,
                    decoration: InputDecoration(
                      labelText: isThai ? 'รวม' : 'Item Amount',
                      border: const OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: _changeItemAmount,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Row 5
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                SizedBox(
                  width: MediaQuery.of(context).size.width * 0.25,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                    onPressed: _confirmCancelItem,
                    child: Text(isThai ? 'ยกเลิก' : 'Cancel', style: const TextStyle(color: Colors.white)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                    onPressed: _saveItem,
                    child: Text(isThai ? 'บันทึก' : 'Save', style: const TextStyle(color: Colors.white)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildCategoryNode(Map<String, dynamic> category, int level) {
    final isar = Isar.getInstance()!;
    final subCategories = List<dynamic>.from(category['Sub'] ?? []);
    final hasSub = subCategories.isNotEmpty;
    final paddingLeft = 16.0 + (level * 16.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Colors.black12)),
          ),
          child: Padding(
            padding: EdgeInsets.only(left: paddingLeft, top: 8.0, bottom: 8.0, right: 8.0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    category['CategoryName'] ?? '',
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
                FutureBuilder<int>(
                  future: isar.merchandiseItemList.where().filter().merchandise_category_IDEqualTo(category['ID']).count(),
                  builder: (context, snapshot) {
                    int count = snapshot.data ?? 0;
                    if (count > 0) {
                      return IconButton(
                        icon: const Icon(Icons.search),
                        onPressed: () => _searchByCategory(category['ID'] ?? ''),
                      );
                    }
                    return const SizedBox.shrink();
                  }
                ),
              ],
            ),
          ),
        ),
        if (hasSub)
          ...subCategories.map((sub) => _buildCategoryNode(Map<String, dynamic>.from(sub), level + 1)),
      ],
    );
  }

  Widget _buildCategorySection() {
    if (_categoriesNode.isEmpty) {
      return const Center(child: Text('ไม่มีข้อมูลหมวดหมู่สินค้า'));
    }
    return ListView.builder(
      itemCount: _categoriesNode.length,
      itemBuilder: (context, index) {
        final category = Map<String, dynamic>.from(_categoriesNode[index]);
        return _buildCategoryNode(category, 0);
      },
    );
  }

  Future<void> _searchByCategory(String categoryID) async {
    final isar = Isar.getInstance()!;
    final items = await isar.merchandiseItemList.where()
        .filter()
        .merchandise_category_IDEqualTo(categoryID)
        .findAll();
    
    setState(() {
      _searchResult = items;
    });
    Navigator.pop(context); // Close the bottom sheet
  }

  void _showCategorySection() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return SizedBox(
          height: MediaQuery.of(context).size.height * 0.7,
          child: Column(
            children: [
              AppBar(
                title: Text(isThai ? 'หมวดหมู่สินค้า' : 'Category'),
                leading: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
              Expanded(
                child: _buildCategorySection(),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _handleSearch(String term) async {
    if (term.length >= 3) {
      final isar = Isar.getInstance()!;
      final results = await isar.merchandiseItemList.where()
         .filter()
         .barcodeContains(term, caseSensitive: false)
         .or()
         .productNameContains(term, caseSensitive: false)
         .findAll();
      
      setState(() {
         _searchResult = results;
      });
    } else {
      setState(() {
        _searchResult = [];
      });
    }
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
                        Navigator.pop(context);
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

  Future<void> _handleScanCode(String code) async {
    final isar = Isar.getInstance()!;
    var item = await isar.merchandiseItemList.where().filter().barcodeEqualTo(code).findFirst();
    if (item != null) {
      _addToItem(item, null);
      return;
    }
    
    var pack = await isar.merchandisePackList.where().filter().barcodeEqualTo(code).findFirst();
    if (pack != null) {
      var pItem = await isar.merchandiseItemList.where().filter().idEqualTo(pack.merchandise_item_ID ?? '').findFirst();
      if (pItem != null) {
         _addToItem(pItem, pack);
         return;
      }
    }
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Not found')));
  }

  Future<void> _addToItem(MerchandiseItem item, MerchandisePack? pack) async {
    final isar = Isar.getInstance()!;
    int selectedUP = 0;
    List<Map<String, dynamic>> unitPackList = [{'name': item.unitName, 'pack': null}];

    final packList = await isar.merchandisePackList
        .where()
        .filter()
        .merchandise_item_IDEqualTo(item.id)
        .findAll();
    
    packList.sort((a, b) => (a.level ?? 0).compareTo(b.level ?? 0));

    for (var p in packList) {
      if (p.id == pack?.id) { selectedUP = p.level ?? 0; }
      unitPackList.add({'name': p.packName, 'pack': p});
    }

    setState(() {
      _selectedUP = selectedUP;
      _unitPackList = unitPackList;
      _selectedItem = item;
      _selectedPack = pack;
      _searchResult = [];
      
      if (pack != null) {
        _selectedItemName = '${pack.packName} (${item.productName})';
        _unitPriceController.text = (pack.price ?? 0.0).toString();
      } else {
        _selectedItemName = item.productName ?? '';
        _unitPriceController.text = (item.price ?? 0.0).toString();
      }
      
      _orderQuantityController.text = '1';
      _receivedQuantityController.text = '1';
      _changeUnitPrice('');
    });
  }

  void _changeOrderQuantity(String val) {
    _receivedQuantityController.text = _orderQuantityController.text;
    _changeUnitPrice('');
  }

  void _changeUnitPrice(String val) {
    double price = double.tryParse(_unitPriceController.text) ?? 0.0;
    double rQty = double.tryParse(_receivedQuantityController.text) ?? 0.0;
    if (_unitPriceController.text.isNotEmpty && _receivedQuantityController.text.isNotEmpty) {
      _itemAmountController.text = (price * rQty).toStringAsFixed(2);
    }
    _changeItemAmount('');
  }

  void _changeItemAmount(String val) {
    // Logic can be added here if needed to recalculate reverse
  }

  void _confirmCancelItem() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isThai ? 'ยืนยันการยกเลิก' : 'Confirm Cancel'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(isThai ? 'ยกเลิก' : 'No'),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                _selectedItem = null;
                _selectedPack = null;
                _showAddItem = false;
              });
              Navigator.pop(context);
            },
            child: Text(isThai ? 'ตกลง' : 'Yes'),
          ),
        ],
      ),
    );
  }

  void _saveItem() {
    if (_selectedItem == null) return;
    
    double itemAmt = double.tryParse(_itemAmountController.text) ?? 0.0;
    double rQty = double.tryParse(_receivedQuantityController.text) ?? 1.0;
    double oQty = double.tryParse(_orderQuantityController.text) ?? 1.0;
    double price = double.tryParse(_unitPriceController.text) ?? 0.0;
    
    double costAmount = itemAmt;

    String priceType = _settingValue['FOC_PRICE_TYPE'] ?? 'PriceNon';
    
    if ((priceType == 'PriceNon' || priceType == 'PriceIncluded') && _vatType == 'Excluded') {
      costAmount += (costAmount * _vatPercent / 100);
    } else if (priceType == 'PriceExcluded' && _vatType == 'Included') {
      costAmount = costAmount * 100 / (_vatPercent + 100);
    }

    double unitCost = rQty > 0 ? costAmount / rQty : 0.0;

    final newItem = PurchaseOrderItem()
      ..id = const Uuid().v4()
      ..purchase_order_ID = '' // Assign later when PO is saved
      ..seq = _currentPoItems.length + 1
      ..stockType = _selectedPack != null ? 'merchandise_pack' : 'merchandise_item'
      ..stockID = _selectedPack?.id ?? _selectedItem?.id
      ..orderQuantity = oQty
      ..unitPrice = price
      ..itemAmount = itemAmt
      ..receivedQuantity = rQty
      ..unitCost = unitCost
      ..status = 'Created'
      ..lastUpdated = DateTime.now().toIso8601String()
      ..isDirty = true;

    setState(() {
      _currentPoItems.add(newItem);
      _selectedItem = null;
      _selectedPack = null;
      _showAddItem = false;
      _recalculateTotals();
    });
  }

  Widget _buildDetailSection() {
    return const Center(child: Text('Detail Section Placeholder'));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(isThai ? 'สั่งซื้อ' : 'Purchase'),
        actions: [
          IconButton(
            icon: const Icon(Icons.home),
            onPressed: () {
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(
                  builder: (context) => PPosScreen(config: _config),
                ),
                (route) => false,
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.list),
            onPressed: () {
              setState(() {
                _currentSection = 'List';
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () async {
              await SyncService.syncPurchaseOrder(_config);
              _handleSearchList();
            },
          ),
          if (poCreate || poFull)
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: () {
                setState(() {
                  _currentSection = 'Add';
                });
              },
            ),
        ],
      ),
      body: _currentSection == 'List'
          ? _buildListSection()
          : _currentSection == 'Add'
              ? _buildAddSection()
              : _buildDetailSection(),
    );
  }
}
