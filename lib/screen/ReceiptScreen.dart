import 'package:flutter/material.dart';
import 'package:isar/isar.dart';
import 'package:meorder_ppos/lib/EnvConfig.dart';
import 'package:meorder_ppos/database/IsarModels.dart';
import 'package:meorder_ppos/screen/PPosScreen.dart';
import 'package:meorder_ppos/screen/FoodMenuScreen.dart';
import 'package:meorder_ppos/screen/PaymentScreen.dart';

class ReceiptScreen extends StatefulWidget {
  final EnvConfig config;
  const ReceiptScreen({super.key, required this.config});

  @override
  State<ReceiptScreen> createState() => _ReceiptScreenState();
}

class _ReceiptScreenState extends State<ReceiptScreen> {
  late Isar isar;
  bool isLoading = true;
  String currentStatus = 'Wait4Payment';
  List<Receipt> receipts = [];
  Map<String, String> receiptPrefixMap = {}; 
  Map<String, List<DisplayOrderItem>> orderItemsMap = {};
  Set<String> expandedReceiptIds = {};

  int currentPage = 0;
  final int itemsPerPage = 10;
  bool hasNextPage = false;

  bool get isThai => widget.config.language == 'th';

  @override
  void initState() {
    super.initState();
    isar = Isar.getInstance()!;
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => isLoading = true);
    try {
      DateTime now = DateTime.now();
      String todayStr = DateTime(now.year, now.month, now.day).toIso8601String();
      
      var query = isar.receiptList.where()
          .filter()
          .statusEqualTo(currentStatus)
          .and()
          .createdAtGreaterThan(DateTime.parse(todayStr));

      if (currentStatus == 'Paid' || currentStatus == 'Cancel') {
        final totalCount = await query.count();
        hasNextPage = (currentPage + 1) * itemsPerPage < totalCount;
        
        receipts = await query.sortByCreatedAtDesc()
            .offset(currentPage * itemsPerPage)
            .limit(itemsPerPage)
            .findAll();
      } else {
        receipts = await query.sortByCreatedAtDesc().findAll();
        hasNextPage = false;
      }

      for (var receipt in receipts) {
        if (receipt.id == null) continue;

        final order = await isar.foodOrderList.where()
            .filter()
            .parentIDEqualTo(receipt.id!)
            .and()
            .parentTypeEqualTo('receipt')
            .findFirst();

        if (order != null) {
          String prefix = order.serveType == 'ServeTable' ? 'T' : 'H';
          receiptPrefixMap[receipt.id!] = '$prefix${order.number ?? ''}';

          final items = await isar.foodOrderItemList.where()
              .filter()
              .food_order_IDEqualTo(order.id)
              .findAll();

          List<DisplayOrderItem> tempDisplayItems = [];
          for (var item in items) {
             String itemName = '';
             String kitchenItemName = '';
             if (item.food_item_ID != null) {
                final foodItem = await isar.foodItemList.where().filter().idEqualTo(item.food_item_ID!).findFirst();
                if (foodItem != null) {
                   itemName = isThai ? (foodItem.thaiName ?? '') : (foodItem.englishName ?? '');
                   kitchenItemName = foodItem.kitchenName ?? itemName;
                }
             }
             String sizeName = '';
             String kitchenSizeName = '';
             if (item.food_size_ID != null && item.food_size_ID!.isNotEmpty) {
                final foodSize = await isar.foodSizeList.where().filter().idEqualTo(item.food_size_ID!).findFirst();
                if (foodSize != null) {
                   sizeName = isThai ? (foodSize.thaiName ?? '') : (foodSize.englishName ?? '');
                   kitchenSizeName = foodSize.kitchenName ?? sizeName;
                }
             }
             String choiceName = '';
             String kitchenChoiceName = '';
             if (item.choiceIDList != null && item.choiceIDList!.isNotEmpty) {
                List<String> choiceIDs = item.choiceIDList!.split(',');
                List<String> choiceNames = [];
                List<String> kitchenChoiceNames = [];
                for (var cID in choiceIDs) {
                   if (cID.trim().isNotEmpty) {
                      final choice = await isar.foodChoiceList.where().filter().idEqualTo(cID.trim()).findFirst();
                      if (choice != null) {
                         choiceNames.add(isThai ? (choice.thaiName ?? '') : (choice.englishName ?? ''));
                         kitchenChoiceNames.add(choice.kitchenName ?? (isThai ? (choice.thaiName ?? '') : (choice.englishName ?? '')));
                      }
                   }
                }
                choiceName = choiceNames.join(', ');
                kitchenChoiceName = kitchenChoiceNames.join(', ');
             }

             tempDisplayItems.add(DisplayOrderItem(
                item: item,
                itemName: itemName,
                sizeName: sizeName,
                choiceName: choiceName,
                kitchenItemName: kitchenItemName,
                kitchenSizeName: kitchenSizeName,
                kitchenChoiceName: kitchenChoiceName,
             ));
          }
          orderItemsMap[receipt.id!] = tempDisplayItems;
        } else {
          receiptPrefixMap[receipt.id!] = '';
          orderItemsMap[receipt.id!] = [];
        }
      }
    } catch (e) {
      debugPrint("Error loading receipts: $e");
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  Widget _buildStatusButton(String status, String label) {
    bool isSelected = currentStatus == status;
    return Expanded(
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: isSelected ? Colors.blue : Colors.grey[200],
          foregroundColor: isSelected ? Colors.white : Colors.black87,
        ),
        onPressed: () {
          setState(() {
            currentStatus = status;
            currentPage = 0;
            expandedReceiptIds.clear();
          });
          _loadData();
        },
        child: Text(label),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(isThai ? 'ใบเสร็จรับเงิน' : 'Receipts'),
        actions: [
          IconButton(
            icon: const Icon(Icons.home),
            onPressed: () {
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (context) => PPosScreen(config: widget.config)),
                (route) => false,
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => FoodMenuScreen(
                    config: widget.config,
                    receiptID: null,
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                _buildStatusButton('Wait4Payment', isThai ? 'รอชำระ' : 'Wait4Payment'),
                const SizedBox(width: 8),
                _buildStatusButton('Paid', isThai ? 'ชำระแล้ว' : 'Paid'),
                const SizedBox(width: 8),
                _buildStatusButton('Cancel', isThai ? 'ยกเลิก' : 'Cancel'),
              ],
            ),
          ),
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : receipts.isEmpty
                    ? Center(child: Text(isThai ? 'ไม่มีข้อมูล' : 'No Data'))
                    : ListView.builder(
                        itemCount: receipts.length,
                        itemBuilder: (context, index) {
                          final receipt = receipts[index];
                          String prefixName = receiptPrefixMap[receipt.id] ?? '';
                          bool isExpanded = expandedReceiptIds.contains(receipt.id);
                          
                          return Card(
                            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            child: Column(
                              children: [
                                ListTile(
                                  title: Text(
                                    '$prefixName ฿${receipt.totalAmount?.toStringAsFixed(2)}',
                                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (currentStatus == 'Wait4Payment')
                                        IconButton(
                                          icon: const Icon(Icons.attach_money, color: Colors.green),
                                          onPressed: () {
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (context) => PaymentScreen(
                                                  config: widget.config,
                                                  receiptID: receipt.id!,
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                      IconButton(
                                        icon: Icon(isExpanded ? Icons.expand_less : Icons.search),
                                        onPressed: () {
                                          setState(() {
                                            if (isExpanded) {
                                              expandedReceiptIds.remove(receipt.id);
                                            } else {
                                              expandedReceiptIds.add(receipt.id!);
                                            }
                                          });
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                                if (isExpanded)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.stretch,
                                      children: (orderItemsMap[receipt.id] ?? []).map((di) {
                                        String desc = '${di.item.quantity ?? 0}x ${di.itemName}';
                                        if (di.sizeName.isNotEmpty) desc += ' ${di.sizeName}';
                                        if (di.choiceName.isNotEmpty) desc += ' ${di.choiceName}';
                                        double amount = (di.item.quantity ?? 0) * (di.item.itemPrice ?? 0.0);
                                        return Padding(
                                          padding: const EdgeInsets.only(bottom: 4.0),
                                          child: Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Expanded(child: Text(desc, style: const TextStyle(fontSize: 14))),
                                              Text(amount.toStringAsFixed(2), style: const TextStyle(fontSize: 14)),
                                            ],
                                          ),
                                        );
                                      }).toList(),
                                    ),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
          ),
          if (!isLoading && (currentStatus == 'Paid' || currentStatus == 'Cancel') && (currentPage > 0 || hasNextPage))
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton(
                    onPressed: currentPage > 0
                        ? () {
                            setState(() {
                              currentPage--;
                            });
                            _loadData();
                          }
                        : null,
                    child: const Icon(Icons.arrow_back),
                  ),
                  const SizedBox(width: 16),
                  Text('${isThai ? 'หน้า' : 'Page'} ${currentPage + 1}'),
                  const SizedBox(width: 16),
                  ElevatedButton(
                    onPressed: hasNextPage
                        ? () {
                            setState(() {
                              currentPage++;
                            });
                            _loadData();
                          }
                        : null,
                    child: const Icon(Icons.arrow_forward),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
