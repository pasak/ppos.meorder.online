import 'package:meorder_ppos/database/IsarModels.dart';

class DisplayOrderItem {
  final FoodOrderItem item;
  final String itemName;
  final String sizeName;
  final String choiceName;
  final String kitchenItemName;
  final String kitchenSizeName;
  final String kitchenChoiceName;
  final String printColor;

  DisplayOrderItem({
    required this.item,
    required this.itemName,
    required this.sizeName,
    required this.choiceName,
    required this.kitchenItemName,
    required this.kitchenSizeName,
    required this.kitchenChoiceName,
    this.printColor = 'blue',
  });
}
