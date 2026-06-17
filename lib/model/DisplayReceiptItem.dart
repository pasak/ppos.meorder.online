import 'package:meorder_ppos/database/IsarModels.dart';

class DisplayReceiptItem {
  final ReceiptItem item;
  final String itemName;
  final String? unitName;
  
  DisplayReceiptItem({ 
    required this.item,
    required this.itemName,
    this.unitName
  });
}
