# IdeaPad Flex 5 14ARE05: el touchpad deja de funcionar tras cada reinicio en Linux (ELAN06FA)

[English](README.md) | **Español**

En los kernels recientes de Linux, el touchpad ELAN06FA del **Lenovo IdeaPad
Flex 5 14ARE05** solo funciona si el portátil se enciende con el cargador
desconectado. Tras cualquier reinicio normal, o un apagado con el cargador
conectado, el touchpad desaparece hasta que se le vuelve a quitar toda la
energía.

Este repositorio explica por qué ocurre e incluye una solución pequeña que
funciona con **Secure Boot activado**.

## Síntomas

- El touchpad funciona tras un arranque en frío sin cargador y desaparece tras un
  reinicio. No aparece en `libinput list-devices` ni en `xinput`, y no hay ningún
  mensaje de error.
- La pantalla táctil y el lápiz siguen funcionando.
- En el registro del kernel de un arranque con el fallo aparece esta línea, y
  después no aparece el dispositivo `ELAN06FA:00 04F3:3140 Touchpad`:

  ```
  i2c_designware AMDI0010:03: [Firmware Bug]: DSDT uses known not-working I2C bus speed 400000, forcing it to 100000
  ```

## Causa

El commit del kernel [`bfd74cd1fbc0`](https://git.kernel.org/torvalds/c/bfd74cd1fbc0)
("i2c: Force ELAN06FA touchpad I2C bus freq to 100KHz", Linux 6.14) fuerza el
bus I2C de todos los touchpads ELAN06FA a 100 kHz, para corregir un "suavizado
excesivo" que se observó a 400 kHz en otros portátiles (por ejemplo, el Lenovo
V15 G4). Algunas distribuciones también lo incorporaron a kernels anteriores (el
kernel 6.8 de Ubuntu lo incluye).

El firmware del Flex 5 14ARE05 pide **400 kHz**, la velocidad que usa Windows. En
este portátil, tras un reinicio en caliente el touchpad deja de responder de
forma fiable a 100 kHz y el driver se rinde sin avisar. A 400 kHz funciona tras
cada reinicio, y cambiar el bus a 400 kHz incluso recupera un touchpad que ya
estaba bloqueado.

La investigación completa, con las mediciones y todo lo que se descartó, está en
[docs/DIAGNOSIS.es.md](docs/DIAGNOSIS.es.md).

## Probado en

| | |
|---|---|
| Portátil | Lenovo IdeaPad Flex 5 14ARE05 (81X2), Ryzen 5 4500U |
| BIOS / EC | EECN44WW (04-09-2023) / EEEC21WW |
| Touchpad | ELAN06FA (04F3:3140) en el controlador I2C AMDI0010:03, dirección 0x15 |
| Sistema | Linux Mint 22.3 (base Ubuntu 24.04), kernel 7.0 HWE, Secure Boot activado |

Uso real durante 18 días con la versión 1.0: 24 arranques, 3 de ellos
reinicios en caliente; el touchpad se recuperó al primer intento en todos, sin
ningún fallo. A 400 kHz el touchpad se siente normal (sin suavizado ni
retraso). La versión 1.1 usa el mismo mecanismo y solo cambia cómo localiza el
controlador del touchpad y cómo informa de los fallos; su verificación en el
mismo portátil está **pendiente**. La cantidad de reinicios en caliente
probados todavía es pequeña: se agradecen los reportes.

## ¿Me afecta?

```bash
./tools/check.sh
```

Solo lee información del sistema (no necesita root) e indica si el touchpad
ELAN06FA está presente, si su bus está forzado a 100 kHz, si se detectó en este
arranque y si la solución está activa.

Con el touchpad fallando también puedes ver cómo no responde en el bus (necesita
`i2c-tools`):

```bash
sudo ./tools/ack-test.sh
```

Un touchpad sano responde 20/20; uno bloqueado responde solo a veces, o nunca.

## Instalación

Requisitos: `dkms` y las cabeceras del kernel (`linux-headers-$(uname -r)`).

```bash
git clone https://github.com/Jheiden7/ideapad-flex5-14are05-touchpad-fix.git
cd ideapad-flex5-14are05-touchpad-fix
sudo ./install.sh
```

Después reinicia normalmente y ejecuta `./tools/check.sh`. Tras un reinicio en
caliente debería indicar `bus was switched to 400 kHz in this boot`; también
puedes consultar `journalctl -b -u elan06fa-400khz`.

### Secure Boot

DKMS firma el módulo con la clave MOK del equipo. En Ubuntu y Linux Mint esa
clave ya existe (`/var/lib/shim-signed/mok/MOK.der`), pero hay que registrarla
una vez; si no, el kernel rechaza el módulo. El instalador avisa si no está
registrada. Para registrarla:

```bash
sudo mokutil --import /var/lib/shim-signed/mok/MOK.der
```

Elige una contraseña de un solo uso, reinicia y, en la pantalla azul *MOK
management*, selecciona **Enroll MOK → Continue → Yes**, escribe la contraseña y
reinicia. Pulsa una tecla antes de 10 segundos o la pantalla se salta. Usa una
contraseña sencilla (minúsculas y números): esa pantalla usa la distribución de
teclado estadounidense.

## Cómo funciona

1. Un módulo del kernel muy pequeño coloca una kretprobe sobre
   `i2c_acpi_find_bus_speed()`. Cuando el kernel consulta la velocidad del
   controlador I2C del touchpad (que localiza a través del padre ACPI del
   touchpad) y obtiene los 100 kHz forzados, el módulo devuelve 400 kHz. Los
   demás buses no se tocan, y el módulo solo se carga en el modelo probado.
2. El driver del controlador I2C viene integrado en el kernel y se inicializa
   antes de que se pueda cargar cualquier módulo. Por eso, un servicio de arranque
   (`elan06fa-400khz.service`) comprueba si el touchpad se detectó. Si no, vuelve
   a conectar el controlador, que detecta el touchpad de nuevo a 400 kHz. Tras un
   arranque en frío el touchpad ya funciona y el servicio no hace nada.
3. DKMS recompila y firma el módulo para cada kernel nuevo, siempre que estén
   instaladas sus cabeceras.

## Desinstalación

```bash
sudo ./install.sh uninstall
```

## Preguntas frecuentes

**¿Y las actualizaciones del kernel?** DKMS recompila el módulo automáticamente.
Compruébalo con `dkms status elan06fa-400khz`; si falta el kernel nuevo, instala
su paquete `linux-headers`.

**¿Y si un kernel futuro cambia algo?** Si la función interceptada cambia de
nombre o el módulo no compila, simplemente no se carga, y el touchpad vuelve al
comportamiento original (funciona tras un arranque en frío). Nada empeora.

**¿Otro portátil con touchpad ELAN06FA?** No está probado. Si `tools/check.sh`
muestra el mismo patrón, puedes probarlo bajo tu responsabilidad añadiendo
`options elan06fa_400khz force=1` en `/etc/modprobe.d/elan06fa-400khz.conf`, y
abre un issue con el resultado.

**¿Aparece "loading out-of-tree module taints kernel" en el registro?** Es
normal: el módulo no forma parte del kernel oficial. Es inofensivo.

**¿Por qué no quitar directamente la excepción?** Habría que recompilar el
kernel. La solución correcta es en el kernel oficial: excluir este modelo de
`i2c_acpi_force_100khz_device_ids`, o encontrar la causa real (el commit
original sospecha de los valores de temporización I2C que se usan por defecto
cuando el firmware no los define).

## Estado en el kernel oficial

Aún no se ha reportado. En [upstream/](upstream/README.md) hay un borrador de
parche para el kernel que exime a este modelo de la excepción de 100 kHz; cuando
algo así se incorpore, el módulo dejará de ser necesario. Si te afecta, un
reporte a la [lista de correo linux-i2c](https://lore.kernel.org/linux-i2c/) que
haga referencia a este repositorio ayudaría.

## Licencia

[GPL-2.0](LICENSE), la licencia requerida para los módulos del kernel de Linux.

Diagnóstico y solución por Jheiden7, desarrollados con la ayuda de Claude
(Anthropic).
