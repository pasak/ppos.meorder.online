import 'package:flutter/material.dart';
import 'package:isar/isar.dart';
import 'package:meorder_ppos/lib/EnvConfig.dart';
import 'package:meorder_ppos/database/IsarModels.dart';
import 'package:meorder_ppos/screen/FoodMenuScreen.dart';
import 'package:meorder_ppos/screen/ReceiptScreen.dart';
import 'package:meorder_ppos/screen/PPosScreen.dart';
import 'package:meorder_ppos/services/PrintService.dart';
import 'package:meorder_ppos/model/DisplayOrderItem.dart';
import 'package:meorder_ppos/services/SyncService.dart';
import 'package:meorder_ppos/services/RolePermissionServices.dart';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:sunmi_printer_plus/sunmi_printer_plus.dart';
import 'package:flutter_usb_printer/flutter_usb_printer.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';


class PaymentScreen extends StatefulWidget {
  final EnvConfig config;
  final String receiptID;

  const PaymentScreen({
    super.key,
    required this.config,
    required this.receiptID,
  });

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  late Isar isar;
  bool isLoading = true;

  Map<String, String?>? foDiscountFood;
  Map<String, String?>? foDiscountReceipt;
  Map<String, String?>? foReceiveCash;
  Map<String, String?>? foCancelFoodOrder;

  Receipt? receipt;
  List<DisplayOrderItem> displayItems = [];
  bool hasMT = false;
  bool hasPP = false;
  bool hasOnline = false;
  List<PaymentValue> mtValues = [];
  List<PaymentValue> ppValues = [];
  String? _ppQrBase64;
  bool _isGeneratingPP = false;

  String selectedMethod = 'Cash';
  String _debugText = '';
  bool isDebug = false;
  double receiveAmount = 0.0;
  double changeAmount = 0.0;
  double tipAmount = 0.0;

  final TextEditingController receiveAmountController = TextEditingController(
    text: '0',
  );
  final TextEditingController changeAmountController = TextEditingController(
    text: '0',
  );
  final TextEditingController tipAmountController = TextEditingController(
    text: '0',
  );
  final TextEditingController receiptDiscountPercentCtrl = TextEditingController(text: '');
  final TextEditingController receiptDiscountAmountCtrl = TextEditingController(text: '');

  bool get isThai => widget.config.language == 'th';

  @override
  void initState() {
    super.initState();
    isar = Isar.getInstance()!;
    _loadData();
  }

  @override
  void dispose() {
    receiveAmountController.dispose();
    changeAmountController.dispose();
    tipAmountController.dispose();
    receiptDiscountPercentCtrl.dispose();
    receiptDiscountAmountCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => isLoading = true);
    try {
      final roleID = widget.config.UserRole;
      if (roleID != null) {
        foDiscountFood = await RolePermissionServices.getRoleTransactionPermissionList(roleID, 'FO_DISCOUNT_FOOD');
        foDiscountReceipt = await RolePermissionServices.getRoleTransactionPermissionList(roleID, 'FO_DISCOUNT_RECEIPT');
        foReceiveCash = await RolePermissionServices.getRoleTransactionPermissionList(roleID, 'FO_RECEIVE_CASH');
        foCancelFoodOrder = await RolePermissionServices.getRoleTransactionPermissionList(roleID, 'FO_CANCEL_FOOD_ORDER');
      }

      receipt = await isar.receiptList
          .where()
          .filter()
          .idEqualTo(widget.receiptID)
          .findFirst();

      if (receipt != null) {
        double currentPercent = (receipt!.discountPercent ?? 0).toDouble();
        double currentAmount = receipt!.discountAmount ?? 0.0;
        receiptDiscountPercentCtrl.text = currentPercent > 0 ? currentPercent.toStringAsFixed(0) : '';
        receiptDiscountAmountCtrl.text = currentAmount > 0 ? currentAmount.toStringAsFixed(2) : '';
        final foodOrders = await isar.foodOrderList
            .where()
            .filter()
            .parentIDEqualTo(receipt!.id)
            .and()
            .parentTypeEqualTo('receipt')
            .findAll();

        List<DisplayOrderItem> tempDisplayItems = [];

        for (var order in foodOrders) {
          final items = await isar.foodOrderItemList
              .where()
              .filter()
              .food_order_IDEqualTo(order.id)
              .findAll();

          for (var item in items) {
            String itemName = '';
            String kitchenItemName = '';
            if (item.food_item_ID != null) {
              final foodItem = await isar.foodItemList
                  .where()
                  .filter()
                  .idEqualTo(item.food_item_ID!)
                  .findFirst();
              if (foodItem != null) {
                itemName = isThai
                    ? (foodItem.thaiName ?? '')
                    : (foodItem.englishName ?? '');
                kitchenItemName = foodItem.kitchenName ?? itemName;
              }
            }

            String sizeName = '';
            String kitchenSizeName = '';
            if (item.food_size_ID != null && item.food_size_ID!.isNotEmpty) {
              final foodSize = await isar.foodSizeList
                  .where()
                  .filter()
                  .idEqualTo(item.food_size_ID!)
                  .findFirst();
              if (foodSize != null) {
                sizeName = isThai
                    ? (foodSize.thaiName ?? '')
                    : (foodSize.englishName ?? '');
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
                  final choice = await isar.foodChoiceList
                      .where()
                      .filter()
                      .idEqualTo(cID.trim())
                      .findFirst();
                  if (choice != null) {
                    choiceNames.add(
                      isThai
                          ? (choice.thaiName ?? '')
                          : (choice.englishName ?? ''),
                    );
                    kitchenChoiceNames.add(
                      choice.kitchenName ??
                          (isThai
                              ? (choice.thaiName ?? '')
                              : (choice.englishName ?? '')),
                    );
                  }
                }
              }
              choiceName = choiceNames.join(', ');
              kitchenChoiceName = kitchenChoiceNames.join(', ');
            }

            tempDisplayItems.add(
              DisplayOrderItem(
                item: item,
                itemName: itemName,
                sizeName: sizeName,
                choiceName: choiceName,
                kitchenItemName: kitchenItemName,
                kitchenSizeName: kitchenSizeName,
                kitchenChoiceName: kitchenChoiceName,
              ),
            );
          }
        }

        displayItems = tempDisplayItems;

        final mtPayment = await isar.paymentList
            .where()
            .filter()
            .payment_channel_IDEqualTo('MT')
            .isActiveEqualTo('Y')
            .findFirst();
        if (mtPayment != null) {
          hasMT = true;
          mtValues = await isar.paymentValueList
              .where()
              .filter()
              .payment_IDEqualTo(mtPayment.id!)
              .findAll();
        }

        final ppPayment = await isar.paymentList
            .where()
            .filter()
            .payment_channel_IDEqualTo('PP')
            .isActiveEqualTo('Y')
            .findFirst();
        if (ppPayment != null) {
          hasPP = true;
          ppValues = await isar.paymentValueList
              .where()
              .filter()
              .payment_IDEqualTo(ppPayment.id!)
              .findAll();
        }

        final onlinePayment = await isar.paymentList
            .where()
            .filter()
            .payment_channel_IDEqualTo('ONLINE')
            .isActiveEqualTo('Y')
            .findFirst();
        if (onlinePayment != null) {
          hasOnline = true;
        }
        
        bool isCashEnabled = foReceiveCash != null && foReceiveCash!['PermissionLevel'] == 'Full';
        if (!isCashEnabled && selectedMethod == 'Cash') {
          if (hasMT) {
            selectedMethod = 'Transfer';
          } else if (hasPP) {
            selectedMethod = 'PromptPay';
          } else if (hasOnline) {
            selectedMethod = 'Online';
          }
        }
      }
    } catch (e) {
      debugPrint("Error loading PaymentScreen data: $e");
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }


  void _handleAmount(String _) {
    double rAmount = double.tryParse(receiveAmountController.text) ?? 0.0;
    double tAmount = double.tryParse(tipAmountController.text) ?? 0.0;
    double total = receipt?.totalAmount ?? 0.0;

    double change = rAmount - total - tAmount;

    setState(() {
      receiveAmount = rAmount;
      tipAmount = tAmount;
      changeAmount = change;
      changeAmountController.text = change.toStringAsFixed(2);
    });
  }

  void _change2Tip() {
    setState(() {
      tipAmount += changeAmount;
      changeAmount = 0.0;
      tipAmountController.text = tipAmount.toStringAsFixed(2);
      changeAmountController.text = changeAmount.toStringAsFixed(2);
    });
  }

  void _addAmount(double amount) {
    setState(() {
      receiveAmount += amount;
      receiveAmountController.text = receiveAmount.toStringAsFixed(0);
    });
    _handleAmount('');
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (didPop) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => FoodMenuScreen(
              config: widget.config,
              receiptID: widget.receiptID,
            ),
          ),
        );
      },
      child: Scaffold(
        backgroundColor: Colors.grey[50],
        appBar: AppBar(
          title: Text(isThai ? 'ชำระเงิน' : 'Payment'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) => FoodMenuScreen(
                    config: widget.config,
                    receiptID: widget.receiptID,
                  ),
                ),
              );
            },
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.list),
              onPressed: () {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ReceiptScreen(config: widget.config),
                  ),
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: () {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (context) =>
                        FoodMenuScreen(config: widget.config, receiptID: null),
                  ),
                );
              },
            ),
          ],
        ),
        body: isLoading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildSection1(),
                      const SizedBox(height: 24),
                      _buildSection2(),
                      const SizedBox(height: 24),
                      if (selectedMethod == 'Cash') _buildSection3(),
                      if (selectedMethod == 'Transfer') _buildMTSection(),
                      if (selectedMethod == 'PromptPay') _buildPPSection(),
                      if (_debugText.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16.0),
                          child: Text(
                            _debugText,
                            style: const TextStyle(
                              color: Colors.red,
                              fontSize: 14,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildSection1() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              isThai ? 'รายละเอียดสินค้า' : 'Order Details',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ...displayItems.map((di) {
              String desc = '${di.item.quantity ?? 0}x ${di.itemName}';
              if (di.sizeName.isNotEmpty) desc += ' ${di.sizeName}';
              if (di.choiceName.isNotEmpty) desc += ' ${di.choiceName}';

              double amount =
                  (di.item.quantity ?? 0) * (di.item.itemPrice ?? 0.0);
              double itemAmount = amount - (di.item.discountAmount ?? 0.0);

              return Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(desc, style: const TextStyle(fontSize: 16)),
                          if ((di.item.discountAmount ?? 0.0) > 0.0)
                            Text(
                              '-${di.item.discountAmount!.toStringAsFixed(2)}',
                              style: const TextStyle(fontSize: 14, color: Colors.red),
                            ),
                        ],
                      ),
                    ),
                    Expanded(
                      flex: 1,
                      child: Text(
                        itemAmount.toStringAsFixed(2),
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontSize: 16),
                      ),
                    ),
                    if (foDiscountFood != null)
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () => _showDiscountItemDialog(di, amount),
                      ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 16),
            const Divider(thickness: 1, color: Colors.black26),
            const SizedBox(height: 16),
            Text(
              isThai ? 'รายละเอียดการชำระเงิน' : 'Payment Details',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            if (foDiscountReceipt != null || (receipt?.sumAmount ?? 0.0) != (receipt?.totalAmount ?? 0.0)) ...[
              _buildAmountRow(
                isThai ? 'ยอดรวม' : 'Subtotal',
                receipt?.sumAmount ?? 0.0,
                isBold: false,
              ),
              const SizedBox(height: 8),
              if (foDiscountReceipt != null)
                _buildReceiptDiscountRow()
              else
                _buildAmountRow(
                  isThai ? 'ส่วนลด' : 'Discount',
                  receipt?.discountAmount ?? 0.0,
                  isBold: false,
                ),
              const SizedBox(height: 8),
            ],
            _buildAmountRow(
              isThai ? 'ยอดรวมทั้งหมด' : 'Total Amount',
              receipt?.totalAmount ?? 0.0,
              isBold: true,
              fontSize: 20,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAmountRow(
    String label,
    double amount, {
    bool isBold = false,
    double fontSize = 16,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        Text(
          amount.toStringAsFixed(2),
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ],
    );
  }

  Widget _buildSection2() {
    bool isCashEnabled = foReceiveCash != null && foReceiveCash!['PermissionLevel'] == 'Full';

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: _buildMethodButton(
                    'Cash',
                    isThai ? 'เงินสด' : 'Cash',
                    isEnabled: isCashEnabled,
                  ),
                ),
                if (hasMT) ...[
                  const SizedBox(width: 4),
                  Expanded(
                    child: _buildMethodButton(
                      'Transfer',
                      isThai ? 'โอน' : 'Transfer',
                      isEnabled: true,
                    ),
                  ),
                ],
                if (hasPP) ...[
                  const SizedBox(width: 4),
                  Expanded(
                    child: _buildMethodButton(
                      'PromptPay',
                      isThai ? 'พร้อมเพย์' : 'PromptPay',
                      isEnabled: true,
                    ),
                  ),
                ],
                if (hasOnline) ...[
                  const SizedBox(width: 4),
                  Expanded(
                    child: _buildMethodButton(
                      'Online',
                      isThai ? 'ออนไลน์' : 'Online',
                      isEnabled: true,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 24),
            Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  (receipt?.totalAmount ?? 0.0).toStringAsFixed(2),
                  style: const TextStyle(
                    fontSize: 50,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMethodButton(
    String methodId,
    String label, {
    required bool isEnabled,
  }) {
    bool isSelected = selectedMethod == methodId;
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: isSelected
            ? Colors.blue
            : (isEnabled ? Colors.grey[200] : Colors.grey[100]),
        foregroundColor: isSelected
            ? Colors.white
            : (isEnabled ? Colors.black87 : Colors.black38),
        elevation: isSelected ? 2 : 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      onPressed: isEnabled
          ? () {
              setState(() {
                selectedMethod = methodId;
              });
            }
          : null,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(label),
      ),
    );
  }

  Widget _buildSection3() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: receiveAmountController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: _handleAmount,
                    decoration: InputDecoration(
                      labelText: isThai
                          ? 'จำนวนเงินที่ได้รับ'
                          : 'Receive Amount',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextField(
                    controller: changeAmountController,
                    readOnly: true,
                    style: TextStyle(
                      color: changeAmount < 0 ? Colors.red : Colors.green,
                      fontWeight: FontWeight.bold,
                    ),
                    decoration: InputDecoration(
                      labelText: isThai ? 'จำนวนเงินทอน' : 'Change Amount',
                      border: const OutlineInputBorder(),
                      filled: true,
                      fillColor: Colors.grey[100],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: tipAmountController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: _handleAmount,
                    decoration: InputDecoration(
                      labelText: isThai ? 'จำนวนเงินทิป' : 'Tip Amount',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    onPressed: changeAmount > 0 ? _change2Tip : null,
                    child: Text(
                      isThai ? 'ไม่รับเงินทอน ให้เป็นทิป' : 'Change to Tip',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [_buildBanknoteButton(10), _buildBanknoteButton(20), _buildBanknoteButton(50) ],
            ),
            const SizedBox(height: 5),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [_buildBanknoteButton(100), _buildBanknoteButton(500), _buildBanknoteButton(1000)],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: SizedBox(
                    height: 60,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: _confirmCancel,
                      child: Text(
                        isThai ? 'ยกเลิก' : 'Cancel',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 3,
                  child: SizedBox(
                    height: 60,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: _processPayment,
                      child: Text(
                        isThai ? 'เก็บเงิน' : 'Pay',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
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

  Widget _buildBanknoteButton(double value) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4.0),
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue[50],
            foregroundColor: Colors.blue[900],
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(color: Colors.blue[200]!),
            ),
          ),
          onPressed: () => _addAmount(value),
          child: Text('${value.toStringAsFixed(0)}'),
        ),
      ),
    );
  }

  Widget _buildMTSection() {
    List<String> requiredParams = [
      "MT_BANK_CODE",
      "MT_ACCOUNT_NAME",
      "MT_ACCOUNT_NUMBER",
      "MT_THAI_MEDIA",
    ];
    List<PaymentValue> displayValues = mtValues
        .where((pv) => requiredParams.contains(pv.payment_parameter_ID))
        .toList();

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ...displayValues.map((pv) {
              if (pv.type == 'T') {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4.0),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: Text(
                          pv.name ?? '',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      Expanded(flex: 3, child: Text(pv.value ?? '')),
                    ],
                  ),
                );
              } else if (pv.type == 'P') {
                Widget imageWidget;
                if (pv.localPicture != null &&
                    pv.localPicture!.isNotEmpty &&
                    File(pv.localPicture!).existsSync()) {
                  imageWidget = Image.file(
                    File(pv.localPicture!),
                    height: 100,
                    fit: BoxFit.contain,
                  );
                } else if (pv.value != null && pv.value!.isNotEmpty) {
                  imageWidget = Image.network(
                    widget.config.apiUrl + pv.value!,
                    height: 100,
                    fit: BoxFit.contain,
                  );
                } else {
                  return const SizedBox();
                }

                return GestureDetector(
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (context) => Dialog(
                        child:
                            pv.localPicture != null &&
                                pv.localPicture!.isNotEmpty &&
                                File(pv.localPicture!).existsSync()
                            ? Image.file(
                                File(pv.localPicture!),
                                fit: BoxFit.contain,
                              )
                            : Image.network(
                                widget.config.apiUrl + pv.value!,
                                fit: BoxFit.contain,
                              ),
                      ),
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: imageWidget,
                    ),
                  ),
                );
              }
              return const SizedBox();
            }).toList(),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: receiveAmountController
                      ..text =
                          (receiveAmountController.text == '0' ||
                              receiveAmountController.text.isEmpty)
                          ? (receipt?.totalAmount ?? 0.0).toStringAsFixed(2)
                          : receiveAmountController.text,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: _handleAmount,
                    decoration: InputDecoration(
                      labelText: isThai
                          ? 'จำนวนเงินที่ได้รับ'
                          : 'Receive Amount',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            if (receipt?.slipFileName != null &&
                receipt!.slipFileName!.isNotEmpty)
              FutureBuilder<Directory>(
                future: getApplicationDocumentsDirectory(),
                builder: (context, snapshot) {
                  if (snapshot.hasData) {
                    final file = File(
                      '${snapshot.data!.path}/${receipt!.slipFileName}',
                    );
                    if (file.existsSync()) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 24.0),
                        child: Center(
                          child: Image.file(
                            file,
                            height: 100,
                            fit: BoxFit.contain,
                          ),
                        ),
                      );
                    }
                  }
                  return const SizedBox();
                },
              ),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    onPressed: () async {
                      debugPrint('print button pressed, calling syncReceipt');

                      bool isSyncSuccess = await SyncService.syncReceipt(widget.config);

                      debugPrint('syncReceipt completed isSyncSuccess=${isSyncSuccess}');

                      if (isSyncSuccess) {
                        await PrintService.printPaymentInfo(config: widget.config, receipt: receipt, mtValues: mtValues, isThai: isThai);
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(isThai ? 'ซิงค์ข้อมูลไม่สำเร็จ' : 'Sync failed')),
                        );
                      }
                    },
                    child: Text(isThai ? 'พิมพ์' : 'Print'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    onPressed: _takePhoto,
                    child: Text(isThai ? 'ถ่ายรูป' : 'Take Photo'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    onPressed: _processMTPayment,
                    child: Text(isThai ? 'เก็บเงิน' : 'Pay'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _takePhoto() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.camera);
    if (pickedFile != null && receipt != null) {
      final docDir = await getApplicationDocumentsDirectory();
      final newFileName = '${const Uuid().v4()}.jpg';
      final newFilePath = '${docDir.path}/$newFileName';
      await File(pickedFile.path).copy(newFilePath);

      setState(() {
        receipt!.slipFileName = newFileName;
        receipt!.isDirty = true;
      });
      await isar.writeTxn(() async {
        await isar.receiptList.put(receipt!);
      });
    }
  }

  void _confirmCancel() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(isThai ? 'ยืนยันการยกเลิก' : 'Confirm Cancel'),
          content: Text(
            isThai
                ? 'คุณต้องการยกเลิกการชำระเงินใช่หรือไม่?'
                : 'Do you want to cancel this payment?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                isThai ? 'ไม่' : 'No',
                style: const TextStyle(color: Colors.grey),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                Navigator.pop(context);
                await _processCancel();
              },
              child: Text(isThai ? 'ใช่, ยกเลิก' : 'Yes, Cancel'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _processCancel() async {
    if (receipt != null) {
      await isar.writeTxn(() async {
        receipt!.status = 'Cancel';
        receipt!.lastUpdated = DateTime.now().toIso8601String();
        receipt!.isDirty = true;
        await isar.receiptList.put(receipt!);
      });
    }
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (context) => PPosScreen(config: widget.config),
      ),
      (route) => false,
    );
  }

  void _processPayment() async {
    if (isDebug) { setState(() => _debugText = 'processPayment'); }
    if (receipt == null) return;

    receipt!.paidAmount = (receipt!.totalAmount ?? 0.0) + tipAmount;
    receipt!.status = 'Paid';
    receipt!.paymentType = 'Cash';

    final foodOrders = await isar.foodOrderList
        .where()
        .filter()
        .parentIDEqualTo(receipt!.id)
        .and()
        .parentTypeEqualTo('receipt')
        .findAll();

    await isar.writeTxn(() async {
      await isar.receiptList.put(receipt!);
      for (var order in foodOrders) {
        order.status = 'OrderFood';
        await isar.foodOrderList.put(order);
      }
    });

    final settings = await isar.settingValueList.where().filter().anyOf([
      'FOC_PRN_RCP_CSH',
      'FOC_PRN_COK',
      'FOC_PAUSE_PRN_COK',
    ], (q, String id) => q.setting_IDEqualTo(id)).findAll();

    Map<String, bool> settingValue = {
      'FOC_PRN_RCP_CSH': true,
      'FOC_PRN_COK': true,
      'FOC_PAUSE_PRN_COK': false,
    };

    for (var sv in settings) {
      if (sv.setting_ID != null) {
        settingValue[sv.setting_ID!] = (sv.value == 'Y');
      }
    }

    if (widget.config.PrinterModel == 'Xprinter N160ii') {
      settingValue['FOC_PAUSE_PRN_COK'] = false;
    }

    if (settingValue['FOC_PRN_RCP_CSH'] == true) {
      await PrintService.printReceipt(isar: isar, config: widget.config, receipt: receipt, foodOrders: foodOrders, displayItems: displayItems, isThai: isThai);
      if (isDebug) { setState(() => _debugText = '_printReceipt'); }
    }

    if (settingValue['FOC_PRN_COK'] == true &&
        widget.config.isKitchen == true) {
      if (settingValue['FOC_PAUSE_PRN_COK'] == true) {
        if (!mounted) return;
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) {
            return AlertDialog(
              content: Text(
                isThai
                    ? 'ฉีกใบเสร็จรับเงินให้ลูกค้า แล้วกดปุ่มเพื่อพิมพ์ใบสั่งอาหาร'
                    : 'Tear off the receipt and press to print cooking order.',
              ),
              actions: [
                ElevatedButton(
                  onPressed: () async {
                    Navigator.pop(context);
                    await PrintService.printCookingOrder(isar: isar, config: widget.config, foodOrders: foodOrders, displayItems: displayItems);
                    await SyncService.syncReceipt(widget.config);
                    _navigateBack();
                  },
                  child: Text(
                    isThai ? 'พิมพ์ใบสั่งอาหาร' : 'Print Cooking Order',
                  ),
                ),
              ],
            );
          },
        );
        return;
      } else {
        await PrintService.printCookingOrder(isar: isar, config: widget.config, foodOrders: foodOrders, displayItems: displayItems);
        if (isDebug) { setState(() => _debugText = '_printCookingOrder'); }
      }
    }

    if (isDebug) { setState(() => _debugText = 'call syncReceipt'); }

    await SyncService.syncReceipt(widget.config);
    // _navigateBack(); 
  }

  void _processMTPayment() async {
    if (isDebug) { setState(() => _debugText = 'processMTPayment'); }
    if (receipt == null) return;

    receipt!.paidAmount = (receipt!.totalAmount ?? 0.0) + tipAmount;
    receipt!.status = 'Paid';
    receipt!.paymentType = 'MoneyTransfer';

    final foodOrders = await isar.foodOrderList
        .where()
        .filter()
        .parentIDEqualTo(receipt!.id)
        .and()
        .parentTypeEqualTo('receipt')
        .findAll();

    await isar.writeTxn(() async {
      await isar.receiptList.put(receipt!);
      for (var order in foodOrders) {
        order.status = 'OrderFood';
        await isar.foodOrderList.put(order);
      }
    });

    final settings = await isar.settingValueList.where().filter().anyOf([
      'FOC_PRN_RCP_CSH',
      'FOC_PRN_COK',
      'FOC_PAUSE_PRN_COK',
    ], (q, String id) => q.setting_IDEqualTo(id)).findAll();

    Map<String, bool> settingValue = {
      'FOC_PRN_RCP_CSH': true,
      'FOC_PRN_COK': true,
      'FOC_PAUSE_PRN_COK': false,
    };

    for (var sv in settings) {
      if (sv.setting_ID != null) {
        settingValue[sv.setting_ID!] = (sv.value == 'Y');
      }
    }

    if (widget.config.PrinterModel == 'Xprinter N160ii') {
      settingValue['FOC_PAUSE_PRN_COK'] = false;
    }

    if (settingValue['FOC_PRN_RCP_CSH'] == true) {
      await PrintService.printReceipt(isar: isar, config: widget.config, receipt: receipt, foodOrders: foodOrders, displayItems: displayItems, isThai: isThai, isMT: true);
      if (isDebug) { setState(() => _debugText = '_printReceipt'); }
    }

    if (settingValue['FOC_PRN_COK'] == true &&
        widget.config.isKitchen == true) {
      if (settingValue['FOC_PAUSE_PRN_COK'] == true) {
        if (!mounted) return;
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) {
            return AlertDialog(
              content: Text(
                isThai
                    ? 'ฉีกใบเสร็จรับเงินให้ลูกค้า แล้วกดปุ่มเพื่อพิมพ์ใบสั่งอาหาร'
                    : 'Tear off the receipt and press to print cooking order.',
              ),
              actions: [
                ElevatedButton(
                  onPressed: () async {
                    Navigator.pop(context);
                    await PrintService.printCookingOrder(isar: isar, config: widget.config, foodOrders: foodOrders, displayItems: displayItems);
                    await SyncService.syncReceipt(widget.config);
                    _navigateBack();
                  },
                  child: Text(
                    isThai ? 'พิมพ์ใบสั่งอาหาร' : 'Print Cooking Order',
                  ),
                ),
              ],
            );
          },
        );
        return;
      } else {
        await PrintService.printCookingOrder(isar: isar, config: widget.config, foodOrders: foodOrders, displayItems: displayItems);
        if (isDebug) { setState(() => _debugText = '_printCookingOrder done'); }
      }
    }

    if (isDebug) { setState(() => _debugText = 'call syncReceipt'); }

    await SyncService.syncReceipt(widget.config);
    // _navigateBack(); 
  }

  void _navigateBack() {
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (context) => PPosScreen(config: widget.config),
      ),
      (route) => false,
    );
  }

  Widget _buildPPSection() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              isThai ? 'คิวอาร์พร้อมเพย์' : 'PromptPay QR',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            if (_isGeneratingPP)
              const Center(child: CircularProgressIndicator())
            else if (_ppQrBase64 == null)
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                onPressed: _generatePPQr,
                child: Text(isThai ? 'สร้างคิวอาร์โค้ด' : 'Generate QR Code'),
              )
            else
              Column(
                children: [
                  Image.memory(
                    base64Decode(_ppQrBase64!),
                    height: 250,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          onPressed: () async { await PrintService.printPromptPay(isar: isar, config: widget.config, receipt: receipt, ppQrBase64: _ppQrBase64); },
                          child: Text(isThai ? 'พิมพ์ QR' : 'Print QR'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          onPressed: _processMTPayment,
                          child: Text(isThai ? 'ตรวจสอบ & ชำระเงิน' : 'Check & Pay'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _generatePPQr() async {
    if (isDebug) { setState(() => _debugText = 'Generating PP QR'); }
    setState(() {
      _isGeneratingPP = true;
    });

    try {
      String merchantId = '';
      String apiKey = '';
      int expireMinute = 15;

      for (var pv in ppValues) {
        if (pv.payment_parameter_ID == 'PP_MERCHANT_ID') merchantId = pv.value ?? '';
        if (pv.payment_parameter_ID == 'PP_API_KEY') apiKey = pv.value ?? '';
        if (pv.payment_parameter_ID == 'PP_EXPIRE_MINUTE') expireMinute = int.tryParse(pv.value ?? '15') ?? 15;
      }

      if (merchantId.isEmpty || apiKey.isEmpty) {
        throw Exception('PP_MERCHANT_ID or PP_API_KEY is missing');
      }

      final now = DateTime.now().toUtc();
      final expiryTime = now.add(Duration(minutes: expireMinute));
      final expiryTimeStr = '${expiryTime.toIso8601String().split('.')[0]}Z';

      int amount = ((receipt?.totalAmount ?? 0.0) * 100).toInt();

      final payload = {
        "amount": amount,
        "currency": "THB",
        "paymentMethod": {
          "qrPromptPay": {
            "expiryTime": expiryTimeStr
          },
          "paymentMethodType": "QR_PROMPT_PAY"
        },
        "referenceId": receipt?.id,
        "returnUrl": "https://www.beamcheckout.com",
        "skip3dsFlow": false
      };

      String basicAuth = 'Basic ' + base64Encode(utf8.encode('$merchantId:$apiKey'));

      final response = await http.post(
        Uri.parse('https://api.beamcheckout.com/api/v1/charges'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': basicAuth,
        },
        body: jsonEncode(payload),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        if (data['encodedImage'] != null && data['encodedImage']['imageBase64Encoded'] != null) {
          await SyncService.syncReceipt(widget.config);

          setState(() { _ppQrBase64 = data['encodedImage']['imageBase64Encoded']; });
        } else {
          throw Exception('No QR image in response');
        }
      } else {
        throw Exception('API error: ${response.statusCode} ${response.body}');
      }
    } catch (e) {
      if (isDebug) {
        setState(() {
          _debugText = 'PP QR Error: $e';
        });
      }
      debugPrint("Error generating PP QR: $e");
    } finally {
      setState(() {
        _isGeneratingPP = false;
      });
    }
  }

  void _showDiscountItemDialog(DisplayOrderItem di, double itemAmount) {
    if (foDiscountFood == null) return;
    
    final level = foDiscountFood!['PermissionLevel'];
    if (level != 'Full' && level != 'Partial') return;
    
    bool showPercent = true;
    if (level == 'Partial' && foDiscountFood!['PartialPercent'] == null) {
      showPercent = false;
    }

    double maxPercent = level == 'Full' ? 100.0 : double.tryParse(foDiscountFood!['PartialPercent'] ?? '0') ?? 0.0;
    double maxAmount = level == 'Full' ? itemAmount : double.tryParse(foDiscountFood!['PartialAmount'] ?? '0') ?? 0.0;
    
    double currentPercent = (di.item.discountPercent ?? 0).toDouble();
    double currentAmount = di.item.discountAmount ?? 0.0;

    TextEditingController percentCtrl = TextEditingController(text: currentPercent > 0 ? currentPercent.toStringAsFixed(0) : '');
    TextEditingController amountCtrl = TextEditingController(text: currentAmount > 0 ? currentAmount.toStringAsFixed(2) : '');

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            
            void updateDiscountAmount(double dA, {bool forceUpdateText = false}) {
              double finalAmount = dA;
              bool exceeded = false;
              if (level == 'Partial' && maxAmount > 0 && finalAmount > maxAmount) {
                finalAmount = maxAmount;
                exceeded = true;
              }
              if (finalAmount > itemAmount) {
                finalAmount = itemAmount;
                exceeded = true;
              }
              currentAmount = finalAmount;
              
              if (forceUpdateText || exceeded) {
                String newText = finalAmount > 0 ? finalAmount.toStringAsFixed(2) : '';
                if (amountCtrl.text != newText) {
                  amountCtrl.text = newText;
                  amountCtrl.selection = TextSelection.collapsed(offset: newText.length);
                }
              }
            }

            return AlertDialog(
              title: Text(isThai ? 'ส่วนลดรายการ' : 'Item Discount'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(di.itemName),
                  Text('${isThai ? 'ราคา' : 'Price'}: ${itemAmount.toStringAsFixed(2)}'),
                  const SizedBox(height: 16),
                  if (showPercent) ...[
                    TextField(
                      controller: percentCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: isThai ? 'ลด %' : 'discount %',
                      ),
                      onChanged: (val) {
                        double p = double.tryParse(val) ?? 0.0;
                        if (p > maxPercent) {
                          p = maxPercent;
                          String newText = p.toStringAsFixed(0);
                          if (percentCtrl.text != newText) {
                            percentCtrl.text = newText;
                            percentCtrl.selection = TextSelection.collapsed(offset: newText.length);
                          }
                        }
                        double dA = itemAmount * (p / 100.0);
                        updateDiscountAmount(dA, forceUpdateText: true);
                        setStateDialog((){});
                      },
                    ),
                    const SizedBox(height: 16),
                  ],
                  TextField(
                    controller: amountCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: isThai ? 'ลด (บาท)' : 'discount (Baht)',
                    ),
                    onChanged: (val) {
                      double dA = double.tryParse(val) ?? 0.0;
                      updateDiscountAmount(dA);
                      setStateDialog((){});
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(isThai ? 'ยกเลิก' : 'Cancel'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    di.item.discountPercent = int.tryParse(percentCtrl.text) ?? 0;
                    di.item.discountAmount = currentAmount;
                    
                    await isar.writeTxn(() async {
                      di.item.lastUpdated = DateTime.now().toIso8601String();
                      di.item.isDirty = true;
                      await isar.foodOrderItemList.put(di.item);
                    });

                    await _recalculateFoodOrder();
                    Navigator.pop(context);
                    setState(() {});
                  },
                  child: Text(isThai ? 'บันทึก' : 'Save'),
                ),
              ],
            );
          }
        );
      }
    );
  }

  Future<void> _recalculateFoodOrder() async {
    if (receipt == null) return;
    
    final foodOrders = await isar.foodOrderList
        .where()
        .filter()
        .parentIDEqualTo(receipt!.id!)
        .and()
        .parentTypeEqualTo('receipt')
        .findAll();
    
    await isar.writeTxn(() async {
      double newSumAmount = 0;

      for (var order in foodOrders) {
        final items = await isar.foodOrderItemList
            .where()
            .filter()
            .food_order_IDEqualTo(order.id)
            .findAll();
            
        double orderAmount = 0;
        for (var item in items) {
           double amt = ((item.itemPrice ?? 0) * (item.quantity ?? 0));
           double itemDiscount = item.discountAmount ?? 0.0;
           orderAmount += (amt - itemDiscount);
        }
        
        order.orderAmount = orderAmount;
        order.lastUpdated = DateTime.now().toIso8601String();
        order.isDirty = true;
        await isar.foodOrderList.put(order);
        
        newSumAmount += orderAmount;
      }
      
      receipt!.sumAmount = newSumAmount;
      receipt!.totalAmount = newSumAmount - (receipt!.discountAmount ?? 0) + (receipt!.vatAmount ?? 0);
      receipt!.lastUpdated = DateTime.now().toIso8601String();
      receipt!.isDirty = true;
      await isar.receiptList.put(receipt!);
    });
  }
  Future<void> _updateReceiptDiscountDB(double amount, int percent) async {
    if (receipt == null) return;
    await isar.writeTxn(() async {
      receipt!.discountAmount = amount;
      receipt!.discountPercent = percent;
      receipt!.totalAmount = (receipt!.sumAmount ?? 0.0) - amount + (receipt!.vatAmount ?? 0.0);
      receipt!.lastUpdated = DateTime.now().toIso8601String();
      receipt!.isDirty = true;
      await isar.receiptList.put(receipt!);
    });
    
    _handleAmount(''); 
    setState(() {});
  }

  Widget _buildReceiptDiscountRow() {
    final level = foDiscountReceipt!['PermissionLevel'];
    if (level != 'Full' && level != 'Partial') {
      return _buildAmountRow(isThai ? 'ส่วนลด' : 'Discount', receipt?.discountAmount ?? 0.0);
    }
    
    bool showPercent = true;
    if (level == 'Partial' && foDiscountReceipt!['PartialPercent'] == null) {
      showPercent = false;
    }

    double itemAmount = receipt?.sumAmount ?? 0.0;
    
    double maxPercent = level == 'Full' ? 100.0 : double.tryParse(foDiscountReceipt!['PartialPercent'] ?? '0') ?? 0.0;
    double maxAmount = level == 'Full' ? itemAmount : double.tryParse(foDiscountReceipt!['PartialAmount'] ?? '0') ?? 0.0;
    
    void updateDiscountAmount(double dA, {bool forceUpdateText = false}) {
      double finalAmount = dA;
      bool exceeded = false;
      if (level == 'Partial' && maxAmount > 0 && finalAmount > maxAmount) {
        finalAmount = maxAmount;
        exceeded = true;
      }
      if (finalAmount > itemAmount) {
        finalAmount = itemAmount;
        exceeded = true;
      }
      
      if (forceUpdateText || exceeded) {
        String newText = finalAmount > 0 ? finalAmount.toStringAsFixed(2) : '';
        if (receiptDiscountAmountCtrl.text != newText) {
          receiptDiscountAmountCtrl.text = newText;
          receiptDiscountAmountCtrl.selection = TextSelection.collapsed(offset: newText.length);
        }
      }
      
      _updateReceiptDiscountDB(finalAmount, int.tryParse(receiptDiscountPercentCtrl.text) ?? 0);
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Text(isThai ? 'ส่วนลด' : 'Discount', style: const TextStyle(fontSize: 16)),
            if (showPercent) ...[
              const SizedBox(width: 8),
              SizedBox(
                width: 60,
                height: 30,
                child: TextField(
                  controller: receiptDiscountPercentCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    hintText: '%',
                    contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (val) {
                    double p = double.tryParse(val) ?? 0.0;
                    if (p > maxPercent) {
                      p = maxPercent;
                      String newText = p.toStringAsFixed(0);
                      if (receiptDiscountPercentCtrl.text != newText) {
                        receiptDiscountPercentCtrl.text = newText;
                        receiptDiscountPercentCtrl.selection = TextSelection.collapsed(offset: newText.length);
                      }
                    }
                    double dA = itemAmount * (p / 100.0);
                    updateDiscountAmount(dA, forceUpdateText: true);
                  },
                ),
              ),
            ],
          ],
        ),
        SizedBox(
          width: 80,
          height: 30,
          child: TextField(
            controller: receiptDiscountAmountCtrl,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.right,
            decoration: const InputDecoration(
              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 0),
              border: OutlineInputBorder(),
            ),
            onChanged: (val) {
              double dA = double.tryParse(val) ?? 0.0;
              updateDiscountAmount(dA);
            },
          ),
        ),
      ],
    );
  }
}
