import { llamar } from './db.js';
import { booleano, entero, numero, texto } from './formato.js';

export function crearRepositorio(pool) {
  return {
    async acceso(huella, origen, maximo, bloqueoMinutos) {
      const filas = await llamar(pool, 'personal_login_matricula', [huella, origen, maximo, bloqueoMinutos]);
      const f = filas[0];
      if (!f) return { estado: 'incorrecta' };
      return {
        estado: texto(f.estado) ?? 'incorrecta',
        personalId: texto(f.personal_id),
        rol: texto(f.rol),
        delegacionId: entero(f.delegacion_id),
        delegacion: texto(f.delegacion),
        permisoContenido: booleano(f.permiso_contenido),
        bloqueadoHasta: f.bloqueado_hasta ?? null,
      };
    },

    async abrirSiguiente(personalId) {
      const filas = await llamar(pool, 'llamada_abrir_siguiente', [personalId]);
      const f = filas[0];
      if (!f) return null;
      return {
        id: texto(f.llamada_id),
        estado: texto(f.estado),
        canal: texto(f.canal),
        inicio: f.inicio,
        delegacion: texto(f.delegacion),
        telefono: texto(f.solicitante_telefono),
        telefonoVerificado: booleano(f.telefono_verificado),
        latitud: numero(f.latitud),
        longitud: numero(f.longitud),
        precisionM: numero(f.precision_m),
        ficha: {
          nombre: texto(f.nombre),
          celular: texto(f.celular),
          motivo: texto(f.motivo),
          lesionados: entero(f.num_lesionados),
          lesionPrincipal: texto(f.lesion_principal),
          lugar: texto(f.lugar),
          ubicacion: texto(f.ubicacion),
          comentarios: texto(f.comentarios),
        },
        editadaPorOperador: f.editado_por !== null && f.editado_por !== undefined,
      };
    },

    async transcripcion(personalId, llamadaId, desdeId) {
      const filas = await llamar(pool, 'transcripcion_listar', [personalId, llamadaId, desdeId]);
      return filas.map((f) => ({
        id: Number(f.id),
        hablante: texto(f.hablante),
        texto: texto(f.texto),
        momento: Number(f.momento_seg),
      }));
    },

    async guardarFicha(personalId, llamadaId, ficha) {
      await llamar(pool, 'ficha_guardar', [
        personalId,
        llamadaId,
        ficha.nombre,
        ficha.celular,
        ficha.motivo,
        ficha.lesionados,
        ficha.lesionPrincipal,
        ficha.lugar,
        ficha.ubicacion,
        ficha.comentarios,
      ]);
    },

    async finalizar(personalId, llamadaId) {
      await llamar(pool, 'llamada_finalizar', [personalId, llamadaId]);
    },

    async perdidas(personalId, horas) {
      const filas = await llamar(pool, 'llamadas_perdidas_listar', [personalId, horas]);
      return filas.map((f) => ({
        id: texto(f.llamada_id),
        inicio: f.inicio,
        nombre: texto(f.solicitante_nombre),
        telefono: texto(f.solicitante_telefono),
        verificado: booleano(f.telefono_verificado),
      }));
    },

    async citasDelDia(personalId, fecha, zona) {
      const filas = await llamar(pool, 'citas_del_dia', [personalId, fecha, zona]);
      return filas.map((f) => ({
        folio: texto(f.folio),
        inicio: f.inicio,
        servicio: texto(f.servicio),
        estado: texto(f.estado),
        nombre: texto(f.nombre),
        telefono: texto(f.telefono),
        especialistaId: Number(f.especialista_id),
        especialista: texto(f.especialista),
      }));
    },

    async posponerCita(personalId, folio) {
      await llamar(pool, 'cita_posponer_personal', [personalId, folio]);
    },
  };
}
