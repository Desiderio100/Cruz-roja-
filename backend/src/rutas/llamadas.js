import { randomUUID } from 'node:crypto';
import { Router } from 'express';
import { z } from 'zod';
import { llamar } from '../db.js';
import { ErrorHttp } from '../errores.js';

/**
 * Botón de EMERGENCIA y llamada.   Responsable: Ayhan Ben Halima Martinez · A01647593
 *   POST  /api/llamadas        crea la llamada, elige la delegación activa más cercana y crea su ficha
 *   PATCH /api/llamadas/:id    actualiza el estado o la autorización de video (solo el dispositivo dueño)
 *   POST  /api/llamadas/:id/transcripcion   guarda las frases que el teléfono transcribió (RF12, HU09)
 *
 * La transcripción se hace en el iPhone (Emergencia/TranscriptorLlamada.swift): aquí solo llega texto,
 * nunca audio. El panel del operador la lee de la tabla transcripcion (carpeta personal/).
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

// Sin caracteres de control: el texto se muestra tal cual en el panel del operador.
const SIN_CONTROL = /^[^\u0000-\u001F\u007F]*$/;

const agregarTranscripcion = z.object({
  deviceId: idDispositivo,
  lines: z.array(z.object({
    text: z.string().trim().min(1).max(1000).regex(SIN_CONTROL),
    second: z.number().int().min(0).max(86_400),   // segundos desde que empezó la llamada
  })).min(1).max(20),
});

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

  // Frases que el teléfono transcribió durante la llamada. Las líneas de un envío se guardan
  // todas o ninguna, para que el teléfono pueda reenviar el grupo completo si hubo un error.
  router.post('/:id/transcripcion', async (req, res) => {
    const id = z.string().uuid().safeParse(req.params.id);
    const cuerpo = agregarTranscripcion.safeParse(req.body);
    if (!id.success || !cuerpo.success) throw new ErrorHttp(400, 'datos no válidos');

    const conexion = await pool.getConnection();
    try {
      await conexion.beginTransaction();
      // El procedimiento revisa que la llamada sea de este dispositivo y siga abierta.
      for (const linea of cuerpo.data.lines) {
        await llamar(conexion, 'CALL transcripcion_agregar(?, ?, ?, ?)', [
          id.data.toLowerCase(), cuerpo.data.deviceId, linea.text, linea.second,
        ]);
      }
      await conexion.commit();
      res.status(201).json({ saved: cuerpo.data.lines.length });
    } catch (error) {
      await conexion.rollback().catch(() => {});
      throw error;
    } finally {
      conexion.release();
    }
  });

  return router;
}
