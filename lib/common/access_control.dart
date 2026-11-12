import 'package:fl_clash/models/models.dart';

AccessControlProps sortedAccessControl(AccessControlProps value) {
  return value.copyWith(
    acceptList: value.acceptList.toSet().toList()..sort(),
    rejectList: value.rejectList.toSet().toList()..sort(),
  );
}

AccessControlProps selectVisibleApplications(
  AccessControlProps value,
  List<Package> packages,
  Set<String> chinaPackages,
) {
  final visible = packages
      .getViewList(
        pinedList: [],
        sortType: value.sort,
        isFilterSystemApp: value.isFilterSystemApp,
        isFilterNonInternetApp: value.isFilterNonInternetApp,
      )
      .map((item) => item.packageName)
      .toSet();
  return value.copyWith(
    acceptList: {
      ...value.acceptList.where((item) => !visible.contains(item)),
      ...visible.where((item) => !chinaPackages.contains(item)),
    }.toList(),
    rejectList: {
      ...value.rejectList.where((item) => !visible.contains(item)),
      ...visible.where(chinaPackages.contains),
    }.toList(),
  );
}

List<String> parseAccessPackageNames(String text) {
  final pattern = RegExp(r'^[a-zA-Z]\w*(\.[a-zA-Z]\w*)+$');
  return text
      .split('\n')
      .map((line) => line.trim())
      .where(pattern.hasMatch)
      .toSet()
      .toList();
}
