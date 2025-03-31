#!/bin/bash

# === VARIABLES ===       Introduction des variables
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")    # Récupére la date + heure
LOG_DIR="./logs"
LOG_FILE="$LOG_DIR/postinstall_$TIMESTAMP.log"  # Création d'un fichier de log unique avec date + heure
CONFIG_DIR="./config"
PACKAGE_LIST="./lists/packages.txt"
USERNAME=$(logname)   # Récupère l'user qui a lancé le script
USER_HOME="/home/$USERNAME"

# === FUNCTIONS ===   Afficher un message avec la date + heure dans la console et le fichier de log
log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

check_and_install() {   # Vérifie que le paquet est déjà installé et l'installe dans le cas contraire
  local pkg=$1
  if dpkg -s "$pkg" &>/dev/null; then
    log "$pkg is already installed."   # Message de log indiquant que le paquet est déjà installé
  else
    log "Installing $pkg..."   # Message de log indiquant l'installation du paquet
    apt install -y "$pkg" &>>"$LOG_FILE"
    if [ $? -eq 0 ]; then   # Si la commande retourne 0, message de log indiqant que l'installation est réussi
      log "$pkg successfully installed."
    else
      log "Failed to install $pkg."     # Si la commande ne retourne pas 0, message de log indiqant que l'installation a échoué
    fi
  fi
}

ask_yes_no() {    # Pose une question à l'user avec comme réponse Oui ou Non
  read -p "$1 [y/N]: " answer
  case "$answer" in
    [Yy]* ) return 0 ;;
    * ) return 1 ;;
  esac
}

# === INITIAL SETUP ===
mkdir -p "$LOG_DIR"     # création du répertoire de log
touch "$LOG_FILE"     #Vérifie l'existence du fichier $LOG FILE ou de le créer s'il n'es pas présent
log "Starting post-installation script. Logged user: $USERNAME"

if [ "$EUID" -ne 0 ]; then    # Vérifie que l'user possède un compte Root
  log "This script must be run as root."
  exit 1
fi

# === 1. SYSTEM UPDATE ===
log "Updating system packages..."
apt update && apt upgrade -y &>>"$LOG_FILE"

# === 2. PACKAGE INSTALLATION ===    Installe les composants présents dans ke répertoire $PACKAGE LIST
if [ -f "$PACKAGE_LIST" ]; then
  log "Reading package list from $PACKAGE_LIST"
  while IFS= read -r pkg || [[ -n "$pkg" ]]; do
    [[ -z "$pkg" || "$pkg" =~ ^# ]] && continue
    check_and_install "$pkg"
  done < "$PACKAGE_LIST"
else
  log "Package list file $PACKAGE_LIST not found. Skipping package installation."
fi

# === 3. UPDATE MOTD ===    # Met à jour le message d'accueil pour la connexion des users
if [ -f "$CONFIG_DIR/motd.txt" ]; then
  cp "$CONFIG_DIR/motd.txt" /etc/motd
  log "MOTD updated."
else
  log "motd.txt not found."
fi

# === 4. CUSTOM .bashrc ===   # Personnalise le Bash des users
if [ -f "$CONFIG_DIR/bashrc.append" ]; then
  cat "$CONFIG_DIR/bashrc.append" >> "$USER_HOME/.bashrc"
  chown "$USERNAME:$USERNAME" "$USER_HOME/.bashrc"
  log ".bashrc customized."
else
  log "bashrc.append not found."
fi

# === 5. CUSTOM .nanorc ===    Personnalise l'éditeur de texte
if [ -f "$CONFIG_DIR/nanorc.append" ]; then
  cat "$CONFIG_DIR/nanorc.append" >> "$USER_HOME/.nanorc"
  chown "$USERNAME:$USERNAME" "$USER_HOME/.nanorc"
  log ".nanorc customized."
else
  log "nanorc.append not found."
fi

# === 6. ADD SSH PUBLIC KEY ===   Donne la possibilité d'ajouter des clés SSH Public à l'user
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