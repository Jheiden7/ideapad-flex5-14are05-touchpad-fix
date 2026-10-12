# IdeaPad Flex 5 14ARE05: el touchpad deja de funcionar tras cada reinicio en Linux (ELAN06FA)

[English](README.md) | **Español**

[![CI](https://github.com/Jheiden7/ideapad-flex5-14are05-touchpad-fix/actions/workflows/ci.yml/badge.svg)](https://github.com/Jheiden7/ideapad-flex5-14are05-touchpad-fix/actions/workflows/ci.yml)
<sub>La integración continua solo comprueba que el módulo compila contra las
cabeceras de los kernels de Ubuntu y que los scripts pasan shellcheck; la
solución en sí se prueba en el portátil.</sub>

En los kernels recientes de Linux, el touchpad ELAN06FA del **Lenovo IdeaPad
Flex 5 14ARE05** deja de funcionar tras un reinicio normal, y solo vuelve cuando
el portátil pasa un tiempo sin energía.

Este repositorio explica por qué ocurre e incluye una solución pequeña que
funciona con **Secure Boot activado**.

> **Términos usados aquí.** Un **arranque en caliente** es un reinicio, o un
> apagado corto con el cargador conectado: el touchpad conserva la alimentación
> y no llega a reiniciarse de verdad. Un **arranque en frío** es un encendido
> después de que el touchpad perdió de verdad la alimentación: el portátil
> estuvo apagado sin cargador, o apagado durante horas.

## Síntomas

- Tras un arranque en frío el touchpad funciona; tras uno en caliente
  desaparece. No aparece en `libinput list-devices` ni en `xinput`, y no hay
  ningún mensaje de error.
- La pantalla táctil y el lápiz siguen funcionando.
- En un kernel afectado, esta línea aparece en el registro del kernel en
  **todos** los arranques; es el cambio que provoca el problema, no una señal de
  que ese arranque fallara:

  ```
  i2c_designware AMDI0010:03: [Firmware Bug]: DSDT uses known not-working I2C bus speed 400000, forcing it to 100000
  ```

  Lo que distingue un arranque con el fallo es que después no aparece el
  dispositivo `ELAN06FA:00 04F3:3140 Touchpad`.

## Causa

El commit del kernel [`bfd74cd1fbc0`](https://git.kernel.org/torvalds/c/bfd74cd1fbc0)
("i2c: Force ELAN06FA touchpad I2C bus freq to 100KHz", Linux 6.14) fuerza el
bus I2C de todos los touchpads ELAN06FA a 100 kHz, para corregir un "suavizado
excesivo" que se observó a 400 kHz en otros portátiles (por ejemplo, el Lenovo
V15 G4). Algunas distribuciones también lo incorporaron a kernels anteriores (el
kernel 6.8.0-142 de Ubuntu lo incluye).

El firmware del Flex 5 14ARE05 pide **400 kHz**, que según ese mismo commit es
también la velocidad con la que el touchpad funciona en Windows. En este
portátil, tras un arranque en caliente el touchpad deja de responder de forma
fiable a 100 kHz y el driver se rinde sin avisar. A 400 kHz funcionó en todos
los reinicios en caliente probados hasta ahora, y cambiar el bus a 400 kHz
incluso recupera un touchpad que ya estaba bloqueado.

La investigación completa, con las mediciones y todo lo que se descartó, está en
[docs/DIAGNOSIS.es.md](docs/DIAGNOSIS.es.md).

## Probado en

| | |
|---|---|
| Portátil | Lenovo IdeaPad Flex 5 14ARE05 (81X2), Ryzen 5 4500U |
| BIOS / EC | EECN44WW (04-09-2023) / EEEC21WW |
| Touchpad | ELAN06FA (04F3:3140) en el controlador I2C AMDI0010:03, dirección 0x15 |
| Sistema | Linux Mint 22.3 (base Ubuntu 24.04), kernel 7.0 HWE, Secure Boot activado |

Solo está probado en la familia Debian/Ubuntu (los scripts sugieren comandos
`apt`). Otras distribuciones necesitan DKMS y las cabeceras del kernel, y no
están probadas.

Resultados hasta ahora: 7 reinicios en caliente a 400 kHz, todos con el touchpad
funcionando (2 con un kernel mainline 6.13, anterior a la excepción, y 5 con la
solución). La versión 1.0 se usó durante 18 días: de 24 arranques, 21 fueron en
frío y el touchpad ya funcionaba, y 3 fueron reinicios en caliente, todos
recuperados al primer intento. Las versiones 1.1 y 1.2 se verificaron en el
mismo portátil; la 1.2 recuperó el touchpad tras un reinicio en caliente y pasó
a 400 kHz uno que ya funcionaba tras un arranque en frío. El servicio tardó
entre 1 y 6 s en las pruebas medidas (registrar la intercepción en el kernel
puede ser lento mientras el sistema aún arranca), y la versión final, probada
tanto tras un reinicio en caliente como tras un arranque en frío, no retrasa la
pantalla de inicio de sesión.
A 400 kHz el touchpad se siente normal (sin suavizado ni retraso). La muestra
todavía es pequeña: si lo pruebas,
[cuéntanos el resultado](https://github.com/Jheiden7/ideapad-flex5-14are05-touchpad-fix/issues/new?template=test-report.yml),
funcione o no (el formulario está en inglés, pero se aceptan reportes en
español).

## ¿Me afecta?

Ejecuta esto **justo después de un arranque en caliente** (un reinicio normal
con el cargador conectado), antes de instalar nada:

```bash
./tools/check.sh
```

Solo lee información del sistema (no necesita root). En un portátil afectado y
sin la solución, termina así:

```
Touchpad
  [ok]   ELAN06FA touchpad present in ACPI
  [--]   attached to I2C controller AMDI0010:03
  [!!]   the kernel forces this bus to 100 kHz (the quirk behind the problem)
  [!!]   touchpad is NOT bound to a driver (not working in this boot)
...
Verdict: affected (bus forced to 100 kHz, touchpad not probed); the fix is not installed.
```

Te afecta si el touchpad está presente, el bus está forzado a 100 kHz y el
touchpad **no está vinculado** a un driver tras un arranque en caliente. Tras un
arranque en frío el touchpad funciona, así que un solo arranque en frío no
demuestra nada.

En ese estado de fallo también puedes ver cómo el touchpad no responde en el bus
(necesita `i2c-tools`):

```bash
sudo ./tools/ack-test.sh
```

Un touchpad bloqueado responde solo a algunas lecturas, o a ninguna. Como
referencia, uno sano respondió 20/20 con su driver desvinculado a mano (ver
[docs/DIAGNOSIS.es.md](docs/DIAGNOSIS.es.md)).

## Instalación

Requisitos: `dkms` y las cabeceras del kernel (`linux-headers-$(uname -r)`).

1. Clona el repositorio y ejecuta el instalador:

   ```bash
   git clone https://github.com/Jheiden7/ideapad-flex5-14are05-touchpad-fix.git
   cd ideapad-flex5-14are05-touchpad-fix
   sudo ./install.sh
   ```

2. Si el instalador mostró un **aviso de Secure Boot**, registra primero la
   clave de firma (ver abajo); si no, el kernel rechazará el módulo.
3. Reinicia normalmente y ejecuta `./tools/check.sh`. Debería terminar con
   `Verdict: affected, and the fix is working (touchpad at 400 kHz).`

### Secure Boot

DKMS firma el módulo con la clave MOK del equipo, que hay que registrar una vez.
El instalador indica si está registrada y muestra su ruta: en Ubuntu y Linux
Mint es `/var/lib/shim-signed/mok/MOK.der`, y con DKMS original
`/var/lib/dkms/mok.pub`. Para registrarla, usa la ruta que mostró el instalador:

```bash
sudo mokutil --import /var/lib/shim-signed/mok/MOK.der
```

Elige una contraseña de un solo uso, solo con minúsculas y números, porque la
siguiente pantalla usa la distribución de teclado estadounidense. Reinicia:
aparecerá una pantalla azul *MOK management*. **Pulsa una tecla antes de 10
segundos** (o se saltará), elige **Enroll MOK → Continue → Yes**, escribe la
contraseña y reinicia.

## Cómo funciona

1. Un módulo del kernel muy pequeño coloca una kretprobe sobre
   `i2c_acpi_find_bus_speed()`. Cuando el kernel consulta la velocidad del
   controlador I2C del touchpad (que localiza a través del padre ACPI del
   touchpad) y obtiene 100 kHz, el módulo devuelve 400 kHz. Los demás buses no
   se tocan, y el módulo solo se carga en el modelo probado. En este modelo el
   firmware pide 400 kHz, así que una respuesta de 100 kHz solo puede venir de
   la excepción.
2. El driver del controlador I2C viene integrado en el kernel y se inicializa
   antes de que se pueda cargar cualquier módulo. El módulo tampoco tiene un
   alias de hardware, así que quien lo carga, en todos los arranques, es el
   servicio `elan06fa-400khz.service`. Después, si este kernel forzó el bus a
   100 kHz, el servicio vuelve a vincular el controlador a su driver (*rebind*)
   para que el touchpad se detecte de nuevo a 400 kHz:
   - tras un arranque en caliente, esto recupera el touchpad;
   - tras un arranque en frío el touchpad ya funciona, y se pasa a 400 kHz
     (desaparece un momento durante el arranque);
   - si un touchpad que funcionaba a 100 kHz no vuelve a 400 kHz, el servicio
     devuelve el bus a 100 kHz;
   - en un kernel que no fuerza 100 kHz, no hace nada.

   La pantalla de inicio de sesión no espera al servicio: el touchpad se
   detecta en caliente, así que puede empezar a funcionar unos segundos después
   de que aparezca la pantalla de inicio de sesión.
3. DKMS recompila y firma el módulo para cada kernel nuevo, siempre que estén
   instaladas sus cabeceras.

## Actualización y desinstalación

El instalador copia el código del módulo a `/usr/src/elan06fa-400khz-<versión>`,
lo compila con DKMS para cada kernel que tenga sus cabeceras instaladas, e
instala `/usr/local/sbin/elan06fa-400khz-rescan` y
`/etc/systemd/system/elan06fa-400khz.service`. Conserva el repositorio clonado:
hace falta para actualizar o desinstalar.

Para actualizar a una versión nueva:

```bash
git pull && sudo ./install.sh
```

Para desinstalar:

```bash
sudo ./install.sh uninstall
```

Esto elimina todo lo anterior. Quedan dos cosas: el archivo
`/etc/modprobe.d/elan06fa-400khz.conf`, si lo creaste para `force=1` (bórralo a
mano), y la clave MOK registrada, que es inofensiva y la usa también cualquier
otro módulo DKMS.

## Preguntas frecuentes

**¿Y las actualizaciones del kernel?** DKMS recompila el módulo automáticamente.
Comprueba que `dkms status elan06fa-400khz` incluya el kernel nuevo. Si no
aparece, instala el paquete `linux-headers` de ese kernel y vuelve a ejecutar
`sudo ./install.sh`.

**¿Y si un kernel futuro cambia algo?** Si el módulo no compila o no carga, el
servicio aparece en `systemctl --failed` con el mensaje `Could not load
elan06fa_400khz…`, y el touchpad se comporta como sin la solución: funciona tras
un arranque en frío. Si un kernel deja de forzar 100 kHz, el servicio lo detecta
y no hace nada.

**¿Otro portátil con touchpad ELAN06FA?** No está probado. Comprueba primero que
`tools/check.sh`, ejecutado tras un arranque en caliente, muestra el bus forzado
a 100 kHz y el touchpad sin vincular. Ten en cuenta que el módulo sube a 400 kHz
cualquier 100 kHz del bus del touchpad, aunque sea el propio firmware quien pida
100 kHz: revisa antes la velocidad en la entrada `I2cSerialBusV2` del touchpad en
tu DSDT (`acpidump`, `iasl`). Para probarlo bajo tu responsabilidad, añade
`options elan06fa_400khz force=1` en `/etc/modprobe.d/elan06fa-400khz.conf`. Los
scripts esperan el touchpad como `i2c-ELAN06FA:00`, y `tools/ack-test.sh` usa la
dirección 0x15 salvo que indiques `ADDR=0x..`.
[Cuéntanos el resultado](https://github.com/Jheiden7/ideapad-flex5-14are05-touchpad-fix/issues/new?template=test-report.yml).

**¿Aparece "loading out-of-tree module taints kernel" en el registro?** Es
normal: el módulo no forma parte del kernel oficial. Es inofensivo.

**¿Por qué no quitar directamente la excepción?** Habría que recompilar el
kernel. La solución correcta es en el kernel oficial: eximir a este modelo de
`i2c_acpi_force_100khz_device_ids`, o encontrar la causa real (el commit
original sospecha de los valores de temporización I2C que se usan por defecto
cuando el firmware no los define).

## Estado en el kernel oficial

Aún no se ha reportado. En [upstream/](upstream/README.md) (en inglés) hay un
borrador de parche para el kernel que exime a este modelo de la excepción de
100 kHz. Compila, pero todavía no se ha probado arrancando un kernel completo.
Cuando algo así se incorpore, el módulo dejará de ser necesario. Si te afecta,
un reporte a la [lista de correo linux-i2c](https://lore.kernel.org/linux-i2c/)
que haga referencia a este repositorio ayudaría.

## Licencia

[GPL-2.0](LICENSE), la licencia requerida para los módulos del kernel de Linux.

Diagnóstico y solución por Jheiden7, desarrollados con la ayuda de Claude
(Anthropic).
