# Base de datos de la App Cruz Roja – MySQL 8.0 o superior

Scripts para crear la base `cruzroja` en Aiven (MySQL 8.4) y, más adelante, en la máquina virtual de la escuela.

| Orden | Archivo | Qué hace |
|---|---|---|
| 1 | `01_esquema.sql` | Crea la base (si no existe), tablas, vistas, funciones, procedimientos y disparadores |
| 2 | `02_datos_prueba.sql` | Datos ficticios para desarrollo (delegaciones, especialistas, productos, tutoriales, un curso) |
| 3 | `03_permisos_app.sql` | Deja a `cruzroja_app` con los permisos mínimos y muestra la lista al final |
| 4 | `04_pruebas.sql` | 17 pruebas + una comprobación final. No deja datos |
| 5 (opcional) | `05_usuarios_desarrollo.sql` | Da permisos de desarrollo (crear y cambiar tablas) a los compañeros del equipo |
| 6 (opcional) | `06_agregar_productos.sql` | Plantilla para agregar productos al catálogo "Productos con causa". Se puede repetir; cada corrida agrega lo que escribas |
| – | `99_borrar_todo_SOLO_DESARROLLO.sql` | Borra la base completa. Solo para volver a empezar |
| – | `diagrama/er.py`, `diagrama/er.png` | Diagrama entidad-relación y el programa que lo dibuja |

## Antes de empezar

1. En MySQL Workbench, abre tu conexión de Aiven **con el usuario `avnadmin`** (doble clic en la tarjeta de la conexión; te pide la contraseña de `avnadmin`).
2. En Aiven (pestaña **Users** del servicio) ya debe existir el usuario `cruzroja_app`. Solo se necesita para el paso 3.

## Cómo correr cada archivo (se repite igual con los 4)

1. Menú **File > Open SQL Script…** (Mac: ⌘⇧O) y elige el archivo. Se abre en una pestaña nueva con el código.
2. Pulsa el **primer rayo amarillo** de la barra de la pestaña (el que dice *Execute the selected portion of the script or everything if there is no selection*; Mac: ⌘⇧↵). **No** el rayo con la "I".
3. Abajo, en **Output > Action Output**, cada línea debe tener un círculo verde. Si alguna sale roja, copia el texto del error y mándamelo.
4. Para ver las tablas nuevas: en el panel izquierdo, pestaña **Schemas**, clic derecho > **Refresh All** y abre `cruzroja`.

Qué esperar en cada uno:

- **01**: todo verde. En Schemas aparecen 17 tablas, 4 vistas y 8 rutinas (procedimientos y funciones).
- **02**: todo verde.
- **03**: al final se abre una tabla "Grants for cruzroja_app@%". Debe empezar con `GRANT USAGE ON *.*` y tener solo líneas de `` `cruzroja`.`...` `` y `GRANT EXECUTE ON `cruzroja`.*`. **No** debe aparecer `WITH GRANT OPTION`, `DELETE`, ni nada sobre otras bases.
- **04**: al final se abre una tabla con una fila por prueba. Todas deben decir `OK` y la última fila (99) debe decir `TODO BIEN`. Si una dice `FALLÓ`, la columna `detalle` explica por qué.

## Si algo sale mal

- **Error 1046 "No database selected"**: no corriste el archivo completo. Cierra la pestaña, ábrelo de nuevo y usa el rayo de todo el script.
- **Error 1044, 1142 o 1227 "Access denied"**: no estás conectado como `avnadmin`.
- **03 dice "el usuario no existe"**: crea `cruzroja_app` en la consola de Aiven y vuelve a correr el 03.
- **El 01 se detuvo a la mitad**: corre `99_borrar_todo_SOLO_DESARROLLO.sql` y empieza otra vez desde el 01.
- **Cualquier archivo se puede volver a correr** salvo el 01 y el 02 (esos fallan si ya hay datos); el 03 y el 04 sí se pueden repetir las veces que quieras.

## Comprobación opcional de que la app no puede de más

Abre una conexión nueva en Workbench con el usuario `cruzroja_app` (la contraseña es la que Aiven mostró) y corre esto, que **debe dar error**:

```sql
DELETE FROM cruzroja.llamada WHERE id = 'x';
```

Debe responder `Error Code: 1142. DELETE command denied to user 'cruzroja_app'...`. Si en cambio dice "0 row(s) affected", la app sí puede borrar y hay que revisar el 03.

## Usuarios de desarrollo para el equipo (opcional)

Para que todos en el equipo puedan ver y editar datos y crear o cambiar tablas, sin darles `avnadmin`:

1. En Aiven, pestaña **Users** del servicio > **Add service user**: crea un usuario por persona (por ejemplo `dev_ana`, `dev_luis`). Copia la contraseña de cada uno.
2. Abre `05_usuarios_desarrollo.sql` y edita **solo** la línea `SET @zz_usuarios = '...'` con los nombres separados por comas.
3. Córrelo como `avnadmin` (igual que los demás). Al final aparece una tabla con los permisos de cada persona.
4. Pásale a cada quien su usuario, su contraseña, el host, el puerto, la base `cruzroja` y el `ca.pem`.

Pueden crear, cambiar y borrar **tablas e índices** y editar datos. No pueden crear ni cambiar disparadores, procedimientos, funciones ni vistas, ni crear usuarios. Esas piezas guardan el nombre de quien las crea, y si esa persona se borra después, dejan de funcionar; las cambia `avnadmin` con el `01`. También pueden vaciar tablas y borrar la base completa, así que acuerden no hacerlo. Los cambios de estructura que hagan deben anotarse en el `01`, para que la base y los scripts no se desfasen. Para quitar a alguien: `DROP USER 'dev_ana'@'%';`

## Agregar productos al catálogo (opcional)

1. Abre `06_agregar_productos.sql` y edita las líneas marcadas `<== EDITA`: nombre, precio, causa, dirección de la foto (o `NULL`) y enlace oficial de compra. Los enlaces deben empezar con `https://`; si no, el servidor no se los entrega a la app.
2. Córrelo como `avnadmin` o con tu usuario dev, igual que los demás. Al final aparece la lista con el `id` de cada producto.
3. Para quitar un producto de la app sin borrarlo: `UPDATE producto SET activo = 0 WHERE id = 5;` (cambia el 5 por su `id`).
4. La app tarda hasta 1 minuto en verlo (el servidor guarda la lista 60 segundos). Jala la pantalla hacia abajo para actualizar.

## Para el backend

- Conexión siempre con TLS: usa el certificado `ca.pem` de Aiven y el modo `VERIFY_CA`.
- Guarda las fechas y horas en UTC (`DATETIME(3)`) y conviértelas a hora local al mostrarlas.
- No cambies el `sql_mode` de tu conexión (debe seguir en modo estricto).
- Los ids son UUID versión 4 (`CHAR(36)`). Genera el tuyo y pásalo en el INSERT cuando necesites conocerlo al instante.
- Usa `CALL` para los procedimientos: `delegacion_mas_cercana`, `horarios_disponibles`, `personal_login_fallido`, `personal_login_exitoso`.

## Migrar a la máquina virtual

Ver la sección 8 del PDF de diseño (`Diseno_backend_ciberseguridad_Cruz_Roja_v2_MySQL.pdf`). Resumen: confirma la versión de MySQL o MariaDB de la VM, saca un `mysqldump --routines --triggers --events --single-transaction --set-gtid-purged=OFF --ssl-ca=ca.pem`, quita los `DEFINER=avnadmin@%` o crea ese usuario allá, crea `cruzroja_app` con tu contraseña y corre `03` y `04`.
