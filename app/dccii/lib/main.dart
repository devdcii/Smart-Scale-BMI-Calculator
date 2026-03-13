import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';

// Hive Models
@HiveType(typeId: 0)
class UserData extends HiveObject {
  @HiveField(0)
  double height; // in cm

  @HiveField(1)
  double weight; // in kg

  @HiveField(2)
  int age;

  @HiveField(3)
  String gender; // 'male' or 'female'

  @HiveField(4)
  String activityLevel;

  @HiveField(5)
  DateTime lastUpdated;

  UserData({
    required this.height,
    required this.weight,
    required this.age,
    required this.gender,
    required this.activityLevel,
    required this.lastUpdated,
  });
}

// Generate adapter (normally done with build_runner)
class UserDataAdapter extends TypeAdapter<UserData> {
  @override
  final int typeId = 0;

  @override
  UserData read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return UserData(
      height: fields[0] as double,
      weight: fields[1] as double,
      age: fields[2] as int,
      gender: fields[3] as String,
      activityLevel: fields[4] as String,
      lastUpdated: fields[5] as DateTime,
    );
  }

  @override
  void write(BinaryWriter writer, UserData obj) {
    writer
      ..writeByte(6)
      ..writeByte(0)
      ..write(obj.height)
      ..writeByte(1)
      ..write(obj.weight)
      ..writeByte(2)
      ..write(obj.age)
      ..writeByte(3)
      ..write(obj.gender)
      ..writeByte(4)
      ..write(obj.activityLevel)
      ..writeByte(5)
      ..write(obj.lastUpdated);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is UserDataAdapter &&
              runtimeType == other.runtimeType &&
              typeId == other.typeId;
}

// Scale Service to handle ESP32 communication
class ScaleService {
  static const String defaultScaleIP = '192.168.4.1'; // ESP32 AP default IP
  String scaleIP;

  ScaleService({this.scaleIP = defaultScaleIP});

  Future<Map<String, dynamic>?> getWeight() async {
    try {
      final response = await http.get(
        Uri.parse('http://$scaleIP/weight'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(Duration(seconds: 5));

      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
    } catch (e) {
      print('Error getting weight: $e');
    }
    return null;
  }

  Future<bool> tareScale() async {
    try {
      final response = await http.post(
        Uri.parse('http://$scaleIP/tare'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(Duration(seconds: 10));

      return response.statusCode == 200;
    } catch (e) {
      print('Error taring scale: $e');
      return false;
    }
  }

  Future<Map<String, dynamic>?> getStatus() async {
    try {
      final response = await http.get(
        Uri.parse('http://$scaleIP/status'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(Duration(seconds: 5));

      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
    } catch (e) {
      print('Error getting status: $e');
    }
    return null;
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  Hive.registerAdapter(UserDataAdapter());
  await Hive.openBox<UserData>('userData');
  runApp(SmartScaleBMIApp());
}

class SmartScaleBMIApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Scale BMI Calculator',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        fontFamily: 'SF Pro Display',
      ),
      home: MainScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

// Weight stability tracker for auto weight updates
class WeightStabilityTracker {
  final List<double> _readings = [];
  final int maxReadings = 5;
  final double threshold = 0.1; // kg tolerance

  void addReading(double weight) {
    _readings.add(weight);
    if (_readings.length > maxReadings) {
      _readings.removeAt(0);
    }
  }

  bool get isStable {
    if (_readings.length < 3) return false;

    final latest = _readings.sublist(_readings.length - 3);
    final avg = latest.reduce((a, b) => a + b) / latest.length;

    return latest.every((weight) => (weight - avg).abs() <= threshold);
  }

  double get stableWeight {
    if (!isStable) return 0.0;
    return _readings.sublist(_readings.length - 3).reduce((a, b) => a + b) / 3;
  }

  void reset() {
    _readings.clear();
  }
}

class MainScreen extends StatefulWidget {
  @override
  _MainScreenState createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;
  late Box<UserData> userBox;
  UserData? currentUser;
  final ScaleService scaleService = ScaleService();
  final WeightStabilityTracker weightTracker = WeightStabilityTracker();

  @override
  void initState() {
    super.initState();
    userBox = Hive.box<UserData>('userData');
    loadUserData();
  }

  void loadUserData() {
    if (userBox.isNotEmpty) {
      setState(() {
        currentUser = userBox.getAt(0);
      });
    }
  }

  void saveUserData(UserData userData) {
    if (userBox.isEmpty) {
      userBox.add(userData);
    } else {
      userBox.putAt(0, userData);
    }
    setState(() {
      currentUser = userData;
    });
  }

  void updateWeightFromScale(double weight) {
    weightTracker.addReading(weight);

    if (weightTracker.isStable && currentUser != null) {
      final stableWeight = weightTracker.stableWeight;
      final updatedUser = UserData(
        height: currentUser!.height,
        weight: stableWeight,
        age: currentUser!.age,
        gender: currentUser!.gender,
        activityLevel: currentUser!.activityLevel,
        lastUpdated: DateTime.now(),
      );
      saveUserData(updatedUser);
      weightTracker.reset(); // Reset after updating profile
    }
  }

  void showAboutDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'About Smart Scale BMI',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Smart Scale BMI Calculator with ESP32 Integration',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: 15),
            Text(
              'Developers:',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: 8),
            Text(
              '• Canlas, Adrian S.\n• Digman, Christian D.\n• Paragas, John Ian Joseph M.',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
                height: 1.4,
              ),
            ),
            SizedBox(height: 15),
            Text(
              'Features:',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: 8),
            Text(
              '• Real-time weight measurement\n• BMI calculation\n• Calorie recommendations\n• ESP32 scale integration\n• Auto weight sync to profile',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
                height: 1.4,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            child: Text('OK'),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          DashboardScreen(
            userData: currentUser,
            scaleService: scaleService,
            onAbout: showAboutDialog,
            onWeightUpdate: updateWeightFromScale,
          ),
          ProfileScreen(
            userData: currentUser,
            onSave: saveUserData,
            onAbout: showAboutDialog,
            scaleService: scaleService,
          ),
          CalorieScreen(
            userData: currentUser,
            onAbout: showAboutDialog,
          ),
          ScaleScreen(
            scaleService: scaleService,
            onAbout: showAboutDialog,
          ),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 10,
              offset: Offset(0, -5),
            ),
          ],
        ),
        child: BottomNavigationBar(
          currentIndex: _selectedIndex,
          onTap: (index) => setState(() => _selectedIndex = index),
          type: BottomNavigationBarType.fixed,
          backgroundColor: Colors.white,
          elevation: 0,
          selectedItemColor: Colors.blue[900],
          unselectedItemColor: Colors.grey[400],
          selectedLabelStyle: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
          unselectedLabelStyle: TextStyle(fontSize: 12),
          items: [
            BottomNavigationBarItem(
              icon: Icon(Icons.dashboard_rounded, size: 24),
              label: 'Dashboard',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.person_rounded, size: 24),
              label: 'Profile',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.local_fire_department_rounded, size: 24),
              label: 'Calories',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.scale_rounded, size: 24),
              label: 'Scale',
            ),
          ],
        ),
      ),
    );
  }
}

class DashboardScreen extends StatefulWidget {
  final UserData? userData;
  final ScaleService scaleService;
  final VoidCallback onAbout;
  final Function(double) onWeightUpdate;

  DashboardScreen({
    required this.userData,
    required this.scaleService,
    required this.onAbout,
    required this.onWeightUpdate,
  });

  @override
  _DashboardScreenState createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  double? currentWeight;
  bool isConnected = false;
  Timer? weightTimer;

  @override
  void initState() {
    super.initState();
    startWeightUpdates();
  }

  @override
  void dispose() {
    weightTimer?.cancel();
    super.dispose();
  }

  void startWeightUpdates() {
    weightTimer = Timer.periodic(Duration(seconds: 2), (timer) async {
      final weightData = await widget.scaleService.getWeight();
      if (weightData != null && mounted) {
        setState(() {
          currentWeight = weightData['weight']?.toDouble();
          isConnected = true;
        });
        if (currentWeight != null) {
          widget.onWeightUpdate(currentWeight!);
        }
      } else if (mounted) {
        setState(() {
          isConnected = false;
        });
      }
    });
  }

  double calculateBMI(double weight, double height) {
    return weight / ((height / 100) * (height / 100));
  }

  String getBMICategory(double bmi) {
    if (bmi < 18.5) return 'Underweight';
    if (bmi < 25.0) return 'Normal';
    if (bmi < 30.0) return 'Overweight';
    return 'Obese';
  }

  Color getBMIColor(double bmi) {
    if (bmi < 18.5) return Colors.blue[400]!;
    if (bmi < 25.0) return Colors.green;
    if (bmi < 30.0) return Colors.orange;
    return Colors.red;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.grey[50],
      child: SafeArea(
        child: CustomScrollView(
          slivers: [
            // Clean App Bar
            SliverAppBar(
              expandedHeight: 100,
              floating: false,
              pinned: true,
              backgroundColor: Colors.white,
              elevation: 0,
              flexibleSpace: FlexibleSpaceBar(
                background: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Colors.blue[900]!, Colors.black87],
                    ),
                  ),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(20, 40, 20, 20),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text(
                              'Dashboard',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            Container(
                              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: isConnected ? Colors.green : Colors.red,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  SizedBox(width: 6),
                                  Text(
                                    isConnected ? 'Online' : 'Offline',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(width: 10),
                            IconButton(
                              onPressed: widget.onAbout,
                              icon: Icon(Icons.info_outline, color: Colors.white),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            if (widget.userData == null)
              SliverFillRemaining(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: EdgeInsets.all(30),
                        decoration: BoxDecoration(
                          color: Colors.blue[50],
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.person_add_rounded,
                          size: 60,
                          color: Colors.blue[700],
                        ),
                      ),
                      SizedBox(height: 30),
                      Text(
                        'Set up your profile first',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      SizedBox(height: 10),
                      Text(
                        'We need your information to calculate BMI',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey[600],
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              )
            else
              SliverPadding(
                padding: EdgeInsets.all(20),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    // Current Weight Card - Clean Design
                    Container(
                      padding: EdgeInsets.all(30),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.04),
                            blurRadius: 10,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Current Weight',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey[600],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          SizedBox(height: 12),
                          Text(
                            currentWeight != null
                                ? '${currentWeight!.toStringAsFixed(1)} kg'
                                : '${widget.userData!.weight.toStringAsFixed(1)} kg',
                            style: TextStyle(
                              fontSize: 42,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue[900],
                            ),
                          ),
                          if (currentWeight != null) ...[
                            SizedBox(height: 8),
                            Container(
                              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.green[50],
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                'Live from scale',
                                style: TextStyle(
                                  color: Colors.green[700],
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),

                    SizedBox(height: 20),

                    // BMI Card - Minimalist Design
                    if (currentWeight != null || widget.userData != null)
                      Builder(
                        builder: (context) {
                          final weight = currentWeight ?? widget.userData!.weight;
                          final bmi = calculateBMI(weight, widget.userData!.height);
                          final category = getBMICategory(bmi);
                          final color = getBMIColor(bmi);

                          return Container(
                            padding: EdgeInsets.all(30),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.04),
                                  blurRadius: 10,
                                  offset: Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Body Mass Index',
                                          style: TextStyle(
                                            fontSize: 16,
                                            color: Colors.grey[600],
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        SizedBox(height: 8),
                                        Container(
                                          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                          decoration: BoxDecoration(
                                            color: color.withOpacity(0.1),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Text(
                                            category,
                                            style: TextStyle(
                                              color: color,
                                              fontWeight: FontWeight.w600,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    Text(
                                      bmi.toStringAsFixed(1),
                                      style: TextStyle(
                                        fontSize: 42,
                                        fontWeight: FontWeight.bold,
                                        color: color,
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(height: 24),
                                // Simple progress bar
                                Container(
                                  height: 6,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(3),
                                    color: Colors.grey[200],
                                  ),
                                  child: FractionallySizedBox(
                                    widthFactor: (bmi / 35).clamp(0.0, 1.0),
                                    alignment: Alignment.centerLeft,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(3),
                                        color: color,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),

                    SizedBox(height: 20),

                    // Quick Stats - Grid Layout
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            padding: EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.04),
                                  blurRadius: 10,
                                  offset: Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Height',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey[600],
                                  ),
                                ),
                                SizedBox(height: 8),
                                Text(
                                  '${widget.userData!.height.toInt()} cm',
                                  style: TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black87,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        SizedBox(width: 16),
                        Expanded(
                          child: Container(
                            padding: EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.04),
                                  blurRadius: 10,
                                  offset: Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Age',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey[600],
                                  ),
                                ),
                                SizedBox(height: 8),
                                Text(
                                  '${widget.userData!.age} yrs',
                                  style: TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black87,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ]),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class ProfileScreen extends StatefulWidget {
  final UserData? userData;
  final Function(UserData) onSave;
  final VoidCallback onAbout;
  final ScaleService scaleService;

  ProfileScreen({
    required this.userData,
    required this.onSave,
    required this.onAbout,
    required this.scaleService,
  });

  @override
  _ProfileScreenState createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late TextEditingController heightController;
  late TextEditingController ageController;
  String selectedGender = 'male';
  String selectedActivity = 'moderate';

  double? liveWeight;
  bool isConnected = false;
  Timer? weightTimer;
  final WeightStabilityTracker weightTracker = WeightStabilityTracker();

  final List<String> activityLevels = [
    'sedentary',
    'light',
    'moderate',
    'active',
    'very_active'
  ];

  final Map<String, String> activityLabels = {
    'sedentary': 'Sedentary',
    'light': 'Light Activity',
    'moderate': 'Moderate',
    'active': 'Active',
    'very_active': 'Very Active',
  };

  @override
  void initState() {
    super.initState();
    heightController = TextEditingController(
      text: widget.userData?.height.toString() ?? '',
    );
    ageController = TextEditingController(
      text: widget.userData?.age.toString() ?? '',
    );
    if (widget.userData != null) {
      selectedGender = widget.userData!.gender;
      selectedActivity = widget.userData!.activityLevel;
    }

    startWeightMonitoring();
  }

  @override
  void dispose() {
    weightTimer?.cancel();
    heightController.dispose();
    ageController.dispose();
    super.dispose();
  }

  void startWeightMonitoring() {
    weightTimer = Timer.periodic(Duration(seconds: 2), (timer) async {
      final weightData = await widget.scaleService.getWeight();
      if (weightData != null && mounted) {
        setState(() {
          liveWeight = weightData['weight']?.toDouble();
          isConnected = true;
        });

        if (liveWeight != null) {
          weightTracker.addReading(liveWeight!);
        }
      } else if (mounted) {
        setState(() {
          isConnected = false;
        });
      }
    });
  }

  void showActivityDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Activity Level'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: activityLevels.map((level) {
            return ListTile(
              title: Text(activityLabels[level]!),
              leading: Radio<String>(
                value: level,
                groupValue: selectedActivity,
                onChanged: (value) {
                  setState(() {
                    selectedActivity = value!;
                  });
                  Navigator.pop(context);
                },
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  void saveProfile() {
    if (heightController.text.isEmpty || ageController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please fill in height and age fields'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Use current weight from profile or default weight if no profile exists yet
    double weightToSave = widget.userData?.weight ?? 50.0; // Default 50kg if no weight exists

    final userData = UserData(
      height: double.parse(heightController.text),
      weight: weightToSave,
      age: int.parse(ageController.text),
      gender: selectedGender,
      activityLevel: selectedActivity,
      lastUpdated: DateTime.now(),
    );

    widget.onSave(userData);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Profile saved successfully! Weight will sync from scale.'),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.grey[50],
      child: SafeArea(
        child: CustomScrollView(
          slivers: [
            // Clean App Bar
            SliverAppBar(
              expandedHeight: 100,
              floating: false,
              pinned: true,
              backgroundColor: Colors.white,
              elevation: 0,
              flexibleSpace: FlexibleSpaceBar(
                background: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Colors.blue[900]!, Colors.black87],
                    ),
                  ),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(20, 40, 20, 20),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text(
                              'Profile',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        IconButton(
                          onPressed: widget.onAbout,
                          icon: Icon(Icons.info_outline, color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            SliverPadding(
              padding: EdgeInsets.all(20),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  // Live Weight Card
                  if (liveWeight != null)
                    Container(
                      padding: EdgeInsets.all(24),
                      margin: EdgeInsets.only(bottom: 20),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Colors.blue[900]!, Colors.black87],
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 10,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.scale, color: Colors.white, size: 32),
                          SizedBox(width: 16),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Live from Scale',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 14,
                                ),
                              ),
                              Text(
                                '${liveWeight!.toStringAsFixed(1)} kg',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          Spacer(),
                          Column(
                            children: [
                              Container(
                                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.green,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  'Connected',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              SizedBox(height: 8),
                              if (weightTracker.isStable)
                                Container(
                                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.orange,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    'Stable - Updating...',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),

                  // Profile Form
                  Container(
                    padding: EdgeInsets.all(30),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.04),
                          blurRadius: 10,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Personal Information',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        SizedBox(height: 24),

                        // Height Field
                        _buildInputField(
                          label: 'Height (cm)',
                          controller: heightController,
                          keyboardType: TextInputType.number,
                          icon: Icons.height,
                        ),
                        SizedBox(height: 20),

                        // Weight Field - READ ONLY
                        _buildWeightField(),
                        SizedBox(height: 20),

                        // Age Field
                        _buildInputField(
                          label: 'Age',
                          controller: ageController,
                          keyboardType: TextInputType.number,
                          icon: Icons.cake_outlined,
                        ),
                        SizedBox(height: 20),

                        // Gender Selection
                        Text(
                          'Gender',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: Colors.black87,
                          ),
                        ),
                        SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: _buildGenderOption('Male', 'male'),
                            ),
                            SizedBox(width: 12),
                            Expanded(
                              child: _buildGenderOption('Female', 'female'),
                            ),
                          ],
                        ),

                        SizedBox(height: 20),

                        // Activity Level
                        Text(
                          'Activity Level',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: Colors.black87,
                          ),
                        ),
                        SizedBox(height: 8),
                        GestureDetector(
                          onTap: showActivityDialog,
                          child: Container(
                            padding: EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey[300]!),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.fitness_center, color: Colors.grey[600]),
                                SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    activityLabels[selectedActivity]!,
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: Colors.black87,
                                    ),
                                  ),
                                ),
                                Icon(Icons.arrow_drop_down, color: Colors.grey[600]),
                              ],
                            ),
                          ),
                        ),

                        SizedBox(height: 30),

                        // Save Button
                        Container(
                          width: double.infinity,
                          height: 54,
                          child: ElevatedButton(
                            onPressed: saveProfile,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue[900],
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 0,
                            ),
                            child: Text(
                              'Save Profile',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputField({
    required String label,
    required TextEditingController controller,
    required TextInputType keyboardType,
    required IconData icon,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: Colors.black87,
          ),
        ),
        SizedBox(height: 8),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          decoration: InputDecoration(
            prefixIcon: Icon(icon, color: Colors.grey[600]),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey[300]!),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey[300]!),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.blue[900]!, width: 2),
            ),
            filled: true,
            fillColor: Colors.grey[50],
            contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          ),
        ),
      ],
    );
  }

  Widget _buildWeightField() {
    final currentWeight = widget.userData?.weight ?? 0.0;
    final displayWeight = liveWeight ?? currentWeight;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Weight (kg)',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Colors.black87,
              ),
            ),
          ],
        ),
        SizedBox(height: 8),
        Container(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey[300]!),
          ),
          child: Row(
            children: [
              Icon(Icons.monitor_weight, color: Colors.grey[500]),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  displayWeight > 0
                      ? '${displayWeight.toStringAsFixed(1)} kg'
                      : 'Step on scale to measure',
                  style: TextStyle(
                    fontSize: 16,
                    color: displayWeight > 0 ? Colors.black87 : Colors.grey[500],
                    fontWeight: displayWeight > 0 ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
              if (liveWeight != null)
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green[100],
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'Live',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.green[800],
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (displayWeight == 0.0)
          Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              'Weight will automatically update when you step on the scale and it stabilizes for 3 seconds',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildGenderOption(String label, String value) {
    final isSelected = selectedGender == value;
    return GestureDetector(
      onTap: () => setState(() => selectedGender = value),
      child: Container(
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blue[900] : Colors.grey[100],
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: isSelected ? Colors.white : Colors.black87,
          ),
        ),
      ),
    );
  }
}

class CalorieScreen extends StatelessWidget {
  final UserData? userData;
  final VoidCallback onAbout;

  CalorieScreen({required this.userData, required this.onAbout});

  double calculateBMR(UserData userData) {
    if (userData.gender == 'male') {
      return 88.362 + (13.397 * userData.weight) + (4.799 * userData.height) - (5.677 * userData.age);
    } else {
      return 447.593 + (9.247 * userData.weight) + (3.098 * userData.height) - (4.330 * userData.age);
    }
  }

  double calculateTDEE(double bmr, String activityLevel) {
    Map<String, double> multipliers = {
      'sedentary': 1.2,
      'light': 1.375,
      'moderate': 1.55,
      'active': 1.725,
      'very_active': 1.9,
    };
    return bmr * (multipliers[activityLevel] ?? 1.55);
  }

  Map<String, double> calculateCalorieGoals(double tdee) {
    return {
      'lose_1': tdee - 1000,
      'lose_0_5': tdee - 500,
      'maintain': tdee,
      'gain_0_5': tdee + 500,
      'gain_1': tdee + 1000,
    };
  }

  @override
  Widget build(BuildContext context) {
    if (userData == null) {
      return Container(
        color: Colors.grey[50],
        child: SafeArea(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: EdgeInsets.all(30),
                  decoration: BoxDecoration(
                    color: Colors.orange[50],
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.local_fire_department_rounded,
                    size: 60,
                    color: Colors.orange[700],
                  ),
                ),
                SizedBox(height: 30),
                Text(
                  'Set up your profile first',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                SizedBox(height: 10),
                Text(
                  'We need your information to calculate calories',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey[600],
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }

    final bmr = calculateBMR(userData!);
    final tdee = calculateTDEE(bmr, userData!.activityLevel);
    final calorieGoals = calculateCalorieGoals(tdee);

    return Container(
      color: Colors.grey[50],
      child: SafeArea(
        child: CustomScrollView(
          slivers: [
            // Clean App Bar
            SliverAppBar(
              expandedHeight: 100,
              floating: false,
              pinned: true,
              backgroundColor: Colors.white,
              elevation: 0,
              flexibleSpace: FlexibleSpaceBar(
                background: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Colors.blue[900]!, Colors.black87],
                    ),
                  ),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(20, 40, 20, 20),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text(
                              'Calories',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        IconButton(
                          onPressed: onAbout,
                          icon: Icon(Icons.info_outline, color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            SliverPadding(
              padding: EdgeInsets.all(20),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  // BMR and TDEE Cards
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.04),
                                blurRadius: 10,
                                offset: Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'BMR',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey[600],
                                ),
                              ),
                              SizedBox(height: 8),
                              Text(
                                '${bmr.toStringAsFixed(0)}',
                                style: TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                ),
                              ),
                              Text(
                                'cal/day',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(width: 16),
                      Expanded(
                        child: Container(
                          padding: EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.04),
                                blurRadius: 10,
                                offset: Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'TDEE',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey[600],
                                ),
                              ),
                              SizedBox(height: 8),
                              Text(
                                '${tdee.toStringAsFixed(0)}',
                                style: TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.orange[600],
                                ),
                              ),
                              Text(
                                'cal/day',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),

                  SizedBox(height: 24),

                  // Calorie Goals Card
                  Container(
                    padding: EdgeInsets.all(30),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.04),
                          blurRadius: 10,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Daily Calorie Goals',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        SizedBox(height: 20),

                        _buildCalorieGoalItem(
                          'Lose 1 kg/week',
                          '${calorieGoals['lose_1']!.toStringAsFixed(0)} cal',
                          Colors.red[400]!,
                        ),
                        SizedBox(height: 12),
                        _buildCalorieGoalItem(
                          'Lose 0.5 kg/week',
                          '${calorieGoals['lose_0_5']!.toStringAsFixed(0)} cal',
                          Colors.orange[400]!,
                        ),
                        SizedBox(height: 12),
                        _buildCalorieGoalItem(
                          'Maintain Weight',
                          '${calorieGoals['maintain']!.toStringAsFixed(0)} cal',
                          Colors.blue[600]!,
                          isHighlighted: true,
                        ),
                        SizedBox(height: 12),
                        _buildCalorieGoalItem(
                          'Gain 0.5 kg/week',
                          '${calorieGoals['gain_0_5']!.toStringAsFixed(0)} cal',
                          Colors.green[500]!,
                        ),
                        SizedBox(height: 12),
                        _buildCalorieGoalItem(
                          'Gain 1 kg/week',
                          '${calorieGoals['gain_1']!.toStringAsFixed(0)} cal',
                          Colors.green[700]!,
                        ),
                      ],
                    ),
                  ),

                  SizedBox(height: 24),

                  // Macronutrient Card
                  Container(
                    padding: EdgeInsets.all(30),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.04),
                          blurRadius: 10,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Macronutrients',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Based on ${tdee.toStringAsFixed(0)} cal/day',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                          ),
                        ),
                        SizedBox(height: 20),

                        _buildMacroItem(
                          'Protein',
                          '${(tdee * 0.25 / 4).toStringAsFixed(0)}g',
                          '25%',
                          Colors.blue[600]!,
                        ),
                        SizedBox(height: 16),
                        _buildMacroItem(
                          'Carbs',
                          '${(tdee * 0.45 / 4).toStringAsFixed(0)}g',
                          '45%',
                          Colors.orange[500]!,
                        ),
                        SizedBox(height: 16),
                        _buildMacroItem(
                          'Fats',
                          '${(tdee * 0.30 / 9).toStringAsFixed(0)}g',
                          '30%',
                          Colors.green[500]!,
                        ),
                      ],
                    ),
                  ),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCalorieGoalItem(String title, String calories, Color color, {bool isHighlighted = false}) {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isHighlighted ? color.withOpacity(0.1) : Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: isHighlighted ? Border.all(color: color, width: 2) : null,
      ),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Colors.black87,
              ),
            ),
          ),
          Text(
            calories,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMacroItem(String name, String grams, String percentage, Color color) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 32,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$name ($percentage)',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            grams,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}

class ScaleScreen extends StatefulWidget {
  final ScaleService scaleService;
  final VoidCallback onAbout;

  ScaleScreen({required this.scaleService, required this.onAbout});

  @override
  _ScaleScreenState createState() => _ScaleScreenState();
}

class _ScaleScreenState extends State<ScaleScreen> {
  double? currentWeight;
  bool isConnected = false;
  bool isTaring = false;
  Timer? weightTimer;
  Map<String, dynamic>? scaleStatus;

  @override
  void initState() {
    super.initState();
    startWeightUpdates();
    getScaleStatus();
  }

  @override
  void dispose() {
    weightTimer?.cancel();
    super.dispose();
  }

  void startWeightUpdates() {
    weightTimer = Timer.periodic(Duration(seconds: 2), (timer) async {
      await updateWeight();
    });
  }

  Future<void> updateWeight() async {
    final weightData = await widget.scaleService.getWeight();
    if (weightData != null && mounted) {
      setState(() {
        currentWeight = weightData['weight']?.toDouble();
        isConnected = true;
      });
    } else if (mounted) {
      setState(() {
        isConnected = false;
      });
    }
  }

  Future<void> tareScale() async {
    setState(() => isTaring = true);
    final success = await widget.scaleService.tareScale();
    setState(() => isTaring = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(success ? 'Scale reset successfully!' : 'Failed to reset scale'),
        backgroundColor: success ? Colors.green : Colors.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );

    if (success) {
      await Future.delayed(Duration(seconds: 2));
      await updateWeight();
    }
  }

  Future<void> getScaleStatus() async {
    final status = await widget.scaleService.getStatus();
    if (status != null && mounted) {
      setState(() {
        scaleStatus = status;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.grey[50],
      child: SafeArea(
        child: CustomScrollView(
          slivers: [
            // Clean App Bar
            SliverAppBar(
              expandedHeight: 100,
              floating: false,
              pinned: true,
              backgroundColor: Colors.white,
              elevation: 0,
              flexibleSpace: FlexibleSpaceBar(
                background: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Colors.blue[900]!, Colors.black87],
                    ),
                  ),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(20, 40, 20, 20),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text(
                              'Scale',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        IconButton(
                          onPressed: widget.onAbout,
                          icon: Icon(Icons.info_outline, color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            SliverPadding(
              padding: EdgeInsets.all(20),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  // Connection Status Card
                  Container(
                    padding: EdgeInsets.all(30),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.04),
                          blurRadius: 10,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: isConnected ? Colors.green : Colors.red,
                            shape: BoxShape.circle,
                          ),
                        ),
                        SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                isConnected ? 'Scale Connected' : 'Scale Offline',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                ),
                              ),
                              Text(
                                isConnected ? 'Receiving live data' : 'Check ESP32 connection',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  SizedBox(height: 24),

                  // Live Weight Display
                  Container(
                    padding: EdgeInsets.all(40),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Colors.blue[900]!, Colors.black87],
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 10,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Text(
                          'Live Weight',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        SizedBox(height: 16),
                        Text(
                          currentWeight != null
                              ? '${currentWeight!.toStringAsFixed(2)} kg'
                              : '---.-- kg',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 48,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 12),
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            isConnected ? 'Real-time' : 'Disconnected',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  SizedBox(height: 24),

                  // Control Buttons
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          height: 54,
                          child: ElevatedButton(
                            onPressed: isTaring ? null : tareScale,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: Colors.blue[900],
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 0,
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if (isTaring) ...[
                                  SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation(Colors.blue[900]),
                                    ),
                                  ),
                                  SizedBox(width: 12),
                                  Text('Resetting...'),
                                ] else ...[
                                  Icon(Icons.settings_backup_restore, size: 20),
                                  SizedBox(width: 8),
                                  Text(
                                    'Reset Scale',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                      SizedBox(width: 16),
                      Expanded(
                        child: Container(
                          height: 54,
                          child: ElevatedButton(
                            onPressed: () async {
                              await updateWeight();
                              await getScaleStatus();
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue[900],
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 0,
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.refresh, size: 20),
                                SizedBox(width: 8),
                                Text(
                                  'Refresh',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),

                  SizedBox(height: 24),

                  // Scale Status (if available)
                  if (scaleStatus != null && isConnected)
                    Container(
                      padding: EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.04),
                            blurRadius: 10,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Scale Status',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                          SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: _buildStatusItem(
                                  'Uptime',
                                  '${(scaleStatus!['uptime'] / 1000 / 60).toStringAsFixed(0)}m',
                                  Colors.blue[600]!,
                                ),
                              ),
                              Expanded(
                                child: _buildStatusItem(
                                  'Clients',
                                  '${scaleStatus!['clients_connected']}',
                                  Colors.green[600]!,
                                ),
                              ),
                              Expanded(
                                child: _buildStatusItem(
                                  'Sensor',
                                  scaleStatus!['hx711_ready'] ? 'Ready' : 'Error',
                                  scaleStatus!['hx711_ready'] ? Colors.green[600]! : Colors.red[600]!,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                  if (scaleStatus != null && isConnected) SizedBox(height: 24),

                  // Tips Card
                  Container(
                    padding: EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.blue[100]!, width: 1),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.lightbulb_outline, color: Colors.blue[700], size: 20),
                            SizedBox(width: 8),
                            Text(
                              'Scale Tips',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.blue[800],
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 12),
                        Text(
                          '• Place scale on flat, hard surface\n'
                              '• Step on center for accurate reading\n'
                              '• Wait for reading to stabilize\n'
                              '• Use "Reset" to zero the scale\n'
                              '• Weight automatically syncs to profile',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.blue[700],
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }
}