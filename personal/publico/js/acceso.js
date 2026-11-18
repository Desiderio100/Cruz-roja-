const formulario = document.getElementById("acceso");
const entrada = document.getElementById("matricula");
const error = document.getElementById("error-matricula");
const boton = document.getElementById("entrar");
const mostrar = document.getElementById("mostrar");

let reloj = null;

function mostrarError(mensaje) {
  error.textContent = mensaje;
  if (mensaje) entrada.setAttribute("aria-invalid", "true");
  else entrada.removeAttribute("aria-invalid");
}

function bloquear(segundos) {
  const termina = Date.now() + segundos * 1000;
  entrada.disabled = true;
  boton.disabled = true;
  const actualizar = () => {
    const restante = Math.max(0, Math.ceil((termina - Date.now()) / 1000));
    if (restante === 0) {
      clearInterval(reloj);
      entrada.disabled = false;
      boton.disabled = false;
      mostrarError("");
      entrada.focus();
      return;
    }
    const minutos = Math.floor(restante / 60);
    const resto = String(restante % 60).padStart(2, "0");
    mostrarError(`Demasiados intentos. Intente de nuevo en ${minutos}:${resto}.`);
  };
  actualizar();
  reloj = setInterval(actualizar, 1000);
}

mostrar.addEventListener("click", () => {
  const visible = entrada.type === "text";
  entrada.type = visible ? "password" : "text";
  mostrar.textContent = visible ? "Mostrar" : "Ocultar";
  mostrar.setAttribute("aria-pressed", visible ? "false" : "true");
});

entrada.addEventListener("input", () => mostrarError(""));

formulario.addEventListener("submit", (evento) => {
  const valor = entrada.value.trim();
  if (!/^[A-Za-z0-9]{25}$/.test(valor)) {
    evento.preventDefault();
    mostrarError("La matrícula tiene 25 caracteres, entre letras y números. Revise que no falten ni sobren.");
    entrada.focus();
  }
});

const segundosBloqueo = Number(formulario.dataset.segundos || 0);
if (segundosBloqueo > 0) bloquear(segundosBloqueo);
else if (error.textContent.trim()) entrada.focus();
