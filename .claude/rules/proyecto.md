# Reglas generales del proyecto

- La app es de uso interno: sirve para controlar el gasto por parcela y no es el registro horario oficial.
- Todo se escribe en español de España: código, comentarios, documentación, mensajes de error de la BD y mensajes de commit.
- Reparto del trabajo:
  - Lovable diseña las pantallas (https://appreport.lovable.app).
  - Claude Code se encarga de la base de datos, las funciones, la Edge Function del PDF, las pruebas y la documentación.
  - `app/` es solo un boceto.
- **La base de datos decide**: toda regla de negocio y todo permiso se imponen en Supabase (RLS, disparadores y
  funciones). La validación en pantalla es solo una ayuda y nunca sustituye a la de la BD.
- Credenciales:
  - Las contraseñas que el usuario pegue en el chat solo se usan para entrar desde el navegador.
  - Nunca se escriben en archivos, commits ni servicios externos.
  - Recomendar al usuario cambiarlas.
- `.env` no se lee ni se muestra. La service role nunca va a la app ni al navegador; el cliente usa solo la clave publishable (anon).
- Antes de hacer commit, comprobar que ningún archivo contiene contraseñas, claves ni el contenido de `.env`.
- Commit y push solo cuando el usuario lo pida.
- Las decisiones del usuario se documentan con fecha en `docs/`:
  - `DECISIONES_MODULOS_4_A_8.md`;
  - `PLAN_MODULOS_9_Y_10.md`.

  Una decisión nueva que cambie el comportamiento se anota ahí, o en un documento nuevo del mismo estilo.
