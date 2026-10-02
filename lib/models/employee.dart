/// Employee profile returned by `GET /api/v1/me/`.
///
/// The backend serializer (EmployeeProfileSerializer) returns:
/// employee_no, full_name, first_name, last_name, department,
/// department_code, position, date_hired (nullable), is_fulltime,
/// employment_type ("FULL_TIME" / "PART_TIME"), username (login name), photo_url (nullable absolute
/// URL; changes with every upload, so it is a good cache key).
class Employee {
  final String employeeNo;
  final String fullName;
  final String firstName;
  final String lastName;
  final String department;
  final String departmentCode;
  final String position;
  final String? dateHired;
  final bool isFulltime;
  final String employmentType;

  /// The login name (starts as the lowercased employee number; can be changed).
  final String username;
  final String? photoUrl;

  const Employee({
    required this.employeeNo,
    required this.fullName,
    required this.firstName,
    required this.lastName,
    required this.department,
    required this.departmentCode,
    required this.position,
    this.dateHired,
    this.isFulltime = true,
    this.employmentType = 'FULL_TIME',
    this.username = '',
    this.photoUrl,
  });

  Employee copyWith({String? photoUrl, String? username}) => Employee(
    employeeNo: employeeNo,
    fullName: fullName,
    firstName: firstName,
    lastName: lastName,
    department: department,
    departmentCode: departmentCode,
    position: position,
    dateHired: dateHired,
    isFulltime: isFulltime,
    employmentType: employmentType,
    username: username ?? this.username,
    photoUrl: photoUrl ?? this.photoUrl,
  );

  factory Employee.fromJson(Map<String, dynamic> json) => Employee(
    employeeNo: (json['employee_no'] ?? '') as String,
    fullName: (json['full_name'] ?? '') as String,
    firstName: (json['first_name'] ?? '') as String,
    lastName: (json['last_name'] ?? '') as String,
    department: (json['department'] ?? '') as String,
    departmentCode: (json['department_code'] ?? '') as String,
    position: (json['position'] ?? '') as String,
    dateHired: json['date_hired'] as String?,
    isFulltime: (json['is_fulltime'] ?? true) as bool,
    employmentType: (json['employment_type'] ?? 'FULL_TIME') as String,
    username: (json['username'] ?? '') as String,
    photoUrl: json['photo_url'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'employee_no': employeeNo,
    'full_name': fullName,
    'first_name': firstName,
    'last_name': lastName,
    'department': department,
    'department_code': departmentCode,
    'position': position,
    'date_hired': dateHired,
    'is_fulltime': isFulltime,
    'employment_type': employmentType,
    'username': username,
    'photo_url': photoUrl,
  };
}
