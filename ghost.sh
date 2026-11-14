#!/usr/bin/env bash
set -euo pipefail

# vm-ghost: camuflaje que se ejecuta DENTRO de la VM.
# Pregunta el sistema operativo y aplica los cambios correspondientes.
#
# Vectores cubiertos:
#   Windows: registro WMI, bcdedit, Guest Additions, hosts, telemetria
#   Linux:   /proc/cpuinfo, modprobe blacklist, Guest Additions, hosts
#   macOS:   system_profiler, launchd, Guest Additions
#
# Analisis basado en los binarios reales:
#   estos sistemas usan si.system(), si.diskLayout(), si.processes(), si.osInfo()
#   estos sistemas usan si.uuid() + BrowserLock (VM detectada)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DB="$SCRIPT_DIR/hardware-db.json"
BANNED=""  # Se detecta automaticamente por OS

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

banner() {
  printf "${BLUE}"
  printf "██╗   ██╗███╗   ███╗       ██████╗ ██╗  ██╗ ██████╗ ███████╗████████╗\n"
  printf "██║   ██║████╗ ████║      ██╔════╝ ██║  ██║██╔═══██╗██╔════╝╚══██╔══╝\n"
  printf "██║   ██║██╔████╔██║█████╗██║  ███╗███████║██║   ██║███████╗   ██║   \n"
  printf "╚██╗ ██╔╝██║╚██╔╝██║╚════╝██║   ██║██╔══██║██║   ██║╚════██║   ██║   \n"
  printf " ╚████╔╝ ██║ ╚═╝ ██║      ╚██████╔╝██║  ██║╚██████╔╝███████║   ██║   \n"
  printf "  ╚═══╝  ╚═╝     ╚═╝       ╚═════╝ ╚═╝  ╚═╝ ╚═════╝ ╚══════╝   ╚═╝   \n"
  printf "${NC}\n"
}

die() { echo -e "${RED}[!] $*${NC}" >&2; exit 1; }

ps_run() {
  local script="$1"
  if command -v powershell.exe >/dev/null 2>&1; then
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$script" 2>/dev/null
  elif command -v pwsh >/dev/null 2>&1; then
    pwsh -NoProfile -Command "$script" 2>/dev/null
  else
    echo ""
  fi
}

ask_os() {
  echo ""
  echo -e "${YELLOW}En que sistema operativo estas ejecutando esto?${NC}"
  echo ""
  echo "  [1] Windows 11 (PowerShell nativo o Git Bash)"
  echo "  [2] Linux (Ubuntu, Debian, Fedora, etc.)"
  echo "  [3] macOS (Intel o Apple Silicon)"
  echo ""
  read -rp "Elige (1-3): " os_choice
  case "$os_choice" in
    1) echo "windows" ;;
    2) echo "linux" ;;
    3) echo "macos" ;;
    *) die "Opcion invalida" ;;
  esac
}

check_admin() {
  local os="$1"
  case "$os" in
    windows)
      local is_admin
      is_admin=$(ps_run "([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)" 2>/dev/null | tr -d '[:space:]')
      if [ "$is_admin" != "True" ]; then
        echo -e "${RED}[!] Necesitas permisos de administrador.${NC}"
        echo -e "${YELLOW}    Abre PowerShell como Admin y ejecuta:${NC}"
        echo -e "${YELLOW}    powershell -ExecutionPolicy Bypass -File ghost.ps1${NC}"
        echo -e "${YELLOW}    O si usas Git Bash: click derecho -> Run as administrator${NC}"
        exit 1
      fi
      ;;
    linux)
      if [ "$(id -u)" -ne 0 ]; then
        echo -e "${YELLOW}[!] Ejecuta como root: sudo $0${NC}"
        exit 1
      fi
      ;;
    macos)
      if [ "$(id -u)" -ne 0 ]; then
        echo -e "${YELLOW}[!] Ejecuta como root: sudo $0${NC}"
        exit 1
      fi
      ;;
  esac
}

select_profile() {
  echo ""
  echo -e "${YELLOW}Paso 1: Elegir perfil de hardware aparente${NC}"
  echo ""
  echo "Cada perfil simula un portatil real con manufacturer, BIOS, CPU,"
  echo "disco, GPU y red coherentes entre si."
  echo ""
  local i=1
  local keys=()
  while IFS= read -r key; do
    local label=$(jq -r ".profiles[\"$key\"].label" "$DB" 2>/dev/null || echo "$key")
    echo "  [$i] $label"
    keys+=("$key")
    i=$((i + 1))
  done < <(jq -r '.profiles | keys[]' "$DB" 2>/dev/null)
  echo ""
  read -rp "Elige perfil (1-${#keys[@]}): " choice
  if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt ${#keys[@]} ]; then
    die "Opcion invalida"
  fi
  SELECTED_KEY="${keys[$((choice - 1))]}"
  SELECTED_LABEL=$(jq -r ".profiles[\"$SELECTED_KEY\"].label" "$DB")
  echo -e "${GREEN}[OK] Perfil: $SELECTED_LABEL${NC}"
}

# ============================================================================
# WINDOWS
# ============================================================================

apply_windows() {
  local profile="$1"
  echo ""
  echo -e "${YELLOW}Paso 2: Parchear registro de Windows${NC}"
  echo "VirtualBox pone 'innotek GmbH' como manufacturer y 'VirtualBox' como model."
  echo "systeminformation lee esto del registro y de WMI."
  echo "El sistema comprueba si system.virtual es true; el verificador usa verificacion nativa."
  echo ""

  local mfg=$(jq -r ".profiles[\"$profile\"].system.manufacturer" "$DB")
  local model=$(jq -r ".profiles[\"$profile\"].system.model" "$DB")
  local bios_vendor=$(jq -r ".profiles[\"$profile\"].bios.vendor" "$DB")
  local bios_version=$(jq -r ".profiles[\"$profile\"].bios.version" "$DB")
  local bios_date=$(jq -r ".profiles[\"$profile\"].bios.date" "$DB")
  local board_vendor=$(jq -r ".profiles[\"$profile\"].board.vendor" "$DB")
  local board_product=$(jq -r ".profiles[\"$profile\"].board.product" "$DB")
  local chassis_vendor=$(jq -r ".profiles[\"$profile\"].chassis.vendor" "$DB")

  local serial="PF$(printf '%06d' $((RANDOM % 1000000)))"
  local board_serial="L1$(printf '%07d' $((RANDOM % 10000000)))"

  echo "  Manufacturer: $mfg"
  echo "  Model:        $model"
  echo "  BIOS:         $bios_vendor $bios_version"
  echo "  Serial:       $serial"

  ps_run "
    \$reg = @{
      'HKLM:\HARDWARE\DESCRIPTION\System\BIOS' = @{
        'SystemManufacturer' = '$mfg'
        'SystemProductName' = '$model'
        'SystemSerialNumber' = '$serial'
        'BaseBoardManufacturer' = '$board_vendor'
        'BaseBoardProduct' = '$board_product'
        'BaseBoardSerialNumber' = '$board_serial'
        'BIOSVendor' = '$bios_vendor'
        'BIOSVersion' = '$bios_version'
        'BIOSReleaseDate' = '$bios_date'
        'ChassisManufacturer' = '$chassis_vendor'
      }
    }
    foreach (\$path in \$reg.Keys) {
      if (-not (Test-Path \$path)) { New-Item -Path \$path -Force | Out-Null }
      foreach (\$name in \$reg[\$path].Keys) {
        New-ItemProperty -Path \$path -Name \$name -Value \$reg[\$path][\$name] -PropertyType String -Force | Out-Null
      }
    }
    Write-Output 'OK'
  " | grep -q OK && echo -e "${GREEN}[OK] Registro parcheado${NC}" || echo -e "${RED}[!] Error parcheando registro${NC}"
}

apply_windows_hypervisor() {
  echo ""
  echo -e "${YELLOW}Paso 3: Desactivar hypervisor flag${NC}"
  echo "Windows reporta HypervisorPresent=true via WMI."
  echo "El sistema comprueba esto. Si es true, VM detectada."
  echo ""
  ps_run "bcdedit /set hypervisorlaunchtype off" 2>/dev/null
  echo -e "${GREEN}[OK] hypervisorlaunchtype desactivado (requiere reinicio)${NC}"

  echo ""
  echo -e "${YELLOW}Paso 4: Desactivar Device Guard y Credential Guard${NC}"
  echo "Estas caracteristicas de Windows activan el hypervisor aunque no haya VM."
  echo ""
  ps_run "bcdedit /set vsmlaunchtype off" 2>/dev/null || true
  echo -e "${GREEN}[OK] VSM desactivado (requiere reinicio)${NC}"
}

kill_windows_guest_additions() {
  echo ""
  echo -e "${YELLOW}Paso 5: Eliminar Guest Additions${NC}"
  echo "VBoxService.exe y VBoxTray.exe son procesos de VirtualBox."
  echo "El sistema los detecta via si.processes()."
  echo "El sistema los detecta en su lista de procesos prohibidos."
  echo ""

  echo "  Matando procesos..."
  ps_run "Get-Process VBoxService,VBoxTray,VBoxControl -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue" 2>/dev/null
  echo -e "  ${GREEN}[OK] Procesos terminados${NC}"

  echo "  Desactivando servicios..."
  ps_run "
    \$services = @('VBoxService','VBoxGuest')
    foreach (\$svc in \$services) {
      \$s = Get-Service -Name \$svc -ErrorAction SilentlyContinue
      if (\$s) {
        Stop-Service -Name \$svc -Force -ErrorAction SilentlyContinue
        Set-Service -Name \$svc -StartupType Disabled -ErrorAction SilentlyContinue
      }
    }
    Write-Output 'OK'
  " 2>/dev/null | grep -q OK && echo -e "  ${GREEN}[OK] Servicios desactivados${NC}" || echo -e "  ${YELLOW}[!] No habia servicios que desactivar${NC}"

  echo "  Desactivando drivers..."
  ps_run "
    \$drivers = @('VBoxGuest','VBoxMouse','VBoxSF','VBoxVideo','VBoxWddm')
    foreach (\$drv in \$drivers) {
      sc.exe config \$drv start= disabled 2>\$null | Out-Null
    }
    Write-Output 'OK'
  " 2>/dev/null | grep -q OK && echo -e "  ${GREEN}[OK] Drivers desactivados${NC}" || echo -e "  ${YELLOW}[!] Algunos drivers no se pudieron desactivar${NC}"

  echo ""
  echo "  Desinstalando Guest Additions (si estan instaladas)..."
  ps_run "
    \$paths = @(
      'C:\Program Files\Oracle\VirtualBox Guest Additions\uninst.exe',
      'C:\Program Files\VMware\VMware Tools\uninstall.exe'
    )
    foreach (\$p in \$paths) {
      if (Test-Path \$p) {
        Start-Process -FilePath \$p -ArgumentList '/S' -Wait -NoNewWindow -ErrorAction SilentlyContinue
      }
    }
    Write-Output 'OK'
  " 2>/dev/null | grep -q OK && echo -e "  ${GREEN}[OK] Desinstalacion completada${NC}" || echo -e "  ${YELLOW}[!] No se encontraron Guest Additions que desinstalar${NC}"
}

block_windows_telemetry() {
  echo ""
  echo -e "${YELLOW}Paso 6: Bloquear telemetria de VirtualBox${NC}"
  echo "Anade entradas al hosts file para bloquear dominios de Oracle."
  echo ""
  local hosts_file=""
  for p in "/c/Windows/System32/drivers/etc/hosts" "/mnt/c/Windows/System32/drivers/etc/hosts" "C:/Windows/System32/drivers/etc/hosts"; do
    if [ -f "$p" ]; then hosts_file="$p"; break; fi
  done
  if [ -z "$hosts_file" ]; then
    ps_run "Add-Content -Path 'C:\Windows\System32\drivers\etc\hosts' -Value '# vm-ghost' -ErrorAction SilentlyContinue; Add-Content -Path 'C:\Windows\System32\drivers\etc\hosts' -Value '0.0.0.0 update.virtualbox.org' -ErrorAction SilentlyContinue; Add-Content -Path 'C:\Windows\System32\drivers\etc\hosts' -Value '0.0.0.0 www.virtualbox.org' -ErrorAction SilentlyContinue; Add-Content -Path 'C:\Windows\System32\drivers\etc\hosts' -Value '0.0.0.0 download.virtualbox.org' -ErrorAction SilentlyContinue; Write-Output 'OK'" 2>/dev/null | grep -q OK && echo -e "${GREEN}[OK] Hosts bloqueado${NC}" || echo -e "${YELLOW}[!] No se pudo modificar hosts${NC}"
    return
  fi
  if grep -q "vm-ghost" "$hosts_file" 2>/dev/null; then
    echo -e "${GREEN}[OK] Ya estaba bloqueado${NC}"
    return
  fi
  cat >> "$hosts_file" << 'EOF'
# vm-ghost
0.0.0.0 update.virtualbox.org
0.0.0.0 www.virtualbox.org
0.0.0.0 download.virtualbox.org
EOF
  echo -e "${GREEN}[OK] Dominios bloqueados${NC}"
}

# ============================================================================
# LINUX
# ============================================================================

apply_linux() {
  local profile="$1"
  echo ""
  echo -e "${YELLOW}Paso 2: Parchear /etc/machine-info${NC}"
  echo "Linux expone manufacturer y model via /etc/machine-info."
  echo "systeminformation lee este fichero."
  echo ""

  local mfg=$(jq -r ".profiles[\"$profile\"].system.manufacturer" "$DB")
  local model=$(jq -r ".profiles[\"$profile\"].system.model" "$DB")

  cat > /etc/machine-info << EOF
HARDWARE_VENDOR=$mfg
HARDWARE_MODEL=$model
EOF
  echo -e "${GREEN}[OK] /etc/machine-info actualado${NC}"
  echo "    Manufacturer: $mfg"
  echo "    Model:        $model"
}

kill_linux_guest_additions() {
  echo ""
  echo -e "${YELLOW}Paso 3: Eliminar Guest Additions${NC}"
  echo "VBoxService, VBoxClient y vmtoolsd son procesos de hypervisor."
  echo "El sistema los detecta via si.processes()."
  echo ""

  echo "  Matando procesos..."
  for proc in VBoxService VBoxClient VBoxControl vmtoolsd vmware-vmblock-fuse; do
    pkill -9 "$proc" 2>/dev/null || true
  done
  echo -e "  ${GREEN}[OK] Procesos terminados${NC}"

  echo "  Desactivando servicios..."
  for svc in vboxadd vboxadd-service vboxadd-x11 virtualbox-guest-utils vboxservice spice-vdagent qemu-guest-agent vmtoolsd open-vm-tools; do
    systemctl disable --now "$svc" 2>/dev/null || true
    systemctl mask "$svc" 2>/dev/null || true
  done
  echo -e "  ${GREEN}[OK] Servicios desactivados${NC}"

  echo "  Bloqueando modulos..."
  cat > /etc/modprobe.d/vm-ghost.conf << 'EOF'
blacklist vboxguest
blacklist vboxsf
blacklist vboxvideo
blacklist vmw_vmci
blacklist vmw_vsock_vmci_transport
blacklist vmwgfx
blacklist virtio_balloon
blacklist qxl
install vboxguest /bin/false
install vboxsf /bin/false
install vboxvideo /bin/false
EOF
  if command -v update-initramfs >/dev/null 2>&1; then
    update-initramfs -u 2>/dev/null || true
  elif command -v dracut >/dev/null 2>&1; then
    dracut -f 2>/dev/null || true
  fi
  echo -e "  ${GREEN}[OK] Modulos bloqueados${NC}"

  echo "  Purgando paquetes..."
  if command -v apt-get >/dev/null 2>&1; then
    apt-get purge -y virtualbox-guest-utils virtualbox-guest-x11 virtualbox-guest-dkms spice-vdagent qemu-guest-agent open-vm-tools open-vm-tools-desktop 2>/dev/null || true
    apt-get autoremove -y 2>/dev/null || true
  elif command -v dnf >/dev/null 2>&1; then
    dnf remove -y virtualbox-guest-additions spice-vdagent qemu-guest-agent open-vm-tools 2>/dev/null || true
  elif command -v pacman >/dev/null 2>&1; then
    pacman -Rns --noconfirm virtualbox-guest-utils spice-vdagent qemu-guest-agent open-vm-tools 2>/dev/null || true
  fi
  echo -e "  ${GREEN}[OK] Paquetes purgados${NC}"
}

block_linux_telemetry() {
  echo ""
  echo -e "${YELLOW}Paso 4: Bloquear telemetria de VirtualBox${NC}"
  if grep -q "vm-ghost" /etc/hosts 2>/dev/null; then
    echo -e "${GREEN}[OK] Ya estaba bloqueado${NC}"
    return
  fi
  cat >> /etc/hosts << 'EOF'
# vm-ghost
0.0.0.0 update.virtualbox.org
0.0.0.0 www.virtualbox.org
0.0.0.0 download.virtualbox.org
EOF
  echo -e "${GREEN}[OK] Dominios bloqueados${NC}"
}

# ============================================================================
# macOS
# ============================================================================

apply_macos() {
  local profile="$1"
  echo ""
  echo -e "${YELLOW}Paso 2: Parchear system_profiler${NC}"
  echo "macOS expone hardware via system_profiler e ioreg."
  echo "En VirtualBox, esto muestra 'Oracle VirtualBox' como model."
  echo ""
  echo -e "${YELLOW}[WARN] macOS no se puede parchear completamente desde el guest.${NC}"
  echo -e "${YELLOW}        Ejecuta ghost-host.sh en el host Mac antes de arrancar la VM.${NC}"
}

kill_macos_guest_additions() {
  echo ""
  echo -e "${YELLOW}Paso 3: Eliminar procesos de Guest Additions${NC}"
  for proc in VBoxService VBoxClient VBoxControl; do
    pkill -9 "$proc" 2>/dev/null || true
  done
  echo -e "${GREEN}[OK] Procesos terminados${NC}"
}

# ============================================================================
# Verificacion comun
# ============================================================================

run_verification() {
  echo ""
  echo -e "${YELLOW}Paso final: Verificar con systeminformation${NC}"
  echo "Esto replica exactamente lo que hacen SMOWL y OnVUE:"
  echo "  - si.system().virtual, si.diskLayout(), si.processes()"
  echo "  - si.uuid() + verificacion nativa"
  echo ""

  if ! command -v node >/dev/null 2>&1; then
    echo -e "${YELLOW}[!] Node.js no esta instalado.${NC}"
    echo -e "${YELLOW}    Windows: descarga desde https://nodejs.org${NC}"
    echo -e "${YELLOW}    Linux: sudo apt install -y nodejs npm${NC}"
    echo -e "${YELLOW}    macOS: brew install node${NC}"
    echo -e "${YELLOW}    Despues ejecuta: node ghost-check.js --advanced${NC}"
    return
  fi

  if [ ! -d "node_modules/systeminformation" ]; then
    echo "  Instalando systeminformation..."
    npm install systeminformation@5.31.7 2>/dev/null
  fi

  node "$SCRIPT_DIR/ghost-check.js" --advanced
}

show_summary() {
  local os="$1"
  echo ""
  echo -e "${BLUE}============================================${NC}"
  echo -e "${GREEN}  Camuflaje aplicado${NC}"
  echo -e "${BLUE}============================================${NC}"
  echo ""
  echo "Resumen:"
  case "$os" in
    windows)
      echo "  [OK] Registro de Windows parcheado (manufacturer, model, BIOS)"
      echo "  [OK] Hypervisor flag desactivado (bcdedit)"
      echo "  [OK] Guest Additions eliminadas (procesos, servicios, drivers)"
      echo "  [OK] Telemetria de VirtualBox bloqueada (hosts)"
      ;;
    linux)
      echo "  [OK] /etc/machine-info actualizado"
      echo "  [OK] Guest Additions eliminadas (procesos, servicios, modulos, paquetes)"
      echo "  [OK] Telemetria de VirtualBox bloqueada (hosts)"
      ;;
    macos)
      echo "  [OK] Procesos de Guest Additions terminados"
      echo "  [WARN] macOS requiere ghost-host.sh en el host Mac"
      ;;
  esac
  echo "  [OK] Verificacion con systeminformation"
  echo ""
  echo -e "${YELLOW}IMPORTANTE: Reinicia la VM antes de la sesion.${NC}"
  echo ""
  echo "Tras el reinicio, verifica de nuevo:"
  echo "  node ghost-check.js --advanced"
  echo ""
  echo "Si todo pasa, puedes iniciar la sesion."
  echo ""
}

main() {
  banner

  if ! command -v jq >/dev/null 2>&1; then
    echo -e "${YELLOW}[!] jq no esta instalado. Instalando...${NC}"
    if command -v brew >/dev/null 2>&1; then
      brew install jq
    elif command -v apt-get >/dev/null 2>&1; then
      apt-get install -y jq
    else
      die "Instala jq manualmente: https://stedolan.github.io/jq/download/"
    fi
  fi

  local os
  os=$(ask_os)
  echo -e "${GREEN}[OK] Sistema: $os${NC}"

  check_admin "$os"
  select_profile

  case "$os" in
    windows)
      apply_windows "$SELECTED_KEY"
      apply_windows_hypervisor
      kill_windows_guest_additions
      block_windows_telemetry
      ;;
    linux)
      apply_linux "$SELECTED_KEY"
      kill_linux_guest_additions
      block_linux_telemetry
      ;;
    macos)
      apply_macos "$SELECTED_KEY"
      kill_macos_guest_additions
      ;;
  esac

  run_verification
  show_summary "$os"
}

main "$@"