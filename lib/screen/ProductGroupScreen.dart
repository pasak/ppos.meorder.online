import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:meorder_ppos/lib/EnvConfig.dart';
// import 'package:meorder_product/screen/HomeScreen.dart';
// import 'package:meorder_product/screen/ProductItemScreen.dart';
// import 'package:meorder_product/screen/StockCountScreen.dart';
import 'package:meorder_ppos/screen/PrintScreen.dart';
class ProductGroupScreen extends StatefulWidget {
  final EnvConfig config;

  const ProductGroupScreen({super.key, required this.config});

  @override
  State<ProductGroupScreen> createState() => _ProductGroupScreenState();
}

class _ProductGroupScreenState extends State<ProductGroupScreen> {
  bool _isLoading = false;
  List<dynamic> _productGroups = [];
  String _error = '';

  @override
  void initState() {
    super.initState();
    _fetchProductGroups();
  }

  Future<void> _fetchProductGroups() async {
    setState(() {
      _isLoading = true;
      _error = '';
    });

    final uri = Uri.parse('${widget.config.apiUrl}api/product-group/list');
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${widget.config.apiToken}',
    };
    final body = jsonEncode({'shop_ID': widget.config.shop_ID});

    try {
      final response = await http.post(uri, headers: headers, body: body);
      if (response.statusCode == 200) {
        final Map<String, dynamic> responseJson = jsonDecode(response.body);
        if (responseJson['message'] == 'success') {
          setState(() {
            _productGroups = responseJson['ProductGroupList'] ?? [];
          });
        } else {
          setState(() {
            _error = responseJson['message'] ?? 'Error loading data';
          });
        }
      } else {
        setState(() {
          _error = 'API Error ${response.statusCode}\napiUrl: ${widget.config.apiUrl}\napiToken: ${widget.config.apiToken}\nid: ${widget.config.shop_ID}\nURL: $uri';
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Network Error: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _saveProductGroup(int? id, String parentType, var parentId, String groupName) async {
    setState(() {
      _isLoading = true;
      _error = '';
    });

    final uri = Uri.parse('${widget.config.apiUrl}api/product-group/save');
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${widget.config.apiToken}',
    };
    
    final Map<String, dynamic> payload = {
      'ParentType': parentType,
      'ParentID': parentId,
      'GroupName': groupName,
    };
    
    if (id != null) {
      payload['ID'] = id;
    }

    try {
      final response = await http.post(uri, headers: headers, body: jsonEncode(payload));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['message'] == 'success' || data['ID'] != null) {
          // Success
          await _fetchProductGroups();
        } else {
          setState(() { _error = data['message'] ?? 'Save failed'; });
        }
      } else {
        setState(() { _error = 'API Error ${response.statusCode}'; });
      }
    } catch (e) {
      setState(() { _error = 'Network Error: $e'; });
    } finally {
      if (mounted) setState(() { _isLoading = false; });
    }
  }

  Future<void> _deleteProductGroup(int id) async {
    setState(() {
      _isLoading = true;
      _error = '';
    });

    final uri = Uri.parse('${widget.config.apiUrl}api/product-group/delete');
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${widget.config.apiToken}',
    };

    try {
      final response = await http.post(uri, headers: headers, body: jsonEncode({'ID': id}));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['message'] == 'success') {
          await _fetchProductGroups();
        } else {
          setState(() { _error = data['message'] ?? 'Delete failed'; });
        }
      } else {
        setState(() { _error = 'API Error ${response.statusCode}'; });
      }
    } catch (e) {
      setState(() { _error = 'Network Error: $e'; });
    } finally {
      if (mounted) setState(() { _isLoading = false; });
    }
  }

  List<Map<String, dynamic>> _getFlattenedGroups(List<dynamic> groups, {int? excludeId, String prefix = ''}) {
    List<Map<String, dynamic>> flatList = [];
    for (var g in groups) {
      final groupMap = Map<String, dynamic>.from(g);
      if (excludeId != null && groupMap['ID'] == excludeId) continue;
      
      flatList.add({
        'ID': groupMap['ID'],
        'GroupName': '$prefix${groupMap['GroupName']}',
      });

      if (groupMap['Sub'] != null) {
        flatList.addAll(_getFlattenedGroups(groupMap['Sub'], excludeId: excludeId, prefix: '$prefix- '));
      }
    }
    return flatList;
  }

  void _showEditDialog({Map<String, dynamic>? group, String? parentType, var parentId}) {
    final TextEditingController nameController = TextEditingController(text: group?['GroupName'] ?? '');

    // Determine initial selected parent
    int selectedParentId = 0;
    if (group != null) {
      if (group['ParentType'] == 'product_group') {
        selectedParentId = group['ParentID'] is int ? group['ParentID'] : int.tryParse(group['ParentID'].toString()) ?? 0;
      }
    } else if (parentType == 'product_group' && parentId != null) {
      selectedParentId = parentId is int ? parentId : int.tryParse(parentId.toString()) ?? 0;
    }

    final flatGroups = _getFlattenedGroups(_productGroups, excludeId: group?['ID']);
    
    // Ensure selectedParentId exists in the flatGroups, otherwise set to 0
    if (selectedParentId != 0 && !flatGroups.any((g) => g['ID'] == selectedParentId)) {
      selectedParentId = 0;
    }

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: Text(group == null ? 'เพิ่มกลุ่มสินค้า' : 'แก้ไขกลุ่มสินค้า'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'ชื่อกลุ่มสินค้า',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<int>(
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'เป็นกลุ่มย่อยของ',
                      border: OutlineInputBorder(),
                    ),
                    value: selectedParentId,
                    items: [
                      const DropdownMenuItem<int>(
                        value: 0,
                        child: Text(''),
                      ),
                      ...flatGroups.map((g) {
                        return DropdownMenuItem<int>(
                          value: g['ID'],
                          child: Text(g['GroupName']),
                        );
                      }).toList(),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setStateDialog(() {
                          selectedParentId = value;
                        });
                      }
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('ยกเลิก'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final name = nameController.text.trim();
                    if (name.isNotEmpty) {
                      Navigator.pop(context);
                      
                      String finalParentType = 'shop';
                      dynamic finalParentId = widget.config.shop_ID;
                      
                      if (selectedParentId != 0) {
                        finalParentType = 'product_group';
                        finalParentId = selectedParentId;
                      }

                      _saveProductGroup(
                        group?['ID'], 
                        finalParentType, 
                        finalParentId, 
                        name
                      );
                    }
                  },
                  child: const Text('บันทึก'),
                ),
              ],
            );
          }
        );
      },
    );
  }

  void _confirmDelete(Map<String, dynamic> group) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('ยืนยันการลบ'),
          content: Text('คุณต้องการลบกลุ่ม "${group['GroupName']}" ใช่หรือไม่?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('ยกเลิก', style: TextStyle(color: Colors.grey)),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _deleteProductGroup(group['ID']);
              },
              child: const Text('ลบ', style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );
  }

  void _navigateToProducts(Map<String, dynamic> group) {
    // Navigate to ProductItemScreen to manage actual products
    // Navigator.push(
    //   context,
    //   MaterialPageRoute(builder: (context) => ProductItemScreen(config: widget.config, group: group)),
    // );
  }

  Widget _buildGroupNode(Map<String, dynamic> group, int level) {
    final subGroups = List<dynamic>.from(group['Sub'] ?? []);
    final hasSub = subGroups.isNotEmpty;
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
                    group['GroupName'] ?? '',
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
                // Actions
                IconButton(
                  icon: const Icon(Icons.edit, color: Colors.blue, size: 20),
                  onPressed: () => _showEditDialog(group: group),
                  tooltip: 'แก้ไข',
                ),
                IconButton(
                  icon: Icon(Icons.delete, color: hasSub ? Colors.grey : Colors.red, size: 20),
                  onPressed: hasSub ? null : () => _confirmDelete(group),
                  tooltip: 'ลบ',
                ),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline, color: Colors.green, size: 20),
                  onPressed: () => _showEditDialog(parentType: 'product_group', parentId: group['ID']),
                  tooltip: 'เพิ่มกลุ่มย่อย',
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.local_offer, size: 16),
                  label: const Text('สินค้า'),
                  onPressed: () => _navigateToProducts(group),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: const Size(0, 30),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (hasSub)
          ...subGroups.map((subGroup) => _buildGroupNode(Map<String, dynamic>.from(subGroup), level + 1)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // title: Text(widget.config.name != null ? '${widget.config.name} - กลุ่มสินค้า' : 'กลุ่มสินค้า'),
        title: Text('กลุ่มสินค้า'),
        actions: [
          IconButton(
            icon: const Icon(Icons.inventory),
            onPressed: () {
              // Navigator.push(
              //   context,
              //   MaterialPageRoute(builder: (context) => StockCountScreen(config: widget.config)),
              // );
            },
            tooltip: 'นับสต๊อก',
          ),
          IconButton(
            icon: const Icon(Icons.print),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => PrintScreen(config: widget.config)),
              );
            },
            tooltip: 'พิมพ์บาร์โค้ด',
          ),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _showEditDialog(parentType: 'shop', parentId: widget.config.shop_ID),
            tooltip: 'เพิ่มกลุ่มหลัก',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchProductGroups,
            tooltip: 'รีเฟรช',
          ),
        ],
      ),
      body: _isLoading && _productGroups.isEmpty
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
                    onRefresh: _fetchProductGroups,
                    child: _productGroups.isEmpty
                        ? ListView(
                            children: const [
                              Padding(
                                padding: EdgeInsets.all(32.0),
                                child: Center(child: Text('ไม่มีข้อมูลกลุ่มสินค้า')),
                              )
                            ],
                          )
                        : ListView.builder(
                            itemCount: _productGroups.length,
                            itemBuilder: (context, index) {
                              final group = Map<String, dynamic>.from(_productGroups[index]);
                              return _buildGroupNode(group, 0);
                            },
                          ),
                  ),
                ),
              ],
            ),
    );
  }
}
