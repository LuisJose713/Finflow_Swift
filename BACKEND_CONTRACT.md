# Contrato actual FinFlow iOS ↔ Spring Boot

Versión revisada el 7 de noviembre de 2026 contra los controladores del repositorio `LuisJose713/WS_FINFLOW`.

## Autenticación y transporte

- Base URL de producción, fija y HTTPS: `https://finflow-backend-yqhi.onrender.com`.
- `POST /auth/login`: `{email,password}` → `{token,user:{id,name,email,role}}`.
- `POST /auth/register`: `{name,email,password}` → misma forma; contraseña >=8, rol servidor USER.
- `GET /auth/me`: consulta autenticada que valida la sesión y devuelve el rol actual.
- Endpoints protegidos: `Authorization: Bearer <JWT>` desde Keychain.
- **No** enviar `X-User-Id`. Todos los recursos usan identidad derivada del token en Spring Security.
- No solicitar vida útil prolongada usando un header `X-Client-Type: mobile` (el backend no lo permite).

## Endpoints

| Vista / dominio | Método y ruta | Tipo de respuesta |
|---|---|---|
| Dashboard | GET /transactions/stats | TransactionStats |
| Movimientos | GET/POST /transactions | Lista/FinanceTransaction |
| Eliminar movimiento | DELETE /transactions/{id} | 204 |
| Filtros / años | GET /transactions?type&year&month&categoryId&search, GET /transactions/years | Transacciones / años |
| Exportaciones | GET /transactions/export/pdf, /transactions/export/csv | Data |
| Categorías visibles | GET /categories | `[{id,name,type,userId?,createdAt?}]` |
| Categorías personales | POST /categories, PUT/DELETE /categories/{id} | Category / 204; globales solo lectura |
| Metas | GET/POST /goals; PUT/DELETE /goals/{id} | Goal / 204 |
| Aportes | PATCH /goals/{id}/contribute | `{amount,note?}` → Goal |
| Historial de abonos | GET /goals/{id}/contributions | Lista de abonos |
| Estado meta | PATCH /goals/{id}/status | `{status}` → Goal |
| Presupuesto mensual | GET /budgets?year&month | BudgetOverview[] con `limitAmount,spent,remaining,percentUsed,status,currency` |
| Crear presupuesto | POST /budgets | `{categoryId,year,month,amount}` → MonthlyBudget |
| Editar límite | PUT /budgets/{id} | `{amount}` → MonthlyBudget |
| Eliminar presupuesto | DELETE /budgets/{id} | 204 |
| Gastos planificados | GET/POST /planned-expenses, PUT/DELETE /planned-expenses/{id} | PlannedExpense / 204 |
| Ejecutar / cancelar | PATCH /planned-expenses/{id}/execute, /cancel | PlannedExpense |
| Administración | GET /admin/overview | AdminOverview (solo ROLE_ADMIN), agregados, no finanzas de terceros |
| Verificar rol | GET /admin/verify | `{status,role}` |
| Asesor IA | POST /ai/chat | `{mensaje}` → `{respuesta}` |

## Mapeo importante

- `FinanceGoal.name` corresponde al `Goal.title` del backend.
- En una edición de meta se omite `currentAmount` para no sobrescribir los aportes existentes; el aporte se hace solo con PATCH.
- `BudgetOverview` se devuelve en GET; POST/PUT devuelve otra entidad `MonthlyBudget`, decodificada por su `id`.
- Categorías con `userId == null` son globales y no modificables desde la app.
- Tipos de categoría se comparan sin distinguir mayúsculas/minúsculas (`Expense`, `Income`).
- `TransactionRequest` no persiste `notes`; `Goal` no persiste icono.
- El gasto de presupuesto lo calcula Spring Boot para COP y solo operaciones de tipo expense completadas.

## No confundir compilación con despliegue

- Una compilación exitosa de Xcode valida el proyecto iOS; no demuestra que los últimos commits del backend ya estén en Render.
- La validación autenticada real (incluida separación entre usuarios) y la rotación de credenciales de producción continúan siendo requisitos.
- Cuentas/billeteras aún necesitan API backend antes de habilitar su gestión desde iOS.
- Ningún secret debe aparecer en GitHub, archivos de código o notas de ejecución.
