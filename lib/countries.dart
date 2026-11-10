class Country {
  final String iso;
  final String nameAr;
  final String dial;
  const Country(this.iso, this.nameAr, this.dial);

  String get label => '$nameAr (+$dial)';
}

/// Every account gets a phone number that starts with its country's dial code.
const List<Country> countries = [
  Country('EG', 'مصر', '20'),
  Country('SA', 'السعودية', '966'),
  Country('AE', 'الإمارات', '971'),
  Country('JO', 'الأردن', '962'),
  Country('LB', 'لبنان', '961'),
  Country('KW', 'الكويت', '965'),
  Country('QA', 'قطر', '974'),
  Country('BH', 'البحرين', '973'),
  Country('OM', 'عُمان', '968'),
  Country('IQ', 'العراق', '964'),
  Country('SY', 'سوريا', '963'),
  Country('PS', 'فلسطين', '970'),
  Country('YE', 'اليمن', '967'),
  Country('MA', 'المغرب', '212'),
  Country('DZ', 'الجزائر', '213'),
  Country('TN', 'تونس', '216'),
  Country('LY', 'ليبيا', '218'),
  Country('SD', 'السودان', '249'),
  Country('TR', 'تركيا', '90'),
  Country('US', 'أمريكا', '1'),
  Country('GB', 'بريطانيا', '44'),
  Country('DE', 'ألمانيا', '49'),
  Country('FR', 'فرنسا', '33'),
];
