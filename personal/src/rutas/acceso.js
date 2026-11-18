import { Router } from 'express';
import { huellaDeMatricula } from '../huella.js';
import { cerrarSesion, inicioDelRol, iniciarSesion } from '../sesion.js';
import { paginaAcceso } from '../vistas/acceso.js';

const FORMATO_MATRICULA = /^[A-Za-z0-9]{25}$/;

function origenDe(req) {
  const ip = req.ip ?? '';
  return ip.startsWith('::ffff:') ? ip.slice(7) : ip || 'desconocido';
}

export function rutasAcceso(repositorio, { maximoIntentos, bloqueoMinutos }) {
  const router = Router();

  const mostrar = (req, res) => {
    const usuario = req.session.usuario;
    if (usuario) return res.redirect(inicioDelRol(usuario));
    res.type('html').send(paginaAcceso({ token: req.session.csrf }));
  };

  router.get('/', mostrar);
  router.get('/Acceso', mostrar);

  router.post('/Acceso', async (req, res) => {
    const enviado = req.body?.matricula;
    const matricula = (typeof enviado === 'string' ? enviado : '').trim();
    const token = req.session.csrf;

    if (!FORMATO_MATRICULA.test(matricula)) {
      return res.type('html').send(
        paginaAcceso({
          token,
          error: 'La matrícula tiene 25 caracteres, entre letras y números. Revise que no falten ni sobren.',
        }),
      );
    }

    const resultado = await repositorio.acceso(huellaDeMatricula(matricula), origenDe(req), maximoIntentos, bloqueoMinutos);

    if (resultado.estado === 'ok') {
      iniciarSesion(req, {
        id: resultado.personalId,
        rol: resultado.rol,
        delegacionId: resultado.delegacionId,
        delegacion: resultado.delegacion ?? '',
        permisoContenido: resultado.permisoContenido,
      });
      return res.redirect(resultado.rol === 'operador' ? '/Llamadas' : '/Citas');
    }

    if (resultado.estado === 'bloqueado' && resultado.bloqueadoHasta) {
      const segundos = Math.max(1, Math.ceil((new Date(resultado.bloqueadoHasta).getTime() - Date.now()) / 1000));
      const resto = String(segundos % 60).padStart(2, '0');
      return res.type('html').send(
        paginaAcceso({
          token,
          segundosBloqueo: segundos,
          error: `Demasiados intentos. Intente de nuevo en ${Math.floor(segundos / 60)}:${resto}.`,
        }),
      );
    }

    res.type('html').send(paginaAcceso({ token, error: 'La matrícula no es correcta. Revísela e intente de nuevo.' }));
  });

  router.post('/Acceso/Salir', (req, res) => {
    cerrarSesion(req);
    res.redirect('/');
  });

  router.get('/Acceso/Denegado', (req, res) => {
    const usuario = req.session.usuario;
    res.redirect(usuario ? inicioDelRol(usuario) : '/Acceso');
  });

  return router;
}
