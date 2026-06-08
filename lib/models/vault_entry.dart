/// B2: tipe entry preset. Menentukan ikon, label, & saran field di form.
enum EntryType { login, card, bankAccount, identity, wifi, secureNote }

extension EntryTypeMeta on EntryType {
  /// id stabil untuk serialisasi (pakai nama enum).
  String get id => name;

  /// Label tampilan (Bahasa Indonesia).
  String get label {
    switch (this) {
      case EntryType.login:
        return 'Login';
      case EntryType.card:
        return 'Kartu';
      case EntryType.bankAccount:
        return 'Rekening Bank';
      case EntryType.identity:
        return 'Identitas';
      case EntryType.wifi:
        return 'WiFi';
      case EntryType.secureNote:
        return 'Catatan Aman';
    }
  }

  /// Parse dari id tersimpan; fallback ke login utk data lama / nilai asing.
  static EntryType fromId(String? id) {
    for (final t in EntryType.values) {
      if (t.name == id) return t;
    }
    return EntryType.login;
  }
}

/// B2: field tambahan bebas pada sebuah entry (label + nilai).
/// [secret] = nilai disembunyikan di UI & clipboard di-auto-clear saat disalin
/// (sama seperti password).
class CustomField {
  String label;
  String value;
  bool secret;

  CustomField({this.label = '', this.value = '', this.secret = false});

  Map<String, dynamic> toJson() => {
        'label': label,
        'value': value,
        'secret': secret,
      };

  factory CustomField.fromJson(Map<String, dynamic> json) => CustomField(
        label: json['label'] as String? ?? '',
        value: json['value'] as String? ?? '',
        secret: json['secret'] as bool? ?? false,
      );

  CustomField copy() =>
      CustomField(label: label, value: value, secret: secret);
}

/// Satu kredensial tersimpan (login, kartu, catatan aman, dll).
class VaultEntry {
  final String id;
  String title;
  String username;
  String password;
  String url;
  String notes;
  String totpSecret; // secret base32 untuk 2FA (opsional)
  String folder; // B1: kategori/folder tunggal (kosong = tanpa folder)
  List<String> tags; // B1: label bebas
  bool favorite; // B1: ditandai favorit
  EntryType type; // B2: tipe entry
  List<CustomField> customFields; // B2: field tambahan
  DateTime createdAt;
  DateTime updatedAt;

  VaultEntry({
    required this.id,
    required this.title,
    this.username = '',
    this.password = '',
    this.url = '',
    this.notes = '',
    this.totpSecret = '',
    this.folder = '',
    List<String>? tags,
    this.favorite = false,
    this.type = EntryType.login,
    List<CustomField>? customFields,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : tags = tags ?? <String>[],
        customFields = customFields ?? <CustomField>[],
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'username': username,
        'password': password,
        'url': url,
        'notes': notes,
        'totpSecret': totpSecret,
        'folder': folder,
        'tags': tags,
        'favorite': favorite,
        'type': type.id,
        'customFields': customFields.map((f) => f.toJson()).toList(),
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory VaultEntry.fromJson(Map<String, dynamic> json) => VaultEntry(
        id: json['id'] as String,
        title: json['title'] as String,
        username: json['username'] as String? ?? '',
        password: json['password'] as String? ?? '',
        url: json['url'] as String? ?? '',
        notes: json['notes'] as String? ?? '',
        totpSecret: json['totpSecret'] as String? ?? '', // aman utk data lama
        folder: json['folder'] as String? ?? '', // aman utk data lama
        tags: (json['tags'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            <String>[],
        favorite: json['favorite'] as bool? ?? false,
        type: EntryTypeMeta.fromId(json['type'] as String?), // aman utk data lama
        customFields: (json['customFields'] as List<dynamic>?)
                ?.map((e) =>
                    CustomField.fromJson(Map<String, dynamic>.from(e as Map)))
                .toList() ??
            <CustomField>[],
        createdAt: DateTime.parse(json['createdAt'] as String),
        updatedAt: DateTime.parse(json['updatedAt'] as String),
      );
}
