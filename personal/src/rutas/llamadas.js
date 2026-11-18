import { Router } from 'express';
import { requiereRol } from '../sesion.js';
import { aLocal, ayer, hoy } from '../zona.js';
import { paginaLlamadas } from '../vistas/llamadas.js';
import { ErrorHttp } from '../errores.js';

const FORMATO_CELULAR = /^\+?[0-9]{10,15}$/;
const FORMATO_NUMERO = /^[0-9]{1,5}$/;

function textoOpcional(valor) {
  return typeof valor === 'string' ? valor : null;
}

function cuandoPerdida(inicio) {
  const local = aLocal(new Date(inicio));
  if (local.dia === hoy()) return `Hoy, ${local.hora}`;
  if (local.dia === ayer()) return `Ayer, ${local.hora}`;
  return `${local.diaMes}, ${local.hora}`;
}

export function rutasLlamadas(repositorio, { perdidasHoras }) {
  const router = Router();
  router.use('/Llamadas', requiereRol('operador'));

  router.get('/Llamadas', (req, res) => {
    res.type('html').send(paginaLlamadas({ usuario: req.session.usuario, token: req.session.csrf, perdidasHoras }));
  });

  router.get('/Llamadas/Actual', async (req, res) => {
    const llamada = await repositorio.abrirSiguiente(req.session.usuario.id);
    if (!llamada) return res.json({ hay: false });

    const f = llamada.ficha;
    const ia = [];
    if (!llamada.editadaPorOperador) {
      if (f.motivo && f.motivo.trim()) ia.push('motivo');
      if (f.lesionados !== null) ia.push('lesionados');
      if (f.lesionPrincipal && f.lesionPrincipal.trim()) ia.push('lesionPrincipal');
      if (f.lugar && f.lugar.trim()) ia.push('lugar');
      if (f.comentarios && f.comentarios.trim()) ia.push('comentarios');
    }

    res.json({
      hay: true,
      id: llamada.id,
      estado: llamada.estado,
      canal: llamada.canal,
      inicio: llamada.inicio,
      delegacion: llamada.delegacion,
      telefono: llamada.telefono,
      telefonoVerificado: llamada.telefonoVerificado,
      latitud: llamada.latitud,
      longitud: llamada.longitud,
      precisionM: llamada.precisionM,
      ia,
      ficha: {
        nombre: f.nombre,
        celular: f.celular,
        motivo: f.motivo,
        lesionados: f.lesionados === null ? null : String(f.lesionados),
        lesionPrincipal: f.lesionPrincipal,
        lugar: f.lugar,
        ubicacion: f.ubicacion,
        comentarios: f.comentarios,
      },
    });
  });

  router.get('/Llamadas/Transcripcion', async (req, res) => {
    const llamada = typeof req.query.llamada === 'string' ? req.query.llamada : '';
    const desde = Number.parseInt(String(req.query.desde ?? '0'), 10);
    const lineas = await repositorio.transcripcion(req.session.usuario.id, llamada, Number.isFinite(desde) ? desde : 0);
    res.json(lineas);
  });

  router.get('/Llamadas/Perdidas', async (req, res) => {
    const perdidas = await repositorio.perdidas(req.session.usuario.id, perdidasHoras);
    res.json(
      perdidas.map((p) => ({
        id: p.id,
        cuando: cuandoPerdida(p.inicio),
        nombre: p.nombre,
        telefono: p.telefono,
        verificado: p.verificado,
      })),
    );
  });

  router.post('/Llamadas/Guardar', async (req, res) => {
    const cuerpo = req.body ?? {};
    if (typeof cuerpo.llamada !== 'string' || !cuerpo.llamada) throw new ErrorHttp(400, 'Falta la llamada');

    const celular = (textoOpcional(cuerpo.celular) ?? '').replace(/ /g, '').replace(/-/g, '');
    if (celular.length > 0 && !FORMATO_CELULAR.test(celular)) {
      return res.status(400).json({ campo: 'celular', error: 'Escriba el celular con 10 dígitos, por ejemplo 55 5501 0142' });
    }

    const lesionados = String(cuerpo.lesionados ?? '').trim();
    if (lesionados.length > 0 && !FORMATO_NUMERO.test(lesionados)) {
      return res.status(400).json({ campo: 'lesionados', error: 'Escriba solo dígitos, por ejemplo 2' });
    }

    await repositorio.guardarFicha(req.session.usuario.id, cuerpo.llamada, {
      nombre: textoOpcional(cuerpo.nombre),
      celular: celular.length === 0 ? null : celular,
      motivo: textoOpcional(cuerpo.motivo),
      lesionados: lesionados.length === 0 ? null : Number.parseInt(lesionados, 10),
      lesionPrincipal: textoOpcional(cuerpo.lesionPrincipal),
      lugar: textoOpcional(cuerpo.lugar),
      ubicacion: textoOpcional(cuerpo.ubicacion),
      comentarios: textoOpcional(cuerpo.comentarios),
    });
    res.json({ ok: true });
  });

  router.post('/Llamadas/Finalizar', async (req, res) => {
    const llamada = req.body?.llamada;
    if (typeof llamada !== 'string' || !llamada) throw new ErrorHttp(400, 'Falta la llamada');
    await repositorio.finalizar(req.session.usuario.id, llamada);
    res.json({ ok: true });
  });

  return router;
}

