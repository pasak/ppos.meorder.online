import 'dart:io';
import 'package:flutter/material.dart';
import 'package:isar/isar.dart';
import 'package:meorder_ppos/database/IsarModels.dart';
import 'package:meorder_ppos/screen/PaymentScreen.dart';
import 'package:meorder_ppos/lib/EnvConfig.dart';
import 'package:uuid/uuid.dart';

class FoodItemViewModel {
  final FoodItem data;
  List<FoodSizeViewModel> sizes = [];
  List<FoodOptionViewModel> options = [];
  List<FoodChoiceViewModel> standaloneChoices = [];
  
  int quantity = 0;
  double itemPrice = 0.0;
  String? selectedSizeID;

  FoodItemViewModel({required this.data}) {
    itemPrice = data.price ?? 0.0;
  }
}

class FoodSizeViewModel {
  final FoodSize data;
  final FoodItemSize itemSizeData;
  bool isSelected = false;

  FoodSizeViewModel({required this.data, required this.itemSizeData});
}

class FoodOptionViewModel {
  final FoodOption data;
  List<FoodChoiceViewModel> choices = [];

  FoodOptionViewModel({required this.data});
}

class FoodChoiceViewModel {
  final FoodChoice data;
  List<FoodChoiceSize> choiceSizes = [];
  bool isSelected = false;
  double choicePrice = 0.0;

  FoodChoiceViewModel({required this.data});
}

class FoodMenuScreen extends StatefulWidget {
  final EnvConfig config;
  final String? shop_open_table_ID;
  final String? receiptID;
  const FoodMenuScreen({super.key, required this.config, this.shop_open_table_ID, this.receiptID});

  @override
  State<FoodMenuScreen> createState() => _FoodMenuScreenState();
}

class _FoodMenuScreenState extends State<FoodMenuScreen> {
  late Isar isar;
  String shop_customer_ID = '0';
  String serveType = 'ServeTable';
  String currentCategoryID = '0';
  List<FoodCategory> categoryList = [];
  List<FoodItemViewModel> itemList = [];
  
  bool isDebug = false;
  String _debugText = '';
  bool isLoading = true;
  int totalQuantity = 0;
  double totalAmount = 0.0;

  bool get isThai => widget.config.language == 'th';

  @override
  void initState() {
    super.initState();
    isar = Isar.getInstance()!;
    if (widget.config.service_module_ID == 'FOC') {
      serveType = 'TakeAway';
    }
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => isLoading = true);
    try {
      categoryList = await isar.foodCategoryList.where().findAll();
      categoryList.sort((a, b) => (a.seq ?? 0).compareTo(b.seq ?? 0));
      await _loadItemsForCategory();
    } catch (e) {
      print("Error loading data from Isar: $e");
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  Future<void> _loadItemsForCategory() async {
    setState(() => isLoading = true);
    try {
      List<FoodItem> rawItems;
      if (currentCategoryID == '0') {
        rawItems = await isar.foodItemList.where().filter().isRecommendEqualTo('Y').findAll();
      } else {
        rawItems = await isar.foodItemList.where().filter().food_category_IDEqualTo(currentCategoryID).findAll();
      }
      
      rawItems.sort((a, b) => (a.seq ?? 0).compareTo(b.seq ?? 0));

      List<FoodItemViewModel> newItems = [];
      
      for (var vm in itemList) {
        if (vm.quantity > 0) newItems.add(vm);
      }

      for (var item in rawItems) {
        bool isServeMatch = (serveType == "ServeTable" && item.isServeTable == "Y");
        bool isTakeAwayMatch = (serveType == "TakeAway" && item.isTakeAway == "Y");

        if (!isServeMatch && !isTakeAwayMatch) continue;
        if (newItems.any((i) => i.data.id == item.id)) continue; 

        var vm = FoodItemViewModel(data: item);
        
        var itemSizes = await isar.foodItemSizeList.where().filter().food_item_IDEqualTo(item.id).findAll();
        for (var isz in itemSizes) {
          var sizeData = await isar.foodSizeList.where().filter().idEqualTo(isz.food_size_ID).findFirst();
          if (sizeData != null) {
            vm.sizes.add(FoodSizeViewModel(data: sizeData, itemSizeData: isz));
          }
        }
        if (vm.sizes.isNotEmpty) {
           vm.sizes[0].isSelected = true;
        }

        var options = await isar.foodOptionList.where().filter().food_item_IDEqualTo(item.id).findAll();
        options.sort((a, b) => (a.seq ?? 0).compareTo(b.seq ?? 0));
        for (var opt in options) {
          var ovm = FoodOptionViewModel(data: opt);
          var choices = await isar.foodChoiceList.where().filter().parentIDEqualTo(opt.id).findAll();
          choices.sort((a, b) => (a.seq ?? 0).compareTo(b.seq ?? 0));
          for (var c in choices) {
             var cvm = FoodChoiceViewModel(data: c);
             cvm.choiceSizes = await isar.foodChoiceSizeList.where().filter().food_choice_IDEqualTo(c.id).findAll();
             ovm.choices.add(cvm);
          }
          vm.options.add(ovm);
        }

        var sChoices = await isar.foodChoiceList.where().filter().parentIDEqualTo(item.id).findAll();
        sChoices.sort((a, b) => (a.seq ?? 0).compareTo(b.seq ?? 0));
        for (var c in sChoices) {
           var cvm = FoodChoiceViewModel(data: c);
           cvm.choiceSizes = await isar.foodChoiceSizeList.where().filter().food_choice_IDEqualTo(c.id).findAll();
           vm.standaloneChoices.add(cvm);
        }

        newItems.add(vm);
      }
      
      itemList = newItems;
      _calculateTotal();

    } catch (e) {
      print("Error loading items: $e");
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  void _calculateTotal() {
    int qty = 0;
    double amt = 0.0;

    for (var vm in itemList) {
      double currentPrice = vm.data.price ?? 0.0;
      
      var selectedSize = vm.sizes.where((s) => s.isSelected).firstOrNull;
      if (selectedSize != null) {
        currentPrice = selectedSize.itemSizeData.price ?? 0.0;
        vm.selectedSizeID = selectedSize.data.id;
      } else {
        vm.selectedSizeID = null;
      }

      for (var opt in vm.options) {
         for (var choice in opt.choices) {
            if (choice.isSelected) {
               double cPrice = choice.data.price ?? 0.0;
               if (vm.selectedSizeID != null) {
                  var sizeMatch = choice.choiceSizes.where((cs) => cs.food_size_ID == vm.selectedSizeID).firstOrNull;
                  if (sizeMatch != null) cPrice = sizeMatch.price ?? 0.0;
               }
               choice.choicePrice = cPrice;
               currentPrice += cPrice;
            }
         }
      }

      for (var choice in vm.standaloneChoices) {
         if (choice.isSelected) {
            double cPrice = choice.data.price ?? 0.0;
            if (vm.selectedSizeID != null) {
               var sizeMatch = choice.choiceSizes.where((cs) => cs.food_size_ID == vm.selectedSizeID).firstOrNull;
               if (sizeMatch != null) cPrice = sizeMatch.price ?? 0.0;
            }
            choice.choicePrice = cPrice;
            currentPrice += cPrice;
         }
      }

      vm.itemPrice = currentPrice;
      qty += vm.quantity;
      amt += (vm.itemPrice * vm.quantity);
    }

    setState(() {
      totalQuantity = qty;
      totalAmount = amt;
    });
  }

  void _handleSelectSize(String itemID, String sizeID) {
    var item = itemList.where((i) => i.data.id == itemID).firstOrNull;
    if (item != null) {
      for (var s in item.sizes) {
         s.isSelected = false;
      }
      var target = item.sizes.where((s) => s.data.id == sizeID).firstOrNull;
      if (target != null) target.isSelected = true;
      _calculateTotal();
    }
  }

  void _handleSelectOptionChoice(String itemID, String optionID, String choiceID) {
    var item = itemList.where((i) => i.data.id == itemID).firstOrNull;
    if (item != null) {
      var opt = item.options.where((o) => o.data.id == optionID).firstOrNull;
      if (opt != null) {
         for (var c in opt.choices) {
            c.isSelected = false;
         }
         var target = opt.choices.where((c) => c.data.id == choiceID).firstOrNull;
         if (target != null) target.isSelected = true;
         _calculateTotal();
      }
    }
  }

  void _handleSelectStandaloneChoice(String itemID, String choiceID) {
    var item = itemList.where((i) => i.data.id == itemID).firstOrNull;
    if (item != null) {
      for (var c in item.standaloneChoices) {
         c.isSelected = false;
      }
      var target = item.standaloneChoices.where((c) => c.data.id == choiceID).firstOrNull;
      if (target != null) target.isSelected = true;
      _calculateTotal();
    }
  }

  void _handleQuantity(String itemID, int delta) {
    var item = itemList.where((i) => i.data.id == itemID).firstOrNull;
    if (item != null) {
       for (var opt in item.options) {
          bool hasSelected = opt.choices.any((c) => c.isSelected);
          if (!hasSelected && opt.choices.isNotEmpty) {
             opt.choices.first.isSelected = true;
          }
       }
       int newQty = item.quantity + delta;
       item.quantity = newQty < 0 ? 0 : newQty;
       _calculateTotal();
    }
  }

  Future<int> _getOrderNumber() async {
    int maxNumber = 0;
    String todayPrefix = DateTime.now().toIso8601String().substring(0, 10);
    
    final ordersToday = await isar.foodOrderList.where()
        .filter()
        .createdAtStartsWith(todayPrefix)
        .findAll();

    int currentBranchId = int.tryParse(widget.config.shop_branch_ID ?? '0') ?? 0;

    for (var fo in ordersToday) {
      if (fo.parentType == 'receipt' && fo.parentID != null) {
        final receipt = await isar.receiptList.where().filter().idEqualTo(fo.parentID!).findFirst();
        if (receipt != null && receipt.shop_branch_ID == currentBranchId) {
           if (fo.number != null && fo.number! > maxNumber) {
             maxNumber = fo.number!;
           }
        }
      } else if (fo.parentType == 'shop_open_table_ID') {
         if (fo.number != null && fo.number! > maxNumber) {
           maxNumber = fo.number!;
         }
      }
    }
    return maxNumber + 1;
  }

  Future<void> _orderFood() async {
    if (totalQuantity <= 0) return;

    setState(() {
      isLoading = true;
    });

    try {
      final uuid = const Uuid();
      final now = DateTime.now();

      List<Map<String, dynamic>> debugItems = [];
      String? receiptID;
      
      await isar.writeTxn(() async {
        String parentType;
        String? parentID;

        receiptID = widget.receiptID;
        
        Receipt? existingReceipt;
        if (receiptID != null) {
          existingReceipt = await isar.receiptList.where().filter().idEqualTo(receiptID).findFirst();
        }

        if (existingReceipt != null) {
            existingReceipt.sumAmount = (existingReceipt.sumAmount ?? 0.0) + totalAmount;
            existingReceipt.totalAmount = (existingReceipt.totalAmount ?? 0.0) + totalAmount;
            existingReceipt.lastUpdated = now.toIso8601String();
            existingReceipt.isDirty = true;
            await isar.receiptList.put(existingReceipt);
            
            parentType = 'receipt';
            parentID = receiptID;
        } else if (widget.shop_open_table_ID == null || widget.shop_open_table_ID == '0') {
          String code = '';
          int seqNumber = 0;
          final docCodeList = await isar.documentCodeList.where().findAll();
          
          final prefix = docCodeList.where((e) => e.name == 'PREFIX').firstOrNull;
          final year = docCodeList.where((e) => e.name == 'YEAR').firstOrNull;
          final month = docCodeList.where((e) => e.name == 'MONTH').firstOrNull;
          final numberCode = docCodeList.where((e) => e.name == 'NUMBER').firstOrNull;

          if (prefix != null && prefix.value != null) {
            code += prefix.value! + (prefix.seperator ?? '');
          }
          
          if (year != null && year.value != null && year.value!.isNotEmpty) {
            int y = now.year;
            if (year.value!.startsWith('BE')) y += 543;
            if (year.value!.contains('2')) y = y % 100;
            code += '$y${year.seperator ?? ''}';
          }
          
          if (month != null) {
             String m = now.month.toString().padLeft(2, '0');
             code += '$m${month.seperator ?? ''}';
          }

          String codePrefix = code;

          int digit = 4;
          if (numberCode != null) {
            digit = int.tryParse(numberCode.seperator ?? '4') ?? 4;
            if (numberCode.value == 'SEQUENCE') {
              final existingCount = await isar.receiptList.where().filter().codeStartsWith(codePrefix).count();
              seqNumber = existingCount + 1;
              code += seqNumber.toString().padLeft(digit, '0');
            } else {
               seqNumber = now.millisecondsSinceEpoch % 10000;
               code += seqNumber.toString().padLeft(digit, '0');
            }
          } else {
            seqNumber = now.millisecondsSinceEpoch % 10000;
            code += seqNumber.toString().padLeft(digit, '0');
          }

          receiptID = uuid.v4();
          final receipt = Receipt()
            ..id = receiptID
            ..shop_branch_ID = int.tryParse(widget.config.shop_branch_ID ?? '0')
            ..shop_user_ID = int.tryParse(widget.config.UserID ?? '0')
            ..shop_customer_ID = shop_customer_ID
            ..code = code
            ..createdAt = now
            ..sumAmount = totalAmount
            ..totalAmount = totalAmount
            ..status = 'Create'
            ..lastUpdated = now.toIso8601String()
            ..isDirty = true;
          
          await isar.receiptList.put(receipt);
          
          parentType = 'receipt';
          parentID = receiptID;

          if (isDebug) {
            debugItems.add({
              'Receipt': {
                'id': receipt.id,
                'code': receipt.code,
                'totalAmount': receipt.totalAmount
              }
            });
          }
        } else {
          parentType = 'shop_open_table_ID';
          parentID = widget.shop_open_table_ID;
        }

        String foodOrderID = '';
        FoodOrder? existingOrder;

        if (receiptID != null) {
          existingOrder = await isar.foodOrderList.where().filter().parentIDEqualTo(receiptID).findFirst();
        } else if (widget.shop_open_table_ID != null) {
          existingOrder = await isar.foodOrderList.where().filter().parentIDEqualTo(widget.shop_open_table_ID).findFirst();
        }

        if (existingOrder != null) {
           foodOrderID = existingOrder.id!;
           existingOrder.orderAmount = (existingOrder.orderAmount ?? 0.0) + totalAmount;
           existingOrder.lastUpdated = now.toIso8601String();
           existingOrder.isDirty = true;
           await isar.foodOrderList.put(existingOrder);
        } else {
           foodOrderID = uuid.v4();
           int orderNum = await _getOrderNumber();

           final foodOrder = FoodOrder()
             ..id = foodOrderID
             ..parentType = parentType
             ..parentID = parentID
             ..number = orderNum
             ..kitchen_ID = 0
             ..createdAt = now.toIso8601String()
             ..serveType = serveType
             ..orderAmount = totalAmount
             ..status = 'OrderFood'
             ..lastUpdated = now.toIso8601String()
             ..isDirty = true;

           await isar.foodOrderList.put(foodOrder);

           if (isDebug) {
             debugItems.add({
               'FoodOrder': {
                 'id': foodOrder.id,
                 'parentType': foodOrder.parentType,
                 'parentID': foodOrder.parentID,
                 'number': foodOrder.number,
                 'kitchen_ID': foodOrder.kitchen_ID,
                 'orderAmount': foodOrder.orderAmount
               }
             });
           }
        }

        for (var vm in itemList) {
          if (vm.quantity > 0) {
            var item = FoodOrderItem()
              ..id = uuid.v4()
              ..food_order_ID = foodOrderID
              ..food_item_ID = vm.data.id
              ..food_size_ID = vm.selectedSizeID
              ..itemPrice = vm.itemPrice
              ..quantity = vm.quantity
              ..choiceIDList = ''
              ..description = vm.data.kitchenName
              ..lastUpdated = now.toIso8601String()
              ..isDirty = true;
            
            List<String> choiceIDs = [];
            for (var opt in vm.options) {
              for (var choice in opt.choices) {
                if (choice.isSelected && choice.data.id != null) {
                  choiceIDs.add(choice.data.id!);
                }
              }
            }
            for (var choice in vm.standaloneChoices) {
              if (choice.isSelected && choice.data.id != null) {
                choiceIDs.add(choice.data.id!);
              }
            }
            item.choiceIDList = choiceIDs.join(',');

            await isar.foodOrderItemList.put(item);

            if (isDebug) {
              debugItems.add({
                'FoodOrderItem': {
                  'id': item.id,
                  'food_item_ID': item.food_item_ID,
                  'quantity': item.quantity,
                  'itemPrice': item.itemPrice,
                  'choiceIDList': item.choiceIDList
                }
              });
            }
          }
        }
      });
      
      if (mounted) {
         if (isDebug) {
            setState(() {
              _debugText = debugItems.map((e) => e.toString()).join('\n');
            });
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Debug: Order Generated')));
         } else {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(isThai ? 'สั่งอาหารสำเร็จ' : 'Order Placed Successfully')));
            if (receiptID != null) {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) => PaymentScreen(
                    config: widget.config,
                    receiptID: receiptID!,
                  ),
                ),
              );
            }
         }
      }
    } catch (e) {
      print("Error creating order: $e");
      if (mounted) {
         ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  String _getDisplayChoicePrice(FoodChoiceViewModel choice) {
    if (choice.choicePrice == 0.0) return "";
    return " +${choice.choicePrice.toStringAsFixed(0)}";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Menu'),
        actions: [
          if (widget.config.service_module_ID != 'FOC')
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 10.0),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    _buildServeTypeButton('ServeTable', isThai ? 'ทานที่ร้าน' : 'Serve Table'),
                    _buildServeTypeButton('TakeAway', isThai ? 'สั่งกลับบ้าน' : 'Take Away'),
                  ],
                ),
              ),
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(50),
          child: Container(
            height: 50,
            color: Colors.grey[50],
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              children: [
                _buildCategoryButton('0', isThai ? 'แนะนำ' : 'Recommend'),
                ...categoryList.map((cat) => _buildCategoryButton(
                  cat.id ?? '', 
                  isThai ? (cat.thaiName ?? '') : (cat.englishName ?? '')
                )),
              ],
            ),
          ),
        ),
      ),
      body: isLoading 
        ? const Center(child: CircularProgressIndicator())
        : ListView.builder(
            padding: const EdgeInsets.only(bottom: 150),
            itemCount: itemList.length + (isDebug && _debugText.isNotEmpty ? 1 : 0),
            itemBuilder: (context, index) {
              if (index == itemList.length) {
                return Container(
                  margin: const EdgeInsets.all(12),
                  padding: const EdgeInsets.all(12),
                  color: Colors.black87,
                  child: Text(_debugText, style: const TextStyle(color: Colors.greenAccent, fontFamily: 'monospace', fontSize: 12)),
                );
              }

              var item = itemList[index];
              bool hasPicture = item.data.localPicture != null && item.data.localPicture!.isNotEmpty;
              File? imageFile = hasPicture ? File(item.data.localPicture!) : null;
              bool fileExists = imageFile != null && imageFile.existsSync();

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                elevation: 1,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (fileExists)
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.file(
                                imageFile!,
                                height: 180,
                                width: double.infinity,
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                        ),
                      Text(
                        isThai ? (item.data.thaiName ?? '') : (item.data.englishName ?? ''),
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      if (item.sizes.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(isThai ? 'ขนาด:' : 'Size:', style: const TextStyle(fontSize: 14, color: Colors.black54)),
                            ),
                            ...item.sizes.map((s) => ChoiceChip(
                              label: Text('${isThai ? s.data.thaiName : s.data.englishName} ${s.itemSizeData.price?.toStringAsFixed(0) ?? ''}'),
                              selected: s.isSelected,
                              showCheckmark: false,
                              onSelected: (_) => _handleSelectSize(item.data.id!, s.data.id!),
                              selectedColor: Colors.blue[600],
                              labelStyle: TextStyle(color: s.isSelected ? Colors.white : Colors.black87),
                            ))
                          ],
                        ),
                      ],
                      for (var opt in item.options) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text('${isThai ? opt.data.thaiName : opt.data.englishName}:', style: const TextStyle(fontSize: 14, color: Colors.black54)),
                            ),
                            ...opt.choices.map((c) => ChoiceChip(
                              label: Text('${isThai ? c.data.thaiName : c.data.englishName}${_getDisplayChoicePrice(c)}'),
                              selected: c.isSelected,
                              showCheckmark: false,
                              onSelected: (_) => _handleSelectOptionChoice(item.data.id!, opt.data.id!, c.data.id!),
                              selectedColor: Colors.blue[600],
                              labelStyle: TextStyle(color: c.isSelected ? Colors.white : Colors.black87),
                            ))
                          ],
                        ),
                      ],
                      if (item.standaloneChoices.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(isThai ? 'เพิ่ม:' : 'Add:', style: const TextStyle(fontSize: 14, color: Colors.black54)),
                            ),
                            ...item.standaloneChoices.map((c) => ChoiceChip(
                              label: Text('${isThai ? c.data.thaiName : c.data.englishName}${_getDisplayChoicePrice(c)}'),
                              selected: c.isSelected,
                              showCheckmark: false,
                              onSelected: (_) => _handleSelectStandaloneChoice(item.data.id!, c.data.id!),
                              selectedColor: Colors.blue[600],
                              labelStyle: TextStyle(color: c.isSelected ? Colors.white : Colors.black87),
                            ))
                          ],
                        ),
                      ],
                      const Divider(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Text(isThai ? 'ราคา ' : 'Price ', style: const TextStyle(color: Colors.black54)),
                              Text('${item.itemPrice.toStringAsFixed(0)}', style: const TextStyle(color: Colors.red, fontSize: 24, fontWeight: FontWeight.bold)),
                              Text(isThai ? ' บ.' : ' THB', style: const TextStyle(color: Colors.black54)),
                            ],
                          ),
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.grey[100],
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              children: [
                                if (item.quantity > 0)
                                  Padding(
                                    padding: const EdgeInsets.only(left: 12, right: 4),
                                    child: Row(
                                      children: [
                                        Text(isThai ? 'จำนวน ' : 'Qty ', style: const TextStyle(color: Colors.black54, fontSize: 12)),
                                        Text('${item.quantity}', style: const TextStyle(color: Colors.blue, fontSize: 20, fontWeight: FontWeight.bold)),
                                      ],
                                    ),
                                  ),
                                IconButton(
                                  icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
                                  onPressed: item.quantity > 0 ? () => _handleQuantity(item.data.id!, -1) : null,
                                ),
                                IconButton(
                                  icon: const Icon(Icons.add_circle_outline, color: Colors.green),
                                  onPressed: () => _handleQuantity(item.data.id!, 1),
                                ),
                              ],
                            ),
                          )
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
      bottomSheet: Container(
        padding: const EdgeInsets.all(16),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Colors.black12)),
          boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, -2))],
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Text(isThai ? 'รวม' : 'Total', style: const TextStyle(fontSize: 16, color: Colors.black54)),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(4)),
                        child: Text('$totalQuantity', style: const TextStyle(fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(width: 8),
                      Text(isThai ? 'รายการ' : 'Items', style: const TextStyle(fontSize: 14, color: Colors.black54)),
                    ],
                  ),
                  Row(
                    children: [
                      Text(totalAmount.toStringAsFixed(0), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.blue)),
                      const SizedBox(width: 4),
                      Text(isThai ? 'บ.' : 'THB', style: const TextStyle(color: Colors.black54)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: totalQuantity > 0 ? Colors.green : Colors.grey[300],
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: totalQuantity > 0 ? _orderFood : null,
                  child: Text(
                    isThai ? 'สั่งอาหาร' : 'Order Food', 
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: totalQuantity > 0 ? Colors.white : Colors.grey[500]),
                  ),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildServeTypeButton(String type, String label) {
    bool isSelected = serveType == type;
    return GestureDetector(
      onTap: () {
        setState(() {
          serveType = type;
        });
        _loadItemsForCategory();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          boxShadow: isSelected ? [const BoxShadow(color: Colors.black12, blurRadius: 2, offset: Offset(0, 1))] : [],
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? Colors.blue[600] : Colors.black54,
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryButton(String id, String label) {
    bool isSelected = currentCategoryID == id;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: isSelected,
        showCheckmark: false,
        onSelected: (selected) {
          if (selected) {
            setState(() {
              currentCategoryID = id;
            });
            _loadItemsForCategory();
          }
        },
        selectedColor: Colors.blue[600],
        labelStyle: TextStyle(
          color: isSelected ? Colors.white : Colors.black87,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }
}
