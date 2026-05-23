// model/OrderModel.dart

class OrderItem {
  final int quantity;
  final String description;

  OrderItem({required this.quantity, required this.description});

  // Factory method สำหรับแปลง JSON (Map) เป็น OrderItem
  factory OrderItem.fromJson(Map<String, dynamic> json) {
    return OrderItem(
      quantity: json['Quantity'] as int,
      description: json['Description'] as String,
    );
  }
}

class Order {
  final int id;
  final int orderNumber;
  final String serveType;
  final String status;
  final String tableNumber;
  final String orderTime; // ใช้ String หรือ DateTime ก็ได้ ขึ้นอยู่กับการจัดการเวลา
  final List<OrderItem> orderItems;

  Order({
    required this.id,
    required this.orderNumber,
    required this.serveType,
    required this.status,
    required this.tableNumber,
    required this.orderTime,
    required this.orderItems,
  });

  // Factory method สำหรับแปลง JSON (Map) เป็น Order
  factory Order.fromJson(Map<String, dynamic> json) {
    // แปลงรายการ OrderItems ที่เป็น List<Map<String, dynamic>> ให้เป็น List<OrderItem>
    final List<dynamic> itemsJson = json['ItemList'] ?? [];
    final List<OrderItem> items = itemsJson
        .map((itemJson) => OrderItem.fromJson(itemJson as Map<String, dynamic>))
        .toList();

    return Order(
      id: json['ID'] as int,
      orderNumber: json['Number'] as int,
      serveType: json['ServeType'] as String,
      status: json['Status'] as String,
      tableNumber: json['TableNumber'] as String,
      orderTime: json['Time'] as String,
      orderItems: items,
    );
  }
}

/*
[{"ID":13,"Number":1,"ServeType":"T","TableNumber":"2","Status":"KitchenFetch","Time":"16:08",
"ItemList":[{"Quantity":2,"Description":"เรือ ชญ เล็ก ตก หมูสด ชิ้นหมู"},
            {"Quantity":1,"Description":"ข้าวผัด ใหญ่ กุ้ง "}]}]
*/
