class TemplateSelectValue {
  final String value;
  final String label;

  const TemplateSelectValue({required this.value, required this.label});

  Map<String, dynamic> toJson() => {'value': value, 'label': label};

  static TemplateSelectValue? fromJson(dynamic json) {
    if (json is! Map<String, dynamic>) return null;
    final v = json['value'];
    final l = json['label'];
    if (v is! String || l is! String) return null;
    return TemplateSelectValue(value: v, label: l);
  }
}

class SubmissionTemplateFields {
  final TemplateSelectValue? category;
  final TemplateSelectValue? theme;
  final TemplateSelectValue? species;
  final TemplateSelectValue? rating;
  final String? title;
  final String? description;
  final String? keywords;

  final String? folderName;
  final List<TemplateSelectValue>? folders;

  const SubmissionTemplateFields({
    this.category,
    this.theme,
    this.species,
    this.rating,
    this.title,
    this.description,
    this.keywords,
    this.folderName,
    this.folders,
  });

  Map<String, dynamic> toJson() => {
    'category': category?.toJson(),
    'theme': theme?.toJson(),
    'species': species?.toJson(),
    'rating': rating?.toJson(),
    'title': title,
    'description': description,
    'keywords': keywords,
    'folderName': folderName,
    'folders': folders?.map((e) => e.toJson()).toList(),
  };

  static SubmissionTemplateFields fromJson(Map<String, dynamic> json) {
    List<TemplateSelectValue>? folders;
    final foldersRaw = json['folders'];
    if (foldersRaw is List) {
      final out = <TemplateSelectValue>[];
      for (final x in foldersRaw) {
        final v = TemplateSelectValue.fromJson(x);
        if (v != null) out.add(v);
      }
      folders = out.isEmpty ? null : out;
    }

    return SubmissionTemplateFields(
      category: TemplateSelectValue.fromJson(json['category']),
      theme: TemplateSelectValue.fromJson(json['theme']),
      species: TemplateSelectValue.fromJson(json['species']),
      rating: TemplateSelectValue.fromJson(json['rating']),
      title: json['title'] is String ? json['title'] as String : null,
      description: json['description'] is String ? json['description'] as String : null,
      keywords: json['keywords'] is String ? json['keywords'] as String : null,
      folderName: json['folderName'] is String ? json['folderName'] as String : null,
      folders: folders,
    );
  }
}

class SubmissionTemplate {
  final String id;
  final String name;
  final int updatedAtMs;
  final SubmissionTemplateFields fields;

  const SubmissionTemplate({
    required this.id,
    required this.name,
    required this.updatedAtMs,
    required this.fields,
  });

  SubmissionTemplate copyWith({
    String? id,
    String? name,
    int? updatedAtMs,
    SubmissionTemplateFields? fields,
  }) {
    return SubmissionTemplate(
      id: id ?? this.id,
      name: name ?? this.name,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
      fields: fields ?? this.fields,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'updatedAtMs': updatedAtMs,
    'fields': fields.toJson(),
  };

  static SubmissionTemplate fromJson(Map<String, dynamic> json) {
    final id = (json['id'] is String) ? json['id'] as String : '';
    final name = (json['name'] is String) ? json['name'] as String : '';
    final updatedAtMs = (json['updatedAtMs'] is int) ? json['updatedAtMs'] as int : 0;
    final fieldsJson = (json['fields'] is Map<String, dynamic>)
        ? (json['fields'] as Map<String, dynamic>)
        : <String, dynamic>{};

    return SubmissionTemplate(
      id: id,
      name: name,
      updatedAtMs: updatedAtMs,
      fields: SubmissionTemplateFields.fromJson(fieldsJson),
    );
  }
}
