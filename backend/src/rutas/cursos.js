import { randomUUID } from 'node:crypto';
import { Router } from 'express';
import rateLimit from 'express-rate-limit';
import { z } from 'zod';
import { ErrorHttp } from '../errores.js';

/**
 * Capacitación — cursos e inscripciones (HU14, RF26).   Dueño: Desiderio
 *   GET  /api/cursos                     próximos cursos con sus lugares (pública, sin datos personales)
 *   GET  /api/cursos/inscripciones       mis inscripciones
 *   POST /api/cursos/:id/inscripciones   me inscribo: { nombre, telefono }
 * Las dos últimas exigen el header X-Dispositivo-Id: una inscripción solo la ve el dispositivo que la hizo.
 *
 * El cupo se cuida aquí y no en la app: dentro de una transacción se bloquea el curso
 * (SELECT ... FOR UPDATE), se cuentan las inscripciones y solo entonces se inserta. Así dos
 * personas no pueden quedarse con el último lugar.
 */

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const SIN_CONTROL = /^[^\u0000-\u001F\u007F]*$/;

const esquemaInscripcion = z.object({
  nombre: z.string({ required_error: 'falta el nombre', invalid_type_error: 'el nombre no es válido' })
    .trim()
    .min(3, 'escribe tu nombre completo')
    .max(120, 'el nombre es muy largo')
    .regex(SIN_CONTROL, 'el nombre no es válido'),
  telefono: z.string({ required_error: 'falta el teléfono', invalid_type_error: 'el teléfono no es válido' })
    .regex(/^[+]?[0-9]{10,15}$/, 'el teléfono no es válido'),
});

function dispositivo(req) {
  const id = String(req.get('X-Dispositivo-Id') || '').toLowerCase();
  if (!UUID.test(id)) throw new ErrorHttp(401, 'falta el dispositivo');
  return id;
}

function idCurso(req) {
  if (!/^[1-9][0-9]{0,9}$/.test(req.params.id)) throw new ErrorHttp(404, 'el curso no existe');
  return Number(req.params.id);
}

/** Folio que ve la persona: se saca del id de la inscripción, así no hace falta otra columna. */
export function folioDe(idInscripcion) {
  return `CAP-${idInscripcion.replaceAll('-', '').slice(0, 6).toUpperCase()}`;
}

/**
 * @param pool      pool de MySQL (el único de la API)
 * @param opciones  en las pruebas puede traer limiteInscribirPorMinuto
 */
export function rutasCursos(pool, opciones = {}) {
  const router = Router();

  // Cada inscripción escribe en la base: límite más estricto que el general.
  const limiteInscribir = rateLimit({
    windowMs: 60_000, limit: opciones.limiteInscribirPorMinuto ?? 10, standardHeaders: 'draft-7', legacyHeaders: false,
  });

  // Próximos cursos, del más cercano en fecha al más lejano. No lleva nombres ni teléfonos.
  router.get('/', async (_req, res) => {
    const [cursos] = await pool.query(
      `SELECT c.id, c.titulo, c.descripcion, c.inicio, c.cupo, d.nombre AS sede,
              (SELECT COUNT(*) FROM inscripcion_curso i WHERE i.curso_id = c.id) AS inscritos
         FROM curso c
         JOIN delegacion d ON d.id = c.delegacion_id
        WHERE c.activo = 1 AND c.inicio > UTC_TIMESTAMP(3)
        ORDER BY c.inicio, c.id`
    );
    res.set('Cache-Control', 'no-store'); // los lugares cambian con cada inscripción
    res.json({ cursos });
  });

  // Inscripciones del dispositivo. Va antes de "/:id/..." para que "inscripciones" no se lea como un id.
  router.get('/inscripciones', async (req, res) => {
    const [filas] = await pool.query(
      `SELECT i.id, i.curso_id, c.titulo, c.inicio, d.nombre AS sede
         FROM inscripcion_curso i
         JOIN curso c      ON c.id = i.curso_id
         JOIN delegacion d ON d.id = c.delegacion_id
        WHERE i.dispositivo_id = ?
        ORDER BY c.inicio, i.creado_en`,
      [dispositivo(req)]
    );
    res.set('Cache-Control', 'no-store');
    res.json({
      inscripciones: filas.map((f) => ({
        folio: folioDe(f.id), curso_id: f.curso_id, titulo: f.titulo, inicio: f.inicio, sede: f.sede,
      })),
    });
  });

  // Inscribe a la persona si el curso existe, no ha pasado y todavía tiene lugar.
  router.post('/:id/inscripciones', limiteInscribir, async (req, res) => {
    const d = dispositivo(req);
    const cursoId = idCurso(req);
    const lectura = esquemaInscripcion.safeParse(req.body || {});
    if (!lectura.success) throw new ErrorHttp(400, lectura.error.issues[0].message);
    const { nombre, telefono } = lectura.data;

    const [disp] = await pool.query('SELECT 1 FROM dispositivo WHERE id = ?', [d]);
    if (disp.length === 0) throw new ErrorHttp(400, 'dispositivo no registrado');

    const conexion = await pool.getConnection();
    try {
      await conexion.beginTransaction();

      // FOR UPDATE: mientras dura esta transacción nadie más puede inscribirse a este curso.
      const [cursos] = await conexion.query(
        `SELECT c.id, c.titulo, c.inicio, c.cupo, d.nombre AS sede
           FROM curso c
           JOIN delegacion d ON d.id = c.delegacion_id
          WHERE c.id = ? AND c.activo = 1 AND c.inicio > UTC_TIMESTAMP(3)
            FOR UPDATE`,
        [cursoId]
      );
      if (cursos.length === 0) throw new ErrorHttp(404, 'el curso no existe');
      const curso = cursos[0];

      const [[{ inscritos }]] = await conexion.query(
        'SELECT COUNT(*) AS inscritos FROM inscripcion_curso WHERE curso_id = ?', [cursoId]);
      if (inscritos >= curso.cupo) throw new ErrorHttp(409, 'Este curso ya no tiene lugares');

      const id = randomUUID();
      try {
        await conexion.query(
          'INSERT INTO inscripcion_curso (id, curso_id, nombre, telefono, dispositivo_id) VALUES (?, ?, ?, ?, ?)',
          [id, cursoId, nombre, telefono, d]
        );
      } catch (error) {
        // La base no deja repetir el mismo teléfono en un curso (llave inscripcion_curso_telefono_uq).
        if (error.code === 'ER_DUP_ENTRY') throw new ErrorHttp(409, 'Ya estás inscrito en este curso');
        throw error;
      }

      await conexion.commit();
      res.status(201).json({
        folio: folioDe(id),
        curso_id: curso.id,
        titulo: curso.titulo,
        inicio: curso.inicio,
        sede: curso.sede,
        lugares_disponibles: curso.cupo - inscritos - 1,
      });
    } catch (error) {
      await conexion.rollback().catch(() => {});
      throw error;
    } finally {
      conexion.release();
    }
  });

  return router;
}
