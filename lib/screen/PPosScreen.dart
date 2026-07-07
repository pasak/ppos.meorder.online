import 'dart:io';
import 'package:flutter/material.dart';

import 'package:meorder_ppos/lib/EnvConfig.dart';
import 'package:meorder_ppos/screen/FoodMenuScreen.dart';
import 'package:meorder_ppos/screen/PaymentScreen.dart';
import 'package:meorder_ppos/screen/ReceiptScreen.dart';
import 'package:meorder_ppos/screen/AdminScreen.dart';
import 'package:isar/isar.dart';
import 'package:meorder_ppos/database/IsarModels.dart';
import 'package:uuid/uuid.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:meorder_ppos/services/GeneralServices.dart';

class PPosScreen extends StatefulWidget {
  final EnvConfig config;
  final String? receiptID;
  const PPosScreen({super.key, required this.config, this.receiptID});

  @override
  State<PPosScreen> createState() => _PPosScreenState();
}

class _PPosScreenState extends State<PPosScreen> {
  bool _isLifeTime = false;
  bool get _isExpired => widget.config.isExpired ?? false;
  bool _canOrderFood = false;
  bool _canSellMerchandise = false;
  bool _canSellNonStock = false;
  Isar isar = Isar.getInstance()!;
  
  bool get isThai => widget.config.language == 'th';

  String _currentSection = 'Cart'; // 'Category', 'SearchResult', 'Cart'
  List<Map<String, dynamic>> _categoriesNode = [];
  List<MerchandiseItem> _searchResult = [];
  List<ReceiptItem> _cartItems = [];
  
  Map<String, String> _itemNames = {};
  Map<String, String> _packNames = {};

  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _checkLifeTime();
    _checkPermissions();
    _loadCategories();
  }

  void _checkPermissions() async {
    if (widget.config.UserRole == null) return;
    
    final roleID = widget.config.UserRole!;
    final foOrderFood = await GeneralServices.getRoleTransactionPermissionList(roleID, 'FO_ORDER_FOOD');
    final foSellMerchandise = await GeneralServices.getRoleTransactionPermissionList(roleID, 'FO_SELL_MERCHANDISE');
    final foSellNonStock = await GeneralServices.getRoleTransactionPermissionList(roleID, 'FO_SELL_NON_STOCK');

    if (mounted) {
      setState(() {
        _canOrderFood = foOrderFood?['PermissionLevel'] == 'Full';
        _canSellMerchandise = foSellMerchandise?['PermissionLevel'] == 'Full';
        _canSellNonStock = foSellNonStock?['PermissionLevel'] == 'Full';
      });
    }

    if (foSellMerchandise == null || foSellMerchandise['PermissionLevel'] != 'Full') {
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Text('Error'),
            content: Text(widget.config.language == 'th' ? 'คุณไม่มีสิทธิใช้งาน' : 'You do not have permission to access'),
            actions: [
              TextButton(
                onPressed: () {
                   Navigator.of(context).pop();
                   Navigator.of(context).pop(); // Exit screen
                },
                child: const Text('OK')
              )
            ]
          )
        );
      }
    }
  }

  void _checkLifeTime() {
    if (widget.config.IntervalType == 'LIFE') {
      _isLifeTime = true;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _formatPrice(double? price) {
    if (price == null) return '';
    return price % 1 == 0 ? price.toInt().toString() : price.toString();
  }

  Future<List<Map<String, dynamic>>> _getChildrenRecursive(String parentType, String parentID) async {
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
    final nodes = await _getChildrenRecursive('shop', widget.config.shop_ID ?? '');
    if (mounted) {
      setState(() {
        _categoriesNode = nodes;
      });
    }
  }

  Future<void> _handleSearch(String term) async {
    if (term.length >= 3) {
      final results = await isar.merchandiseItemList.where()
         .filter()
         .barcodeContains(term, caseSensitive: false)
         .or()
         .productNameContains(term, caseSensitive: false)
         .findAll();
      
      final stockResults = await _getStock(results);
      
      setState(() {
         _searchResult = stockResults;
         if (stockResults.isNotEmpty) _currentSection = 'SearchResult';
      });
    }
  }

  Future<void> _searchByCategory(String categoryID) async {
    final results = await isar.merchandiseItemList.where().filter().merchandise_category_IDEqualTo(categoryID).findAll();
    final stockResults = await _getStock(results);
    setState(() {
      _searchResult = stockResults;
      _currentSection = 'SearchResult';
    });
  }

  Future<double?> _checkNextLevelMerchandiseStockList(String stockType, String stockID) async {
    if (stockType == 'merchandise_item') {
      var packL1List = await isar.merchandisePackList
          .where()
          .filter()
          .merchandise_item_IDEqualTo(stockID)
          .and()
          .levelEqualTo(1)
          .findAll();

      double totalQty = 0;
      for (var pack in packL1List) {
        var packStock = await isar.merchandiseStockList
            .where()
            .filter()
            .storeTypeEqualTo('shop_branch')
            .and()
            .storeIDEqualTo(int.tryParse(widget.config.shop_branch_ID ?? '0') ?? 0)
            .and()
            .stockTypeEqualTo('merchandise_pack')
            .and()
            .stockIDEqualTo(pack.id)
            .findFirst();

        double packAvail = packStock?.availableQuantity ?? 0.0;
        if (packAvail > 0) {
          totalQty += packAvail * (pack.quantity ?? 1).toDouble();
        } else {
          double? nextQty = await _checkNextLevelMerchandiseStockList('merchandise_pack', pack.id!);
          if (nextQty != null && nextQty > 0) {
             totalQty += nextQty * (pack.quantity ?? 1).toDouble();
          }
        }
      }
      return totalQty > 0 ? totalQty : null;

    } else if (stockType == 'merchandise_pack') {
      var currentPack = await isar.merchandisePackList
          .where()
          .filter()
          .idEqualTo(stockID)
          .findFirst();

      if (currentPack != null) {
        int currentLevel = currentPack.level ?? 1;
        var nextLevelPacks = await isar.merchandisePackList
            .where()
            .filter()
            .merchandise_item_IDEqualTo(currentPack.merchandise_item_ID)
            .and()
            .levelEqualTo(currentLevel + 1)
            .findAll();

        double totalQty = 0;
        for (var nextPack in nextLevelPacks) {
          var nextPackStock = await isar.merchandiseStockList
              .where()
              .filter()
              .storeTypeEqualTo('shop_branch')
              .and()
              .storeIDEqualTo(int.tryParse(widget.config.shop_branch_ID ?? '0') ?? 0)
              .and()
              .stockTypeEqualTo('merchandise_pack')
              .and()
              .stockIDEqualTo(nextPack.id)
              .findFirst();

          double nextAvail = nextPackStock?.availableQuantity ?? 0.0;
          if (nextAvail > 0) {
            totalQty += nextAvail * (nextPack.quantity ?? 1).toDouble();
          } else {
            double? nextQty = await _checkNextLevelMerchandiseStockList('merchandise_pack', nextPack.id!);
            if (nextQty != null && nextQty > 0) {
              totalQty += nextQty * (nextPack.quantity ?? 1).toDouble();
            }
          }
        }
        return totalQty > 0 ? totalQty : null;
      }
    }
    return null;
  }

  Future<List<MerchandiseItem>> _getStock(List<MerchandiseItem> merchandiseItemList) async {
    List<MerchandiseItem> results = [];

    final bool isDebug = true;

    for (var mi in merchandiseItemList) {
      var ms = await isar.merchandiseStockList
          .where()
          .filter()
          .storeTypeEqualTo('shop_branch')
          .and()
          .storeIDEqualTo(int.tryParse(widget.config.shop_branch_ID ?? '0') ?? 0)
          .and()
          .stockTypeEqualTo('merchandise_item')
          .and()
          .stockIDEqualTo(mi.id)
          .findFirst();

      if (ms == null) {
        mi.availableQuantity =  0.0;

        /* ไม่จำเป็นต้องสร้างสต๊อคไว้ก่อน
        ms = MerchandiseStock()
          ..id = const Uuid().v4()
          ..storeType = 'shop_branch'
          ..storeID = int.tryParse(widget.config.shop_branch_ID ?? '0') ?? 0
          ..stockType = 'merchandise_item'
          ..stockID = mi.id
          ..currentQuantity = 0.0
          ..availableQuantity = 0.0 
          ..unitCost = 0.0
          ..lastUpdated = DateTime.now().toIso8601String()
          ..isDirty = true;
          
        await isar.writeTxn(() async {
          await isar.merchandiseStockList.put(ms!);
        });

        if (isDebug) { 
          debugPrint('_getStock create MerchandiseStock id: ${ms!.id}, storeType: ${ms!.storeType}, storeID: ${ms!.storeID}, stockType: ${ms!.stockType}, stockID: ${ms!.stockID}, current: ${ms!.currentQuantity}, available: ${ms!.availableQuantity}, isDirty: ${ms!.isDirty}'); 
        }
        */
      } else {
        mi.availableQuantity = ms.availableQuantity;
      }

      if (_canSellNonStock || (mi.availableQuantity ?? 0.0) > 0.0) {
        results.add(mi);
      } else {
        double? packQty = await _checkNextLevelMerchandiseStockList('merchandise_item', mi.id!);

        if (packQty != null && packQty > 0) {
          mi.availableQuantity = packQty;
          results.add(mi);
        }
      }
    }

    return results;
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
                title: const Text('สแกนบาร์โค้ด'),
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

  Future<void> _handleScanCode(String code) async {
    var item = await isar.merchandiseItemList.where().filter().barcodeEqualTo(code).findFirst();
    if (item != null) {
      var stockList = await _getStock([item]);
      if (stockList.isNotEmpty) {
        item = stockList.first;
      } else {
        item.availableQuantity = 0.0;
      }
      _addToCart(item, null);
      return;
    }
    
    var pack = await isar.merchandisePackList.where().filter().barcodeEqualTo(code).findFirst();
    if (pack != null) {
      var pItem = await isar.merchandiseItemList.where().filter().idEqualTo(pack.merchandise_item_ID ?? '').findFirst();
      if (pItem != null) {
         var packStock = await isar.merchandiseStockList
             .where()
             .filter()
             .storeTypeEqualTo('shop_branch')
             .and()
             .storeIDEqualTo(int.tryParse(widget.config.shop_branch_ID ?? '0') ?? 0)
             .and()
             .stockTypeEqualTo('merchandise_pack')
             .and()
             .stockIDEqualTo(pack.id)
             .findFirst();

         double pAvail = packStock?.availableQuantity ?? 0.0;
         if (pAvail == 0) {
           double? nextQty = await _checkNextLevelMerchandiseStockList('merchandise_pack', pack.id!);
           pAvail = nextQty ?? 0.0;
         }
         pack.availableQuantity = pAvail;
         
         _addToCart(pItem, pack);
         return;
      }
    }
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Not found')));
  }

  Future<void> _addToCart(MerchandiseItem item, MerchandisePack? pack) async {
    bool _notEnoughQty = false;
    int idx = _cartItems.indexWhere((e) => e.merchandise_item_ID == item.id && e.merchandise_pack_ID == pack?.id);
    int reqQty = (idx >= 0) ? (_cartItems[idx].quantity ?? 0) + 1 : 1;

    if (_canSellNonStock == false) {
      if (pack != null) {
        if ((pack.availableQuantity ?? 0.0) < reqQty) {
          _notEnoughQty = true;
        }
      } else {
        if ((item.availableQuantity ?? 0.0) < reqQty) {
          _notEnoughQty = true;
        }
      }
    }

    if (_notEnoughQty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(isThai ? 'สต็อคไม่เพียงพอ' : 'Not enough stock'), backgroundColor: Colors.red));
      return;
    }

    if (idx >= 0) {
      setState(() {
        _cartItems[idx].quantity = (_cartItems[idx].quantity ?? 0) + 1;
      });
    } else {
      final rItem = ReceiptItem()
        ..id = const Uuid().v4()
        ..merchandise_item_ID = item.id
        ..merchandise_pack_ID = pack?.id
        ..itemPrice = pack != null ? pack.price : item.price
        ..unitCost = 0.0
        ..quantity = 1
        ..discountPercent = 0
        ..discountAmount = 0
        ..lastUpdated = DateTime.now().toIso8601String()
        ..isDirty = true;
        
      _itemNames[item.id ?? ''] = item.productName ?? '';
      
      if (pack != null) {
        String unitName = item.unitName ?? '';
        final currentLevel = pack.level ?? 1;
        
        if (currentLevel > 1) {
          final allPacks = await isar.merchandisePackList.where()
              .filter()
              .merchandise_item_IDEqualTo(item.id)
              .findAll();
              
          try {
            final prevPack = allPacks.firstWhere((p) => (p.level ?? 1) == currentLevel - 1);
            unitName = prevPack.packName ?? '';
          } catch (e) {
            allPacks.sort((a, b) => (a.level ?? 1).compareTo(b.level ?? 1));
            int packIdx = allPacks.indexWhere((p) => p.id == pack.id);
            if (packIdx > 0) {
              unitName = allPacks[packIdx - 1].packName ?? '';
            }
          }
        }
        _packNames[pack.id ?? ''] = '${pack.packName ?? '-'} ${pack.quantity ?? 1} $unitName';
      }
      
      setState(() {
        _cartItems.add(rItem);
      });
    }
    setState(() { _currentSection = 'Cart'; });
  }

  Future<void> _showPacks(MerchandiseItem item) async {
    final packs = await isar.merchandisePackList.where().filter().merchandise_item_IDEqualTo(item.id).findAll();
    if (packs.isEmpty) return;

    for (var p in packs) {
      var pStock = await isar.merchandiseStockList
          .where()
          .filter()
          .storeTypeEqualTo('shop_branch')
          .and()
          .storeIDEqualTo(int.tryParse(widget.config.shop_branch_ID ?? '0') ?? 0)
          .and()
          .stockTypeEqualTo('merchandise_pack')
          .and()
          .stockIDEqualTo(p.id)
          .findFirst();

      double pAvail = pStock?.availableQuantity ?? 0.0;
      if (pAvail == 0) {
        double? nextQty = await _checkNextLevelMerchandiseStockList('merchandise_pack', p.id!);
        pAvail = nextQty ?? 0.0;
      }
      p.availableQuantity = pAvail;
    }

    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        return ListView.builder(
          itemCount: packs.length,
          itemBuilder: (ctx, idx) {
            final p = packs[idx];
            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: ListTile(
                title: Text('${p.packName} (${p.quantity} ${item.unitName})'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _formatPrice(p.price),
                      style: const TextStyle(fontSize: 30, color: Colors.blue),
                    ),
                    const SizedBox(width: 16),
                    IconButton(
                      icon: const Icon(Icons.add_shopping_cart, color: Colors.green),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _addToCart(item, p);
                      }
                    )
                  ],
                ),
              ),
            );
          }
        );
      }
    );
  }

  Future<void> _orderMerchandise() async {
    if (_cartItems.isEmpty) return;
    try {
      final uuid = const Uuid();
      DateTime now = DateTime.now();
      
      double totalAmount = 0;
      for (var ci in _cartItems) {
        totalAmount += ((ci.itemPrice ?? 0) * (ci.quantity ?? 1));
      }

      String? receiptID = widget.receiptID;

      await isar.writeTxn(() async {
        Receipt? existingReceipt;
        if (receiptID != null) {
          existingReceipt = await isar.receiptList.where().filter().idEqualTo(receiptID).findFirst();
        }

        if (existingReceipt != null) {
          existingReceipt.sumAmount = (existingReceipt.sumAmount ?? 0.0) + totalAmount;
          existingReceipt.totalAmount = (existingReceipt.totalAmount ?? 0.0) + totalAmount;
          existingReceipt.status = 'Wait4Payment';
          existingReceipt.lastUpdated = now.toIso8601String();
          existingReceipt.isDirty = true;
          await isar.receiptList.put(existingReceipt);

          for (var ci in _cartItems) {
            ci.receipt_ID = receiptID;
            await isar.receiptItemList.put(ci);
          }
        } else {
          String code = await GeneralServices.getDocumentCode('FO_RECEIPT', posID: widget.config.PosID);

          receiptID = uuid.v4();
          final receipt = Receipt()
            ..id = receiptID
            ..pos_ID = int.tryParse(widget.config.PosID ?? '0')
            ..shop_user_ID = int.tryParse(widget.config.UserID ?? '0')
            ..shop_customer_ID = '0'
            ..code = code
            ..createdAt = now
            ..sumAmount = totalAmount
            ..totalAmount = totalAmount
            ..status = 'Wait4Payment'
            ..lastUpdated = now.toIso8601String()
            ..isDirty = true;

          await isar.receiptList.put(receipt);

          for (var ci in _cartItems) {
            ci.receipt_ID = receiptID;
            await isar.receiptItemList.put(ci);
          }
        }
      });

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => PaymentScreen(config: widget.config, receiptID: receiptID!)
        )
      );
    } catch (e) {
      debugPrint(e.toString());
    }
  }

  Widget _buildTopHeader() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                reverse: true,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_canSellMerchandise) ...[
                      IconButton(
                        icon: const Icon(Icons.category, color: Colors.black),
                        onPressed: () { setState(() { _currentSection = 'Category'; }); },
                      ),
                      IconButton(
                        icon: const Icon(Icons.qr_code_scanner, color: Colors.black),
                        onPressed: () => _openScanner(onScan: _handleScanCode),
                      ),
                      IconButton(
                        icon: const Icon(Icons.search, color: Colors.black),
                        onPressed: () { setState(() { _currentSection = 'SearchResult'; }); },
                      ),
                      IconButton(
                        icon: const Icon(Icons.shopping_cart, color: Colors.black),
                        onPressed: () { setState(() { _currentSection = 'Cart'; }); },
                      ),
                    ], // if (_canSellMerchandise)

                    if (_canOrderFood) ...[
                      IconButton(
                        icon: const Icon(Icons.restaurant_menu, color: Colors.black),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => FoodMenuScreen(
                                config: widget.config,
                                shop_open_table_ID: '0',
                              ),
                            ),
                          );
                        },
                      ),
                    ],

                    IconButton(
                      icon: const Icon(Icons.list, color: Colors.black),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ReceiptScreen(config: widget.config),
                          ),
                        );
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.settings, color: Colors.black),
                      onPressed: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => AdminScreen(config: widget.config),
                          ),
                        );
                        _checkPermissions();
                      },
                    ),
                  ],
                ),
              ),
            ),
          ], // children
        ),
      ),
    );
  }

  Widget _buildCategoryNode(Map<String, dynamic> category, int level) {
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

  Widget _buildSearchResultSection() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: TextField(
            controller: _searchController,
            onChanged: _handleSearch,
            decoration: InputDecoration(
              hintText: 'Search...',
              fillColor: Colors.white,
              filled: true,
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: _searchResult.length,
            itemBuilder: (context, index) {
              final item = _searchResult[index];
        return FutureBuilder<int>(
          future: isar.merchandisePackList.where().filter().merchandise_item_IDEqualTo(item.id).count(),
          builder: (context, snapshot) {
            int packCount = snapshot.data ?? 0;
            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: ListTile(
                title: Text(item.productName ?? ''),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _formatPrice(item.price),
                      style: const TextStyle(fontSize: 30, color: Colors.blue),
                    ),
                    const SizedBox(width: 16),
                    if (packCount > 0)
                      IconButton(
                        icon: const Icon(Icons.layers, color: Colors.blue), // Pack icon
                        onPressed: () => _showPacks(item),
                      ),
                    IconButton(
                      icon: const Icon(Icons.add_shopping_cart, color: Colors.green),
                      onPressed: () => _addToCart(item, null),
                    )
                  ],
                ),
              ),
            );
          }
        );
            }
          ),
        ),
      ],
    );
  }

  Widget _buildCartSection() {
    return ListView.builder(
      itemCount: _cartItems.length,
      itemBuilder: (context, index) {
        final ci = _cartItems[index];
        String name = _itemNames[ci.merchandise_item_ID ?? ''] ?? '';
        String pName = _packNames[ci.merchandise_pack_ID ?? ''] ?? '';
        if (pName.isNotEmpty) name += ' ($pName)';

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: ListTile(
            title: Text(name),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _formatPrice(ci.itemPrice),
                  style: const TextStyle(fontSize: 30, color: Colors.blue),
                ),
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
                  onPressed: () {
                    setState(() {
                      if (ci.quantity! > 1) {
                        ci.quantity = ci.quantity! - 1;
                      } else {
                        _cartItems.removeAt(index);
                      }
                    });
                  }
                ),
                Text('${ci.quantity}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline, color: Colors.green),
                  onPressed: () {
                    setState(() {
                      ci.quantity = ci.quantity! + 1;
                    });
                  }
                ),
              ],
            ),
          ),
        );
      }
    );
  }

  Widget _buildMiddleSection() {
    switch (_currentSection) {
      case 'Category':
        return _buildCategorySection();
      case 'SearchResult':
        return _buildSearchResultSection();
      case 'Cart':
        return _buildCartSection();
      default:
        return const SizedBox();
    }
  }

  Widget _buildBottomFooter() {
    int totalQty = _cartItems.fold<int>(0, (p, e) => p + (e.quantity ?? 0));
    double totalAmt = _cartItems.fold<double>(0, (p, e) => p + ((e.itemPrice ?? 0) * (e.quantity ?? 0)));

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.black12)),
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 10,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            /*
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Total Items: $totalQty',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                Text(
                  'Total Amount: ${totalAmt.toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 20, color: Colors.blue, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            */
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Text(
                      isThai ? 'รวม' : 'Total',
                      style: const TextStyle(
                        fontSize: 16,
                        color: Colors.black54,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '$totalQty',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      isThai ? 'รายการ' : 'Items',
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.black54,
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Text(
                      totalAmt.toStringAsFixed(0),
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isThai ? 'บ.' : 'THB',
                      style: const TextStyle(color: Colors.black54),
                    ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  flex: 1,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () {
                      setState(() {
                        _cartItems.clear();
                      });
                    },
                    child: Text(
                      isThai ? 'ยกเลิก' : 'Cancel',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 3,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: totalQty > 0 ? Colors.green : Colors.grey[300],
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: totalQty > 0 ? _orderMerchandise : null,
                    child: Text(
                      isThai ? 'ซื้อสินค้า' : 'Order Merchandise',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: totalQty > 0 ? Colors.white : Colors.grey[500],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_isLifeTime && _isExpired) {
      return Scaffold(
        appBar: AppBar(title: const Text('PPOS')),
        body: Center(
          child: Text(
            isThai ? 'บริการหมดอายุ กรุณาชำระค่าบริการ' : 'Service Expired Please Pay Fee',
            style: const TextStyle(fontSize: 20, color: Colors.red, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: Column(
        children: [
          _buildTopHeader(),
          Expanded(
            child: _buildMiddleSection(),
          ),
          _buildBottomFooter(),
        ],
      ),
    );
  }
}
