import { randomUUID } from 'node:crypto';
import { Router } from 'express';
import rateLimit from 'express-rate-limit';
import { z } from 'zod';
import { ErrorHttp } from '../errores.js';

/**
 * HU14 — Inscripción a capacitación (RF29).   Dueño: Desiderio
 *   GET  /api/cursos                     próximos cursos con fecha, sede y lugares disponibles
 *   POST /api/cursos/:id/inscripcion     aparta un lugar y devuelve el folio de confirmación
 *   GET  /api/cursos/inscripciones       inscripciones hechas desde este dispositivo
 *
 * El cupo se comprueba dentro de una transacción con el curso bloqueado (SELECT ... FOR UPDATE),
 * así dos personas no pueden quedarse con el último lugar. Un mismo celular no puede inscribirse
 * dos veces al mismo curso (llave única curso_id + telefono).
 * El header X-Dispositivo-Id es opcional al inscribirse; si llega, la inscripción queda ligada al
 * dispositivo para poder consultarla después.
 */

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

const datosInscripcion = z.object({
  nombre: z.string().trim().min(3).max(120),
  telefono: z.string().max(20),
});

/** Deja solo los 10 dígitos del celular (quita espacios, guiones y la lada +52). */
function celular(valor) {
  let digitos = String(valor).replace(/\D/g, '');
  if (digitos.length === 12 && digitos.startsWith('52')) digitos = digitos.slice(2);
  if (digitos.length !== 10) throw new ErrorHttp(400, 'Escribe un celular de 10 dígitos.');
  return digitos;
}

function dispositivoOpcional(req) {
  const id = String(req.get('X-Dispositivo-Id') || '').toLowerCase();
  return UUID.test(id) ? id : null;
}

/** Folio corto para mostrar: "CR-1A2B3C4D". */
function folioDe(id) {
  return 'CR-' + id.replace(/-/g, '').slice(0, 8).toUpperCase();
}

export function rutasCursos(pool) {
  const router = Router();

  // Cada inscripción escribe en la base: límite más estricto que el general.
  const limiteInscripciones = rateLimit({ windowMs: 60_000, limit: 10, standardHeaders: 'draft-7', legacyHeaders: false });

  router.get('/', async (_req, res) => {
    // duracion y costo_mxn llegan con db/12_cursos_y_centros.sql; sin ese script se omiten.
    const consulta = (extra) => pool.query(
      `SELECT c.id, c.titulo, c.descripcion, c.inicio, c.cupo, ${extra}
              COUNT(i.id) AS inscritos, d.id AS delegacion_id, d.nombre AS sede
         FROM curso c
         JOIN delegacion d ON d.id = c.delegacion_id
         LEFT JOIN inscripcion_curso i ON i.curso_id = c.id
        WHERE c.activo = 1 AND c.inicio > UTC_TIMESTAMP(3)
        GROUP BY c.id
        ORDER BY c.inicio, c.id`
    );
    let filas;
    try {
      [filas] = await consulta('c.duracion, c.costo_mxn,');
    } catch (error) {
      if (error.code !== 'ER_BAD_FIELD_ERROR') throw error;
      [filas] = await consulta('');
    }
    res.set('Cache-Control', 'no-cache');
    res.json({ cursos: filas.map((c) => ({ ...c, inscritos: Number(c.inscritos) })) });
  });

  router.get('/inscripciones', async (req, res) => {
    const dispositivo = dispositivoOpcional(req);
    if (!dispositivo) throw new ErrorHttp(401, 'falta el dispositivo');
    const [filas] = await pool.query(
      `SELECT i.id, i.curso_id, c.titulo, c.inicio, d.nombre AS sede
         FROM inscripcion_curso i
         JOIN curso c ON c.id = i.curso_id
         JOIN delegacion d ON d.id = c.delegacion_id
        WHERE i.dispositivo_id = ?
        ORDER BY c.inicio`,
      [dispositivo]
    );
    res.json({ inscripciones: filas.map((f) => ({ ...f, folio: folioDe(f.id) })) });
  });

  router.post('/:id/inscripcion', limiteInscripciones, async (req, res) => {
    const cursoId = Number(req.params.id);
    if (!Number.isInteger(cursoId) || cursoId < 1) throw new ErrorHttp(404, 'El curso no existe.');
    const datos = datosInscripcion.safeParse(req.body ?? {});
    if (!datos.success) throw new ErrorHttp(400, 'Escribe tu nombre y un celular de 10 dígitos.');
    const telefono = celular(datos.data.telefono);
    const dispositivo = dispositivoOpcional(req);

    const conexion = await pool.getConnection();
    try {
      await conexion.beginTransaction();

      const [[curso]] = await conexion.query(
        'SELECT id, titulo, inicio, cupo, activo FROM curso WHERE id = ? FOR UPDATE',
        [cursoId]
      );
      if (!curso || !curso.activo) throw new ErrorHttp(404, 'El curso no existe.');
      if (curso.inicio <= new Date()) throw new ErrorHttp(409, 'Este curso ya empezó.');

      const [[{ inscritos }]] = await conexion.query(
        'SELECT COUNT(*) AS inscritos FROM inscripcion_curso WHERE curso_id = ?',
        [cursoId]
      );
      if (Number(inscritos) >= curso.cupo) {
        throw new ErrorHttp(409, 'Este curso ya no tiene lugares. Revisa otras fechas.');
      }

      const id = randomUUID();
      try {
        await conexion.execute(
          'INSERT INTO inscripcion_curso (id, curso_id, nombre, telefono, dispositivo_id) VALUES (?, ?, ?, ?, ?)',
          [id, cursoId, datos.data.nombre, telefono, dispositivo]
        );
      } catch (error) {
        if (error.code === 'ER_DUP_ENTRY') throw new ErrorHttp(409, 'Ese celular ya está inscrito en este curso.');
        if (error.code === 'ER_NO_REFERENCED_ROW_2') throw new ErrorHttp(400, 'dispositivo no registrado');
        throw error;
      }

      await conexion.commit();
      res.status(201).json({
        id,
        folio: folioDe(id),
        curso_id: cursoId,
        inscritos: Number(inscritos) + 1,
        cupo: curso.cupo,
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
