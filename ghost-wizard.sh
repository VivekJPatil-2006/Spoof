#!/usr/bin/env bash
set -euo pipefail

# vm-ghost wizard: asistente interactivo que guia al usuario en todo el proceso.
# Detecta automaticamente si se ejecuta en el host o en el guest.
# Soporta modo no-interactivo con flags.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DB="$SCRIPT_DIR/hardware-db.json"
BANNED=""  # Se detecta automaticamente por OS
PROFILES_DIR="$SCRIPT_DIR/profiles"

# --- Argumentos ---
LANG_OPT="es"
NON_INTERACTIVE=0
VM_NAME=""
PROFILE_KEY=""
RUN_CHECK=0
GUEST_OS=""
YES=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --lang) LANG_OPT="$2"; shift 2 ;;
    --vm) VM_NAME="$2"; shift 2 ;;
    --profile) PROFILE_KEY="$2"; shift 2 ;;
    --guest-os) GUEST_OS="$2"; shift 2 ;;
    --check) RUN_CHECK=1; shift ;;
    --yes) YES=1; shift ;;
    --help|-h)
      echo "Uso: ghost-wizard.sh [opciones]"
      echo ""
      echo "Opciones:"
      echo "  --lang es|en        Idioma (por defecto: es)"
      echo "  --vm <nombre>       Nombre de la VM (modo no-interactivo)"
      echo "  --profile <key>     Clave del perfil de hardware-db.json"
      echo "  --guest-os win|lin  Forzar modo guest (Windows/Linux)"
      echo "  --check             Ejecutar verificacion al final"
      echo "  --yes               No pedir confirmaciones"
      echo "  --help              Esta ayuda"
      exit 0 ;;
    *) echo "Opcion desconocida: $1"; exit 1 ;;
  esac
done

# --- Colores ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# --- Textos multi-idioma ---
declare -A T
if [ "$LANG_OPT" = "en" ]; then
  T[banner]="VM GHOST - Virtual machine camouflage wizard"
  T[host_guest]="Are you running this on the HOST (your computer) or inside the GUEST (the VM)?"
  T[host]="Host (your computer)"
  T[guest]="Guest (inside the VM)"
  T[detect_env]="Detecting environment..."
  T[select_vm]="Select the VirtualBox VM"
  T[select_profile]="Select hardware profile"
  T[custom]="Custom (step by step)"
  T[confirm]="Apply?"
  T[applied]="Camouflage applied"
  T[reboot]="IMPORTANT: Reboot the VM before starting the session."
  T[enter_vm]="Now copy this folder into the VM and run ghost-wizard.sh there."
  T[step]="Step"
  T[of]="of"
  T[manufacturer]="Manufacturer"
  T[model]="Model"
  T[cpu]="CPU"
  T[ram]="RAM (MB)"
  T[cores]="Cores"
  T[disk]="Disk"
  T[gpu]="GPU"
  T[nic]="Network"
  T[mac]="MAC"
  T[bios]="BIOS"
  T[board]="Board"
  T[chassis]="Chassis"
  T[acpi]="ACPI"
  T[review]="Review and confirm"
  T[saved]="Profile saved"
  T[load_profile]="Load saved profile"
  T[no_profiles]="No saved profiles found"
  T[custom_profile]="Customize hardware"
  T[regpatch]="Patching system registry"
  T[guestclean]="Removing Guest Additions"
  T[telemetry]="Blocking telemetry"
  T[verify]="Verifying with systeminformation"
  T[report]="Generating report"
  T[pass]="PASS - No VM indicators detected"
  T[fail]="FAIL - VM indicators detected"
  T[open_nodejs]="Node.js is not installed."
  T[copy_files]="Copy these files into the VM:"
  T[start_vm]="Start the VM now?"
  T[choose]="Choose"
  T[or_custom]="or enter custom value"
  T[edit_field]="Edit this field?"
  T[yes]="Yes"
  T[no]="No"
  T[enter]="Enter"
  T[optional]="(optional)"
else
  T[banner]="VM GHOST - Asistente de camuflaje de maquina virtual"
  T[host_guest]="Estas ejecutando esto en el HOST (tu ordenador) o dentro del GUEST (la VM)?"
  T[host]="Host (tu ordenador)"
  T[guest]="Guest (dentro de la VM)"
  T[detect_env]="Detectando entorno..."
  T[select_vm]="Selecciona la VM de VirtualBox"
  T[select_profile]="Selecciona perfil de hardware"
  T[custom]="Personalizado (paso a paso)"
  T[confirm]="Aplicar?"
  T[applied]="Camuflaje aplicado"
  T[reboot]="IMPORTANTE: Reinicia la VM antes de la sesion."
  T[enter_vm]="Ahora copia esta carpeta dentro de la VM y ejecuta ghost-wizard.sh alli."
  T[step]="Paso"
  T[of]="de"
  T[manufacturer]="Fabricante"
  T[model]="Modelo"
  T[cpu]="CPU"
  T[ram]="RAM (MB)"
  T[cores]="Cores"
  T[disk]="Disco"
  T[gpu]="GPU"
  T[nic]="Red"
  T[mac]="MAC"
  T[bios]="BIOS"
  T[board]="Placa"
  T[chassis]="Chassis"
  T[acpi]="ACPI"
  T[review]="Revision y confirmacion"
  T[saved]="Perfil guardado"
  T[load_profile]="Cargar perfil guardado"
  T[no_profiles]="No hay perfiles guardados"
  T[custom_profile]="Personalizar hardware"
  T[regpatch]="Parcheando registro del sistema"
  T[guestclean]="Eliminando Guest Additions"
  T[telemetry]="Bloqueando telemetria"
  T[verify]="Verificando con systeminformation"
  T[report]="Generando informe"
  T[pass]="PASS - No se detectaron indicadores de VM"
  T[fail]="FAIL - Se detectaron indicadores de VM"
  T[open_nodejs]="Node.js no esta instalado."
  T[copy_files]="Copia estos archivos dentro de la VM:"
  T[start_vm]="Arrancar la VM ahora?"
  T[choose]="Elige"
  T[or_custom]="o introduce valor personalizado"
  T[edit_field]="Editar este campo?"
  T[yes]="Si"
  T[no]="No"
  T[enter]="Introduce"
  T[optional]="(opcional)"
fi

# --- Utilidades ---
t() { echo -n "${T[$1]:-$1}"; }

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

ask() {
  local prompt="$1" default="${2:-}"
  if [ $YES -eq 1 ]; then echo "$default"; return; fi
  echo -ne "${CYON}${prompt}${NC}: " 2>/dev/null || echo -ne "${prompt}: "
  read -r answer
  echo "${answer:-$default}"
}

ask_yn() {
  local prompt="$1"
  if [ $YES -eq 1 ]; then return 0; fi
  echo -ne "${prompt} [s/N]: "
  read -r answer
  case "$(printf '%s' "$answer" | tr '[:upper:]' '[:lower:]')" in
    s|si|y|yes) return 0 ;;
    *) return 1 ;;
  esac
}

select_option() {
  local prompt="$1"; shift
  local options=("$@")
  local n=${#options[@]}
  echo ""
  echo -e "${YELLOW}$prompt${NC}"
  for i in "${!options[@]}"; do
    echo "  [$((i+1))] ${options[$i]}"
  done
  if [ $YES -eq 1 ]; then echo "1"; return; fi
  echo -ne "${CYAN}$(t choose) (1-$n): ${NC}"
  read -r choice
  if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt $n ]; then
    die "Opcion invalida"
  fi
  echo "${options[$((choice-1))]}"
}

select_option_index() {
  local prompt="$1"; shift
  local options=("$@")
  local n=${#options[@]}
  echo ""
  echo -e "${YELLOW}$prompt${NC}"
  for i in "${!options[@]}"; do
    echo "  [$((i+1))] ${options[$i]}"
  done
  if [ $YES -eq 1 ]; then echo "0"; return; fi
  echo -ne "${CYAN}$(t choose) (1-$n): ${NC}"
  read -r choice
  if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt $n ]; then
    die "Opcion invalida"
  fi
  echo "$((choice-1))"
}

CYAN='\033[0;36m'

# --- Deteccion de entorno ---
detect_environment() {
  echo -e "${YELLOW}$(t detect_env)${NC}"

  # Detectar OS
  if [ -n "$GUEST_OS" ]; then
    if [ "$GUEST_OS" = "win" ]; then DETECTED_OS="windows"
    elif [ "$GUEST_OS" = "lin" ]; then DETECTED_OS="linux"
    else DETECTED_OS="unknown"
    fi
  elif command -v powershell.exe >/dev/null 2>&1; then
    DETECTED_OS="windows"
  elif [ -f /proc/version ] && grep -qi microsoft /proc/version 2>/dev/null; then
    DETECTED_OS="windows-wsl"
  elif [ "$(uname -s)" = "Linux" ]; then
    DETECTED_OS="linux"
  elif [ "$(uname -s)" = "Darwin" ]; then
    DETECTED_OS="macos"
  else
    DETECTED_OS="unknown"
  fi

  # Detectar arquitectura
  DETECTED_ARCH=$(uname -m)

  # Detectar VBoxManage
  VBOX=""
  for c in VBoxManage /usr/local/bin/VBoxManage /opt/homebrew/bin/VBoxManage \
           "/Applications/VirtualBox.app/Contents/MacOS/VBoxManage" \
           "/c/Program Files/Oracle/VirtualBox/VBoxManage.exe" \
           "/c/Program Files (x86)/Oracle/VirtualBox/VBoxManage.exe"; do
    if command -v "$c" >/dev/null 2>&1 || [ -x "$c" ]; then
      VBOX="$c"; break
    fi
  done

  # Detectar Node.js
  NODE_BIN=""
  if command -v node >/dev/null 2>&1; then NODE_BIN="node"
  elif command -v node.exe >/dev/null 2>&1; then NODE_BIN="node.exe"
  fi

  echo "  OS:           $DETECTED_OS"
  echo "  Arquitectura:  $DETECTED_ARCH"
  echo "  VBoxManage:   ${VBOX:-no encontrado}"
  echo "  Node.js:      ${NODE_BIN:-no encontrado}"
}

# --- Preguntar host vs guest ---
ask_host_guest() {
  if [ -n "$VM_NAME" ]; then
    echo -e "${GREEN}[OK] Modo host (VM especificada via --vm)${NC}"
    MODE="host"
    return
  fi
  if [ -n "$GUEST_OS" ]; then
    echo -e "${GREEN}[OK] Modo guest (forzado via --guest-os)${NC}"
    MODE="guest"
    return
  fi

  local result
  result=$(select_option "$(t host_guest)" "$(t host)" "$(t guest)")
  if [ "$result" = "$(t host)" ]; then
    MODE="host"
  else
    MODE="guest"
  fi
}

# --- Seleccion de VM ---
select_vm() {
  if [ -z "$VBOX" ]; then
    die "VBoxManage no encontrado. Instala VirtualBox."
  fi
  if [ -n "$VM_NAME" ]; then
    SELECTED_VM="$VM_NAME"
    echo -e "${GREEN}[OK] VM: $SELECTED_VM${NC}"
    return
  fi
  local vms
  vms=$("$VBOX" list vms 2>/dev/null | sed 's/^"\(.*\)" {.*$/\1/')
  if [ -z "$vms" ]; then
    die "No hay VMs en VirtualBox."
  fi
  local vm_array=()
  while IFS= read -r vm; do vm_array+=("$vm"); done <<< "$vms"
  local idx
  idx=$(select_option_index "$(t select_vm)" "${vm_array[@]}")
  SELECTED_VM="${vm_array[$idx]}"
  echo -e "${GREEN}[OK] VM: $SELECTED_VM${NC}"
}

# --- Seleccion de perfil ---
select_profile() {
  local saved_profiles=()
  if [ -d "$PROFILES_DIR" ]; then
    for f in "$PROFILES_DIR"/*.json; do
      [ -f "$f" ] && saved_profiles+=("$(basename "$f" .json)")
    done
  fi

  local builtin=()
  while IFS= read -r key; do
    local label=$(jq -r ".profiles[\"$key\"].label" "$DB" 2>/dev/null)
    builtin+=("$label")
  done < <(jq -r '.profiles | keys[]' "$DB" 2>/dev/null)

  local options=()
  for b in "${builtin[@]}"; do options+=("$b"); done
  if [ ${#saved_profiles[@]} -gt 0 ]; then
    for s in "${saved_profiles[@]}"; do options+=("Guardado: $s"); done
  fi
  options+=("$(t custom)")

  if [ -n "$PROFILE_KEY" ]; then
    local label=$(jq -r ".profiles[\"$PROFILE_KEY\"].label" "$DB" 2>/dev/null)
    if [ -n "$label" ]; then
      SELECTED_PROFILE_KEY="$PROFILE_KEY"
      SELECTED_PROFILE_LABEL="$label"
      SELECTED_PROFILE_SOURCE="builtin"
      echo -e "${GREEN}[OK] Perfil: $label${NC}"
      return
    fi
  fi

  local result
  result=$(select_option "$(t select_profile)" "${options[@]}")

  # Verificar si es un perfil builtin
  local i=0
  while IFS= read -r key; do
    local label=$(jq -r ".profiles[\"$key\"].label" "$DB" 2>/dev/null)
    if [ "$result" = "$label" ]; then
      SELECTED_PROFILE_KEY="$key"
      SELECTED_PROFILE_LABEL="$label"
      SELECTED_PROFILE_SOURCE="builtin"
      echo -e "${GREEN}[OK] Perfil: $label${NC}"
      return
    fi
    i=$((i+1))
  done < <(jq -r '.profiles | keys[]' "$DB" 2>/dev/null)

  # Verificar si es un perfil guardado
  if [[ "$result" == Guardado:* ]]; then
    local name="${result#Guardado: }"
    local pf="$PROFILES_DIR/$name.json"
    SELECTED_PROFILE_KEY="$name"
    SELECTED_PROFILE_LABEL="$name"
    SELECTED_PROFILE_SOURCE="saved"
    SELECTED_PROFILE_FILE="$pf"
    echo -e "${GREEN}[OK] Perfil guardado: $name${NC}"
    return
  fi

  # Custom
  SELECTED_PROFILE_KEY="custom"
  SELECTED_PROFILE_LABEL="Personalizado"
  SELECTED_PROFILE_SOURCE="custom"
  echo -e "${YELLOW}[OK] Perfil personalizado${NC}"
}

# --- Perfil custom ---
custom_profile() {
  echo ""
  echo -e "${YELLOW}$(t custom_profile)${NC}"
  echo "Cada campo muestra el valor por defecto. Pulsa Enter para aceptar o escribe uno nuevo."
  echo ""

  local defaults=$(jq -r '.profiles["lenovo_thinkpad_t14"]' "$DB")

  local mfg=$(jq -r '.system.manufacturer' <<< "$defaults")
  mfg=$(ask "$(t manufacturer) [$mfg]" "$mfg")

  local model=$(jq -r '.system.model' <<< "$defaults")
  model=$(ask "$(t model) [$model]" "$model")

  local cpu_brand=$(jq -r '.cpu.brand' <<< "$defaults")
  cpu_brand=$(ask "$(t cpu) [$cpu_brand]" "$cpu_brand")

  local cores=$(jq -r '.cpu.cores' <<< "$defaults")
  cores=$(ask "$(t cores) [$cores]" "$cores")

  local memory=$(jq -r '.memory' <<< "$defaults")
  memory=$(ask "$(t ram) [$memory]" "$memory")

  local disk_model=$(jq -r '.disk.model' <<< "$defaults")
  disk_model=$(ask "$(t disk) [$disk_model]" "$disk_model")

  local gpu_name=$(jq -r '.gpu.name' <<< "$defaults")
  gpu_name=$(ask "$(t gpu) [$gpu_name]" "$gpu_name")

  local nic_name=$(jq -r '.nic.name' <<< "$defaults")
  nic_name=$(ask "$(t nic) [$nic_name]" "$nic_name")

  local mac_prefix=$(jq -r '.nic.mac_prefix' <<< "$defaults")
  mac_prefix=$(ask "$(t mac) prefix [$mac_prefix]" "$mac_prefix")

  local bios_vendor=$(jq -r '.bios.vendor' <<< "$defaults")
  bios_vendor=$(ask "$(t bios) vendor [$bios_vendor]" "$bios_vendor")

  local bios_version=$(jq -r '.bios.version' <<< "$defaults")
  bios_version=$(ask "$(t bios) version [$bios_version]" "$bios_version")

  local bios_date=$(jq -r '.bios.date' <<< "$defaults")
  bios_date=$(ask "$(t bios) date [$bios_date]" "$bios_date")

  local board_vendor=$(jq -r '.board.vendor' <<< "$defaults")
  board_vendor=$(ask "$(t board) vendor [$board_vendor]" "$board_vendor")

  local board_product=$(jq -r '.board.product' <<< "$defaults")
  board_product=$(ask "$(t board) product [$board_product]" "$board_product")

  local chassis_vendor=$(jq -r '.chassis.vendor' <<< "$defaults")
  chassis_vendor=$(ask "$(t chassis) vendor [$chassis_vendor]" "$chassis_vendor")

  local acpi_oem=$(jq -r '.acpi.oem_id' <<< "$defaults")
  acpi_oem=$(ask "$(t acpi) OEM [$acpi_oem]" "$acpi_oem")

  CUSTOM_JSON=$(cat << JSONEOF
{
  "label": "Personalizado ($mfg $model)",
  "system": {"manufacturer": "$mfg", "model": "$model", "version": "", "serial": ""},
  "bios": {"vendor": "$bios_vendor", "version": "$bios_version", "date": "$bios_date", "major": "1", "minor": "0", "firmware_major": "1", "firmware_minor": "0"},
  "board": {"vendor": "$board_vendor", "product": "$board_product", "version": ""},
  "chassis": {"vendor": "$chassis_vendor", "type": "10"},
  "cpu": {"brand": "$cpu_brand", "cores": $cores, "threads": $cores},
  "memory": $memory,
  "disk": {"model": "$disk_model", "serial_prefix": "S6ZP", "firmware": "5B2QGXA7"},
  "gpu": {"name": "$gpu_name", "pci_name": "$gpu_name"},
  "nic": {"name": "$nic_name", "mac_prefix": "$mac_prefix", "pci_name": "$nic_name"},
  "acpi": {"oem_id": "$acpi_oem", "creator_id": "$acpi_oem", "creator_rev": "20240101"}
}
JSONEOF
)
  SELECTED_PROFILE_KEY="custom"
  SELECTED_PROFILE_LABEL="Personalizado"
  SELECTED_PROFILE_SOURCE="custom"
}

# --- Guardar perfil ---
save_profile() {
  if ask_yn "Guardar perfil para reutilizar despues?"; then
    local name=$(ask "Nombre del perfil" "mi_perfil")
    local out="$PROFILES_DIR/$name.json"
    mkdir -p "$PROFILES_DIR"
    if [ "$SELECTED_PROFILE_SOURCE" = "builtin" ]; then
      jq ".profiles[\"$SELECTED_PROFILE_KEY\"]" "$DB" > "$out"
    elif [ "$SELECTED_PROFILE_SOURCE" = "custom" ]; then
      echo "$CUSTOM_JSON" > "$out"
    fi
    echo -e "${GREEN}[OK] $(t saved): $out${NC}"
  fi
}

# --- Obtener valor del perfil ---
profile_val() {
  local field="$1"
  if [ "$SELECTED_PROFILE_SOURCE" = "builtin" ]; then
    jq -r ".profiles[\"$SELECTED_PROFILE_KEY\"].$field" "$DB"
  elif [ "$SELECTED_PROFILE_SOURCE" = "saved" ]; then
    jq -r ".$field" "$SELECTED_PROFILE_FILE"
  elif [ "$SELECTED_PROFILE_SOURCE" = "custom" ]; then
    echo "$CUSTOM_JSON" | jq -r ".$field"
  fi
}

# --- Revision ---
show_review() {
  echo ""
  echo -e "${BLUE}$(t review)${NC}"
  echo "============================================"
  echo "  $(t manufacturer): $(profile_val system.manufacturer)"
  echo "  $(t model):        $(profile_val system.model)"
  echo "  $(t cpu):          $(profile_val cpu.brand)"
  echo "  $(t cores):        $(profile_val cpu.cores)"
  echo "  $(t ram):          $(profile_val memory) MB"
  echo "  $(t disk):         $(profile_val disk.model)"
  echo "  $(t gpu):          $(profile_val gpu.name)"
  echo "  $(t nic):          $(profile_val nic.name)"
  echo "  $(t mac):          $(profile_val nic.mac_prefix):XX:XX:XX"
  echo "  $(t bios):         $(profile_val bios.vendor) $(profile_val bios.version)"
  echo "  $(t board):        $(profile_val board.vendor) $(profile_val board.product)"
  echo "  $(t chassis):      $(profile_val chassis.vendor)"
  echo "  $(t acpi):         $(profile_val acpi.oem_id)"
  echo "============================================"
  echo ""
  ask_yn "$(t confirm)" || { echo "Cancelado."; exit 0; }
}

# --- Generadores ---
gen_serial() {
  local prefix="$1" len="${2:-6}"
  local chars="0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ" result="$prefix"
  for i in $(seq 1 "$len"); do result+="${chars:$((RANDOM % ${#chars})):1}"; done
  echo "$result"
}

gen_uuid() {
  cat /proc/sys/kernel/random/uuid 2>/dev/null || uuidgen 2>/dev/null || python3 -c "import uuid; print(uuid.uuid4())"
}

gen_mac() {
  local prefix=$(profile_val nic.mac_prefix)
  printf '%s:%02X:%02X:%02X' "$prefix" $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256)) | tr 'a-f' 'A-F'
}

brand_to_cpuid() {
  local brand="$1"
  local padded
  padded=$(printf '%-48s' "$brand")
  for leaf in 0x80000002 0x80000003 0x80000004; do
    local base=$(( (leaf - 0x80000002) * 16 ))
    local eax_hex=$(printf '%s' "$padded" | dd bs=1 skip=$base count=4 2>/dev/null | xxd -p -u)
    local ebx_hex=$(printf '%s' "$padded" | dd bs=1 skip=$((base + 4)) count=4 2>/dev/null | xxd -p -u)
    local ecx_hex=$(printf '%s' "$padded" | dd bs=1 skip=$((base + 8)) count=4 2>/dev/null | xxd -p -u)
    local edx_hex=$(printf '%s' "$padded" | dd bs=1 skip=$((base + 12)) count=4 2>/dev/null | xxd -p -u)
    echo "$leaf 0x$eax_hex 0x$ebx_hex 0x$ecx_hex 0x$edx_hex"
  done
}

read_cpuid_leaf1() {
  python3 "$SCRIPT_DIR/read-cpuid.py" 2>/dev/null || echo ""
}

# --- Aplicar parches en el host ---
apply_host_patches() {
  local vbox="$VBOX"
  local vm="$SELECTED_VM"

  local mfg=$(profile_val system.manufacturer)
  local model=$(profile_val system.model)
  local bios_vendor=$(profile_val bios.vendor)
  local bios_version=$(profile_val bios.version)
  local bios_date=$(profile_val bios.date)
  local board_vendor=$(profile_val board.vendor)
  local board_product=$(profile_val board.product)
  local chassis_vendor=$(profile_val chassis.vendor)
  local cpu_brand=$(profile_val cpu.brand)
  local disk_model=$(profile_val disk.model)
  local disk_fw=$(profile_val disk.firmware)
  local disk_prefix=$(profile_val disk.serial_prefix)
  local acpi_oem=$(profile_val acpi.oem_id)
  local acpi_creator=$(profile_val acpi.creator_id)
  local acpi_rev=$(profile_val acpi.creator_rev)
  local memory=$(profile_val memory)
  local cores=$(profile_val cpu.cores)

  local sys_serial=$(gen_serial "PF" 6)
  local board_serial=$(gen_serial "L1" 7)
  local uuid=$(gen_uuid)
  local disk_serial=$(gen_serial "$disk_prefix" 4)
  local mac=$(gen_mac)

  echo ""
  echo -e "${YELLOW}[1/6] Paravirtualizacion y CPUID...${NC}"
  "$vbox" modifyvm "$vm" --paravirtprovider none --cpuid-portability-level 0 2>/dev/null || true
  "$vbox" modifyvm "$vm" --memory "$memory" --cpus "$cores" 2>/dev/null || true

  echo -e "${YELLOW}[2/6] CPUID brand string...${NC}"
  brand_to_cpuid "$cpu_brand" | while IFS=' ' read -r leaf eax ebx ecx edx; do
    "$vbox" setextradata "$vm" "VBoxInternal/Devices/$leaf/Config/CustomCPUID" "$eax,$ebx,$ecx,$edx" 2>/dev/null
  done
  echo -e "  ${GREEN}CPU: $cpu_brand${NC}"

  echo -e "${YELLOW}[3/6] CPUID leaf 0x1 (hypervisor bit)...${NC}"
  local leaf1_val
  leaf1_val=$(read_cpuid_leaf1)
  if [ -n "$leaf1_val" ]; then
    "$vbox" setextradata "$vm" "VBoxInternal/Devices/0x1/Config/CustomCPUID" "$leaf1_val" 2>/dev/null
    echo -e "  ${GREEN}Hypervisor bit desactivado${NC}"
  else
    echo -e "  ${YELLOW}[WARN] No se pudo leer CPUID (Apple Silicon?)${NC}"
  fi

  local P="VBoxInternal/Devices/pcbios/0/Config"
  local fw=$("$vbox" showvminfo "$vm" --machinereadable 2>/dev/null | grep "^firmware=" | cut -d'"' -f2)
  if echo "$fw" | grep -qi "efi"; then P="VBoxInternal/Devices/efi/0/Config"; fi

  echo -e "${YELLOW}[4/6] DMI/SMBIOS/BIOS...${NC}"
  "$vbox" setextradata "$vm" "$P/DmiSystemVendor" "$mfg" 2>/dev/null
  "$vbox" setextradata "$vm" "$P/DmiSystemProduct" "$model" 2>/dev/null
  "$vbox" setextradata "$vm" "$P/DmiSystemSerial" "$sys_serial" 2>/dev/null
  "$vbox" setextradata "$vm" "$P/DmiSystemUuid" "$uuid" 2>/dev/null
  "$vbox" setextradata "$vm" "$P/DmiBoardVendor" "$board_vendor" 2>/dev/null
  "$vbox" setextradata "$vm" "$P/DmiBoardProduct" "$board_product" 2>/dev/null
  "$vbox" setextradata "$vm" "$P/DmiBoardSerial" "$board_serial" 2>/dev/null
  "$vbox" setextradata "$vm" "$P/DmiChassisVendor" "$chassis_vendor" 2>/dev/null
  "$vbox" setextradata "$vm" "$P/DmiBiosVendor" "$bios_vendor" 2>/dev/null
  "$vbox" setextradata "$vm" "$P/DmiBiosVersion" "$bios_version" 2>/dev/null
  "$vbox" setextradata "$vm" "$P/DmiBiosReleaseDate" "$bios_date" 2>/dev/null
  echo -e "  ${GREEN}DMI: $mfg $model${NC}"

  echo -e "${YELLOW}[5/6] Disco, MAC, ACPI...${NC}"
  "$vbox" setextradata "$vm" "VBoxInternal/Devices/ahci/0/Config/Port0/SerialNumber" "$disk_serial" 2>/dev/null
  "$vbox" setextradata "$vm" "VBoxInternal/Devices/ahci/0/Config/Port0/FirmwareRevision" "$disk_fw" 2>/dev/null
  "$vbox" setextradata "$vm" "VBoxInternal/Devices/ahci/0/Config/Port0/ModelNumber" "$disk_model" 2>/dev/null
  "$vbox" setextradata "$vm" "VBoxInternal/Devices/acpi/0/Config/AcpiOemId" "$acpi_oem" 2>/dev/null
  "$vbox" setextradata "$vm" "VBoxInternal/Devices/acpi/0/Config/AcpiCreatorId" "$acpi_creator" 2>/dev/null
  "$vbox" setextradata "$vm" "VBoxInternal/Devices/acpi/0/Config/AcpiCreatorRev" "$acpi_rev" 2>/dev/null
  "$vbox" modifyvm "$vm" --macaddress1 "$mac" 2>/dev/null
  echo -e "  ${GREEN}Disco: $disk_model, MAC: $mac${NC}"

  echo -e "${YELLOW}[6/7] VMMDev...${NC}"
  "$vbox" setextradata "$vm" "VBoxInternal/Devices/VMMDev/0/Config/GetHostTimeDisabled" "1" 2>/dev/null
  echo -e "  ${GREEN}VMMDev desactivado${NC}"

  # --- Perifericos: webcam, microfono, altavoces ---
  echo ""
  echo -e "${YELLOW}[7/7] Perifericos: webcam, microfono y altavoces${NC}"
  echo "Puedes activar la webcam, microfono y altavoces en la VM."
  echo "Si los activas, se usan IDs de hardware real para que parezcan dispositivos fisicos."
  echo ""
  echo "  [1] Activar webcam + microfono + altavoces (recomendado)"
  echo "  [2] Activar solo webcam"
  echo "  [3] Activar solo microfono + altavoces"
  echo "  [4] No activar ninguno"
  echo ""
  if [ $YES -eq 1 ]; then
    periph_choice="1"
  else
    read -rp "Elige (1-4): " periph_choice
  fi

  local webcam_label="No activada"
  local mic_label="No activado"
  local speaker_label="No activado"

  case "$periph_choice" in
    1|2)
      echo ""
      echo -e "${YELLOW}Webcam disponible:${NC}"
      local wc_i=1
      local wc_keys=()
      while IFS= read -r key; do
        local wclabel=$(jq -r ".peripherals.webcams[\"$key\"].label" "$DB")
        echo "  [$wc_i] $wclabel"
        wc_keys+=("$key")
        wc_i=$((wc_i + 1))
      done < <(jq -r '.peripherals.webcams | keys[]' "$DB")
      if [ $YES -eq 1 ]; then
        wc_choice=1
      else
        read -rp "Elige webcam (1-${#wc_keys[@]}): " wc_choice
      fi
      if [[ "$wc_choice" =~ ^[0-9]+$ ]] && [ "$wc_choice" -ge 1 ] && [ "$wc_choice" -le ${#wc_keys[@]} ]; then
        local wc_key="${wc_keys[$((wc_choice - 1))]}"
        local wc_vid=$(jq -r ".peripherals.webcams[\"$wc_key\"].vendor_id" "$DB")
        local wc_pid=$(jq -r ".peripherals.webcams[\"$wc_key\"].product_id" "$DB")
        webcam_label=$(jq -r ".peripherals.webcams[\"$wc_key\"].label" "$DB")
        "$vbox" modifyvm "$vm" --webcam on 2>/dev/null || true
        "$vbox" usbfilter add 0 --target "$vm" --name "Webcam" --action hold --vendorid "$wc_vid" --productid "$wc_pid" 2>/dev/null || true
        echo -e "  ${GREEN}Webcam: $webcam_label${NC}"
      fi
      ;;
  esac

  case "$periph_choice" in
    1|3)
      echo ""
      echo -e "${YELLOW}Microfono disponible:${NC}"
      local mic_i=1
      local mic_keys=()
      while IFS= read -r key; do
        local miclabel=$(jq -r ".peripherals.microphones[\"$key\"].label" "$DB")
        echo "  [$mic_i] $miclabel"
        mic_keys+=("$key")
        mic_i=$((mic_i + 1))
      done < <(jq -r '.peripherals.microphones | keys[]' "$DB")
      if [ $YES -eq 1 ]; then
        mic_choice=1
      else
        read -rp "Elige microfono (1-${#mic_keys[@]}): " mic_choice
      fi
      if [[ "$mic_choice" =~ ^[0-9]+$ ]] && [ "$mic_choice" -ge 1 ] && [ "$mic_choice" -le ${#mic_keys[@]} ]; then
        local mic_key="${mic_keys[$((mic_choice - 1))]}"
        mic_label=$(jq -r ".peripherals.microphones[\"$mic_key\"].label" "$DB")
        echo -e "  ${GREEN}Microfono: $mic_label${NC}"
      fi

      echo ""
      echo -e "${YELLOW}Altavoces disponibles:${NC}"
      local spk_i=1
      local spk_keys=()
      while IFS= read -r key; do
        local spklabel=$(jq -r ".peripherals.speakers[\"$key\"].label" "$DB")
        echo "  [$spk_i] $spklabel"
        spk_keys+=("$key")
        spk_i=$((spk_i + 1))
      done < <(jq -r '.peripherals.speakers | keys[]' "$DB")
      if [ $YES -eq 1 ]; then
        spk_choice=1
      else
        read -rp "Elige altavoces (1-${#spk_keys[@]}): " spk_choice
      fi
      if [[ "$spk_choice" =~ ^[0-9]+$ ]] && [ "$spk_choice" -ge 1 ] && [ "$spk_choice" -le ${#spk_keys[@]} ]; then
        local spk_key="${spk_keys[$((spk_choice - 1))]}"
        speaker_label=$(jq -r ".peripherals.speakers[\"$spk_key\"].label" "$DB")
        echo -e "  ${GREEN}Altavoces: $speaker_label${NC}"
      fi

      "$vbox" modifyvm "$vm" --audio-driver default --audioin on --audioout on 2>/dev/null || \
      "$vbox" modifyvm "$vm" --audio on --audioin on --audioout on 2>/dev/null || true
      echo -e "  ${GREEN}Audio in/out activado${NC}"
      ;;
  esac

  case "$periph_choice" in
    4)
      echo -e "  ${YELLOW}Perifericos no activados${NC}"
      ;;
  esac

  # Guardar datos para el informe
  HOST_REPORT="$SCRIPT_DIR/profiles/host-report-$(date +%Y%m%d_%H%M%S).md"
  cat > "$HOST_REPORT" << REPEOF
# Informe de camuflaje (Host)

**Fecha:** $(date)
**VM:** $SELECTED_VM
**Perfil:** $SELECTED_PROFILE_LABEL

## Cambios aplicados

| Parametro | Valor |
|---|---|
| Manufacturer | $mfg |
| Model | $model |
| CPU | $cpu_brand |
| Cores | $cores |
| RAM | $memory MB |
| Disco | $disk_model |
| MAC | $mac |
| BIOS | $bios_vendor $bios_version |
| Board | $board_vendor $board_product |
| ACPI OEM | $acpi_oem |
| Hypervisor bit | Desactivado |
| Paravirt | none |
| Webcam | $webcam_label |
| Microfono | $mic_label |
| Altavoces | $speaker_label |

## Valores generados

- System serial: $sys_serial
- Board serial: $board_serial
- System UUID: $uuid
- Disk serial: $disk_serial

## Pasos siguientes

1. Arranca la VM
2. Copia esta carpeta dentro de la VM
3. Ejecuta ghost-wizard.sh dentro de la VM (modo guest)
4. Reinicia la VM
5. Ejecuta: node ghost-check.js --advanced
6. Si todo pasa, inicia la sesion
REPEOF
  echo -e "${GREEN}[OK] Informe: $HOST_REPORT${NC}"
}

# --- Aplicar parches en el guest ---
ps_run() {
  if command -v powershell.exe >/dev/null 2>&1; then
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$1" 2>/dev/null
  elif command -v pwsh >/dev/null 2>&1; then
    pwsh -NoProfile -Command "$1" 2>/dev/null
  fi
}

apply_guest_patches() {
  local os="$DETECTED_OS"
  local mfg=$(profile_val system.manufacturer)
  local model=$(profile_val system.model)
  local bios_vendor=$(profile_val bios.vendor)
  local bios_version=$(profile_val bios.version)
  local bios_date=$(profile_val bios.date)
  local board_vendor=$(profile_val board.vendor)
  local board_product=$(profile_val board.product)
  local chassis_vendor=$(profile_val chassis.vendor)

  case "$os" in
    windows|windows-wsl)
      echo ""
      echo -e "${YELLOW}$(t step) 1/5: $(t regpatch)${NC}"
      echo "VirtualBox pone 'innotek GmbH' como manufacturer y 'VirtualBox' como model."
      echo "systeminformation lee esto del registro y WMI."
      echo ""

      local serial="PF$(printf '%06d' $((RANDOM % 1000000)))"
      local board_serial="L1$(printf '%07d' $((RANDOM % 10000000)))"

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
      " | grep -q OK && echo -e "${GREEN}[OK] Registro parcheado${NC}" || echo -e "${RED}[!] Error${NC}"

      echo -e "${YELLOW}$(t step) 2/5: Desactivar hypervisor flag...${NC}"
      ps_run "bcdedit /set hypervisorlaunchtype off" 2>/dev/null
      ps_run "bcdedit /set vsmlaunchtype off" 2>/dev/null || true
      echo -e "${GREEN}[OK] hypervisorlaunchtype off (requiere reinicio)${NC}"
      ;;

    linux)
      echo ""
      echo -e "${YELLOW}$(t step) 1/3: Parchear /etc/machine-info...${NC}"
      cat > /etc/machine-info << EOF
HARDWARE_VENDOR=$mfg
HARDWARE_MODEL=$model
EOF
      echo -e "${GREEN}[OK] /etc/machine-info actualado${NC}"
      ;;
  esac

  # --- Limpieza de Guest Additions ---
  echo ""
  echo -e "${YELLOW}$(t guestclean)...${NC}"
  case "$os" in
    windows|windows-wsl)
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
      " 2>/dev/null | grep -q OK && echo -e "  ${GREEN}[OK] Servicios desactivados${NC}" || true
      echo "  Desactivando drivers..."
      ps_run "
        \$drivers = @('VBoxGuest','VBoxMouse','VBoxSF','VBoxVideo','VBoxWddm')
        foreach (\$drv in \$drivers) {
          sc.exe config \$drv start= disabled 2>\$null | Out-Null
        }
        Write-Output 'OK'
      " 2>/dev/null | grep -q OK && echo -e "  ${GREEN}[OK] Drivers desactivados${NC}" || true
      ;;
    linux)
      echo "  Matando procesos..."
      for proc in VBoxService VBoxClient VBoxControl vmtoolsd vmware-vmblock-fuse; do
        pkill -9 "$proc" 2>/dev/null || true
      done
      echo -e "  ${GREEN}[OK]${NC}"
      echo "  Desactivando servicios..."
      for svc in vboxadd vboxadd-service vboxadd-x11 virtualbox-guest-utils vboxservice spice-vdagent qemu-guest-agent vmtoolsd open-vm-tools; do
        systemctl disable --now "$svc" 2>/dev/null || true
        systemctl mask "$svc" 2>/dev/null || true
      done
      echo -e "  ${GREEN}[OK]${NC}"
      echo "  Bloqueando modulos..."
      mkdir -p /etc/modprobe.d
      cat > /etc/modprobe.d/vm-ghost.conf << 'EOF'
blacklist vboxguest
blacklist vboxsf
blacklist vboxvideo
blacklist vmw_vmci
blacklist vmw_vsock_vmci_transport
blacklist vmwgfx
install vboxguest /bin/false
install vboxsf /bin/false
install vboxvideo /bin/false
EOF
      if command -v update-initramfs >/dev/null 2>&1; then update-initramfs -u 2>/dev/null || true; fi
      echo -e "  ${GREEN}[OK]${NC}"
      ;;
  esac

  # --- Bloqueo de telemetria ---
  echo ""
  echo -e "${YELLOW}$(t telemetry)...${NC}"
  case "$os" in
    windows|windows-wsl)
      local hosts_file=""
      for p in "/c/Windows/System32/drivers/etc/hosts" "/mnt/c/Windows/System32/drivers/etc/hosts" "C:/Windows/System32/drivers/etc/hosts"; do
        if [ -f "$p" ]; then hosts_file="$p"; break; fi
      done
      if [ -n "$hosts_file" ]; then
        if ! grep -q "vm-ghost" "$hosts_file" 2>/dev/null; then
          cat >> "$hosts_file" << 'EOF'
# vm-ghost
0.0.0.0 update.virtualbox.org
0.0.0.0 www.virtualbox.org
0.0.0.0 download.virtualbox.org
EOF
          echo -e "${GREEN}[OK] Hosts bloqueado${NC}"
        else
          echo -e "${GREEN}[OK] Ya estaba bloqueado${NC}"
        fi
      else
        ps_run "Add-Content -Path 'C:\Windows\System32\drivers\etc\hosts' -Value '# vm-ghost' -EA SilentlyContinue; Add-Content -Path 'C:\Windows\System32\drivers\etc\hosts' -Value '0.0.0.0 update.virtualbox.org' -EA SilentlyContinue; Add-Content -Path 'C:\Windows\System32\drivers\etc\hosts' -Value '0.0.0.0 www.virtualbox.org' -EA SilentlyContinue; Add-Content -Path 'C:\Windows\System32\drivers\etc\hosts' -Value '0.0.0.0 download.virtualbox.org' -EA SilentlyContinue; Write-Output 'OK'" 2>/dev/null | grep -q OK && echo -e "${GREEN}[OK] Hosts bloqueado${NC}" || echo -e "${YELLOW}[!] No se pudo${NC}"
      fi
      ;;
    linux)
      if ! grep -q "vm-ghost" /etc/hosts 2>/dev/null; then
        cat >> /etc/hosts << 'EOF'
# vm-ghost
0.0.0.0 update.virtualbox.org
0.0.0.0 www.virtualbox.org
0.0.0.0 download.virtualbox.org
EOF
        echo -e "${GREEN}[OK] Hosts bloqueado${NC}"
      else
        echo -e "${GREEN}[OK] Ya estaba bloqueado${NC}"
      fi
      ;;
  esac

  # --- Verificacion ---
  echo ""
  echo -e "${YELLOW}$(t verify)...${NC}"
  if [ -z "$NODE_BIN" ]; then
    echo -e "${YELLOW}$(t open_nodejs)${NC}"
    case "$os" in
      windows|windows-wsl) echo -e "${YELLOW}    Descarga desde https://nodejs.org${NC}" ;;
      linux) echo -e "${YELLOW}    sudo apt install -y nodejs npm${NC}" ;;
    esac
    echo -e "${YELLOW}    Despues: node ghost-check.js --advanced${NC}"
  else
    if [ ! -d "node_modules/systeminformation" ]; then
      npm install systeminformation@5.31.7 2>/dev/null
    fi
    if [ $RUN_CHECK -eq 1 ] || [ $YES -eq 1 ]; then
      node "$SCRIPT_DIR/ghost-check.js" --advanced 2>&1 || true
    else
      echo "Ejecuta: node ghost-check.js --advanced"
    fi
  fi

  # --- Informe ---
  local guest_report="$SCRIPT_DIR/guest-report-$(date +%Y%m%d_%H%M%S).md"
  cat > "$guest_report" << REPEOF
# Informe de camuflaje (Guest)

**Fecha:** $(date)
**OS:** $DETECTED_OS
**Perfil:** $SELECTED_PROFILE_LABEL

## Cambios aplicados en el guest

$(case "$os" in
  windows|windows-wsl)
    echo "- Registro WMI parcheado (manufacturer=$mfg, model=$model)"
    echo "- bcdedit /set hypervisorlaunchtype off"
    echo "- bcdedit /set vsmlaunchtype off"
    echo "- Procesos Guest Additions terminados"
    echo "- Servicios Guest Additions desactivados"
    echo "- Drivers Guest Additions desactivados"
    echo "- Telemetria VirtualBox bloqueada en hosts"
    ;;
  linux)
    echo "- /etc/machine-info actualado ($mfg $model)"
    echo "- Procesos Guest Additions terminados"
    echo "- Servicios desactivados y modulos bloqueados"
    echo "- Telemetria bloqueada en /etc/hosts"
    ;;
esac)

## Pasos siguientes

1. **Reiniciar la VM** (obligatorio para bcdedit y drivers)
2. Ejecutar: node ghost-check.js --advanced
3. Si todo pasa (Score 0/100, sin findings), iniciar la sesion
REPEOF
  echo -e "${GREEN}[OK] Informe: $guest_report${NC}"
}

# --- Copiar archivos al guest ---
show_copy_instructions() {
  echo ""
  echo -e "${BLUE}$(t copy_files)${NC}"
  echo "  ghost-wizard.sh"
  echo "  ghost-check.js"
  echo "  banned-windows.json, banned-macos.json, banned-linux.json"
  echo "  hardware-db.json"
  echo "  read-cpuid.py"
  echo ""
  echo -e "${YELLOW}Metodos:${NC}"
  echo "  - Carpeta compartida de VirtualBox (sin Guest Additions, usar transferencia manual)"
  echo "  - USB pendrive"
  echo "  - Descargar desde GitHub"
  echo "  - scp/sftp"
}

# --- Funcion principal ---
main() {
  banner
  detect_environment
  ask_host_guest

  if [ "$MODE" = "host" ]; then
    # --- MODO HOST ---
    if [ -z "$VBOX" ]; then die "VBoxManage no encontrado."; fi
    select_vm
    select_profile
    if [ "$SELECTED_PROFILE_SOURCE" = "custom" ]; then
      custom_profile
    fi
    show_review
    save_profile
    apply_host_patches
    show_copy_instructions
    if ask_yn "$(t start_vm)"; then
      "$VBOX" startvm "$SELECTED_VM" --type gui 2>/dev/null || "$VBOX" startvm "$SELECTED_VM" 2>/dev/null || true
    fi
    echo ""
    echo -e "${GREEN}$(t applied)${NC}"
    echo -e "${YELLOW}$(t enter_vm)${NC}"
    echo -e "${YELLOW}$(t reboot)${NC}"
  else
    # --- MODO GUEST ---
    select_profile
    if [ "$SELECTED_PROFILE_SOURCE" = "custom" ]; then
      custom_profile
    fi
    apply_guest_patches
    echo ""
    echo -e "${GREEN}$(t applied)${NC}"
    echo -e "${YELLOW}$(t reboot)${NC}"
  fi
}

main "$@"