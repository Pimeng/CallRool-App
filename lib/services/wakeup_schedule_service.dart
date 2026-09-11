import 'quick_import/api_quick_import_backend.dart';
import 'quick_import/quick_import_backend.dart';

export 'quick_import/quick_import_backend.dart'
    show QuickImportBackend, QuickImportException, extractWakeUpShareCode;

@Deprecated('Use QuickImportException instead.')
typedef WakeUpScheduleException = QuickImportException;

@Deprecated('Use ApiQuickImportBackend through backend_binding.dart instead.')
class WakeUpScheduleService extends ApiQuickImportBackend {
  const WakeUpScheduleService();
}

@Deprecated('Use decodeQuickImportApiResponse instead.')
String decodeWakeUpShareResponse(String body) =>
    decodeQuickImportApiResponse(body);
