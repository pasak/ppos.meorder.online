import 'package:flutter/material.dart';
import 'package:meorder_ppos/lib/EnvConfig.dart';
import 'package:meorder_ppos/screen/PPosScreen.dart';
import 'package:meorder_ppos/services/GeneralServices.dart';
import 'package:meorder_ppos/services/SyncService.dart';
import 'package:meorder_ppos/database/IsarModels.dart';
import 'package:isar/isar.dart';
import 'package:uuid/uuid.dart';

class MerchandiseCategoryScreen extends StatefulWidget {
  final EnvConfig config;
  const MerchandiseCategoryScreen({super.key, required this.config});

  @override
  State<MerchandiseCategoryScreen> createState() => _MerchandiseCategoryScreenState();
}

class _MerchandiseCategoryScreenState extends State<MerchandiseCategoryScreen> {
  bool get isThai => widget.config.language == 'th';
  List<RoleMasterPermission> _adminMenuList = [];
  bool _isLoading = false;
  List<Map<String, dynamic>> _merchandiseCategories = [];
  String _error = '';

  @override
  void initState() {
    super.initState();
    _loadPermissions();
    _fetchMerchandiseCategories();
  }

  Future<void> _loadPermissions() async {
    final roleID = widget.config.UserRole;
    if (roleID != null) {
      final menu = await GeneralServices.getAdminMenuList(roleID, widget.config);
      if (mounted) {
        setState(() {
          _adminMenuList = menu;
        });
      }
    }
  }

  Future<void> _fetchMerchandiseCategories() async {
    setState(() {
      _isLoading = true;
      _error = '';
    });

    try {
      final isar = Isar.getInstance()!;
      // Fetch active categories
      final rawCategories = await isar.merchandiseCategoryList.filter().isActiveEqualTo('Y').findAll();
      
      // Build tree
      final Map<String, Map<String, dynamic>> catMap = {};
      for (var c in rawCategories) {
        final hasItem = await isar.merchandiseItemList.filter().merchandise_category_IDEqualTo(c.id).isActiveEqualTo('Y').count() > 0;
        catMap[c.id!] = {
          'ID': c.id,
          'ParentType': c.parentType,
          'ParentID': c.parentID,
          'CategoryName': c.categoryName,
          'Sub': <Map<String, dynamic>>[],
          'hasItem': hasItem
        };
      }

      List<Map<String, dynamic>> rootNodes = [];
      for (var c in rawCategories) {
        if (c.parentType == 'shop' || c.parentType == null || c.parentType!.isEmpty) {
          rootNodes.add(catMap[c.id!]!);
        } else if (c.parentType == 'merchandise_category') {
          if (catMap.containsKey(c.parentID)) {
            (catMap[c.parentID]!['Sub'] as List).add(catMap[c.id!]!);
          } else {
             rootNodes.add(catMap[c.id!]!);
          }
        }
      }

      setState(() {
        _merchandiseCategories = rootNodes;
      });
    } catch (e) {
      setState(() {
        _error = 'Error loading data: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _saveMerchandiseCategory(String? id, String parentType, String? parentId, String categoryName) async {
    setState(() {
      _isLoading = true;
      _error = '';
    });

    try {
      final isar = Isar.getInstance()!;
      await isar.writeTxn(() async {
        MerchandiseCategory? category;
        if (id != null) {
          category = await isar.merchandiseCategoryList.filter().idEqualTo(id).findFirst();
        }
        
        category ??= MerchandiseCategory()
          ..id = const Uuid().v4()
          ..isActive = 'Y';
        
        category.parentType = parentType;
        category.parentID = parentId;
        category.categoryName = categoryName;
        category.isDirty = true;
        category.lastUpdated = DateTime.now().toIso8601String();
        
        await isar.merchandiseCategoryList.put(category);
      });

      await SyncService.syncMaster(widget.config);

      await _fetchMerchandiseCategories();
    } catch (e) {
      setState(() { _error = 'Error saving data: $e'; });
    } finally {
      if (mounted) setState(() { _isLoading = false; });
    }
  }

  Future<void> _deleteMerchandiseCategory(String id) async {
    setState(() {
      _isLoading = true;
      _error = '';
    });

    try {
      final isar = Isar.getInstance()!;
      await isar.writeTxn(() async {
        final category = await isar.merchandiseCategoryList.filter().idEqualTo(id).findFirst();
        if (category != null) {
          category.isActive = 'N';
          category.isDirty = true;
          category.lastUpdated = DateTime.now().toIso8601String();
          await isar.merchandiseCategoryList.put(category);
        }
      });

      await SyncService.syncMaster(widget.config);

      await _fetchMerchandiseCategories();
    } catch (e) {
      setState(() { _error = 'Error deleting data: $e'; });
    } finally {
      if (mounted) setState(() { _isLoading = false; });
    }
  }

  List<Map<String, dynamic>> _getFlattenedCategories(List<Map<String, dynamic>> categories, {String? excludeId, String prefix = ''}) {
    List<Map<String, dynamic>> flatList = [];
    for (var g in categories) {
      if (excludeId != null && g['ID'] == excludeId) continue;
      
      flatList.add({
        'ID': g['ID'],
        'CategoryName': '$prefix${g['CategoryName']}',
      });

      if (g['Sub'] != null && (g['Sub'] as List).isNotEmpty) {
        flatList.addAll(_getFlattenedCategories(List<Map<String, dynamic>>.from(g['Sub']), excludeId: excludeId, prefix: '$prefix- '));
      }
    }
    return flatList;
  }

  void _showEditDialog({Map<String, dynamic>? category, String? parentType, String? parentId}) {
    final TextEditingController nameController = TextEditingController(text: category?['CategoryName'] ?? '');

    String? selectedParentId;
    if (category != null) {
      if (category['ParentType'] == 'merchandise_category') {
        selectedParentId = category['ParentID'];
      }
    } else if (parentType == 'merchandise_category' && parentId != null) {
      selectedParentId = parentId;
    }

    final flatCategories = _getFlattenedCategories(_merchandiseCategories, excludeId: category?['ID']);
    
    // Ensure selectedParentId exists
    if (selectedParentId != null && !flatCategories.any((g) => g['ID'] == selectedParentId)) {
      selectedParentId = null;
    }

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: Text(category == null ? (isThai ? 'เพิ่มหมวดหมู่สินค้า' : 'Add Category') : (isThai ? 'แก้ไขหมวดหมู่สินค้า' : 'Edit Category')),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: InputDecoration(
                      labelText: isThai ? 'ชื่อหมวดหมู่สินค้า' : 'Category Name',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String?>(
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: isThai ? 'เป็นหมวดหมู่ย่อยของ' : 'Sub-category of',
                      border: const OutlineInputBorder(),
                    ),
                    value: selectedParentId,
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text(''),
                      ),
                      ...flatCategories.map((g) {
                        return DropdownMenuItem<String?>(
                          value: g['ID'],
                          child: Text(g['CategoryName']),
                        );
                      }).toList(),
                    ],
                    onChanged: (value) {
                      setStateDialog(() {
                        selectedParentId = value;
                      });
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
                  onPressed: () {
                    final name = nameController.text.trim();
                    if (name.isNotEmpty) {
                      Navigator.pop(context);
                      
                      String finalParentType = 'shop';
                      String? finalParentId = widget.config.shop_ID;
                      
                      if (selectedParentId != null) {
                        finalParentType = 'merchandise_category';
                        finalParentId = selectedParentId;
                      }

                      _saveMerchandiseCategory(
                        category?['ID'], 
                        finalParentType, 
                        finalParentId, 
                        name
                      );
                    }
                  },
                  child: Text(isThai ? 'บันทึก' : 'Save'),
                ),
              ],
            );
          }
        );
      },
    );
  }

  void _confirmDelete(Map<String, dynamic> category) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(isThai ? 'ยืนยันการลบ' : 'Confirm Delete'),
          content: Text(isThai ? 'คุณต้องการลบหมวดหมู่ "${category['CategoryName']}" ใช่หรือไม่?' : 'Are you sure you want to delete "${category['CategoryName']}"?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(isThai ? 'ยกเลิก' : 'Cancel', style: const TextStyle(color: Colors.grey)),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _deleteMerchandiseCategory(category['ID']);
              },
              child: Text(isThai ? 'ลบ' : 'Delete', style: const TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );
  }

  void _navigateToProducts(Map<String, dynamic> category) {
    // Navigate to MerchandiseItemScreen to manage actual products
  }

  Widget _buildCategoryNode(Map<String, dynamic> category, int level) {
    final subCategories = List<Map<String, dynamic>>.from(category['Sub'] ?? []);
    final hasSub = subCategories.isNotEmpty;
    final hasItem = category['hasItem'] == true;
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
                // Actions
                IconButton(
                  icon: const Icon(Icons.edit, color: Colors.blue, size: 20),
                  onPressed: () => _showEditDialog(category: category),
                  tooltip: isThai ? 'แก้ไข' : 'Edit',
                ),
                IconButton(
                  icon: Icon(Icons.delete, color: (hasSub || hasItem) ? Colors.grey : Colors.red, size: 20),
                  onPressed: (hasSub || hasItem) ? null : () => _confirmDelete(category),
                  tooltip: isThai ? 'ลบ' : 'Delete',
                ),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline, color: Colors.green, size: 20),
                  onPressed: () => _showEditDialog(parentType: 'merchandise_category', parentId: category['ID']),
                  tooltip: isThai ? 'เพิ่มหมวดหมู่ย่อย' : 'Add Sub-category',
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.local_offer, size: 16),
                  label: Text(isThai ? 'สินค้า' : 'Items'),
                  onPressed: () => _navigateToProducts(category),
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
          ...subCategories.map((subCat) => _buildCategoryNode(subCat, level + 1)),
      ],
    );
  }

  Widget _buildTopHeader() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            /*
            IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.black),
              onPressed: () => Navigator.pop(context),
            ),
            */
            Expanded(
              child: Text(
                isThai ? 'หมวดหมู่สินค้า' : 'Merchandise Categories',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.home, color: Colors.black),
              onPressed: () {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (context) => PPosScreen(config: widget.config)),
                  (Route<dynamic> route) => false,
                );
              },
            ),
            GeneralServices.getAdminPopupMenuButton(context, widget.config, _adminMenuList, isThai),
            IconButton(
              icon: const Icon(Icons.add, color: Colors.black),
              onPressed: () => _showEditDialog(parentType: 'shop', parentId: widget.config.shop_ID),
              tooltip: isThai ? 'เพิ่มหมวดหมู่หลัก' : 'Add Main Category',
            ),
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.black),
              onPressed: _fetchMerchandiseCategories,
              tooltip: isThai ? 'รีเฟรช' : 'Refresh',
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: Column(
        children: [
          _buildTopHeader(),
          Expanded(
            child: _isLoading && _merchandiseCategories.isEmpty
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
                          onRefresh: _fetchMerchandiseCategories,
                          child: _merchandiseCategories.isEmpty
                              ? ListView(
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.all(32.0),
                                      child: Center(child: Text(isThai ? 'ไม่มีข้อมูลหมวดหมู่สินค้า' : 'No Merchandise Categories')),
                                    )
                                  ],
                                )
                              : ListView.builder(
                                  itemCount: _merchandiseCategories.length,
                                  itemBuilder: (context, index) {
                                    final category = _merchandiseCategories[index];
                                    return _buildCategoryNode(category, 0);
                                  },
                                ),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
