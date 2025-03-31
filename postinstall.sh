#!/bin/bash

# === VARIABLES ===
TIMESTAMP=$(date +"%Y%m%d_%H%M%S") ## Génère un timestamp unique
LOG_DIR="./logs" ##Emplacement du dossier log
LOG_FILE="$LOG_DIR/postinstall_$TIMESTAMP.log" ## Création du fichier log nommé avec le timestamp
CONFIG_DIR="./config" ## Définit l'emplacement du dossier .config
PACKAGE_LIST="./lists/packages.txt" ## indique l'emplacement du fichier package.txt
USERNAME=$(logname) ## Récupère le nom de l'utilisateur utilisant le script (autre que root de préférence)
USER_HOME="/home/$USERNAME" ## Chemin du dossier perso de l'utilisateur identifié précédemment

# === FUNCTIONS ===
log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE" ## Affiche un message de log avec un horodatage et le copie dans le fichier de log
}

check_and_install() {
  local pkg=$1 ## Vérifie la présence du paquet
  if dpkg -s "$pkg" &>/dev/null; then ## Si le paquet est installé
    log "$pkg is already installed." ##Annonce que le paquet est déjà installé
  else 
    log "Installing $pkg..." ## Sinon installe le paquet
    apt install -y "$pkg" &>>"$LOG_FILE"
    if [ $? -eq 0 ]; then
      log "$pkg successfully installed." ## Confirme l'installation du paquet
    else
      log "Failed to install $pkg." ## annonce l'échec de l'installation du paquet
    fi
  fi
}

ask_yes_no() {
  read -p "$1 [y/N]: " answer ## Demande à l'utilisaterur de valider ou non l'installation
  case "$answer" in
    [Yy]* ) return 0 ;;
    * ) return 1 ;;
  esac
}

# === INITIAL SETUP ===
mkdir -p "$LOG_DIR" ## Création du dossier LOG_DIR ou vérifie son existence
touch "$LOG_FILE" ## Créer le fichier de log vierge s'il n'existe pas
log "Starting post-installation script. Logged user: $USERNAME" ## Appelle la fonction log()

if [ "$EUID" -ne 0 ]; then ## Vérifie que le script est lancé en tant que root
  log "This script must be run as root." ## si ce n'est pas le cas affiche ce message
  exit 1 ## stop le script si non lancé en tant que root
fi

# === 1. SYSTEM UPDATE ===
log "Updating system packages..."
apt update && apt upgrade -y &>>"$LOG_FILE" ## Réalise un apt update && upgrade l'ajoute au fichier log

# === 2. PACKAGE INSTALLATION ===
if [ -f "$PACKAGE_LIST" ]; then ## Vérifie la présence des paquet listé dans package_list
  log "Reading package list from $PACKAGE_LIST"
  while IFS= read -r pkg || [[ -n "$pkg" ]]; do ## Evite les coupure de ligne / lit le contenu du fichier
    [[ -z "$pkg" || "$pkg" =~ ^# ]] && continue ## saute les lignes vide et les ligne commenté
    check_and_install "$pkg" ## Appelle la fonction check_and_install
  done < "$PACKAGE_LIST"
else
  log "Package list file $PACKAGE_LIST not found. Skipping package installation." ## Si fichier non trouvé skip la section
fi

# === 3. UPDATE MOTD ===
if [ -f "$CONFIG_DIR/motd.txt" ]; then ## vérifie la présence du motd.txt
  cp "$CONFIG_DIR/motd.txt" /etc/motd ## copy motd.txt dans MOTD
  log "MOTD updated." ## Enregistre le log
else
  log "motd.txt not found." ## Indique l'absence du fichier motd.txt
fi

# === 4. CUSTOM .bashrc ===
if [ -f "$CONFIG_DIR/bashrc.append" ]; then
  cat "$CONFIG_DIR/bashrc.append" >> "$USER_HOME/.bashrc"
  chown "$USERNAME:$USERNAME" "$USER_HOME/.bashrc"
  log ".bashrc customized."
else
  log "bashrc.append not found."
fi

# === 5. CUSTOM .nanorc ===
if [ -f "$CONFIG_DIR/nanorc.append" ]; then
  cat "$CONFIG_DIR/nanorc.append" >> "$USER_HOME/.nanorc"
  chown "$USERNAME:$USERNAME" "$USER_HOME/.nanorc"
  log ".nanorc customized."
else
  log "nanorc.append not found."
fi

# === 6. ADD SSH PUBLIC KEY ===
if ask_yes_no "Would you like to add a public SSH key?"; then
  read -p "Paste your public SSH key: " ssh_key
  mkdir -p "$USER_HOME/.ssh"
  echo "$ssh_key" >> "$USER_HOME/.ssh/authorized_keys"
  chown -R "$USERNAME:$USERNAME" "$USER_HOME/.ssh"
  chmod 700 "$USER_HOME/.ssh"
  chmod 600 "$USER_HOME/.ssh/authorized_keys"
  log "SSH public key added."
fi

# === 7. SSH CONFIGURATION: KEY AUTH ONLY ===
if [ -f /etc/ssh/sshd_config ]; then
  sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
  sed -i 's/^#\?ChallengeResponseAuthentication.*/ChallengeResponseAuthentication no/' /etc/ssh/sshd_config
  sed -i 's/^#\?PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config
  systemctl restart ssh
  log "SSH configured to accept key-based authentication only."
else
  log "sshd_config file not found."
fi

log "Post-installation script completed."

exit 0