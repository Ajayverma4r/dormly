import 'package:dormly/features/tenancies/presentation/widgets/tenant_document_image.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final docs = [
    {'id': 'p1', 'doc_type': 'photo'},
    {'id': 'a1', 'doc_type': 'aadhaar'},
    {'id': '', 'doc_type': 'pan'},
  ];

  test('finds the stored document id by type', () {
    expect(storedDocumentId(docs, {'aadhaar', 'pan'}), 'a1');
    expect(storedDocumentId(docs, {'photo'}), 'p1');
  });

  test('ignores missing types and rows without an id', () {
    expect(storedDocumentId(docs, {'pan'}), isNull);
    expect(storedDocumentId(docs, {'address_proof'}), isNull);
    expect(storedDocumentId(const [], {'aadhaar'}), isNull);
  });

  test('accepts camelCase rows', () {
    expect(
      storedDocumentId([
        {'id': 'x', 'docType': 'AADHAAR'},
      ], {'aadhaar'}),
      'x',
    );
  });

  test('document refs with equal fields are the same provider key', () {
    const a = (propertyId: 'p', tenancyId: 't', documentId: 'd');
    const b = (propertyId: 'p', tenancyId: 't', documentId: 'd');
    expect(a, b);
    expect(tenantDocumentBytesProvider(a), tenantDocumentBytesProvider(b));
  });
}
