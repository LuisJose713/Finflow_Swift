# Contrato de integración Frontend ↔ WS_FINFLOW

Este documento se basa en los controladores, DTO y entidades del ZIP `WS_FINFLOW-master` proporcionado para esta migración. No incluye credenciales ni archivos de entorno.

## Contexto HTTP

- Base URL inicial: `https://finflow-backend-yqhi.onrender.com`.
- Login y registro envían `X-Client-Type: mobile`.
- Peticiones autenticadas envían `Authorization: Bearer <JWT>`.
- La app también envía `X-User-Id` obtenido de la respuesta de autenticación porque los controladores de metas y gastos planificados lo requieren explícitamente.
- JSON usa los nombres de propiedades de Java tal como se serializan con Jackson.

## Endpoints usados

| Función | Método y ruta | Contrato esperado |
|---|---|---|
| Login | `POST /auth/login` | `{email,password}` → `{token,user:{id,name,email}}` |
| Registro | `POST /auth/register` | `{name,email,password}` → `{token,user:{id,name,email}}` |
| Usuario actual | `GET /auth/me` | `{id,name,email}` |
| Categorías | `GET /categories` | Lista de `{id,name,type,createdAt}` |
| Dashboard | `GET /transactions/stats` | `totalIncome,totalExpenses,balance,savingsRate,monthlyData,categoryData` |
| Movimientos | `GET /transactions` | Lista de entidades `Transaction`; filtros opcionales `type,month,year,categoryId,search` |
| Crear movimiento | `POST /transactions` | `amount,type,categoryId,description,date,currency,status` |
| Eliminar movimiento | `DELETE /transactions/{id}` | HTTP 204 |
| Años disponibles | `GET /transactions/years` | Lista de enteros |
| Exportar CSV | `GET /transactions/export/csv` | Archivo CSV binario/texto |
| Exportar PDF | `GET /transactions/export/pdf` | Archivo PDF binario |
| Metas | `GET/POST /goals` | Lista/entidad `Goal`; `GoalRequest` acepta `title,targetAmount,currentAmount,deadline,description,status` |
| Actualizar meta | `PUT /goals/{id}` | `GoalRequest` |
| Aportar a meta | `PATCH /goals/{id}/contribute` | `{amount,note?}` |
| Historial de aportes | `GET /goals/{id}/contributions` | Lista de `GoalContribution` |
| Estado de meta | `PATCH /goals/{id}/status` | `{status}` |
| Eliminar meta | `DELETE /goals/{id}` | HTTP 204 |
| Gastos planificados | `GET/POST /planned-expenses` | Lista/entidad `PlannedExpense`; solicitud `title,amount,categoryId,dueDate,notes,remindAt` |
| Editar gasto planificado | `PUT /planned-expenses/{id}` | `PlannedExpenseRequest` |
| Ejecutar gasto | `PATCH /planned-expenses/{id}/execute` | Actualiza estado y crea una transacción en el backend |
| Cancelar gasto | `PATCH /planned-expenses/{id}/cancel` | Actualiza estado a `cancelled` |
| Vencidos/recordatorios | `GET /planned-expenses/overdue`, `/planned-expenses/reminders` | Lista de gastos planificados |
| Asesor IA | `POST /ai/chat` | `{mensaje}` → respuesta JSON que incluye `respuesta` |
| Análisis IA | `GET /ai/analisis` | `AIAnalysisResponse` |
| Proyección de meta | `POST /ai/meta?descripcion=…&monto=…` | Respuesta JSON del servicio IA |

## Diferencias detectadas en el backend

1. `TransactionRequest` no define `notes`, aunque el frontend Flutter original modelaba notas. La app SwiftUI evita ofrecer ese campo para no dar a entender que se guarda.
2. La entidad `Goal` no incluye `icon`; la app usa un icono visual de respaldo.
3. `TransactionStats.categoryData` se devuelve como lista vacía en `TransactionService.getStats`.
4. Los controladores de metas y gastos planificados requieren `X-User-Id`; transacciones y asesor obtienen el usuario desde el JWT. El cliente envía ambos encabezados para cubrir esos contratos.
5. `GET /categories` devuelve `Category.type` con valores que el frontend compara sin distinguir mayúsculas/minúsculas.

## Validaciones ejecutadas en este entorno

- Parseo sintáctico de todos los archivos `.swift`.
- Decodificación de muestras JSON para autenticación, transacciones, metas y gastos planificados con Swift 6.
- No se ejecutó `xcodebuild`, el simulador iOS ni pruebas reales contra Render; requieren macOS/Xcode y deben realizarse antes de publicar.
