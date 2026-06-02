import 'package:isar/isar.dart';

part 'IsarModels.g.dart';

@Collection(accessor: 'userList')
class User {
  Id isarId = Isar.autoIncrement;
  @Index(unique: true, replace: true)
  int? id;
  String? name;
  String? userName;
  String? passwordHash;
  String? role_ID;
  String? language;
  String? isActive;
  String? lastUpdated;
  bool isDirty = false;
}

@Collection(accessor: 'roleList')
class Role {
  Id isarId = Isar.autoIncrement;
  @Index(unique: true, replace: true)
  String? id;
  String? thaiName;
  String? englishName;
  String? isActive;
  String? lastUpdated;
  bool isDirty = false;
}

@Collection(accessor: 'roleTransactionPermissionList')
class RoleTransactionPermission {
  Id isarId = Isar.autoIncrement;
  @Index(unique: true, replace: true)
  String? id;
  String? role_ID;
  String? transaction_permission_ID;
  String? permissionLevel;
  String? partialPercent;
  String? partialAmount;
  String? lastUpdated;
  bool isDirty = false;
}

@Collection(accessor: 'shopCustomerList')
class ShopCustomer {
  Id isarId = Isar.autoIncrement;
  @Index(unique: true, replace: true)
  String? id;
  String? firstName;
  String? lastName;
  String? loginType;
  String? loginID;
  String? email;
  String? passwordHash;
  String? language;
  String? picture;
  String? telephone;
  String? isActive;
  String? lastUpdated;
  bool isDirty = false;
}

@Collection(accessor: 'shopTableList')
class ShopTable {
  Id isarId = Isar.autoIncrement;
  @Index(unique: true, replace: true)
  String? id;
  int? code;
  String? tableNumber;
  int? numberOfSeat;
  String? status;
  String? lastUpdated;
  bool isDirty = false;
}

@Collection(accessor: 'settingValueList')
class SettingValue {
  Id isarId = Isar.autoIncrement;
  @Index(unique: true, replace: true)
  int? id;
  String? setting_ID;
  String? name;
  String? value;
  String? type;
  String? list;
  String? lastUpdated;
  bool isDirty = false;
}

@Collection(accessor: 'documentCodeList')
class DocumentCode {
  Id isarId = Isar.autoIncrement;
  @Index(unique: true, replace: true)
  int? id;
  int? seq;
  String? name;
  String? value;
  String? seperator;
  String? isActive;
  String? lastUpdated;
  bool isDirty = false;
}

@Collection(accessor: 'documentTemplateList')
class DocumentTemplate {
  Id isarId = Isar.autoIncrement;
  @Index(unique: true, replace: true)
  int? id;
  int? seq;
  String? printText;
  String? alignment;
  int? fontSize;
  String? isActive;
  String? lastUpdated;
  bool isDirty = false;
}

@Collection(accessor: 'foodCategoryList')
class FoodCategory {
  Id isarId = Isar.autoIncrement;
  @Index(unique: true, replace: true)
  String? id;
  String? parentType;
  String? parentID;
  int? seq;
  String? thaiName;
  String? englishName;
  String? isActive;
  String? lastUpdated;
  bool isDirty = false;
}

@Collection(accessor: 'foodSizeList')
class FoodSize {
  Id isarId = Isar.autoIncrement;
  @Index(unique: true, replace: true)
  String? id;
  String? parentType;
  String? parentID;
  int? seq;
  String? thaiName;
  String? englishName;
  String? kitchenName;
  String? isActive;
  String? lastUpdated;
  bool isDirty = false;
}

@Collection(accessor: 'foodItemList')
class FoodItem {
  Id isarId = Isar.autoIncrement;
  @Index(unique: true, replace: true)
  String? id;
  String? food_category_ID;
  int? seq;
  String? thaiName;
  String? englishName;
  String? kitchenName;
  double? price;
  String? currency_ID;
  String? picture;
  String? localPicture;
  String? isRecommend;
  String? isServeTable;
  String? isTakeAway;
  String? isDelivery;
  String? isActive;
  String? lastUpdated;
  bool isDirty = false;
}

@Collection(accessor: 'foodItemSizeList')
class FoodItemSize {
  Id isarId = Isar.autoIncrement;
  @Index(unique: true, replace: true)
  String? id;
  String? food_item_ID;
  String? food_size_ID;
  double? price;
  String? isActive;
  String? lastUpdated;
  bool isDirty = false;
}

@Collection(accessor: 'foodOptionList')
class FoodOption {
  Id isarId = Isar.autoIncrement;
  @Index(unique: true, replace: true)
  String? id;
  String? food_item_ID;
  int? seq;
  String? thaiName;
  String? englishName;
  String? isActive;
  String? lastUpdated;
  bool isDirty = false;
}

@Collection(accessor: 'foodChoiceList')
class FoodChoice {
  Id isarId = Isar.autoIncrement;
  @Index(unique: true, replace: true)
  String? id;
  String? parentType;
  String? parentID;
  int? seq;
  String? thaiName;
  String? englishName;
  String? kitchenName;
  double? price;
  String? currency_ID;
  String? picture;
  String? isServeTable;
  String? isTakeAway;
  String? isDelivery;
  String? isActive;
  String? lastUpdated;
  bool isDirty = false;
}

@Collection(accessor: 'foodChoiceSizeList')
class FoodChoiceSize {
  Id isarId = Isar.autoIncrement;
  @Index(unique: true, replace: true)
  String? id;
  String? food_choice_ID;
  String? food_size_ID;
  double? price;
  String? isActive;
  String? lastUpdated;
  bool isDirty = false;
}

@Collection(accessor: 'receiptList')
class Receipt {
  Id isarId = Isar.autoIncrement;
  @Index(unique: true, replace: true)
  String? id;
  int? shop_branch_ID;
  int? shop_user_ID;
  String? shop_customer_ID;
  String? code;
  DateTime? createdAt;
  double? sumAmount;
  double? serviceChargeAmount;
  int? discountPercent;
  double? discountAmount;
  double? vatAmount;
  double? totalAmount;
  double? paidAmount;
  String? status;
  String? paymentType;
  String? slipFileName;
  String? lastUpdated;
  bool isDirty = false;
}

@Collection(accessor: 'shopOpenTableList')
class ShopOpenTable {
  Id isarId = Isar.autoIncrement;
  @Index(unique: true, replace: true)
  String? id;
  String? shop_table_ID;
  String? shop_customer_ID;
  String? receipt_ID;
  String? openAt;
  double? orderAmount;
  String? status;
  String? lastUpdated;
  bool isDirty = false;
}

@Collection(accessor: 'foodOrderList')
class FoodOrder {
  Id isarId = Isar.autoIncrement;
  @Index(unique: true, replace: true)
  String? id;
  String? parentType;
  String? parentID;
  int? number;
  int? kitchen_ID;
  String? createdAt;
  String? serveType;
  double? orderAmount;
  String? status;
  String? lastUpdated;
  bool isDirty = false;
}

@Collection(accessor: 'foodOrderItemList')
class FoodOrderItem {
  Id isarId = Isar.autoIncrement;
  @Index(unique: true, replace: true)
  String? id;
  String? food_order_ID;
  String? food_item_ID;
  String? food_size_ID;
  double? itemPrice;
  int? quantity;
  int? discountPercent;
  double? discountAmount;
  String? choiceIDList;
  String? description;
  String? lastUpdated;
  bool isDirty = false;
}

@Collection(accessor: 'paymentList')
class Payment {
  Id isarId = Isar.autoIncrement;
  @Index(unique: true, replace: true)
  int? id;
  String? payment_channel_ID;
  double? feePercent;
  String? mode;
  String? isActive;
  String? lastUpdated;
  String? name;
  bool isDirty = false;
}

@Collection(accessor: 'paymentValueList')
class PaymentValue {
  Id isarId = Isar.autoIncrement;
  @Index(unique: true, replace: true)
  int? id;
  int? payment_ID;
  String? payment_parameter_ID;
  String? value;
  String? lastUpdated;
  String? name;
  String? type;
  String? localPicture;
  bool isDirty = false;
}

@Collection(accessor: 'lastSyncList')
class LastSync {
  Id isarId = Isar.autoIncrement;
  @Index(unique: true, replace: true)
  int? id;
  String? master;
  String? receipt;
}
