#!/usr/bin/env bash
set -euo pipefail

# vm-ghost host: script que se ejecuta en el HOST antes de arrancar la VM.
# Usa VBoxManage setextradata para parchear DMI/SMBIOS/CPUID/MAC/disco.
#
# Esto cubre los vectores que no se pueden cambiar desde dentro del guest:
# - DMI/SMBIOS (vendor, product, serial, UUID)
# - CPUID brand string (leaves 0x80000002-0x80000004)
# - CPUID leaf 0x1 (hypervisor bit)
# - MAC address (OUI del fabricante)
# - Disco serie/modelo/firmware
# - ACPI OEM

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DB="$SCRIPT_DIR/hardware-db.json"

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

find_vboxmanage() {
  local candidates=(
    "VBoxManage"
    "/usr/local/bin/VBoxManage"
    "/opt/homebrew/bin/VBoxManage"
    "/Applications/VirtualBox.app/Contents/MacOS/VBoxManage"
    "/c/Program Files/Oracle/VirtualBox/VBoxManage.exe"
    "/c/Program Files (x86)/Oracle/VirtualBox/VBoxManage.exe"
  )
  for c in "${candidates[@]}"; do
    if command -v "$c" >/dev/null 2>&1 || [ -x "$c" ]; then
      echo "$c"
      return
    fi
  done
  echo ""
}

list_vms() {
  local vbox="$1"
  "$vbox" list vms 2>/dev/null | sed 's/^"\(.*\)" {.*$/\1/'
}

gen_serial() {
  local prefix="$1" len="${2:-6}"
  local chars="0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ" result="$prefix"
  for i in $(seq 1 "$len"); do result+="${chars:$((RANDOM % ${#chars})):1}"; done
  echo "$result"
}

gen_uuid() {
  cat /proc/sys/kernel/random/uuid 2>/dev/null || uuidgen 2>/dev/null || python3 -c "import uuid; print(uuid.uuid4())"
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

apply_cpuid() {
  local vbox="$1" vm="$2" brand="$3"
  brand_to_cpuid "$brand" | while IFS=' ' read -r leaf eax ebx ecx edx; do
    "$vbox" setextradata "$vm" "VBoxInternal/Devices/$leaf/Config/CustomCPUID" "$eax,$ebx,$ecx,$edx" 2>/dev/null
  done
}

read_cpuid_leaf1() {
  python3 "$SCRIPT_DIR/read-cpuid.py" 2>/dev/null || echo ""
}

main() {
  banner

  local vbox
  vbox=$(find_vboxmanage)
  if [ -z "$vbox" ]; then
    die "VBoxManage no encontrado. Instala VirtualBox."
  fi
  echo -e "${GREEN}[OK] VBoxManage: $vbox${NC}"

  local vms
  vms=$(list_vms "$vbox")
  if [ -z "$vms" ]; then
    die "No hay VMs en VirtualBox. Crea una VM primero."
  fi

  echo ""
  echo -e "${YELLOW}VMs disponibles:${NC}"
  local i=1
  local vm_array=()
  while IFS= read -r vm; do
    echo "  [$i] $vm"
    vm_array+=("$vm")
    i=$((i + 1))
  done <<< "$vms"
  echo ""
  read -rp "Elige VM (1-${#vm_array[@]}): " vm_choice
  if ! [[ "$vm_choice" =~ ^[0-9]+$ ]] || [ "$vm_choice" -lt 1 ] || [ "$vm_choice" -gt ${#vm_array[@]} ]; then
    die "Opcion invalida"
  fi
  local vm_name="${vm_array[$((vm_choice - 1))]}"
  echo -e "${GREEN}[OK] VM: $vm_name${NC}"

  echo ""
  echo -e "${YELLOW}Perfiles de hardware:${NC}"
  local j=1
  local profile_keys=()
  while IFS= read -r key; do
    local label=$(jq -r ".profiles[\"$key\"].label" "$DB")
    echo "  [$j] $label"
    profile_keys+=("$key")
    j=$((j + 1))
  done < <(jq -r '.profiles | keys[]' "$DB")
  echo ""
  read -rp "Elige perfil (1-${#profile_keys[@]}): " profile_choice
  if ! [[ "$profile_choice" =~ ^[0-9]+$ ]] || [ "$profile_choice" -lt 1 ] || [ "$profile_choice" -gt ${#profile_keys[@]} ]; then
    die "Opcion invalida"
  fi
  local profile_key="${profile_keys[$((profile_choice - 1))]}"
  local profile_label=$(jq -r ".profiles[\"$profile_key\"].label" "$DB")
  echo -e "${GREEN}[OK] Perfil: $profile_label${NC}"

  local mfg=$(jq -r ".profiles[\"$profile_key\"].system.manufacturer" "$DB")
  local model=$(jq -r ".profiles[\"$profile_key\"].system.model" "$DB")
  local bios_vendor=$(jq -r ".profiles[\"$profile_key\"].bios.vendor" "$DB")
  local bios_version=$(jq -r ".profiles[\"$profile_key\"].bios.version" "$DB")
  local bios_date=$(jq -r ".profiles[\"$profile_key\"].bios.date" "$DB")
  local board_vendor=$(jq -r ".profiles[\"$profile_key\"].board.vendor" "$DB")
  local board_product=$(jq -r ".profiles[\"$profile_key\"].board.product" "$DB")
  local chassis_vendor=$(jq -r ".profiles[\"$profile_key\"].chassis.vendor" "$DB")
  local cpu_brand=$(jq -r ".profiles[\"$profile_key\"].cpu.brand" "$DB")
  local disk_model=$(jq -r ".profiles[\"$profile_key\"].disk.model" "$DB")
  local disk_fw=$(jq -r ".profiles[\"$profile_key\"].disk.firmware" "$DB")
  local mac_prefix=$(jq -r ".profiles[\"$profile_key\"].nic.mac_prefix" "$DB")
  local acpi_oem=$(jq -r ".profiles[\"$profile_key\"].acpi.oem_id" "$DB")
  local acpi_creator=$(jq -r ".profiles[\"$profile_key\"].acpi.creator_id" "$DB")
  local acpi_rev=$(jq -r ".profiles[\"$profile_key\"].acpi.creator_rev" "$DB")

  local sys_serial=$(gen_serial "PF" 6)
  local board_serial=$(gen_serial "L1" 7)
  local uuid=$(gen_uuid)
  local disk_serial=$(gen_serial "$(jq -r ".profiles[\"$profile_key\"].disk.serial_prefix" "$DB")" 4)
  local mac=$(printf '%s:%02X:%02X:%02X' "$mac_prefix" $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256)) | tr 'a-f' 'A-F')

  echo ""
  echo -e "${YELLOW}Resumen:${NC}"
  echo "  VM:           $vm_name"
  echo "  Perfil:       $profile_label"
  echo "  Manufacturer: $mfg"
  echo "  Model:        $model"
  echo "  CPU:          $cpu_brand"
  echo "  Disk:         $disk_model"
  echo "  MAC:          $mac"
  echo ""
  read -rp "Aplicar? (s/N): " confirm
  case "$(printf '%s' "$confirm" | tr '[:upper:]' '[:lower:]')" in
    s|si|y|yes) ;;
    *) echo "Cancelado."; exit 0 ;;
  esac

  echo ""
  echo -e "${YELLOW}[1/6] Configurando paravirtualizacion y CPUID...${NC}"
  "$vbox" modifyvm "$vm_name" --paravirtprovider none --cpuid-portability-level 0 2>/dev/null || true

  echo -e "${YELLOW}[2/6] Aplicando CPUID brand string...${NC}"
  apply_cpuid "$vbox" "$vm_name" "$cpu_brand"
  echo -e "  ${GREEN}CPU visible: $cpu_brand${NC}"

  echo -e "${YELLOW}[3/6] Aplicando CPUID leaf 0x1 (hypervisor bit)...${NC}"
  local leaf1_val
  leaf1_val=$(read_cpuid_leaf1)
  if [ -n "$leaf1_val" ]; then
    "$vbox" setextradata "$vm_name" "VBoxInternal/Devices/0x1/Config/CustomCPUID" "$leaf1_val" 2>/dev/null
    echo -e "  ${GREEN}Hypervisor bit desactivado: $leaf1_val${NC}"
  else
    echo -e "  ${YELLOW}[WARN] No se pudo leer CPUID del host (Apple Silicon o sin python3)${NC}"
  fi

  local P="VBoxInternal/Devices/pcbios/0/Config"
  local fw=$("$vbox" showvminfo "$vm_name" --machinereadable 2>/dev/null | grep "^firmware=" | cut -d'"' -f2)
  if echo "$fw" | grep -qi "efi"; then
    P="VBoxInternal/Devices/efi/0/Config"
  fi

  echo -e "${YELLOW}[4/6] Aplicando DMI/SMBIOS...${NC}"
  "$vbox" setextradata "$vm_name" "$P/DmiSystemVendor" "$mfg" 2>/dev/null
  "$vbox" setextradata "$vm_name" "$P/DmiSystemProduct" "$model" 2>/dev/null
  "$vbox" setextradata "$vm_name" "$P/DmiSystemSerial" "$sys_serial" 2>/dev/null
  "$vbox" setextradata "$vm_name" "$P/DmiSystemUuid" "$uuid" 2>/dev/null
  "$vbox" setextradata "$vm_name" "$P/DmiBoardVendor" "$board_vendor" 2>/dev/null
  "$vbox" setextradata "$vm_name" "$P/DmiBoardProduct" "$board_product" 2>/dev/null
  "$vbox" setextradata "$vm_name" "$P/DmiBoardSerial" "$board_serial" 2>/dev/null
  "$vbox" setextradata "$vm_name" "$P/DmiChassisVendor" "$chassis_vendor" 2>/dev/null
  "$vbox" setextradata "$vm_name" "$P/DmiBiosVendor" "$bios_vendor" 2>/dev/null
  "$vbox" setextradata "$vm_name" "$P/DmiBiosVersion" "$bios_version" 2>/dev/null
  "$vbox" setextradata "$vm_name" "$P/DmiBiosReleaseDate" "$bios_date" 2>/dev/null
  echo -e "  ${GREEN}DMI aplicado: $mfg $model${NC}"

  echo -e "${YELLOW}[5/6] Aplicando disco y MAC...${NC}"
  "$vbox" setextradata "$vm_name" "VBoxInternal/Devices/ahci/0/Config/Port0/SerialNumber" "$disk_serial" 2>/dev/null
  "$vbox" setextradata "$vm_name" "VBoxInternal/Devices/ahci/0/Config/Port0/FirmwareRevision" "$disk_fw" 2>/dev/null
  "$vbox" setextradata "$vm_name" "VBoxInternal/Devices/ahci/0/Config/Port0/ModelNumber" "$disk_model" 2>/dev/null
  "$vbox" setextradata "$vm_name" "VBoxInternal/Devices/acpi/0/Config/AcpiOemId" "$acpi_oem" 2>/dev/null
  "$vbox" setextradata "$vm_name" "VBoxInternal/Devices/acpi/0/Config/AcpiCreatorId" "$acpi_creator" 2>/dev/null
  "$vbox" setextradata "$vm_name" "VBoxInternal/Devices/acpi/0/Config/AcpiCreatorRev" "$acpi_rev" 2>/dev/null
  "$vbox" modifyvm "$vm_name" --macaddress1 "$mac" 2>/dev/null
  echo -e "  ${GREEN}Disco: $disk_model, MAC: $mac${NC}"

  echo -e "${YELLOW}[6/6] Desactivando VMMDev...${NC}"
  "$vbox" setextradata "$vm_name" "VBoxInternal/Devices/VMMDev/0/Config/GetHostTimeDisabled" "1" 2>/dev/null
  echo -e "  ${GREEN}VMMDev desactivado${NC}"

  # --- Perifericos: webcam, microfono, altavoces ---
  echo ""
  echo -e "${YELLOW}Perifericos: webcam, microfono y altavoces${NC}"
  echo "Puedes activar la webcam, microfono y altavoces en la VM."
  echo "Si los activas, se usan IDs de hardware real para que parezcan dispositivos fisicos."
  echo ""
  echo "  [1] Activar webcam + microfono + altavoces (recomendado)"
  echo "  [2] Activar solo webcam"
  echo "  [3] Activar solo microfono + altavoces"
  echo "  [4] No activar ninguno"
  echo ""
  read -rp "Elige (1-4): " periph_choice

  case "$periph_choice" in
    1|2)
      echo ""
      echo -e "${YELLOW}Webcam disponible:${NC}"
      local wc_i=1
      local wc_keys=()
      while IFS= read -r key; do
        local label=$(jq -r ".peripherals.webcams[\"$key\"].label" "$DB")
        echo "  [$wc_i] $label"
        wc_keys+=("$key")
        wc_i=$((wc_i + 1))
      done < <(jq -r '.peripherals.webcams | keys[]' "$DB")
      read -rp "Elige webcam (1-${#wc_keys[@]}): " wc_choice
      if [[ "$wc_choice" =~ ^[0-9]+$ ]] && [ "$wc_choice" -ge 1 ] && [ "$wc_choice" -le ${#wc_keys[@]} ]; then
        local wc_key="${wc_keys[$((wc_choice - 1))]}"
        local wc_vid=$(jq -r ".peripherals.webcams[\"$wc_key\"].vendor_id" "$DB")
        local wc_pid=$(jq -r ".peripherals.webcams[\"$wc_key\"].product_id" "$DB")
        "$vbox" modifyvm "$vm_name" --webcam on 2>/dev/null || true
        echo -e "  ${GREEN}Webcam: $(jq -r ".peripherals.webcams[\"$wc_key\"].label" "$DB")${NC}"
        echo -e "  ${YELLOW}Nota: la webcam USB se pasa por passthrough. VirtualBox no permite spoofear USB vendor/product ID via CLI.${NC}"
        echo -e "  ${YELLOW}Para spoofear el ID, usa: VBoxManage usbfilter add 0 --target \"$vm_name\" --name \"Webcam\" --action hold --vendorid $wc_vid --productid $wc_pid${NC}"
        "$vbox" usbfilter add 0 --target "$vm_name" --name "Webcam" --action hold --vendorid "$wc_vid" --productid "$wc_pid" 2>/dev/null || true
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
        local label=$(jq -r ".peripherals.microphones[\"$key\"].label" "$DB")
        echo "  [$mic_i] $label"
        mic_keys+=("$key")
        mic_i=$((mic_i + 1))
      done < <(jq -r '.peripherals.microphones | keys[]' "$DB")
      read -rp "Elige microfono (1-${#mic_keys[@]}): " mic_choice
      if [[ "$mic_choice" =~ ^[0-9]+$ ]] && [ "$mic_choice" -ge 1 ] && [ "$mic_choice" -le ${#mic_keys[@]} ]; then
        local mic_key="${mic_keys[$((mic_choice - 1))]}"
        echo -e "  ${GREEN}Microfono: $(jq -r ".peripherals.microphones[\"$mic_key\"].label" "$DB")${NC}"
      fi

      echo ""
      echo -e "${YELLOW}Altavoces disponibles:${NC}"
      local spk_i=1
      local spk_keys=()
      while IFS= read -r key; do
        local label=$(jq -r ".peripherals.speakers[\"$key\"].label" "$DB")
        echo "  [$spk_i] $label"
        spk_keys+=("$key")
        spk_i=$((spk_i + 1))
      done < <(jq -r '.peripherals.speakers | keys[]' "$DB")
      read -rp "Elige altavoces (1-${#spk_keys[@]}): " spk_choice
      if [[ "$spk_choice" =~ ^[0-9]+$ ]] && [ "$spk_choice" -ge 1 ] && [ "$spk_choice" -le ${#spk_keys[@]} ]; then
        local spk_key="${spk_keys[$((spk_choice - 1))]}"
        echo -e "  ${GREEN}Altavoces: $(jq -r ".peripherals.speakers[\"$spk_key\"].label" "$DB")${NC}"
      fi

      # Activar audio in/out en la VM
      "$vbox" modifyvm "$vm_name" --audio-driver default --audioin on --audioout on 2>/dev/null || \
      "$vbox" modifyvm "$vm_name" --audio on --audioin on --audioout on 2>/dev/null || true
      echo -e "  ${GREEN}Audio in/out activado en la VM${NC}"
      ;;
  esac

  case "$periph_choice" in
    4)
      echo -e "  ${YELLOW}Perifericos no activados${NC}"
      ;;
  esac

  echo ""
  echo -e "${BLUE}============================================${NC}"
  echo -e "${GREEN}  Parche del host aplicado${NC}"
  echo -e "${BLUE}============================================${NC}"
  echo ""
  echo "Ahora:"
  echo "  1. Arranca la VM"
  echo "  2. Dentro de la VM, copia esta carpeta y ejecuta ghost.sh"
  echo "  3. Reinicia la VM"
  echo "  4. Ejecuta: node ghost-check.js --advanced"
  echo "  5. Si todo pasa, inicia la sesion"
  echo ""
  read -rp "Arrancar la VM ahora? (s/N): " start_vm
  case "$(printf '%s' "$start_vm" | tr '[:upper:]' '[:lower:]')" in
    s|si|y|yes) "$vbox" startvm "$vm_name" --type gui 2>/dev/null || "$vbox" startvm "$vm_name" 2>/dev/null ;;
  esac
}

main "$@"