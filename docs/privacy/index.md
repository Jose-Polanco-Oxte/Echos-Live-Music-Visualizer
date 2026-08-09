---
title: Política de Privacidad de Echo Visualizer
---

# Política de Privacidad de Echo Visualizer

**Última actualización: 9 de agosto de 2026**

## 1. Introducción

La privacidad de los usuarios es importante para Echo Visualizer.

Esta Política de Privacidad explica cómo **Echo Visualizer** ("la Aplicación") accede, utiliza, procesa, almacena y, cuando corresponde, comparte información durante su funcionamiento.

Echo Visualizer es una aplicación de escritorio para Windows diseñada para generar representaciones visuales en tiempo real a partir del audio reproducido o capturado por el sistema.

La Aplicación ha sido diseñada siguiendo un principio de **procesamiento local**, procurando minimizar la recopilación de información y evitando, en la medida técnicamente posible, que los datos utilizados para proporcionar sus funciones abandonen el dispositivo del usuario.

Esta Política de Privacidad se aplica a Echo Visualizer y a sus funcionalidades oficiales.

No se aplica a servicios, aplicaciones, sitios web o productos de terceros que puedan utilizarse junto con Echo Visualizer y que estén sujetos a sus propias políticas de privacidad.

---

## 2. Responsable de la aplicación

Echo Visualizer es desarrollado y mantenido por:

**Desarrollador:** José Antonio Polanco Oxté
**Producto:** Echo Visualizer
**País:** México
**Correo electrónico de privacidad y soporte:** josepolanco4569@gmail.com
**Repositorio oficial:** https://github.com/Jose-Polanco-Oxte/Echos-Live-Music-Visualizer

Para cualquier pregunta relacionada con esta Política de Privacidad o con el tratamiento de información por parte de Echo Visualizer, puedes comunicarte mediante el correo indicado anteriormente.

---

## 3. Principios de privacidad

Echo Visualizer se diseña siguiendo los siguientes principios:

* **Minimización de datos:** la Aplicación procura acceder únicamente a los recursos necesarios para proporcionar sus funciones.
* **Procesamiento local:** el procesamiento de audio y la generación de visualizaciones se realizan localmente en el dispositivo siempre que sea técnicamente posible.
* **No recopilación innecesaria:** Echo Visualizer no recopila información personal que no sea necesaria para su funcionamiento.
* **Transparencia:** esta política explica qué recursos puede utilizar la Aplicación y con qué finalidad.
* **Control del usuario:** el usuario mantiene el control sobre la ejecución de la Aplicación y sobre los permisos administrados por Windows.
* **Seguridad:** se procura reducir la exposición innecesaria de información mediante una arquitectura que evita transmitir datos cuando no es necesario.

---

## 4. Datos e información a los que puede acceder Echo Visualizer

### 4.1 Audio del sistema

La función principal de Echo Visualizer requiere analizar información de audio para producir visualizaciones en tiempo real.

La Aplicación puede acceder al flujo de audio proporcionado por Windows mediante las interfaces de audio disponibles en el sistema, incluyendo tecnologías como **Windows Audio Session API (WASAPI)**, tanto al audio que reproduce el sistema (loopback) como, cuando el usuario lo selecciona, a un dispositivo de entrada de audio.

Este acceso se utiliza exclusivamente para realizar operaciones relacionadas con la visualización del audio, como:

* obtener información de amplitud;
* obtener niveles de señal;
* analizar frecuencias;
* realizar transformaciones espectrales;
* calcular información necesaria para animaciones;
* generar representaciones visuales sincronizadas con el audio.

### Echo Visualizer no utiliza el audio para identificar al usuario.

El análisis del audio tiene como finalidad producir la representación visual solicitada por el usuario.

---

## 5. Procesamiento del audio

El procesamiento de audio realizado por Echo Visualizer se lleva a cabo **localmente en el dispositivo del usuario**.

Salvo que una funcionalidad futura indique expresamente lo contrario:

* Echo Visualizer **no envía el audio capturado a servidores externos**;
* Echo Visualizer **no carga el audio en servicios en la nube**;
* Echo Visualizer **no vende el contenido de audio**;
* Echo Visualizer **no utiliza el audio para publicidad**;
* Echo Visualizer **no utiliza el audio para crear perfiles personales**;
* Echo Visualizer **no utiliza el audio para entrenar modelos de inteligencia artificial**;
* Echo Visualizer **no comparte el contenido del audio con terceros**.

El audio puede permanecer temporalmente en memoria durante el tiempo estrictamente necesario para calcular las visualizaciones.

La información temporal utilizada para este procesamiento se descarta como parte del funcionamiento normal de la aplicación.

---

## 6. Grabación y almacenamiento de audio

Echo Visualizer **no está diseñado para grabar ni almacenar de forma permanente el audio del sistema** utilizado para generar las visualizaciones.

El análisis se realiza sobre el flujo de audio mientras este se reproduce.

Por lo tanto, salvo que el usuario utilice en el futuro una función claramente identificada que permita expresamente guardar o exportar audio:

**Echo Visualizer no crea grabaciones del audio que analiza.**

Esto incluye, entre otros:

* música;
* audio de videojuegos;
* películas;
* llamadas;
* contenido multimedia;
* sonidos generados por otras aplicaciones.

La Aplicación utiliza únicamente la información necesaria en tiempo real para generar el resultado visual.

---

## 7. Micrófono

Echo Visualizer puede capturar el micrófono u otros dispositivos de entrada de audio disponibles en Windows **únicamente cuando el usuario selecciona expresamente dicho dispositivo** como fuente para la visualización.

Este acceso se utiliza exclusivamente para generar visualizaciones basadas en la señal recibida.

Echo Visualizer no transmite ni almacena automáticamente el audio obtenido mediante el micrófono.

El acceso a dispositivos de entrada está sujeto a los controles de privacidad proporcionados por Windows. El usuario puede administrar dichos permisos desde la configuración de privacidad de Windows (`ms-settings:privacy-microphone`) y revocarlos en cualquier momento, incluso sin desinstalar la Aplicación.

---

## 8. Información personal

Echo Visualizer no requiere crear una cuenta para utilizar sus funciones principales.

Salvo que se indique expresamente dentro de la Aplicación, Echo Visualizer no solicita ni recopila directamente información como:

* nombre;
* apellidos;
* domicilio;
* número telefónico;
* correo electrónico;
* fecha de nacimiento;
* documentos de identificación;
* información financiera;
* contactos;
* mensajes;
* contraseñas;
* ubicación precisa;
* identificadores biométricos.

No se intenta vincular el contenido de audio procesado con la identidad de una persona.

---

## 9. Cuentas de usuario

Echo Visualizer actualmente **no requiere una cuenta propia** para utilizar la Aplicación.

La instalación realizada mediante Microsoft Store puede estar asociada a una cuenta Microsoft como parte del funcionamiento de Microsoft Store o Windows.

Ese procesamiento es realizado por Microsoft y está sujeto a las políticas y condiciones de Microsoft, no a esta Política de Privacidad de Echo Visualizer.

Microsoft mantiene su propia declaración de privacidad para los datos procesados por sus productos y servicios.

---

## 10. Datos de diagnóstico y telemetría

Echo Visualizer **no opera un sistema propio de telemetría remota** y no envía al desarrollador, de manera intencionada, información sobre:

* aplicaciones utilizadas;
* contenido de audio reproducido;
* canciones reproducidas;
* hábitos de escucha;
* archivos personales;
* historial de navegación;
* actividad realizada en otras aplicaciones.

Con fines de diagnóstico durante el funcionamiento activo, la Aplicación puede escribir localmente en la carpeta de datos locales de la aplicación en Windows (`%LOCALAPPDATA%\EchoVisualizer`):

* un registro de errores de inicio (`startup-errors.log`);
* métricas agregadas de análisis de audio (`telemetry\spectral-*.csv`) con valores numéricos agregados de nivel, potencia y amplitud.

Estos archivos:

* no contienen audio, ni contenido de archivos, ni bandas espectrales completas;
* no identifican al usuario;
* no se transmiten a ningún servidor;
* pueden eliminarse junto con los datos de la Aplicación.

Windows, Microsoft Store, .NET, Windows App SDK u otros componentes de la plataforma pueden generar sus propios datos de diagnóstico conforme a la configuración de privacidad del sistema operativo. Dichos datos son procesados por los respectivos proveedores y no constituyen una recopilación realizada directamente por Echo Visualizer.

---

## 11. Informes de errores

Echo Visualizer no envía automáticamente informes de errores a servidores administrados por el desarrollador.

Windows puede generar registros, volcados de memoria u otra información diagnóstica como parte de sus propios mecanismos de funcionamiento y diagnóstico.

El usuario puede, voluntariamente, proporcionar registros o información de diagnóstico al desarrollador cuando solicita soporte.

La información enviada voluntariamente para soporte se utilizará únicamente para investigar y resolver el problema correspondiente.

---

## 12. Configuración y preferencias

Echo Visualizer puede guardar localmente determinadas preferencias necesarias para mantener la configuración seleccionada por el usuario.

Por ejemplo:

* visualizador seleccionado;
* parámetros visuales;
* colores;
* sensibilidad;
* configuración del audio;
* dispositivo seleccionado;
* opciones de interfaz;
* tema;
* presets;
* configuración general de la Aplicación.

Esta información se guarda localmente en la carpeta de datos locales de la aplicación en Windows y no se utiliza para identificar al usuario.

Salvo que se indique expresamente lo contrario, estas preferencias no se sincronizan con servidores administrados por Echo Visualizer.

---

## 13. Archivos locales

Si alguna funcionalidad permite seleccionar archivos locales, Echo Visualizer accederá únicamente a los archivos que sean necesarios para realizar la acción solicitada por el usuario.

La Aplicación no analiza de forma general el contenido del sistema de archivos con fines de seguimiento o recopilación de información personal.

Los archivos del usuario no se transmiten a servidores externos operados por Echo Visualizer salvo que una funcionalidad específica lo indique expresamente antes de hacerlo.

---

## 14. Conexiones a Internet

Las funciones principales de procesamiento y visualización de audio de Echo Visualizer están diseñadas para funcionar localmente.

Cuando la Aplicación realice conexiones a Internet, estas podrán utilizarse exclusivamente para funcionalidades claramente identificadas, tales como:

* comprobar actualizaciones;
* abrir documentación;
* acceder al repositorio del proyecto;
* abrir enlaces proporcionados por la interfaz;
* recuperar contenido explícitamente solicitado por el usuario.

Echo Visualizer no utiliza una conexión a Internet para transmitir silenciosamente el contenido de audio analizado.

---

## 15. Microsoft Store

Cuando Echo Visualizer se obtiene mediante Microsoft Store, Microsoft puede procesar determinada información relacionada con:

* descarga;
* instalación;
* actualizaciones;
* licencia;
* compras, cuando corresponda;
* funcionamiento de Microsoft Store;
* estadísticas de distribución;
* diagnósticos de la plataforma.

Este procesamiento es realizado por Microsoft y está sujeto a la [Declaración de Privacidad de Microsoft](https://www.microsoft.com/es-mx/privacy/privacystatement).

Echo Visualizer no controla las prácticas independientes de procesamiento de información realizadas por Microsoft Store o Windows.

---

## 16. GitHub

Echo Visualizer también puede ser distribuido o desarrollado públicamente mediante GitHub.

Cuando un usuario visita GitHub, descarga una release, abre una issue, participa en discussions o interactúa con el repositorio, GitHub puede procesar información conforme a sus propios términos y políticas.

Echo Visualizer no controla la información que GitHub recopila directamente a través de sus servicios.

---

## 17. Servicios de terceros

Echo Visualizer puede utilizar bibliotecas, frameworks o componentes de terceros necesarios para su funcionamiento.

Esto puede incluir tecnologías como:

* .NET;
* Windows App SDK;
* WinUI;
* componentes nativos de Windows;
* bibliotecas de procesamiento de audio;
* bibliotecas open source.

La inclusión de una biblioteca no implica necesariamente que dicha biblioteca transmita información fuera del dispositivo.

Cuando una dependencia externa incorpore un servicio que procese información del usuario, esta Política de Privacidad será actualizada para reflejarlo cuando corresponda.

---

## 18. Publicidad

Echo Visualizer actualmente **no utiliza redes publicitarias** y no realiza seguimiento del usuario con fines de publicidad personalizada.

La Aplicación no vende información del usuario a anunciantes.

---

## 19. Venta de información personal

Echo Visualizer **no vende información personal**.

Asimismo, no intercambia información personal por contraprestación económica con empresas de publicidad, data brokers u organizaciones similares.

---

## 20. Compartición de información

Dado que Echo Visualizer está diseñado principalmente para procesar información localmente, el desarrollador normalmente no recibe el contenido procesado por la Aplicación.

En consecuencia, Echo Visualizer no comparte rutinariamente información personal con terceros.

Podría ser necesario revelar información únicamente cuando:

1. el usuario la proporcione voluntariamente para recibir soporte;
2. exista una obligación legal válida;
3. sea necesario proteger la seguridad del proyecto, usuarios o infraestructura;
4. el usuario solicite expresamente una funcionalidad que requiera interacción con un tercero.

En tales casos, se limitará la información al mínimo necesario.

---

## 21. Conservación de datos

Echo Visualizer no mantiene una base de datos central de usuarios para proporcionar sus funciones principales.

La información procesada exclusivamente en memoria para generar visualizaciones se conserva solamente durante el tiempo necesario para realizar dicho procesamiento.

Las preferencias y diagnósticos locales podrán permanecer en el dispositivo hasta que:

* el usuario los elimine;
* restablezca la configuración;
* desinstale la Aplicación;
* Windows elimine los datos de la aplicación.

La información que el usuario proporcione voluntariamente para soporte podrá conservarse durante el tiempo razonablemente necesario para resolver la solicitud y mantener registros técnicos o de seguridad cuando corresponda.

---

## 22. Seguridad

Echo Visualizer procura aplicar medidas razonables destinadas a proteger la confidencialidad e integridad de la información procesada por la Aplicación.

Entre estas medidas se encuentra la reducción de transferencias de información y la preferencia por procesamiento local.

No obstante, ningún software, sistema operativo o método de almacenamiento puede garantizar seguridad absoluta.

Los usuarios deben mantener Windows y la Aplicación actualizados para beneficiarse de las correcciones de seguridad disponibles.

---

## 23. Permisos de Windows

Determinadas funcionalidades pueden requerir acceso a recursos administrados por Windows.

Los permisos disponibles dependen de la versión de Windows, configuración del dispositivo y APIs utilizadas.

Cuando Windows proporcione controles específicos de privacidad para un recurso, el usuario puede modificarlos desde la configuración del sistema.

Echo Visualizer no intenta eludir los mecanismos de seguridad o privacidad proporcionados por Windows.

---

## 24. Decisiones automatizadas y perfilado

Echo Visualizer no utiliza la información procesada por la Aplicación para realizar decisiones automatizadas que produzcan efectos jurídicos o significativamente similares sobre el usuario.

Tampoco crea perfiles personales basados en:

* contenido de audio;
* preferencias musicales;
* aplicaciones utilizadas;
* comportamiento;
* características personales.

El análisis matemático del audio tiene únicamente el propósito de producir visualizaciones.

---

## 25. Inteligencia artificial

Echo Visualizer no utiliza el contenido de audio del usuario para entrenar modelos de inteligencia artificial.

Salvo que se comunique expresamente en una versión futura, el audio procesado por la Aplicación no se transmite a proveedores de modelos de IA ni a servicios generativos externos.

---

## 26. Menores de edad

Echo Visualizer no está diseñado específicamente para recopilar información personal de menores de edad.

Dado que las funciones principales se realizan localmente y no requieren la creación de una cuenta, Echo Visualizer no solicita intencionadamente datos personales de menores.

Si en el futuro se incorporan servicios en línea destinados a recopilar información personal, se implementarán las medidas correspondientes conforme a las leyes aplicables.

---

## 27. Derechos de privacidad

Dependiendo del lugar de residencia del usuario, las leyes aplicables pueden reconocer derechos relacionados con sus datos personales, tales como:

* conocer qué información se procesa;
* solicitar acceso;
* solicitar rectificación;
* solicitar eliminación;
* oponerse a determinados tratamientos;
* solicitar limitación;
* retirar consentimiento cuando el procesamiento se base en este;
* presentar una reclamación ante la autoridad competente.

Debido a que las funciones principales de Echo Visualizer se ejecutan localmente y el desarrollador no recibe normalmente la información procesada, es posible que no exista información personal almacenada por el desarrollador sobre la cual ejercer alguno de estos derechos.

Cuando el desarrollador sí mantenga información identificable —por ejemplo, un correo enviado voluntariamente al soporte—, las solicitudes podrán dirigirse a: josepolanco4569@gmail.com

---

## 28. Usuarios de México

Cuando corresponda, el tratamiento de datos personales relacionado directamente con el desarrollador deberá realizarse respetando las disposiciones aplicables en México.

Echo Visualizer está diseñado para minimizar la recopilación de información, por lo que las funciones principales no requieren la transferencia del contenido de audio al desarrollador.

---

## 29. Transferencias internacionales

Echo Visualizer no realiza transferencias internacionales del contenido de audio procesado localmente.

No obstante, si el usuario interactúa con plataformas de terceros como Microsoft Store o GitHub, estas empresas pueden procesar información mediante infraestructura ubicada en diferentes países conforme a sus propias políticas.

---

## 30. Código abierto

Cuando Echo Visualizer se distribuya como software de código abierto, los usuarios podrán inspeccionar el código fuente publicado para comprender mejor cómo funciona la Aplicación.

La disponibilidad del código fuente proporciona transparencia adicional, pero no sustituye esta Política de Privacidad ni las obligaciones que correspondan al desarrollador.

---

## 31. Cambios en esta Política de Privacidad

Esta Política de Privacidad podrá actualizarse cuando:

* se agreguen nuevas funcionalidades;
* cambie la forma en que se procesan datos;
* se incorporen servicios de terceros;
* cambien los requisitos legales;
* cambien los requisitos de Microsoft Store;
* sea necesario proporcionar información adicional a los usuarios.

Cuando se realicen cambios materiales, se actualizará la fecha indicada al principio de este documento.

Cuando corresponda, los cambios importantes podrán comunicarse mediante el repositorio, la Aplicación, Microsoft Store u otros canales oficiales del proyecto.

---

## 32. Versiones anteriores

Cuando resulte razonable, las versiones anteriores de esta Política de Privacidad podrán conservarse públicamente en el repositorio oficial de Echo Visualizer, permitiendo consultar los cambios realizados a lo largo del tiempo.

---

## 33. Aplicaciones y servicios externos

Echo Visualizer puede permitir abrir enlaces o interactuar con aplicaciones externas.

Una vez que el usuario abandona Echo Visualizer, el tratamiento de información realizado por el servicio externo queda sujeto a la política de privacidad de dicho servicio.

El desarrollador de Echo Visualizer no controla las prácticas de privacidad de terceros independientes.

---

## 34. Cambios futuros en las prácticas de datos

Si Echo Visualizer incorpora en el futuro funcionalidades como:

* sincronización en la nube;
* cuentas de usuario;
* telemetría remota;
* crash reporting remoto;
* almacenamiento en servidores;
* servicios de inteligencia artificial;
* publicidad;
* compras gestionadas mediante infraestructura propia;
* servicios online;
* compartición de presets;
* estadísticas de uso;

esta Política de Privacidad deberá actualizarse antes o al momento de activar dichas funciones según corresponda.

Cuando una funcionalidad requiera consentimiento, este se solicitará de acuerdo con los requisitos aplicables.

---

## 35. Contacto

Si tienes preguntas, inquietudes o solicitudes relacionadas con esta Política de Privacidad, puedes comunicarte con:

**Echo Visualizer**
**Responsable:** José Antonio Polanco Oxté
**Correo:** josepolanco4569@gmail.com
**Repositorio:** https://github.com/Jose-Polanco-Oxte/Echos-Live-Music-Visualizer
**País:** México

---

## Resumen de privacidad

Echo Visualizer está diseñado bajo un modelo de procesamiento local.

En su configuración actual:

**Audio**

* Se utiliza para generar visualizaciones.
* Se procesa localmente.
* No se transmite a servidores de Echo Visualizer.
* No se vende.
* No se utiliza para publicidad.
* No se utiliza para entrenar IA.
* No se almacena como grabación.

**Información personal**

* No se requiere cuenta.
* No se solicita nombre, dirección o teléfono.
* No se crea un perfil del usuario.

**Telemetría**

* Echo Visualizer no dispone de telemetría remota propia; solo escribe métricas agregadas y registros de diagnóstico locales en el dispositivo.

**Configuración**

* Las preferencias pueden almacenarse localmente en el dispositivo.

**Terceros**

* Microsoft Store, Windows, GitHub y otros servicios externos aplican sus propias políticas cuando el usuario interactúa con ellos.