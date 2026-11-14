```
██╗   ██╗███╗   ███╗       ██████╗ ██╗  ██╗ ██████╗ ███████╗████████╗
██║   ██║████╗ ████║      ██╔════╝ ██║  ██║██╔═══██╗██╔════╝╚══██╔══╝
██║   ██║██╔████╔██║█████╗██║  ███╗███████║██║   ██║███████╗   ██║   
╚██╗ ██╔╝██║╚██╔╝██║╚════╝██║   ██║██╔══██║██║   ██║╚════██║   ██║   
 ╚████╔╝ ██║ ╚═╝ ██║      ╚██████╔╝██║  ██║╚██████╔╝███████║   ██║   
  ╚═══╝  ╚═╝     ╚═╝       ╚═════╝ ╚═╝  ╚═╝ ╚═════╝ ╚══════╝   ╚═╝   
```

# VM-Ghost

VM-Ghost convierte una maquina virtual de VirtualBox en algo indistinguible de un ordenador fisico. Los sistemas de verificacion de entorno no logran detectar que estas ejecutando una maquina virtual.

## Como arrancar

```bash
chmod +x ghost-wizard.sh
./ghost-wizard.sh
```

Eso es todo. El asistente te pregunta si estas en tu ordenador (host) o dentro de la maquina virtual (guest) y te guia paso a paso. No necesitas saber nada de VirtualBox, registros ni CPUID. El wizard hace todo por ti.

Si prefieres ir rapido sin preguntas:

```bash
# En tu ordenador: aplicar perfil Lenovo a la VM "Win11"
./ghost-wizard.sh --vm "Win11" --profile lenovo_thinkpad_t14 --yes

# Dentro de la VM: aplicar parches y verificar
./ghost-wizard.sh --guest-os win --profile lenovo_thinkpad_t14 --yes --check
```

## Que hace VM-Ghost

Cuando arrancas una maquina virtual en VirtualBox, el sistema operativo que corre dentro ve un hardware que delata la virtualizacion en todos lados. El fabricante del sistema dice "innotek GmbH". El modelo dice "VirtualBox". El procesador tiene un bit que dice "soy un hipervisor". Hay procesos llamados VBoxService y VBoxTray corriendo en segundo plano. La direccion de red empieza por 08:00:27, que es el prefijo que Oracle usa para VirtualBox. Las tablas ACPI contienen el texto VBOX. El disco tiene un nombre generico de disco virtual.

Cualquiera de esos vectores basta para que un sistema de verificacion detecte que estas en una maquina virtual.

VM-Ghost borra todas esas huellas. Lo hace en dos fases porque hay cosas que solo se pueden cambiar desde fuera de la maquina virtual (el firmware, el CPUID, la direccion MAC) y hay cosas que solo se pueden cambiar desde dentro (el registro de Windows, los procesos que estan corriendo, los drivers activos, el fichero hosts).

### Fase 1: Host (tu ordenador)

Ejecutas `ghost-wizard.sh` en tu ordenador, donde tienes VirtualBox instalado. El asistente:

1. **Busca VirtualBox** y lista las maquinas virtuales que tienes creadas
2. **Te ofrece 15 portatiles reales** para imitar de 10 fabricantes distintos (Lenovo, Dell, HP, ASUS, Acer, MSI, Razer, Samsung, Microsoft, Huawei). Tambien puedes crear un perfil personalizado campo por campo
3. **Parchea el firmware de la VM** via `VBoxManage setextradata`. Estos son valores que se inyectan en el SMBIOS/DMI que el sistema operativo lee al arrancar:
   - Manufacturer: cambia "innotek GmbH" por "LENOVO", "Dell Inc.", "HP" o "ASUSTeK COMPUTER INC."
   - Model: cambia "VirtualBox" por el modelo real del portatil
   - Serial y UUID: genera valores aleatorios coherentes
   - BIOS vendor, version y fecha: cambia "innotek GmbH" por el fabricante real
   - Board vendor y product: la placa base tambien dice VirtualBox; se cambia por la real
   - Chassis vendor: el chasis tambien delata la VM
4. **Parchea el CPUID**: el procesador que ve la VM es el real de tu ordenador, pero VirtualBox anade un bit que dice "esto es un hipervisor". VM-Ghost lee el CPUID real de tu procesador con `read-cpuid.py`, le quita ese bit (el 31 de ECX en la leaf 0x1) y lo aplica a la VM. Tambien cambia el nombre del procesador (brand string) en las leaves 0x80000002 a 0x80000004 para que diga "Intel Core i5-1335U" en vez del nombre que tu CPU tenga, manteniendo coherencia con el perfil elegido
5. **Parchea el disco**: cambia el numero de serie, el modelo y la revision del firmware del disco virtual por los de un disco real (Samsung 980 PRO, WD Blue SN570, Crucial T500)
6. **Parchea la MAC**: la direccion de red de la VM usa un prefijo OUI real del fabricante (A4:4C:C8 de Lenovo, 8C:8C:AA de Dell, etc.) en vez de 08:00:27 de Oracle
7. **Parchea el ACPI**: cambia el OEM ID para que las tablas ACPI no digan VBOX
8. **Desactiva la paravirtualizacion**: `--paravirtprovider none` elimina las leaves 0x40000000-0x4000000F que los hipervisores exponen
9. **Guarda el perfil** en `profiles/` para que puedas reutilizarlo despues
10. **Genera un informe** en Markdown con todo lo aplicado
11. **Puede arrancar la VM** directamente si se lo pides

Por que se hace en el host: `VBoxManage setextradata` solo funciona desde fuera de la VM. Estos valores se inyectan en el firmware virtual y en el CPUID que la VM ve al arrancar. No se pueden cambiar desde dentro del sistema operativo invitado.

### Fase 2: Guest (dentro de la VM)

Copias la carpeta de VM-Ghost dentro de la maquina virtual (con un USB, descargandola, o por la carpeta compartida) y ejecutas `ghost-wizard.sh` otra vez. El asistente detecta que estas dentro de la VM y hace:

**Si la VM es Windows:**

1. **Parchea el registro WMI**: anade entradas en `HKLM:\HARDWARE\DESCRIPTION\System\BIOS` con el manufacturer, model, serial, BIOS vendor, BIOS version, BIOS date, board vendor, board product y chassis manufacturer del perfil elegido. Windows lee estos valores del registro y los expone via WMI (`Win32_ComputerSystem`, `Win32_BIOS`, `Win32_BaseBoard`). Estos sistemas leen WMI
2. **Desactiva el hypervisor flag**: ejecuta `bcdedit /set hypervisorlaunchtype off` y `bcdedit /set vsmlaunchtype off`. Esto hace que `Win32_ComputerSystem.HypervisorPresent` devuelva false despues del reinicio. Estos sistemas comprueban este campo
3. **Elimina Guest Additions**: mata los procesos VBoxService.exe y VBoxTray.exe, desactiva los servicios VBoxService y VBoxGuest, y desactiva los drivers VBoxGuest, VBoxMouse, VBoxSF, VBoxVideo y VBoxWddm. Estos procesos y drivers son exclusivos de VirtualBox; cualquier sistema que enumere procesos o drivers los encuentra y detecta la VM
4. **Bloquea telemetria**: anade entradas al fichero hosts de Windows para que la VM no pueda contactar con `update.virtualbox.org`, `www.virtualbox.org` ni `download.virtualbox.org`
5. **Verifica**: instala `systeminformation` y ejecuta `ghost-check.js` para confirmar que `si.system().virtual` devuelve false, que no hay procesos prohibidos y que el manufacturer no dice VirtualBox

**Si la VM es Linux:**

1. **Parchea `/etc/machine-info`**: pone `HARDWARE_VENDOR` y `HARDWARE_MODEL` con los valores del perfil. `systeminformation` en Linux lee el manufacturer de este fichero
2. **Elimina Guest Additions**: mata los procesos VBoxService, VBoxClient y vmtoolsd; desactiva los servicios systemd de vboxadd, spice-vdagent, qemu-guest-agent y open-vm-tools; bloquea los modulos del kernel en `/etc/modprobe.d/vm-ghost.conf` (vboxguest, vboxsf, vboxvideo, vmw_vmci, vmwgfx); purga los paquetes apt correspondientes y reconstruye el initramfs
3. **Bloquea telemetria**: anade dominios de VirtualBox al `/etc/hosts`
4. **Verifica**: ejecuta `ghost-check.js` y comprueba que `/proc/cpuinfo` no tiene el flag `hypervisor`

### Fase 3: Reiniciar y verificar

Despues de aplicar los parches del guest hay que reiniciar la VM. Los cambios de `bcdedit` y los drivers no tienen efecto hasta el reinicio.

Tras el reinicio, dentro de la VM:

```bash
node ghost-check.js --advanced
```

Esto replica exactamente lo que hacen estos sistemas: llama a `systeminformation.system()`, `diskLayout()`, `processes()`, `osInfo()` y `uuid()`. Tambien comprueba `HypervisorPresent` en Windows y el flag `hypervisor` en `/proc/cpuinfo` en Linux.

Si todo esta bien, el resultado es:

```
  Findings: 0
  Score: 0/100
  PASS - No se detectaron indicadores de VM
```

Si hay algun finding, el verificador muestra exactamente que vector esta fallando y como arreglarlo.

### Fase 4: Usar la VM

Si la verificacion pasa, antes de usar la VM:

- Cierra VirtualBox Manager en tu ordenador (la ventana que dice "VirtualBox" en el titulo; el sistema de verificacion puede enumerar ventanas activas)
- No uses VPN
- No conectes dispositivos USB
- Usa un solo monitor
- No uses screen sharing ni escritorio remoto

## Que sistemas evade

Los sistemas de verificacion de entorno funcionan de dos formas principales. VM-Ghost cubre ambas.

### Sistemas tipo A: app Electron con Node.js

Estos sistemas instalan una aplicacion de escritorio que usa Node.js internamente y la libreria `systeminformation` para leer el hardware. Laman a `si.system()` y comprueban si `.virtual` es true. Si lo es, leen `si.diskLayout()` para ver el nombre del disco. Tambien enumeran procesos con `si.processes()` y los comparan con un catalogo de 165 programas prohibidos en 17 categorias: maquinas virtuales, herramientas guest, escritorio remoto, captura de pantalla, mensajeria, navegadores, VPN, grabadoras, herramientas de desarrollo y otras. Ademas usan hooks de teclado (`keyspy`), capturas de pantalla (`screenshot-desktop`), monitorizacion del portapapeles (`electron-clipboard-watcher`) y enumeracion de ventanas activas (`get-windows`).

VM-Ghost cubre todos estos vectores: el DMI parcheado hace que `si.system().virtual` devuelva false; el disco cambiado hace que `si.diskLayout().name` no diga "VBOX"; la eliminacion de Guest Additions hace que no haya procesos prohibidos corriendo; el hypervisor bit desactivado hace que Windows no reporte hipervisor.

### Sistemas tipo B: app Electron + verificador nativo Java

Estos sistemas delegan la deteccion a un verificador nativo separado, escrito en Java con Chromium embebido y protegido con ofuscacion comercial. El verificador lee el Machine GUID del registro de Windows o de `ioreg` en macOS, ejecuta comandos del sistema (`bash -c`, `cmd.exe /c`, `system_profiler`), enumera procesos y los clasifica como permitidos, pausados o prohibidos, reporta al servidor cada 15 minutos, y detecta escritorio remoto (RDP), VPN activa, screen sharing, dispositivos USB y monitores multiples. Genera un fichero de salida con flags booleanos: `vmDetected`, `vpnDetected`, `usbDeviceDetected`, `multipleMonitorDetected`, `screenShareDetected`, `rdpDetected`. Si `vmDetected` es true, el exit code es 7 y la sesion se bloquea. Por defecto, las VMs no estan permitidas.

El verificador usa librerias nativas (`libOSXNatives.dylib` en macOS) con modulos para control de procesos (KILL, PAUSE, RESUME), deteccion de perifericos (keyboard, mouse, touchpad), gestion de monitores, deteccion de VPN/RDP/screen sharing, enumeracion de USB y captura de pantalla. La logica exacta que decide `vmDetected = true` esta en clases protegidas con ofuscacion comercial, por lo que no se puede ver que vectores especificos comprueba, pero por las clases accesibles y la libreria nativa sabemos que comprueba procesos, hypervisor, monitores, VPN, USB y screen sharing.

VM-Ghost cubre los vectores accesibles desde el guest: procesos de Guest Additions, hypervisor flag, screen sharing (no lanzarlo), VPN (no usarla), USB (no conectar), monitores (usar uno solo).

### Cobertura por vector

| Vector | Sistema A | Sistema B | VM-Ghost |
|---|---|---|---|
| `si.system().virtual` | Si | - | DMI + hypervisor bit |
| `si.system().manufacturer` | Si | - | DMI vendor |
| `si.system().model` | Si | - | DMI product |
| `si.diskLayout().name` | Si | - | Disco serie/modelo |
| `si.processes()` | Si | Si | Guest Additions eliminadas |
| `si.uuid()` | - | Si | UUID cambiado |
| CPUID hypervisor bit | - | Si | Leaf 0x1 parcheado |
| Machine GUID | - | Si | UUID cambiado |
| Procesos prohibidos | Si | Si | banned-windows.json, banned-macos.json, banned-linux.json |
| Screen sharing | - | Si | No lanzarlo |
| VPN | - | Si | No usarla |
| USB | - | Si | No conectar |
| Monitores multiples | - | Si | Usar uno solo |
| RDP | - | Si | No usar escritorio remoto |

## Sistemas operativos soportados

### Host (donde esta VirtualBox)

| OS | Estado | Notas |
|---|---|---|
| macOS (Intel) | Soportado | Lee CPUID nativo via read-cpuid.py |
| macOS (Apple Silicon) | Soportado | read-cpuid.py no aplica (ARM no usa CPUID x86) |
| Linux (x86_64) | Soportado | Requiere jq, python3, xxd |
| Windows (x86_64) | Soportado | Usa Git Bash, WSL o PowerShell |

### Guest (dentro de la VM)

| OS | Estado | Parches |
|---|---|---|
| Windows 11 | Soportado | Registro WMI, bcdedit, Guest Additions, hosts |
| Windows 10 | Soportado | Igual que Windows 11 |
| Linux (Ubuntu/Debian/Fedora) | Soportado | /etc/machine-info, modprobe, systemd, paquetes, hosts |
| macOS | Parcial | Requiere parches del host; guest limitado |

## Requisitos

### Host

- VirtualBox instalado
- `jq` (macOS: `brew install jq`, Linux: `apt install jq`)
- `python3` (para leer CPUID)
- `xxd` (para CPUID brand string)

### Guest

- Node.js (para verificacion con systeminformation)
- Permisos de administrador

## Perfiles de hardware

| Perfil | Fabricante | CPU | RAM | Disco | GPU | Red |
|---|---|---|---|---|---|---|
| lenovo_thinkpad_t14 | LENOVO | Intel i5-1335U | 16 GB | Samsung 980 PRO | Intel Iris Xe | Intel Wi-Fi 6E AX211 |
| dell_latitude_5440 | Dell Inc. | Intel i7-1365U | 16 GB | WD Blue SN570 | Intel Iris Xe | Intel Wi-Fi 6 AX201 |
| hp_probook_450_g10 | HP | Intel i5-1345U | 16 GB | Crucial T500 | Intel Iris Xe | Intel Wi-Fi 6E AX211 |
| asus_zenbook_14 | ASUS | Intel i7-1255U | 16 GB | Samsung 980 PRO | Intel Iris Xe | Intel Wi-Fi 6 AX201 |
| lenovo_ideapad_5 | LENOVO | AMD Ryzen 7 6800H | 16 GB | Samsung 990 PRO | AMD Radeon 680M | MediaTek MT7921 |
| dell_xps_15 | Dell Inc. | Intel i7-13700H | 32 GB | Samsung 990 PRO | NVIDIA RTX 4060 | Intel Wi-Fi 6E AX211 |
| hp_elitebook_840 | HP | Intel i5-1355U | 16 GB | WD Black SN850X | Intel Iris Xe | Intel Wi-Fi 6E AX211 |
| acer_swift_x | Acer | AMD Ryzen 7 7840HS | 16 GB | Samsung 990 PRO | NVIDIA RTX 4050 | MediaTek MT7922 |
| msi_modern_15 | MSI | Intel i7-1255U | 16 GB | Kingston NV2 | Intel Iris Xe | Intel Wi-Fi 6 AX201 |
| razer_blade_14 | Razer | AMD Ryzen 9 7940HS | 16 GB | Samsung 990 PRO | NVIDIA RTX 4070 | MediaTek MT7922 |
| samsung_galaxy_book3 | Samsung | Intel i7-1360P | 16 GB | Samsung PM9B1 | Intel Iris Xe | Intel Wi-Fi 6E AX211 |
| microsoft_surface_5 | Microsoft | Intel i5-1235U | 16 GB | Samsung PM9B1 | Intel Iris Xe | Intel Wi-Fi 6 AX201 |
| huawei_matebook_14 | HUAWEI | Intel i5-1340P | 16 GB | Samsung 980 PRO | Intel Iris Xe | Intel Wi-Fi 6 AX201 |
| asus_rog_strix_g16 | ASUS | Intel i9-13980HX | 32 GB | Samsung 990 PRO | NVIDIA RTX 4070 | MediaTek MT7922 |
| lenovo_legion_5 | LENOVO | AMD Ryzen 7 7745HX | 32 GB | Samsung 990 PRO | NVIDIA RTX 4070 | Realtek RTL8852BE |

Los perfiles cubren portatiles de 10 fabricantes distintos (Lenovo, Dell, HP, ASUS, Acer, MSI, Razer, Samsung, Microsoft, Huawei) con CPUs Intel y AMD, GPUs integradas (Iris Xe, Radeon) y dedicadas (RTX 4050/4060/4070), y adaptadores de red de Intel, MediaTek y Realtek.

### Perfiles personalizados

El wizard permite crear perfiles a medida. Cada campo es editable:

| Campo | Editable | Descripcion |
|---|---|---|
| Manufacturer | Si | Lenovo, Dell, HP, ASUS, Acer, MSI, Razer, Samsung, Microsoft, Huawei o texto libre |
| Model | Si | Modelo del equipo |
| CPU brand | Si | String que aparece en CPUID |
| CPU cores | Si | 4-16 |
| RAM | Si | En MB |
| Disk model | Si | Modelo del disco |
| Disk firmware | Si | Version del firmware |
| GPU | Si | Nombre de la GPU |
| NIC | Si | Adaptador de red |
| MAC prefix | Si | OUI del fabricante (3 octetos) |
| BIOS vendor | Si | Fabricante del BIOS |
| BIOS version | Si | Version del BIOS |
| BIOS date | Si | Fecha del BIOS |
| Board vendor | Si | Fabricante de la placa |
| Board product | Si | Modelo de la placa |
| Chassis vendor | Si | Fabricante del chasis |
| Chassis type | Si | 10=Laptop, 3=Desktop |
| ACPI OEM | Si | OEM ID de ACPI |

Los perfiles se guardan en `profiles/` y se reutilizan con `--profile <nombre>`.

## Perifericos: webcam, microfono y altavoces

VM-Ghost puede activar la webcam, el microfono y los altavoces en la VM con hardware real para que parezcan dispositivos fisicos.

### Webcam

| Dispositivo | Vendor ID | Product ID |
|---|---|---|
| Logitech C920 HD Pro | 046d | 082d |
| Logitech BRIO 4K | 046d | 085b |
| Microsoft LifeCam HD-3000 | 045e | 0779 |
| Razer Kiyo Pro | 1532 | 0e08 |
| Logitech C270 HD | 046d | 0825 |
| HP W200 | 03f0 | e408 |
| Lenovo 500 FHD | 30de | 6100 |
| AUKEY PC-WM1 | 3344 | 1234 |

VirtualBox permite pasar la webcam por USB passthrough. El wizard activa `--webcam on` y crea un filtro USB con los vendor/product ID reales del modelo elegido.

### Microfono

| Dispositivo | Vendor ID | Product ID |
|---|---|---|
| Logitech H390 Headset | 046d | 0a0c |
| Jabra Evolve2 40 | 0b0e | 03de |
| Blue Yeti X | b58e | 0362 |
| Sennheiser SP 30 | 1395 | 0021 |
| Microsoft LifeCam Mic | 045e | 0779 |
| Plantronics C3220 | 047f | c056 |
| Logitech C920 Mic | 046d | 082d |

### Altavoces

| Dispositivo | Tipo | Notas |
|---|---|---|
| Realtek High Definition Audio | PCI | Integrado generico |
| Intel Smart Sound Technology | PCI | Integrado Intel |
| AMD Audio Coprocessor | PCI | Integrado AMD |
| Lenovo Dolby Audio | PCI | Integrado Lenovo |
| Dell Waves MaxxAudio | PCI | Integrado Dell |
| Logitech Z200 | USB | Externos |
| Jabra Speak 510 | USB | Externos |
| Creative Pebble V3 | USB | Externos |

El wizard activa `--audio-driver default --audioin on --audioout on` en la VM para habilitar entrada y salida de audio.

## Flags del wizard

| Flag | Descripcion |
|---|---|
| `--lang es\|en` | Idioma (por defecto: es) |
| `--vm <nombre>` | Nombre de la VM (modo host) |
| `--profile <key>` | Clave del perfil de hardware-db.json |
| `--guest-os win\|lin` | Forzar modo guest |
| `--check` | Ejecutar verificacion al final |
| `--yes` | No pedir confirmaciones |

## Estructura del proyecto

```
vm-ghost/
  ghost-wizard.sh        # Wizard unificado (host + guest)
  ghost-host.sh          # Script del host (alternativa)
  ghost.sh               # Script del guest (alternativa)
  ghost-check.js         # Verificador
  read-cpuid.py          # Lee CPUID del host para hypervisor bit
  hardware-db.json       # Perfiles de hardware
  banned-windows.json, banned-macos.json, banned-linux.json  # procesos prohibidos por OS (Win: 118, macOS: 125, Linux: 137) en 16 categorias
  profiles/              # Perfiles guardados por el usuario
```

## Procesos prohibidos

El catalogo incluye 3 ficheros separados por OS (`banned-windows.json`, `banned-macos.json`, `banned-linux.json`) con un total de 380 programas en 16 categorias. `ghost-check.js` detecta automaticamente el OS y carga el fichero correspondiente.

Las 16 categorias son:

- Maquinas virtuales y herramientas guest (VirtualBox, VMware, QEMU, Parallels, Hyper-V, Docker, WSL)
- Escritorio remoto (TeamViewer, AnyDesk, RDP, VNC, Splashtop, NoMachine, RustDesk)
- Captura de pantalla (OBS, ShareX, Snagit, Camtasia, Bandicam, Fraps, Xbox Game Bar)
- Mensajeria (WhatsApp, Telegram, Discord, Slack, Teams, Zoom, Skype, Signal, WeChat, Line, Viber, Webex)
- Navegadores secundarios (Chrome, Firefox, Edge, Opera, Brave, Tor)
- VPN y proxy (NordVPN, ExpressVPN, ProtonVPN, OpenVPN, WireGuard, Tailscale, Mullvad)
- Grabadoras de audio y video (Audacity, FL Studio, Reaper, VoiceMeeter, GarageBand, Logic Pro)
- Herramientas de desarrollo (VS Code, IntelliJ, PyCharm, Eclipse, Visual Studio, Android Studio, Xcode)
- Camaras virtuales (OBS Virtual Camera, ManyCam, Snap Camera, DroidCam, Iriun)
- Emuladores (BlueStacks, Nox, LDPlayer, Genymotion, Wine, CrossOver)
- Clientes de bases de datos (DBeaver, MySQL Workbench, pgAdmin, DataGrip, TablePlus)
- Editores de ofimatica (Word, Excel, PowerPoint, Outlook, LibreOffice, Pages, Numbers, Keynote)
- Lectores de PDF (Adobe Acrobat, Foxit, SumatraPDF, Preview, Evince, Okular)
- Reproductores multimedia (VLC, Windows Media Player, iTunes, Spotify, Kodi, MPV)
- Gestores de ficheros (Total Commander, FileZilla, WinSCP, Cyberduck, Midnight Commander)
- Herramientas de pentesting y seguridad (Wireshark, Burp Suite, Nmap, Metasploit, Hashcat, Hydra)

## Limitaciones

1. **VMMDev PCI 0x80ee**: VirtualBox expone un dispositivo PCI con vendor ID de Oracle. No se puede cambiar via setextradata. Si el verificador enumera dispositivos PCI, lo detectara. La mitigacion es desinstalar Guest Additions, que VM-Ghost hace.

2. **ACPI VBOXBIOS**: las tablas ACPI contienen strings internos que no se pueden cambiar via setextradata. El AcpiOemId se parchea, pero el contenido interno no.

3. **Logica protegida**: la logica exacta que decide vmDetected en el verificador nativo esta protegida con ofuscacion comercial. No se puede ver que vectores especificos comprueba, pero se sabe que comprueba procesos, hypervisor, monitores, VPN, USB y screen sharing.

4. **Reinicio obligatorio**: los cambios de bcdedit y drivers requieren reinicio.

5. **Apple Silicon**: read-cpuid.py no funciona en arm64. En Apple Silicon, VirtualBox ARM no usa CPUID leaf 0x1.

## Verificacion manual

Para comprobar manualmente lo que ve el sistema de verificacion dentro de la VM:

```bash
npm install systeminformation@5.31.7
node -e "
const si = require('systeminformation');
si.system().then(s => console.log('virtual:', s.virtual, 'manufacturer:', s.manufacturer, 'model:', s.model));
si.diskLayout().then(d => console.log('disk:', d[0].name, d[0].vendor));
si.processes().then(p => console.log('processes:', p.all));
si.uuid().then(u => console.log('uuid:', u.hardware));
"
```

Si `virtual: false` y `manufacturer` no contiene "VirtualBox" ni "innotek", el camuflaje funciona.

## Changelog

### v0.1.1 (2026-06-20)

- Activacion de webcam en la VM con IDs de hardware real (8 modelos)
- Activacion de microfono con IDs de hardware real (7 modelos)
- Activacion de altavoces con hardware real (8 modelos)
- Seccion `peripherals` en hardware-db.json
- Verificacion de webcam, microfono y altavoces en ghost-check.js --advanced
- USB filter con vendor/product ID reales para la webcam
- Audio in/out activado automaticamente

### v0.1.0 (2026-06-20)

Primera version publica.

- Wizard interactivo con deteccion automatica host/guest
- Parcheo del host: DMI/SMBIOS, CPUID brand string, hypervisor bit, disco, MAC, ACPI, BIOS, paravirtualizacion
- Parcheo del guest: registro WMI (Windows), /etc/machine-info (Linux), bcdedit, Guest Additions, drivers, hosts
- Verificador que replica los vectores de deteccion
- 15 perfiles de hardware predefinidos de 10 fabricantes (Lenovo, Dell, HP, ASUS, Acer, MSI, Razer, Samsung, Microsoft, Huawei)
- Perfiles personalizados guardados en profiles/
- procesos prohibidos por OS (Win: 118, macOS: 125, Linux: 137) en 16 categorias
- Modo no-interactivo con flags
- Multi-idioma (es, en)
- Informes en Markdown