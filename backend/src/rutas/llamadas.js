import { randomUUID } from 'node:crypto';
import { Router } from 'express';
import { z } from 'zod';
import { ErrorHttp } from '../errores.js';
import { tokenDeTelefono } from '../livekit.js';

/**
 * Botón de EMERGENCIA y llamada.   Responsable: Ayhan Ben Halima Martinez · A01647593
 *   POST  /api/llamadas        crea la llamada, elige la delegación activa más cercana y crea su ficha
 *   PATCH /api/llamadas/:id    actualiza el estado o la autorización de video (solo el dispositivo dueño)
 *   POST  /api/llamadas/:id/sala           token para entrar a la sala de audio y video de la llamada
 *   POST  /api/llamadas/:id/transcripcion  líneas que la app transcribe en el teléfono
 *   PUT   /api/llamadas/:id/ficha          campos de la ficha que la IA del teléfono extrajo
 *
 * Los campos del cuerpo van en inglés/camelCase porque así los manda la app (Emergencia/EmergencyAPI.swift).
 */

const idDispositivo = z.string().uuid().transform((v) => v.toLowerCase());

const crearLlamada = z.object({
  deviceId: idDispositivo,
  latitude: z.number().min(-90).max(90),
  longitude: z.number().min(-180).max(180),
  accuracyMeters: z.number().nonnegative().max(100000).optional(),
  requesterName: z.string().trim().min(1).max(120).optional(),
  requesterPhone: z.string().regex(/^\+?[0-9]{10,15}$/).optional(),
});

const actualizarLlamada = z.object({
  deviceId: idDispositivo,
  status: z.enum(['en_curso', 'finalizada', 'cortada']).optional(),
  videoAccepted: z.boolean().optional(),
}).refine((body) => body.status !== undefined || body.videoAccepted !== undefined, {
  message: 'Se necesita al menos un cambio',
});

const entrarASala = z.object({ deviceId: idDispositivo });

const lineasTranscripcion = z.object({
  deviceId: idDispositivo,
  lineas: z.array(z.object({
    texto: z.string().trim().min(1).max(1000),
    momentoSeg: z.number().int().min(0).max(86400),
  })).min(1).max(20),
});

const textoCorto = (maximo) => z.string().trim().max(maximo).optional();

const camposIa = z.object({
  deviceId: idDispositivo,
  motivo: textoCorto(500),
  numLesionados: z.number().int().min(0).max(32767).optional(),
  lesionPrincipal: textoCorto(200),
  lugar: textoCorto(300),
  comentarios: textoCorto(2000),
});

async function llamadaDelDispositivo(pool, idLlamada, idDispositivoDueno) {
  const [filas] = await pool.execute(
    'SELECT id, estado FROM llamada WHERE id = ? AND dispositivo_id = ?',
    [idLlamada, idDispositivoDueno]
  );
  if (filas.length === 0) throw new ErrorHttp(404, 'la llamada no existe');
  return filas[0];
}

export function rutasLlamadas(pool) {
  const router = Router();

  router.post('/', async (req, res) => {
    const parsed = crearLlamada.safeParse(req.body);
    if (!parsed.success) throw new ErrorHttp(400, 'datos no válidos');
    const entrada = parsed.data;

    const conexion = await pool.getConnection();
    try {
      await conexion.beginTransaction();

      // El dispositivo se registra si todavía no existe (si ya existe, solo se completa su teléfono).
      await conexion.execute(
        `INSERT INTO dispositivo (id, telefono)
         VALUES (?, ?)
         ON DUPLICATE KEY UPDATE telefono = COALESCE(VALUES(telefono), telefono)`,
        [entrada.deviceId, entrada.requesterPhone ?? null]
      );

      // Delegación activa más cercana, con la función de la base (Haversine, RF17).
      const [delegaciones] = await conexion.execute(
        `SELECT id, nombre, telefono_cecom AS phone,
                distancia_km(?, ?, latitud, longitud) AS distancia
           FROM delegacion
          WHERE activa = 1
          ORDER BY distancia ASC, id ASC
          LIMIT 1`,
        [entrada.latitude, entrada.longitude]
      );
      if (delegaciones.length === 0) {
        await conexion.rollback();
        throw new ErrorHttp(503, 'no hay una delegación disponible por ahora');
      }
      const delegacion = delegaciones[0];
      const idLlamada = randomUUID();

      await conexion.execute(
        `INSERT INTO llamada (
           id, delegacion_id, dispositivo_id, canal, estado,
           solicitante_nombre, solicitante_telefono,
           latitud, longitud, precision_m, conectada_en, datos_recibidos_en
         ) VALUES (?, ?, ?, 'internet', 'en_curso', ?, ?, ?, ?, ?, UTC_TIMESTAMP(3), UTC_TIMESTAMP(3))`,
        [
          idLlamada, delegacion.id, entrada.deviceId,
          entrada.requesterName ?? null, entrada.requesterPhone ?? null,
          entrada.latitude, entrada.longitude, entrada.accuracyMeters ?? null,
        ]
      );

      await conexion.execute(
        `INSERT INTO ficha (llamada_id, nombre, celular, ubicacion)
         VALUES (?, ?, ?, ?)`,
        [
          idLlamada,
          entrada.requesterName ?? null,
          entrada.requesterPhone ?? null,
          `${entrada.latitude}, ${entrada.longitude}`,
        ]
      );

      await conexion.commit();
      res.status(201).json({
        id: idLlamada,
        status: 'en_curso',
        delegation: { id: delegacion.id, name: delegacion.nombre, phone: delegacion.phone },
      });
    } catch (error) {
      await conexion.rollback().catch(() => {});
      throw error;
    } finally {
      conexion.release();
    }
  });

  router.patch('/:id', async (req, res) => {
    const id = z.string().uuid().safeParse(req.params.id);
    const cuerpo = actualizarLlamada.safeParse(req.body);
    if (!id.success || !cuerpo.success) throw new ErrorHttp(400, 'datos no válidos');

    const campos = [];
    const valores = [];
    if (cuerpo.data.status !== undefined) {
      campos.push('estado = ?');
      valores.push(cuerpo.data.status);
      if (['finalizada', 'cortada'].includes(cuerpo.data.status)) campos.push('fin = UTC_TIMESTAMP(3)');
    }
    if (cuerpo.data.videoAccepted !== undefined) {
      campos.push('video_aceptado = ?');
      valores.push(cuerpo.data.videoAccepted ? 1 : 0);
    }
    valores.push(id.data.toLowerCase(), cuerpo.data.deviceId);

    const [resultado] = await pool.execute(
      `UPDATE llamada SET ${campos.join(', ')} WHERE id = ? AND dispositivo_id = ?`,
      valores
    );
    if (resultado.affectedRows === 0) throw new ErrorHttp(404, 'la llamada no existe');
    res.status(204).end();
  });

  router.post('/:id/sala', async (req, res) => {
    const id = z.string().uuid().safeParse(req.params.id);
    const cuerpo = entrarASala.safeParse(req.body);
    if (!id.success || !cuerpo.success) throw new ErrorHttp(400, 'datos no válidos');
    const sala = id.data.toLowerCase();

    const llamada = await llamadaDelDispositivo(pool, sala, cuerpo.data.deviceId);
    if (llamada.estado !== 'en_curso') throw new ErrorHttp(409, 'la llamada ya terminó');
    res.json(await tokenDeTelefono(sala, cuerpo.data.deviceId));
  });

  router.post('/:id/transcripcion', async (req, res) => {
    const id = z.string().uuid().safeParse(req.params.id);
    const cuerpo = lineasTranscripcion.safeParse(req.body);
    if (!id.success || !cuerpo.success) throw new ErrorHttp(400, 'datos no válidos');
    const sala = id.data.toLowerCase();

    await llamadaDelDispositivo(pool, sala, cuerpo.data.deviceId);
    const filas = cuerpo.data.lineas.map((l) => [sala, 'solicitante', l.texto, l.momentoSeg]);
    await pool.query('INSERT INTO transcripcion (llamada_id, hablante, texto, momento_seg) VALUES ?', [filas]);
    res.status(204).end();
  });

  router.put('/:id/ficha', async (req, res) => {
    const id = z.string().uuid().safeParse(req.params.id);
    const cuerpo = camposIa.safeParse(req.body);
    if (!id.success || !cuerpo.success) throw new ErrorHttp(400, 'datos no válidos');
    const sala = id.data.toLowerCase();
    const c = cuerpo.data;

    await llamadaDelDispositivo(pool, sala, c.deviceId);
    const vacio = (valor) => (valor === undefined || valor === '' ? null : valor);
    await pool.execute(
      `UPDATE ficha
          SET motivo           = COALESCE(?, motivo),
              num_lesionados   = COALESCE(?, num_lesionados),
              lesion_principal = COALESCE(?, lesion_principal),
              lugar            = COALESCE(?, lugar),
              comentarios      = COALESCE(?, comentarios)
        WHERE llamada_id = ? AND editado_por IS NULL`,
      [vacio(c.motivo), vacio(c.numLesionados), vacio(c.lesionPrincipal), vacio(c.lugar), vacio(c.comentarios), sala]
    );
    res.status(204).end();
  });

  return router;
}
