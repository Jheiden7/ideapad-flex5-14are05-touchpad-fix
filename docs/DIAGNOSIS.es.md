# Diagnóstico

[English](DIAGNOSIS.md) | **Español**

Cómo se encontró la causa, qué se midió y qué se descartó por el camino.
Equipo: Lenovo IdeaPad Flex 5 14ARE05 (81X2), BIOS EECN44WW, EC EEEC21WW,
Linux Mint 22.3 con kernel 7.0.0-14-generic y Secure Boot activado.

## 1. El patrón del síntoma

En Windows el touchpad funcionaba tras cualquier reinicio. En Linux solo
funcionaba al encender con el cargador desconectado. Lo confirmó el cruce de dos
semanas de registros de arranque (cómo terminó el arranque anterior, si el
cargador estaba conectado y si apareció el dispositivo del touchpad):

| Apagado anterior | Cargador al arrancar | Touchpad |
|---|---|---|
| Reinicio | conectado | falla, siempre |
| Apagado corto (1–2 min) | conectado | falla, casi siempre |
| Apagado largo (de noche) o apagado sin cargador | cualquiera | funciona, casi siempre |

Con el cargador conectado, el touchpad conserva la alimentación durante un
reinicio o un apagado, así que nunca llega a reiniciarse del todo. Solo quitarle
toda la energía lo recupera.

## 2. Qué pasa al arrancar

En un arranque con el fallo, `i2c_hid_acpi` no logra detectar el touchpad y no
registra nada: su primera lectura de la dirección I2C del dispositivo no recibe
confirmación, así que la detección devuelve `-ENXIO` (el mensaje solo se muestra
en modo depuración). Al forzar a mano la vinculación del driver se obtiene
`No such device or address` o, cuando el dispositivo responde a la primera
lectura, `failed to fetch HID descriptor: -121`.

En la DSDT el dispositivo es `\_SB.I2CD.TPDD`, conectado al controlador I2C
`AMDI0010:03`:

```
I2cSerialBusV2 (0x0015, ControllerInitiated, 0x00061A80, ...)   // dirección 0x15, 400 kHz
GpioInt (Level, ActiveLow, ExclusiveAndWake, PullUp, ...) { 0x0009 }
Method (_PS0, 0, NotSerialized) { }   // vacío
Method (_PS3, 0, NotSerialized) { }   // vacío
```

La DSDT pide 400 kHz, pero desde Linux 6.14 el kernel lo sustituye:

```
i2c_designware AMDI0010:03: [Firmware Bug]: DSDT uses known not-working I2C bus speed 400000, forcing it to 100000
```

## 3. Medición del bus

Con el driver desvinculado, leer 20 veces la dirección del touchpad (cada
0,25 s, con `i2cget`) muestra claramente la diferencia (`S` = confirmado,
`.` = sin respuesta):

| Estado del touchpad | Respuestas |
|---|---|
| Sano (tras un arranque en frío) | `SSSSSSSSSSSSSSSSSSSS` (20/20) |
| Tras un reinicio en caliente | `..S......S..S.....SS` (~25 %), a veces `....................` |

El touchpad está vivo (cuando se le pilló respondiendo devolvió incluso un
descriptor HID válido, 04F3:3140), pero solo responde a veces, así que las
muchas transferencias de una detección completa nunca llegan a completarse.

## 4. Hipótesis descartadas

Todo lo siguiente se probó con el touchpad bloqueado, sin éxito:

| Hipótesis | Prueba | Resultado |
|---|---|---|
| Carrera en la detección al arrancar | Vincular `i2c_hid_acpi` muchas veces, sincronizado con los momentos en que el dispositivo respondía | sigue fallando |
| Estado del controlador I2C | Desvincular y volver a vincular `i2c_designware` | sigue fallando |
| Touchpad en reposo HID | Enviar a mano `SET_POWER(ON)` y `RESET` de HID (`i2ctransfer`) | los acepta, pero sigue respondiendo solo ~25 % |
| Causado por la orden `SLEEP` del apagado | Desvincular el driver y dejar el touchpad despierto justo antes de reiniciar | falla igualmente tras el reinicio |
| El touchpad necesita un corte de corriente | Apagar y encender el touchpad desde el EC (`ideapad_laptop touchpad_ctrl_via_ec=1`) durante 3 s y durante 60 s | deja de responder mientras está apagado (no se sabe si el EC le corta la corriente o solo lo aísla); sigue bloqueado después |
| El controlador necesita un reinicio por hardware | Ejecutar el método ACPI `RSET` del controlador (reinicio AOAC, que Linux nunca usa) con `acpi_call` | se ejecuta bien (`0x0`); sigue bloqueado |
| Estado de la plataforma | Suspender (S3) y reanudar | sigue bloqueado |
| Línea de interrupción sin pull-up | El GPIO 9 tenía el pull-up desactivado en un arranque con el fallo; activarlo | en otros arranques con el fallo ya estaba activado; sin cambios |
| Estado del EC | Volcar los 256 registros del EC (`ec_sys`, solo lectura) en ambos estados | los campos del touchpad son idénticos; solo cambian valores de batería y temperatura |
| Ajustes de la BIOS | Revisar el menú de configuración (no hay opción de arranque rápido) | nada relevante |
| Kernel anterior | El kernel 6.8.0-142 de Ubuntu | también fuerza 100 kHz (excepción incorporada) |

Como reiniciar todo lo relativo al touchpad no cambiaba nada, la variable que
quedaba era lo único que Windows y Linux hacen distinto: la velocidad del bus.

## 5. La prueba decisiva

El kernel mainline 6.13 (kernel.ubuntu.com) es anterior a la excepción, así que
mantiene los 400 kHz de la DSDT. No está firmado, así que para esta prueba se
desactivó Secure Boot. (La clave DKMS que crea Ubuntu está restringida a firmar
módulos y no sirve para firmar un kernel.) Cuatro reinicios en caliente
seguidos, con el cargador conectado:

| Kernel | Velocidad del bus | El arranque anterior terminó con | Touchpad |
|---|---|---|---|
| 6.13 | 400 kHz | reinicio | funciona |
| 7.0 | 100 kHz | reinicio | **falla** |
| 7.0 | 100 kHz | reinicio | **falla** |
| 6.13 | 400 kHz | reinicio (desde el 7.0 con el fallo) | funciona |

A 400 kHz el touchpad sobrevive a todos los reinicios, y la última fila demuestra
que los 400 kHz también recuperan un touchpad que se había bloqueado a 100 kHz.

## 6. La solución

Como el touchpad se puede recuperar a posteriori, no hace falta un kernel
modificado: basta con un módulo que cambie la velocidad de este único bus y con
volver a conectar el controlador después del arranque. Ver "Cómo funciona" en el
[README](../README.es.md).

Con la solución (versión 1.0) en el 7.0.0-14 (Secure Boot activado, módulo
firmado con la clave MOK):

```
i2c_designware AMDI0010:03: [Firmware Bug]: DSDT uses known not-working I2C bus speed 400000, forcing it to 100000
elan06fa_400khz: active for AMDI0010:03
i2c_designware AMDI0010:03: [Firmware Bug]: DSDT uses known not-working I2C bus speed 400000, forcing it to 100000
elan06fa_400khz: AMDI0010:03: bus speed 100 kHz -> 400 kHz
input: ELAN06FA:00 04F3:3140 Touchpad as /devices/platform/AMDI0010:03/i2c-4/i2c-ELAN06FA:00/...
```

En 18 días de uso normal con la versión 1.0: 24 arranques, 21 en frío (el
touchpad ya funcionaba y el servicio no hizo nada) y 3 reinicios en caliente,
todos recuperados al primer intento. La versión 1.1 mantiene el mismo mecanismo y
se verificó tras un reinicio en caliente:

```
[    0.29] i2c_designware AMDI0010:03: [Firmware Bug]: DSDT uses known not-working I2C bus speed 400000, forcing it to 100000
[    3.98] elan06fa_400khz: active for AMDI0010:03
[    5.50] elan06fa_400khz: AMDI0010:03: bus speed 100 kHz -> 400 kHz
[    5.58] input: ELAN06FA:00 04F3:3140 Touchpad as /devices/platform/AMDI0010:03/i2c-1/i2c-ELAN06FA:00/...
[    6.01] elan06fa-400khz-rescan: Touchpad recovered at 400 kHz (attempt 1).
```

## 7. Preguntas abiertas

- **¿Por qué 100 kHz solo falla tras un reinicio en caliente?** No se sabe. El
  commit original señala que el dispositivo funciona en Windows a 400 kHz y
  sospecha de los contadores de nivel alto y bajo de SCL (HCNT/LCNT) que el
  driver designware calcula por defecto cuando la DSDT no los define, como ocurre
  aquí. También es posible que el firmware hable con el touchpad a 400 kHz
  durante un arranque en caliente y lo deje en un estado que no tolera 100 kHz.
- **¿Aparece a 400 kHz en este modelo el "suavizado excesivo" que motivó la
  excepción?** No se ha observado: el touchpad se siente normal.
- **¿Otros portátiles con ELAN06FA?** Sin probar.
