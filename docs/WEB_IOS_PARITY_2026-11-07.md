# FinFlow — paridad Web ↔ iOS (7 de noviembre de 2026)

## Principio
FinFlow iOS es una app **SwiftUI nativa**, no una web embebida. Usa el mismo backend Java/Spring Boot de la web en Render, que es la única autoridad para autenticación, roles, propiedad de registros, cálculos y presupuesto. Neon es la fuente de verdad y no se replica a mano en el iPhone.

## Matriz

| Módulo web | SwiftUI | Backend / estado | Observaciones |
|---|---|---|---|
| Registro / login | AuthView, SessionStore | POST /auth/register, /auth/login; GET /auth/me | Recuperación verificada por servidor, token en Keychain, clave >= 8 |
| Inicio / estadísticas | DashboardView | /transactions/stats, /transactions | Gráficos nativos Charts |
| Movimientos | TransactionsView | /transactions; PDF/CSV | Altas y eliminación online, caché cifrada de solo lectura sin conexión; no reintentos que dupliquen dinero |
| Metas | GoalsView | /goals y /goals/{id}/contribute | Edición no altera el saldo existente; los aportes son validados en cliente **y** servidor |
| Gastos planificados | PlannedExpensesView | /planned-expenses | Crear, editar, ejecutar, cancelar, eliminar |
| Categorías | CategoriesView | /categories | Sistema visible en modo lectura; CRUD solo propias; servidor valida propietario |
| Presupuestos mensuales | BudgetsView | /budgets | Periodo, categoría, límite, gasto agregado por backend, estado >=80%, exceso |
| Administrador | AdminView | /admin/overview | Menú visible solo con rol ADMIN actualizado por /auth/me. Server exige ROLE_ADMIN |
| Asesor IA | AdvisorView | /ai/chat | Depende de disponibilidad del servicio de IA |
| Apariencia / perfil | SettingsView | /auth/me | Soporta modo del sistema, claro y oscuro |
| Cuentas y billeteras | AccountsView | /accounts y /accounts/transfers | Saldos reales del servidor, crear, editar, archivar y transferir |
| Movimientos recurrentes | RecurringView | /recurring y /recurring/process-due | Crear, pausar, activar y ejecutar vencimientos idempotentes |
| Seguridad de cuenta | SecurityView | /auth/change-password y /auth/revoke-sessions | Cambio de contraseña y cierre global de sesiones |
| Historial de metas | GoalHistoryView | /goals/{id}/contributions | Listar aportes y actualizar estado |
| Notificaciones push | **No implementado** | Requiere APNs, permisos y flujo servidor | No simular alertas push |
| App Store / TestFlight | **Pendiente firma** | Apple Developer / App Store Connect | CI build Simulator sin firmar; IPA exige certificados y provisioning |

## Seguridad
- No se usa `X-User-Id`: el backend extrae el propietario a partir del JWT validado.
- No se usa un encabezado configurable para pedir tokens móviles de 30 días.
- El host de API HTTPS está fijado para impedir envío accidental de bearer a terceros.
- Keychain guarda tokens y la llave AES-GCM; UserDefaults solo mantiene caché cifrada.
- Los pendientes antiguos permanecen cifrados para revisión; no se reenvían POST tras fallos de red ambiguos hasta que el backend tenga un contrato de idempotencia.
- Recuperación de sesión obliga a validar `GET /auth/me`; rol administrativo nunca se confía a datos locales.
- No registrar tokens, passwords ni datos financieros sensibles en logs.
- El backend es responsable de impedir acceso entre usuarios y de validar aportes concurrentes.

## Verificación
- Código iOS: SwiftUI, iOS 17+, Xcode project `FinFlow.xcodeproj`.
- GitHub Actions: `.github/workflows/ios-ci.yml`, compila en macOS con Xcode para simulador sin firma.
- El check **debe estar verde** antes de fusionar y declarar compilación terminada.
- Además de compilar, queda pendiente QA visual de UI en simulador pequeño (iPhone SE/320-375 pt), Pro Max e iPad, login con cuentas aisladas, categorías, presupuestos, metas, admin, pruebas de red inestable.
- No se hacen cambios manuales en Neon ni se comparten contraseñas al validar el iOS.
- Para TestFlight se necesitan Team ID, bundle ID definitivo, firma de distribución y clave de API App Store Connect (configurados como secretos en GitHub).
- El backend de producción debe estar desplegado con las rutas nuevas; una compilación iOS correcta no garantiza que Render esté actualizado.

## Dependencias de fin de release P1 web
Véase: https://github.com/LuisJose713/WS_FINFLOW/issues/22

## Pull request iOS
Véase: https://github.com/LuisJose713/Finflow_Swift/pull/4
