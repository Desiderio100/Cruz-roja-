import { Router } from 'express';
import { llamar } from '../db.js';
import { ErrorHttp } from '../errores.js';

/**
 * Pantalla 5 — Agenda de citas, Mis citas y Cancelar cita.   Dueño: Luis
 * Cada ruta llama a un procedimiento almacenado de la base (CALL ...).
 *   GET  /api/citas/horarios        horarios libres de un día (sin header de dispositivo)
 *   GET  /api/citas                 mis citas
 *   POST /api/citas                 agendar
 *   POST /api/citas/:id/cancelar
 *   POST /api/citas/:id/reprogramar
 * Todas, menos horarios, exigen el header X-Dispositivo-Id: una cita solo la ve y la
 * modifica el dispositivo que la creó.
 */

const SERVICIOS = ['nutricion', 'psicologia'];
const ZONA = /^[+-](0\d|1[0-4]):[0-5]\d$/;
const FECHA = /^\d{4}-\d{2}-\d{2}$/;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function dispositivo(req) {
  const id = String(req.get('X-Dispositivo-Id') || '').toLowerCase();
  if (!UUID.test(id)) throw new ErrorHttp(401, 'falta el dispositivo');
  return id;
}

function zona(valor) {
  if (!ZONA.test(String(valor || ''))) throw new ErrorHttp(400, 'zona horaria no válida');
  return valor;
}

// Convierte la fecha de inicio que manda la app.
function inicio(valor) {
  const fecha = new Date(valor);
  if (typeof valor !== 'string' || Number.isNaN(fecha.getTime())) {
    throw new ErrorHttp(400, 'fecha de inicio no válida');
  }
  return fecha;
}

function idCita(req) {
  if (!UUID.test(req.params.id)) throw new ErrorHttp(404, 'la cita no existe');
  return req.params.id.toLowerCase();
}

export function rutasCitas(pool) {
  const router = Router();

  // Horarios libres de un día para un servicio.
  router.get('/horarios', async (req, res) => {
    const delegacion = Number(req.query.delegacion_id);
    const servicio = req.query.servicio;
    if (!Number.isInteger(delegacion) || delegacion < 1) throw new ErrorHttp(400, 'delegación no válida');
    if (!SERVICIOS.includes(servicio)) throw new ErrorHttp(400, 'servicio no válido');
    if (!FECHA.test(String(req.query.fecha || ''))) throw new ErrorHttp(400, 'fecha no válida');
    const filas = await llamar(pool, 'CALL horarios_disponibles(?, ?, ?, ?)', [
      delegacion, servicio, req.query.fecha, zona(req.query.zona),
    ]);
    res.json(filas);
  });

  // Citas del dispositivo, las pospuestas primero.
  router.get('/', async (req, res) => {
    const filas = await llamar(pool, 'CALL citas_del_dispositivo(?)', [dispositivo(req)]);
    res.json(filas);
  });

  // Agenda una cita nueva.
  router.post('/', async (req, res) => {
    const d = dispositivo(req);
    const { delegacion_id, servicio, inicio: ini, zona: z, nombre, telefono } = req.body || {};
    const filas = await llamar(pool, 'CALL cita_agendar(?, ?, ?, ?, ?, ?, ?)', [
      d, delegacion_id, servicio, inicio(ini), zona(z), nombre, telefono,
    ]);
    res.status(201).json(filas[0]);
  });

  // Cancela una cita del dispositivo.
  router.post('/:id/cancelar', async (req, res) => {
    await llamar(pool, 'CALL cita_cancelar(?, ?)', [idCita(req), dispositivo(req)]);
    res.status(204).end();
  });

  // Reprograma una cita pospuesta.
  router.post('/:id/reprogramar', async (req, res) => {
    const d = dispositivo(req);
    const { inicio: ini, zona: z } = req.body || {};
    const filas = await llamar(pool, 'CALL cita_reprogramar(?, ?, ?, ?)', [
      idCita(req), d, inicio(ini), zona(z),
    ]);
    res.json(filas[0]);
  });

  return router;
}
