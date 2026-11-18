import { Router } from 'express';
import { telefono } from '../formato.js';
import { requiereRol } from '../sesion.js';
import { aLocal, desfase, fechaEnPalabras, fechaValida, hoy } from '../zona.js';
import { agenda, paginaCitas } from '../vistas/citas.js';
import { ErrorHttp } from '../errores.js';

export function rutasCitas(repositorio) {
  const router = Router();
  router.use('/Citas', requiereRol('administrativo'));

  async function cargar(personalId, fechaTexto) {
    const fecha = fechaValida(fechaTexto) ? fechaTexto : hoy();
    const citas = await repositorio.citasDelDia(personalId, fecha, desfase(fecha));

    const mapa = new Map();
    for (const c of citas) {
      const clave = `${c.especialistaId}|${c.especialista}|${c.servicio}`;
      if (!mapa.has(clave)) {
        mapa.set(clave, { especialistaId: c.especialistaId, nombre: c.especialista, servicio: c.servicio, citas: [] });
      }
      mapa.get(clave).citas.push(c);
    }

    const grupos = [...mapa.values()]
      .sort((a, b) => a.especialistaId - b.especialistaId)
      .map((g) => ({
        ...g,
        citas: g.citas
          .sort((a, b) => new Date(a.inicio) - new Date(b.inicio))
          .map((c) => ({
            folio: c.folio,
            hora: aLocal(new Date(c.inicio)).hora,
            estado: c.estado,
            nombre: c.nombre,
            telefono: telefono(c.telefono),
          })),
      }));

    return { fecha, fechaTexto: fechaEnPalabras(fecha), grupos };
  }

  const fechaDe = (req) => (typeof req.query.fecha === 'string' ? req.query.fecha : '');

  router.get('/Citas', async (req, res) => {
    const modelo = await cargar(req.session.usuario.id, fechaDe(req));
    res.type('html').send(paginaCitas({ usuario: req.session.usuario, token: req.session.csrf, modelo }));
  });

  router.get('/Citas/Agenda', async (req, res) => {
    const modelo = await cargar(req.session.usuario.id, fechaDe(req));
    res.type('html').send(agenda(modelo));
  });

  router.post('/Citas/Posponer', async (req, res) => {
    const folio = req.body?.folio;
    if (typeof folio !== 'string' || !folio) throw new ErrorHttp(400, 'Falta el folio');
    await repositorio.posponerCita(req.session.usuario.id, folio);
    res.json({ ok: true });
  });

  return router;
}
