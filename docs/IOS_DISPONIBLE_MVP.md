# FinFlow Disponible — paridad iOS

- MVP lectura de \`GET /accounts\` y \`GET /planned-expenses\`, sin nuevos endpoints ni cambios en base de datos.
- Cuentas COP activas menos gastos planificados pendientes con vencimiento anterior al próximo ingreso, menos ahorro reservado.
- Incluye vencidos pendientes; excluye gastos sin fecha, ingresos futuros, gastos recurrentes y operaciones que aún no se registraron para evitar supuestos falsos.
- Parámetros locales y temporales: fecha y reserva no se guardan ni se envían al backend.
- Montos se agregan con Decimal; al repartir por días se redondea hacia abajo a 2 decimales.
- Navegación desde Inicio y Más; diseño iPhone/iPad con SwiftUI, Refreshable y estados vacíos/errores.
- Requiere QA contra backend real con usuarios de prueba y pruebas de usabilidad. No es saldo bancario ni consejo de crédito.
- PR apilado sobre rama iOS de privacidad/perfil; no fusionar antes de confirmar CI y las pruebas de estabilidad.
- Beta Estudiante queda excluida.
